class_name IFState
extends RefCounted
## res://addons/nox_if_engine/if_state.gd
## Short-term runtime state — the deterministic, save-able heart of a play
## session. It EXTENDS two existing NoxDev conventions into one object:
##
##   * ff-gamebook SessionState (session_state.gd): passage flow + history +
##     roll_log, and the "persistent" save_data()/load_data() contract.
##   * ff-gamebook Sheet (character_sheet.gd): the adventure sheet — here it is
##     system-defined (attributes + resources come from the IFRuleset).
##   * VN runtime-variables/inventory (vn_runtime.gd): numeric `vars`, `flags`,
##     and INVENTORY AS VARIABLES under the `item.` prefix — `give a key` =
##     `item.key += 1`, `needs a key` = `item.key >= 1`. Same op/cmp vocabulary
##     (set/add · >=,<=,==,!=,>,<) so the ink authoring path and the node-graph
##     authoring path compile to exactly this model.
##
## It is also the single seam a future multiplayer/DM layer intercepts (the same
## role SessionState plays for nox_netcode) — nothing here talks to the tree.
##
## This object holds NO randomness and NO rules; it is pure data + typed
## accessors. The Runner drives it, the Resolver reads/writes it, conditions and
## effects are interpreted against it (see eval_condition / apply_effect).

const ITEM_PREFIX := "item."

## The ruleset defines attribute/resource bounds; kept for clamping.
var ruleset: IFRuleset

## Sheet: system attributes (SKILL/LUCK/STAMINA...) and depletable resources.
var attributes: Dictionary = {}      # key -> float
var resources: Dictionary = {}       # key -> float
var resource_max: Dictionary = {}    # key -> float (for trackMax resources)
## Per-RUN attribute cap — the "never exceed this" ceiling a system may tighten to
## a rolled value (FF's Initial SKILL/STAMINA/LUCK). When present for a key it is
## the BINDING max in `_clamp_attr` (it OVERRIDES the ruleset's static max, so a
## sanctioned exception — e.g. Potion of Fortune raising Initial LUCK past the
## ruleset ceiling — is expressible by raising the cap). Absent => the ruleset's
## static max applies. This is where FFAdventureSheet's never-exceed-Initial
## invariant is enforced, in the engine's ONE clamp — see adventure_sheet.gd.
var attribute_max: Dictionary = {}   # key -> float

## VN-style short-term state.
var vars: Dictionary = {}            # numeric variables, incl. item.* inventory
var flags: Dictionary = {}           # named flags (any value)
## First-class codeword set (GDD §5) — the "true path" store queried by section
## logic. A codeword is a name that is either carried (true) or not. Kept distinct
## from `flags` so the printed Adventure Sheet's codeword box maps 1:1 (and so the
## authoring validator can reason about codewords specifically).
var codewords: Dictionary = {}       # word -> true
## Free-text clues jotted on the sheet (GDD §5 AdventureSheet.notes).
var notes: Array = []

## SessionState-style flow.
var current_passage: String = ""
var passage_history: Array[String] = []
var roll_log: Array[Dictionary] = []
## The most recent resolution result (for `checkResult` conditions & bands).
var last_check: Dictionary = {}
## Terminal state (set when an ending passage is entered).
var ended: bool = false
var ending: Dictionary = {}


func _init(rs: IFRuleset = null) -> void:
	ruleset = rs


# --- Sheet initialization ---------------------------------------------------


## Seed the sheet from a generate_sheet() result or a fixed override dict of the
## same shape ({attributes, resources, resource_max?}).
func init_sheet(sheet: Dictionary) -> void:
	attributes = (sheet.get("attributes", {}) as Dictionary).duplicate(true)
	resources = (sheet.get("resources", {}) as Dictionary).duplicate(true)
	resource_max = (sheet.get("resource_max", {}) as Dictionary).duplicate(true)
	# Any trackMax resource with no explicit max mirrors its starting value.
	if ruleset != null:
		for key in resources.keys():
			var rd := ruleset.resource_def(key)
			if bool(rd.get("trackMax", false)) and not resource_max.has(key):
				resource_max[key] = resources[key]


# --- Attributes -------------------------------------------------------------


func get_attr(key: String) -> float:
	if not attributes.has(key):
		push_warning("IFState: unknown attribute '%s'" % key)
		return 0.0
	return float(attributes[key])


func set_attr(key: String, value: float) -> void:
	attributes[key] = _clamp_attr(key, value)


func add_attr(key: String, delta: float) -> void:
	set_attr(key, get_attr(key) + delta)


