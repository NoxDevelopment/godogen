class_name IFRulesetValidator
extends RefCounted
## res://addons/nox_if_engine/if_ruleset_validator.gd
## The ruleset VALIDATOR + IMPORTER (spec §2.5, P2) — the engine half the future
## Ruleset Builder UI (P2b, a separate Studio surface) writes to. It accepts an
## ARBITRARY user `ruleset.json` (a hand-authored system, a cloned builtin, an
## imported third-party system the user re-expressed as data) and checks it,
## field by field, against the §2.5 schema — returning either a list of clear,
## specific errors OR a runnable IFRuleset.
##
## It hardcodes NO system. It only knows the SHAPE a ruleset must have to be
## interpretable by IFResolver (resolution rules), IFRuleset (attributes/
## resources/sheet) and IFPortableCheck (the optional portability block). Nothing
## here reaches out to a network or an LLM — pure, deterministic structural
## validation, the same on every run.
##
## Result (a Dictionary, so callers/UI can serialise it directly):
##   {
##     ok:       bool,             # true == importable (no errors)
##     errors:   [String],         # blocking problems — MUST be empty to run
##     warnings: [String],         # non-blocking advisories (still runnable)
##     ruleset:  IFRuleset | null  # a loaded, runnable ruleset when ok
##   }
##
## Usage (Builder UI / importer):
##   var res := IFRulesetValidator.validate(user_ruleset_dict)
##   if res.ok:  play_with(res.ruleset)
##   else:       show_errors(res.errors)         # or res.warnings

const COMPARE_MODES: Array[String] = ["roll-under", "meet-or-beat", "threshold-bands"]
const OPERAND_TYPES: Array[String] = ["attribute", "attributeArg", "resource", "var", "param", "const"]
const OPERAND_ROLES: Array[String] = ["target", "modifier"]
const TRANSFORMS: Array[String] = ["none", "abilityMod", "negate"]
const CRIT_MODES: Array[String] = ["none", "natural", "doubles"]
const BINARY_WHENS: Array[String] = ["success", "fail", "critSuccess", "critFail"]
const EFFECT_KINDS: Array[String] = ["var", "item", "attr", "resource", "flag", "codeword", "note", "goto"]
const DIFFICULTY_MODES: Array[String] = ["dc", "targetDelta", "rollModifier"]


