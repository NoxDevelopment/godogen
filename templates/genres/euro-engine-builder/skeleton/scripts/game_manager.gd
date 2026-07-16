extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one EuroEngine —
## the pure, seedable Euro engine-builder rules — and adds the NoxDev template ABI
## on top: it lives in the "game_manager" + "persistent" groups and implements
## save_data()/load_data(), so godotsmith's save_system persists the WHOLE game.
##
## It is ALSO the TURN DISPATCHER for the play-mode matrix (STAGE 1). Every seat
## carries a ControllerKind (EuroEngine.ControllerKind). The dispatcher walks the
## turn cursor and, per seat, asks "whose turn, what kind":
##   * AI_HEURISTIC seats auto-resolve via ai_choose() (the existing behaviour).
##   * HUMAN_LOCAL seats BLOCK — the dispatcher stops and waits for board.gd to
##     forward the local human's chosen action.
## For LOCAL HOTSEAT (more than one HUMAN_LOCAL seat, pass-and-play on one
## machine) it raises a "pass the device" hand-off before every human turn AFTER
## the first, so the next player is prompted to take the seat before input opens.
##
## Adding AI_LLM (an LLM provider picks a legal action) or REMOTE (a networked
## action arrives) is a NEW match case in _advance_dispatch() + one hook — NOT a
## rewrite. The default branch fails loud on any unhandled kind (never silently
## passes). All rules stay in EuroEngine; board.gd only reads state + forwards a
## click; this file only decides WHO acts next.

signal changed  ## any state change — the board redraws on this.
signal handoff_requested(seat: int, seat_name: String)  ## hotseat: prompt the pass-the-device banner.

const HUMAN := 0  ## the default-preset human seat (seat 0); kept for the classic 1-human flow.

var engine: EuroEngine

## The optional local-LLM seat provider (STAGE 2). Stateless adapter; created once.
## It is only consulted for AI_LLM seats and is fully offline-safe (heuristic
## fallback), so owning it here costs nothing until a seat opts in.
var _llm_seat: LlmSeat

## Dispatcher state (transient — derived from the engine cursor, not persisted).
var awaiting_input := false     ## the dispatcher is BLOCKED on a local human seat, input open.
var pending_handoff := false    ## a pass-the-device banner must be acknowledged before input opens.
var _first_human_seen := false  ## the game's FIRST human turn shows no banner (nobody to pass from).
var _dispatching := false       ## re-entrancy guard: an AI_LLM turn awaits async HTTP; block overlap.


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = EuroEngine.new()
	_llm_seat = LlmSeat.new()


# =====================================================================
#  Game setup — presets + custom seat lineups
# =====================================================================

## Start a fresh game with the DEFAULT preset (seat 0 human, the rest heuristic
## AI). Behaviour is unchanged from the classic 1-human-vs-AI template.
func new_game(seed_value: int = 0, player_count: int = 4) -> void:
	engine.setup(seed_value, player_count)
	_restart_dispatch()


## Start a fresh game with a CUSTOM seat lineup. `kinds` is one
## EuroEngine.ControllerKind per seat (2..5 seats); `names` are optional display
## names. Supports all-AI, 1-human-vs-AI, and multi-human HOTSEAT lineups.
func configure_game(kinds: Array, names: Array = [], seed_value: int = 0) -> void:
	engine.setup(seed_value, kinds.size())
	engine.configure_seats(kinds, names)
	_restart_dispatch()


## Convenience preset: a local hotseat of `human_count` humans followed by
## `ai_count` heuristic AIs (pass-and-play). Total seats clamp to EuroEngine's 2..5.
func new_hotseat_game(human_count: int, ai_count: int, seed_value: int = 0) -> void:
	var total := clampi(human_count + ai_count, 2, 5)
	var humans := clampi(human_count, 1, total)
	var kinds: Array = []
	var names: Array = []
	for i in total:
		if i < humans:
			kinds.append(EuroEngine.ControllerKind.HUMAN_LOCAL)
			names.append("P%d Human" % (i + 1))
		else:
			kinds.append(EuroEngine.ControllerKind.AI_HEURISTIC)
			names.append("P%d AI" % (i + 1))
	configure_game(kinds, names, seed_value)


## OPTIONAL LLM-assist preset: seat 0 is you, seat 1 is an AI_LLM opponent, the
## rest are heuristic AIs. The LLM seat only calls a provider when [euro_llm]
## `enabled` is true AND a local endpoint answers; otherwise it plays exactly like
## a heuristic AI (see LlmSeat). Nothing here touches the network by itself — this
## just assigns the seat kind; the default new_game() preset is untouched.
func new_game_with_llm(seed_value: int = 0, player_count: int = 4) -> void:
	var total := clampi(player_count, 2, 5)
	var kinds: Array = []
	var names: Array = []
	for i in total:
		if i == 0:
			kinds.append(EuroEngine.ControllerKind.HUMAN_LOCAL)
			names.append("P1 You")
		elif i == 1:
			kinds.append(EuroEngine.ControllerKind.AI_LLM)
			names.append("P2 LLM")
		else:
			kinds.append(EuroEngine.ControllerKind.AI_HEURISTIC)
			names.append("P%d AI" % (i + 1))
	configure_game(kinds, names, seed_value)


func reset() -> void:
	new_game(0, engine.num_players if engine != null else 4)


func _restart_dispatch() -> void:
	awaiting_input = false
	pending_handoff = false
	_first_human_seen = false
	_advance_dispatch()
	changed.emit()


# =====================================================================
#  The TURN DISPATCHER — the play-mode seam
# =====================================================================

