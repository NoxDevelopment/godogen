class_name IFResolver
extends RefCounted
## res://addons/nox_if_engine/if_resolver.gd
## THE generic rule engine (spec §2.5). A resolution rule is DATA; this
## interpreter turns any such rule into an outcome. It is what lets ONE engine
## express every resolution family — the `compare` mode + `bands` are the knobs:
##
##   * roll-under  (FF 2d6)  : total <= target  -> success / failure
##   * meet-or-beat (d20+mod): total >= target  -> failure / success (+ crits)
##   * threshold-bands (PbtA): total mapped into numeric [min..max] bands
##
## A resolution rule (lives in a ruleset's `resolutionRules[]`):
##   {
##     id, label,
##     dice: "2d6",                       # overridable per call via args.dice
##     operands: [                        # each contributes a target or a modifier
##        { type, ref?, value?, role, transform? }
##     ],
##     compare: "roll-under"|"meet-or-beat"|"threshold-bands",
##     crit:    { mode, ... }?            # optional critical override
##     bands:   [ { id, when|min|max, label } ],   # labelled OUTCOMES (system-level)
##     postEffects: [ <effect> ]?         # applied to state after every resolution
##                                        #   (e.g. FF LUCK attrition)
##   }
##
## Operand types (the abstraction that unifies the families):
##   attribute     -> state.get_attr(ref)                 (SKILL)
##   attributeArg  -> state.get_attr(args[ref])           ($attr picked at call site)
##   resource      -> state.get_resource(ref)
##   var           -> state.get_var(ref)
##   param         -> float(args[ref] ?? default)         (a DC supplied by the scene)
##   const         -> value
## Operand role:  "target" (compared against) | "modifier" (added to the total).
## Operand transform: "none" | "abilityMod"  (floor((v-10)/2) — d20 ability mod).
##
## Bands are SYSTEM-level labelled outcomes ("success"/"failure"/"partial"...).
## What each outcome DOES in a given story (route + effects) is CONTENT and lives
## on the scenario's check node — see if_runner.gd. This keeps rulesets pure and
## reusable across every scenario.

var ruleset: IFRuleset
var dice: IFDice


func _init(rs: IFRuleset, d: IFDice) -> void:
	ruleset = rs
	dice = d


## Resolve `rule` against `state`, with optional `args` from the scenario's check
## node (e.g. {attr:"SKILL"} or {dc:14}). Records the result into state.roll_log
## and applies the rule's postEffects. Returns the full result dict:
##   { rule, label, dice, faces, sum, modifier, total, target, compare,
##     success (bool|null), crit ("" | "success" | "fail"), band, band_label }
func resolve(rule: Dictionary, state: IFState, args: Dictionary = {}) -> Dictionary:
	var expr := str(args.get("dice", rule.get("dice", ruleset.dice_default)))
	var roll := dice.roll(expr)

	var target: Variant = null
	var modifier := 0.0
	for op in rule.get("operands", []):
		var v := _operand_value(op, state, args)
		var role := str(op.get("role", "target"))
		if role == "modifier":
			modifier += v
		else:
			target = v

	var total := float(roll.total) + modifier
	var compare := str(rule.get("compare", "meet-or-beat"))

	# Critical override (evaluated on the raw faces, before/over the arithmetic).
	var crit := _eval_crit(rule.get("crit", {}), roll)

	var success: Variant = null
	match compare:
		"roll-under":
			success = target != null and total <= float(target)
		"meet-or-beat":
			success = target != null and total >= float(target)
		"threshold-bands":
			success = null   # bands carry the outcome, not a binary
		_:
			push_error("IFResolver: unknown compare mode '%s'" % compare)
			success = false

	# Criticals force the binary outcome (a nat-20 hits, double-6 fumbles).
	if crit == "success":
		success = true
	elif crit == "fail":
		success = false

	var band := _pick_band(rule.get("bands", []), success, crit, total)

	var result := {
		"rule": str(rule.get("id", "")),
		"label": str(rule.get("label", rule.get("id", ""))),
		"dice": expr,
		"faces": roll.faces,
		"sum": roll.sum,
		"modifier": modifier,
		"total": total,
		"target": target,
		"compare": compare,
		"success": success,
		"crit": crit,
		"band": str(band.get("id", "")),
		"band_label": str(band.get("label", band.get("id", ""))),
	}

	state.record_roll(result)
	# Rule-level side effects (any outcome) — FF "testing your luck erodes it".
	state.apply_effects(rule.get("postEffects", []))
	return result


