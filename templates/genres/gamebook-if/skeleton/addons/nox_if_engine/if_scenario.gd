class_name IFScenario
extends RefCounted
## res://addons/nox_if_engine/if_scenario.gd
## The shared narrative-graph data model (spec §2, P0) — the ONE model both
## authoring views (ink text via the Writers Room, and the visual passage/choice
## graph) compile to and from. It is pure content: passages, choices, conditions,
## effects. It names a ruleset but contains no resolution logic itself.
##
## Shape (`module.json` / scenario):
##   {
##     id, name, meta:{...},
##     ruleset: "ff-2d6",              # which system resolves this scenario
##     start:   "<passage id>",
##     sheet:   {attributes:{...}, resources:{...}} | null,   # fixed sheet, or
##                                     # null => generate from the ruleset
##     init:    { vars:{...}, items:{name:count}, flags:{...} },
##     passages: [ <passage> ]
##   }
##
## Passage:
##   {
##     id, title?, text?,
##     onEnter: [ <effect> ]?,          # applied when the passage is entered
##     check:   <check node>?,          # a resolution invoked on entry; routes
##                                      #   by outcome band (see below)
##     choices: [ <choice> ]?,          # player options
##     ending:  { id, kind, label }?    # terminal passage
##   }
##
## Choice:
##   {
##     id, text,
##     conditions: [ <condition> ]?,    # ALL must hold to be offered
##     effects:    [ <effect> ]?,       # applied when chosen
##     check:      <check node>?,       # optional resolution before routing
##     goto:       "<passage id>"?      # route (a check outcome may override)
##   }
##
## Check node (binds a resolution to story outcomes — where CONTENT meets a rule).
## TWO shapes; the Runner dispatches on which (see if_portable_check.gd):
##
##   NATIVE (P0/P1) — bound to ONE ruleset's rule + native attributes/bands:
##   {
##     rule: "test",                    # id of a ruleset resolutionRule
##     args: { attr: "SKILL" } | {...}, # operands the rule reads (attr/dc/dice)
##     outcomes: {                      # NATIVE band id -> what that outcome DOES
##        success: { effects:[...], goto:"..." },
##        failure: { effects:[...], goto:"..." },
##        _default: { goto:"..." }      # fallback for any unlisted band
##     }
##   }
##
##   PORTABLE (P2) — ruleset-AGNOSTIC; the SAME node runs under every system:
##   {
##     semantic:   "skill-test",        # a canonical semantic every ruleset maps
##     attribute:  "prowess",           # a CANONICAL attribute (not a native key)
##     difficulty: "hard",              # a CANONICAL difficulty rung
##     outcomes: {                      # CANONICAL band -> what that outcome DOES
##        success: {...}, partial: {...}, failure: {...}, _default: {...}
##     }
##   }
## A portable scenario declares `"ruleset": "*"` (any/portable) — the runtime
## ruleset is supplied by the campaign/one-off/probe, not the scenario.

var id: String = ""
var name: String = ""
var meta: Dictionary = {}
var ruleset_id: String = ""
var start: String = ""
var sheet_override: Variant = null       # Dictionary or null
var init_vars: Dictionary = {}
var init_items: Dictionary = {}
var init_flags: Dictionary = {}

## id -> passage dict.
var passages: Dictionary = {}

var _raw: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		load_from(data)


static func from_file(path: String) -> IFScenario:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("IFScenario: could not read '%s'" % path)
		return IFScenario.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("IFScenario: '%s' is not a JSON object" % path)
		return IFScenario.new()
	return IFScenario.new(parsed)


func load_from(data: Dictionary) -> void:
	_raw = data
	id = str(data.get("id", ""))
	name = str(data.get("name", id))
	meta = data.get("meta", {})
	ruleset_id = str(data.get("ruleset", ""))
	start = str(data.get("start", ""))
	sheet_override = data.get("sheet", null)
	var init: Dictionary = data.get("init", {})
	init_vars = init.get("vars", {})
	init_items = init.get("items", {})
	init_flags = init.get("flags", {})

	passages.clear()
	for p in data.get("passages", []):
		var pid := str(p.get("id", ""))
		if pid == "":
			push_warning("IFScenario '%s': passage with no id" % id)
			continue
		passages[pid] = p


func has_passage(passage_id: String) -> bool:
	return passages.has(passage_id)


func passage(passage_id: String) -> Dictionary:
	if not passages.has(passage_id):
		push_error("IFScenario '%s': no passage '%s'" % [id, passage_id])
		return {}
	return passages[passage_id]


## Structural validation — every referenced passage exists, start is set, the
## ruleset is named. Returns a list of human-readable problems ([] == valid).
func validate(ruleset: IFRuleset = null) -> Array[String]:
	var problems: Array[String] = []
	if start == "":
		problems.append("no start passage")
	elif not has_passage(start):
		problems.append("start passage '%s' missing" % start)
	if ruleset_id == "":
		problems.append("no ruleset id")

	for pid in passages.keys():
		var p: Dictionary = passages[pid]
		# Choice routes.
		for ch in p.get("choices", []):
			var goto := str(ch.get("goto", ""))
			if goto != "" and not has_passage(goto):
				problems.append("passage '%s' choice -> missing '%s'" % [pid, goto])
			_validate_check(ch.get("check", null), pid, ruleset, problems)
		# Passage-level check.
		_validate_check(p.get("check", null), pid, ruleset, problems)
	return problems


func _validate_check(check: Variant, pid: String, ruleset: IFRuleset, problems: Array[String]) -> void:
	if check == null:
		return
	if IFPortableCheck.is_portable(check):
		# PORTABLE (P2): validated against the canonical vocabularies + (if a
		# ruleset is supplied) the ruleset's ability to express the semantic.
		for p in IFPortableCheck.validate(check, pid, ruleset):
			problems.append(p)
	else:
		# NATIVE (P0/P1): the check names a ruleset rule id directly.
		var rule_id := str(check.get("rule", ""))
		if rule_id == "" and not check.get("outcomes", {}).is_empty():
			problems.append("passage '%s' check has neither 'rule' nor 'semantic'" % pid)
		if ruleset != null and rule_id != "" and not ruleset.rules.has(rule_id):
			problems.append("passage '%s' check -> unknown rule '%s'" % [pid, rule_id])
	# Outcome routes exist — shared by both shapes.
	for band in check.get("outcomes", {}).keys():
		var oc: Dictionary = check["outcomes"][band]
		var goto := str(oc.get("goto", ""))
		if goto != "" and not has_passage(goto):
			problems.append("passage '%s' outcome '%s' -> missing '%s'" % [pid, band, goto])


func raw() -> Dictionary:
	return _raw
