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


## Load system + content + seed. The sheet is chosen in precedence order:
##   1. `sheet_in` — an EXPLICIT sheet injected by the caller (P1: a campaign
##      injecting a carried character's sheet into the slot). Highest priority.
##   2. `scenario.sheet_override` — a fixed sheet authored on the scenario.
##   3. generated from the ruleset's attribute `gen` expressions (seeded).
## `sheet_in` is a small, additive P1 seam: it lets IFCharacter fill the slot
## without the scenario having to hardcode a sheet. When omitted the P0 behaviour
## is byte-for-byte unchanged.
func load(ruleset_in: IFRuleset, scenario_in: IFScenario, seed_in: int, sheet_in: Variant = null) -> void:
	ruleset = ruleset_in
	scenario = scenario_in
	_seed = seed_in
	dice = IFDice.new()
	dice.set_seed(seed_in)
	resolver = IFResolver.new(ruleset, dice)
	state = IFState.new(ruleset)

	# Sheet: explicit injection > scenario override > generated.
	var sheet: Dictionary
	if typeof(sheet_in) == TYPE_DICTIONARY:
		sheet = _normalize_sheet_override(sheet_in)
	elif typeof(scenario.sheet_override) == TYPE_DICTIONARY:
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


# --- authoring / debug seams (GDD §10) --------------------------------------


## Jump-to-any-section debug play (GDD §10). Teleports straight into `passage_id`
## — applying its onEnter/check/ending exactly as a normal entry would — WITHOUT
## needing a legal route to it. Clears any terminal flag so a jump out of an ending
## resumes play. Returns false for an unknown id. Debug-only; not a play action.
func jump_to(passage_id: String) -> bool:
	if not scenario.has_passage(passage_id):
		push_error("IFRunner.jump_to: unknown passage '%s'" % passage_id)
		return false
	state.ended = false
	state.ending = {}
	_enter_passage(passage_id, 0)
	return true


## Hot-reload preview (GDD §10). Swaps in a freshly-read scenario (e.g. after the
## author edits the JSON) while preserving live state. Returns true if the current
## section still exists in the new content (the UI can re-render in place); false if
## it vanished (the caller should jump to the new start). Content only — state,
## sheet, seed and RNG position are untouched.
func reload_scenario(new_scenario: IFScenario) -> bool:
	scenario = new_scenario
	return scenario.has_passage(state.current_passage)


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
##
## Dispatches on the check SHAPE (P2):
##   * PORTABLE (has `semantic`) — compiled by IFPortableCheck into a concrete
##     { rule, args } for THIS ruleset, resolved, and the native band mapped back
##     to a CANONICAL band that the scenario's `outcomes` route on (with the
##     canonical fallback ladder). This is what lets ONE scenario run under every
##     system. The scenario carries no ruleset; the runner supplies it.
##   * NATIVE (has `rule`) — the P0/P1 path, unchanged: the check names a ruleset
##     rule id + native args and routes on native band ids.
func _run_check(check: Dictionary) -> String:
	var portable := IFPortableCheck.is_portable(check)

	var rule_id: String
	var args: Dictionary
	if portable:
		var compiled := IFPortableCheck.compile(check, ruleset)
		if not compiled.get("ok", false):
			push_error("IFRunner: portable check could not compile — %s" % compiled.get("error", ""))
			return ""
		rule_id = str(compiled.get("rule", ""))
		args = compiled.get("args", {})
	else:
		rule_id = str(check.get("rule", ""))
		args = check.get("args", {})

	var rule := ruleset.rule(rule_id)
	if rule.is_empty():
		return ""
	var result := resolver.resolve(rule, state, args)
	var native_band := str(result.get("band", ""))

	# Route on the canonical band for portable checks; on the native band for
	# native checks (byte-for-byte the P0/P1 behaviour).
	var band := native_band
	var outcomes: Dictionary = check.get("outcomes", {})
	var outcome: Dictionary
	if portable:
		band = IFPortableCheck.canonical_band(native_band, ruleset)
		outcome = IFPortableCheck.resolve_outcome(outcomes, band)
	else:
		outcome = outcomes.get(native_band, outcomes.get("_default", {}))

	trace.append({
		"type": "check",
		"passage": state.current_passage,
		"portable": portable,
		"semantic": str(check.get("semantic", "")),
		"rule": rule_id,
		"band": band,
		"native_band": native_band,
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


## Snapshot for save/replay — the SHORT-TERM store's payload (P1). Captures the
## seed, the live RNG position and the full IFState so a session can be resumed
## byte-for-byte with restore().
func snapshot() -> Dictionary:
	return {
		"seed": _seed,
		"dice_state": dice.get_state(),
		"state": state.save_data(),
	}


## Rehydrate a runner from a snapshot() — the inverse of load()+play. Rebuilds the
## dice at its exact mid-stream position (seed + saved RNG state) and reloads the
## IFState, so continuing to play produces the identical sequence a non-interrupted
## run would have. The caller supplies the same ruleset + scenario the snapshot was
## taken against (content is not stored in the save — only mutable state is). This
## is the P1 resume seam for short-term (mid-module) saves.
func restore(ruleset_in: IFRuleset, scenario_in: IFScenario, snapshot_in: Dictionary) -> void:
	ruleset = ruleset_in
	scenario = scenario_in
	_seed = int(snapshot_in.get("seed", 0))
	dice = IFDice.new()
	dice.set_seed(_seed)
	dice.set_state(int(snapshot_in.get("dice_state", 0)))
	resolver = IFResolver.new(ruleset, dice)
	state = IFState.new(ruleset)
	state.load_data(snapshot_in.get("state", {}))
	trace.clear()
