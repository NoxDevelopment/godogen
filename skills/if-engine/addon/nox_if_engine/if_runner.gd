class_name IFRunner
extends RefCounted
## res://addons/nox_if_engine/if_runner.gd
## Plays a scenario deterministically over the computed engine — NO LLM, NO
## networking (P0). Wires the four pure pieces together:
##   IFRuleset (system data) + IFScenario (content data) + IFDice (seeded RNG)
##   -> drives an IFState through the narrative graph, resolving checks via
##   IFResolver and routing by outcome bands.
##
## Given a fixed seed this replays byte-for-byte, which is what makes it headless-
## testable and, later, the authoritative state a multiplayer host would sync.
##
## Play loop (host/caller side):
##   var r := IFRunner.new(); r.load(ruleset, scenario, seed); r.start()
##   while not r.is_ended():
##       var choices := r.available_choices()      # conditions already filtered
##       r.choose(choices[i].id)                    # apply effects + route
##
## Passage entry sequence (enter_passage):
##   1. record the passage on the state (history)
##   2. apply passage.onEnter effects
##   3. if the passage has a `check`, resolve it now and route by outcome band
##      (an auto-resolution node — e.g. a trap or a guardian) — chained entry
##   4. if the passage is an `ending`, mark terminal and stop

const MAX_CHAIN := 64   # guard against a mis-authored routing cycle

var ruleset: IFRuleset
var scenario: IFScenario
var state: IFState
var dice: IFDice
var resolver: IFResolver

## Ordered log of everything that happened (for the probe/UI/replay assertions).
##   { type:"enter"|"effect_route"|"check"|"choice"|"ending", ... }
var trace: Array[Dictionary] = []

var _seed: int = 0


func _init() -> void:
	pass


## Load system + content + seed. `sheet_override` (optional) forces a fixed sheet
## for a fully deterministic play; otherwise the sheet is generated from the
## ruleset's attribute `gen` expressions (also seeded, so still deterministic).
func load(ruleset_in: IFRuleset, scenario_in: IFScenario, seed_in: int) -> void:
	ruleset = ruleset_in
	scenario = scenario_in
	_seed = seed_in
	dice = IFDice.new()
	dice.set_seed(seed_in)
	resolver = IFResolver.new(ruleset, dice)
	state = IFState.new(ruleset)

	# Sheet: fixed override from the scenario, else generated.
	var sheet: Dictionary
	if typeof(scenario.sheet_override) == TYPE_DICTIONARY:
		sheet = _normalize_sheet_override(scenario.sheet_override)
	else:
		sheet = ruleset.generate_sheet(dice)
	state.init_sheet(sheet)

	# Initial short-term state.
	for k in scenario.init_vars.keys():
		state.set_var(str(k), float(scenario.init_vars[k]))
	for k in scenario.init_items.keys():
		state.grant_item(str(k), int(scenario.init_items[k]))
	for k in scenario.init_flags.keys():
		state.set_flag(str(k), scenario.init_flags[k])


func _normalize_sheet_override(ov: Dictionary) -> Dictionary:
	# Accept {attributes:{...}, resources:{...}, resource_max?:{...}} directly, or
	# a flat {SKILL:9, STAMINA:20, ...} which we split into attrs/resources.
	if ov.has("attributes") or ov.has("resources"):
		return {
			"attributes": ov.get("attributes", {}),
			"resources": ov.get("resources", {}),
			"resource_max": ov.get("resource_max", {}),
		}
	var attrs: Dictionary = {}
	var res: Dictionary = {}
	for k in ov.keys():
		var key := str(k)
		if ruleset.has_resource(key):
			res[key] = float(ov[k])
		if ruleset.has_attribute(key):
			attrs[key] = float(ov[k])
	return {"attributes": attrs, "resources": res, "resource_max": {}}


## Begin play at the scenario's start passage.
func start() -> void:
	trace.clear()
	_enter_passage(scenario.start, 0)


func is_ended() -> bool:
	return state.ended


func ending() -> Dictionary:
	return state.ending


func current_passage() -> Dictionary:
	return scenario.passage(state.current_passage)