## Validate a raw ruleset dict. Never throws; returns the result Dictionary above.
static func validate(data: Variant) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if typeof(data) != TYPE_DICTIONARY:
		errors.append("ruleset is not a JSON object")
		return _result(errors, warnings, null)
	var rs: Dictionary = data

	# --- identity -----------------------------------------------------------
	if str(rs.get("id", "")).strip_edges() == "":
		errors.append("missing 'id'")
	if not rs.has("name"):
		warnings.append("missing 'name' (will default to id)")

	# --- dice ---------------------------------------------------------------
	var dice: Dictionary = rs.get("dice", {})
	if not rs.has("dice") or not dice.has("default"):
		errors.append("missing 'dice.default' (the system's default dice expression)")
	else:
		var dv := IFDice.validate_expr(str(dice.get("default", "")))
		if not dv.ok:
			errors.append("dice.default: %s" % dv.error)

	# --- attributes ---------------------------------------------------------
	var attr_keys: Array[String] = []
	var attrs: Variant = rs.get("attributes", null)
	if typeof(attrs) != TYPE_ARRAY or (attrs as Array).is_empty():
		errors.append("'attributes' must be a non-empty array")
	else:
		var seen: Dictionary = {}
		for i in (attrs as Array).size():
			var a: Variant = attrs[i]
			if typeof(a) != TYPE_DICTIONARY:
				errors.append("attributes[%d] is not an object" % i)
				continue
			var key := str(a.get("key", "")).strip_edges()
			if key == "":
				errors.append("attributes[%d] has no 'key'" % i)
				continue
			if seen.has(key):
				errors.append("attribute key '%s' is duplicated" % key)
			seen[key] = true
			attr_keys.append(key)
			if a.has("gen"):
				var gv := IFDice.validate_expr(str(a.get("gen", "")))
				if not gv.ok:
					errors.append("attribute '%s' gen: %s" % [key, gv.error])
			_check_bounds("attribute '%s'" % key, a, errors)

	# --- resources ----------------------------------------------------------
	var res_keys: Array[String] = []
	var resources: Variant = rs.get("resources", [])
	if typeof(resources) != TYPE_ARRAY:
		errors.append("'resources' must be an array")
	else:
		var seen_r: Dictionary = {}
		for i in (resources as Array).size():
			var r: Variant = resources[i]
			if typeof(r) != TYPE_DICTIONARY:
				errors.append("resources[%d] is not an object" % i)
				continue
			var key := str(r.get("key", "")).strip_edges()
			if key == "":
				errors.append("resources[%d] has no 'key'" % i)
				continue
			if seen_r.has(key):
				errors.append("resource key '%s' is duplicated" % key)
			seen_r[key] = true
			res_keys.append(key)
			if r.has("from") and str(r["from"]) not in attr_keys:
				errors.append("resource '%s' from '%s' is not a declared attribute" % [key, r["from"]])
			_check_bounds("resource '%s'" % key, r, errors)

	# --- sheetTemplate ------------------------------------------------------
	if rs.has("sheetTemplate"):
		var st: Dictionary = rs.get("sheetTemplate", {})
		for k in st.get("attributes", []):
			if str(k) not in attr_keys:
				errors.append("sheetTemplate.attributes references undeclared attribute '%s'" % k)
		for k in st.get("resources", []):
			if str(k) not in res_keys:
				errors.append("sheetTemplate.resources references undeclared resource '%s'" % k)
	else:
		warnings.append("no 'sheetTemplate' (a default sheet from all attributes/resources will be used)")

	# --- resolutionRules ----------------------------------------------------
	var rule_ids: Array[String] = []
	var rules: Variant = rs.get("resolutionRules", null)
	if typeof(rules) != TYPE_ARRAY or (rules as Array).is_empty():
		errors.append("'resolutionRules' must be a non-empty array")
	else:
		var seen_rule: Dictionary = {}
		for i in (rules as Array).size():
			var rule: Variant = rules[i]
			if typeof(rule) != TYPE_DICTIONARY:
				errors.append("resolutionRules[%d] is not an object" % i)
				continue
			var rid := str(rule.get("id", "")).strip_edges()
			if rid == "":
				errors.append("resolutionRules[%d] has no 'id'" % i)
				continue
			if seen_rule.has(rid):
				errors.append("resolution rule id '%s' is duplicated" % rid)
			seen_rule[rid] = true
			rule_ids.append(rid)
			_validate_rule(rule, rid, attr_keys, res_keys, errors, warnings)

	# --- portability (optional) --------------------------------------------
	if rs.has("portability"):
		_validate_portability(rs.get("portability", {}), attr_keys, rule_ids, errors, warnings)

	# --- build the runnable ruleset if clean --------------------------------
	var ruleset: IFRuleset = null
	if errors.is_empty():
		ruleset = IFRuleset.new(rs)
	return _result(errors, warnings, ruleset)


## Validate a ruleset FILE (res:// path). Reads + JSON-parses, then validate().
static func validate_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return _result(["could not read '%s'" % path] as Array[String], [] as Array[String], null)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return _result(["'%s' is not valid JSON" % path] as Array[String], [] as Array[String], null)
	return validate(parsed)


## Import: validate and return the runnable IFRuleset, or null on any error. The
## thin "give me a ruleset or nothing" entry point for callers that only branch on
## success; use validate() when you need the error/warning detail (the UI does).
static func import_ruleset(data: Variant) -> IFRuleset:
	var res := validate(data)
	return res.ruleset if res.ok else null


# --- internals --------------------------------------------------------------


