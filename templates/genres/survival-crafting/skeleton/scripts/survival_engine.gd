class_name SurvivalEngine
extends RefCounted
## Pure, seedable SURVIVAL-CRAFTING engine (Don't Starve / Valheim-lite) run as a DETERMINISTIC
## FIXED-TIMESTEP sim: gather wood/stone/food from seeded resource nodes, CRAFT tools + a
## campfire + cook, manage HUNGER / WARMTH / HEALTH across a DAY-NIGHT cycle (night is cold —
## keep a fire lit), and survive N days. Node-free + Time-free: one seeded RNG places the world +
## drives events, so a whole playthrough replays BYTE-IDENTICALLY from a seed (FNV-1a checksum
## over quantized needs). The scene (survival_view.gd) + GameManager wrap this; all rules live
## here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const WORLD := Vector2(620, 400)
const DAY_TICKS := 220
const NIGHT_START := 132            ## night = ticks 132..219 (~40% of the day)
const SURVIVE_DAYS := 8
const MOVE_SPEED := 4.2
const HARVEST_R := 20.0
const FIRE_R := 70.0                ## warmth radius of a lit fire
const FIRE_FUEL := 130
const REFUEL := 45
const REGROW := 260

const HUNGER_DAY := 0.22
const HUNGER_NIGHT := 0.30
const WARM_SUN := 0.6
const WARM_FIRE := 0.7
const WARM_NIGHT := 0.85

# resource node kinds
const TREE := 0
const ROCK := 1
const BUSH := 2

# recipes: name → {cost:{res:amt}, needs_fire:bool}
const RECIPES := {
	"axe": {"cost": {"wood": 3}, "needs_fire": false},
	"campfire": {"cost": {"wood": 5, "stone": 2}, "needs_fire": false},
	"meal": {"cost": {"food": 1}, "needs_fire": true},
	"shelter": {"cost": {"wood": 10, "fiber": 4}, "needs_fire": false},
}

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var pos := Vector2.ZERO
var health := 100.0
var hunger := 100.0
var warmth := 100.0
var inv := {}                       ## wood/stone/food/fiber/meal + tools (axe/shelter as counts)
var has_axe := false
var has_shelter := false
var nodes: Array = []               ## {kind, pos, amount, regrow}
var fires: Array = []               ## {pos, fuel}
var day := 1
var tick_of_day := 0
var frame := 0
var game_over := false
var won := false
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	pos = WORLD * 0.5
	health = 100.0
	hunger = 100.0
	warmth = 100.0
	inv = {"wood": 0, "stone": 0, "food": 0, "fiber": 0, "meal": 0}
	has_axe = false
	has_shelter = false
	nodes = []
	fires = []
	day = 1
	tick_of_day = 0
	frame = 0
	game_over = false
	won = false
	log_lines = []
	_next_id = 1
	_gen_world()

func _gen_world() -> void:
	for i in range(10):
		nodes.append(_make_node(TREE, 3))
	for i in range(7):
		nodes.append(_make_node(ROCK, 3))
	for i in range(8):
		nodes.append(_make_node(BUSH, 2))

func _make_node(kind: int, amount: int) -> Dictionary:
	return {"id": _new_id(), "kind": kind, "pos": Vector2(rng.randf_range(20, WORLD.x - 20), rng.randf_range(20, WORLD.y - 20)),
		"amount": amount, "max": amount, "regrow": 0}

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

func is_night() -> bool:
	return tick_of_day >= NIGHT_START

func hour() -> int:
	return int(float(tick_of_day) / float(DAY_TICKS) * 24.0)

func near_lit_fire() -> bool:
	for f in fires:
		if int(f.fuel) > 0 and (f.pos as Vector2).distance_to(pos) <= FIRE_R:
			return true
	return false

# --------------------------------------------------------------------------- #
# Lookups / helpers
# --------------------------------------------------------------------------- #

func nearest_node(kind: int) -> Dictionary:
	var best := {}
	var bd := 1e20
	for n in nodes:
		if int(n.kind) == kind and int(n.amount) > 0:
			var d: float = (n.pos as Vector2).distance_squared_to(pos)
			if d < bd:
				bd = d
				best = n
	return best

func can_craft(name: String) -> bool:
	if not (name in RECIPES):
		return false
	var rec: Dictionary = RECIPES[name]
	if bool(rec.needs_fire) and not near_lit_fire():
		return false
	for res in rec.cost:
		if int(inv.get(res, 0)) < int(rec.cost[res]):
			return false
	return true

# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #

func _move_toward(target: Vector2) -> bool:
	var to: Vector2 = target - pos
	if to.length() <= MOVE_SPEED:
		pos = target
		return true
	pos = (pos + to.normalized() * MOVE_SPEED).clamp(Vector2.ZERO, WORLD)
	return false

func harvest(node_id: int) -> bool:
	var n := _node_by_id(node_id)
	if n.is_empty() or int(n.amount) <= 0:
		return false
	if (n.pos as Vector2).distance_to(pos) > HARVEST_R:
		return false
	n.amount = int(n.amount) - 1
	if int(n.amount) <= 0:
		n.regrow = REGROW
	match int(n.kind):
		TREE:
			inv.wood = int(inv.wood) + (3 if has_axe else 2)
		ROCK:
			inv.stone = int(inv.stone) + 2
		BUSH:
			inv.food = int(inv.food) + 1
			inv.fiber = int(inv.fiber) + 1
	return true

func craft(name: String) -> bool:
	if not can_craft(name):
		return false
	var rec: Dictionary = RECIPES[name]
	for res in rec.cost:
		inv[res] = int(inv[res]) - int(rec.cost[res])
	match name:
		"axe": has_axe = true
		"shelter": has_shelter = true
		"campfire": fires.append({"pos": pos, "fuel": FIRE_FUEL})
		"meal": inv.meal = int(inv.meal) + 1
	_log("Crafted %s" % name)
	return true

func eat() -> bool:
	if int(inv.get("meal", 0)) > 0:
		inv.meal = int(inv.meal) - 1
		hunger = minf(100.0, hunger + 55.0)
		return true
	if int(inv.get("food", 0)) > 0:
		inv.food = int(inv.food) - 1
		hunger = minf(100.0, hunger + 28.0)
		return true
	return false

func refuel_nearest_fire() -> bool:
	if int(inv.get("wood", 0)) <= 0:
		return false
	for f in fires:
		if (f.pos as Vector2).distance_to(pos) <= FIRE_R:
			inv.wood = int(inv.wood) - 1
			f.fuel = int(f.fuel) + REFUEL
			return true
	return false

func _node_by_id(id: int) -> Dictionary:
	for n in nodes:
		if int(n.id) == id:
			return n
	return {}

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

## input = {move: Vector2, act: String, target: int} — the view/AI drives one intent per tick.
func tick(input: Dictionary) -> void:
	if game_over:
		return
	# intent
	var mv: Vector2 = input.get("move", Vector2.ZERO)
	if mv.length() > 0.01:
		pos = (pos + mv.normalized() * MOVE_SPEED).clamp(Vector2.ZERO, WORLD)
	var act: String = str(input.get("act", ""))
	match act:
		"harvest": harvest(int(input.get("target", 0)))
		"eat": eat()
		"refuel": refuel_nearest_fire()
		"": pass
		_: craft(act)          # any recipe name
	# world: node regrow, fire burn-down
	for n in nodes:
		if int(n.amount) <= 0 and int(n.regrow) > 0:
			n.regrow = int(n.regrow) - 1
			if int(n.regrow) <= 0:
				n.amount = int(n.max)
	for f in fires:
		if int(f.fuel) > 0:
			f.fuel = int(f.fuel) - 1
	# needs
	hunger = maxf(0.0, hunger - (HUNGER_NIGHT if is_night() else HUNGER_DAY))
	if is_night():
		if near_lit_fire():
			warmth = minf(100.0, warmth + WARM_FIRE)
		else:
			warmth = maxf(0.0, warmth - WARM_NIGHT * (0.6 if has_shelter else 1.0))
	else:
		warmth = minf(100.0, warmth + WARM_SUN)
	# health
	var dmg := 0.0
	if hunger <= 0.0:
		dmg += 0.55
	if warmth <= 0.0:
		dmg += 0.6
	if dmg > 0.0:
		health = maxf(0.0, health - dmg)
	elif hunger > 50.0 and warmth > 50.0:
		health = minf(100.0, health + 0.06)
	if health <= 0.0:
		_finish(false)
		return
	# clock
	tick_of_day += 1
	frame += 1
	if tick_of_day >= DAY_TICKS:
		_new_day()

func _new_day() -> void:
	tick_of_day = 0
	day += 1
	_log("Survived to day %d (hp %.0f)" % [day, health])
	if day > SURVIVE_DAYS:
		_finish(true)

