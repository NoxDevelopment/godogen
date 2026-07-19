class_name IFCharacter
extends RefCounted
## res://addons/nox_if_engine/if_character.gd
## A CHARACTER (spec P1) — the thing that fills a slot. Two tiers, one interface:
##
##   * tier "sheet"     — a LIGHTWEIGHT persistent character: its own ruleset
##                        sheet (attributes/resources), carried vars/inventory,
##                        and a cross-module history. Hand-authored or rolled.
##   * tier "companion" — a character that IS a full companion_ai_core entity,
##                        bound CONSUME-ONLY via a stable id + an interchange
##                        projection (companion-interchange v1). On first use its
##                        ruleset sheet is DERIVED from the interchange (see
##                        IFCompanionProjection) and then it behaves exactly like
##                        a sheet character — mutations persist on the overlay,
##                        never on the companion.
##
## Either way the engine treats it as "a character in a slot": to_slot_sheet()
## produces the {attributes,resources,resource_max} the IFRunner injects, and
## capture_from() reads the played IFState back into the character's persistent
## LONG-TERM state so it carries into the next module. The immutable companion
## binding (ref + interchange + derive) is kept verbatim so a re-materialisation
## or an AI-DM layer (P4) can still reach the deep entity data.
##
## Shape (`character.json`):
##   {
##     id, name, tier:"sheet"|"companion", ruleset?:"ff-2d6",
##     # persistent LONG-TERM game state (both tiers, mutated across modules):
##     sheet:  { attributes:{...}, resources:{...}, resource_max?:{...} },
##     vars:   { "char.valor":2, ... },      # character-scoped persistent vars
##     items:  { "oath_ring":1, ... },       # character-scoped inventory
##     flags:  { ... },                      # character-scoped flags
##     history:[ { module, ending, kind } ], # cross-module trail
##     # tier "companion" only — the immutable, consume-only binding:
##     companion: {
##       ref:"cmp_9f3ab2e07d41",             # stable companion id (identity.id)
##       interchange: { <companion-interchange v1 doc> } | interchangeRef,
##       derive: { attributes:{...}, resources:{...} }   # projection spec
##     }
##   }

const TIER_SHEET := "sheet"
const TIER_COMPANION := "companion"

var id: String = ""
var name: String = ""
var tier: String = TIER_SHEET
var ruleset_id: String = ""

## Persistent LONG-TERM state (the mutable overlay for BOTH tiers).
var sheet: Dictionary = {}          # {attributes, resources, resource_max}
var vars: Dictionary = {}           # char.* persistent vars
var items: Dictionary = {}          # name -> count (persistent inventory)
var flags: Dictionary = {}
var history: Array = []

## tier "companion" binding (immutable, consume-only).
var companion_ref: String = ""
var interchange: Dictionary = {}
var derive_spec: Dictionary = {}

## True once a companion's sheet has been derived (so we derive at most once, then
## persist mutations on `sheet`).
var materialized: bool = false

var _raw: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		load_from(data)


static func from_file(path: String) -> IFCharacter:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("IFCharacter: could not read '%s'" % path)
		return IFCharacter.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("IFCharacter: '%s' is not a JSON object" % path)
		return IFCharacter.new()
	return IFCharacter.new(parsed)


## Resolve an inline `character` dict or a `characterRef` res:// path.
static func resolve(container: Dictionary, inline_key: String = "character", ref_key: String = "characterRef") -> IFCharacter:
	if container.has(inline_key) and typeof(container[inline_key]) == TYPE_DICTIONARY:
		return IFCharacter.new(container[inline_key])
	if container.has(ref_key):
		return IFCharacter.from_file(str(container[ref_key]))
	push_error("IFCharacter.resolve: no '%s' or '%s' present" % [inline_key, ref_key])
	return IFCharacter.new()


func load_from(data: Dictionary) -> void:
	_raw = data
	id = str(data.get("id", ""))
	name = str(data.get("name", id))
	tier = str(data.get("tier", TIER_SHEET))
	ruleset_id = str(data.get("ruleset", ""))

	sheet = (data.get("sheet", {}) as Dictionary).duplicate(true)
	vars = (data.get("vars", {}) as Dictionary).duplicate(true)
	items = (data.get("items", {}) as Dictionary).duplicate(true)
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	history = (data.get("history", []) as Array).duplicate(true)
	materialized = bool(data.get("materialized", not sheet.is_empty()))

	var comp: Dictionary = data.get("companion", {})
	companion_ref = str(comp.get("ref", ""))
	derive_spec = comp.get("derive", {})
	# interchange may be inline or a res:// ref.
	if comp.has("interchange") and typeof(comp["interchange"]) == TYPE_DICTIONARY:
		interchange = comp["interchange"]
	elif comp.has("interchangeRef"):
		var t := FileAccess.get_file_as_string(str(comp["interchangeRef"]))
		var parsed: Variant = JSON.parse_string(t)
		if typeof(parsed) == TYPE_DICTIONARY:
			interchange = parsed
		else:
			push_error("IFCharacter '%s': bad interchangeRef" % id)


