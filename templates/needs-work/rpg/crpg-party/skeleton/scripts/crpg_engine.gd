class_name CrpgEngine
extends RefCounted
## Pure, seedable PARTY CRPG engine (Baldur's-Gate / Gold-Box lineage) on a D&D-5e-LITE
## ruleset: a 4-hero party (fighter / wizard / cleric / rogue) runs an ADVENTURE PATH of
## encounters — initiative-order combats, skill-check EVENTS (d20 + ability vs DC with
## branching outcomes), and RESTS — leveling up until it beats the boss or is wiped.
## Node-free + Time-free: one private RNG seeds the party rolls, the encounter path, AND
## every d20 attack / save / damage roll, so a whole run replays BYTE-IDENTICALLY from a
## seed (FNV-1a checksum) and drives headlessly. The scene (crpg_view.gd) + GameManager
## wrap this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const N_ENCOUNTERS := 8              ## adventure length incl. the boss (last)
const ACTION_CAP := 4000             ## safety bound for auto_play_to_end

# class → base combat/casting profile
const CLASSES := {
	"fighter": {"hd": 10, "atk_stat": "str", "armor": 6, "caster": "", "attacks": 1},
	"rogue":   {"hd": 8,  "atk_stat": "dex", "armor": 3, "caster": "", "attacks": 1},
	"wizard":  {"hd": 6,  "atk_stat": "int", "armor": 1, "caster": "int", "attacks": 1},
	"cleric":  {"hd": 8,  "atk_stat": "wis", "armor": 5, "caster": "wis", "attacks": 1},
}
# enemy templates → {hp, ac, atk, dmg, xp}
const ENEMIES := {
	"goblin": {"hp": 12, "ac": 13, "atk": 4, "dmg": 5, "xp": 25, "boss": false},
	"orc":    {"hp": 20, "ac": 13, "atk": 5, "dmg": 8, "xp": 45, "boss": false},
	"ogre":   {"hp": 34, "ac": 11, "atk": 6, "dmg": 12, "xp": 90, "boss": false},
	"dragon": {"hp": 82, "ac": 16, "atk": 8, "dmg": 13, "xp": 400, "boss": true},
}

# skill-check events: {desc, ability, dc, reward, penalty}
const EVENTS := [
	{"desc": "A rune-locked door bars the way.", "ability": "dex", "dc": 13, "reward": "gold", "penalty": "trap"},
	{"desc": "A wounded pilgrim begs for aid.", "ability": "wis", "dc": 12, "reward": "heal", "penalty": "curse"},
	{"desc": "A sneering warlord blocks the bridge.", "ability": "cha", "dc": 14, "reward": "xp", "penalty": "ambush"},
	{"desc": "An arcane seal hums with power.", "ability": "int", "dc": 13, "reward": "slot", "penalty": "trap"},
	{"desc": "A chasm must be leapt.", "ability": "str", "dc": 12, "reward": "gold", "penalty": "trap"},
]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var party: Array = []                ## Array[Dictionary] heroes
var enemies: Array = []              ## Array[Dictionary] current-combat foes
var order: Array = []                ## initiative order: [{"side":0/1,"id":n}]
var turn_ptr := 0
var encounter := 0                   ## index into the adventure path
var path: Array = []                 ## Array[Dictionary] {kind, ...}
var phase := "explore"               ## explore | combat | event | done
var in_combat := false
var game_over := false
var won := false
var gold := 0
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	party = []
	enemies = []
	order = []
	turn_ptr = 0
	encounter = 0
	path = []
	phase = "explore"
	in_combat = false
	game_over = false
	won = false
	gold = 0
	log_lines = []
	_next_id = 1
	_make_party()
	_gen_path()
	_enter_encounter()

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

func _mod(score: int) -> int:
	return floori(float(score - 10) / 2.0)

func _prof(level: int) -> int:
	return 2 + (level - 1) / 4

func _d(sides: int) -> int:
	return rng.randi_range(1, sides)

func _roll(n: int, sides: int, bonus: int = 0) -> int:
	var s := bonus
	for _i in range(n):
		s += _d(sides)
	return s

