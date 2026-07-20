class_name FFAdventureSheet
extends RefCounted
## res://scripts/rules/adventure_sheet.gd
## THE Fighting-Fantasy Adventure Sheet — the authoritative character record and
## the single place FF's numeric invariants live (GDD §5, INSPIRATION §2.1).
##
## PHASE 1 — STATE UNIFICATION. The sheet no longer owns a parallel copy of the
## numbers. It is a thin FF-flavoured VIEW over ONE `IFState` (nox_if_engine) — the
## SAME `IFState` the scenario runner mutates. That is the whole point of the
## unification: when a section's `onEnter` does `gold +25` or grants an item, the
## engine writes it into the shared `IFState`, and because this sheet READS from
## that same state, the change reaches the sheet + HUD with zero glue. The §5 model
##
##   { skill{init,cur}, stamina{init,cur}, luck{init,cur},
##     provisions, gold, potion{type,doses}, equipment[], codewords:set, notes[] }
##
## maps onto IFState as:
##   skill/stamina/luck.cur   -> IFState.attributes[SKILL|STAMINA|LUCK]
##   skill/stamina/luck.init  -> IFState.attribute_max[...] (the per-run CAP)
##   provisions               -> IFState.resources["provisions"]
##   gold                     -> IFState.vars["gold"]
##   equipment[]              -> IFState inventory (item.* vars)
##   codewords                -> IFState.codewords
##   notes[]                  -> IFState.notes
##   potion{type,doses}       -> IFState.flags["potion"]
##
## EVERY numeric mutation still funnels through ONE method — `apply_delta()` — but
## that method now writes THROUGH to the shared IFState, and the two rules a
## faithful FF adaptation must never get wrong are enforced in the engine's ONE
## clamp (IFState._clamp_attr honouring `attribute_max`):
##
##   1. Current SKILL / STAMINA / LUCK may fall but NEVER exceed Initial (the cap).
##      The sole exception is an explicit Initial change (Potion of Fortune raising
##      Initial LUCK by 1 — a `luck_init` delta that raises the cap).
##   2. Death is STAMINA reaching 0.
##
## Dice for combat/luck come from the seeded `IFDice`; a fixed seed replays every
## roll (MP sync + replay/verify, GDD §5). This object holds NO scene-tree
## dependency; the `Adventure` autoload wraps it and re-emits change signals.

## The three core FF attributes, keyed by the ruleset's native attribute names.
const _STATS: Array[String] = ["skill", "stamina", "luck"]
const _ATTR: Dictionary = {"skill": "SKILL", "stamina": "STAMINA", "luck": "LUCK"}

## GDD §3 starting kit (sword, leather armour, lantern) + one Potion. The roll-up
## UI (Phase 2) will let the player pick the Potion; Fortune is the faithful default.
const _STARTING_KIT: Array[String] = ["sword", "leather armour", "lantern"]

## The single shared runtime store this sheet is a view over.
var state: IFState
var ruleset: IFRuleset


# --- Roll-up / binding ------------------------------------------------------


## Roll a fresh STANDALONE hero (own IFState) — used by unit probes and any caller
## that wants a sheet without a running scenario. SKILL 1d6+6, STAMINA 2d6+12,
## LUCK 1d6+6 as encoded in ff-2d6.json; the rolled value is BOTH Initial and
## Current; the never-exceed-Initial cap is set from the roll; the GDD §3 kit is
## applied. Provisions come from the ruleset's resource default (10).
func roll_up(rs: IFRuleset, dice: IFDice) -> void:
	ruleset = rs
	state = IFState.new(rs)
	state.init_sheet(rs.generate_sheet(dice))
	_bind_caps_and_kit()


## Bind this sheet as a VIEW over an EXISTING IFState (the scenario runner's), then
## set the FF caps + starting kit. This is the unification seam: the runner has
## already rolled the sheet via `ruleset.generate_sheet()` inside `IFRunner.load`,
## so we do NOT re-roll — we adopt that state and layer FF semantics on top.
func bind(existing_state: IFState, rs: IFRuleset) -> void:
	ruleset = rs
	state = existing_state
	_bind_caps_and_kit()