static func _validate_rule(rule: Dictionary, rid: String, attr_keys: Array[String], res_keys: Array[String], errors: Array[String], warnings: Array[String]) -> void:
	if rule.has("dice"):
		var dv := IFDice.validate_expr(str(rule.get("dice", "")))
		if not dv.ok:
			errors.append("rule '%s' dice: %s" % [rid, dv.error])

	var compare := str(rule.get("compare", ""))
	if compare == "":
		errors.append("rule '%s' has no 'compare' mode" % rid)
	elif compare not in COMPARE_MODES:
		errors.append("rule '%s' has unknown compare mode '%s' (expected %s)" % [rid, compare, str(COMPARE_MODES)])

	# operands
	var operands: Variant = rule.get("operands", [])
	var has_target := false
	if typeof(operands) != TYPE_ARRAY:
		errors.append("rule '%s' operands must be an array" % rid)
	else:
		for j in (operands as Array).size():
			var op: Variant = operands[j]
			if typeof(op) != TYPE_DICTIONARY:
				errors.append("rule '%s' operand[%d] is not an object" % [rid, j])
				continue
			var otype := str(op.get("type", ""))
			if otype not in OPERAND_TYPES:
				errors.append("rule '%s' operand[%d] has unknown type '%s'" % [rid, j, otype])
			var role := str(op.get("role", "target"))
			if role not in OPERAND_ROLES:
				errors.append("rule '%s' operand[%d] has unknown role '%s'" % [rid, j, role])
			if role == "target":
				has_target = true
			if op.has("transform") and str(op["transform"]) not in TRANSFORMS:
				errors.append("rule '%s' operand[%d] unknown transform '%s'" % [rid, j, op["transform"]])
			match otype:
				"attribute":
					if str(op.get("ref", "")) == "":
						errors.append("rule '%s' operand[%d] type attribute needs a 'ref'" % [rid, j])
					elif str(op["ref"]) not in attr_keys:
						warnings.append("rule '%s' operand[%d] attribute '%s' is not declared" % [rid, j, op["ref"]])
				"resource":
					if str(op.get("ref", "")) == "":
						errors.append("rule '%s' operand[%d] type resource needs a 'ref'" % [rid, j])
					elif str(op["ref"]) not in res_keys:
						warnings.append("rule '%s' operand[%d] resource '%s' is not declared" % [rid, j, op["ref"]])
				"attributeArg", "param", "var":
					if str(op.get("ref", "")) == "":
						errors.append("rule '%s' operand[%d] type %s needs a 'ref' (the arg/var name)" % [rid, j, otype])
				"const":
					if not _is_number(op.get("value", null)):
						errors.append("rule '%s' operand[%d] type const needs a numeric 'value'" % [rid, j])

	# compare-mode / target coherence
	if compare in ["roll-under", "meet-or-beat"] and not has_target:
		errors.append("rule '%s' compare '%s' needs a target operand" % [rid, compare])

	# crit
	if rule.has("crit"):
		_validate_crit(rule["crit"], rid, errors)

	# bands
	_validate_bands(rule.get("bands", []), rid, compare, errors, warnings)

	# postEffects
	for e in rule.get("postEffects", []):
		_validate_effect(e, "rule '%s' postEffect" % rid, errors)


static func _validate_crit(crit: Variant, rid: String, errors: Array[String]) -> void:
	if typeof(crit) != TYPE_DICTIONARY:
		errors.append("rule '%s' crit is not an object" % rid)
		return
	var mode := str(crit.get("mode", "none"))
	if mode not in CRIT_MODES:
		errors.append("rule '%s' crit has unknown mode '%s'" % [rid, mode])
		return
	if mode == "natural" and not crit.has("low") and not crit.has("high"):
		errors.append("rule '%s' crit natural needs a 'low' and/or 'high' result" % rid)
	if mode == "doubles":
		var has_low: bool = crit.has("lowValue") and crit.has("lowResult")
		var has_high: bool = crit.has("highValue") and crit.has("highResult")
		if not has_low and not has_high:
			errors.append("rule '%s' crit doubles needs lowValue+lowResult and/or highValue+highResult" % rid)


static func _validate_bands(bands: Variant, rid: String, compare: String, errors: Array[String], warnings: Array[String]) -> void:
	if typeof(bands) != TYPE_ARRAY or (bands as Array).is_empty():
		errors.append("rule '%s' needs a non-empty 'bands' list" % rid)
		return
	var seen_id: Dictionary = {}
	var is_threshold := compare == "threshold-bands"
	var range_count := 0
	for k in (bands as Array).size():
		var b: Variant = bands[k]
		if typeof(b) != TYPE_DICTIONARY:
			errors.append("rule '%s' bands[%d] is not an object" % [rid, k])
			continue
		var bid := str(b.get("id", ""))
		if bid == "":
			errors.append("rule '%s' bands[%d] has no 'id'" % [rid, k])
		elif seen_id.has(bid):
			errors.append("rule '%s' band id '%s' is duplicated" % [rid, bid])
		seen_id[bid] = true
		var is_range: bool = b.has("min") or b.has("max")
		if is_range:
			range_count += 1
			if b.has("min") and not _is_number(b["min"]):
				errors.append("rule '%s' band '%s' min is not numeric" % [rid, bid])
			if b.has("max") and not _is_number(b["max"]):
				errors.append("rule '%s' band '%s' max is not numeric" % [rid, bid])
		elif b.has("when"):
			if str(b["when"]) not in BINARY_WHENS:
				errors.append("rule '%s' band '%s' when '%s' is not one of %s" % [rid, bid, b["when"], str(BINARY_WHENS)])
	if is_threshold and range_count == 0:
		errors.append("rule '%s' compare threshold-bands needs at least one min/max range band" % rid)
	if not is_threshold and range_count > 0:
		warnings.append("rule '%s' has range bands but compare is '%s' (ranges only apply to threshold-bands)" % [rid, compare])


