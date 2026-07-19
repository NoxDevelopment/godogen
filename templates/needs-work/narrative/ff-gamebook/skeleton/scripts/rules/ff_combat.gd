class_name FFCombat
extends RefCounted
## res://scripts/rules/ff_combat.gd
## The faithful Fighting-Fantasy combat resolver (INSPIRATION §2.3, GDD §3). It is
## PURE rules over the seeded `IFDice` roller and mutates the hero ONLY through
## `FFAdventureSheet.apply_delta()`, so the never-exceed-Initial + death-at-0
## invariants are enforced in the one sanctioned place. Enemies are lightweight
## dicts (a combat is transient scratch state, like the printed encounter boxes):
##
##   { name:String, skill:int, stamina:int, stamina_max:int }
##
## One Attack Round:
##   * Your Attack Strength = 2d6 + current SKILL
##   * Enemy Attack Strength = 2d6 + enemy SKILL
##   * Higher total WOUNDS the loser for 2 STAMINA; a TIE deals no damage
## Optional Luck-in-combat, Escape (−2 STAMINA), and multi-enemy hooks build on
## this base round.

const WOUND := 2


## Build an enemy scratch record. `stamina_max` defaults to `stamina` so a bar
## can render current/max.
static func make_enemy(enemy_name: String, enemy_skill: int, enemy_stamina: int) -> Dictionary:
	return {
		"name": enemy_name,
		"skill": enemy_skill,
		"stamina": enemy_stamina,
		"stamina_max": enemy_stamina,
	}


## Resolve ONE attack round between `sheet` and `enemy` using the seeded `dice`.
## Mutates the loser: the hero via apply_delta({stamina:-2}); the enemy dict in
## place. Returns a full result for the combat log / dice overlay:
##   { player_faces, player_total, enemy_faces, enemy_total, outcome,
##     wound, player_stamina, enemy_stamina, died, enemy_defeated }
## outcome ∈ "player_wounds" | "enemy_wounds" | "tie".
static func attack_round(sheet: FFAdventureSheet, enemy: Dictionary, dice: IFDice) -> Dictionary:
	var p_roll := dice.roll("2d6")
	var e_roll := dice.roll("2d6")
	var p_total := int(p_roll.total) + sheet.cur("skill")
	var e_total := int(e_roll.total) + int(enemy.get("skill", 0))

	var outcome := "tie"
	var died := false
	var enemy_defeated := false

	if p_total > e_total:
		outcome = "player_wounds"
		enemy["stamina"] = maxi(int(enemy.get("stamina", 0)) - WOUND, 0)
		enemy_defeated = int(enemy["stamina"]) <= 0
	elif e_total > p_total:
		outcome = "enemy_wounds"
		var report := sheet.apply_delta({"stamina": -WOUND})
		died = bool(report.get("died", false))

	return {
		"kind": "combat-round",
		"player_faces": p_roll.faces, "player_total": p_total,
		"enemy_faces": e_roll.faces, "enemy_total": e_total,
		"outcome": outcome, "wound": WOUND,
		"player_stamina": sheet.cur("stamina"),
		"enemy_stamina": int(enemy.get("stamina", 0)),
		"died": died, "enemy_defeated": enemy_defeated,
	}


## Optional Luck-in-combat AFTER the hero wounds the enemy (INSPIRATION §2.3):
## Lucky deals 2 MORE (total 4), Unlucky deals only 1 (heal 1 back). The Test-your-
## Luck itself (roll + always-−1 LUCK) is resolved by the MIGRATED rule engine —
## the caller passes the `luck_result` from `Adventure.test_luck()`, so combat
## stays the only bespoke layer while every die routes through the ruleset. Mutates
## `enemy` in place; returns the luck result augmented with the applied `extra`
## (negative = enemy healed) and the enemy's new STAMINA.
static func luck_after_wounding(enemy: Dictionary, luck_result: Dictionary) -> Dictionary:
	var lr := luck_result.duplicate(true)
	var extra := 2 if bool(lr.get("lucky", false)) else -1
	enemy["stamina"] = clampi(int(enemy.get("stamina", 0)) - extra, 0, int(enemy.get("stamina_max", 9999)))
	lr["extra"] = extra
	lr["enemy_stamina"] = int(enemy["stamina"])
	lr["enemy_defeated"] = int(enemy["stamina"]) <= 0
	return lr


## Optional Luck-in-combat AFTER the hero is wounded (INSPIRATION §2.3): Lucky
## reduces the wound to 1 (heal 1 back), Unlucky raises it to 3 (lose 1 more). The
## caller supplies the `luck_result` from `Adventure.test_luck()` (which already
## spent the LUCK). Applies the STAMINA adjustment through `apply_delta`. Returns
## the luck result + the applied `extra` to the hero.
static func luck_after_wounded(sheet: FFAdventureSheet, luck_result: Dictionary) -> Dictionary:
	var lr := luck_result.duplicate(true)
	var extra := 1 if bool(lr.get("lucky", false)) else -1   # +1 = heal one back, -1 = lose one more
	var report := sheet.apply_delta({"stamina": extra})
	lr["extra"] = extra
	lr["died"] = bool(report.get("died", false))
	lr["player_stamina"] = sheet.cur("stamina")
	return lr


## Escape an encounter (only where the section offers it, INSPIRATION §2.3): a
## parting blow costs an automatic 2 STAMINA. Returns { player_stamina, died }.
static func escape(sheet: FFAdventureSheet) -> Dictionary:
	var report := sheet.apply_delta({"stamina": -WOUND})
	return {
		"kind": "combat-escape",
		"player_stamina": sheet.cur("stamina"),
		"died": bool(report.get("died", false)),
	}
