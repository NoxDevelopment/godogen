class_name TbsEngine
extends RefCounted
## Pure, seedable TURN-BASED 4X STRATEGY engine (Civilization-lite): eXplore a seeded
## map through fog of war, eXpand by founding cities with settlers, eXploit tiles for
## food/production/science/gold, and eXterminate rivals by capturing their cities. Two
## civs (0 = player, 1 = AI) alternate turns. Node-free + Time-free: one private RNG
## seeds the map + starts, and turns are pure deterministic logic, so a whole game
## replays BYTE-IDENTICALLY from a seed (FNV-1a checksum) and drives headlessly. The
## scene (tbs_view.gd) + GameManager wrap this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const W := 26
const H := 18
const TURN_CAP := 400
const N_CIVS := 2
const CIV_PLAYER := 0
const CIV_AI := 1

# terrain codes
const OCEAN := 0
const PLAINS := 1
const GRASS := 2
const FOREST := 3
const HILL := 4
const MOUNTAIN := 5

# per-terrain [food, prod, gold]
const YIELDS := {
	OCEAN: [1, 0, 1], PLAINS: [1, 1, 0], GRASS: [2, 0, 0],
	FOREST: [1, 2, 0], HILL: [0, 2, 0], MOUNTAIN: [0, 0, 0],
}
# defensive multiplier (x100) by terrain for a unit standing on it
const TERRAIN_DEF := {
	OCEAN: 100, PLAINS: 100, GRASS: 100, FOREST: 125, HILL: 150, MOUNTAIN: 100,
}
const IMPASSABLE := [OCEAN, MOUNTAIN]     ## for land units

# unit kinds → {str, moves, cost}
const UNIT_DEF := {
	"settler": {"str": 0, "moves": 2, "cost": 40},
	"warrior": {"str": 8, "moves": 2, "cost": 25},
	"spearman": {"str": 12, "moves": 2, "cost": 40},
}
const UNIT_HP := 100

# buildings → {cost, tech, food, science, def_hp}
const BUILDING_DEF := {
	"granary": {"cost": 35, "tech": "pottery", "food": 2, "science": 0, "def_hp": 0},
	"library": {"cost": 45, "tech": "writing", "food": 0, "science": 2, "def_hp": 0},
	"walls": {"cost": 40, "tech": "mathematics", "food": 0, "science": 0, "def_hp": 60},
}

# tech tree, researched in order → {cost, unlocks}
const TECHS := ["bronze_working", "pottery", "writing", "mathematics"]
const TECH_COST := {"bronze_working": 30, "pottery": 30, "writing": 50, "mathematics": 70}

const CITY_BASE_HP := 100
const CITY_BASE_DEF := 6                 ## innate defensive strength of an ungarrisoned city
const AI_TARGET_CITIES := 4

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var terrain: PackedByteArray = PackedByteArray()
var turn := 1
var current := CIV_PLAYER
var game_over := false
var winner := -1

var cities: Array = []                   ## Array[Dictionary]
var units: Array = []                    ## Array[Dictionary]
var civ_science := [0, 0]
var civ_gold := [0, 0]
var civ_techs := [[], []]                ## Array of researched tech names per civ
var civ_research := ["", ""]             ## the tech each civ is currently researching
var seen: Array = []                     ## per-civ PackedByteArray fog (explored)
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	turn = 1
	current = CIV_PLAYER
	game_over = false
	winner = -1
	cities = []
	units = []
	civ_science = [0, 0]
	civ_gold = [0, 0]
	civ_techs = [[], []]
	civ_research = [TECHS[0], TECHS[0]]
	log_lines = []
	_next_id = 1
	_gen_map()
	seen = []
	for c in range(N_CIVS):
		var s := PackedByteArray()
		s.resize(W * H)
		seen.append(s)
	_place_starts()
	_begin_turn(CIV_PLAYER)

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
		return MOUNTAIN
	return terrain[_idx(x, y)]