static func _validate_portability(port: Variant, attr_keys: Array[String], rule_ids: Array[String], errors: Array[String], warnings: Array[String]) -> void:
	if typeof(port) != TYPE_DICTIONARY:
		errors.append("'portability' is not an object")
		return
	var p: Dictionary = port

	# attributeMap: canonical -> native attribute
	var amap: Dictionary = p.get("attributeMap", {})
	for canon in amap.keys():
		if str(canon) not in IFPortableCheck.CANONICAL_ATTRIBUTES:
			warnings.append("portability.attributeMap key '%s' is not a canonical attribute" % canon)
		if str(amap[canon]) not in attr_keys:
			errors.append("portability.attributeMap '%s' -> '%s' is not a declared attribute" % [canon, amap[canon]])

	# outcomeMap: native band -> canonical band
	var omap: Dictionary = p.get("outcomeMap", {})
	for native in omap.keys():
		if str(omap[native]) not in IFPortableCheck.CANONICAL_BANDS:
			errors.append("portability.outcomeMap '%s' -> '%s' is not a canonical band" % [native, omap[native]])

	# semantics: each maps a canonical semantic onto a native rule
	var sems: Dictionary = p.get("semantics", {})
	if sems.is_empty():
		warnings.append("portability has no 'semantics' (portable checks cannot resolve under this system)")
	for sid in sems.keys():
		var sdef: Variant = sems[sid]
		if typeof(sdef) != TYPE_DICTIONARY:
			errors.append("portability.semantics['%s'] is not an object" % sid)
			continue
		var rule_id := str(sdef.get("rule", ""))
		if rule_id == "":
			errors.append("portability.semantics['%s'] has no 'rule'" % sid)
		elif rule_id not in rule_ids:
			errors.append("portability.semantics['%s'] rule '%s' is not a declared resolution rule" % [sid, rule_id])
		if sdef.has("difficulty"):
			var ddef: Dictionary = sdef["difficulty"]
			var mode := str(ddef.get("mode", ""))
			if mode not in DIFFICULTY_MODES:
				errors.append("portability.semantics['%s'] difficulty mode '%s' is not one of %s" % [sid, mode, str(DIFFICULTY_MODES)])
			var ladder: Dictionary = ddef.get("ladder", {})
			if ladder.is_empty():
				errors.append("portability.semantics['%s'] difficulty has an empty ladder" % sid)
			for rung in ladder.keys():
				if not _is_number(ladder[rung]):
					errors.append("portability.semantics['%s'] ladder rung '%s' is not numeric" % [sid, rung])
			for rung in IFPortableCheck.CANONICAL_DIFFICULTIES:
				if not ladder.has(rung):
					warnings.append("portability.semantics['%s'] ladder is missing difficulty rung '%s'" % [sid, rung])


static func _validate_effect(eff: Variant, ctx: String, errors: Array[String]) -> void:
	if typeof(eff) != TYPE_DICTIONARY:
		errors.append("%s is not an object" % ctx)
		return
	var kind := str(eff.get("kind", ""))
	if kind not in EFFECT_KINDS:
		errors.append("%s has unknown kind '%s'" % [ctx, kind])


static func _check_bounds(ctx: String, d: Dictionary, errors: Array[String]) -> void:
	var has_min: bool = d.has("min") and _is_number(d["min"])
	var has_max: bool = d.has("max") and _is_number(d["max"])
	if d.has("min") and not _is_number(d["min"]):
		errors.append("%s min is not numeric" % ctx)
	if d.has("max") and not _is_number(d["max"]):
		errors.append("%s max is not numeric" % ctx)
	if has_min and has_max and float(d["min"]) > float(d["max"]):
		errors.append("%s has min %s > max %s" % [ctx, d["min"], d["max"]])
	if d.has("default") and _is_number(d["default"]):
		var v := float(d["default"])
		if has_min and v < float(d["min"]):
			errors.append("%s default %s is below min %s" % [ctx, v, d["min"]])
		if has_max and v > float(d["max"]):
			errors.append("%s default %s is above max %s" % [ctx, v, d["max"]])


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _result(errors: Array[String], warnings: Array[String], ruleset: IFRuleset) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"ruleset": ruleset,
	}
