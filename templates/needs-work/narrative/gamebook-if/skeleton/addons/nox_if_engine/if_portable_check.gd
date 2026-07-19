class_name IFPortableCheck
extends RefCounted
## res://addons/nox_if_engine/if_portable_check.gd
## THE ruleset-portability layer (spec §2.5, P2) — the abstraction that lets ONE
## scenario run under EVERY system. It is the counterpart to IFResolver: the
## resolver runs a system's OWN rule; this compiler lets a scenario name a check
## in a system-AGNOSTIC "interlingua" and have each ruleset express it in its own
## resolution math.
##
## A scenario's check node comes in two shapes, and the Runner dispatches on which:
##
##   * NATIVE (P0/P1, still supported):
##       { "rule":"test", "args":{attr:"SKILL"}, "outcomes":{ <nativeBand>: {...} } }
##     Tied to one ruleset's rule id + native attributes + native band ids.
##
##   * PORTABLE (P2, new):
##       { "semantic":"skill-test", "attribute":"prowess", "difficulty":"hard",
##         "outcomes":{ <canonicalBand>: {effects,goto}, _default: {...} } }
##     Names a SEMANTIC, a CANONICAL attribute, a CANONICAL difficulty and routes
##     on CANONICAL outcome bands. Carries NO ruleset. The same node resolves under
##     ff-2d6, srd-d20, pbta or any user system that declares a `portability` block.
##
## The interlingua (the three canonical vocabularies below) is fixed by the engine;
## each ruleset's `portability` block (see if_ruleset.gd) maps it onto native
## attributes, a native resolution rule, a per-system difficulty ladder and native
## outcome bands. Story routing NEVER moves into the ruleset — it stays on the
## scenario's `outcomes{ band -> {effects, goto} }`, exactly as for native checks.
##
## compile() turns a portable check into a concrete { rule, args } the ordinary
## IFResolver runs; canonical_band()/resolve_outcome() map the native result back
## to a canonical band and pick the routed outcome (with a documented fallback
## ladder so a binary system routes a coarse scenario sensibly, and a scenario that
## only authors success/failure still handles a system that produces a partial).

# --- The interlingua: three fixed canonical vocabularies --------------------

## Canonical ATTRIBUTES a portable check may name. Each ruleset maps every one of
## these onto a native attribute key (its `portability.attributeMap`). Six broad
## axes chosen to fold cleanly onto 3-stat (FF), 6-stat (d20) and 5-stat (PbtA)
## systems alike.
const CANONICAL_ATTRIBUTES: Array[String] = [
	"prowess",   # fighting / physical skill
	"agility",   # finesse / speed / reflexes
	"might",     # raw power / toughness / endurance
	"wits",      # intellect / perception / cunning
	"presence",  # social force / charm / command
	"resolve",   # willpower / nerve / luck
]

## Canonical DIFFICULTY rungs (ordinal, easy -> hard). Each ruleset maps every rung
## to a per-system number via its semantic's `difficulty.ladder` — a DC for d20, a
## roll-under target delta for FF, a forward/ongoing roll modifier for PbtA.
const CANONICAL_DIFFICULTIES: Array[String] = [
	"trivial", "easy", "standard", "hard", "formidable", "heroic",
]

## Canonical OUTCOME bands a scenario routes on. A ruleset's native bands are
## mapped onto these by its `portability.outcomeMap`.
const CANONICAL_BANDS: Array[String] = [
	"critSuccess", "success", "partial", "failure", "critFailure",
]

## Routing fallback ladder — when a resolved canonical band is not explicitly
## authored in the scenario's `outcomes`, try these in order, then `_default`.
## This is the crux of "routes sensibly across systems":
##   * a natural crit falls back to its plain success/failure branch;
##   * a PARTIAL (success-at-a-cost) falls back to the success branch — a
##     scenario that only distinguishes success/failure treats a PbtA 7-9 as
##     forward progress rather than a failure. (Documented design decision.)
## Binary systems (FF, d20) never PRODUCE `partial`, so a scenario that authors a
## `partial` branch simply won't reach it under them — the honest behaviour of a
## system that has no mixed result.
const BAND_FALLBACK: Dictionary = {
	"critSuccess": ["critSuccess", "success"],
	"success": ["success"],
	"partial": ["partial", "success"],
	"failure": ["failure"],
	"critFailure": ["critFailure", "failure"],
}


## Is this check node the portable shape (names a `semantic`)? A node with a
## `rule` is native. A node with neither is malformed (validator flags it).
static func is_portable(check: Variant) -> bool:
	return typeof(check) == TYPE_DICTIONARY and check.has("semantic")


