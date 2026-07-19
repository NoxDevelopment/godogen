class_name SrpgEngine
extends RefCounted
## Pure, seedable TACTICS-SRPG engine (Fire Emblem / XCOM lineage): two armies fight on a
## grid in alternating TEAM PHASES — each unit moves (Dijkstra move-range over terrain
## cost) then acts once (attack / heal / wait). Combat is a real SRPG kernel: hit% + crit
## from speed/terrain, a weapon triangle (sword>axe>lance), counterattacks, double-attacks
## on a speed lead, terrain avoid/defense, and dedicated healers. Node-free + Time-free:
## one private RNG seeds the map AND every hit/crit roll, so a whole battle replays
## BYTE-IDENTICALLY from a seed (FNV-1a checksum) and drives headlessly. The scene
## (srpg_view.gd) + GameManager wrap this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const W := 16
const H := 12
const ROUND_CAP := 60
const TEAM_PLAYER := 0
const TEAM_ENEMY := 1

# terrain → {cost, avoid, def, heal}  (cost = movement points to enter; avoid subtracts
# from attacker hit%, def subtracts from damage, heal = HP regained standing there)
const PLAIN := 0
const FOREST := 1
const HILL := 2
const FORT := 3
const WALL := 4
const TERRAIN = {
	PLAIN: {"cost": 1, "avoid": 0, "def": 0, "heal": 0},
	FOREST: {"cost": 2, "avoid": 20, "def": 1, "heal": 0},
	HILL: {"cost": 2, "avoid": 10, "def": 1, "heal": 0},
	FORT: {"cost": 1, "avoid": 30, "def": 2, "heal": 10},
	WALL: {"cost": 99, "avoid": 0, "def": 0, "heal": 0},
}

# weapon triangle: sword beats axe beats lance beats sword. bow + staff are neutral.
const WEAP_SWORD := "sword"
const WEAP_AXE := "axe"
const WEAP_LANCE := "lance"
const WEAP_BOW := "bow"
const WEAP_STAFF := "staff"

# class → stats. rng = attack range (bow reaches 2, staff heals at 1). hit = base weapon
# accuracy. crit = base crit chance.
const CLASSES := {
	"soldier": {"weapon": "sword", "hp": 24, "atk": 8, "def": 5, "spd": 7, "move": 5, "rng": 1, "hit": 85, "crit": 5},
	"fighter": {"weapon": "axe", "hp": 30, "atk": 11, "def": 3, "spd": 5, "move": 5, "rng": 1, "hit": 75, "crit": 8},
	"knight": {"weapon": "lance", "hp": 28, "atk": 9, "def": 9, "spd": 3, "move": 4, "rng": 1, "hit": 80, "crit": 3},
	"archer": {"weapon": "bow", "hp": 22, "atk": 8, "def": 4, "spd": 6, "move": 5, "rng": 2, "hit": 82, "crit": 6},
	"healer": {"weapon": "staff", "hp": 20, "atk": 0, "def": 3, "spd": 6, "move": 5, "rng": 1, "hit": 100, "crit": 0},
}
const DOUBLE_ATTACK_SPD := 4         ## speed lead needed to strike twice
const HEAL_AMOUNT := 12

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var terrain: PackedByteArray = PackedByteArray()
var units: Array = []                ## Array[Dictionary]
var round_no := 1
var current_team := TEAM_PLAYER
var game_over := false
var winner := -1
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	round_no = 1
	current_team = TEAM_PLAYER
	game_over = false
	winner = -1
	units = []
	log_lines = []
	_next_id = 1
	_gen_map()
	_place_armies()
	_begin_phase(TEAM_PLAYER)

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

func _idx(x: int, y: int) -> int:
	return y * W + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < W and y >= 0 and y < H

