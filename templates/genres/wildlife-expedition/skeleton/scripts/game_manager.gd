extends Node
## res://scripts/game_manager.gd
## Global game-state singleton (autoload "GameManager"). It OWNS one WildlifeEngine —
## the pure, seedable nature-exploration + wildlife-documentation rules — and adds the
## NoxDev template ABI on top: it lives in the "game_manager" + "persistent" groups and
## implements save_data()/load_data(), so godotsmith's save_system persists the WHOLE
## game (banks, journals, hands, gear, pawns, trail, decks, goals, cursor, RNG state).
##
## It is ALSO the TURN DISPATCHER for the play-mode matrix. Every seat carries a
## ControllerKind (WildlifeEngine.ControllerKind). The dispatcher walks the turn cursor
## and, per seat, asks "whose turn, what kind":
##   * AI_HEURISTIC seats auto-resolve via ai_choose() + apply_action().
##   * HUMAN_LOCAL seats BLOCK — the dispatcher stops and waits for board.gd to forward
##     the local human's chosen action.
## For LOCAL HOTSEAT (more than one HUMAN_LOCAL seat, pass-and-play on one machine) it
## raises a "pass the device" hand-off before every human turn AFTER the first.
##
## Adding AI_LLM (a local LLM picks a legal action) or REMOTE (a networked action
## arrives) is a NEW match case in _advance_dispatch() + one hook — NOT a rewrite. The
## default branch fails LOUD on any unhandled/unsupported kind (never silently passes).
## All rules stay in WildlifeEngine; board.gd only reads state + forwards a click; this
## file only decides WHO acts next.

signal changed  ## any state change — the board redraws on this.
signal handoff_requested(seat: int, seat_name: String)  ## hotseat: prompt the pass-the-device banner.

var engine: WildlifeEngine

## Dispatcher state (transient — derived from the engine cursor, not persisted).
var awaiting_input := false     ## BLOCKED on a local human seat, input open.
var pending_handoff := false    ## a pass-the-device banner must be acknowledged first.
var _first_human_seen := false  ## the game's FIRST human turn shows no banner.
var _dispatching := false       ## re-entrancy guard for the dispatch loop.


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = WildlifeEngine.new()


# =====================================================================
#  Game setup — presets + custom seat lineups
# =====================================================================

## Start a fresh game with the DEFAULT preset (seat 0 human, the rest heuristic AI).
## player_count 2..5.
func new_game(seed_value: int = 0, player_count: int = 4) -> void:
	engine.setup(seed_value, player_count)
	_restart_dispatch()


## Start a fresh game with a CUSTOM seat lineup. `kinds` is one
## WildlifeEngine.ControllerKind per seat; `names` are optional. Supports all-AI,
## 1-human-vs-AI, and multi-human HOTSEAT lineups.
func configure_game(kinds: Array, names: Array = [], seed_value: int = 0) -> void:
	engine.setup(seed_value, kinds.size())
	engine.configure_seats(kinds, names)
	_restart_dispatch()


## Convenience preset: an all-AI game of `count` heuristic explorers — the "watch the
## AI play" mode (and the shape the full-game probe drives).
func new_all_ai_game(count: int = 4, seed_value: int = 0) -> void:
	var kinds: Array = []
	for i in clampi(count, 2, 5):
		kinds.append(WildlifeEngine.ControllerKind.AI_HEURISTIC)
	configure_game(kinds, [], seed_value)


## Convenience preset: a local hotseat of `human_count` humans + `ai_count` heuristic
## AIs (pass-and-play), clamped to 2..5 total.
func new_hotseat_game(human_count: int, ai_count: int, seed_value: int = 0) -> void:
	var total := clampi(human_count + ai_count, 2, 5)
	var humans := clampi(human_count, 1, total)
	var kinds: Array = []
	var names: Array = []
	for i in total:
		if i < humans:
			kinds.append(WildlifeEngine.ControllerKind.HUMAN_LOCAL)
			names.append("P%d Human" % (i + 1))
		else:
			kinds.append(WildlifeEngine.ControllerKind.AI_HEURISTIC)
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

## Walk seats from the current cursor: auto-resolve every AI seat, and STOP at a
## local-human seat (blocking for UI input), raising a pass-the-device hand-off first
## when this is a hotseat and not the game's first human turn.
##
## The default `_:` branch fails LOUD on any unwired/unsupported kind (AI_LLM, REMOTE,
## or a corrupt value) — it can never silently pass. Those two kinds are the documented
## extension points: each drops in as one more `case` here + one hook.
func _advance_dispatch() -> void:
	if _dispatching:
		return
	_dispatching = true
	var guard := 0
	while not engine.game_over and guard < 100000:
		guard += 1
		var seat := engine.current
		var kind := engine.controller_of(seat)
		match kind:
			WildlifeEngine.ControllerKind.HUMAN_LOCAL:
				if engine.human_seat_count() > 1 and _first_human_seen:
					pending_handoff = true
					awaiting_input = false
					handoff_requested.emit(seat, engine.seat_name(seat))
				else:
					pending_handoff = false
					awaiting_input = true
				_first_human_seen = true
				_dispatching = false
				changed.emit()
				return
			WildlifeEngine.ControllerKind.AI_HEURISTIC:
				engine.ai_take_turn(seat)
				engine.advance_turn()
			_:
				# AI_LLM / REMOTE / corrupt value: fail loud, never silently pass. This
				# is where an LLM-assist case or a network transport case drops in (see
				# WildlifeEngine.ControllerKind). Add the case ABOVE.
				push_error("GameManager: unhandled ControllerKind %d at seat %d — AI_LLM/REMOTE not wired." % [kind, seat])
				assert(false, "Unhandled ControllerKind %d — extension point for AI_LLM/REMOTE." % kind)
				_dispatching = false
				return
	awaiting_input = false
	_dispatching = false
	changed.emit()


# =====================================================================
#  Human input — the current local-human seat submits ONE legal action
# =====================================================================

## The CURRENT local human seat takes its single action. Rejected (returns false, state
## unchanged) if it is not a human seat's turn, if a hand-off banner is still pending,
## or if the action is illegal. On success the turn advances and the dispatcher resolves
## every following seat until the next human (or game end).
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


## Legacy alias for the classic 1-human flow.
func human_action(action: Dictionary) -> bool:
	return submit_action(action)


## The active player pressed "Ready" on the pass-the-device banner.
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


## True when the board may accept the active human seat's input RIGHT NOW.
func can_accept_input() -> bool:
	return is_human_turn() and awaiting_input and not pending_handoff


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
	# A loaded mid-game is never "before the first human turn", so a hotseat resume
	# prompts the hand-off.
	_first_human_seen = true
	awaiting_input = false
	pending_handoff = false
	_advance_dispatch()
	changed.emit()