## Set each core attribute's per-run cap to its just-rolled value (that value IS
## the FF Initial) and grant the starting kit additively (never clobbering scenario
## init items or a previously-restored save).
func _bind_caps_and_kit() -> void:
	for stat in _STATS:
		var key: String = _ATTR[stat]
		if state.attributes.has(key) and not state.has_attr_cap(key):
			state.set_attr_cap(key, state.get_attr(key))
	# gold var exists (0) so the HUD reads a real number from turn one.
	if not state.vars.has("gold"):
		state.set_var("gold", 0.0)
	# one Potion of Fortune, unless a save already recorded one.
	if str((state.get_flag("potion", {}) as Dictionary).get("type", "")) == "":
		state.set_flag("potion", {"type": "fortune", "doses": 2})
	# starting equipment, granted once (a re-bind of a loaded save skips these).
	if not state.get_flag("kit_granted", false):
		for item in _STARTING_KIT:
			state.grant_item(item, 1)
		state.set_flag("kit_granted", true)


# --- THE single mutation funnel ---------------------------------------------


## Apply a bundle of changes and return a report of what actually happened. This is
## the ONLY sanctioned way to change the sheet's numbers — combat, luck tests,
## provisions, potions and (indirectly, via the shared IFState) section effects all
## resolve to state writes that the engine clamp governs (GDD §5, §9).
##
## `delta` keys (all optional, all integer):
##   skill / stamina / luck            — change to CURRENT (clamped 0..cap)
##   skill_init / stamina_init / luck_init
##                                     — change to the CAP (Initial); magical
##                                       exceptions; pulls Current down if lowered
##   provisions / gold                 — change to those pools (floored at 0)
##
## Returns:
##   { applied:{key->{from,to}}, died:bool, overflow:{stat->clipped_amount} }
func apply_delta(delta: Dictionary) -> Dictionary:
	var applied: Dictionary = {}
	var overflow: Dictionary = {}
	var newly_dead := false

	# 1) Cap (Initial) changes first, so a same-call Current change sees the new cap.
	for stat in _STATS:
		var ik := stat + "_init"
		if not delta.has(ik) or int(delta[ik]) == 0:
			continue
		var key: String = _ATTR[stat]
		var before_cap := int(state.attr_cap(key))
		var after_cap := maxi(before_cap + int(delta[ik]), 0)
		state.set_attr_cap(key, after_cap)   # also re-clamps Current under the new cap
		applied[ik] = {"from": before_cap, "to": after_cap}

	# 2) Current changes — the engine clamp enforces 0..cap (never-exceed-Initial).
	for stat in _STATS:
		if not delta.has(stat) or int(delta[stat]) == 0:
			continue
		var key: String = _ATTR[stat]
		var before := int(state.get_attr(key))
		var raw := before + int(delta[stat])
		state.add_attr(key, float(int(delta[stat])))
		var after := int(state.get_attr(key))
		applied[stat] = {"from": before, "to": after}
		if raw != after:
			overflow[stat] = raw - after
		if key == "STAMINA" and after <= 0 and before > 0:
			newly_dead = true

	# 3) Pools.
	if delta.has("provisions") and int(delta["provisions"]) != 0:
		var pbefore := provisions
		state.add_resource("provisions", float(int(delta["provisions"])))
		applied["provisions"] = {"from": pbefore, "to": provisions}
	if delta.has("gold") and int(delta["gold"]) != 0:
		var gbefore := gold
		state.set_var("gold", float(maxi(gbefore + int(delta["gold"]), 0)))
		applied["gold"] = {"from": gbefore, "to": gold}

	return {"applied": applied, "died": newly_dead, "overflow": overflow}


# --- Accessors (all read the shared IFState) --------------------------------


