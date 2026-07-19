extends Node
## res://scripts/session_state.gd
## Session state (autoload "SessionState"): the SINGLE routing point for
## passage flow, choices and dice results — and, by design, the future
## multiplayer sync point. The single-player core is authoritative locally;
## when the ENet layer lands, these three methods become the RPC surface (the
## host validates + broadcasts, clients render off the signals) and nothing
## in the scenes has to change, because scenes already talk ONLY to this
## interface:
##
##   advance_passage(id)  — dialogue mutation at the top of every passage
##                          (`do SessionState.advance_passage("passage_N")`);
##                          the page listens to passage_changed to bind the
##                          passage's illustration slot.
##   choose(next_id, txt) — the response buttons' route; emits choice_made
##                          and returns the id to advance to.
##   roll(stat)           — awaits the 2d6 dice layer (Dice.test) and records
##                          the result into roll_log; roll_luck() adds the
##                          classic LUCK attrition.
##
## DM-seat hooks (dm_push_passage / dm_override_roll) are REAL DM-authority
## operations (see the "DM seat" section): the host/DM forces the book or
## fudges a roll. In single-player they are simply never called; when
## nox_netcode is injected they become the host-only RPC surface.
##
## STAGING (multiplayer "staging" input — StageWhisper-pattern, additive):
## non-DM peers do not race to click. A peer's client STAGES an intent via
## submit_staged() — the intent is buffered in `staged_actions`, NOT applied.
## The DM seat curates the buffer (reorder/discard/clear) and applies ONE
## staged action at a time via apply_staged(), which routes the chosen intent
## through the EXACT existing turn method (choose / roll / roll_luck /
## advance_passage) so every rule, effect and die runs identically to a direct
## action. The single-player core is byte-identical: a game that never calls
## submit_staged/apply_staged leaves `staged_actions` empty and plays exactly
## as before staging existed.

signal session_reset
signal passage_changed(passage_id: String)
signal choice_made(next_id: String, choice_text: String)
signal roll_resolved(result: Dictionary)
## Emitted whenever the staged-action buffer changes (submit / apply / discard
## / reorder / clear). The DM-seat review UI listens on this to re-render.
signal staged_actions_changed

## The passage the party is on ("" before the book opens).
var current_passage := ""
## Every passage entered this session, in order (the party's trail).
var passage_history: Array[String] = []
## Every dice result this session (see Dice.roll_test for the shape).
var roll_log: Array[Dictionary] = []
## The staging buffer: intents submitted by peers but NOT yet applied. Each
## element is a normalized Dictionary
##   { id:String, peer:int, kind:String, args:Dictionary, at:int }
## where `id` is a stable handle, `peer` is the submitter (0 = local/unknown),
## `kind` is one of "choose"|"roll"|"roll_luck"|"advance", `args` is the shape
## the target turn method needs, and `at` is a monotone submit-order stamp.
## Empty in single-player — the SP path never touches it.
var staged_actions: Array[Dictionary] = []
## Monotone counter backing both the stable `id` and the `at` submit-order
## stamp of staged actions. Persisted so ids stay stable across save/load.
var _stage_counter: int = 0

## The kinds submit_staged accepts, mapped to the REQUIRED arg keys that must
## be present (and String) for the intent to be well-formed. "roll_luck" needs
## no args. This is the validation contract — the same legal set the DM applies.
const _STAGED_KINDS := {
	"choose": ["next_id"],
	"roll": ["stat"],
	"roll_luck": [],
	"advance": ["passage_id"],
}


func _enter_tree() -> void:
	add_to_group(&"persistent")


## Start a fresh session (new adventure). The title screen calls this.
func reset_session() -> void:
	current_passage = ""
	passage_history.clear()
	roll_log.clear()
	# Drop any un-applied staged intents from the previous adventure. Inert in
	# single-player (the buffer is always empty there), so this leaves the SP
	# reset path byte-identical.
	clear_staged()
	session_reset.emit()


## Enter a passage. Called as the first mutation of every passage in
## dialogue/book.dialogue, so the page (and, later, every peer) always knows
## where the party is.
func advance_passage(passage_id: String) -> void:
	current_passage = passage_id
	passage_history.append(passage_id)
	passage_changed.emit(passage_id)


## Route a choice. The page's response handler calls this and advances to the
## returned id — in multiplayer this is where the host arbitrates the party
## vote / leader pick before broadcasting.
func choose(next_id: String, choice_text := "") -> String:
	choice_made.emit(next_id, choice_text)
	return next_id


## 2d6 roll-under test against the adventure sheet, recorded into roll_log.
## Dialogue awaits it: `do SessionState.roll("skill")` then
## `if Dice.last_success`. In multiplayer the host rolls, peers replay.
func roll(stat: String) -> bool:
	var ok: bool = await Dice.test(stat)
	_record_roll()
	return ok


## Test your luck (LUCK attrition applies), recorded like roll().
func roll_luck() -> bool:
	var ok: bool = await Dice.test_luck()
	_record_roll()
	return ok


# --- Staging (multiplayer "staging" input) ----------------------------------


