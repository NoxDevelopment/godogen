class_name GodWorld
extends RefCounted
## res://scripts/god_world.gd
## THE PURE ENGINE — a deterministic, seedable DEITY strategy sim in the
## Populous / Black & White lineage. A top-down GRID of terrain HEIGHTS (water
## below sea level, walkable/buildable land above) seeds two rival TRIBES of
## autonomous FOLLOWERS. You are a god: you shape the land and spend BELIEF on
## divine POWERS to grow your tribe and out-compete a rival god who does the same.
##
## Everything — terrain generation, the populace AI, every power's effect, the
## rival god's heuristic, breeding, expansion, win/loss — is a pure function of
## (state, tick, seeded RNG). The same seed + the same scripted divine commands
## always yield a BYTE-IDENTICAL world+tribes after N ticks. No engine/scene
## dependencies: this class is fully headless-testable.
##
## STORAGE (packed + serializable):
##   _height : PackedByteArray  — terrain height per cell (row-major i = y*W + x)
##   _res    : PackedByteArray  — resource flag per cell (RES_*)
##   villagers/huts             — parallel PackedInt32Arrays (compact, id-stable)
##   _belief/_wood              — per-tribe pools (index 0 = you, 1 = rival)
##
## TICK DISCIPLINE (why it stays deterministic AND terminates):
##   tick() runs a fixed pipeline — accrue belief → apply queued player powers →
##   rival god decides+casts → advance every villager ONE cell (index order) →
##   advance huts (flood/breed) → compact the dead → judge win/loss. No step does
##   an unbounded rescan: villagers search for resources only inside a bounded
##   radius and only when idle, so a tick is O(V·R² + W·H) with small constants.
##   Every stochastic choice (terrain, breeding, wander, rival tie-breaks) draws
##   from the SEEDED RNG whose state is saved — so replays are exact.

# =====================================================================
#  Tribes
# =====================================================================
const YOU := 0     ## the player's tribe
const RIVAL := 1   ## the rival god's tribe
const TRIBE_COUNT := 2

# =====================================================================
#  Terrain
# =====================================================================
const SEA_LEVEL := 100    ## height < SEA_LEVEL is water (impassable); >= is land
const LAND_MAX := 255
const DEEP_WATER := 60     ## a cell this low is deep — a villager on it drowns fast

## Resource flags (a cell holds at most one).
const RES_NONE := 0
const RES_FOREST := 1     ## a renewable WOOD source (villagers fell it for wood)
const RES_FOOD := 2       ## a renewable FOOD source (villagers forage it for food)

# =====================================================================
#  Villager state machine
# =====================================================================
const ST_IDLE := 0     ## deciding what to do next
const ST_GATHER := 1   ## walking to a resource cell to harvest
const ST_RETURN := 2   ## carrying a resource back to the home hut
const ST_BUILD := 3    ## walking to a build site to raise a new hut
const ST_FLEE := 4     ## standing in / next to water — escaping to dry land

## What a villager is carrying home.
const CARRY_NONE := 0
const CARRY_WOOD := 1
const CARRY_FOOD := 2

# =====================================================================
#  Divine powers (>= 5, each a real effect)
# =====================================================================
const P_RAISE_LAND := 0   ## raise cells above sea → new buildable land / land-bridges
const P_LOWER_LAND := 1   ## sink cells below sea → flood land, drown/scatter followers
const P_GROW_FOOD := 2     ## bless the land with food → attracts + breeds your tribe
const P_INSPIRE := 3       ## inspire your followers near a point → faster gather/breed
const P_MIRACLE := 4       ## a miracle → CONVERT nearby rival followers to your tribe
const POWER_COUNT := 5

## Belief cost of each power (index == power id).
const POWER_COST: PackedInt32Array = [20, 30, 25, 15, 40]
const POWER_NAME: PackedStringArray = [
	"Raise Land", "Lower Land", "Grow Food", "Inspire", "Miracle",
]

# =====================================================================
#  Tuning (auditable constants)
# =====================================================================
const POWER_RADIUS := 3        ## most powers act over this disc radius
const GATHER_RADIUS := 11      ## how far an idle villager looks for a resource
const WOOD_PER_TRIP := 2       ## wood banked per forest trip (×2 while inspired)
const FOOD_PER_TRIP := 3       ## food banked at the hut per forage trip (×2 inspired)
const BREED_COST := 16         ## food a hut consumes to spawn one new villager
const HUT_WOOD_COST := 6       ## tribe wood spent to raise a new hut
const VILLAGERS_PER_HUT := 3   ## a tribe expands once pop exceeds huts × this
const POP_CAP := 60            ## hard cap on a tribe's population (keeps ticks bounded)
const INSPIRE_TICKS := 60      ## how long an inspired villager stays boosted
const DROWN_TICKS := 4         ## ticks a follower survives stranded on water
const FOOD_BOUNTY := 16        ## instant food a GROW_FOOD grants the nearest hut
const BELIEF_PER_POP := 1      ## belief a tribe accrues per follower per tick
const RIVAL_REACH := 22        ## how far the rival god reaches to strike your tribe
const RIVAL_FOOD_TARGET := 30  ## rival keeps growing (Grow Food) until this pop
const WIN_POP := 30            ## reach this pop AND lead the rival to win
const TICK_CAP := 4000         ## a game is judged by pop at this tick if nobody won