func _clamp_attr(key: String, value: float) -> float:
	var lo := -INF
	var hi := INF
	if ruleset != null and ruleset.has_attribute(key):
		var b := ruleset.attribute_bounds(key)
		lo = float(b.min)
		hi = float(b.max)
	# A per-run cap is the BINDING ceiling — it replaces the ruleset's static max so
	# a sanctioned exception (Potion of Fortune) can raise Initial past it.
	if attribute_max.has(key):
		hi = float(attribute_max[key])
	value = maxf(value, lo)
	value = minf(value, hi)
	return value


## The per-run cap (FF Initial) for an attribute, or its ruleset static max when no
## cap has been set. This is what FFAdventureSheet reports as `init_of(stat)`.
func attr_cap(key: String) -> float:
	if attribute_max.has(key):
		return float(attribute_max[key])
	if ruleset != null and ruleset.has_attribute(key):
		return float(ruleset.attribute_bounds(key).max)
	return INF


func has_attr_cap(key: String) -> bool:
	return attribute_max.has(key)


## Set the per-run cap and pull Current back under it if it now exceeds it.
func set_attr_cap(key: String, value: float) -> void:
	attribute_max[key] = value
	if attributes.has(key):
		set_attr(key, get_attr(key))   # re-clamp Current to the new ceiling


# --- Resources --------------------------------------------------------------


func get_resource(key: String) -> float:
	return float(resources.get(key, 0.0))


func set_resource(key: String, value: float) -> void:
	resources[key] = _clamp_resource(key, value)


func add_resource(key: String, delta: float) -> void:
	set_resource(key, get_resource(key) + delta)


func _clamp_resource(key: String, value: float) -> float:
	var lo := 0.0
	var hi := INF
	if ruleset != null:
		var rd := ruleset.resource_def(key)
		if rd.has("min"):
			lo = float(rd["min"])
		if rd.has("max"):
			hi = float(rd["max"])
	if resource_max.has(key):
		hi = minf(hi, float(resource_max[key]))
	return clampf(value, lo, hi)


# --- Variables (VN convention) ----------------------------------------------


func get_var(key: String) -> float:
	return float(vars.get(key, 0.0))


func set_var(key: String, value: float) -> void:
	vars[key] = value


func add_var(key: String, delta: float) -> void:
	vars[key] = get_var(key) + delta


# --- Inventory = vars under item.* (VN convention) --------------------------


func get_item(key: String) -> int:
	return int(get_var(ITEM_PREFIX + key))


func has_item(key: String) -> bool:
	return get_item(key) >= 1


func grant_item(key: String, count: int = 1) -> void:
	add_var(ITEM_PREFIX + key, count)


func consume_item(key: String, count: int = 1) -> bool:
	var have := get_item(key)
	if have < count:
		return false
	set_var(ITEM_PREFIX + key, have - count)
	return true


## Inventory as a {name: count} map (item.* vars with count > 0) for the UI/save.
func inventory() -> Dictionary:
	var inv: Dictionary = {}
	for k in vars.keys():
		var key := str(k)
		if key.begins_with(ITEM_PREFIX):
			var count := int(vars[k])
			if count > 0:
				inv[key.substr(ITEM_PREFIX.length())] = count
	return inv


# --- Flags ------------------------------------------------------------------


func get_flag(key: String, default: Variant = false) -> Variant:
	return flags.get(key, default)


func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value


func clear_flag(key: String) -> void:
	flags.erase(key)


# --- Codewords (first-class "true path" store, GDD §5) -----------------------


func set_codeword(word: String) -> void:
	codewords[word] = true


func has_codeword(word: String) -> bool:
	return codewords.get(word, false) == true


func clear_codeword(word: String) -> void:
	codewords.erase(word)


# --- Passage flow (SessionState role) ---------------------------------------


func enter_passage(passage_id: String) -> void:
	current_passage = passage_id
	passage_history.append(passage_id)


func record_roll(result: Dictionary) -> void:
	last_check = result
	roll_log.append(result)


func mark_ending(ending_def: Dictionary) -> void:
	ended = true
	ending = ending_def


# --- Condition interpreter --------------------------------------------------
# Shared vocabulary with vn_runtime.var_conditions_met + item.* + flags + attrs.
# A condition list is ANDed; `any`/`all` nest for OR/grouping.


func conditions_met(conds: Variant) -> bool:
	if conds == null:
		return true
	for c in conds:
		if not eval_condition(c):
			return false
	return true