func is_land(x: int, y: int) -> bool:
	return in_bounds(x, y) and not (tile(x, y) in IMPASSABLE)

# --------------------------------------------------------------------------- #
# Seeded map generation (smoothed random elevation + moisture → terrain)
# --------------------------------------------------------------------------- #

func _gen_map() -> void:
	terrain = PackedByteArray()
	terrain.resize(W * H)
	var elev := _noise_field(2)
	var moist := _noise_field(2)
	for y in range(H):
		for x in range(W):
			var i := _idx(x, y)
			# push the map edges toward ocean so continents form inland
			var edge: float = min(float(x), float(W - 1 - x)) / float(W) + min(float(y), float(H - 1 - y)) / float(H)
			var e: float = elev[i] * 0.75 + clampf(edge, 0.0, 0.5)
			var m: float = moist[i]
			var t := PLAINS
			if e < 0.42:
				t = OCEAN
			elif e > 0.90:
				t = MOUNTAIN
			elif e > 0.78:
				t = HILL
			elif m > 0.60:
				t = FOREST
			elif m > 0.38:
				t = GRASS
			else:
				t = PLAINS
			terrain[i] = t

func _noise_field(passes: int) -> Array:
	var f: Array = []
	f.resize(W * H)
	for i in range(W * H):
		f[i] = rng.randf()
	for _p in range(passes):
		var g: Array = f.duplicate()
		for y in range(H):
			for x in range(W):
				var sum := 0.0
				var n := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := x + dx
						var ny := y + dy
						if nx >= 0 and nx < W and ny >= 0 and ny < H:
							sum += float(f[_idx(nx, ny)])
							n += 1
				g[_idx(x, y)] = sum / float(n)
		f = g
	return f

func _place_starts() -> void:
	var p_spot := _find_start(int(W * 0.20), int(H * 0.5))
	var a_spot := _find_start(int(W * 0.80), int(H * 0.5))
	_found_city_at(CIV_PLAYER, p_spot.x, p_spot.y, "Capital-A")
	_found_city_at(CIV_AI, a_spot.x, a_spot.y, "Capital-B")
	units.append(_make_unit(CIV_PLAYER, "settler", _adj_land(p_spot)))
	units.append(_make_unit(CIV_PLAYER, "warrior", _adj_land(p_spot)))
	units.append(_make_unit(CIV_AI, "settler", _adj_land(a_spot)))
	units.append(_make_unit(CIV_AI, "warrior", _adj_land(a_spot)))

func _find_start(cx: int, cy: int) -> Vector2i:
	if is_land(cx, cy) and tile(cx, cy) != HILL:
		return Vector2i(cx, cy)
	for r in range(1, max(W, H)):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nx := cx + dx
				var ny := cy + dy
				if is_land(nx, ny) and tile(nx, ny) != MOUNTAIN:
					return Vector2i(nx, ny)
	return Vector2i(clampi(cx, 1, W - 2), clampi(cy, 1, H - 2))

func _adj_land(c: Vector2i) -> Vector2i:
	for d in _dirs8():
		var n := c + d
		if is_land(n.x, n.y) and _unit_at(n.x, n.y).is_empty() and _city_at(n.x, n.y).is_empty():
			return n
	return c