## Choices whose conditions currently hold — what the player (or AI-player-assist
## later) may pick. Each is the raw choice dict; use `.id` to choose.
func available_choices() -> Array:
	var out: Array = []
	if state.ended:
		return out
	var p := current_passage()
	for ch in p.get("choices", []):
		if state.conditions_met(ch.get("conditions", null)):
			out.append(ch)
	return out


## Is a given choice offered right now (conditions hold)? Used for item-gate
## assertions.
func is_choice_available(choice_id: String) -> bool:
	for ch in available_choices():
		if str(ch.get("id", "")) == choice_id:
			return true
	return false


## Take a choice by id: apply its effects, run its optional check, route.
func choose(choice_id: String) -> void:
	if state.ended:
		push_warning("IFRunner: choose('%s') after ending" % choice_id)
		return
	var p := current_passage()
	var choice: Dictionary = {}
	for ch in p.get("choices", []):
		if str(ch.get("id", "")) == choice_id:
			choice = ch
			break
	if choice.is_empty():
		push_error("IFRunner: no choice '%s' at passage '%s'" % [choice_id, state.current_passage])
		return
	if not state.conditions_met(choice.get("conditions", null)):
		push_error("IFRunner: choice '%s' not available (conditions unmet)" % choice_id)
		return

	trace.append({"type": "choice", "passage": state.current_passage, "choice": choice_id})

	var route := state.apply_effects(choice.get("effects", null))

	# An inline check on the choice can override the route.
	if choice.has("check"):
		var check_route := _run_check(choice["check"])
		if check_route != "":
			route = check_route

	if route == "":
		route = str(choice.get("goto", ""))
	if route == "":
		push_error("IFRunner: choice '%s' produced no route" % choice_id)
		return
	_enter_passage(route, 0)


# --- internals --------------------------------------------------------------


func _enter_passage(passage_id: String, depth: int) -> void:
	if depth > MAX_CHAIN:
		push_error("IFRunner: routing depth exceeded at '%s' (cycle?)" % passage_id)
		return
	if not scenario.has_passage(passage_id):
		push_error("IFRunner: route to missing passage '%s'" % passage_id)
		return

	state.enter_passage(passage_id)
	var p := scenario.passage(passage_id)
	trace.append({"type": "enter", "passage": passage_id})

	# 1) onEnter effects (a passage effect may itself route via a goto effect).
	var route := state.apply_effects(p.get("onEnter", null))

	# 2) ending short-circuits.
	if p.has("ending"):
		state.mark_ending(p["ending"])
		trace.append({"type": "ending", "passage": passage_id, "ending": p["ending"]})
		return

	# 3) an onEnter goto effect routes immediately.
	if route != "":
		_enter_passage(route, depth + 1)
		return

	# 4) a passage-level check auto-resolves and routes by outcome band.
	if p.has("check"):
		var check_route := _run_check(p["check"])
		if check_route != "":
			_enter_passage(check_route, depth + 1)
		return
	# else: an interactive passage — wait for choose().


## Resolve a check node against a ruleset rule, apply the matched outcome's
## effects, and return its route ("" if none). Records into trace + roll_log.
func _run_check(check: Dictionary) -> String:
	var rule_id := str(check.get("rule", ""))
	var rule := ruleset.rule(rule_id)
	if rule.is_empty():
		return ""
	var args: Dictionary = check.get("args", {})
	var result := resolver.resolve(rule, state, args)
	var band := str(result.get("band", ""))

	var outcomes: Dictionary = check.get("outcomes", {})
	var outcome: Dictionary = outcomes.get(band, outcomes.get("_default", {}))

	trace.append({
		"type": "check",
		"passage": state.current_passage,
		"rule": rule_id,
		"band": band,
		"total": result.total,
		"faces": result.faces,
		"target": result.target,
		"success": result.success,
		"crit": result.crit,
	})

	var route := state.apply_effects(outcome.get("effects", null))
	var goto := str(outcome.get("goto", ""))
	if goto != "":
		route = goto
	return route


## Snapshot for save/replay (P1 will extend this into the persistence stores).
func snapshot() -> Dictionary:
	return {
		"seed": _seed,
		"dice_state": dice.get_state(),
		"state": state.save_data(),
	}