# --------------------------------------------------------------------------- #
# Party + adventure generation (seeded)
# --------------------------------------------------------------------------- #

func _make_party() -> void:
	# pregen stat arrays per class (point-buy-ish), with a little seeded jitter
	var pregens := {
		"fighter": {"str": 16, "dex": 13, "con": 15, "int": 9, "wis": 11, "cha": 10},
		"rogue":   {"str": 11, "dex": 16, "con": 13, "int": 12, "wis": 10, "cha": 14},
		"wizard":  {"str": 8, "dex": 14, "con": 13, "int": 16, "wis": 12, "cha": 10},
		"cleric":  {"str": 13, "dex": 10, "con": 14, "int": 10, "wis": 16, "cha": 12},
	}
	for cls in ["fighter", "rogue", "wizard", "cleric"]:
		var stats: Dictionary = (pregens[cls] as Dictionary).duplicate()
		var jitter := rng.randi_range(-1, 1)
		stats[CLASSES[cls].atk_stat] = int(stats[CLASSES[cls].atk_stat]) + jitter
		party.append(_make_hero(cls, stats))

func _make_hero(cls: String, stats: Dictionary) -> Dictionary:
	var c: Dictionary = CLASSES[cls]
	var con_mod := _mod(int(stats.con))
	var max_hp: int = int(c.hd) + con_mod + 9      # level 1 + survivability padding
	var h := {
		"id": _new_id(), "side": 0, "cls": cls, "level": 1, "xp": 0,
		"str": int(stats.str), "dex": int(stats.dex), "con": int(stats.con),
		"int": int(stats.int), "wis": int(stats.wis), "cha": int(stats.cha),
		"hp": max_hp, "max_hp": max_hp,
		"ac": 10 + _mod(int(stats.dex)) + int(c.armor),
		"caster": str(c.caster), "attacks": int(c.attacks),
		"slots": 2 if str(c.caster) != "" else 0, "max_slots": 2 if str(c.caster) != "" else 0,
		"blessed": 0, "alive": true,
	}
	return h

func _gen_path() -> void:
	# a mix of combats + events + a couple rests, boss last. Seeded ordering.
	var kinds := ["combat", "event", "combat", "rest", "event", "combat", "event"]
	for i in range(N_ENCOUNTERS - 1):
		var k: String = kinds[i % kinds.size()]
		if k == "combat":
			path.append({"kind": "combat", "foes": _roll_foes(i)})
		elif k == "event":
			path.append({"kind": "event", "event": EVENTS[rng.randi_range(0, EVENTS.size() - 1)]})
		else:
			path.append({"kind": "rest"})
	path.append({"kind": "rest"})            # catch your breath before the boss
	path.append({"kind": "boss", "foes": [{"tpl": "dragon"}, {"tpl": "orc"}]})

func _roll_foes(depth: int) -> Array:
	var pool := ["goblin", "goblin", "orc"] if depth < 3 else ["goblin", "orc", "ogre"]
	var n := 2 + rng.randi_range(0, 1)
	var foes: Array = []
	for i in range(n):
		foes.append({"tpl": pool[rng.randi_range(0, pool.size() - 1)]})
	return foes

# --------------------------------------------------------------------------- #
# Encounter flow
# --------------------------------------------------------------------------- #

func _enter_encounter() -> void:
	if encounter >= path.size():
		_finish(true)
		return
	var node: Dictionary = path[encounter]
	match str(node.kind):
		"combat", "boss":
			_start_combat(node.foes)
		"event":
			phase = "event"
			_log("Encounter %d: %s" % [encounter + 1, str(node.event.desc)])
		"rest":
			phase = "explore"
			_do_rest()
			_advance_encounter()

func _advance_encounter() -> void:
	encounter += 1
	if encounter >= path.size():
		_finish(true)
	else:
		_enter_encounter()

func _do_rest() -> void:
	for h in party:
		if not h.alive:
			continue
		h.hp = int(h.max_hp)
		h.slots = int(h.max_slots)
		h.blessed = 0
	_log("The party rests — HP and spell slots restored.")

# --------------------------------------------------------------------------- #
# Combat
# --------------------------------------------------------------------------- #