## Compile a portable check into a concrete resolver call for `ruleset`:
##   { ok: bool, error: String, rule: "<ruleId>", args: {...}, semantic: "..." }
## `args` is ready to hand to IFResolver.resolve(rule, state, args): the mapped
## native attribute under the semantic's `attrArg`, the difficulty applied per the
## semantic's `mode` (a `dc` param, a `_targetDelta` or a `_rollModifier`), plus
## any static/explicit passthrough args. Errors are clear + specific.
static func compile(check: Dictionary, ruleset: IFRuleset) -> Dictionary:
	var semantic := str(check.get("semantic", ""))
	if semantic == "":
		return _err("portable check has no 'semantic'")
	if ruleset == null:
		return _err("no ruleset supplied to compile semantic '%s'" % semantic)
	if not ruleset.has_semantic(semantic):
		return _err("ruleset '%s' declares no mapping for semantic '%s'" % [ruleset.id, semantic])

	var sdef := ruleset.semantic_def(semantic)
	var rule_id := str(sdef.get("rule", ""))
	if rule_id == "" or not ruleset.rules.has(rule_id):
		return _err("semantic '%s' -> unknown resolution rule '%s' in ruleset '%s'" % [semantic, rule_id, ruleset.id])

	var args: Dictionary = {}

	# 1) static args the semantic always supplies (e.g. a fixed dice override).
	for k in sdef.get("args", {}).keys():
		args[k] = sdef["args"][k]

	# 2) the canonical attribute -> this system's native attribute.
	var canon_attr := str(check.get("attribute", ""))
	if canon_attr != "":
		if canon_attr not in CANONICAL_ATTRIBUTES:
			return _err("unknown canonical attribute '%s'" % canon_attr)
		var native := ruleset.native_attribute_for(canon_attr)
		if native == "":
			return _err("ruleset '%s' does not map canonical attribute '%s'" % [ruleset.id, canon_attr])
		if not ruleset.has_attribute(native):
			return _err("ruleset '%s' attributeMap '%s'->'%s' names a non-attribute" % [ruleset.id, canon_attr, native])
		var attr_arg := str(sdef.get("attrArg", ""))
		if attr_arg != "":
			args[attr_arg] = native

	# 3) the canonical difficulty -> a per-system number, applied by mode.
	var diff := str(check.get("difficulty", "standard"))
	var ddef: Dictionary = sdef.get("difficulty", {})
	if not ddef.is_empty():
		if diff not in CANONICAL_DIFFICULTIES:
			return _err("unknown canonical difficulty '%s'" % diff)
		var ladder: Dictionary = ddef.get("ladder", {})
		if not ladder.has(diff):
			return _err("semantic '%s' difficulty ladder has no rung '%s' in ruleset '%s'" % [semantic, diff, ruleset.id])
		var value := float(ladder[diff])
		match str(ddef.get("mode", "")):
			"dc":
				args[str(ddef.get("arg", "dc"))] = value
			"targetDelta":
				args["_targetDelta"] = value
			"rollModifier":
				args["_rollModifier"] = value
			_:
				return _err("semantic '%s' has unknown difficulty mode '%s'" % [semantic, ddef.get("mode")])

	# 4) explicit per-call passthrough on the check itself (advanced; e.g. dice).
	for k in check.get("args", {}).keys():
		args[k] = check["args"][k]

	return {"ok": true, "error": "", "rule": rule_id, "args": args, "semantic": semantic}


## Map a native band id (what IFResolver returned for this system) to a canonical
## band, via the ruleset's outcomeMap.
static func canonical_band(native_band: String, ruleset: IFRuleset) -> String:
	return ruleset.canonical_band_for(native_band)


## Pick the scenario outcome for a resolved canonical band, applying the fallback
## ladder then `_default`. Returns {} if nothing matches (validator prevents this).
static func resolve_outcome(outcomes: Dictionary, canon_band: String) -> Dictionary:
	var chain: Array = BAND_FALLBACK.get(canon_band, [canon_band])
	for b in chain:
		if outcomes.has(b):
			return outcomes[b]
	if outcomes.has("_default"):
		return outcomes["_default"]
	return {}


## Structural validation of a portable check against a ruleset (used by the
## scenario validator). Returns human-readable problems ([] == valid). When
## `ruleset` is null only shape-level checks run (semantic/attribute/difficulty in
## the canonical vocabularies); with a ruleset, the mapping is cross-checked.
static func validate(check: Dictionary, pid: String, ruleset: IFRuleset) -> Array[String]:
	var problems: Array[String] = []
	var semantic := str(check.get("semantic", ""))
	if semantic == "":
		problems.append("passage '%s' portable check has no 'semantic'" % pid)
		return problems

	var canon_attr := str(check.get("attribute", ""))
	if canon_attr != "" and canon_attr not in CANONICAL_ATTRIBUTES:
		problems.append("passage '%s' check names unknown canonical attribute '%s'" % [pid, canon_attr])
	var diff := str(check.get("difficulty", "standard"))
	if diff not in CANONICAL_DIFFICULTIES:
		problems.append("passage '%s' check names unknown canonical difficulty '%s'" % [pid, diff])

	# Outcome keys should be canonical bands (or _default).
	for band in check.get("outcomes", {}).keys():
		var b := str(band)
		if b != "_default" and b not in CANONICAL_BANDS:
			problems.append("passage '%s' outcome '%s' is not a canonical band" % [pid, b])

	# Cross-check the mapping is expressible under the supplied ruleset.
	if ruleset != null:
		var compiled := compile(check, ruleset)
		if not compiled.get("ok", false):
			problems.append("passage '%s' check: %s" % [pid, compiled.get("error", "")])
	return problems


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "rule": "", "args": {}, "semantic": ""}
