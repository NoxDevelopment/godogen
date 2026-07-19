extends Node
## res://scripts/play_session.gd
## PlaySession (autoload) — the SINGLE bridge between the UI and the computed
## nox_if_engine. It OWNS the active runner (a one-off OR a campaign), the loaded
## ruleset, and the flow between them; the play scene talks ONLY to this
## interface and never touches the engine directly. This is the if-engine
## analogue of the ff-gamebook SessionState: the one routing point for passages,
## choices, dice and save/load — and the seam a future AI/DM/multiplayer layer
## would intercept (it intercepts the engine's IFState, never the rule engine).
##
## Everything here is 100% COMPUTED — no LLM, no networking. The optional AiDm
## autoload is consulted only behind `if AiDm.enabled` guards (shipped false), so
## the game plays identically with or without it.
##
## Content is REUSED from the vendored engine data (zero duplication): the
## Thornwood Crypt scenario, the Goblin Toll one-off, and the Crown of Embers
## campaign all ship inside addons/nox_if_engine/data/. The one-off scenario is
## wrapped into an IFOneOff in code so the rich standalone scenario reuses the
## IFOneOffRunner path with no JSON copy.
##
## Play loop the scene runs:
##   PlaySession.begin_oneoff_scenario(SCENARIO_THORNWOOD)   # or begin_campaign(...)
##   render(current_passage(), available_choices(), sheet_view())
##   var report := PlaySession.choose(choice_id)             # applies effects + rolls
##   for roll in report.rolls: show_dice_tray(roll)          # surface the resolver
##   render(...)  ;  handle report.ended / report.between_modules

signal session_reset()
signal passage_changed(passage: Dictionary)
signal sheet_changed()
signal check_resolved(result: Dictionary)
signal adventure_ended(ending: Dictionary, outcome: String)
signal module_boundary(last_ending: Dictionary, campaign_ended: bool)

const RULESETS_DIR := "res://addons/nox_if_engine/data/rulesets/"
const SAVE_PATH := "user://gamebook_if_save.json"

# Sample content, reused verbatim from the vendored engine data.
const SCENARIO_THORNWOOD := "res://addons/nox_if_engine/data/scenarios/thornwood-crypt.json"
const ONEOFF_GOBLIN := "res://addons/nox_if_engine/data/adventures/goblin-toll.oneoff.json"
const CAMPAIGN_CROWN := "res://addons/nox_if_engine/data/campaigns/crown-of-embers.campaign.json"

## "" | "oneoff" | "campaign"
var mode: String = ""
var ruleset: IFRuleset

var oneoff: IFOneOff
var oneoff_runner: IFOneOffRunner

var campaign: IFCampaign
var campaign_runner: IFCampaignRunner

## How to rebuild THIS session's content on load (content is not in the engine
## save). Written into the save file next to the IFSaveGame payload.
var content_descriptor: Dictionary = {}


# --- ruleset loading --------------------------------------------------------


## Load a ruleset by its id from the vendored builtins (ff-2d6 / srd-d20 / pbta /
## nox-2d10). A game with its own custom ruleset would point this elsewhere.
func load_ruleset(ruleset_id: String) -> IFRuleset:
	var path := RULESETS_DIR + ruleset_id + ".json"
	var rs := IFRuleset.from_file(path)
	if rs.id == "":
		push_error("PlaySession: could not load ruleset '%s' (%s)" % [ruleset_id, path])
	return rs


# --- one-off (IFOneOffRunner) ------------------------------------------------


## Start a one-off from a standalone SCENARIO file (e.g. Thornwood Crypt). The
## scenario is wrapped into an IFOneOff in code so the IFOneOffRunner path drives
## it with no data duplication. Deterministic for a fixed seed.
func begin_oneoff_scenario(scenario_path: String, seed: int = 0) -> bool:
	var scen := IFScenario.from_file(scenario_path)
	if scen.id == "":
		return false
	var o := _wrap_scenario_oneoff(scen, seed)
	content_descriptor = {"kind": "oneoff-scenario", "scenario": scenario_path, "seed": seed}
	return _begin_oneoff(o)