func _finish(victory: bool) -> void:
	game_over = true
	won = victory
	_log("Run over: %s (day %d, hp %.0f)" % [("SURVIVED!" if victory else "died"), day, health])

# --------------------------------------------------------------------------- #
# Heuristic survival auto-seat (probe / demo)
# --------------------------------------------------------------------------- #

func ai_input() -> Dictionary:
	# emergencies first
	if hunger < 40.0 and (int(inv.meal) > 0 or int(inv.food) > 0):
		# cook if we can, then eat
		if int(inv.meal) == 0 and int(inv.food) > 0 and can_craft("meal"):
			return {"act": "meal"}
		return {"act": "eat"}
	# night survival: be at a lit fire; build/refuel as needed
	var night_soon: bool = tick_of_day >= NIGHT_START - 30
	if is_night() or night_soon:
		if fires.is_empty() and can_craft("campfire"):
			return {"act": "campfire"}
		if not fires.is_empty():
			var f: Dictionary = fires[0]
			var d: float = (f.pos as Vector2).distance_to(pos)
			if d > FIRE_R * 0.5:
				return {"move": (f.pos as Vector2) - pos}
			if int(f.fuel) < 60 and int(inv.wood) > 0:
				return {"act": "refuel"}
			# stay warm by the fire (idle)
			if is_night():
				return {}
		elif int(inv.wood) < 5 or int(inv.stone) < 2:
			# scramble to gather campfire mats before dark
			pass
	# crafting priorities during the day
	if not has_axe and can_craft("axe"):
		return {"act": "axe"}
	# gather what we're short on
	var want := _most_needed_resource()
	var node := nearest_node(want)
	if node.is_empty():
		node = nearest_node(TREE)
	if node.is_empty():
		return {}
	var d: float = (node.pos as Vector2).distance_to(pos)
	if d <= HARVEST_R:
		return {"act": "harvest", "target": int(node.id)}
	return {"move": (node.pos as Vector2) - pos}

func _most_needed_resource() -> int:
	# prioritise campfire mats, then food, then a buffer of wood
	if int(inv.wood) < 6:
		return TREE
	if int(inv.stone) < 2:
		return ROCK
	if int(inv.food) < 3:
		return BUSH
	if int(inv.wood) < 14:
		return TREE
	return BUSH

func auto_step() -> void:
	tick(ai_input())

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < SURVIVE_DAYS * DAY_TICKS + DAY_TICKS + 10:
		auto_step()
		guard += 1
	if not game_over:
		_finish(won)

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[D%d %02dh] %s" % [day, hour(), s])
	if log_lines.size() > 40:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func _q(v: float) -> int:
	return int(round(v))

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d,%d,%d|%d,%d,%d,%d,%d|%d,%d" % [frame, day, tick_of_day,
		int(game_over), int(won), _q(health), _q(hunger), _q(warmth),
		int(inv.wood), int(inv.stone), int(inv.food), int(inv.fiber), int(inv.meal),
		int(has_axe), int(has_shelter)]
	s += "|P%d,%d" % [_q(pos.x), _q(pos.y)]
	for n in nodes:
		s += "|N%d,%d" % [int(n.amount), int(n.regrow)]
	for f in fires:
		s += "|F%d" % int(f.fuel)
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "pos": pos, "health": health, "hunger": hunger, "warmth": warmth,
		"inv": inv.duplicate(), "has_axe": has_axe, "has_shelter": has_shelter,
		"nodes": nodes.duplicate(true), "fires": fires.duplicate(true), "day": day,
		"tick_of_day": tick_of_day, "frame": frame, "game_over": game_over, "won": won,
		"next_id": _next_id, "seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	pos = d.get("pos", WORLD * 0.5)
	health = float(d.get("health", 100.0))
	hunger = float(d.get("hunger", 100.0))
	warmth = float(d.get("warmth", 100.0))
	inv = (d.get("inv", {}) as Dictionary).duplicate()
	has_axe = bool(d.get("has_axe", false))
	has_shelter = bool(d.get("has_shelter", false))
	nodes = (d.get("nodes", []) as Array).duplicate(true)
	fires = (d.get("fires", []) as Array).duplicate(true)
	day = int(d.get("day", 1))
	tick_of_day = int(d.get("tick_of_day", 0))
	frame = int(d.get("frame", 0))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	_next_id = int(d.get("next_id", 1))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
