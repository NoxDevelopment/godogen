extends Node
## res://scripts/game_manager.gd
## Global game-state singleton (autoload "GameManager"). It OWNS one CosmicEngine —
## the pure, seedable CO-OP cosmic-horror rules — and adds the NoxDev template ABI
## on top: it lives in the "game_manager" + "persistent" groups and implements
## save_data()/load_data(), so godotsmith's save_system persists the WHOLE game.
##
## It is ALSO the CO-OP TURN DISPATCHER. All investigators are ONE team; each seat
## carries a ControllerKind. In the ACTION phase the dispatcher walks the current
## actor and asks "whose turn, what kind":
##   * AI_AUTOPILOT seats auto-resolve each action via the engine's co-op heuristic.
##   * HUMAN_LOCAL seats BLOCK — the dispatcher stops and waits for the board to
##     forward the local human's chosen action.
## The ENCOUNTER and MYTHOS phases are fully AUTOMATED inside the engine (they run
## when the action phase completes), so the dispatcher only ever manages who takes
## ACTION-phase actions. For LOCAL HOTSEAT (more than one HUMAN_LOCAL seat) it
## raises a "pass the device" hand-off before every human turn after the first.
##
## Adding AI_LLM (a local LLM picks a legal action) or REMOTE (a networked action
## arrives) is a NEW match case in _advance_dispatch() + one hook — NOT a rewrite.
## The default branch fails LOUD on any unhandled/unsupported kind (never silently
## passes). All rules stay in CosmicEngine; the board only reads state + forwards a
## click; this file only decides WHO acts next.

signal changed  ## any state change — the board redraws on this.
signal handoff_requested(seat: int, seat_name: String)  ## hotseat: prompt the pass-the-device banner.

var engine: CosmicEngine

## Dispatcher state (transient — derived from the engine cursor, not persisted).
var awaiting_input := false     ## BLOCKED on a local human seat, input open.
var pending_handoff := false    ## a pass-the-device banner must be acknowledged first.
var _first_human_seen := false  ## the game's FIRST human turn shows no banner.
var _dispatching := false       ## re-entrancy guard for the dispatch loop.


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = CosmicEngine.new()


# =====================================================================
#  Game setup — presets + custom seat lineups
# =====================================================================

## Start a fresh game with the DEFAULT preset (seat 0 human, the rest autopilot
## teammates). investigator_count 1..4, difficulty "normal"/"harsh".
func new_game(seed_value: int = 0, investigator_count: int = 4, difficulty: String = "normal") -> void:
	engine.setup(seed_value, investigator_count, difficulty)
	_restart_dispatch()


## Start a fresh game with a CUSTOM seat lineup. `kinds` is one
## CosmicEngine.ControllerKind per seat; `names` are optional. Supports all-autopilot
## (co-op AI buddies), 1-human + autopilot, and multi-human HOTSEAT lineups.
func configure_game(kinds: Array, names: Array = [], seed_value: int = 0, difficulty: String = "normal") -> void:
	engine.setup(seed_value, kinds.size(), difficulty)
	engine.configure_seats(kinds, names)
	_restart_dispatch()


## Convenience preset: an all-AI co-op run of `count` autopilot investigators — the
## "watch the AI buddies play" mode (and the shape the WIN/LOSS probes drive).
func new_all_autopilot_game(count: int = 4, seed_value: int = 0, difficulty: String = "normal") -> void:
	var kinds: Array = []
	for i in clampi(count, 1, 4):
		kinds.append(CosmicEngine.ControllerKind.AI_AUTOPILOT)
	configure_game(kinds, [], seed_value, difficulty)


## Convenience preset: a local hotseat of `human_count` humans + `ai_count`
## autopilot investigators (pass-and-play), clamped to 1..4 total.
func new_hotseat_game(human_count: int, ai_count: int, seed_value: int = 0, difficulty: String = "normal") -> void:
	var total := clampi(human_count + ai_count, 1, 4)
	var humans := clampi(human_count, 1, total)
	var kinds: Array = []
	for i in total:
		kinds.append(CosmicEngine.ControllerKind.HUMAN_LOCAL if i < humans else CosmicEngine.ControllerKind.AI_AUTOPILOT)
	configure_game(kinds, [], seed_value, difficulty)


func reset() -> void:
	new_game(0, engine.num_investigators if engine != null else 4, engine.difficulty if engine != null else "normal")


func _restart_dispatch() -> void:
	awaiting_input = false
	pending_handoff = false
	_first_human_seen = false
	_advance_dispatch()
	changed.emit()


# =====================================================================
#  The CO-OP TURN DISPATCHER — the play-mode seam
# =====================================================================

## Walk the ACTION-phase actor from the engine cursor: auto-resolve every autopilot
## seat's actions, and STOP at a local-human seat (blocking for UI input), raising a
## pass-the-device hand-off first when this is a hotseat and not the game's first
## human turn. The encounter/mythos phases run automatically inside the engine when
## the action phase completes, so this loop only ever advances action-phase actors.
##
## The default `_:` branch fails LOUD on any unwired/unsupported kind (AI_LLM,
## REMOTE, or a corrupt value) — it can never silently pass. Those two kinds are
## the documented extension points: each drops in as one more `case` here.
func _advance_dispatch() -> void:
	if _dispatching:
		return
	_dispatching = true
	var guard := 0
	while not engine.game_over and guard < 100000:
		guard += 1
		if engine.phase != "action":
			# Should not happen (the engine auto-runs encounter/mythos), but never spin.
			break
		var seat := engine.active_index
		var kind := engine.controller_of(seat)
		match kind:
			CosmicEngine.ControllerKind.HUMAN_LOCAL:
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
			CosmicEngine.ControllerKind.AI_AUTOPILOT:
				var acted: Dictionary = engine.autopilot_take_action(seat)
				if acted.is_empty():
					# No legal action for a living seat should be impossible; guard anyway.
					push_error("GameManager: autopilot produced no action at seat %d." % seat)
					break
			_:
				# AI_LLM / REMOTE / corrupt value: fail loud, never silently pass. This
				# is where an LLM-assist case or a network transport case drops in
				# (see CosmicEngine.ControllerKind). Add the case ABOVE.
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

## The CURRENT local human seat takes its single action. Rejected (returns false,
## state unchanged) if it is not a human seat's turn, if a hand-off banner is still
## pending, or if the action is illegal. On success the engine advances the actor
## (and, when the action phase ends, auto-resolves encounter + mythos), then the
## dispatcher resolves every following autopilot seat until the next human / end.
func submit_action(action: Dictionary) -> bool:
	if engine.game_over:
		return false
	var seat := engine.active_index
	if not engine.is_human_seat(seat):
		return false
	if pending_handoff or not awaiting_input:
		return false
	if not engine.apply_action(seat, action):
		return false
	awaiting_input = false
	_advance_dispatch()
	changed.emit()
	return true


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
	return not engine.game_over and engine.phase == "action" and engine.is_human_seat(engine.active_index)


## True when the board may accept the active human seat's input RIGHT NOW.
func can_accept_input() -> bool:
	return is_human_turn() and awaiting_input and not pending_handoff


func active_seat() -> int:
	return engine.active_index


# =====================================================================
#  Persistence — the WHOLE game round-trips through save_system
# =====================================================================

func save_data() -> Dictionary:
	return {"engine": engine.to_dict()}


func load_data(data: Dictionary) -> void:
	if data.has("engine"):
		engine.from_dict(data["engine"] as Dictionary)
	_first_human_seen = true
	awaiting_input = false
	pending_handoff = false
	_advance_dispatch()
	changed.emit()
