class_name IFAdventureValidator
extends RefCounted
## res://addons/nox_if_engine/if_adventure_validator.gd
## The ADVENTURE (scenario) authoring validator — the author-first tooling the GDD
## §10 asks for over the if-engine format. A ~400-section gamebook is a large graph;
## this catches the errors that make one unplayable BEFORE it ships:
##
##   * DANGLING ROUTES  — any `turn to N` (choice goto, onEnter/effect goto, check
##                        outcome goto) that points at a passage that doesn't exist.
##   * UNREACHABLE       — sections no path from `start` can ever enter.
##   * DEAD-ENDS         — a non-ending section the hero can enter but never leave
##                        (no choices, no routing check, no onEnter goto).
##   * UNWINNABLE        — no victory ending is reachable from the start.
##   * FLAG/CODEWORD     — a condition that reads a flag/codeword/var/item that NO
##     INCONSISTENCY       effect (or scenario init) ever writes (a "true path" that
##                        can never open), and codewords set but never tested.
##
## It reuses IFScenario.validate() for the structural pass (start/ruleset presence +
## the native dangling-goto + unknown-rule checks) and layers the graph analyses on
## top. Pure + deterministic; returns a serialisable result so a Studio authoring
## UI (or a probe) can render it directly:
##
##   { ok:bool, errors:[String], warnings:[String],
##     reachable:[id], unreachable:[id], dead_ends:[id],
##     victory_reachable:bool }

static func validate(scenario: IFScenario, ruleset: IFRuleset = null) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	# --- 1) structural pass (dangling choice/check gotos, start, ruleset) -------
	for problem in scenario.validate(ruleset):
		errors.append(problem)

	# --- 2) dangling gotos the structural pass doesn't cover -------------------
	# (onEnter effect gotos + choice effect gotos — `goto` kind effects.)
	for pid in scenario.passages.keys():
		var p: Dictionary = scenario.passages[pid]
		for eff in p.get("onEnter", []):
			_check_goto_effect(eff, pid, "onEnter", scenario, errors)
		for ch in p.get("choices", []):
			for eff in ch.get("effects", []):
				_check_goto_effect(eff, pid, "choice '%s' effect" % str(ch.get("id", "?")), scenario, errors)

	# --- 3) reachability + dead-ends + winnability ----------------------------
	var reachable := _reachable_from(scenario, scenario.start)
	var unreachable: Array[String] = []
	for pid in scenario.passages.keys():
		if not reachable.has(pid):
			unreachable.append(str(pid))
	unreachable.sort()
	for pid in unreachable:
		errors.append("unreachable section '%s' (no path from start '%s')" % [pid, scenario.start])

	var dead_ends: Array[String] = []
	for pid in reachable.keys():
		var p: Dictionary = scenario.passages.get(pid, {})
		if p.is_empty():
			continue
		if p.has("ending"):
			continue
		if _successors(p, scenario).is_empty():
			dead_ends.append(str(pid))
	dead_ends.sort()
	for pid in dead_ends:
		errors.append("dead-end section '%s' — not an ending, but has no way out" % pid)

	var victory_reachable := false
	for pid in reachable.keys():
		var p: Dictionary = scenario.passages.get(pid, {})
		if p.has("ending") and str((p["ending"] as Dictionary).get("kind", "")) == "victory":
			victory_reachable = true
			break
	if not victory_reachable:
		errors.append("unwinnable — no victory ending is reachable from the start")

	# --- 4) flag / codeword / var / item consistency --------------------------
	var written := _collect_written(scenario)
	var read := _collect_read(scenario)
	# a read that nothing ever writes -> the gate can never open
	for domain in read.keys():
		for key in read[domain].keys():
			if not written.get(domain, {}).has(key):
				warnings.append("condition reads %s '%s' that no effect or init ever sets" % [domain, key])
	# a codeword set but never tested -> dead content (advisory)
	for key in written.get("codeword", {}).keys():
		if not read.get("codeword", {}).has(key):
			warnings.append("codeword '%s' is set but never tested by any condition" % key)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"reachable": reachable.keys(),
		"unreachable": unreachable,
		"dead_ends": dead_ends,
		"victory_reachable": victory_reachable,
	}


static func validate_file(scenario_path: String, ruleset: IFRuleset = null) -> Dictionary:
	return validate(IFScenario.from_file(scenario_path), ruleset)


# --- internals --------------------------------------------------------------


static func _check_goto_effect(eff: Variant, pid: String, ctx: String, scenario: IFScenario, errors: Array[String]) -> void:
	if typeof(eff) != TYPE_DICTIONARY:
		return
	if str(eff.get("kind", "")) != "goto":
		return
	var target := str(eff.get("value", eff.get("target", "")))
	if target != "" and not scenario.has_passage(target):
		errors.append("passage '%s' %s -> missing '%s'" % [pid, ctx, target])


