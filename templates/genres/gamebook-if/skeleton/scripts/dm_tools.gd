extends RefCounted
class_name DmTools
## res://scripts/dm_tools.gd
## DmTools — the VALIDATED TOOL-SCHEMA ADAPTER over the computed nox_if_engine
## PlaySession (AI-DM harvest plan, slice 1: "bounded-state + validated-tools
## AI-DM"). It is the deterministic, NO-LLM layer through which a FUTURE AI-DM
## slice may read and mutate game state — and the ONLY way it may do so. Every
## state change is proposed as a typed tool call and DISPOSED by the computed
## engine: "the LLM proposes, the engine disposes." An illegal proposal can NEVER
## change state, because `choose` is gated on the engine's own legality check
## (PlaySession.is_choice_available) BEFORE anything mutates.
##
## This is purely ADDITIVE. It wraps a live PlaySession and calls only that
## bridge's public API — it re-implements no rule, owns no dice (the engine owns
## all randomness), opens no network, and does not touch the engine, the addon,
## the scenes, or the inert AiDm seam. With DmTools present but unused, the
## template plays byte-for-byte as shipped.
##
## Shape of the contract:
##   * tool_schema() -> Array   — the typed tools an AI-DM may call. EXACTLY ONE
##                                mutates state (`choose`); the rest are read-only.
##   * snapshot()     -> Dict   — the DM's player-safe grounding context.
##   * apply(name,args) -> Dict — the single validated gateway. {ok:true,...} on
##                                success; {ok:false, error:...} on any rejection,
##                                with NO mutation on rejection.
##
## Usage (deterministic, no AI needed for slice 1):
##   var dm := DmTools.new()
##   dm.bind(PlaySession)
##   var view := dm.snapshot()                                  # ground the DM
##   var r := dm.apply("choose", {"choice_id": "descend"})      # a validated turn
##   if r.ok: view = r.snapshot                                 # advance the DM

## The bound PlaySession bridge (the SINGLE routing point into the computed
## engine). Never null once bind() has run; every tool defers to it.
var _session: Object = null


## Attach this adapter to a live PlaySession (or any object exposing the same
## bridge API: current_passage/available_choices/sheet_view/is_ended/ending/
## outcome/is_choice_available/choose). Call before snapshot()/apply().
func bind(session: Object) -> void:
	_session = session


## Convenience factory: build an adapter already bound to `session`.
static func for_session(session: Object) -> DmTools:
	var dm: DmTools = DmTools.new()
	dm.bind(session)
	return dm


# --- the tool contract ------------------------------------------------------


## The typed list of tools an AI-DM may call. `choose` is the ONLY state-mutating
## tool; inspect_passage / list_choices / read_sheet / status are strictly
## read-only. Each entry: {name, mutates, args:[{name,type}], desc}.
func tool_schema() -> Array:
	var schema: Array = [
		{
			"name": "choose",
			"mutates": true,
			"args": [{"name": "choice_id", "type": "String"}],
			"desc": "Apply a turn by taking the choice `choice_id`. Rejected with error 'illegal_choice' (no mutation) unless the choice's conditions currently hold; on success the engine routes effects and auto-resolves entry dice and returns the turn report.",
		},
		{
			"name": "inspect_passage",
			"mutates": false,
			"args": [],
			"desc": "Read the current passage dictionary ({id, title, text, choices, ending?}) without changing state.",
		},
		{
			"name": "list_choices",
			"mutates": false,
			"args": [],
			"desc": "Read the LEGAL action set: the choices whose conditions currently hold (the engine-gated available choices).",
		},
		{
			"name": "read_sheet",
			"mutates": false,
			"args": [],
			"desc": "Read the ruleset-agnostic adventure sheet ({attributes, resources, inventory}) without changing state.",
		},
		{
			"name": "status",
			"mutates": false,
			"args": [],
			"desc": "Read terminal status: {ended, ending, outcome} without changing state.",
		},
	]
	return schema


## The DM's grounding context — the player-safe view of live state. Pure read:
## calling it never mutates the session.
func snapshot() -> Dictionary:
	if _session == null:
		return {}
	var view: Dictionary = {
		"passage": _session.current_passage(),
		"choices": _session.available_choices(),
		"sheet": _session.sheet_view(),
		"ended": _session.is_ended(),
		"ending": _session.ending(),
		"outcome": _session.outcome(),
	}
	return view


## The VALIDATED gateway — the one door through which a tool call touches state.
## Read-only tools return {ok:true, data:...}. `choose` is gated on the engine's
## legality check FIRST: an illegal choice returns {ok:false, error:"illegal_choice"}
## and mutates NOTHING; a legal choice is disposed by the engine and returns the
## turn report plus a fresh snapshot. Unknown tool -> {ok:false, error:"unknown_tool"}.
func apply(tool_name: String, args: Dictionary) -> Dictionary:
	if _session == null:
		return {"ok": false, "error": "no_session"}

	match tool_name:
		"inspect_passage":
			return {"ok": true, "data": _session.current_passage()}
		"list_choices":
			return {"ok": true, "data": _session.available_choices()}
		"read_sheet":
			return {"ok": true, "data": _session.sheet_view()}
		"status":
			var status: Dictionary = {
				"ended": _session.is_ended(),
				"ending": _session.ending(),
				"outcome": _session.outcome(),
			}
			return {"ok": true, "data": status}
		"choose":
			var choice_id: String = str(args.get("choice_id", ""))
			# GATE: the engine's own legality check decides. If the proposed
			# choice is not in the legal action set, reject WITHOUT mutating —
			# this is the "engine disposes" guarantee.
			if not _session.is_choice_available(choice_id):
				return {
					"ok": false,
					"error": "illegal_choice",
					"choice_id": choice_id,
					"legal": _legal_choice_ids(),
				}
			var report: Dictionary = _session.choose(choice_id)
			return {"ok": true, "report": report, "snapshot": snapshot()}
		_:
			return {"ok": false, "error": "unknown_tool", "tool": tool_name}


# --- internals --------------------------------------------------------------


## The ids of the currently-legal choices (the engine-gated available set),
## surfaced to the DM when it proposes an illegal one.
func _legal_choice_ids() -> Array:
	var ids: Array = []
	for ch in _session.available_choices():
		ids.append(str(ch.get("id", "")))
	return ids
