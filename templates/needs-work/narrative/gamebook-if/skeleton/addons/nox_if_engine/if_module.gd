class_name IFModule
extends RefCounted
## res://addons/nox_if_engine/if_module.gd
## A MODULE (spec P1) — the reusable content unit: metadata + a narrative graph +
## the ruleset it runs on + an ENTRY and an EXIT contract. A P0 IFScenario is a
## single module's content; a module wraps it and adds the two things a module
## needs to compose into bigger structures (one-offs and campaigns):
##
##   * entry — how the module BEGINS: the start passage, optional onEntry effects
##     applied to the seeded session, and optional `requires` conditions checked
##     against the CARRIED long-term state (a campaign can gate a later module on
##     progress: "only if world.vault_opened >= 1").
##   * exit  — how the module ENDS: a map from the reached scenario ending
##     (by ending id, else by ending kind, else `default`) to a campaign-level
##     OUTCOME ("complete" | "fail") plus effects applied to the carried state
##     (award a campaign var, set a world flag) and an optional explicit `goto`
##     to the next module. This is the seam that turns a pile of modules into a
##     linked campaign — the narrative graph never knows about "next module".
##
## Shape (`module.json`):
##   {
##     id, name, version?, kind:"module", meta:{...},
##     ruleset: "ff-2d6",
##     scenario: { <IFScenario shape: passages/choices/... > },
##     entry: { start?:"<passage>", onEntry?:[<effect>], requires?:[<condition>] },
##     exit:  { endings: { <endingId|kind>: <exitRule> }, default?: <exitRule> },
##     slots: [ { id, role, tier?:"any"|"sheet"|"companion", required?:bool } ]
##   }
##   exitRule = { outcome:"complete"|"fail", effects?:[<effect>], goto?:"<moduleId>" }
##
## `slots` DECLARE the character roles a module expects (e.g. a "protagonist"
## whose sheet drives the engine). A campaign binds its roster characters to
## these slots; a one-off binds a single character. The declaration is advisory
## metadata the runners validate against — the engine still runs one active
## protagonist sheet per module (the single IFState sheet).

var id: String = ""
var name: String = ""
var version: String = ""
var meta: Dictionary = {}
var ruleset_id: String = ""

## The embedded narrative graph, already parsed into the shared P0 model.
var scenario: IFScenario

## entry contract.
var entry_start: String = ""
var entry_on_entry: Array = []
var entry_requires: Array = []

## exit contract: endingKey -> exitRule dict, plus a default.
var exit_endings: Dictionary = {}
var exit_default: Dictionary = {}

## Declared character slots.
var slots: Array = []

var _raw: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		load_from(data)


static func from_file(path: String) -> IFModule:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("IFModule: could not read '%s'" % path)
		return IFModule.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("IFModule: '%s' is not a JSON object" % path)
		return IFModule.new()
	return IFModule.new(parsed)


## Resolve either an inline `module` dict or a `moduleRef` res:// path from a
## containing object (a campaign entry, a one-off). Returns a parsed IFModule.
static func resolve(container: Dictionary, inline_key: String = "module", ref_key: String = "moduleRef") -> IFModule:
	if container.has(inline_key) and typeof(container[inline_key]) == TYPE_DICTIONARY:
		return IFModule.new(container[inline_key])
	if container.has(ref_key):
		return IFModule.from_file(str(container[ref_key]))
	push_error("IFModule.resolve: no '%s' or '%s' present" % [inline_key, ref_key])
	return IFModule.new()


func load_from(data: Dictionary) -> void:
	_raw = data
	id = str(data.get("id", ""))
	name = str(data.get("name", id))
	version = str(data.get("version", ""))
	meta = data.get("meta", {})
	ruleset_id = str(data.get("ruleset", ""))

	var scen_data: Dictionary = data.get("scenario", {})
	scenario = IFScenario.new(scen_data)
	# A module's ruleset is authoritative; keep the scenario's in sync if unset.
	if scenario.ruleset_id == "" and ruleset_id != "":
		scenario.ruleset_id = ruleset_id

	var entry: Dictionary = data.get("entry", {})
	entry_start = str(entry.get("start", ""))
	entry_on_entry = entry.get("onEntry", [])
	entry_requires = entry.get("requires", [])

	var exit: Dictionary = data.get("exit", {})
	exit_endings = exit.get("endings", {})
	exit_default = exit.get("default", {})

	slots = data.get("slots", [])


## The passage the module starts at: entry override, else the scenario's start.
func start_passage() -> String:
	if entry_start != "":
		return entry_start
	return scenario.start


## Look up the exit rule for a reached ending. Resolution order: exact ending id,
## then ending kind, then the module `default`, then a synthesised complete/fail
## from the kind (victory-like -> complete, otherwise fail).
func exit_rule_for(ending: Dictionary) -> Dictionary:
	var eid := str(ending.get("id", ""))
	var kind := str(ending.get("kind", ""))
	if eid != "" and exit_endings.has(eid):
		return exit_endings[eid]
	if kind != "" and exit_endings.has(kind):
		return exit_endings[kind]
	if not exit_default.is_empty():
		return exit_default
	# Fallback: treat a "victory"/"success"/"complete" kind as completion.
	var complete := kind in ["victory", "success", "complete", "win", "cleared"]
	return {"outcome": "complete" if complete else "fail"}


## The declared "protagonist" slot id (role == "protagonist"), else the first
## required slot, else "" (the engine falls back to the caller-supplied slot).
func protagonist_slot() -> String:
	for s in slots:
		if str(s.get("role", "")) == "protagonist":
			return str(s.get("id", ""))
	for s in slots:
		if bool(s.get("required", false)):
			return str(s.get("id", ""))
	return ""


## Structural validation. `ruleset` (optional) enables rule/route cross-checks
## via the scenario validator. Returns human-readable problems ([] == valid).
func validate(ruleset: IFRuleset = null) -> Array[String]:
	var problems: Array[String] = []
	if id == "":
		problems.append("module has no id")
	if ruleset_id == "":
		problems.append("module '%s' names no ruleset" % id)
	if scenario == null or scenario.passages.is_empty():
		problems.append("module '%s' has no scenario passages" % id)
	else:
		var start := start_passage()
		if start == "":
			problems.append("module '%s' has no start passage" % id)
		elif not scenario.has_passage(start):
			problems.append("module '%s' entry start '%s' missing" % [id, start])
		for p in scenario.validate(ruleset):
			problems.append("module '%s' scenario: %s" % [id, p])
	# Exit routes point at ending passages that exist.
	for key in exit_endings.keys():
		var rule: Dictionary = exit_endings[key]
		if str(rule.get("outcome", "")) not in ["complete", "fail"]:
			problems.append("module '%s' exit '%s' has bad outcome '%s'" % [id, key, rule.get("outcome")])
	return problems


func raw() -> Dictionary:
	return _raw