## Walk seats from the current cursor: auto-resolve every AI seat (heuristic OR
## LLM), and STOP at a local-human seat (blocking for UI input), raising a
## pass-the-device hand-off first when this is a hotseat and not the game's first
## human turn.
##
## AI_LLM seats are resolved by an AWAIT on the LLM provider (LlmSeat) — the only
## async path in the dispatcher. Because a turn is always "produce one legal
## action; apply_action() validates it", the LlmSeat ALWAYS yields a legal action
## (heuristic fallback on any failure), so this stays a pure input seam: the rules,
## RNG and heuristic determinism are untouched. For any lineup WITHOUT an AI_LLM
## seat the `await` is never reached, so the loop completes synchronously exactly
## as before (byte-identical). The default `_:` branch fails LOUD on any unwired
## kind (REMOTE / corrupt value) — it can never silently pass.
##
## EXTENSION POINT: REMOTE (a networked seat) drops in as one more `case` here,
## awaiting a transport that delivers the seat's chosen action.
func _advance_dispatch() -> void:
	if _dispatching:
		return  # an AI_LLM turn is mid-await; do not overlap coroutines.
	_dispatching = true
	var guard := 0
	while not engine.game_over and guard < 4096:
		guard += 1
		var seat := engine.current
		var kind := engine.controller_of(seat)
		match kind:
			EuroEngine.ControllerKind.HUMAN_LOCAL:
				# Block for local input. In a hotseat (>1 human) raise the
				# pass-the-device banner before every human turn after the first.
				if engine.human_seat_count() > 1 and _first_human_seen:
					pending_handoff = true
					awaiting_input = false
					handoff_requested.emit(seat, engine.seat_name(seat))
				else:
					pending_handoff = false
					awaiting_input = true
				_first_human_seen = true
				_dispatching = false
				# Refresh the view now — matters when we REACH this human seat after
				# an async AI_LLM turn resolved (the original caller already returned).
				changed.emit()
				return
			EuroEngine.ControllerKind.AI_HEURISTIC:
				engine.ai_take_turn(seat)
				engine.advance_turn()
			EuroEngine.ControllerKind.AI_LLM:
				# OPTIONAL local-LLM seat. choose_action_async ALWAYS returns a
				# legal action (heuristic fallback on any provider failure) and its
				# HARD HTTP timeout guarantees this await resolves — headless runs
				# never hang. apply_action() re-validates before mutating state.
				var chosen: Dictionary = await _llm_seat.choose_action_async(engine, seat, self)
				var applied := engine.apply_action(seat, chosen["action"])
				if not applied:
					# Belt-and-braces: an unexpected reject still cannot stall the
					# game — take the guaranteed-legal heuristic action instead.
					engine.apply_action(seat, engine.ai_choose(seat))
				engine.advance_turn()
			_:
				# Unwired controller kind (REMOTE / corrupt value): fail loud, never
				# silently pass. This is where a network transport case drops in
				# (see EuroEngine.ControllerKind). Add the case ABOVE.
				push_error("GameManager: unhandled ControllerKind %d at seat %d — REMOTE not wired." % [kind, seat])
				assert(false, "Unhandled ControllerKind %d — extension point for REMOTE." % kind)
				_dispatching = false
				return
	awaiting_input = false
	_dispatching = false
	# The loop resolved to game-over or a full auto-play. Emit so the UI refreshes
	# after an ASYNC (AI_LLM) resolution, whose caller already returned. Harmless
	# for the synchronous path (an extra idempotent board refresh).
	changed.emit()


# =====================================================================
#  Human input — the current local-human seat submits ONE legal action
# =====================================================================

## The CURRENT local human seat takes its single action. Rejected (returns false,
## state unchanged) if it is not a human seat's turn, if a hand-off banner is
## still pending, or if the action is illegal. On success the turn advances and
## the dispatcher resolves every following seat until the next human (or game end).
func submit_action(action: Dictionary) -> bool:
	if engine.game_over:
		return false
	var seat := engine.current
	if not engine.is_human_seat(seat):
		return false
	if pending_handoff or not awaiting_input:
		return false
	if not engine.apply_action(seat, action):
		return false
	awaiting_input = false
	engine.advance_turn()
	_advance_dispatch()
	changed.emit()
	return true


## Legacy alias for the classic 1-human flow (board.gd used this name). Forwards
## to submit_action for the active human seat.
func human_action(action: Dictionary) -> bool:
	return submit_action(action)


## The active player pressed "Ready" on the pass-the-device banner: reveal the
## seat and open input for their turn.
func acknowledge_handoff() -> void:
	if not pending_handoff:
		return
	pending_handoff = false
	awaiting_input = true
	changed.emit()


# =====================================================================
#  Queries for the view
# =====================================================================

func is_human_turn() -> bool:
	return not engine.game_over and engine.is_human_seat(engine.current)


## True when the board may accept the active human seat's input RIGHT NOW (their
## turn, input open, no hand-off banner pending).
func can_accept_input() -> bool:
	return is_human_turn() and awaiting_input and not pending_handoff


## The seat whose turn it currently is (the active human seat when it is a human
## turn). Replaces the old hard-coded HUMAN==0 assumption for hotseat play.
func active_seat() -> int:
	return engine.current


# =====================================================================
#  Persistence — the WHOLE game round-trips through save_system
# =====================================================================

func save_data() -> Dictionary:
	return {"engine": engine.to_dict()}


func load_data(data: Dictionary) -> void:
	if data.has("engine"):
		engine.from_dict(data["engine"] as Dictionary)
	# Re-settle the dispatcher on the restored cursor. A loaded mid-game is never
	# "before the first human turn", so a hotseat resume prompts the hand-off.
	_first_human_seen = true
	awaiting_input = false
	pending_handoff = false
	_advance_dispatch()
	changed.emit()