## 8-neighbour offsets in a fixed, deterministic order.
const NB8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

# =====================================================================
#  State
# =====================================================================
var width: int = 0
var height: int = 0
var tick: int = 0
var winner: int = -1               ## -1 ongoing, YOU(0) or RIVAL(1) once decided

var _height := PackedByteArray()   ## terrain height per cell
var _res := PackedByteArray()      ## resource flag per cell

# Per-tribe pools (index by tribe).
var _belief: PackedInt32Array = PackedInt32Array([0, 0])
var _wood: PackedInt32Array = PackedInt32Array([0, 0])

# Villagers — parallel arrays, kept compact (dead ones removed each tick).
var _vx := PackedInt32Array()
var _vy := PackedInt32Array()
var _vtribe := PackedInt32Array()
var _vstate := PackedInt32Array()
var _vcarry := PackedInt32Array()
var _vhome := PackedInt32Array()    ## hut id this villager belongs to (-1 homeless)
var _vboost := PackedInt32Array()   ## inspire ticks remaining
var _vtx := PackedInt32Array()      ## current target cell x (-1 none)
var _vty := PackedInt32Array()      ## current target cell y
var _vflood := PackedInt32Array()   ## consecutive ticks stranded on water

# Huts — parallel arrays, id-stable.
var _hx := PackedInt32Array()
var _hy := PackedInt32Array()
var _htribe := PackedInt32Array()
var _hstore := PackedInt32Array()   ## food banked toward the next birth
var _hid := PackedInt32Array()      ## stable id (never reused)
var _next_hut_id: int = 0

var _pending: Array = []            ## queued player powers for the next tick
var _rng := RandomNumberGenerator.new()


# =====================================================================
#  Lifecycle
# =====================================================================

## Build a fresh W×H world with two starting tribes. seed == 0 → randomised;
## any other value is fully deterministic.
func setup(w: int, h: int, seed_value: int = 0) -> void:
	width = maxi(8, w)
	height = maxi(8, h)
	tick = 0
	winner = -1
	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_belief = PackedInt32Array([0, 0])
	_wood = PackedInt32Array([0, 0])
	_clear_populace()
	_next_hut_id = 0
	_pending = []
	_generate_terrain()
	# Two rival settlements on opposite flanks of the map.
	_place_tribe(YOU, int(width * 0.20), int(height * 0.5))
	_place_tribe(RIVAL, int(width * 0.80), int(height * 0.5))


func _clear_populace() -> void:
	_vx = PackedInt32Array()
	_vy = PackedInt32Array()
	_vtribe = PackedInt32Array()
	_vstate = PackedInt32Array()
	_vcarry = PackedInt32Array()
	_vhome = PackedInt32Array()
	_vboost = PackedInt32Array()
	_vtx = PackedInt32Array()
	_vty = PackedInt32Array()
	_vflood = PackedInt32Array()
	_hx = PackedInt32Array()
	_hy = PackedInt32Array()
	_htribe = PackedInt32Array()
	_hstore = PackedInt32Array()
	_hid = PackedInt32Array()


# --- terrain generation ----------------------------------------------------

## Rolling hills from the seed: random field → box-blur passes → some water pools,
## then forests + food scattered on the land.
func _generate_terrain() -> void:
	var n := width * height
	_height = PackedByteArray()
	_height.resize(n)
	_res = PackedByteArray()
	_res.resize(n)
	for i in n:
		_height[i] = _rng.randi_range(0, 255)
	for _pass in 3:
		_height = _blur(_height)
	for y in height:
		for x in width:
			var i := y * width + x
			if _height[i] >= SEA_LEVEL:
				var r := _rng.randf()
				if r < 0.10:
					_res[i] = RES_FOREST
				elif r < 0.13:
					_res[i] = RES_FOOD
				else:
					_res[i] = RES_NONE
			else:
				_res[i] = RES_NONE