func eval_condition(cond: Dictionary) -> bool:
	var kind := str(cond.get("kind", "var"))
	match kind:
		"always":
			return true
		"any":
			for c in cond.get("of", []):
				if eval_condition(c):
					return true
			return false
		"all":
			for c in cond.get("of", []):
				if not eval_condition(c):
					return false
			return true
		"not":
			return not eval_condition(cond.get("of", {}))
		"var":
			return _cmp(get_var(str(cond.get("key", ""))), cond)
		"attr":
			return _cmp(get_attr(str(cond.get("key", ""))), cond)
		"resource":
			return _cmp(get_resource(str(cond.get("key", ""))), cond)
		"item":
			# Default: presence (item.key >= 1).
			var have := float(get_item(str(cond.get("key", ""))))
			if not cond.has("cmp") and not cond.has("value"):
				return have >= 1.0
			return _cmp(have, cond, 1.0)
		"flag":
			var want: Variant = cond.get("value", true)
			return get_flag(str(cond.get("key", "")), false) == want
		"codeword":
			# Default: the codeword is carried. `value:false` tests its ABSENCE.
			var want_cw: bool = bool(cond.get("value", true))
			return has_codeword(str(cond.get("key", ""))) == want_cw
		"checkResult":
			var band := str(last_check.get("band", ""))
			var target: Variant = cond.get("value", "")
			if typeof(target) == TYPE_ARRAY:
				return band in target
			return band == str(target)
		_:
			push_warning("IFState: unknown condition kind '%s'" % kind)
			return false


func _cmp(lhs: float, cond: Dictionary, default_value: float = 0.0) -> bool:
	var rhs := float(cond.get("value", default_value))
	match str(cond.get("cmp", ">=")):
		">=": return lhs >= rhs
		"<=": return lhs <= rhs
		"==": return is_equal_approx(lhs, rhs)
		"!=": return not is_equal_approx(lhs, rhs)
		">": return lhs > rhs
		"<": return lhs < rhs
		_:
			push_warning("IFState: unknown cmp '%s'" % cond.get("cmp"))
			return false


# --- Effect interpreter -----------------------------------------------------
# Shared with the narrative graph's choice effects AND resolution postEffects.
# Returns a route (passage id) if the effect is a `goto`, else "".


func apply_effects(effects: Variant) -> String:
	var route := ""
	if effects == null:
		return route
	for e in effects:
		var r := apply_effect(e)
		if r != "":
			route = r
	return route


func apply_effect(eff: Dictionary) -> String:
	var kind := str(eff.get("kind", "var"))
	var key := str(eff.get("key", ""))
	var op := str(eff.get("op", "add"))
	var value := float(eff.get("value", 0))
	match kind:
		"var":
			if op == "set":
				set_var(key, value)
			else:
				add_var(key, value)
		"item":
			# op: grant (add) | consume (subtract, floored at 0)
			if op == "consume":
				consume_item(key, int(value if value != 0 else 1))
			else:
				grant_item(key, int(value if value != 0 else 1))
		"attr":
			if op == "set":
				set_attr(key, value)
			else:
				add_attr(key, value)
		"resource":
			if op == "set":
				set_resource(key, value)
			else:
				add_resource(key, value)
		"flag":
			set_flag(key, eff.get("value", true))
		"codeword":
			# op: set (default, carry it) | clear (drop it).
			if op == "clear":
				clear_codeword(key)
			else:
				set_codeword(key)
		"note":
			var text := str(eff.get("value", eff.get("text", "")))
			if text != "":
				notes.append(text)
		"goto":
			return str(eff.get("value", eff.get("target", "")))
		_:
			push_warning("IFState: unknown effect kind '%s'" % kind)
	return ""


# --- "persistent" save contract (SessionState/Sheet ABI) --------------------


func save_data() -> Dictionary:
	return {
		"attributes": attributes.duplicate(true),
		"resources": resources.duplicate(true),
		"resource_max": resource_max.duplicate(true),
		"attribute_max": attribute_max.duplicate(true),
		"vars": vars.duplicate(true),
		"flags": flags.duplicate(true),
		"codewords": codewords.duplicate(true),
		"notes": notes.duplicate(true),
		"current_passage": current_passage,
		"passage_history": passage_history.duplicate(),
		"roll_log": roll_log.duplicate(true),
		"last_check": last_check.duplicate(true),
		"ended": ended,
		"ending": ending.duplicate(true),
	}


func load_data(data: Dictionary) -> void:
	attributes = (data.get("attributes", {}) as Dictionary).duplicate(true)
	resources = (data.get("resources", {}) as Dictionary).duplicate(true)
	resource_max = (data.get("resource_max", {}) as Dictionary).duplicate(true)
	attribute_max = (data.get("attribute_max", {}) as Dictionary).duplicate(true)
	vars = (data.get("vars", {}) as Dictionary).duplicate(true)
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	codewords = (data.get("codewords", {}) as Dictionary).duplicate(true)
	notes.assign(data.get("notes", []))
	current_passage = str(data.get("current_passage", ""))
	passage_history.assign(data.get("passage_history", []))
	roll_log.assign(data.get("roll_log", []))
	last_check = (data.get("last_check", {}) as Dictionary).duplicate(true)
	ended = bool(data.get("ended", false))
	ending = (data.get("ending", {}) as Dictionary).duplicate(true)
