class_name RPGSchedule
extends RefCounted
## res://addons/nox_rpg/rpg_schedule.gd
## Deterministic NPC daily schedules (Immersion-Engine RPG systems, spec P3). Each
## NPC has ordered hour-blocks; `activity_at(npc, hour)` returns where they are and
## what they're doing — the hook a game reads to place NPCs and drive ambient life.
## Wraps midnight; falls back to home/idle. Pure RefCounted, no RNG.
##
## Schedule shape:
##   { "smith": [ {"from": 8,  "to": 18, "location": "forge",  "activity": "working"},
##                {"from": 18, "to": 22, "location": "tavern", "activity": "drinking"},
##                {"from": 22, "to": 8,  "location": "home",   "activity": "sleeping"} ] }

var _schedules: Dictionary = {}


func _init(schedules: Dictionary = {}) -> void:
	_schedules = schedules.duplicate(true)


func has_npc(npc_id: String) -> bool:
	return _schedules.has(npc_id)


## { location, activity } for an NPC at `hour` (0-23; wraps). Blocks may cross
## midnight (from > to). Default: home / idle.
func activity_at(npc_id: String, hour: int) -> Dictionary:
	var h: int = ((hour % 24) + 24) % 24
	var blocks: Array = _schedules.get(npc_id, [])
	for b in blocks:
		var from: int = int(b.get("from", 0))
		var to: int = int(b.get("to", 24))
		var inside := false
		if from <= to:
			inside = h >= from and h < to
		else: # crosses midnight, e.g. 22 -> 8
			inside = h >= from or h < to
		if inside:
			return { "location": String(b.get("location", "home")), "activity": String(b.get("activity", "idle")) }
	return { "location": "home", "activity": "idle" }


## Where an NPC is at `hour` (convenience).
func location_of(npc_id: String, hour: int) -> String:
	return String(activity_at(npc_id, hour).get("location", "home"))