func cur(stat: String) -> int:
	return int(state.get_attr(_ATTR.get(stat, stat)))


func init_of(stat: String) -> int:
	return int(state.attr_cap(_ATTR.get(stat, stat)))


func is_dead() -> bool:
	return state != null and int(state.get_attr("STAMINA")) <= 0


## Provisions pool — a property so `sheet.provisions` reads/writes still work while
## the value lives in the shared IFState resource.
var provisions: int:
	get:
		return int(state.get_resource("provisions")) if state != null else 0
	set(value):
		if state != null:
			state.set_resource("provisions", float(maxi(value, 0)))


var gold: int:
	get:
		return int(state.get_var("gold")) if state != null else 0
	set(value):
		if state != null:
			state.set_var("gold", float(maxi(value, 0)))


## The chosen elixir {type, doses}, stored on the shared IFState flags.
var potion: Dictionary:
	get:
		return state.get_flag("potion", {"type": "", "doses": 0}) if state != null else {"type": "", "doses": 0}
	set(value):
		if state != null:
			state.set_flag("potion", value)


## Carried gear, derived from the shared IFState inventory (item.* vars).
var equipment: Array[String]:
	get:
		var out: Array[String] = []
		if state != null:
			for k in state.inventory().keys():
				out.append(str(k))
			out.sort()
		return out


## The codeword set — the shared IFState's first-class store.
var codewords: Dictionary:
	get:
		return state.codewords if state != null else {}


var notes: Array:
	get:
		return state.notes if state != null else []


# --- Tests are MIGRATED to the ruleset's resolutionRules via IFResolver ------
# See adventure.gd: Adventure.test_luck() / test_attribute() resolve the ff-2d6
# `test-luck` / `test` rules (the `test-luck` rule's postEffect is the always-−1
# LUCK attrition, GDD §3). The old bespoke test_luck()/test_attribute() methods
# that lived here have been RETIRED now that state is unified — there is exactly
# one place FF checks resolve, and it is the shared rule engine.


# --- Convenience mutations (route through apply_delta) -----------------------


## Eat one Provision (INSPIRATION §2.7): +4 STAMINA, never above Initial, only when
## Provisions remain. Returns true if a ration was actually eaten.
func eat_provision() -> bool:
	if provisions <= 0:
		return false
	apply_delta({"provisions": -1, "stamina": 4})
	return true


## Quaff one dose of the starting Potion (INSPIRATION §2.6). Skill/Strength restore
## that stat to Initial; Fortune restores LUCK to Initial AND raises Initial LUCK
## by 1 (the one sanctioned way to exceed the starting cap).
func drink_potion() -> bool:
	var p: Dictionary = potion
	if int(p.get("doses", 0)) <= 0:
		return false
	p = p.duplicate()
	p["doses"] = int(p["doses"]) - 1
	potion = p
	match str(p.get("type", "")):
		"skill":
			apply_delta({"skill": init_of("skill") - cur("skill")})
		"strength":
			apply_delta({"stamina": init_of("stamina") - cur("stamina")})
		"fortune":
			apply_delta({"luck_init": 1})
			apply_delta({"luck": init_of("luck") - cur("luck")})
		_:
			return false
	return true


# --- Codewords / equipment (state store, INSPIRATION §2.8) ------------------


func set_codeword(word: String) -> void:
	state.set_codeword(word)


func has_codeword(word: String) -> bool:
	return state != null and state.has_codeword(word)


func add_item(item: String) -> void:
	state.grant_item(item, 1)


func has_item(item: String) -> bool:
	return state != null and state.has_item(item)


func remove_item(item: String) -> bool:
	return state != null and state.consume_item(item, 1)


# --- "persistent" save contract (templates ABI) -----------------------------
# Everything now lives in the shared IFState, so save == the state's payload.


func save_data() -> Dictionary:
	return state.save_data() if state != null else {}


func load_data(data: Dictionary) -> void:
	if state == null:
		state = IFState.new(ruleset)
	state.load_data(data)