## The set of passage ids a single passage can route to, ignoring conditions
## (over-approximation — used for reachability + dead-end detection).
static func _successors(p: Dictionary, scenario: IFScenario) -> Dictionary:
	var out: Dictionary = {}
	for eff in p.get("onEnter", []):
		_add_goto(eff, out)
	_add_check_targets(p.get("check", null), out)
	for ch in p.get("choices", []):
		var g := str(ch.get("goto", ""))
		if g != "":
			out[g] = true
		for eff in ch.get("effects", []):
			_add_goto(eff, out)
		_add_check_targets(ch.get("check", null), out)
	# only keep targets that actually exist (dangling ones are reported separately)
	var valid: Dictionary = {}
	for t in out.keys():
		if scenario.has_passage(str(t)):
			valid[str(t)] = true
	return valid


static func _add_goto(eff: Variant, out: Dictionary) -> void:
	if typeof(eff) == TYPE_DICTIONARY and str(eff.get("kind", "")) == "goto":
		var t := str(eff.get("value", eff.get("target", "")))
		if t != "":
			out[t] = true


static func _add_check_targets(check: Variant, out: Dictionary) -> void:
	if typeof(check) != TYPE_DICTIONARY:
		return
	for band in check.get("outcomes", {}).keys():
		var oc: Dictionary = check["outcomes"][band]
		var g := str(oc.get("goto", ""))
		if g != "":
			out[g] = true
		for eff in oc.get("effects", []):
			_add_goto(eff, out)


static func _reachable_from(scenario: IFScenario, start: String) -> Dictionary:
	var seen: Dictionary = {}
	if start == "" or not scenario.has_passage(start):
		return seen
	var stack: Array[String] = [start]
	while not stack.is_empty():
		var pid := stack.pop_back()
		if seen.has(pid):
			continue
		seen[pid] = true
		for succ in _successors(scenario.passages[pid], scenario).keys():
			if not seen.has(succ):
				stack.append(str(succ))
	return seen


## Walk every effect site and collect written keys per domain (flag/codeword/var/
## item), seeded with the scenario's init vars/items/flags.
static func _collect_written(scenario: IFScenario) -> Dictionary:
	var w := {"flag": {}, "codeword": {}, "var": {}, "item": {}}
	for k in scenario.init_vars.keys():
		w["var"][str(k)] = true
	for k in scenario.init_items.keys():
		w["item"][str(k)] = true
	for k in scenario.init_flags.keys():
		w["flag"][str(k)] = true
	for pid in scenario.passages.keys():
		var p: Dictionary = scenario.passages[pid]
		_collect_effects(p.get("onEnter", []), w)
		_collect_check_effects(p.get("check", null), w)
		for ch in p.get("choices", []):
			_collect_effects(ch.get("effects", []), w)
			_collect_check_effects(ch.get("check", null), w)
	return w


static func _collect_effects(effects: Variant, w: Dictionary) -> void:
	if typeof(effects) != TYPE_ARRAY:
		return
	for eff in effects:
		if typeof(eff) != TYPE_DICTIONARY:
			continue
		var kind := str(eff.get("kind", ""))
		var key := str(eff.get("key", ""))
		if key == "":
			continue
		if w.has(kind):
			w[kind][key] = true


static func _collect_check_effects(check: Variant, w: Dictionary) -> void:
	if typeof(check) != TYPE_DICTIONARY:
		return
	for band in check.get("outcomes", {}).keys():
		_collect_effects((check["outcomes"][band] as Dictionary).get("effects", []), w)


## Walk every condition site and collect read keys per domain.
static func _collect_read(scenario: IFScenario) -> Dictionary:
	var r := {"flag": {}, "codeword": {}, "var": {}, "item": {}}
	for pid in scenario.passages.keys():
		var p: Dictionary = scenario.passages[pid]
		for ch in p.get("choices", []):
			_collect_conditions(ch.get("conditions", null), r)
	return r


static func _collect_conditions(conds: Variant, r: Dictionary) -> void:
	if typeof(conds) == TYPE_ARRAY:
		for c in conds:
			_collect_condition(c, r)
	elif typeof(conds) == TYPE_DICTIONARY:
		_collect_condition(conds, r)


static func _collect_condition(cond: Variant, r: Dictionary) -> void:
	if typeof(cond) != TYPE_DICTIONARY:
		return
	var kind := str(cond.get("kind", "var"))
	match kind:
		"any", "all":
			for c in cond.get("of", []):
				_collect_condition(c, r)
		"not":
			_collect_condition(cond.get("of", {}), r)
		"flag", "codeword", "var", "item":
			var key := str(cond.get("key", ""))
			if key != "" and r.has(kind):
				r[kind][key] = true
		_:
			pass