## Start a one-off from an adventure DATA file (e.g. the Goblin Toll one-off,
## which references a module + a character). Proves the full data-driven path.
func begin_oneoff_file(oneoff_path: String) -> bool:
	var o := IFOneOff.from_file(oneoff_path)
	if o.id == "":
		return false
	content_descriptor = {"kind": "oneoff-file", "path": oneoff_path}
	return _begin_oneoff(o)


func _wrap_scenario_oneoff(scen: IFScenario, seed: int) -> IFOneOff:
	var module_dict := {
		"id": scen.id, "name": scen.name, "kind": "module",
		"ruleset": scen.ruleset_id,
		"entry": {"start": scen.start},
		"exit": {"default": {"outcome": "complete"}},
		"scenario": scen.raw(),
	}
	var oneoff_dict := {
		"id": scen.id + "-oneoff", "name": scen.name, "type": "oneoff",
		"ruleset": scen.ruleset_id, "seed": seed, "module": module_dict,
	}
	return IFOneOff.new(oneoff_dict)


func _begin_oneoff(o: IFOneOff) -> bool:
	mode = "oneoff"
	oneoff = o
	campaign = null
	campaign_runner = null
	ruleset = load_ruleset(o.ruleset_id)
	oneoff_runner = IFOneOffRunner.new()
	oneoff_runner.begin(o, ruleset)
	session_reset.emit()
	_emit_current()
	return true


# --- campaign (IFCampaignRunner) --------------------------------------------


## Begin a multi-module campaign (Crown of Embers). Long-term world state + a
## carried roster progress module-to-module with save/resume between them.
func begin_campaign_file(campaign_path: String) -> bool:
	mode = "campaign"
	campaign = IFCampaign.from_file(campaign_path)
	if campaign.id == "":
		return false
	ruleset = load_ruleset(campaign.ruleset_id)
	oneoff = null
	oneoff_runner = null
	campaign_runner = IFCampaignRunner.new()
	var ok := campaign_runner.begin(campaign, ruleset)
	content_descriptor = {"kind": "campaign-file", "path": campaign_path}
	session_reset.emit()
	_emit_current()
	return ok


## Between modules: start the next module's session. Returns false if not
## currently between modules (or the campaign has ended).
func advance_campaign_module() -> bool:
	if mode != "campaign" or campaign_runner == null:
		return false
	if not campaign_runner.is_between_modules():
		return false
	var ok := campaign_runner.start_current_module()
	_emit_current()
	return ok


# --- reading the live session (what the UI renders) --------------------------


func _active_runner() -> IFRunner:
	if mode == "oneoff" and oneoff_runner != null:
		return oneoff_runner.runner
	if mode == "campaign" and campaign_runner != null:
		return campaign_runner.runner
	return null


func active_state() -> IFState:
	var r := _active_runner()
	return r.state if r != null else null


## The current passage dict ({id, title, text, choices, ending?}), or {} when
## there is no live session (e.g. a campaign between modules).
func current_passage() -> Dictionary:
	var r := _active_runner()
	if r == null or r.state == null or r.state.current_passage == "":
		return {}
	return r.current_passage()


## The choices whose conditions currently HOLD — already gated by the engine.
## AiDm.review_choices is a documented, guarded pass-through (inert by default).
func available_choices() -> Array:
	var choices: Array = []
	if mode == "oneoff" and oneoff_runner != null and not oneoff_runner.is_ended():
		choices = oneoff_runner.available_choices()
	elif mode == "campaign" and campaign_runner != null:
		choices = campaign_runner.available_choices()
	if AiDm.enabled:
		choices = AiDm.review_choices(choices, active_state())
	return choices


## Whether a specific choice id is offered right now (its conditions hold) — used
## by the play scene to visibly mark gated choices, and by tests.
func is_choice_available(choice_id: String) -> bool:
	for ch in available_choices():
		if str(ch.get("id", "")) == choice_id:
			return true
	return false