func is_companion() -> bool:
	return tier == TIER_COMPANION


## The stable id an AI-DM/NPC layer or a save uses to re-find the source entity.
## For a companion this is the interchange identity.id; for a sheet it is the id.
func stable_id() -> String:
	if is_companion() and companion_ref != "":
		return companion_ref
	return id


## Produce the slot sheet {attributes, resources, resource_max} the IFRunner
## injects. For a companion tier this DERIVES the sheet from the interchange on
## first use (consume-only) and caches it onto `sheet`; thereafter (and for a
## sheet tier) it returns the persistent, possibly-mutated sheet.
func to_slot_sheet(ruleset: IFRuleset) -> Dictionary:
	if is_companion() and not materialized:
		if interchange.is_empty() or derive_spec.is_empty():
			push_error("IFCharacter '%s': companion tier needs interchange + derive" % id)
		else:
			sheet = IFCompanionProjection.derive(interchange, derive_spec, ruleset)
			materialized = true
	return {
		"attributes": (sheet.get("attributes", {}) as Dictionary).duplicate(true),
		"resources": (sheet.get("resources", {}) as Dictionary).duplicate(true),
		"resource_max": (sheet.get("resource_max", {}) as Dictionary).duplicate(true),
	}


## The character's persistent, character-scoped short state to seed onto a fresh
## session: char.* vars and the inventory. (World/campaign state is layered on
## separately by the campaign store.)
func carried_vars() -> Dictionary:
	return vars.duplicate(true)


func carried_items() -> Dictionary:
	return items.duplicate(true)


func carried_flags() -> Dictionary:
	return flags.duplicate(true)


## Read a played-out IFState back into this character's LONG-TERM state — the
## capture that makes a character carry across modules. `item_prefix` and
## `char_prefix` route the session's namespaced vars: item.* -> inventory,
## char.* -> persistent character vars. Everything else in the session is
## SHORT-TERM (scene-scoped) and is intentionally NOT captured.
func capture_from(state: IFState, char_prefix: String = "char.") -> void:
	# Full current sheet (attributes incl. live STAMINA, resources, maxes).
	sheet = {
		"attributes": state.attributes.duplicate(true),
		"resources": state.resources.duplicate(true),
		"resource_max": state.resource_max.duplicate(true),
	}
	materialized = true
	# Inventory (item.* vars with count > 0).
	items = state.inventory()
	# Character-scoped persistent vars (char.*).
	vars.clear()
	for k in state.vars.keys():
		var key := str(k)
		if key.begins_with(char_prefix):
			vars[key] = state.vars[k]
	# Character-scoped persistent flags (char.*).
	flags.clear()
	for k in state.flags.keys():
		var key := str(k)
		if key.begins_with(char_prefix):
			flags[key] = state.flags[k]


## Append a module-completion record to the cross-module history.
func note_module(module_id: String, ending: Dictionary) -> void:
	history.append({
		"module": module_id,
		"ending": str(ending.get("id", "")),
		"kind": str(ending.get("kind", "")),
	})


## Serialise the character's LONG-TERM state for the roster store. The immutable
## companion binding rides along verbatim so the character can be re-loaded whole.
func save_data() -> Dictionary:
	var out: Dictionary = {
		"id": id,
		"name": name,
		"tier": tier,
		"ruleset": ruleset_id,
		"sheet": sheet.duplicate(true),
		"vars": vars.duplicate(true),
		"items": items.duplicate(true),
		"flags": flags.duplicate(true),
		"history": history.duplicate(true),
		"materialized": materialized,
	}
	if is_companion():
		out["companion"] = {
			"ref": companion_ref,
			"interchange": interchange,
			"derive": derive_spec,
		}
	return out


func load_data(data: Dictionary) -> void:
	load_from(data)


func raw() -> Dictionary:
	return _raw
