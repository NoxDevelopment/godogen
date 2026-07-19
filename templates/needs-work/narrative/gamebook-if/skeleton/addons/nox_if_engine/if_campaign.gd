class_name IFCampaign
extends RefCounted
## res://addons/nox_if_engine/if_campaign.gd
## A CAMPAIGN (spec P1) — the LONG-RUNNING container. An ordered, linked set of
## modules with a persistent world/campaign store and a carried roster of
## characters, progressing module-to-module (finish module 1 -> module 2 -> ...).
## This is the DISTINCT counterpart to IFOneOff: a campaign owns long-term state
## (campaign vars + flags + roster + progress) and its own management surface,
## where a one-off owns none of that. Both drive the same P0 engine per module;
## the difference is everything AROUND a single module's play.
##
## Shape (`campaign.json`):
##   {
##     id, name, type:"campaign", version?, meta:{...},
##     ruleset: "ff-2d6",
##     seed: <int>,                            # campaign master seed
##     campaignVars:  { "world.embers":0, ... }, campaignFlags:{...},   # long-term defaults
##     roster: [ { slot:"knight", character:{...}|characterRef } ],
##     start: "<moduleId>",
##     modules: [
##       { moduleId, order, protagonist:"<slot>", module:{...}|moduleRef,
##         next?: { onComplete:"<moduleId>" } }
##     ]
##   }
## `roster` characters are bound to module `protagonist` slots by slot id; the
## protagonist's sheet drives that module's engine, the rest are carried.

var id: String = ""
var name: String = ""
var version: String = ""
var meta: Dictionary = {}
var ruleset_id: String = ""
var seed: int = 0

var campaign_vars: Dictionary = {}
var campaign_flags: Dictionary = {}

## slot id -> IFCharacter (the authored starting roster).
var roster: Dictionary = {}
var roster_order: Array[String] = []

var start_module_id: String = ""

## moduleId -> { order, protagonist, module:IFModule, next:{...} }
var modules: Dictionary = {}
var module_order: Array[String] = []

var _raw: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		load_from(data)


static func from_file(path: String) -> IFCampaign:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("IFCampaign: could not read '%s'" % path)
		return IFCampaign.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("IFCampaign: '%s' is not a JSON object" % path)
		return IFCampaign.new()
	return IFCampaign.new(parsed)


func load_from(data: Dictionary) -> void:
	_raw = data
	id = str(data.get("id", ""))
	name = str(data.get("name", id))
	version = str(data.get("version", ""))
	meta = data.get("meta", {})
	ruleset_id = str(data.get("ruleset", ""))
	seed = int(data.get("seed", 0))
	campaign_vars = (data.get("campaignVars", {}) as Dictionary).duplicate(true)
	campaign_flags = (data.get("campaignFlags", {}) as Dictionary).duplicate(true)

	roster.clear()
	roster_order.clear()
	for entry in data.get("roster", []):
		var slot := str(entry.get("slot", ""))
		if slot == "":
			push_warning("IFCampaign '%s': roster entry with no slot" % id)
			continue
		roster[slot] = IFCharacter.resolve(entry)
		roster_order.append(slot)

	modules.clear()
	module_order.clear()
	var ordered: Array = data.get("modules", []).duplicate()
	ordered.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for m in ordered:
		var mid := str(m.get("moduleId", ""))
		if mid == "":
			push_warning("IFCampaign '%s': module entry with no moduleId" % id)
			continue
		modules[mid] = {
			"order": int(m.get("order", module_order.size() + 1)),
			"protagonist": str(m.get("protagonist", "")),
			"module": IFModule.resolve(m),
			"next": m.get("next", {}),
		}
		module_order.append(mid)

	start_module_id = str(data.get("start", module_order[0] if not module_order.is_empty() else ""))


func has_module(module_id: String) -> bool:
	return modules.has(module_id)


func module_entry(module_id: String) -> Dictionary:
	return modules.get(module_id, {})


func module_of(module_id: String) -> IFModule:
	return modules.get(module_id, {}).get("module", null)


## The module that follows `module_id` on completion: an explicit `next.onComplete`
## link, else the next module in `order`. "" when the campaign ends here.
func next_module_after(module_id: String) -> String:
	var entry := module_entry(module_id)
	var nxt: Dictionary = entry.get("next", {})
	if nxt.has("onComplete"):
		return str(nxt["onComplete"])
	var idx := module_order.find(module_id)
	if idx >= 0 and idx + 1 < module_order.size():
		return module_order[idx + 1]
	return ""


## The protagonist slot a module runs on (module entry override, else the module's
## own declared protagonist slot).
func protagonist_for(module_id: String) -> String:
	var entry := module_entry(module_id)
	var slot := str(entry.get("protagonist", ""))
	if slot != "":
		return slot
	var m: IFModule = entry.get("module", null)
	if m != null:
		return m.protagonist_slot()
	return ""


func validate(ruleset: IFRuleset = null) -> Array[String]:
	var problems: Array[String] = []
	if id == "":
		problems.append("campaign has no id")
	if str(_raw.get("type", "campaign")) != "campaign":
		problems.append("campaign '%s' has type '%s' (expected 'campaign')" % [id, _raw.get("type")])
	if ruleset_id == "":
		problems.append("campaign '%s' names no ruleset" % id)
	if module_order.is_empty():
		problems.append("campaign '%s' has no modules" % id)
	if start_module_id == "" or not has_module(start_module_id):
		problems.append("campaign '%s' start module '%s' missing" % [id, start_module_id])
	for mid in module_order:
		var m: IFModule = module_of(mid)
		if m == null:
			problems.append("campaign '%s' module '%s' failed to load" % [id, mid])
			continue
		if m.ruleset_id != "" and ruleset_id != "" and m.ruleset_id != ruleset_id:
			problems.append("campaign '%s' module '%s' ruleset '%s' != campaign ruleset '%s'" % [id, mid, m.ruleset_id, ruleset_id])
		for p in m.validate(ruleset):
			problems.append("campaign '%s': %s" % [id, p])
		# The protagonist slot must exist in the roster.
		var slot := protagonist_for(mid)
		if slot != "" and not roster.has(slot):
			problems.append("campaign '%s' module '%s' protagonist slot '%s' not in roster" % [id, mid, slot])
		# next.onComplete must point somewhere real.
		var nxt := str(module_entry(mid).get("next", {}).get("onComplete", ""))
		if nxt != "" and not has_module(nxt):
			problems.append("campaign '%s' module '%s' next -> missing module '%s'" % [id, mid, nxt])
	return problems


func raw() -> Dictionary:
	return _raw