func _start_combat(foes: Array) -> void:
	enemies = []
	for f in foes:
		enemies.append(_make_enemy(str(f.tpl)))
	in_combat = true
	phase = "combat"
	_roll_initiative()
	_log("Combat begins vs %d foes!" % enemies.size())
	_skip_to_actor()

func _make_enemy(tpl: String) -> Dictionary:
	var t: Dictionary = ENEMIES[tpl]
	return {
		"id": _new_id(), "side": 1, "tpl": tpl, "name": tpl,
		"hp": int(t.hp), "max_hp": int(t.hp), "ac": int(t.ac),
		"atk": int(t.atk), "dmg": int(t.dmg), "xp": int(t.xp),
		"boss": bool(t.boss), "alive": true,
	}

func _roll_initiative() -> void:
	var rolls: Array = []
	for h in party:
		if h.alive:
			rolls.append({"side": 0, "id": int(h.id), "init": _d(20) + _mod(int(h.dex))})
	for e in enemies:
		if e.alive:
			rolls.append({"side": 1, "id": int(e.id), "init": _d(20) + 1})
	rolls.sort_custom(func(a, b):
		if int(a.init) != int(b.init):
			return int(a.init) > int(b.init)
		return int(a.id) < int(b.id))          # stable tiebreak by id
	order = rolls
	turn_ptr = 0

func actor_at_ptr() -> Dictionary:
	if turn_ptr < 0 or turn_ptr >= order.size():
		return {}
	var o: Dictionary = order[turn_ptr]
	return hero_by_id(int(o.id)) if int(o.side) == 0 else enemy_by_id(int(o.id))

func hero_by_id(id: int) -> Dictionary:
	for h in party:
		if int(h.id) == id:
			return h
	return {}

func enemy_by_id(id: int) -> Dictionary:
	for e in enemies:
		if int(e.id) == id:
			return e
	return {}

func _skip_to_actor() -> void:
	# advance the pointer past dead combatants; end combat if a side is gone
	var guard := 0
	while guard < 200:
		guard += 1
		if _side_down(0) or _side_down(1):
			_end_combat()
			return
		var a := actor_at_ptr()
		if not a.is_empty() and bool(a.alive):
			return
		_next_turn()

func _next_turn() -> void:
	turn_ptr += 1
	if turn_ptr >= order.size():
		turn_ptr = 0
		# clear one-turn buffs at the top of a fresh round
		for h in party:
			if int(h.blessed) > 0:
				h.blessed = int(h.blessed) - 1

func alive_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.alive:
			out.append(e)
	return out

func alive_party() -> Array:
	var out: Array = []
	for h in party:
		if h.alive:
			out.append(h)
	return out

func _side_down(side: int) -> bool:
	if side == 0:
		return alive_party().is_empty()
	return alive_enemies().is_empty()

# ---- player/AI action API (the actor at the pointer acts, then the turn advances) ---- #

func act_attack(target_id: int) -> bool:
	var a := actor_at_ptr()
	if a.is_empty() or not bool(a.alive) or not in_combat:
		return false
	var t := enemy_by_id(target_id) if int(a.side) == 0 else hero_by_id(target_id)
	if t.is_empty() or not bool(t.alive):
		return false
	if int(a.side) == 0:
		_hero_attack(a, t)
	else:
		_enemy_attack(a, t)
	_after_action()
	return true

func act_spell(spell: String, target_id: int) -> bool:
	var a := actor_at_ptr()
	if a.is_empty() or not bool(a.alive) or int(a.side) != 0:
		return false
	if not _cast(a, spell, target_id):
		return false
	_after_action()
	return true

func act_defend() -> bool:
	var a := actor_at_ptr()
	if a.is_empty():
		return false
	_after_action()
	return true

func _after_action() -> void:
	_next_turn()
	_skip_to_actor()

# ---- resolution ---- #