## A ruleset-agnostic view of the adventure sheet for the HUD, built from the
## CHOSEN ruleset's sheetTemplate (attributes + resources) + item.* inventory.
## Works unchanged for ff-2d6, srd-d20, pbta or any custom ruleset.
func sheet_view() -> Dictionary:
	var out := {"attributes": [], "resources": [], "inventory": {}}
	var state := active_state()
	if state == null or ruleset == null:
		return out
	var tmpl: Dictionary = ruleset.sheet_template
	for key in tmpl.get("attributes", ruleset.attribute_order):
		var a: Dictionary = ruleset.attributes.get(key, {})
		out["attributes"].append({
			"key": key, "label": str(a.get("label", key)),
			"value": state.get_attr(str(key)),
			"max": (a.get("max") if a.has("max") else null),
		})
	for key in tmpl.get("resources", ruleset.resource_order):
		var r: Dictionary = ruleset.resources.get(key, {})
		out["resources"].append({
			"key": key, "label": str(r.get("label", key)),
			"value": state.get_resource(str(key)),
			"max": (state.resource_max.get(key) if state.resource_max.has(key) else null),
		})
	if bool(tmpl.get("inventory", true)):
		out["inventory"] = state.inventory()
	return out


# --- taking a choice (the turn) ---------------------------------------------


## Apply a choice: the engine routes it (effects, an optional inline/entry check,
## the gate conditions were already enforced) and this returns a TURN REPORT the
## scene sequences — any dice rolls surfaced this turn, the passage arrived at,
## and the terminal / module-boundary status. Signals fire too for reactive HUDs.
func choose(choice_id: String) -> Dictionary:
	var state := active_state()
	var rolls_before := state.roll_log.size() if state != null else 0

	if mode == "oneoff" and oneoff_runner != null:
		oneoff_runner.choose(choice_id)
	elif mode == "campaign" and campaign_runner != null:
		campaign_runner.choose(choice_id)
	else:
		push_warning("PlaySession.choose('%s') with no active session" % choice_id)
		return {}

	# Surface any dice checks resolved during this turn (passage-entry checks
	# auto-resolve inside the engine, so a single choose can produce 0..N rolls).
	var rolls: Array = []
	if state != null:
		for i in range(rolls_before, state.roll_log.size()):
			var roll: Dictionary = state.roll_log[i]
			if AiDm.enabled:
				roll = roll.duplicate(true)
				roll["ai_gloss"] = AiDm.gloss_roll(roll)
			rolls.append(roll)
			check_resolved.emit(roll)

	var report := {"rolls": rolls, "passage": current_passage()}
	sheet_changed.emit()
	_emit_passage()

	if mode == "oneoff":
		report["ended"] = oneoff_runner.is_ended()
		report["ending"] = oneoff_runner.ending()
		report["outcome"] = oneoff_runner.outcome()
		report["between_modules"] = false
		report["campaign_ended"] = report["ended"]
		if report["ended"]:
			adventure_ended.emit(report["ending"], report["outcome"])
	else:
		var module_ended: bool = not campaign_runner.is_session_active()
		report["module_ended"] = module_ended
		report["between_modules"] = campaign_runner.is_between_modules()
		report["campaign_ended"] = campaign_runner.is_campaign_ended()
		report["campaign_status"] = campaign_runner.campaign_status()
		report["last_module_id"] = campaign_runner.last_module_id
		report["ending"] = campaign_runner.last_ending
		report["outcome"] = campaign_runner.last_outcome
		report["ended"] = report["campaign_ended"]
		if module_ended:
			module_boundary.emit(campaign_runner.last_ending, campaign_runner.is_campaign_ended())
		if report["campaign_ended"]:
			adventure_ended.emit(campaign_runner.last_ending, campaign_runner.last_outcome)
	return report


# --- terminal / status accessors --------------------------------------------


func is_ended() -> bool:
	if mode == "oneoff":
		return oneoff_runner != null and oneoff_runner.is_ended()
	if mode == "campaign":
		return campaign_runner != null and campaign_runner.is_campaign_ended()
	return false


func is_between_modules() -> bool:
	return mode == "campaign" and campaign_runner != null and campaign_runner.is_between_modules()


func ending() -> Dictionary:
	if mode == "oneoff" and oneoff_runner != null:
		return oneoff_runner.ending()
	if mode == "campaign" and campaign_runner != null:
		return campaign_runner.last_ending
	return {}