## 3×3 box blur (edge-clamped) — turns white noise into smooth terrain.
func _blur(src: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(src.size())
	for y in height:
		for x in width:
			var sum := 0
			var cnt := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx := clampi(x + dx, 0, width - 1)
					var ny := clampi(y + dy, 0, height - 1)
					sum += src[ny * width + nx]
					cnt += 1
			out[y * width + x] = int(sum / cnt)
	return out


## Force a dry platform + a starter settlement (1 hut, 4 villagers) and seed
## nearby wood + food so the tribe is viable from tick 0.
func _place_tribe(tribe: int, cx: int, cy: int) -> void:
	cx = clampi(cx, 4, width - 5)
	cy = clampi(cy, 4, height - 5)
	# Raise a dry buildable platform.
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var x := cx + dx
			var y := cy + dy
			if in_bounds(x, y) and dx * dx + dy * dy <= 30:
				var i := y * width + x
				_height[i] = maxi(_height[i], SEA_LEVEL + 40)
				_res[i] = RES_NONE
	# The founding hut.
	_add_hut(cx, cy, tribe)
	# Nearby renewable resources (two forests, two food groves).
	_seed_res(cx + 3, cy, RES_FOREST)
	_seed_res(cx - 3, cy, RES_FOREST)
	_seed_res(cx, cy + 3, RES_FOOD)
	_seed_res(cx, cy - 3, RES_FOOD)
	_seed_res(cx + 2, cy + 2, RES_FOOD)
	# Four founding villagers around the hut.
	var spots: Array[Vector2i] = [
		Vector2i(cx + 1, cy), Vector2i(cx - 1, cy),
		Vector2i(cx, cy + 1), Vector2i(cx, cy - 1),
	]
	for s in spots:
		_add_villager(s.x, s.y, tribe, _hid[_hut_index_at(cx, cy)])


func _seed_res(x: int, y: int, res: int) -> void:
	if in_bounds(x, y) and _height[y * width + x] >= SEA_LEVEL:
		_res[y * width + x] = res


# =====================================================================
#  Grid queries
# =====================================================================

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func height_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return _height[y * width + x]


func res_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return RES_NONE
	return _res[y * width + x]


## Land = walkable/standable (height at or above sea level).
func is_land(x: int, y: int) -> bool:
	return in_bounds(x, y) and _height[y * width + x] >= SEA_LEVEL


func is_water(x: int, y: int) -> bool:
	return in_bounds(x, y) and _height[y * width + x] < SEA_LEVEL


## Buildable = dry land, no resource on it, no hut on it.
func is_buildable(x: int, y: int) -> bool:
	if not is_land(x, y):
		return false
	if _res[y * width + x] != RES_NONE:
		return false
	return _hut_index_at(x, y) < 0


func get_height() -> PackedByteArray:
	return _height


func get_res() -> PackedByteArray:
	return _res


func belief_of(tribe: int) -> int:
	return _belief[tribe]


func wood_of(tribe: int) -> int:
	return _wood[tribe]


func rng_state() -> int:
	return _rng.state


## Grant belief to a tribe (divine favour / a quest reward / a shrine). Public so
## the game layer can feed the economy and tests can set up a cast.
func grant_belief(tribe: int, amount: int) -> void:
	_belief[tribe] = maxi(0, _belief[tribe] + amount)


# =====================================================================
#  Villager + hut storage helpers
# =====================================================================

func villager_count() -> int:
	return _vx.size()


func hut_count() -> int:
	return _hx.size()


## Population (living villagers) of a tribe.
func population(tribe: int) -> int:
	var c := 0
	for i in _vtribe.size():
		if _vtribe[i] == tribe:
			c += 1
	return c


func huts_of(tribe: int) -> int:
	var c := 0
	for i in _htribe.size():
		if _htribe[i] == tribe:
			c += 1
	return c


## Read-only villager snapshot for the renderer: {x,y,tribe,state,carry,boost}.
func villager_info(i: int) -> Dictionary:
	return {
		"x": _vx[i], "y": _vy[i], "tribe": _vtribe[i], "state": _vstate[i],
		"carry": _vcarry[i], "boost": _vboost[i],
	}


func hut_info(i: int) -> Dictionary:
	return {"x": _hx[i], "y": _hy[i], "tribe": _htribe[i], "store": _hstore[i], "id": _hid[i]}


func _add_villager(x: int, y: int, tribe: int, home_id: int) -> void:
	_vx.append(x)
	_vy.append(y)
	_vtribe.append(tribe)
	_vstate.append(ST_IDLE)
	_vcarry.append(CARRY_NONE)
	_vhome.append(home_id)
	_vboost.append(0)
	_vtx.append(-1)
	_vty.append(-1)
	_vflood.append(0)


func _add_hut(x: int, y: int, tribe: int) -> int:
	var id := _next_hut_id
	_next_hut_id += 1
	_hx.append(x)
	_hy.append(y)
	_htribe.append(tribe)
	_hstore.append(0)
	_hid.append(id)
	return id


func _hut_index_at(x: int, y: int) -> int:
	for i in _hx.size():
		if _hx[i] == x and _hy[i] == y:
			return i
	return -1


func _hut_index_of_id(id: int) -> int:
	for i in _hid.size():
		if _hid[i] == id:
			return i
	return -1


# =====================================================================
#  Powers — legality + effect
# =====================================================================

## Queue a player power to apply at the START of the next tick(). Returns false
## (and queues nothing) if it is illegal RIGHT NOW.
func queue_power(power: int, tribe: int, x: int, y: int) -> bool:
	if not is_legal(power, tribe, x, y):
		return false
	_pending.append({"power": power, "tribe": tribe, "x": x, "y": y})
	return true


## True iff `tribe` could legally cast `power` at (x,y) this instant: in bounds,
## enough belief, and a valid target for that specific power.
func is_legal(power: int, tribe: int, x: int, y: int) -> bool:
	if winner != -1:
		return false
	if power < 0 or power >= POWER_COUNT:
		return false
	if not in_bounds(x, y):
		return false
	if _belief[tribe] < POWER_COST[power]:
		return false
	match power:
		P_RAISE_LAND:
			# Only meaningful on cells not already at max height.
			return _height[y * width + x] < LAND_MAX
		P_LOWER_LAND:
			# Must be land to flood (lowering water is a no-op → illegal).
			return is_land(x, y)
		P_GROW_FOOD:
			# Bless dry land only.
			return is_land(x, y)
		P_INSPIRE:
			# Needs at least one of YOUR followers within the disc.
			return _has_villager_near(x, y, POWER_RADIUS, tribe, true)
		P_MIRACLE:
			# Needs at least one ENEMY follower within the disc.
			return _has_villager_near(x, y, POWER_RADIUS, tribe, false)
	return false


## Cast immediately (used by the rival AI and by tests). Spends belief + applies
## the effect. Returns false if illegal (state untouched).
func cast_power(power: int, tribe: int, x: int, y: int) -> bool:
	if not is_legal(power, tribe, x, y):
		return false
	_belief[tribe] -= POWER_COST[power]
	match power:
		P_RAISE_LAND:
			_apply_raise(x, y)
		P_LOWER_LAND:
			_apply_lower(x, y)
		P_GROW_FOOD:
			_apply_grow_food(x, y, tribe)
		P_INSPIRE:
			_apply_inspire(x, y, tribe)
		P_MIRACLE:
			_apply_miracle(x, y, tribe)
	return true


func _has_villager_near(x: int, y: int, radius: int, tribe: int, same: bool) -> bool:
	var r2 := radius * radius
	for i in _vx.size():
		var dx := _vx[i] - x
		var dy := _vy[i] - y
		if dx * dx + dy * dy <= r2:
			var is_same := _vtribe[i] == tribe
			if is_same == same:
				return true
	return false


## RAISE_LAND: push every cell in the disc upward; a water cell rises past sea
## level and becomes buildable land (or extends a land-bridge).
func _apply_raise(cx: int, cy: int) -> void:
	var r2 := POWER_RADIUS * POWER_RADIUS
	for dy in range(-POWER_RADIUS, POWER_RADIUS + 1):
		for dx in range(-POWER_RADIUS, POWER_RADIUS + 1):
			if dx * dx + dy * dy <= r2:
				var x := cx + dx
				var y := cy + dy
				if in_bounds(x, y):
					var i := y * width + x
					_height[i] = mini(LAND_MAX, _height[i] + 60)


## LOWER_LAND: sink the disc below sea level (a flood). Any follower standing on
## a now-flooded cell is thrown into ST_FLEE immediately; one on DEEP water
## drowns at once. Huts on flooded cells are washed away.
func _apply_lower(cx: int, cy: int) -> void:
	var r2 := POWER_RADIUS * POWER_RADIUS
	for dy in range(-POWER_RADIUS, POWER_RADIUS + 1):
		for dx in range(-POWER_RADIUS, POWER_RADIUS + 1):
			if dx * dx + dy * dy <= r2:
				var x := cx + dx
				var y := cy + dy
				if in_bounds(x, y):
					var i := y * width + x
					_height[i] = maxi(0, _height[i] - 80)
					if _height[i] < SEA_LEVEL:
						_res[i] = RES_NONE
	# React: flee/drown villagers, wash away huts on the newly flooded cells.
	for i in _vx.size():
		if is_water(_vx[i], _vy[i]):
			if _height[_vy[i] * width + _vx[i]] < DEEP_WATER:
				_vtribe[i] = -1   # drowned → removed on compaction
			else:
				_vstate[i] = ST_FLEE
				_vcarry[i] = CARRY_NONE
	for i in _hx.size():
		if is_water(_hx[i], _hy[i]):
			_htribe[i] = -1


## GROW_FOOD: bless the disc with food sources AND drop an instant FOOD_BOUNTY
## into the caster's nearest hut so the settlement visibly grows over the next
## few ticks. The new food cells also ATTRACT foragers (they seek nearest food).
func _apply_grow_food(cx: int, cy: int, tribe: int) -> void:
	var r2 := POWER_RADIUS * POWER_RADIUS
	for dy in range(-POWER_RADIUS, POWER_RADIUS + 1):
		for dx in range(-POWER_RADIUS, POWER_RADIUS + 1):
			if dx * dx + dy * dy <= r2:
				var x := cx + dx
				var y := cy + dy
				if is_land(x, y) and _hut_index_at(x, y) < 0:
					_res[y * width + x] = RES_FOOD
	var hi := _nearest_hut_index(cx, cy, tribe)
	if hi >= 0:
		_hstore[hi] += FOOD_BOUNTY


## INSPIRE: light a fire under YOUR followers in the disc — each gets an
## INSPIRE_TICKS boost that doubles what they bank per trip (faster wood/food →
## faster building + breeding).
func _apply_inspire(cx: int, cy: int, tribe: int) -> void:
	var r2 := POWER_RADIUS * POWER_RADIUS
	for i in _vx.size():
		if _vtribe[i] != tribe:
			continue
		var dx := _vx[i] - cx
		var dy := _vy[i] - cy
		if dx * dx + dy * dy <= r2:
			_vboost[i] = INSPIRE_TICKS


## MIRACLE: a display of divine power. Every RIVAL follower in the disc is
## CONVERTED to the caster's tribe (rehomed to the caster's nearest hut). If the
## caster has no hut they still defect and become homeless foragers.
func _apply_miracle(cx: int, cy: int, tribe: int) -> void:
	var r2 := POWER_RADIUS * POWER_RADIUS
	var hi := _nearest_hut_index(cx, cy, tribe)
	var new_home := _hid[hi] if hi >= 0 else -1
	for i in _vx.size():
		if _vtribe[i] == tribe or _vtribe[i] < 0:
			continue
		var dx := _vx[i] - cx
		var dy := _vy[i] - cy
		if dx * dx + dy * dy <= r2:
			_vtribe[i] = tribe
			_vhome[i] = new_home
			_vstate[i] = ST_IDLE
			_vcarry[i] = CARRY_NONE


func _nearest_hut_index(x: int, y: int, tribe: int) -> int:
	var best := -1
	var best_d := 1 << 30
	for i in _hx.size():
		if _htribe[i] != tribe:
			continue
		var dx := _hx[i] - x
		var dy := _hy[i] - y
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = i
	return best


# =====================================================================
#  The tick — one deterministic step of the whole world
# =====================================================================

func tick_world() -> void:
	if winner != -1:
		return
	tick += 1
	# 1) belief accrues from congregation size.
	for t in TRIBE_COUNT:
		_belief[t] += population(t) * BELIEF_PER_POP
	# 2) queued player powers.
	for cmd in _pending:
		cast_power(int(cmd["power"]), int(cmd["tribe"]), int(cmd["x"]), int(cmd["y"]))
	_pending = []
	# 3) the rival god acts.
	_rival_ai()
	# 4) advance the populace (index order → deterministic).
	for i in _vx.size():
		if _vtribe[i] < 0:
			continue
		_update_villager(i)
	# 5) advance huts (flood check + breeding).
	_update_huts()
	# 6) compact away the dead.
	_compact()
	# 7) judge the game.
	_judge()


# --- movement --------------------------------------------------------------

## Step villager i ONE cell toward (tx,ty) over walkable land. Returns true when
## it is already standing on the target. Tries the diagonal, then each axis, in a
## fixed order (deterministic); if fully blocked it holds position.
func _step_toward(i: int, tx: int, ty: int) -> bool:
	var x := _vx[i]
	var y := _vy[i]
	if x == tx and y == ty:
		return true
	var sx := signi(tx - x)
	var sy := signi(ty - y)
	var tries: Array[Vector2i] = []
	if sx != 0 and sy != 0:
		tries.append(Vector2i(sx, sy))
	if absi(tx - x) >= absi(ty - y):
		if sx != 0:
			tries.append(Vector2i(sx, 0))
		if sy != 0:
			tries.append(Vector2i(0, sy))
	else:
		if sy != 0:
			tries.append(Vector2i(0, sy))
		if sx != 0:
			tries.append(Vector2i(sx, 0))
	for step in tries:
		var nx := x + step.x
		var ny := y + step.y
		if is_land(nx, ny):
			_vx[i] = nx
			_vy[i] = ny
			return nx == tx and ny == ty
	return false


func _update_villager(i: int) -> void:
	if _vboost[i] > 0:
		_vboost[i] -= 1
	# Stranded on water? Flee no matter the current plan.
	if is_water(_vx[i], _vy[i]) and _vstate[i] != ST_FLEE:
		_vstate[i] = ST_FLEE
		_vcarry[i] = CARRY_NONE
	match _vstate[i]:
		ST_IDLE:
			_decide(i)
		ST_GATHER:
			_do_gather(i)
		ST_RETURN:
			_do_return(i)
		ST_BUILD:
			_do_build(i)
		ST_FLEE:
			_do_flee(i)


## An idle villager's priorities, in order:
##   1. If the tribe is overcrowded and can already afford a hut (and nobody is
##      mid-build), go raise a new one — settlement EXPANSION.
##   2. If the tribe is overcrowded but short on wood, go fell the nearest FOREST
##      to fund that hut (so expansion is always financed, never starved).
##   3. Otherwise forage the nearest resource (food-led growth); wander if none.
func _decide(i: int) -> void:
	var tribe := _vtribe[i]
	var overcrowded := population(tribe) > huts_of(tribe) * VILLAGERS_PER_HUT
	if overcrowded and _wood[tribe] >= HUT_WOOD_COST and not _has_builder(tribe):
		var spot := _find_build_spot(_vx[i], _vy[i])
		if spot.x >= 0:
			_vstate[i] = ST_BUILD
			_vtx[i] = spot.x
			_vty[i] = spot.y
			return
	if overcrowded and _wood[tribe] < HUT_WOOD_COST:
		var forest := _nearest_resource_of(_vx[i], _vy[i], RES_FOREST)
		if forest.x >= 0:
			_vstate[i] = ST_GATHER
			_vtx[i] = forest.x
			_vty[i] = forest.y
			return
	var target := _nearest_resource(_vx[i], _vy[i])
	if target.x >= 0:
		_vstate[i] = ST_GATHER
		_vtx[i] = target.x
		_vty[i] = target.y
		return
	_wander(i)


## True if a clansman of `tribe` is already walking out to build (so the tribe
## raises ONE hut at a time — controlled sprawl, not a build frenzy).
func _has_builder(tribe: int) -> bool:
	for j in _vx.size():
		if _vtribe[j] == tribe and _vstate[j] == ST_BUILD:
			return true
	return false


func _do_gather(i: int) -> void:
	# Target no longer a resource (e.g. flooded)? Rethink.
	if res_at(_vtx[i], _vty[i]) == RES_NONE:
		_vstate[i] = ST_IDLE
		return
	if _step_toward(i, _vtx[i], _vty[i]):
		var res := res_at(_vx[i], _vy[i])
		_vcarry[i] = CARRY_WOOD if res == RES_FOREST else CARRY_FOOD
		_vstate[i] = ST_RETURN
		_vtx[i] = -1
		_vty[i] = -1


func _do_return(i: int) -> void:
	var hi := _hut_index_of_id(_vhome[i])
	if hi < 0 or _htribe[hi] != _vtribe[i]:
		# Home lost → adopt the nearest surviving hut of the tribe.
		hi = _nearest_hut_index(_vx[i], _vy[i], _vtribe[i])
		if hi < 0:
			# Homeless with no hut anywhere: drop the load and forage.
			_vcarry[i] = CARRY_NONE
			_vstate[i] = ST_IDLE
			return
		_vhome[i] = _hid[hi]
	if _step_toward(i, _hx[hi], _hy[hi]):
		_deposit(i, hi)


func _deposit(i: int, hi: int) -> void:
	var mult := 2 if _vboost[i] > 0 else 1
	if _vcarry[i] == CARRY_WOOD:
		_wood[_vtribe[i]] += WOOD_PER_TRIP * mult
	elif _vcarry[i] == CARRY_FOOD:
		_hstore[hi] += FOOD_PER_TRIP * mult
	_vcarry[i] = CARRY_NONE
	_vstate[i] = ST_IDLE


func _do_build(i: int) -> void:
	if not is_buildable(_vtx[i], _vty[i]):
		_vstate[i] = ST_IDLE
		return
	if _step_toward(i, _vtx[i], _vty[i]):
		if _wood[_vtribe[i]] >= HUT_WOOD_COST:
			_wood[_vtribe[i]] -= HUT_WOOD_COST
			var id := _add_hut(_vx[i], _vy[i], _vtribe[i])
			_vhome[i] = id
		_vstate[i] = ST_IDLE
		_vtx[i] = -1
		_vty[i] = -1


func _do_flee(i: int) -> void:
	if is_land(_vx[i], _vy[i]):
		_vflood[i] = 0
		_vstate[i] = ST_IDLE
		return
	_vflood[i] += 1
	if _vflood[i] >= DROWN_TICKS:
		_vtribe[i] = -1   # drowned
		return
	var safe := _nearest_land(_vx[i], _vy[i])
	if safe.x >= 0:
		_step_toward(i, safe.x, safe.y)


func _wander(i: int) -> void:
	var order := _rng.randi() % 8
	for k in 8:
		var off := NB8[(order + k) % 8]
		var nx := _vx[i] + off.x
		var ny := _vy[i] + off.y
		if is_land(nx, ny):
			_vx[i] = nx
			_vy[i] = ny
			return


# --- resource / land search (bounded radius, deterministic tie-break) -------

## Nearest resource cell to (x,y) within GATHER_RADIUS by squared distance;
## ties broken by row-major scan order. (-1,-1) if none in reach.
func _nearest_resource(x: int, y: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for dy in range(-GATHER_RADIUS, GATHER_RADIUS + 1):
		for dx in range(-GATHER_RADIUS, GATHER_RADIUS + 1):
			var nx := x + dx
			var ny := y + dy
			if not in_bounds(nx, ny):
				continue
			if _res[ny * width + nx] == RES_NONE:
				continue
			var d := dx * dx + dy * dy
			if d < best_d:
				best_d = d
				best = Vector2i(nx, ny)
	return best


## Nearest cell of a SPECIFIC resource type within GATHER_RADIUS (deterministic
## tie-break) — used to steer foragers onto forests when the tribe needs wood.
func _nearest_resource_of(x: int, y: int, restype: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for dy in range(-GATHER_RADIUS, GATHER_RADIUS + 1):
		for dx in range(-GATHER_RADIUS, GATHER_RADIUS + 1):
			var nx := x + dx
			var ny := y + dy
			if not in_bounds(nx, ny):
				continue
			if _res[ny * width + nx] != restype:
				continue
			var d := dx * dx + dy * dy
			if d < best_d:
				best_d = d
				best = Vector2i(nx, ny)
	return best


## Nearest dry land to (x,y) within a small radius (for fleeing water).
func _nearest_land(x: int, y: int) -> Vector2i:
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var nx := x + dx
				var ny := y + dy
				if is_land(nx, ny):
					return Vector2i(nx, ny)
	return Vector2i(-1, -1)


## A buildable cell close to (x,y) that neighbours a resource (settlements grow
## next to what feeds them). Searches nearest-first; deterministic tie-break.
func _find_build_spot(x: int, y: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var nx := x + dx
			var ny := y + dy
			if not is_buildable(nx, ny):
				continue
			if not _near_resource(nx, ny, 2):
				continue
			var d := dx * dx + dy * dy
			if d < best_d:
				best_d = d
				best = Vector2i(nx, ny)
	return best


func _near_resource(x: int, y: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if res_at(x + dx, y + dy) != RES_NONE:
				return true
	return false


# --- huts ------------------------------------------------------------------

func _update_huts() -> void:
	for i in _hx.size():
		if _htribe[i] < 0:
			continue
		if is_water(_hx[i], _hy[i]):
			_htribe[i] = -1
			continue
		# Breed while fed and under the population cap.
		if _hstore[i] >= BREED_COST and population(_htribe[i]) < POP_CAP:
			_hstore[i] -= BREED_COST
			_add_villager(_hx[i], _hy[i], _htribe[i], _hid[i])


# --- rival god heuristic (deterministic, non-LLM) --------------------------

## The rival god accrues belief like you and spends it on a fixed priority
## ladder: (1) MIRACLE-convert one of YOUR followers that has strayed near its
## land, (2) GROW_FOOD for itself while below its target size, (3) LOWER_LAND to
## flood your hut nearest to it. Every target is chosen by nearest distance with
## a deterministic tie-break, so its play is fully reproducible.
func _rival_ai() -> void:
	if winner != -1:
		return
	var home := _nearest_hut_index(0, 0, RIVAL)
	if home < 0:
		return   # no seat of power → the rival can cast nothing meaningful
	var hx := _hx[home]
	var hy := _hy[home]
	var b := _belief[RIVAL]
	# (1) Convert a nearby enemy follower.
	if b >= POWER_COST[P_MIRACLE]:
		var prey := _nearest_enemy_villager(hx, hy, RIVAL, RIVAL_REACH)
		if prey.x >= 0 and cast_power(P_MIRACLE, RIVAL, prey.x, prey.y):
			return
	# (2) Grow its own tribe.
	if b >= POWER_COST[P_GROW_FOOD] and population(RIVAL) < RIVAL_FOOD_TARGET:
		var spot := _rival_food_spot(hx, hy)
		if spot.x >= 0 and cast_power(P_GROW_FOOD, RIVAL, spot.x, spot.y):
			return
	# (3) Flood your nearest settlement.
	if b >= POWER_COST[P_LOWER_LAND]:
		var target := _nearest_enemy_hut(hx, hy, RIVAL)
		if target.x >= 0 and cast_power(P_LOWER_LAND, RIVAL, target.x, target.y):
			return


func _nearest_enemy_villager(x: int, y: int, tribe: int, reach: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := reach * reach + 1
	for i in _vx.size():
		if _vtribe[i] == tribe or _vtribe[i] < 0:
			continue
		var dx := _vx[i] - x
		var dy := _vy[i] - y
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = Vector2i(_vx[i], _vy[i])
	return best


func _nearest_enemy_hut(x: int, y: int, tribe: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for i in _hx.size():
		if _htribe[i] == tribe or _htribe[i] < 0:
			continue
		var dx := _hx[i] - x
		var dy := _hy[i] - y
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = Vector2i(_hx[i], _hy[i])
	return best


## A dry cell one step off the rival's hut to bless with food (falls back to the
## hut itself, which is always land).
func _rival_food_spot(hx: int, hy: int) -> Vector2i:
	for off in NB8:
		if is_land(hx + off.x, hy + off.y):
			return Vector2i(hx + off.x, hy + off.y)
	return Vector2i(hx, hy)


# --- compaction + judging --------------------------------------------------

## Remove villagers/huts flagged dead (tribe < 0), rebuilding the packed arrays.
## Runs once per tick so indices only shift at a stable point.
func _compact() -> void:
	if _vtribe.find(-1) != -1:
		var nx := PackedInt32Array()
		var ny := PackedInt32Array()
		var nt := PackedInt32Array()
		var ns := PackedInt32Array()
		var nc := PackedInt32Array()
		var nh := PackedInt32Array()
		var nb := PackedInt32Array()
		var ntx := PackedInt32Array()
		var nty := PackedInt32Array()
		var nf := PackedInt32Array()
		for i in _vtribe.size():
			if _vtribe[i] < 0:
				continue
			nx.append(_vx[i]); ny.append(_vy[i]); nt.append(_vtribe[i])
			ns.append(_vstate[i]); nc.append(_vcarry[i]); nh.append(_vhome[i])
			nb.append(_vboost[i]); ntx.append(_vtx[i]); nty.append(_vty[i])
			nf.append(_vflood[i])
		_vx = nx; _vy = ny; _vtribe = nt; _vstate = ns; _vcarry = nc
		_vhome = nh; _vboost = nb; _vtx = ntx; _vty = nty; _vflood = nf
	if _htribe.find(-1) != -1:
		var mx := PackedInt32Array()
		var my := PackedInt32Array()
		var mt := PackedInt32Array()
		var msr := PackedInt32Array()
		var mid := PackedInt32Array()
		for i in _htribe.size():
			if _htribe[i] < 0:
				continue
			mx.append(_hx[i]); my.append(_hy[i]); mt.append(_htribe[i])
			msr.append(_hstore[i]); mid.append(_hid[i])
		_hx = mx; _hy = my; _htribe = mt; _hstore = msr; _hid = mid


## Decide the winner. Reachable both ways: eliminate the rival (or hit WIN_POP
## while leading) to WIN; be wiped out (or let the rival hit WIN_POP first) to
## LOSE; at the tick cap the larger tribe takes it (tie → you).
func _judge() -> void:
	if winner != -1:
		return
	var p0 := population(YOU)
	var p1 := population(RIVAL)
	var h0 := huts_of(YOU)
	var h1 := huts_of(RIVAL)
	if p0 == 0 and h0 == 0:
		winner = RIVAL
	elif p1 == 0 and h1 == 0:
		winner = YOU
	elif p0 >= WIN_POP and p0 > p1:
		winner = YOU
	elif p1 >= WIN_POP and p1 > p0:
		winner = RIVAL
	elif tick >= TICK_CAP:
		winner = YOU if p0 >= p1 else RIVAL


# =====================================================================
#  Determinism helper + persistence
# =====================================================================

## FNV-1a-style checksum of the whole simulation. Two worlds are byte-identical
## iff their checksums (and arrays) match — the determinism probe compares this.
func checksum() -> int:
	var h: int = 1469598103934665603
	h = _mix_bytes(h, _height)
	h = _mix_bytes(h, _res)
	h = _mix_ints(h, _vx)
	h = _mix_ints(h, _vy)
	h = _mix_ints(h, _vtribe)
	h = _mix_ints(h, _vstate)
	h = _mix_ints(h, _vcarry)
	h = _mix_ints(h, _vhome)
	h = _mix_ints(h, _vboost)
	h = _mix_ints(h, _vflood)
	h = _mix_ints(h, _hx)
	h = _mix_ints(h, _hy)
	h = _mix_ints(h, _htribe)
	h = _mix_ints(h, _hstore)
	h = _mix_ints(h, _hid)
	h = _mix_ints(h, _belief)
	h = _mix_ints(h, _wood)
	h = (h ^ tick) & 0x7FFFFFFFFFFFFFFF
	h = (h ^ (winner + 2)) & 0x7FFFFFFFFFFFFFFF
	return h


func _mix_bytes(h: int, arr: PackedByteArray) -> int:
	for i in arr.size():
		h = (h ^ int(arr[i])) * 1099511628211
		h = h & 0x7FFFFFFFFFFFFFFF
	return h


func _mix_ints(h: int, arr: PackedInt32Array) -> int:
	for i in arr.size():
		h = (h ^ (int(arr[i]) & 0xFFFFFFFF)) * 1099511628211
		h = h & 0x7FFFFFFFFFFFFFFF
	return h


## Full portable snapshot including RNG state, so a reload replays byte-for-byte.
func snapshot() -> Dictionary:
	return {
		"w": width, "h": height, "tick": tick, "winner": winner,
		"height": Marshalls.raw_to_base64(_height),
		"res": Marshalls.raw_to_base64(_res),
		"belief": Marshalls.raw_to_base64(_belief.to_byte_array()),
		"wood": Marshalls.raw_to_base64(_wood.to_byte_array()),
		"vx": Marshalls.raw_to_base64(_vx.to_byte_array()),
		"vy": Marshalls.raw_to_base64(_vy.to_byte_array()),
		"vtribe": Marshalls.raw_to_base64(_vtribe.to_byte_array()),
		"vstate": Marshalls.raw_to_base64(_vstate.to_byte_array()),
		"vcarry": Marshalls.raw_to_base64(_vcarry.to_byte_array()),
		"vhome": Marshalls.raw_to_base64(_vhome.to_byte_array()),
		"vboost": Marshalls.raw_to_base64(_vboost.to_byte_array()),
		"vtx": Marshalls.raw_to_base64(_vtx.to_byte_array()),
		"vty": Marshalls.raw_to_base64(_vty.to_byte_array()),
		"vflood": Marshalls.raw_to_base64(_vflood.to_byte_array()),
		"hx": Marshalls.raw_to_base64(_hx.to_byte_array()),
		"hy": Marshalls.raw_to_base64(_hy.to_byte_array()),
		"htribe": Marshalls.raw_to_base64(_htribe.to_byte_array()),
		"hstore": Marshalls.raw_to_base64(_hstore.to_byte_array()),
		"hid": Marshalls.raw_to_base64(_hid.to_byte_array()),
		"next_hut_id": _next_hut_id,
		"pending": _pending.duplicate(true),
		"rng_seed": _rng.seed,
		"rng_state": _rng.state,
	}


func restore(d: Dictionary) -> void:
	width = int(d.get("w", width))
	height = int(d.get("h", height))
	tick = int(d.get("tick", 0))
	winner = int(d.get("winner", -1))
	_height = Marshalls.base64_to_raw(String(d.get("height", "")))
	_res = Marshalls.base64_to_raw(String(d.get("res", "")))
	_belief = _ints(d.get("belief", ""))
	_wood = _ints(d.get("wood", ""))
	_vx = _ints(d.get("vx", ""))
	_vy = _ints(d.get("vy", ""))
	_vtribe = _ints(d.get("vtribe", ""))
	_vstate = _ints(d.get("vstate", ""))
	_vcarry = _ints(d.get("vcarry", ""))
	_vhome = _ints(d.get("vhome", ""))
	_vboost = _ints(d.get("vboost", ""))
	_vtx = _ints(d.get("vtx", ""))
	_vty = _ints(d.get("vty", ""))
	_vflood = _ints(d.get("vflood", ""))
	_hx = _ints(d.get("hx", ""))
	_hy = _ints(d.get("hy", ""))
	_htribe = _ints(d.get("htribe", ""))
	_hstore = _ints(d.get("hstore", ""))
	_hid = _ints(d.get("hid", ""))
	_next_hut_id = int(d.get("next_hut_id", _hid.size()))
	_pending = (d.get("pending", []) as Array).duplicate(true)
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(d.get("rng_seed", 0))
	_rng.state = int(d.get("rng_state", 0))


## Decode a base64 int32 blob back into a PackedInt32Array.
func _ints(v: Variant) -> PackedInt32Array:
	return Marshalls.base64_to_raw(String(v)).to_int32_array()