func _hero_attack(h: Dictionary, t: Dictionary) -> void:
	var stat: String = str(CLASSES[str(h.cls)].atk_stat)
	var atk_mod := _mod(int(h[stat])) + _prof(int(h.level))
	var bless := 1 if int(h.blessed) > 0 else 0
	var n_attacks: int = int(h.attacks)
	for i in range(n_attacks):
		if not bool(t.alive):
			break
		var roll := _d(20)
		var total := roll + atk_mod + bless
		if roll == 20 or total >= int(t.ac):
			var crit := roll == 20
			var dmg := _roll(2 if crit else 1, 8, _mod(int(h[stat])))
			if str(h.cls) == "rogue":
				dmg += _roll(1, 6)                 # sneak attack
			dmg = max(1, dmg)
			_damage(t, dmg)
			_log("%s hits %s for %d%s" % [h.cls, t.name, dmg, (" CRIT" if crit else "")])
		else:
			_log("%s misses %s" % [h.cls, t.name])

func _enemy_attack(e: Dictionary, t: Dictionary) -> void:
	var attacks := 2 if bool(e.boss) else 1
	for i in range(attacks):
		if not bool(t.alive):
			break
		var roll := _d(20)
		if roll == 20 or roll + int(e.atk) >= int(t.ac):
			var dmg: int = max(1, _roll(1, int(e.dmg)) + (int(e.dmg) / 4))
			_damage(t, dmg)
			_log("%s hits %s for %d" % [e.name, t.cls, dmg])
		else:
			_log("%s misses %s" % [e.name, t.cls])

func _cast(h: Dictionary, spell: String, target_id: int) -> bool:
	var caster: String = str(h.caster)
	if caster == "":
		return false
	var save_dc := 8 + _prof(int(h.level)) + _mod(int(h[caster]))
	match spell:
		"magic_missile":
			if str(h.cls) != "wizard" or int(h.slots) <= 0:
				return false
			h.slots = int(h.slots) - 1
			var t := enemy_by_id(target_id)
			if t.is_empty():
				var ae := alive_enemies()
				if ae.is_empty():
					return false
				t = ae[0]
			var dmg := _roll(3, 4, 3)             # 3 darts, auto-hit
			_damage(t, dmg)
			_log("wizard's magic missiles hit %s for %d" % [t.name, dmg])
			return true
		"fireball":
			if str(h.cls) != "wizard" or int(h.slots) <= 0:
				return false
			h.slots = int(h.slots) - 1
			var base := _roll(6, 6)
			for e in alive_enemies():
				var save := _d(20) + 1
				var d: int = base / 2 if save >= save_dc else base
				_damage(e, max(1, d))
			_log("wizard's fireball engulfs the enemies (DC %d)!" % save_dc)
			return true
		"cure_wounds":
			if str(h.cls) != "cleric" or int(h.slots) <= 0:
				return false
			h.slots = int(h.slots) - 1
			var ally := hero_by_id(target_id)
			if ally.is_empty() or not bool(ally.alive):
				ally = _most_wounded_ally()
			if ally.is_empty():
				return false
			var heal := _roll(1, 8, _mod(int(h[caster])))
			ally.hp = min(int(ally.max_hp), int(ally.hp) + max(1, heal))
			_log("cleric heals %s for %d" % [ally.cls, heal])
			return true
		"bless":
			if str(h.cls) != "cleric" or int(h.slots) <= 0:
				return false
			h.slots = int(h.slots) - 1
			for ally in alive_party():
				ally.blessed = 3
			_log("cleric blesses the party (+1 to hit)")
			return true
	return false

func _damage(t: Dictionary, dmg: int) -> void:
	t.hp = int(t.hp) - dmg
	if int(t.hp) <= 0:
		t.hp = 0
		t.alive = false
		var who: String = str(t.name) if t.has("name") else str(t.cls)
		_log("%s falls!" % who)

func _most_wounded_ally() -> Dictionary:
	var best := {}
	var worst := 1 << 30
	for h in alive_party():
		var missing := int(h.max_hp) - int(h.hp)
		if missing > 0 and int(h.hp) < worst:
			worst = int(h.hp)
			best = h
	return best

func _end_combat() -> void:
	in_combat = false
	if _side_down(0):
		_finish(false)
		return
	# victory: award XP (full to every survivor — classic party progression), then continue
	var xp := 0
	for e in enemies:
		xp += int(e.xp)
	for h in alive_party():
		h.xp = int(h.xp) + xp
		_maybe_level_up(h)
	_log("Victory! +%d XP each." % xp)
	enemies = []
	order = []
	_advance_encounter()