func tile(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return WALL
	return terrain[_idx(x, y)]

# --------------------------------------------------------------------------- #
# Seeded map + army placement
# --------------------------------------------------------------------------- #

func _gen_map() -> void:
	terrain = PackedByteArray()
	terrain.resize(W * H)
	for y in range(H):
		for x in range(W):
			var r := rng.randf()
			var t := PLAIN
			if r < 0.10:
				t = FOREST
			elif r < 0.16:
				t = HILL
			elif r < 0.19:
				t = FORT
			elif r < 0.225:
				t = WALL
			terrain[_idx(x, y)] = t
	# a couple of guaranteed forts near each home edge for defensive play
	_set_terrain(2, H / 2, FORT)
	_set_terrain(W - 3, H / 2, FORT)

func _set_terrain(x: int, y: int, t: int) -> void:
	if in_bounds(x, y):
		terrain[_idx(x, y)] = t

func _place_armies() -> void:
	# player army on the left, enemy mirrored on the right
	var roster := ["soldier", "fighter", "knight", "archer", "healer"]
	for i in range(roster.size()):
		var yy: int = 1 + i * 2
		_spawn(TEAM_PLAYER, roster[i], _open_near(1, yy))
		_spawn(TEAM_ENEMY, roster[i], _open_near(W - 2, yy))

func _spawn(team: int, cls: String, pos: Vector2i) -> void:
	var c: Dictionary = CLASSES[cls]
	units.append({
		"id": _new_id(), "team": team, "cls": cls, "weapon": str(c.weapon),
		"x": pos.x, "y": pos.y,
		"hp": int(c.hp), "max_hp": int(c.hp), "atk": int(c.atk), "def": int(c.def),
		"spd": int(c.spd), "move": int(c.move), "rng": int(c.rng),
		"hit": int(c.hit), "crit": int(c.crit),
		"acted": false,
	})

func _open_near(cx: int, cy: int) -> Vector2i:
	if _passable(cx, cy) and _unit_at(cx, cy).is_empty():
		return Vector2i(cx, cy)
	for r in range(1, max(W, H)):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nx := cx + dx
				var ny := cy + dy
				if _passable(nx, ny) and _unit_at(nx, ny).is_empty():
					return Vector2i(nx, ny)
	return Vector2i(clampi(cx, 0, W - 1), clampi(cy, 0, H - 1))

func _passable(x: int, y: int) -> bool:
	return in_bounds(x, y) and tile(x, y) != WALL

# --------------------------------------------------------------------------- #
# Lookups
# --------------------------------------------------------------------------- #

func unit_by_id(id: int) -> Dictionary:
	for u in units:
		if int(u.id) == id:
			return u
	return {}

func _unit_at(x: int, y: int) -> Dictionary:
	for u in units:
		if int(u.x) == x and int(u.y) == y:
			return u
	return {}

func units_of(team: int) -> Array:
	var out: Array = []
	for u in units:
		if int(u.team) == team:
			out.append(u)
	return out

func combatants_of(team: int) -> int:
	var n := 0
	for u in units:
		if int(u.team) == team and str(u.cls) != "healer":
			n += 1
	return n

func _dirs4() -> Array[Vector2i]:
	return [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

# --------------------------------------------------------------------------- #
# Movement (Dijkstra over terrain cost, blocked by enemies, stop on empty tiles)
# --------------------------------------------------------------------------- #

## Map of reachable tile-index → accumulated move cost for `u` (includes its own tile at
## cost 0). Enemies block passage; allies can be passed through but not stopped on.
func reachable(u: Dictionary) -> Dictionary:
	var start := _idx(int(u.x), int(u.y))
	var budget: int = int(u.move)
	var team: int = int(u.team)
	var dist := {start: 0}
	var frontier: Array = [start]
	while not frontier.is_empty():
		# pick the lowest-cost frontier node (small maps → linear scan is fine + stable)
		var bi := 0
		var bc := 1 << 30
		for i in range(frontier.size()):
			var c: int = int(dist[frontier[i]])
			if c < bc:
				bc = c
				bi = i
		var cur: int = frontier[bi]
		frontier.remove_at(bi)
		var cx: int = cur % W
		var cy: int = cur / W
		var cd: int = int(dist[cur])
		for d in _dirs4():
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if not in_bounds(nx, ny):
				continue
			var step: int = int(TERRAIN[tile(nx, ny)].cost)
			if step >= 99:
				continue
			var occ := _unit_at(nx, ny)
			if not occ.is_empty() and int(occ.team) != team:
				continue                       # enemy blocks passage
			var nd: int = cd + step
			if nd > budget:
				continue
			var nk: int = _idx(nx, ny)
			if not dist.has(nk) or nd < int(dist[nk]):
				dist[nk] = nd
				frontier.append(nk)
	return dist

## Tiles the unit can actually END on (reachable AND unoccupied, or its own tile).
func stand_tiles(u: Dictionary) -> Array:
	var out: Array = []
	var reach := reachable(u)
	for k in reach:
		var x: int = int(k) % W
		var y: int = int(k) / W
		var occ := _unit_at(x, y)
		if occ.is_empty() or int(occ.id) == int(u.id):
			out.append(Vector2i(x, y))
	return out

func _cheb(ax: int, ay: int, bx: int, by: int) -> int:
	return max(abs(ax - bx), abs(ay - by))

func _man(ax: int, ay: int, bx: int, by: int) -> int:
	return abs(ax - bx) + abs(ay - by)

# --------------------------------------------------------------------------- #
# Command API (turn-based → applied immediately in deterministic caller order)
# --------------------------------------------------------------------------- #

func move_unit(uid: int, tx: int, ty: int) -> bool:
	var u := unit_by_id(uid)
	if u.is_empty() or int(u.team) != current_team or u.acted:
		return false
	var ok := false
	for t in stand_tiles(u):
		if t.x == tx and t.y == ty:
			ok = true
			break
	if not ok:
		return false
	u.x = tx
	u.y = ty
	return true

## Attack `target_uid` if it is within this unit's attack range from its current tile.
## Resolves the full exchange (hit/crit, counter, double) and marks the unit acted.
func attack(uid: int, target_uid: int) -> bool:
	var a := unit_by_id(uid)
	var d := unit_by_id(target_uid)
	if a.is_empty() or d.is_empty() or int(a.team) != current_team or a.acted:
		return false
	if str(a.cls) == "healer" or int(a.team) == int(d.team):
		return false
	if _man(int(a.x), int(a.y), int(d.x), int(d.y)) > int(a.rng):
		return false
	_resolve_exchange(a, d)
	a.acted = true
	_check_victory()
	return true

func heal(uid: int, ally_uid: int) -> bool:
	var h := unit_by_id(uid)
	var t := unit_by_id(ally_uid)
	if h.is_empty() or t.is_empty() or int(h.team) != current_team or h.acted:
		return false
	if str(h.cls) != "healer" or int(h.team) != int(t.team) or int(h.id) == int(t.id):
		return false
	if _man(int(h.x), int(h.y), int(t.x), int(t.y)) > int(h.rng):
		return false
	var before: int = int(t.hp)
	t.hp = min(int(t.max_hp), int(t.hp) + HEAL_AMOUNT)
	h.acted = true
	_log("%s heals %s (+%d)" % [h.cls, t.cls, int(t.hp) - before])
	return true

func wait(uid: int) -> bool:
	var u := unit_by_id(uid)
	if u.is_empty() or int(u.team) != current_team:
		return false
	u.acted = true
	return true

# --------------------------------------------------------------------------- #
# Combat kernel (seeded rolls → deterministic; full SRPG exchange)
# --------------------------------------------------------------------------- #

func _triangle(att_w: String, def_w: String) -> int:
	# +1 advantage, -1 disadvantage, 0 neutral
	var beats := {WEAP_SWORD: WEAP_AXE, WEAP_AXE: WEAP_LANCE, WEAP_LANCE: WEAP_SWORD}
	if beats.get(att_w, "") == def_w:
		return 1
	if beats.get(def_w, "") == att_w:
		return -1
	return 0

func _hit_chance(a: Dictionary, d: Dictionary) -> int:
	var tri := _triangle(str(a.weapon), str(d.weapon))
	var avo: int = int(TERRAIN[tile(int(d.x), int(d.y))].avoid)
	var h: int = int(a.hit) + int(a.spd) * 2 - int(d.spd) * 2 - avo + tri * 15
	return clampi(h, 5, 100)

func _crit_chance(a: Dictionary, d: Dictionary) -> int:
	return clampi(int(a.crit) + int(a.spd) - int(d.spd), 0, 60)

func _damage(a: Dictionary, d: Dictionary, crit: bool) -> int:
	var tri := _triangle(str(a.weapon), str(d.weapon))
	var tdef: int = int(TERRAIN[tile(int(d.x), int(d.y))].def)
	var base: int = int(a.atk) + tri * 1 - int(d.def) - tdef
	base = max(1, base)
	if crit:
		base *= 3
	return base

## One strike from a→d. Returns true if d died.
func _strike(a: Dictionary, d: Dictionary) -> bool:
	var hit: int = _hit_chance(a, d)
	var roll: int = rng.randi_range(0, 99)
	if roll >= hit:
		_log("%s misses %s (%d%%)" % [a.cls, d.cls, hit])
		return false
	var crit_roll: int = rng.randi_range(0, 99)
	var is_crit: bool = crit_roll < _crit_chance(a, d)
	var dmg: int = _damage(a, d, is_crit)
	d.hp = int(d.hp) - dmg
	_log("%s hits %s for %d%s" % [a.cls, d.cls, dmg, (" CRIT!" if is_crit else "")])
	return int(d.hp) <= 0

func _resolve_exchange(a: Dictionary, d: Dictionary) -> void:
	# attacker strikes; defender counters if it survives and can reach; then doubles apply
	if _strike(a, d):
		_kill(d)
		return
	var can_counter: bool = str(d.cls) != "healer" and _man(int(a.x), int(a.y), int(d.x), int(d.y)) <= int(d.rng)
	if can_counter:
		if _strike(d, a):
			_kill(a)
			return
	# double attacks (speed lead), attacker first then defender
	if int(a.spd) - int(d.spd) >= DOUBLE_ATTACK_SPD:
		if _strike(a, d):
			_kill(d)
			return
	elif can_counter and int(d.spd) - int(a.spd) >= DOUBLE_ATTACK_SPD:
		if _strike(d, a):
			_kill(a)
			return

func _kill(u: Dictionary) -> void:
	_log("%s (team %d) is defeated" % [u.cls, int(u.team)])
	units.erase(u)

# --------------------------------------------------------------------------- #
# Phase / victory
# --------------------------------------------------------------------------- #

func _begin_phase(team: int) -> void:
	for u in units_of(team):
		u.acted = false
		# fort/terrain healing at the start of the owner's phase
		var th: int = int(TERRAIN[tile(int(u.x), int(u.y))].heal)
		if th > 0 and int(u.hp) < int(u.max_hp):
			u.hp = min(int(u.max_hp), int(u.hp) + th)

func end_phase() -> void:
	if game_over:
		return
	current_team = (current_team + 1) % 2
	if current_team == TEAM_PLAYER:
		round_no += 1
	_begin_phase(current_team)
	if round_no > ROUND_CAP:
		_end_by_count()

func _check_victory() -> void:
	var p := combatants_of(TEAM_PLAYER)
	var e := combatants_of(TEAM_ENEMY)
	if p > 0 and e == 0:
		game_over = true
		winner = TEAM_PLAYER
	elif e > 0 and p == 0:
		game_over = true
		winner = TEAM_ENEMY
	elif p == 0 and e == 0:
		game_over = true
		winner = -1

func _end_by_count() -> void:
	game_over = true
	var p := units_of(TEAM_PLAYER).size()
	var e := units_of(TEAM_ENEMY).size()
	winner = TEAM_PLAYER if p > e else (TEAM_ENEMY if e > p else -1)

# --------------------------------------------------------------------------- #
# Heuristic AI — plays one team's whole phase, then ends it. Deterministic.
# --------------------------------------------------------------------------- #

func ai_take_phase(team: int) -> void:
	if game_over or current_team != team:
		return
	var ids: Array = []
	for u in units_of(team):
		ids.append(int(u.id))
	ids.sort()
	for id in ids:
		var u := unit_by_id(id)
		if u.is_empty() or u.acted:
			continue
		if str(u.cls) == "healer":
			_ai_healer(u)
		else:
			_ai_combatant(u)
	end_phase()

func _ai_combatant(u: Dictionary) -> void:
	# find the best (tile, target) pair: reachable stand tile from which an enemy is in
	# range. Prefer a kill, then most damage, then closing distance.
	var best_tile := Vector2i(int(u.x), int(u.y))
	var best_target := 0
	var best_score := -1
	var enemies := units_of(1 - int(u.team))
	for st in stand_tiles(u):
		for e in enemies:
			if _man(st.x, st.y, int(e.x), int(e.y)) <= int(u.rng):
				var score := _attack_score(u, e, st)
				if score > best_score:
					best_score = score
					best_tile = st
					best_target = int(e.id)
	if best_target != 0:
		move_unit(int(u.id), best_tile.x, best_tile.y)
		attack(int(u.id), best_target)
		return
	# no target in reach → advance toward the nearest enemy
	var goal := _nearest_enemy_tile(u)
	if goal.x >= 0:
		var step := _closest_stand_toward(u, goal)
		move_unit(int(u.id), step.x, step.y)
	u.acted = true

func _attack_score(u: Dictionary, e: Dictionary, from: Vector2i) -> int:
	# simulate expected damage cheaply (no RNG) to rank options
	var saved_x: int = int(u.x)
	var saved_y: int = int(u.y)
	u.x = from.x
	u.y = from.y
	var dmg := _damage(u, e, false)
	var hitc := _hit_chance(u, e)
	u.x = saved_x
	u.y = saved_y
	var kill_bonus: int = 100 if dmg >= int(e.hp) else 0
	# favour hitting healers/low-def and staying accurate
	return kill_bonus + dmg * 2 + hitc / 5 + (10 if str(e.cls) == "healer" else 0)

func _ai_healer(u: Dictionary) -> void:
	# heal the most-wounded reachable ally; else follow the pack
	var best_ally := 0
	var best_missing := 0
	var best_tile := Vector2i(int(u.x), int(u.y))
	for st in stand_tiles(u):
		for a in units_of(int(u.team)):
			if int(a.id) == int(u.id):
				continue
			var missing: int = int(a.max_hp) - int(a.hp)
			if missing > best_missing and _man(st.x, st.y, int(a.x), int(a.y)) <= int(u.rng):
				best_missing = missing
				best_ally = int(a.id)
				best_tile = st
	if best_ally != 0 and best_missing >= 6:
		move_unit(int(u.id), best_tile.x, best_tile.y)
		heal(int(u.id), best_ally)
		return
	var goal := _nearest_ally_tile(u)
	if goal.x >= 0:
		var step := _closest_stand_toward(u, goal)
		move_unit(int(u.id), step.x, step.y)
	u.acted = true

func _nearest_enemy_tile(u: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for e in units_of(1 - int(u.team)):
		var d := _man(int(u.x), int(u.y), int(e.x), int(e.y))
		if d < bd:
			bd = d
			best = Vector2i(int(e.x), int(e.y))
	return best

func _nearest_ally_tile(u: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for a in units_of(int(u.team)):
		if int(a.id) == int(u.id) or str(a.cls) == "healer":
			continue
		var d := _man(int(u.x), int(u.y), int(a.x), int(a.y))
		if d < bd:
			bd = d
			best = Vector2i(int(a.x), int(a.y))
	return best

func _closest_stand_toward(u: Dictionary, goal: Vector2i) -> Vector2i:
	var best := Vector2i(int(u.x), int(u.y))
	var bd := 1 << 30
	for st in stand_tiles(u):
		var d := _man(st.x, st.y, goal.x, goal.y)
		if d < bd:
			bd = d
			best = st
	return best

# --------------------------------------------------------------------------- #
# Deterministic auto-play (probe / an AI seat) — both teams driven by the macro AI
# --------------------------------------------------------------------------- #

func auto_step(_policy: String = "both") -> void:
	if game_over:
		return
	ai_take_phase(current_team)

func auto_play_to_end(policy: String = "both") -> void:
	var guard := 0
	while not game_over and guard < ROUND_CAP * 2 + 4:
		auto_step(policy)
		guard += 1
	if not game_over:
		_end_by_count()

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[R%d] %s" % [round_no, s])
	if log_lines.size() > 80:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d" % [round_no, current_team, int(game_over), winner]
	for u in units:
		s += "|U%d,%d,%s,%d,%d,%d,%d" % [int(u.id), int(u.team), str(u.cls),
			int(u.x), int(u.y), int(u.hp), int(u.acted)]
	for b in terrain:
		h = (h ^ int(b)) & mask
		h = (h * 1099511628211) & mask
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "round_no": round_no, "current_team": current_team,
		"game_over": game_over, "winner": winner, "next_id": _next_id,
		"seed": int(rng.seed), "rng_state": int(rng.state),
		"terrain": terrain, "units": units.duplicate(true),
	}

func load_data(d: Dictionary) -> void:
	round_no = int(d.get("round_no", 1))
	current_team = int(d.get("current_team", 0))
	game_over = bool(d.get("game_over", false))
	winner = int(d.get("winner", -1))
	_next_id = int(d.get("next_id", 1))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	terrain = d.get("terrain", PackedByteArray())
	units = (d.get("units", []) as Array).duplicate(true)
