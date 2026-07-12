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
## DM-seat hooks (dm_push_passage / dm_override_roll) are documented no-ops:
## the reserved entry points for a human DM seat once multiplayer exists.

signal session_reset
signal passage_changed(passage_id: String)
signal choice_made(next_id: String, choice_text: String)
signal roll_resolved(result: Dictionary)

## The passage the party is on ("" before the book opens).
var current_passage := ""
## Every passage entered this session, in order (the party's trail).
var passage_history: Array[String] = []
## Every dice result this session (see Dice.roll_test for the shape).
var roll_log: Array[Dictionary] = []


func _enter_tree() -> void:
	add_to_group(&"persistent")


## Start a fresh session (new adventure). The title screen calls this.
func reset_session() -> void:
	current_passage = ""
	passage_history.clear()
	roll_log.clear()
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


# --- DM seat (reserved for multiplayer) -------------------------------------


## DM seat: force the party's book to a passage. No-op by design in the
## single-player core — returns false ("not handled"). The future ENet layer
## implements it as host-authoritative advance_passage + broadcast.
func dm_push_passage(_passage_id: String) -> bool:
	return false


## DM seat: replace the next/last dice result (fudge the roll). No-op by
## design in the single-player core — returns false ("not handled"). The
## future ENet layer implements it as a host-side override consumed by roll().
func dm_override_roll(_result: Dictionary) -> bool:
	return false


## "persistent" group contract (see templates ABI).
func save_data() -> Dictionary:
	return {
		"current_passage": current_passage,
		"passage_history": passage_history.duplicate(),
		"roll_log": roll_log.duplicate(true),
	}


func load_data(data: Dictionary) -> void:
	current_passage = str(data.get("current_passage", ""))
	passage_history.assign(data.get("passage_history", []))
	roll_log.assign(data.get("roll_log", []))
	if not current_passage.is_empty():
		passage_changed.emit(current_passage)


func _record_roll() -> void:
	roll_log.append(Dice.last_result.duplicate(true))
	roll_resolved.emit(Dice.last_result)