func _dirs8() -> Array[Vector2i]:
	return [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

# --------------------------------------------------------------------------- #
# Entity construction / lookup
# --------------------------------------------------------------------------- #

func _make_unit(owner: int, kind: String, pos: Vector2i) -> Dictionary:
	var d: Dictionary = UNIT_DEF[kind]
	return {
		"id": _new_id(), "owner": owner, "kind": kind, "x": pos.x, "y": pos.y,
		"hp": UNIT_HP, "max_hp": UNIT_HP, "str": int(d.str),
		"moves": int(d.moves), "moves_left": int(d.moves),
	}

func _found_city_at(owner: int, x: int, y: int, cname: String) -> Dictionary:
	var c := {
		"id": _new_id(), "owner": owner, "name": cname, "x": x, "y": y,
		"pop": 1, "food_box": 0, "prod_box": 0,
		"hp": CITY_BASE_HP, "max_hp": CITY_BASE_HP,
		"build": "warrior", "buildings": [],
	}
	cities.append(c)
	return c

func unit_by_id(id: int) -> Dictionary:
	for u in units:
		if int(u.id) == id:
			return u
	return {}

func city_by_id(id: int) -> Dictionary:
	for c in cities:
		if int(c.id) == id:
			return c
	return {}

func _unit_at(x: int, y: int) -> Dictionary:
	for u in units:
		if int(u.x) == x and int(u.y) == y:
			return u
	return {}

func _city_at(x: int, y: int) -> Dictionary:
	for c in cities:
		if int(c.x) == x and int(c.y) == y:
			return c
	return {}

func units_of(owner: int) -> Array:
	var out: Array = []
	for u in units:
		if int(u.owner) == owner:
			out.append(u)
	return out

func cities_of(owner: int) -> Array:
	var out: Array = []
	for c in cities:
		if int(c.owner) == owner:
			out.append(c)
	return out

func has_tech(civ: int, tech: String) -> bool:
	return tech in civ_techs[civ]

# --------------------------------------------------------------------------- #
# Fog of war
# --------------------------------------------------------------------------- #

func _reveal(civ: int, cx: int, cy: int, radius: int) -> void:
	var s: PackedByteArray = seen[civ]
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx := cx + dx
			var ny := cy + dy
			if in_bounds(nx, ny) and abs(dx) + abs(dy) <= radius + 1:
				s[_idx(nx, ny)] = 1

func is_seen(civ: int, x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return seen[civ][_idx(x, y)] == 1

# --------------------------------------------------------------------------- #
# Turn processing
# --------------------------------------------------------------------------- #

## Runs at the START of `civ`'s turn: reveal fog, work city tiles (grow + produce +
## research + gold), reset unit moves, and heal idle units.
func _begin_turn(civ: int) -> void:
	# fog
	for u in units_of(civ):
		_reveal(civ, int(u.x), int(u.y), 2)
	for c in cities_of(civ):
		_reveal(civ, int(c.x), int(c.y), 2)
	# cities
	var science_gain := 0
	var gold_gain := 0
	for c in cities_of(civ):
		var y3 := _city_yields(c)
		var food: int = int(y3[0])
		var prod: int = int(y3[1])
		var gold: int = int(y3[2])
		var sci: int = 1 + int(c.pop) / 2
		if "library" in c.buildings:
			sci += int(BUILDING_DEF["library"].science)
		# food → growth
		c.food_box = int(c.food_box) + food - int(c.pop) * 2
		if int(c.food_box) < 0:
			c.food_box = 0
		var grow_cost: int = 10 + int(c.pop) * 6
		if int(c.food_box) >= grow_cost:
			c.food_box = int(c.food_box) - grow_cost
			c.pop = int(c.pop) + 1
		# production → build
		c.prod_box = int(c.prod_box) + prod
		_try_complete_build(c)
		science_gain += sci
		gold_gain += gold + 1
		# city passive heal
		if int(c.hp) < int(c.max_hp):
			c.hp = min(int(c.max_hp), int(c.hp) + 8)
	civ_science[civ] += science_gain
	civ_gold[civ] += gold_gain
	_advance_research(civ)
	# units: refresh moves + heal
	for u in units_of(civ):
		var healed: bool = int(u.hp) < int(u.max_hp) and _in_friendly_territory(civ, int(u.x), int(u.y))
		u.moves_left = int(u.moves)
		if healed:
			u.hp = min(int(u.max_hp), int(u.hp) + 15)

func _city_yields(c: Dictionary) -> Array:
	# center tile (with a min 1 food / 1 prod floor) + the pop best adjacent tiles
	var cx: int = int(c.x)
	var cy: int = int(c.y)
	var cy3: Array = YIELDS[tile(cx, cy)]
	var food: int = max(1, int(cy3[0]))
	var prod: int = max(1, int(cy3[1]))
	var gold: int = int(cy3[2])
	# gather candidate ring tiles by yield weight
	var ring: Array = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var nx := cx + dx
			var ny := cy + dy
			if not in_bounds(nx, ny):
				continue
			var yy: Array = YIELDS[tile(nx, ny)]
			ring.append({"w": int(yy[0]) * 2 + int(yy[1]) * 2 + int(yy[2]), "f": int(yy[0]), "p": int(yy[1]), "g": int(yy[2])})
	ring.sort_custom(func(a, b): return int(a.w) > int(b.w))
	var worked: int = min(int(c.pop), ring.size())
	for i in range(worked):
		var r: Dictionary = ring[i]
		food += int(r.f)
		prod += int(r.p)
		gold += int(r.g)
	if "granary" in c.buildings:
		food += int(BUILDING_DEF["granary"].food)
	return [food, prod, gold]

func _try_complete_build(c: Dictionary) -> void:
	var kind: String = str(c.build)
	var cost := _build_cost(int(c.owner), kind)
	if cost <= 0 or int(c.prod_box) < cost:
		return
	c.prod_box = int(c.prod_box) - cost
	if kind in UNIT_DEF:
		var spot := _free_adjacent(int(c.x), int(c.y))
		units.append(_make_unit(int(c.owner), kind, spot))
		_log("%s built a %s" % [c.name, kind])
	elif kind in BUILDING_DEF:
		if not (kind in c.buildings):
			c.buildings.append(kind)
			if kind == "walls":
				c.max_hp = int(c.max_hp) + int(BUILDING_DEF["walls"].def_hp)
				c.hp = int(c.hp) + int(BUILDING_DEF["walls"].def_hp)
			_log("%s completed %s" % [c.name, kind])
		# after a one-off building, default back to producing a warrior
		c.build = "warrior"
	# pick a sensible next build if the current one is a now-owned unique building
	if kind in BUILDING_DEF:
		c.build = _default_build(int(c.owner), c)

func _build_cost(civ: int, kind: String) -> int:
	if kind in UNIT_DEF:
		return int(UNIT_DEF[kind].cost)
	if kind in BUILDING_DEF:
		return int(BUILDING_DEF[kind].cost)
	return 0

func _default_build(civ: int, c: Dictionary) -> String:
	if has_tech(civ, "bronze_working"):
		return "spearman"
	return "warrior"

func _advance_research(civ: int) -> void:
	var cur: String = str(civ_research[civ])
	if cur == "":
		return
	var cost: int = int(TECH_COST.get(cur, 9999))
	if civ_science[civ] >= cost and not (cur in civ_techs[civ]):
		civ_science[civ] -= cost
		civ_techs[civ].append(cur)
		_log("Civ %d researched %s" % [civ, cur])
		# queue the next unresearched tech
		civ_research[civ] = ""
		for t in TECHS:
			if not (t in civ_techs[civ]):
				civ_research[civ] = t
				break

# --------------------------------------------------------------------------- #
# Command API (turn-based → applied immediately, in the caller's deterministic order)
# --------------------------------------------------------------------------- #

## Move a unit one or more tiles toward (tx,ty), spending a move point per tile. Returns
## true if it moved at least one tile. Blocked by impassable terrain, friendly stacking,
## and enemy units (use attack() for those).
func move_unit(uid: int, tx: int, ty: int) -> bool:
	var u := unit_by_id(uid)
	if u.is_empty() or int(u.owner) != current or int(u.moves_left) <= 0:
		return false
	var moved := false
	while int(u.moves_left) > 0 and (int(u.x) != tx or int(u.y) != ty):
		var nxt := _step_dir(int(u.x), int(u.y), tx, ty, int(u.owner))
		if nxt == Vector2i(int(u.x), int(u.y)):
			break
		u.x = nxt.x
		u.y = nxt.y
		u.moves_left = int(u.moves_left) - 1
		moved = true
		_reveal(int(u.owner), nxt.x, nxt.y, 2)
	return moved

func _step_dir(cx: int, cy: int, tx: int, ty: int, owner: int) -> Vector2i:
	# greedy 8-dir step toward target over passable, unoccupied-by-friendly tiles
	var best := Vector2i(cx, cy)
	var bd := 1 << 30
	for d in _dirs8():
		var nx := cx + d.x
		var ny := cy + d.y
		if not is_land(nx, ny):
			continue
		var occ := _unit_at(nx, ny)
		if not occ.is_empty() and int(occ.owner) == owner:
			continue
		if not occ.is_empty() and int(occ.owner) != owner:
			continue          # enemy blocks movement — must attack instead
		var city := _city_at(nx, ny)
		if not city.is_empty() and int(city.owner) != owner:
			continue
		var dist := _cheb(nx, ny, tx, ty)
		if dist < bd:
			bd = dist
			best = Vector2i(nx, ny)
	return best

## Melee attack an adjacent tile. Fights the enemy unit there, or (if none) bombards an
## enemy city; capturing it when its HP hits 0. Consumes the attacker's move.
func attack(uid: int, tx: int, ty: int) -> bool:
	var u := unit_by_id(uid)
	if u.is_empty() or int(u.owner) != current or int(u.moves_left) <= 0:
		return false
	if int(u.str) <= 0:
		return false          # settlers can't attack
	if _cheb(int(u.x), int(u.y), tx, ty) != 1:
		return false
	var target := _unit_at(tx, ty)
	if not target.is_empty() and int(target.owner) != int(u.owner):
		_resolve_combat(u, target, tx, ty)
		u.moves_left = int(u.moves_left) - 1
		return true
	var city := _city_at(tx, ty)
	if not city.is_empty() and int(city.owner) != int(u.owner):
		_resolve_city_attack(u, city)
		u.moves_left = int(u.moves_left) - 1
		return true
	return false

func found_city(uid: int) -> bool:
	var u := unit_by_id(uid)
	if u.is_empty() or int(u.owner) != current or u.kind != "settler":
		return false
	var x: int = int(u.x)
	var y: int = int(u.y)
	if not is_land(x, y) or not _city_at(x, y).is_empty():
		return false
	# min spacing from any existing city
	for c in cities:
		if _cheb(x, y, int(c.x), int(c.y)) < 3:
			return false
	var civ: int = int(u.owner)
	_found_city_at(civ, x, y, "City-%d" % _next_id)
	_reveal(civ, x, y, 2)
	units.erase(u)
	_log("Civ %d founded a city at %d,%d" % [civ, x, y])
	return true

func set_city_build(cid: int, kind: String) -> bool:
	var c := city_by_id(cid)
	if c.is_empty() or int(c.owner) != current:
		return false
	if not _can_build(int(c.owner), kind):
		return false
	c.build = kind
	return true

func set_research(civ: int, tech: String) -> void:
	if tech in TECHS and not (tech in civ_techs[civ]):
		civ_research[civ] = tech

func _can_build(civ: int, kind: String) -> bool:
	if kind in UNIT_DEF:
		if kind == "spearman" and not has_tech(civ, "bronze_working"):
			return false
		return true
	if kind in BUILDING_DEF:
		return has_tech(civ, str(BUILDING_DEF[kind].tech))
	return false

# --------------------------------------------------------------------------- #
# Combat (HP-based, deterministic — no RNG)
# --------------------------------------------------------------------------- #

func _eff_str(u: Dictionary, terrain_mult: int) -> float:
	return float(u.str) * (float(u.hp) / float(UNIT_HP)) * (float(terrain_mult) / 100.0)

func _resolve_combat(atk: Dictionary, def: Dictionary, tx: int, ty: int) -> void:
	var atk_eff: float = _eff_str(atk, 100)
	var def_eff: float = _eff_str(def, int(TERRAIN_DEF[tile(tx, ty)]))
	if atk_eff <= 0.01:
		atk_eff = 0.01
	if def_eff <= 0.01:
		def_eff = 0.01
	var ratio: float = atk_eff / def_eff
	var dmg_def: int = clampi(int(round(30.0 * ratio)), 8, 75)
	var dmg_atk: int = clampi(int(round(30.0 / ratio)), 4, 60)
	def.hp = int(def.hp) - dmg_def
	atk.hp = int(atk.hp) - dmg_atk
	if int(def.hp) <= 0:
		units.erase(def)
		_log("Civ %d's %s destroyed a %s" % [int(atk.owner), atk.kind, def.kind])
		# melee advances onto the vacated tile if it survived and the tile is now clear
		if int(atk.hp) > 0 and _unit_at(tx, ty).is_empty() and _city_at(tx, ty).is_empty():
			atk.x = tx
			atk.y = ty
			_reveal(int(atk.owner), tx, ty, 2)
	elif int(atk.hp) <= 0:
		units.erase(atk)
		_log("Civ %d's %s fell attacking a %s" % [int(atk.owner), atk.kind, def.kind])

func _resolve_city_attack(atk: Dictionary, city: Dictionary) -> void:
	# a garrisoned unit defends first; otherwise the city's innate defense trades HP
	var garrison := _unit_at(int(city.x), int(city.y))
	if not garrison.is_empty() and int(garrison.owner) == int(city.owner):
		_resolve_combat(atk, garrison, int(city.x), int(city.y))
		return
	var atk_eff: float = _eff_str(atk, 100)
	var def_str: float = float(CITY_BASE_DEF) + float(int(city.pop))
	if "walls" in city.buildings:
		def_str += 4.0
	var ratio: float = atk_eff / max(def_str, 0.1)
	var dmg_city: int = clampi(int(round(28.0 * ratio)), 8, 60)
	var dmg_atk: int = clampi(int(round(22.0 / max(ratio, 0.1))), 2, 45)
	city.hp = int(city.hp) - dmg_city
	atk.hp = int(atk.hp) - dmg_atk
	if int(atk.hp) <= 0:
		units.erase(atk)
		return
	if int(city.hp) <= 0:
		_capture_city(int(atk.owner), city, atk)

func _capture_city(new_owner: int, city: Dictionary, atk: Dictionary) -> void:
	var old: int = int(city.owner)
	city.owner = new_owner
	city.hp = int(city.max_hp) / 2
	city.pop = max(1, int(city.pop) - 1)
	city.build = _default_build(new_owner, city)
	city.food_box = 0
	city.prod_box = 0
	# the attacker garrisons the captured city
	atk.x = int(city.x)
	atk.y = int(city.y)
	_reveal(new_owner, int(city.x), int(city.y), 2)
	_log("Civ %d CAPTURED %s from Civ %d" % [new_owner, city.name, old])

# --------------------------------------------------------------------------- #
# End turn + victory
# --------------------------------------------------------------------------- #

func end_turn() -> void:
	if game_over:
		return
	current = (current + 1) % N_CIVS
	if current == CIV_PLAYER:
		turn += 1
	_begin_turn(current)
	_check_victory()
	if turn > TURN_CAP:
		_end_by_score()

func _in_friendly_territory(civ: int, x: int, y: int) -> bool:
	for c in cities_of(civ):
		if _cheb(x, y, int(c.x), int(c.y)) <= 2:
			return true
	return false

func _check_victory() -> void:
	var alive: Array = []
	for civ in range(N_CIVS):
		var has_city := cities_of(civ).size() > 0
		var has_settler := false
		for u in units_of(civ):
			if u.kind == "settler":
				has_settler = true
		if has_city or has_settler:
			alive.append(civ)
	if alive.size() == 1:
		game_over = true
		winner = int(alive[0])
	elif alive.size() == 0:
		game_over = true
		winner = -1

func score(civ: int) -> int:
	var s := cities_of(civ).size() * 10
	for c in cities_of(civ):
		s += int(c.pop) * 3
	s += civ_techs[civ].size() * 5
	s += units_of(civ).size()
	return s

func _end_by_score() -> void:
	game_over = true
	var s0 := score(CIV_PLAYER)
	var s1 := score(CIV_AI)
	winner = CIV_PLAYER if s0 > s1 else (CIV_AI if s1 > s0 else -1)

# --------------------------------------------------------------------------- #
# Geometry
# --------------------------------------------------------------------------- #

func _cheb(ax: int, ay: int, bx: int, by: int) -> int:
	return max(abs(ax - bx), abs(ay - by))

func _free_adjacent(cx: int, cy: int) -> Vector2i:
	for d in _dirs8():
		var n := Vector2i(cx + d.x, cy + d.y)
		if is_land(n.x, n.y) and _unit_at(n.x, n.y).is_empty() and _city_at(n.x, n.y).is_empty():
			return n
	# fall back to the city tile itself (stacking a fresh unit on its city is allowed)
	return Vector2i(cx, cy)

# --------------------------------------------------------------------------- #
# Heuristic AI — drives one civ's whole turn, then ends it. Deterministic.
# --------------------------------------------------------------------------- #

func ai_take_turn(civ: int) -> void:
	if game_over or current != civ:
		return
	# 1) research: keep a target queued
	if str(civ_research[civ]) == "":
		for t in TECHS:
			if not (t in civ_techs[civ]):
				civ_research[civ] = t
				break
	# 2) city production orders
	var n_cities := cities_of(civ).size()
	var have_settler := false
	for u in units_of(civ):
		if u.kind == "settler":
			have_settler = true
	for c in cities_of(civ):
		if n_cities < AI_TARGET_CITIES and not have_settler and str(c.build) != "settler":
			c.build = "settler"
			have_settler = true            # only earmark one at a time
		elif str(c.build) == "settler" and (n_cities >= AI_TARGET_CITIES):
			c.build = _default_build(civ, c)
		elif not (str(c.build) in UNIT_DEF) and not _can_build(civ, str(c.build)):
			c.build = _default_build(civ, c)
	# 3) unit actions (settlers expand; military hunts). Snapshot ids for stable order.
	var ids: Array = []
	for u in units_of(civ):
		ids.append(int(u.id))
	ids.sort()
	for id in ids:
		var u := unit_by_id(id)
		if u.is_empty():
			continue
		if u.kind == "settler":
			_ai_settler(u)
		else:
			_ai_military(u)
	end_turn()

func _ai_settler(u: Dictionary) -> void:
	# found here if it's a legal, well-spaced spot; else walk toward the best nearby spot
	if _good_city_spot(int(u.x), int(u.y)):
		found_city(int(u.id))
		return
	var goal := _nearest_open_spot(int(u.x), int(u.y))
	if goal.x >= 0:
		move_unit(int(u.id), goal.x, goal.y)
		if _good_city_spot(int(u.x), int(u.y)):
			found_city(int(u.id))

func _good_city_spot(x: int, y: int) -> bool:
	if not is_land(x, y) or not _city_at(x, y).is_empty():
		return false
	for c in cities:
		if _cheb(x, y, int(c.x), int(c.y)) < 3:
			return false
	return true

func _nearest_open_spot(cx: int, cy: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for y in range(H):
		for x in range(W):
			if _good_city_spot(x, y):
				var d := _cheb(cx, cy, x, y)
				if d > 0 and d < bd:
					bd = d
					best = Vector2i(x, y)
	return best

func _ai_military(u: Dictionary) -> void:
	var civ: int = int(u.owner)
	# target: nearest enemy unit, else nearest enemy city (known or not — small map)
	var target := _nearest_enemy_target(u)
	if target.x < 0:
		return
	# adjacent to an enemy? attack it
	if _cheb(int(u.x), int(u.y), target.x, target.y) == 1:
		if not _unit_at(target.x, target.y).is_empty() or not _city_at(target.x, target.y).is_empty():
			attack(int(u.id), target.x, target.y)
			return
	move_unit(int(u.id), target.x, target.y)
	# opportunistic attack after moving
	if int(u.moves_left) > 0:
		for d in _dirs8():
			var nx := int(u.x) + d.x
			var ny := int(u.y) + d.y
			var e := _unit_at(nx, ny)
			var ec := _city_at(nx, ny)
			if (not e.is_empty() and int(e.owner) != civ) or (not ec.is_empty() and int(ec.owner) != civ):
				attack(int(u.id), nx, ny)
				return

func _nearest_enemy_target(u: Dictionary) -> Vector2i:
	var civ: int = int(u.owner)
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for e in units:
		if int(e.owner) == civ:
			continue
		var d := _cheb(int(u.x), int(u.y), int(e.x), int(e.y))
		if d < bd:
			bd = d
			best = Vector2i(int(e.x), int(e.y))
	for ec in cities:
		if int(ec.owner) == civ:
			continue
		var d := _cheb(int(u.x), int(u.y), int(ec.x), int(ec.y))
		if d < bd:
			bd = d
			best = Vector2i(int(ec.x), int(ec.y))
	return best

# --------------------------------------------------------------------------- #
# Deterministic auto-play (probe / an AI seat) — both civs driven by the macro AI
# --------------------------------------------------------------------------- #

func auto_step(_policy: String = "both") -> void:
	if game_over:
		return
	ai_take_turn(current)

func auto_play_to_end(policy: String = "both") -> void:
	var guard := 0
	while not game_over and guard < TURN_CAP * N_CIVS + 4:
		auto_step(policy)
		guard += 1
	if not game_over:
		_end_by_score()

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[T%d] %s" % [turn, s])
	if log_lines.size() > 80:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d,%d|%d,%d" % [turn, current, int(game_over), winner,
		int(civ_science[0]), int(civ_science[1]), int(civ_gold[0]), int(civ_gold[1])]
	s += "|t%d,%d" % [civ_techs[0].size(), civ_techs[1].size()]
	for c in cities:
		s += "|C%d,%d,%d,%d,%d,%d,%d" % [int(c.id), int(c.owner), int(c.x), int(c.y),
			int(c.pop), int(c.hp), int(c.prod_box)]
	for u in units:
		s += "|U%d,%d,%s,%d,%d,%d,%d" % [int(u.id), int(u.owner), str(u.kind),
			int(u.x), int(u.y), int(u.hp), int(u.moves_left)]
	for b in terrain:
		h = (h ^ int(b)) & mask
		h = (h * 1099511628211) & mask
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "turn": turn, "current": current, "game_over": game_over,
		"winner": winner, "next_id": _next_id, "seed": int(rng.seed), "rng_state": int(rng.state),
		"terrain": terrain, "cities": cities.duplicate(true), "units": units.duplicate(true),
		"civ_science": civ_science.duplicate(), "civ_gold": civ_gold.duplicate(),
		"civ_techs": civ_techs.duplicate(true), "civ_research": civ_research.duplicate(),
		"seen": seen.duplicate(true),
	}

func load_data(d: Dictionary) -> void:
	turn = int(d.get("turn", 1))
	current = int(d.get("current", 0))
	game_over = bool(d.get("game_over", false))
	winner = int(d.get("winner", -1))
	_next_id = int(d.get("next_id", 1))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	terrain = d.get("terrain", PackedByteArray())
	cities = (d.get("cities", []) as Array).duplicate(true)
	units = (d.get("units", []) as Array).duplicate(true)
	civ_science = (d.get("civ_science", [0, 0]) as Array).duplicate()
	civ_gold = (d.get("civ_gold", [0, 0]) as Array).duplicate()
	civ_techs = (d.get("civ_techs", [[], []]) as Array).duplicate(true)
	civ_research = (d.get("civ_research", ["", ""]) as Array).duplicate()
	seen = (d.get("seen", []) as Array).duplicate(true)
