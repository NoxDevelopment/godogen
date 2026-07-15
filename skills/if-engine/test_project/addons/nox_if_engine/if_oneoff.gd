class_name IFOneOff
extends RefCounted
## res://addons/nox_if_engine/if_oneoff.gd
## A ONE-OFF adventure (spec P1) — the QUICK front door. A single self-contained
## module, minimal setup, played straight through to an ending. There is NO
## long-running store, NO progression, NO carried roster: one module, one seed,
## one optional character in the protagonist slot, done. This is a DELIBERATELY
## DISTINCT object from IFCampaign (the spec's "separate one-off vs campaign
## flows" decision) even though both run on the same P0 engine underneath — the
## shapes and the runner entry points differ so the two UX paths never entangle.
##
## Shape (`adventure.json`, one-off):
##   {
##     id, name, type:"oneoff", meta:{...},
##     ruleset: "ff-2d6",                 # optional; defaults to the module's
##     seed: <int>,                       # deterministic play seed
##     module: { <module.json> } | moduleRef:"res://...",
##     character: { <character.json> } | characterRef:"res://..."   # optional
##   }
## If no character is supplied the module's scenario sheet (fixed or generated)
## is used, exactly as in P0.

var id: String = ""
var name: String = ""
var meta: Dictionary = {}
var ruleset_id: String = ""
var seed: int = 0

var module: IFModule
var character: IFCharacter          # may be an empty IFCharacter (none supplied)
var has_character: bool = false

var _raw: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		load_from(data)


static func from_file(path: String) -> IFOneOff:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("IFOneOff: could not read '%s'" % path)
		return IFOneOff.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("IFOneOff: '%s' is not a JSON object" % path)
		return IFOneOff.new()
	return IFOneOff.new(parsed)


func load_from(data: Dictionary) -> void:
	_raw = data
	id = str(data.get("id", ""))
	name = str(data.get("name", id))
	meta = data.get("meta", {})
	seed = int(data.get("seed", 0))

	module = IFModule.resolve(data)
	ruleset_id = str(data.get("ruleset", module.ruleset_id))

	if data.has("character") or data.has("characterRef"):
		character = IFCharacter.resolve(data)
		has_character = true
	else:
		character = IFCharacter.new()
		has_character = false


func validate(ruleset: IFRuleset = null) -> Array[String]:
	var problems: Array[String] = []
	if id == "":
		problems.append("one-off has no id")
	if str(_raw.get("type", "oneoff")) != "oneoff":
		problems.append("one-off '%s' has type '%s' (expected 'oneoff')" % [id, _raw.get("type")])
	if module == null:
		problems.append("one-off '%s' has no module" % id)
	else:
		for p in module.validate(ruleset):
			problems.append("one-off '%s': %s" % [id, p])
		if ruleset_id != "" and module.ruleset_id != "" and ruleset_id != module.ruleset_id:
			problems.append("one-off '%s' ruleset '%s' != module ruleset '%s'" % [id, ruleset_id, module.ruleset_id])
	return problems


func raw() -> Dictionary:
	return _raw
