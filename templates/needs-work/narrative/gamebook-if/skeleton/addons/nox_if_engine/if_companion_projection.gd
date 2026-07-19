class_name IFCompanionProjection
extends RefCounted
## res://addons/nox_if_engine/if_companion_projection.gd
## The CONSUME-ONLY projection that turns a companion_ai_core entity (delivered as
## a companion-interchange-v1 document — see skills/companion-npcs) into a ruleset
## character sheet. This is how the SECOND character tier — "a character that IS a
## full companion" — fills a slot without the engine ever importing or editing
## companion_ai_core. We read the interchange DATA (a point-in-time projection the
## companion-npcs export already produced) and map its fields to the ruleset's
## attributes/resources with a declared, deterministic formula. Nothing here is
## random; nothing here mutates the companion.
##
## A derive spec (lives on the character's `companion.derive`):
##   {
##     attributes: {
##       <ATTR>: { base:<num>, terms:[<term>], round:"nearest"|"floor"|"ceil",
##                 min?:<num>, max?:<num> }
##     },
##     resources: {
##       <RES>: { from:"<ATTR>" } | { const:<num> } | { base, terms[], round } ,
##       ...
##     }
##   }
##   term = { path:"<dotpath>", weight:<num>, map?:{<str>:<num>}, default?:<num> }
##
## A `path` walks the interchange document by dot-segments into Dictionaries and,
## when the current node is an Array, supports aggregate segments:
##   "#max:<field>"  largest element.<field>       "#min:<field>"  smallest
##   "#avg:<field>"  mean of element.<field>        "#sum:<field>"  total
##   "#count"        array length
## e.g. "social.skills.#max:proficiency" reads the top skill proficiency (0..1),
## "personality.bigFive.conscientiousness" reads a trait (0..1). A `map` converts a
## categorical leaf (e.g. appearance.fitnessLevel "active") into a number before
## weighting. Missing paths fall back to the term's `default` (0 if unset).


## Derive a slot sheet {attributes, resources, resource_max} from an interchange
## document + a derive spec, clamped to the ruleset's attribute/resource bounds.
static func derive(interchange: Dictionary, spec: Dictionary, ruleset: IFRuleset) -> Dictionary:
	var attrs: Dictionary = {}
	var attr_specs: Dictionary = spec.get("attributes", {})
	for attr_key in attr_specs.keys():
		var s: Dictionary = attr_specs[attr_key]
		var raw := _compute(interchange, s)
		var value := _round(raw, str(s.get("round", "nearest")))
		# Clamp to the spec's own min/max first, then the ruleset's bounds.
		if s.has("min"):
			value = maxf(value, float(s["min"]))
		if s.has("max"):
			value = minf(value, float(s["max"]))
		if ruleset != null and ruleset.has_attribute(str(attr_key)):
			var b := ruleset.attribute_bounds(str(attr_key))
			value = clampf(value, float(b.min), float(b.max))
		attrs[attr_key] = value

	var res: Dictionary = {}
	var res_max: Dictionary = {}
	var res_specs: Dictionary = spec.get("resources", {})
	for res_key in res_specs.keys():
		var s: Dictionary = res_specs[res_key]
		var value: float
		if s.has("from") and attrs.has(str(s["from"])):
			value = float(attrs[str(s["from"])])
		elif s.has("const"):
			value = float(s["const"])
		else:
			value = _round(_compute(interchange, s), str(s.get("round", "nearest")))
		# Resource bounds from the ruleset (min/max).
		if ruleset != null and ruleset.has_resource(str(res_key)):
			var rd := ruleset.resource_def(str(res_key))
			if rd.has("min"):
				value = maxf(value, float(rd["min"]))
			if rd.has("max"):
				value = minf(value, float(rd["max"]))
			if bool(rd.get("trackMax", false)):
				res_max[res_key] = value
		res[res_key] = value

	return {"attributes": attrs, "resources": res, "resource_max": res_max}


static func _compute(interchange: Dictionary, s: Dictionary) -> float:
	var v := float(s.get("base", 0.0))
	for term in s.get("terms", []):
		v += _term_value(interchange, term)
	return v


static func _term_value(interchange: Dictionary, term: Dictionary) -> float:
	var weight := float(term.get("weight", 1.0))
	var resolved: Variant = _resolve(interchange, str(term.get("path", "")))
	if resolved == null:
		return weight * float(term.get("default", 0.0))
	# Categorical -> numeric via an explicit map.
	if term.has("map"):
		var m: Dictionary = term["map"]
		var mapped: Variant = m.get(str(resolved), term.get("default", 0.0))
		return weight * float(mapped)
	if typeof(resolved) == TYPE_BOOL:
		return weight * (1.0 if resolved else 0.0)
	return weight * float(resolved)


## Walk a dot-path through the interchange, with array-aggregate segments.
## Returns null if any segment cannot be resolved.
static func _resolve(root: Variant, path: String) -> Variant:
	if path == "":
		return null
	var node: Variant = root
	for seg in path.split("."):
		if node == null:
			return null
		if seg.begins_with("#"):
			node = _aggregate(node, seg)
		elif typeof(node) == TYPE_DICTIONARY:
			var d: Dictionary = node
			if not d.has(seg):
				return null
			node = d[seg]
		else:
			return null
	return node


static func _aggregate(node: Variant, seg: String) -> Variant:
	if typeof(node) != TYPE_ARRAY:
		return null
	var arr: Array = node
	if seg == "#count":
		return float(arr.size())
	var parts := seg.substr(1).split(":")   # strip '#', split "op:field"
	var op := str(parts[0])
	var field := str(parts[1]) if parts.size() > 1 else ""
	var values: Array[float] = []
	for el in arr:
		var val: Variant
		if field == "":
			val = el
		elif typeof(el) == TYPE_DICTIONARY and (el as Dictionary).has(field):
			val = (el as Dictionary)[field]
		else:
			continue
		if typeof(val) == TYPE_BOOL:
			values.append(1.0 if val else 0.0)
		else:
			values.append(float(val))
	if values.is_empty():
		return null
	match op:
		"max":
			var m := values[0]
			for x in values:
				m = maxf(m, x)
			return m
		"min":
			var m := values[0]
			for x in values:
				m = minf(m, x)
			return m
		"sum":
			var t := 0.0
			for x in values:
				t += x
			return t
		"avg":
			var t := 0.0
			for x in values:
				t += x
			return t / float(values.size())
		_:
			push_warning("IFCompanionProjection: unknown aggregate '%s'" % op)
			return null


static func _round(v: float, mode: String) -> float:
	match mode:
		"floor":
			return floorf(v)
		"ceil":
			return ceilf(v)
		_:
			return roundf(v)