func _maybe_level_up(h: Dictionary) -> void:
	var need := int(h.level) * 80
	while int(h.xp) >= need:
		h.xp = int(h.xp) - need
		h.level = int(h.level) + 1
		var gain: int = int(CLASSES[str(h.cls)].hd) / 2 + 1 + _mod(int(h.con))
		h.max_hp = int(h.max_hp) + max(1, gain)
		h.hp = int(h.hp) + max(1, gain)
		if str(h.caster) != "":
			h.max_slots = int(h.max_slots) + 1
			h.slots = int(h.slots) + 1
		if str(h.cls) == "fighter" and int(h.level) >= 5:
			h.attacks = 2
		_log("%s reaches level %d!" % [h.cls, int(h.level)])
		need = int(h.level) * 100

# --------------------------------------------------------------------------- #
# Skill-check events
# --------------------------------------------------------------------------- #

## Resolve the current event using `hero_id`'s ability (or the best-suited hero if -1).
func resolve_event(hero_id: int = -1) -> bool:
	if phase != "event":
		return false
	var node: Dictionary = path[encounter]
	var ev: Dictionary = node.event
	var ability: String = str(ev.ability)
	var hero := hero_by_id(hero_id) if hero_id >= 0 else _best_at(ability)
	if hero.is_empty():
		hero = _best_at(ability)
	var roll := _d(20) + _mod(int(hero[ability])) + _prof(int(hero.level))
	var success: bool = roll >= int(ev.dc)
	if success:
		_apply_event_reward(str(ev.reward))
		_log("%s passes the %s check (%d vs DC %d) — %s" % [hero.cls, ability, roll, int(ev.dc), str(ev.reward)])
	else:
		_apply_event_penalty(str(ev.penalty))
		_log("%s fails the %s check (%d vs DC %d) — %s" % [hero.cls, ability, roll, int(ev.dc), str(ev.penalty)])
	_advance_encounter()
	return true

func _best_at(ability: String) -> Dictionary:
	var best := {}
	var bv := -999
	for h in alive_party():
		var v := int(h[ability])
		if v > bv:
			bv = v
			best = h
	return best

func _apply_event_reward(reward: String) -> void:
	match reward:
		"gold": gold += 50 + _d(50)
		"heal":
			for h in alive_party():
				h.hp = min(int(h.max_hp), int(h.hp) + 8)
		"xp":
			for h in alive_party():
				h.xp = int(h.xp) + 60
				_maybe_level_up(h)
		"slot":
			for h in alive_party():
				if str(h.caster) != "":
					h.slots = min(int(h.max_slots), int(h.slots) + 1)

func _apply_event_penalty(penalty: String) -> void:
	match penalty:
		"trap":
			for h in alive_party():
				_damage(h, _roll(2, 6))
		"curse":
			for h in alive_party():
				_damage(h, _roll(1, 8))
		"ambush":
			# a nasty surprise fight next — inject a combat node right here
			path.insert(encounter + 1, {"kind": "combat", "foes": [{"tpl": "orc"}, {"tpl": "ogre"}]})
	_check_party_wipe()

func _check_party_wipe() -> void:
	if alive_party().is_empty():
		_finish(false)

# --------------------------------------------------------------------------- #
# Heuristic AI — enemy turns + optional full party auto. Deterministic.
# --------------------------------------------------------------------------- #

## Act for whoever's at the pointer (enemy always AI; party AI when auto). Returns false
## if it's a party turn and auto is off (the view should drive it).
func ai_act(auto_party: bool) -> bool:
	if not in_combat or game_over:
		return false
	var a := actor_at_ptr()
	if a.is_empty():
		_skip_to_actor()
		return true
	if int(a.side) == 1:
		_ai_enemy(a)
		return true
	if auto_party:
		_ai_hero(a)
		return true
	return false

func _ai_enemy(e: Dictionary) -> void:
	# focus the lowest-HP hero
	var target := {}
	var low := 1 << 30
	for h in alive_party():
		if int(h.hp) < low:
			low = int(h.hp)
			target = h
	if target.is_empty():
		act_defend()
		return
	act_attack(int(target.id))

