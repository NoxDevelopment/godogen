class_name IFRuleset
extends RefCounted
## res://addons/nox_if_engine/if_ruleset.gd
## A ruleset is DATA, not code (spec §2.5). This class is the typed reader over
## one ruleset dict — it never hardcodes a system. Swapping the dict reskins ALL
## resolution: attributes, resources, the character-sheet template, the dice
## defaults and the resolution rules the interpreter walks.
##
## Shape (`ruleset.json`):
##   {
##     id, name,
##     meta:            { family, license, degreesOfSuccess:[...] , advancement? },
##     dice:            { default: "2d6" },
##     attributes:      [ { key, label, gen:"1d6+6", min, max } ],
##     resources:       [ { key, label, default, min, max?, from? , trackMax? } ],
##     sheetTemplate:   { attributes:[keys], resources:[keys], inventory:bool },
##     resolutionRules: [ <resolution rule>, ... ]     # see if_resolver.gd
##   }
##
## `attributes` are the stats a check reads (SKILL/LUCK/STAMINA). `resources` are
## depletable pools (STAMINA hit-points, provisions, PbtA tokens). A resource may
## mirror an attribute's roll as its starting max via `from` (FF STAMINA is both a
## checkable attribute AND the hp pool). This is the generalization of the
## ff-gamebook adventure sheet (character_sheet.gd) into system-defined data.

var id: String = ""
var name: String = ""
var meta: Dictionary = {}
var dice_default: String = "1d6"

## key -> attribute def dict.
var attributes: Dictionary = {}
## Ordered attribute keys (sheet display order).
var attribute_order: Array[String] = []

## key -> resource def dict.
var resources: Dictionary = {}
var resource_order: Array[String] = []

var sheet_template: Dictionary = {}

## id -> resolution rule dict.
var rules: Dictionary = {}

var _raw: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		load_from(data)


## Load a Godot resource path (res://.../ff-2d6.json) into a ruleset.
static func from_file(path: String) -> IFRuleset:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("IFRuleset: could not read '%s'" % path)
		return IFRuleset.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("IFRuleset: '%s' is not a JSON object" % path)
		return IFRuleset.new()
	return IFRuleset.new(parsed)


func load_from(data: Dictionary) -> void:
	_raw = data
	id = str(data.get("id", ""))
	name = str(data.get("name", id))
	meta = data.get("meta", {})
	dice_default = str(data.get("dice", {}).get("default", "1d6"))

	attributes.clear()
	attribute_order.clear()
	for a in data.get("attributes", []):
		var key := str(a.get("key", ""))
		if key == "":
			continue
		attributes[key] = a
		attribute_order.append(key)

	resources.clear()
	resource_order.clear()
	for r in data.get("resources", []):
		var key := str(r.get("key", ""))
		if key == "":
			continue
		resources[key] = r
		resource_order.append(key)

	sheet_template = data.get("sheetTemplate", {
		"attributes": attribute_order.duplicate(),
		"resources": resource_order.duplicate(),
		"inventory": true,
	})

	rules.clear()
	for rule in data.get("resolutionRules", []):
		var rid := str(rule.get("id", ""))
		if rid == "":
			continue
		rules[rid] = rule


func has_attribute(key: String) -> bool:
	return attributes.has(key)


func attribute_bounds(key: String) -> Dictionary:
	var a: Dictionary = attributes.get(key, {})
	return {
		"min": a.get("min", -INF),
		"max": a.get("max", INF),
	}


func has_resource(key: String) -> bool:
	return resources.has(key)


func resource_def(key: String) -> Dictionary:
	return resources.get(key, {})


func rule(rule_id: String) -> Dictionary:
	if not rules.has(rule_id):
		push_error("IFRuleset '%s': no resolution rule '%s'" % [id, rule_id])
		return {}
	return rules[rule_id]


## Roll a fresh sheet from the attribute `gen` expressions + resource defaults —
## the system-defined version of character_sheet.gd's roll_new_character(). The
## returned dict feeds IFState.init_sheet(). A resource with `from: <attr>` takes
## that attribute's rolled value as its starting value/max (FF STAMINA).
func generate_sheet(dice: IFDice) -> Dictionary:
	var attr_values: Dictionary = {}
	for key in attribute_order:
		var a: Dictionary = attributes[key]
		var gen := str(a.get("gen", ""))
		var value: float
		if gen == "":
			value = float(a.get("default", 0))
		else:
			value = float(dice.roll(gen).total)
		value = _clamp_attr(a, value)
		attr_values[key] = value

	var res_values: Dictionary = {}
	var res_max: Dictionary = {}
	for key in resource_order:
		var r: Dictionary = resources[key]
		var value: float
		if r.has("from") and attr_values.has(str(r["from"])):
			value = attr_values[str(r["from"])]
		else:
			value = float(r.get("default", 0))
		res_values[key] = value
		if bool(r.get("trackMax", false)):
			res_max[key] = value

	return {
		"attributes": attr_values,
		"resources": res_values,
		"resource_max": res_max,
	}


func _clamp_attr(a: Dictionary, value: float) -> float:
	if a.has("min"):
		value = maxf(value, float(a["min"]))
	if a.has("max"):
		value = minf(value, float(a["max"]))
	return value


func raw() -> Dictionary:
	return _raw