func outcome() -> String:
	if mode == "oneoff" and oneoff_runner != null:
		return oneoff_runner.outcome()
	if mode == "campaign" and campaign_runner != null:
		return campaign_runner.last_outcome
	return ""


func adventure_title() -> String:
	if mode == "oneoff" and oneoff != null:
		return oneoff.name
	if mode == "campaign" and campaign != null:
		return campaign.name
	return "Adventure"


# --- save / load (IFSaveGame) -----------------------------------------------


## Save the live adventure to user://. The engine save carries only MUTABLE state
## (long-term campaign store + short-term session snapshot); we bundle a content
## DESCRIPTOR so load() can rebuild the scenario/module/campaign it was taken
## against. Works for a one-off (short-term only) and a campaign (both halves).
func save_game() -> bool:
	var sg: IFSaveGame
	if mode == "campaign" and campaign_runner != null:
		sg = campaign_runner.save()
	elif mode == "oneoff" and oneoff_runner != null:
		sg = IFSaveGame.new("oneoff")
		sg.long_term = null
		if not oneoff_runner.is_ended():
			sg.set_short_term(oneoff_runner.runner.snapshot(), oneoff.module.id)
		else:
			sg.short_term = null
	else:
		return false
	sg.saved_at = Time.get_datetime_string_from_system()
	var payload := {"descriptor": content_descriptor, "save": sg.to_dict()}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("PlaySession: cannot open save at %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(payload, "  ", true, true))
	f.close()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Load the saved adventure: rebuild its content from the descriptor, then
## restore the engine state (campaign: resume both halves; one-off: restore the
## inner runner byte-for-byte from the short-term snapshot).
func load_game() -> bool:
	if not has_save():
		return false
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PlaySession: corrupt save at %s" % SAVE_PATH)
		return false
	var payload: Dictionary = parsed
	var descriptor: Dictionary = payload.get("descriptor", {})
	var sg := IFSaveGame.from_dict(payload.get("save", {}))
	content_descriptor = descriptor

	match str(descriptor.get("kind", "")):
		"oneoff-scenario":
			var scen := IFScenario.from_file(str(descriptor.get("scenario", "")))
			var o := _wrap_scenario_oneoff(scen, int(descriptor.get("seed", 0)))
			return _restore_oneoff(o, sg)
		"oneoff-file":
			var o := IFOneOff.from_file(str(descriptor.get("path", "")))
			return _restore_oneoff(o, sg)
		"campaign-file":
			campaign = IFCampaign.from_file(str(descriptor.get("path", "")))
			ruleset = load_ruleset(campaign.ruleset_id)
			oneoff = null
			oneoff_runner = null
			campaign_runner = IFCampaignRunner.new()
			campaign_runner.resume(sg, campaign, ruleset)
			mode = "campaign"
			session_reset.emit()
			_emit_current()
			return true
		_:
			push_error("PlaySession: unknown save descriptor '%s'" % descriptor.get("kind"))
			return false


## Rebuild a one-off runner and restore its inner IFRunner from a short-term
## snapshot (the engine's byte-for-byte resume seam). Uses only public API of the
## vendored addon — the engine source is not modified.
func _restore_oneoff(o: IFOneOff, sg: IFSaveGame) -> bool:
	mode = "oneoff"
	oneoff = o
	campaign = null
	campaign_runner = null
	ruleset = load_ruleset(o.ruleset_id)
	oneoff_runner = IFOneOffRunner.new()
	oneoff_runner.oneoff = o
	oneoff_runner.ruleset = ruleset
	oneoff_runner.runner = IFRunner.new()
	var scenario := o.module.scenario
	scenario.start = o.module.start_passage()
	if sg.has_short_term():
		oneoff_runner.runner.restore(ruleset, scenario, sg.session_snapshot())
	else:
		# Ended save (or none): replay from the start deterministically.
		oneoff_runner.runner.load(ruleset, scenario, o.seed)
		oneoff_runner.runner.start()
	session_reset.emit()
	_emit_current()
	return true


func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# --- signal helpers ---------------------------------------------------------


func _emit_current() -> void:
	_emit_passage()
	sheet_changed.emit()


func _emit_passage() -> void:
	passage_changed.emit(current_passage())