func _operand_value(op: Dictionary, state: IFState, args: Dictionary) -> float:
	var v := 0.0
	match str(op.get("type", "const")):
		"attribute":
			v = state.get_attr(str(op.get("ref", "")))
		"attributeArg":
			v = state.get_attr(str(args.get(str(op.get("ref", "")), "")))
		"resource":
			v = state.get_resource(str(op.get("ref", "")))
		"var":
			v = state.get_var(str(op.get("ref", "")))
		"param":
			v = float(args.get(str(op.get("ref", "")), op.get("default", 0)))
		"const":
			v = float(op.get("value", 0))
		_:
			push_warning("IFResolver: unknown operand type '%s'" % op.get("type"))
	return _transform(str(op.get("transform", "none")), v)


func _transform(kind: String, v: float) -> float:
	match kind:
		"none":
			return v
		"abilityMod":
			# D&D-style ability modifier: floor((score - 10) / 2).
			return floorf((v - 10.0) / 2.0)
		"negate":
			return -v
		_:
			push_warning("IFResolver: unknown transform '%s'" % kind)
			return v


## Critical rules, as data. Returns "" | "success" | "fail".
##   { mode: "none" }
##   { mode: "natural", low: "fail",    high: "success" }   # d20 nat1/nat20
##   { mode: "doubles", lowValue: 1, lowResult: "success",  # FF double-1 always
##                      highValue: 6, highResult: "fail" }   #    double-6 always
func _eval_crit(crit: Dictionary, roll: Dictionary) -> String:
	if crit.is_empty():
		return ""
	var faces: Array = roll.faces
	match str(crit.get("mode", "none")):
		"none":
			return ""
		"natural":
			# Single-die naturals (uses the first/only die).
			if faces.is_empty():
				return ""
			var f := int(faces[0])
			if f == 1 and crit.has("low"):
				return str(crit["low"])
			if f == int(roll.sides) and crit.has("high"):
				return str(crit["high"])
			return ""
		"doubles":
			if faces.size() < 2:
				return ""
			var all_same := true
			for i in range(1, faces.size()):
				if int(faces[i]) != int(faces[0]):
					all_same = false
					break
			if not all_same:
				return ""
			var val := int(faces[0])
			if crit.has("lowValue") and val == int(crit["lowValue"]):
				return str(crit.get("lowResult", ""))
			if crit.has("highValue") and val == int(crit["highValue"]):
				return str(crit.get("highResult", ""))
			return ""
		_:
			push_warning("IFResolver: unknown crit mode '%s'" % crit.get("mode"))
			return ""


## Choose the outcome band. Threshold bands (any band with min/max) map the
## total into a numeric range; otherwise binary bands match on `when` with crits
## preferred over their plain counterparts.
func _pick_band(bands: Array, success: Variant, crit: String, total: float) -> Dictionary:
	if bands.is_empty():
		return {"id": "", "label": ""}

	var is_range := false
	for b in bands:
		if b.has("min") or b.has("max"):
			is_range = true
			break

	if is_range:
		for b in bands:
			var lo := float(b.get("min", -INF))
			var hi := float(b.get("max", INF))
			if total >= lo and total <= hi:
				return b
		return bands[bands.size() - 1]

	# Binary bands, most-specific outcome first.
	var wants: Array[String] = []
	if crit == "success":
		wants = ["critSuccess", "success"]
	elif crit == "fail":
		wants = ["critFail", "fail"]
	elif success == true:
		wants = ["success"]
	else:
		wants = ["fail"]
	for w in wants:
		for b in bands:
			if str(b.get("when", "")) == w:
				return b
	return bands[0]