func _ai_hero(h: Dictionary) -> void:
	# cleric: heal a badly hurt ally, else bless/attack. wizard: fireball a crowd, else
	# magic missile / firebolt. martials: focus the lowest-HP enemy.
	if str(h.cls) == "cleric" and int(h.slots) > 0:
		var hurt := _most_wounded_ally()
		if not hurt.is_empty() and int(hurt.hp) <= int(hurt.max_hp) / 2:
			act_spell("cure_wounds", int(hurt.id))
			return
		var anyone_blessed := false
		for a in alive_party():
			if int(a.blessed) > 0:
				anyone_blessed = true
		if not anyone_blessed and alive_enemies().size() >= 2:
			act_spell("bless", 0)
			return
	if str(h.cls) == "wizard" and int(h.slots) > 0:
		if alive_enemies().size() >= 3:
			act_spell("fireball", 0)
			return
		act_spell("magic_missile", int(_lowest_enemy().id))
		return
	var t := _lowest_enemy()
	if t.is_empty():
		act_defend()
		return
	act_attack(int(t.id))

func _lowest_enemy() -> Dictionary:
	var best := {}
	var low := 1 << 30
	for e in alive_enemies():
		if int(e.hp) < low:
			low = int(e.hp)
			best = e
	return best

# --------------------------------------------------------------------------- #
# End state
# --------------------------------------------------------------------------- #

func _finish(victory: bool) -> void:
	game_over = true
	won = victory
	phase = "done"
	in_combat = false
	_log("The adventure ends: %s" % ("VICTORY" if victory else "The party has fallen."))

# --------------------------------------------------------------------------- #
# Deterministic auto-play (probe / an AI seat)
# --------------------------------------------------------------------------- #

## One atomic step of the whole run: a combat action, an event resolution, or exploring
## on to the next node. Everything is AI/auto-resolved. Deterministic given the seed.
func auto_step(_policy: String = "auto") -> void:
	if game_over:
		return
	if phase == "combat" and in_combat:
		ai_act(true)
	elif phase == "event":
		resolve_event(-1)
	else:
		# explore/rest transitions are handled inline; nudge if somehow idle
		if encounter >= path.size():
			_finish(true)
		else:
			_enter_encounter()

func auto_play_to_end(policy: String = "auto") -> void:
	var guard := 0
	while not game_over and guard < ACTION_CAP:
		auto_step(policy)
		guard += 1
	if not game_over:
		_finish(won)

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[E%d] %s" % [encounter + 1, s])
	if log_lines.size() > 100:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%s" % [encounter, int(game_over), int(won), gold, turn_ptr, phase]
	for m in party:
		s += "|H%d,%s,%d,%d,%d,%d,%d" % [int(m.id), str(m.cls), int(m.level),
			int(m.hp), int(m.max_hp), int(m.slots), int(m.alive)]
	for e in enemies:
		s += "|E%d,%s,%d,%d" % [int(e.id), str(e.tpl), int(e.hp), int(e.alive)]
	s += "|path%d" % path.size()
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "encounter": encounter, "phase": phase, "in_combat": in_combat,
		"game_over": game_over, "won": won, "gold": gold, "turn_ptr": turn_ptr,
		"next_id": _next_id, "seed": int(rng.seed), "rng_state": int(rng.state),
		"party": party.duplicate(true), "enemies": enemies.duplicate(true),
		"order": order.duplicate(true), "path": path.duplicate(true),
	}

func load_data(d: Dictionary) -> void:
	encounter = int(d.get("encounter", 0))
	phase = str(d.get("phase", "explore"))
	in_combat = bool(d.get("in_combat", false))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	gold = int(d.get("gold", 0))
	turn_ptr = int(d.get("turn_ptr", 0))
	_next_id = int(d.get("next_id", 1))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	party = (d.get("party", []) as Array).duplicate(true)
	enemies = (d.get("enemies", []) as Array).duplicate(true)
	order = (d.get("order", []) as Array).duplicate(true)
	path = (d.get("path", []) as Array).duplicate(true)
