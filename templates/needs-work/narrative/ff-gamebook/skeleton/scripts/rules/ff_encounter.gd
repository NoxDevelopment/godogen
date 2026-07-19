class_name FFEncounter
extends RefCounted
## res://scripts/rules/ff_encounter.gd
## The GDD §5 `Encounter` data model — the transient combat set-up read from a
## section's combat event:
##
##   Encounter = { enemies: [ { name, skill, stamina, portrait?, modifiers[]? } ],
##                 escapeTarget?: "<passage id>",
##                 gangRules?: { mode: "sequential"|"gang", ... } }
##
## It is authored two ways and normalised here to ONE shape:
##   * single foe  — a passage `enemy: { name, skill, stamina }` (P0 scaffold)
##   * multi foe   — a passage `encounter: { enemies:[...], escapeTarget, gangRules }`
##
## The bespoke round math lives in ff_combat.gd (the one hand-rolled layer); this
## type just carries the roster + escape/gang metadata the Combat Screen (Phase 3)
## and the reading view read. Enemy scratch records are built with `enemy_at()` /
## `make_enemy_records()` (delegating to FFCombat.make_enemy so stamina_max tracks).

var enemies: Array[Dictionary] = []       # authored enemy defs
var escape_target: String = ""
var gang_rules: Dictionary = {}


## Build an encounter from a passage dict. Supports the single-`enemy` shorthand and
## the full `encounter` object. Returns an empty encounter (no enemies) if neither.
static func from_passage(passage: Dictionary) -> FFEncounter:
	var enc := FFEncounter.new()
	if passage.has("encounter"):
		var e: Dictionary = passage["encounter"]
		for raw in e.get("enemies", []):
			enc.enemies.append(_norm_enemy(raw))
		enc.escape_target = str(e.get("escapeTarget", ""))
		enc.gang_rules = e.get("gangRules", {})
	elif passage.has("enemy"):
		enc.enemies.append(_norm_enemy(passage["enemy"]))
	return enc


static func _norm_enemy(raw: Dictionary) -> Dictionary:
	return {
		"name": str(raw.get("name", "Foe")),
		"skill": int(raw.get("skill", 6)),
		"stamina": int(raw.get("stamina", 6)),
		"portrait": str(raw.get("portrait", "")),
		"modifiers": raw.get("modifiers", []),
	}


func is_empty() -> bool:
	return enemies.is_empty()


func count() -> int:
	return enemies.size()


func offers_escape() -> bool:
	return escape_target != ""


## True when foes are fought all-at-once (gang round) rather than one at a time.
func is_gang() -> bool:
	return str(gang_rules.get("mode", "sequential")) == "gang"


## A live combat scratch record for the enemy at `index` (FFCombat.make_enemy shape,
## with stamina_max so a health bar can render). Carries name/skill/portrait/mods.
func enemy_record(index: int) -> Dictionary:
	if index < 0 or index >= enemies.size():
		return {}
	var e: Dictionary = enemies[index]
	var rec := FFCombat.make_enemy(str(e["name"]), int(e["skill"]), int(e["stamina"]))
	rec["portrait"] = str(e.get("portrait", ""))
	rec["modifiers"] = e.get("modifiers", [])
	return rec


## Live scratch records for the WHOLE roster (multi-enemy layouts / gang rounds).
func make_enemy_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in enemies.size():
		out.append(enemy_record(i))
	return out