## STAGE an intent WITHOUT applying it. This is what a non-DM peer's client
## calls: the intent is validated (kind + arg shape), normalized and appended
## to `staged_actions`, but NO turn method runs — `current_passage`, the sheet
## and the dice are untouched. Returns the new action's stable `id`, or "" if
## the kind/args are malformed (nothing is buffered on a reject). `peer` tags
## the submitter (0 = local/unknown); the host fills it from the transport.
func submit_staged(kind: String, args: Dictionary, peer: int = 0) -> String:
	if not _STAGED_KINDS.has(kind):
		push_warning("SessionState.submit_staged: unknown kind '%s'" % kind)
		return ""
	var required: Array = _STAGED_KINDS[kind]
	for key in required:
		if not args.has(key) or not (args[key] is String) or String(args[key]).is_empty():
			push_warning("SessionState.submit_staged: kind '%s' missing/blank arg '%s'" % [kind, key])
			return ""
	_stage_counter += 1
	var id := "staged_%d" % _stage_counter
	staged_actions.append({
		"id": id,
		"peer": peer,
		"kind": kind,
		"args": args.duplicate(true),
		"at": _stage_counter,
	})
	staged_actions_changed.emit()
	return id


## DM curation: drop a staged intent without applying it. Returns false if the
## id is not in the buffer.
func discard_staged(id: String) -> bool:
	var index := _staged_index(id)
	if index < 0:
		return false
	staged_actions.remove_at(index)
	staged_actions_changed.emit()
	return true


## DM curation: move a staged intent to a new position in the buffer (the DM
## decides the order intents resolve in). `to_index` is clamped into range.
## Returns false if the id is not in the buffer.
func reorder_staged(id: String, to_index: int) -> bool:
	var index := _staged_index(id)
	if index < 0:
		return false
	var action := staged_actions[index]
	staged_actions.remove_at(index)
	var dest := clampi(to_index, 0, staged_actions.size())
	staged_actions.insert(dest, action)
	staged_actions_changed.emit()
	return true


## DM APPLY: resolve ONE staged intent. The action is removed from the buffer
## and routed through the EXACT existing turn method for its kind, so every
## rule, effect and die runs identically to a direct action. Returns false if
## the id is gone or the action is no longer legal (unknown kind). Awaitable:
## the roll kinds await the dice layer, exactly like a direct roll().
func apply_staged(id: String) -> bool:
	var index := _staged_index(id)
	if index < 0:
		return false
	var action: Dictionary = staged_actions[index]
	var kind := String(action["kind"])
	if not _STAGED_KINDS.has(kind):
		return false
	# Consume from the buffer BEFORE routing, so the applied intent can never
	# be double-applied and the review UI sees it gone as the turn resolves.
	staged_actions.remove_at(index)
	staged_actions_changed.emit()
	var args: Dictionary = action["args"]
	match kind:
		"choose":
			choose(String(args["next_id"]), String(args.get("choice_text", "")))
		"advance":
			advance_passage(String(args["passage_id"]))
		"roll":
			await roll(String(args["stat"]))
		"roll_luck":
			await roll_luck()
		_:
			return false
	return true


## Empty the staging buffer (DM reset / session reset).
func clear_staged() -> void:
	if staged_actions.is_empty():
		return
	staged_actions.clear()
	staged_actions_changed.emit()


func _staged_index(id: String) -> int:
	for i in staged_actions.size():
		if String(staged_actions[i]["id"]) == id:
			return i
	return -1


# --- DM seat (host-authoritative) -------------------------------------------


## DM seat: force the party's book to a passage (a DM "push"). Routes through
## the authoritative advance_passage so the plate, history and every peer stay
## in lockstep; returns true (handled). A DM-authority operation — under
## nox_netcode it is host-only (`require_dm`); in single-player it is simply
## never invoked.
func dm_push_passage(passage_id: String) -> bool:
	advance_passage(passage_id)
	return true


## DM seat: override the last dice result (fudge the roll). Pushes the forced
## result into roll_log — replacing the most recent entry when one exists, else
## appending — and emits roll_resolved so every listener re-renders off the
## forced verdict. Returns true (handled). A DM-authority operation
## (`require_dm` under nox_netcode); never invoked in single-player.
func dm_override_roll(result: Dictionary) -> bool:
	var forced := result.duplicate(true)
	if roll_log.is_empty():
		roll_log.append(forced)
	else:
		roll_log[roll_log.size() - 1] = forced
	roll_resolved.emit(forced)
	return true


## "persistent" group contract (see templates ABI).
func save_data() -> Dictionary:
	return {
		"current_passage": current_passage,
		"passage_history": passage_history.duplicate(),
		"roll_log": roll_log.duplicate(true),
		"staged_actions": staged_actions.duplicate(true),
		"stage_counter": _stage_counter,
	}


func load_data(data: Dictionary) -> void:
	current_passage = str(data.get("current_passage", ""))
	passage_history.assign(data.get("passage_history", []))
	roll_log.assign(data.get("roll_log", []))
	# Back-compat: pre-staging saves have no staged buffer — tolerate its
	# absence (an empty buffer restores to exactly the old meaning).
	staged_actions.assign(data.get("staged_actions", []))
	_stage_counter = int(data.get("stage_counter", 0))
	if not current_passage.is_empty():
		passage_changed.emit(current_passage)


func _record_roll() -> void:
	roll_log.append(Dice.last_result.duplicate(true))
	roll_resolved.emit(Dice.last_result)
