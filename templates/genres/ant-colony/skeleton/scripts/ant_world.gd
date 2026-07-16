class_name AntWorld
extends RefCounted
## res://scripts/ant_world.gd
## THE PURE ENGINE — a deterministic, seedable COLONY ECOSYSTEM sim in the SimAnt
## lineage. A top-down grid with a SURFACE band (open air, where food sits and a
## predator roams) over diggable SOIL where each colony tunnels out a nest. Two
## rival ANT COLONIES (you + a rival heuristic) forage with PHEROMONE TRAILS,
## raise CASTES (queen / workers / soldiers), dig tunnels, and war over the map
## while a spider predator picks off lone ants.
##
## Everything — terrain, the twin-pheromone foraging model, the ant state machine,
## caste births, tunnelling, the rival AI, combat, the predator, win/loss — is a
## pure function of (state, tick, seeded RNG). The same seed + the same player
## designations always yield a BYTE-IDENTICAL world after N ticks. No engine/scene
## dependencies: this class is fully headless-testable.
##
## PHEROMONE MODEL (the signature mechanic — classic double-field ant routing):
##   Each colony owns two scalar fields over the passable grid:
##     _phh (HOME trail) — emitted strongly by the nest core each tick and laid
##       weakly by outbound SEARCHERS; it diffuses through connected open cells
##       into a gradient that climbs toward the nest. Food-carrying ants ASCEND it
##       to walk home.
##     _phf (FOOD trail) — laid strongly by RETURNING ants carrying food, all the
##       way from the food back to the nest. Outbound searchers ASCEND it to reach
##       the food. Both fields EVAPORATE (×EVAP) and DIFFUSE every tick, so an
##       unused trail FADES and a used one is continuously reinforced — a stable
##       nest→food trail emerges with no scripting.
##
## TICK DISCIPLINE (deterministic AND terminating):
##   tick_world() runs a fixed pipeline — evaporate+diffuse pheromones → nest
##   emits home scent → economy (upkeep, starvation, caste births) → assign a
##   digger → advance every ant ONE cell in index order → advance predators →
##   compact the dead → judge. No step does an unbounded rescan (enemy/dig/food
##   searches are bounded-radius or single linear passes), so a tick is O(A + W·H)
##   with small constants. Every stochastic choice draws from the SEEDED RNG whose
##   state is saved — replays are exact.

# =====================================================================
#  Colonies
# =====================================================================
const YOU := 0
const RIVAL := 1
const COLONY_COUNT := 2

# =====================================================================
#  Terrain cell kinds (packed into _terrain, one byte per cell)
# =====================================================================
const OPEN := 0      ## surface air / above ground — passable, ants roam freely
const SOIL := 1      ## underground earth — IMPASSABLE until a worker digs it
const TUNNEL := 2    ## dug-out earth — passable underground corridor
const CHAMBER := 3   ## nest chamber — passable, the heart of a colony
const FOOD := 4      ## a food source on the surface — passable, holds food_amt
const ROCK := 5      ## bedrock — IMPASSABLE and UNDIGGABLE
const NEST := 6      ## your nest core marker — passable
const RNEST := 7     ## rival nest core marker — passable

# =====================================================================
#  Castes
# =====================================================================
const QUEEN := 0     ## lays eggs, consumes food, never moves — kill her to win
const WORKER := 1    ## forages food + digs tunnels, follows/lays pheromones
const SOLDIER := 2   ## fights rival ants + the predator; guards or assaults
const CASTE_COUNT := 3
const CASTE_NAME: PackedStringArray = ["Queen", "Worker", "Soldier"]

# =====================================================================
#  Ant state machine
# =====================================================================
const ST_SEARCH := 0   ## worker hunting food (ascend food trail / explore)
const ST_RETURN := 1   ## worker carrying food home (ascend home trail)
const ST_DIG := 2      ## worker walking to a soil cell to excavate it
const ST_GUARD := 3    ## soldier holding near the nest, intercepting intruders
const ST_FIGHT := 4    ## soldier assaulting toward the attack target
const ST_IDLE := 5     ## the queen — stationary in the chamber

# =====================================================================
#  Player designation zones (indirect, SimAnt-style influence)
# =====================================================================
const ZONE_DIG := 0     ## bias tunnelling toward this cell
const ZONE_FORAGE := 1  ## bias searchers' exploration toward this cell
const ZONE_ATTACK := 2  ## send your soldiers to assault this cell
const ZONE_COUNT := 3
const ZONE_NAME: PackedStringArray = ["Dig", "Forage", "Attack"]

# =====================================================================
#  Tuning (auditable constants)
# =====================================================================
const SURFACE_ROWS := 10        ## rows [0, SURFACE_ROWS) are open surface air

# Pheromone field dynamics.
const EVAP := 0.94              ## each field is multiplied by this every tick
const DIFFUSE := 0.10           ## fraction each cell blends toward its neighbours
const HOME_EMIT := 80.0         ## home scent the nest core injects each tick
const HOME_DEPOSIT := 1.0       ## home scent a searcher lays on its cell
const FOOD_DEPOSIT := 10.0      ## food scent a food-carrier lays on its cell
const EPS_TRAIL := 0.02         ## a neighbour must beat this to be "uphill"
const EXPLORE := 0.15           ## chance a searcher explores instead of trailing
const BIAS := 0.70              ## chance an exploring ant heads toward its bias pt

# Colony economy.
const FOUND_WORKERS := 6        ## founding worker count per colony
const FOUND_SOLDIERS := 2       ## founding soldier count per colony
const START_FOOD := 25          ## founding food stock
const EGG_INTERVAL := 5         ## the queen lays at most one egg every N ticks
const EGG_COST := 5             ## food a single egg→ant birth consumes
const POP_CAP := 70             ## hard population cap per colony (bounds ticks)
const SOLDIER_EVERY := 3        ## every 3rd ant born is a soldier (~33% soldiers)
const UPKEEP_INTERVAL := 3      ## the colony eats 1 food every N ticks
const STARVE_LIMIT := 40        ## ticks at zero food before the queen weakens
const STARVE_DMG := 3           ## hp the queen loses per tick while starving

# Combat / health.
const HP_WORKER := 8
const HP_SOLDIER := 28
const HP_QUEEN := 120
const HP_PREDATOR := 44
const ATK_SOLDIER := 5          ## soldier damage to an enemy ant / predator
const ATK_SOLDIER_QUEEN := 9    ## soldier damage when adjacent to an enemy QUEEN
const ATK_PREDATOR := 4         ## predator damage to a non-soldier ant
const SOLDIER_REACH := 10       ## how far a soldier will chase a spotted enemy
const PRED_HUNT := 14           ## how far the predator senses a surface worker
const PRED_RESPAWN := 120       ## ticks before a driven-off predator returns

# Tunnelling.
const MAX_DIGGERS := 3          ## at most this many diggers per colony at once
const DIG_CAP := 140            ## a colony stops auto-digging past this many digs
const DIG_SEARCH_R := 12        ## radius to look for a soil cell to excavate

# Nest geometry / victory.
const NEST_RADIUS := 2          ## Manhattan radius counted as "at the nest"
const POP_GOAL := 45            ## reach this pop while leading to WIN
const TICK_CAP := 4000          ## judged by population at this tick if unresolved

## Orthogonal neighbour offsets, fixed deterministic order.
const NB4: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

# =====================================================================
#  State
# =====================================================================
var width: int = 0
var height: int = 0
var tick: int = 0
var winner: int = -1               ## -1 ongoing, YOU / RIVAL once decided
var n: int = 0                     ## width * height (cell count)

var _terrain := PackedByteArray()  ## cell kind per cell (row-major i = y*W + x)
var _food_amt := PackedInt32Array()## remaining food units per FOOD cell (else 0)

# Twin pheromone fields, flat over both colonies: index = colony*n + cell.
var _phf := PackedFloat32Array()   ## FOOD trail (laid by carriers)
var _phh := PackedFloat32Array()   ## HOME trail (emitted by the nest)

# Ants — parallel arrays, kept compact (dead removed each tick).
var _ax := PackedInt32Array()
var _ay := PackedInt32Array()
var _acolony := PackedInt32Array() ## YOU / RIVAL, or -1 = dead (compacted out)
var _acaste := PackedInt32Array()
var _astate := PackedInt32Array()
var _acarry := PackedInt32Array()  ## 0 empty, 1 carrying food
var _ahp := PackedInt32Array()
var _adx := PackedInt32Array()     ## dig-target x (-1 none)
var _ady := PackedInt32Array()     ## dig-target y

# Predators (a spider) — parallel arrays, id-stable (never compacted).
var _px := PackedInt32Array()
var _py := PackedInt32Array()
var _php := PackedInt32Array()     ## predator hp
var _palive := PackedInt32Array()  ## 1 alive, 0 driven off (respawning)
var _ptimer := PackedInt32Array()  ## ticks until respawn while driven off

# Per-colony pools (index by colony).
var _nest_x := PackedInt32Array()
var _nest_y := PackedInt32Array()
var _food_stock := PackedInt32Array()
var _harvested := PackedInt32Array() ## cumulative food ever banked (foraging proof)
var _born := PackedInt32Array()      ## cumulative ants birthed (caste ratio driver)
var _starve := PackedInt32Array()    ## consecutive zero-food ticks
var _dug := PackedInt32Array()       ## cumulative tunnels excavated

# Player designation zones (YOU only); (-1,-1) means none.
var _dig_zone := Vector2i(-1, -1)
var _forage_zone := Vector2i(-1, -1)
var _attack_zone := Vector2i(-1, -1)

var _rng := RandomNumberGenerator.new()


# =====================================================================
#  Lifecycle
# =====================================================================

## Build a fresh W×H world with two founding colonies. seed == 0 → randomised;
## any other value is fully deterministic.
func setup(w: int, h: int, seed_value: int = 0) -> void:
	width = maxi(24, w)
	height = maxi(SURFACE_ROWS + 8, h)
	n = width * height
	tick = 0
	winner = -1
	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_clear_actors()
	_food_stock = PackedInt32Array([START_FOOD, START_FOOD])
	_harvested = PackedInt32Array([0, 0])
	_born = PackedInt32Array([0, 0])
	_starve = PackedInt32Array([0, 0])
	_dug = PackedInt32Array([0, 0])
	_dig_zone = Vector2i(-1, -1)
	_forage_zone = Vector2i(-1, -1)
	_attack_zone = Vector2i(-1, -1)
	_phf = PackedFloat32Array()
	_phf.resize(n * COLONY_COUNT)
	_phh = PackedFloat32Array()
	_phh.resize(n * COLONY_COUNT)
	_generate_terrain()
	# Two nests on opposite flanks, just below the surface.
	var ny := SURFACE_ROWS + 2
	_nest_x = PackedInt32Array([int(width * 0.16), int(width * 0.84)])
	_nest_y = PackedInt32Array([ny, ny])
	_found_colony(YOU, _nest_x[YOU], ny, NEST)
	_found_colony(RIVAL, _nest_x[RIVAL], ny, RNEST)
	# One spider stalking the surface.
	_add_predator(int(width * 0.5), 1)


func _clear_actors() -> void:
	_ax = PackedInt32Array()
	_ay = PackedInt32Array()
	_acolony = PackedInt32Array()
	_acaste = PackedInt32Array()
	_astate = PackedInt32Array()
	_acarry = PackedInt32Array()
	_ahp = PackedInt32Array()
	_adx = PackedInt32Array()
	_ady = PackedInt32Array()
	_px = PackedInt32Array()
	_py = PackedInt32Array()
	_php = PackedInt32Array()
	_palive = PackedInt32Array()
	_ptimer = PackedInt32Array()


## Deterministic terrain: open surface band, soil below with scattered bedrock,
## and food sources dotted along the ground line (positions jittered by the seed).
func _generate_terrain() -> void:
	_terrain = PackedByteArray()
	_terrain.resize(n)
	_food_amt = PackedInt32Array()
	_food_amt.resize(n)
	for y in height:
		for x in width:
			var i := y * width + x
			if y < SURFACE_ROWS:
				_terrain[i] = OPEN
			else:
				# Bedrock veins deep down (undiggable obstacles), else soil.
				if y > SURFACE_ROWS + 3 and _rng.randf() < 0.05:
					_terrain[i] = ROCK
				else:
					_terrain[i] = SOIL
	# Food sources sit on the lowest surface row (the ground line), spread across
	# the map with a seed-jittered column so different seeds diverge.
	var ground := SURFACE_ROWS - 1
	var slots := 8
	for k in slots:
		var base_col := int((k + 0.5) * width / float(slots))
		var col := clampi(base_col + _rng.randi_range(-2, 2), 1, width - 2)
		var fi := ground * width + col
		_terrain[fi] = FOOD
		_food_amt[fi] = 50


## Carve a colony's starter nest (a 3-wide entrance tunnel + a chamber) and seat a
## queen, some workers, and some soldiers. `core_kind` marks the nest core cell.
func _found_colony(colony: int, cx: int, cy: int, core_kind: int) -> void:
	cx = clampi(cx, 3, width - 4)
	# Entrance: 3-wide shaft from the surface down to the chamber.
	for x in range(cx - 1, cx + 2):
		for y in range(SURFACE_ROWS - 1, cy):
			_carve(x, y, TUNNEL)
	# Chamber: a 5×3 pocket around the core.
	for x in range(cx - 2, cx + 3):
		for y in range(cy, cy + 3):
			_carve(x, y, CHAMBER)
	_terrain[cy * width + cx] = core_kind
	# The founding queen sits at the core.
	_add_ant(colony, QUEEN, cx, cy)
	# Founding workers in the chamber, soldiers by the entrance.
	for i in FOUND_WORKERS:
		var wx := cx - 2 + (i % 5)
		var wy := cy + 1 + (i / 5)
		_add_ant(colony, WORKER, clampi(wx, cx - 2, cx + 2), clampi(wy, cy, cy + 2))
	for i in FOUND_SOLDIERS:
		_add_ant(colony, SOLDIER, cx - 1 + i * 2, cy)


## Turn a cell into `kind` only if it is diggable/open (never overwrite bedrock).
func _carve(x: int, y: int, kind: int) -> void:
	if not in_bounds(x, y):
		return
	var i := y * width + x
	if _terrain[i] == ROCK:
		return
	_terrain[i] = kind
	_food_amt[i] = 0


func _add_ant(colony: int, caste: int, x: int, y: int) -> void:
	_ax.append(x)
	_ay.append(y)
	_acolony.append(colony)
	_acaste.append(caste)
	_astate.append(_default_state(caste))
	_acarry.append(0)
	_ahp.append(_caste_hp(caste))
	_adx.append(-1)
	_ady.append(-1)


func _default_state(caste: int) -> int:
	match caste:
		QUEEN:
			return ST_IDLE
		SOLDIER:
			return ST_GUARD
		_:
			return ST_SEARCH


func _caste_hp(caste: int) -> int:
	match caste:
		QUEEN:
			return HP_QUEEN
		SOLDIER:
			return HP_SOLDIER
		_:
			return HP_WORKER


func _add_predator(x: int, y: int) -> void:
	_px.append(x)
	_py.append(y)
	_php.append(HP_PREDATOR)
	_palive.append(1)
	_ptimer.append(0)


# =====================================================================
#  Grid queries
# =====================================================================

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func terrain_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return ROCK
	return _terrain[y * width + x]


## Passable = an ant may stand here (anything that is not solid soil or bedrock).
func _passable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var t := _terrain[y * width + x]
	return t != SOIL and t != ROCK


func is_passable(x: int, y: int) -> bool:
	return _passable(x, y)


func food_amt_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return _food_amt[y * width + x]


func food_ph(colony: int, x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	return _phf[colony * n + y * width + x]


func home_ph(colony: int, x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	return _phh[colony * n + y * width + x]


func get_terrain() -> PackedByteArray:
	return _terrain


func nest_x_of(colony: int) -> int:
	return _nest_x[colony]


func nest_y_of(colony: int) -> int:
	return _nest_y[colony]


func food_stock_of(colony: int) -> int:
	return _food_stock[colony]


func harvested_of(colony: int) -> int:
	return _harvested[colony]


func dug_of(colony: int) -> int:
	return _dug[colony]


func born_of(colony: int) -> int:
	return _born[colony]


func rng_state() -> int:
	return _rng.state


## Count of living ants of a colony.
func population(colony: int) -> int:
	var c := 0
	for i in _acolony.size():
		if _acolony[i] == colony:
			c += 1
	return c


## Count of living ants of a colony in a given caste.
func caste_pop(colony: int, caste: int) -> int:
	var c := 0
	for i in _acolony.size():
		if _acolony[i] == colony and _acaste[i] == caste:
			c += 1
	return c


func queen_alive(colony: int) -> bool:
	return _find_queen(colony) >= 0


func _find_queen(colony: int) -> int:
	for i in _acolony.size():
		if _acolony[i] == colony and _acaste[i] == QUEEN:
			return i
	return -1


func ant_count() -> int:
	return _ax.size()


## Read-only ant snapshot for the renderer / tests.
func ant_info(i: int) -> Dictionary:
	return {
		"x": _ax[i], "y": _ay[i], "colony": _acolony[i], "caste": _acaste[i],
		"state": _astate[i], "carry": _acarry[i], "hp": _ahp[i],
	}


func predator_count() -> int:
	return _px.size()


func predator_alive_count() -> int:
	var c := 0
	for i in _palive.size():
		if _palive[i] == 1:
			c += 1
	return c


func predator_info(i: int) -> Dictionary:
	return {"x": _px[i], "y": _py[i], "hp": _php[i], "alive": _palive[i]}


## Passable open-tunnel cells excavated + native — a rough "nest size" readout.
func open_count() -> int:
	var c := 0
	for i in n:
		var t := _terrain[i]
		if t == TUNNEL or t == CHAMBER:
			c += 1
	return c


func dig_zone() -> Vector2i:
	return _dig_zone


func forage_zone() -> Vector2i:
	return _forage_zone


func attack_zone() -> Vector2i:
	return _attack_zone


# =====================================================================
#  Public economy / test hooks
# =====================================================================

## Bank food into a colony's stock (a foraged windfall / a test lever). The colony
## turns food into eggs → ants, so this is the honest growth lever a strong
## economy pulls.
func add_food(colony: int, amount: int) -> void:
	_food_stock[colony] = maxi(0, _food_stock[colony] + amount)


## Lay food pheromone directly (used by the evaporation probe + scripted setups).
func deposit_food_ph(colony: int, x: int, y: int, amount: float) -> void:
	if in_bounds(x, y):
		_phf[colony * n + y * width + x] += amount


## Spawn an ant of a caste for a colony near (x,y) (public founding / test hook).
func spawn_ant(colony: int, caste: int, x: int, y: int) -> void:
	var spot := _nearest_passable(x, y)
	_add_ant(colony, caste, spot.x, spot.y)


# =====================================================================
#  Designations (indirect player influence) — legality + apply
# =====================================================================

## True iff YOU could legally designate this zone right now (game live, in bounds).
func is_legal_designation(kind: int, x: int, y: int) -> bool:
	if winner != -1:
		return false
	if kind < 0 or kind >= ZONE_COUNT:
		return false
	return in_bounds(x, y)


## Set one of your bias zones. Returns false (and changes nothing) if illegal.
func designate(kind: int, x: int, y: int) -> bool:
	if not is_legal_designation(kind, x, y):
		return false
	match kind:
		ZONE_DIG:
			_dig_zone = Vector2i(x, y)
		ZONE_FORAGE:
			_forage_zone = Vector2i(x, y)
		ZONE_ATTACK:
			_attack_zone = Vector2i(x, y)
	return true


## Clear one of your bias zones.
func clear_zone(kind: int) -> void:
	match kind:
		ZONE_DIG:
			_dig_zone = Vector2i(-1, -1)
		ZONE_FORAGE:
			_forage_zone = Vector2i(-1, -1)
		ZONE_ATTACK:
			_attack_zone = Vector2i(-1, -1)


# =====================================================================
#  The tick — one deterministic step of the whole world
# =====================================================================

func tick_world() -> void:
	if winner != -1:
		return
	tick += 1
	# 1) pheromones evaporate + diffuse (both colonies, both fields).
	_evaporate_and_diffuse()
	# 2) each nest injects home scent at its core.
	for c in COLONY_COUNT:
		var core := _nest_y[c] * width + _nest_x[c]
		_phh[c * n + core] += HOME_EMIT
	# 3) economy: upkeep, starvation, caste births.
	for c in COLONY_COUNT:
		_economy(c)
	# 4) assign a digger per colony (bounded, self-limiting).
	for c in COLONY_COUNT:
		_maybe_assign_dig(c)
	# 5) advance every ant one cell in index order (deterministic).
	for i in _ax.size():
		if _acolony[i] < 0:
			continue
		_update_ant(i)
	# 6) advance predators.
	for p in _px.size():
		_update_predator(p)
	# 7) compact away the dead.
	_compact()
	# 8) judge the game.
	_judge()


# --- pheromone field dynamics ----------------------------------------------

func _evaporate_and_diffuse() -> void:
	for c in COLONY_COUNT:
		_diffuse_evap(_phf, c * n)
		_diffuse_evap(_phh, c * n)


## Blend each passable cell toward its passable neighbours (diffusion) then scale
## by EVAP (evaporation). Non-passable cells are forced to 0 — scent cannot sit in
## solid earth, so trails stay inside the connected tunnels + surface.
func _diffuse_evap(arr: PackedFloat32Array, base: int) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(n)
	for y in height:
		for x in width:
			var i := y * width + x
			if not _passable(x, y):
				tmp[i] = 0.0
				continue
			var v := arr[base + i]
			var acc := 0.0
			var cnt := 0
			for off in NB4:
				var nx := x + off.x
				var ny := y + off.y
				if _passable(nx, ny):
					acc += arr[base + ny * width + nx]
					cnt += 1
			var diffused := v
			if cnt > 0:
				diffused = v + DIFFUSE * (acc / float(cnt) - v)
			tmp[i] = diffused * EVAP
	for i in n:
		arr[base + i] = tmp[i]


# --- economy: upkeep, starvation, caste births -----------------------------

func _economy(c: int) -> void:
	var qi := _find_queen(c)
	if qi < 0:
		return  # no queen → no economy (the judge will end it)
	# Colony consumes food periodically.
	if tick % UPKEEP_INTERVAL == 0:
		_food_stock[c] = maxi(0, _food_stock[c] - 1)
	# Starvation: an empty larder eventually weakens (and can kill) the queen.
	if _food_stock[c] <= 0:
		_starve[c] += 1
		if _starve[c] >= STARVE_LIMIT:
			_ahp[qi] -= STARVE_DMG
			if _ahp[qi] <= 0:
				_acolony[qi] = -1
	else:
		_starve[c] = 0
	# Egg → ant birth: costs food, respects the cap, castes by a fixed ratio.
	if tick % EGG_INTERVAL == 0 and _food_stock[c] >= EGG_COST and population(c) < POP_CAP:
		if _acolony[qi] < 0:
			return
		_food_stock[c] -= EGG_COST
		var caste := SOLDIER if (_born[c] % SOLDIER_EVERY == SOLDIER_EVERY - 1) else WORKER
		_born[c] += 1
		var spot := _nearest_passable(_nest_x[c], _nest_y[c])
		_add_ant(c, caste, spot.x, spot.y)


# --- digger assignment -----------------------------------------------------

func _maybe_assign_dig(c: int) -> void:
	if _dug[c] >= DIG_CAP:
		return
	if _count_state(c, ST_DIG) >= MAX_DIGGERS:
		return
	var wi := _find_idle_worker(c)
	if wi < 0:
		return
	var t := _find_dig_target(c)
	if t.x < 0:
		return
	_astate[wi] = ST_DIG
	_adx[wi] = t.x
	_ady[wi] = t.y


func _count_state(c: int, state: int) -> int:
	var k := 0
	for i in _acolony.size():
		if _acolony[i] == c and _astate[i] == state:
			k += 1
	return k


func _find_idle_worker(c: int) -> int:
	for i in _acolony.size():
		if _acolony[i] == c and _acaste[i] == WORKER and _astate[i] == ST_SEARCH and _acarry[i] == 0:
			return i
	return -1


## Nearest SOIL cell (to the dig zone if you set one, else the nest core) that has
## at least one passable neighbour — i.e. a reachable excavation frontier.
func _find_dig_target(c: int) -> Vector2i:
	var center := Vector2i(_nest_x[c], _nest_y[c])
	if c == YOU and _dig_zone.x >= 0:
		center = _dig_zone
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for dy in range(-DIG_SEARCH_R, DIG_SEARCH_R + 1):
		for dx in range(-DIG_SEARCH_R, DIG_SEARCH_R + 1):
			var x := center.x + dx
			var y := center.y + dy
			if not in_bounds(x, y):
				continue
			if _terrain[y * width + x] != SOIL:
				continue
			if not _has_passable_neighbour(x, y):
				continue
			var d := dx * dx + dy * dy
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


func _has_passable_neighbour(x: int, y: int) -> bool:
	for off in NB4:
		if _passable(x + off.x, y + off.y):
			return true
	return false


# --- ant behaviour ---------------------------------------------------------

func _update_ant(i: int) -> void:
	match _astate[i]:
		ST_SEARCH:
			_ant_search(i)
		ST_RETURN:
			_ant_return(i)
		ST_DIG:
			_ant_dig(i)
		ST_GUARD, ST_FIGHT:
			_ant_soldier(i)
		ST_IDLE:
			pass  # the queen holds station


## A searching worker: harvest food it reaches, otherwise ASCEND the food trail
## (with occasional exploration biased toward the surface / forage zone). It lays
## a weak home trail as it goes so the outbound path is marked.
func _ant_search(i: int) -> void:
	var c := _acolony[i]
	var x := _ax[i]
	var y := _ay[i]
	var here := y * width + x
	_phh[c * n + here] += HOME_DEPOSIT
	# On a food cell with food? Pick it up and head home.
	if _terrain[here] == FOOD and _food_amt[here] > 0:
		_food_amt[here] -= 1
		if _food_amt[here] <= 0:
			_terrain[here] = OPEN
		_acarry[i] = 1
		_astate[i] = ST_RETURN
		return
	# A neighbouring food cell? Step onto it (harvest next tick).
	for off in NB4:
		var nx := x + off.x
		var ny := y + off.y
		if in_bounds(nx, ny) and _terrain[ny * width + nx] == FOOD and _food_amt[ny * width + nx] > 0:
			_ax[i] = nx
			_ay[i] = ny
			return
	# Follow the food trail if it points anywhere; else explore.
	if _rng.randf() >= EXPLORE and _follow_gradient(i, true):
		return
	_explore_move(i, true)


## A returning worker: LAY the food trail on every cell, ASCEND the home trail
## toward the nest, and bank its load when it arrives.
func _ant_return(i: int) -> void:
	var c := _acolony[i]
	var x := _ax[i]
	var y := _ay[i]
	_phf[c * n + y * width + x] += FOOD_DEPOSIT
	if _at_nest(c, x, y):
		_food_stock[c] += 1
		_harvested[c] += 1
		_acarry[i] = 0
		_astate[i] = ST_SEARCH
		return
	if _follow_gradient(i, false):
		return
	_explore_move(i, false)


## A digging worker: walk to the excavation frontier and turn one soil cell into a
## tunnel, then rejoin the foragers.
func _ant_dig(i: int) -> void:
	var c := _acolony[i]
	var tx := _adx[i]
	var ty := _ady[i]
	if not in_bounds(tx, ty) or _terrain[ty * width + tx] != SOIL:
		_astate[i] = ST_SEARCH
		_adx[i] = -1
		_ady[i] = -1
		return
	if absi(_ax[i] - tx) + absi(_ay[i] - ty) == 1:
		_terrain[ty * width + tx] = TUNNEL
		_dug[c] += 1
		_astate[i] = ST_SEARCH
		_adx[i] = -1
		_ady[i] = -1
		return
	# Approach: step toward the target across passable cells (it stops adjacent,
	# since the soil target itself is not passable).
	if not _step_toward(i, tx, ty):
		# Made no legal progress toward an unreachable target → give up.
		if not _passable(_ax[i] + signi(tx - _ax[i]), _ay[i]) \
				and not _passable(_ax[i], _ay[i] + signi(ty - _ay[i])):
			_astate[i] = ST_SEARCH
			_adx[i] = -1
			_ady[i] = -1


## A soldier: strike any adjacent enemy ant / predator, then move — chase the
## nearest spotted enemy, else advance to the attack target (or hold at the nest).
func _ant_soldier(i: int) -> void:
	var c := _acolony[i]
	var enemy := 1 - c
	var x := _ax[i]
	var y := _ay[i]
	# One pass over enemy ants: strike adjacents, remember the nearest in reach.
	var best := Vector2i(-1, -1)
	var best_d := SOLDIER_REACH * SOLDIER_REACH + 1
	for j in _acolony.size():
		if _acolony[j] != enemy:
			continue
		var dx := _ax[j] - x
		var dy := _ay[j] - y
		if maxi(absi(dx), absi(dy)) <= 1:
			var dmg := ATK_SOLDIER_QUEEN if _acaste[j] == QUEEN else ATK_SOLDIER
			_ahp[j] -= dmg
			if _ahp[j] <= 0:
				_acolony[j] = -1
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = Vector2i(_ax[j], _ay[j])
	# Strike an adjacent predator too.
	for p in _px.size():
		if _palive[p] == 0:
			continue
		if maxi(absi(_px[p] - x), absi(_py[p] - y)) <= 1:
			_php[p] -= ATK_SOLDIER
	# Movement target.
	var tgt := best
	if tgt.x < 0:
		tgt = _predator_target(x, y)
	if tgt.x < 0:
		tgt = _assault_target(c)
	if tgt.x >= 0:
		_astate[i] = ST_FIGHT if (best.x >= 0 or (c == YOU and _attack_zone.x >= 0) or c == RIVAL) else ST_GUARD
		_step_toward(i, tgt.x, tgt.y)


## Where a soldier heads with no enemy in sight: YOU → the attack zone if set, else
## hold at your own nest (defend). RIVAL → always your queen (relentless assault),
## so a passive player is eventually overrun.
func _assault_target(c: int) -> Vector2i:
	if c == YOU:
		if _attack_zone.x >= 0:
			return _attack_zone
		return Vector2i(_nest_x[YOU], _nest_y[YOU])
	return Vector2i(_nest_x[YOU], _nest_y[YOU])


func _predator_target(x: int, y: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := SOLDIER_REACH * SOLDIER_REACH + 1
	for p in _px.size():
		if _palive[p] == 0:
			continue
		var dx := _px[p] - x
		var dy := _py[p] - y
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = Vector2i(_px[p], _py[p])
	return best


# --- movement primitives ---------------------------------------------------

## Move ant i one passable cell toward (tx,ty). Returns true iff it now stands on
## the target. Tries the axis of larger delta first (deterministic).
func _step_toward(i: int, tx: int, ty: int) -> bool:
	var x := _ax[i]
	var y := _ay[i]
	if x == tx and y == ty:
		return true
	var sx := signi(tx - x)
	var sy := signi(ty - y)
	var tries: Array[Vector2i] = []
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
	for st in tries:
		var nx := x + st.x
		var ny := y + st.y
		if _passable(nx, ny):
			_ax[i] = nx
			_ay[i] = ny
			return nx == tx and ny == ty
	return false


## Ascend a pheromone field: step to the passable neighbour whose scent most
## exceeds the current cell (by at least EPS_TRAIL). Returns false if none is
## meaningfully uphill (caller then explores / falls back).
func _follow_gradient(i: int, use_food: bool) -> bool:
	var c := _acolony[i]
	var base := c * n
	var x := _ax[i]
	var y := _ay[i]
	var cur := (_phf[base + y * width + x] if use_food else _phh[base + y * width + x])
	var best_v := cur + EPS_TRAIL
	var bx := -1
	var by := -1
	for off in NB4:
		var nx := x + off.x
		var ny := y + off.y
		if not _passable(nx, ny):
			continue
		var v := (_phf[base + ny * width + nx] if use_food else _phh[base + ny * width + nx])
		if v > best_v:
			best_v = v
			bx = nx
			by = ny
	if bx >= 0:
		_ax[i] = bx
		_ay[i] = by
		return true
	return false


## Explore: with probability BIAS head toward a bias point (surface / forage zone
## when searching, the nest when returning), else take a seeded random passable
## step. This gets ants out of the nest and reliably home even where scent is flat.
func _explore_move(i: int, searching: bool) -> void:
	var c := _acolony[i]
	var target: Vector2i
	if searching:
		if c == YOU and _forage_zone.x >= 0:
			target = _forage_zone
		else:
			target = Vector2i(_nest_x[c], 0)  # bias up toward the surface/food line
	else:
		target = Vector2i(_nest_x[c], _nest_y[c])
	if _rng.randf() < BIAS and _step_toward(i, target.x, target.y):
		return
	var order := _rng.randi() % 4
	for k in 4:
		var off := NB4[(order + k) % 4]
		var nx := _ax[i] + off.x
		var ny := _ay[i] + off.y
		if _passable(nx, ny):
			_ax[i] = nx
			_ay[i] = ny
			return


func _at_nest(c: int, x: int, y: int) -> bool:
	return absi(x - _nest_x[c]) + absi(y - _nest_y[c]) <= NEST_RADIUS


func _nearest_passable(x: int, y: int) -> Vector2i:
	if _passable(x, y):
		return Vector2i(x, y)
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				if _passable(x + dx, y + dy):
					return Vector2i(x + dx, y + dy)
	return Vector2i(clampi(x, 0, width - 1), clampi(y, 0, height - 1))


# --- predator --------------------------------------------------------------

## The spider stalks the surface: it bites adjacent non-soldier ants, hunts the
## nearest surface worker, takes damage from adjacent soldiers (in their turn), and
## is DRIVEN OFF at zero hp — respawning at a surface edge after a delay.
func _update_predator(p: int) -> void:
	if _palive[p] == 0:
		_ptimer[p] -= 1
		if _ptimer[p] <= 0:
			_px[p] = 0 if (_rng.randi() & 1) == 0 else width - 1
			_py[p] = 0
			_php[p] = HP_PREDATOR
			_palive[p] = 1
		return
	var x := _px[p]
	var y := _py[p]
	var best := Vector2i(-1, -1)
	var best_d := PRED_HUNT * PRED_HUNT + 1
	for j in _acolony.size():
		if _acolony[j] < 0:
			continue
		var dx := _ax[j] - x
		var dy := _ay[j] - y
		if maxi(absi(dx), absi(dy)) <= 1 and _acaste[j] != SOLDIER:
			_ahp[j] -= ATK_PREDATOR
			if _ahp[j] <= 0:
				_acolony[j] = -1
		# Hunt the nearest WORKER exposed on the surface.
		if _acaste[j] == WORKER and _ay[j] < SURFACE_ROWS:
			var d := dx * dx + dy * dy
			if d < best_d:
				best_d = d
				best = Vector2i(_ax[j], _ay[j])
	if _php[p] <= 0:
		_palive[p] = 0
		_ptimer[p] = PRED_RESPAWN
		return
	if best.x >= 0:
		_step_predator(p, best.x, best.y)
	else:
		_wander_predator(p)


## Predators only move over open surface cells (row < SURFACE_ROWS).
func _pred_passable(x: int, y: int) -> bool:
	if not in_bounds(x, y) or y >= SURFACE_ROWS:
		return false
	var t := _terrain[y * width + x]
	return t == OPEN or t == FOOD


func _step_predator(p: int, tx: int, ty: int) -> void:
	var x := _px[p]
	var y := _py[p]
	var sx := signi(tx - x)
	var sy := signi(ty - y)
	var tries: Array[Vector2i] = []
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
	for st in tries:
		if _pred_passable(x + st.x, y + st.y):
			_px[p] = x + st.x
			_py[p] = y + st.y
			return


func _wander_predator(p: int) -> void:
	var order := _rng.randi() % 4
	for k in 4:
		var off := NB4[(order + k) % 4]
		if _pred_passable(_px[p] + off.x, _py[p] + off.y):
			_px[p] = _px[p] + off.x
			_py[p] = _py[p] + off.y
			return


# --- compaction + judging --------------------------------------------------

func _compact() -> void:
	if _acolony.find(-1) == -1:
		return
	var nx := PackedInt32Array()
	var ny := PackedInt32Array()
	var nc := PackedInt32Array()
	var nca := PackedInt32Array()
	var nst := PackedInt32Array()
	var ncy := PackedInt32Array()
	var nhp := PackedInt32Array()
	var ndx := PackedInt32Array()
	var ndy := PackedInt32Array()
	for i in _acolony.size():
		if _acolony[i] < 0:
			continue
		nx.append(_ax[i])
		ny.append(_ay[i])
		nc.append(_acolony[i])
		nca.append(_acaste[i])
		nst.append(_astate[i])
		ncy.append(_acarry[i])
		nhp.append(_ahp[i])
		ndx.append(_adx[i])
		ndy.append(_ady[i])
	_ax = nx
	_ay = ny
	_acolony = nc
	_acaste = nca
	_astate = nst
	_acarry = ncy
	_ahp = nhp
	_adx = ndx
	_ady = ndy


## Decide the winner. Reachable both ways: eliminate the rival QUEEN (or wipe their
## ants, or lead at the pop goal) to WIN; lose your queen / all ants (or let the
## rival hit the goal) to LOSE; the tick cap awards the larger colony.
func _judge() -> void:
	if winner != -1:
		return
	var q0 := queen_alive(YOU)
	var q1 := queen_alive(RIVAL)
	var p0 := population(YOU)
	var p1 := population(RIVAL)
	if not q0 or p0 == 0:
		winner = RIVAL
	elif not q1 or p1 == 0:
		winner = YOU
	elif p0 >= POP_GOAL and p0 > p1:
		winner = YOU
	elif p1 >= POP_GOAL and p1 > p0:
		winner = RIVAL
	elif tick >= TICK_CAP:
		winner = YOU if p0 >= p1 else RIVAL


# =====================================================================
#  Determinism helper + persistence
# =====================================================================

## FNV-1a-style checksum over the ENTIRE world (terrain, food, ants, predators,
## pools, and both pheromone fields). Two worlds are byte-identical iff their
## checksums (and arrays) match — the determinism probe compares this.
func checksum() -> int:
	var h: int = 1469598103934665603
	h = _mix_bytes(h, _terrain)
	h = _mix_ints(h, _food_amt)
	h = _mix_ints(h, _ax)
	h = _mix_ints(h, _ay)
	h = _mix_ints(h, _acolony)
	h = _mix_ints(h, _acaste)
	h = _mix_ints(h, _astate)
	h = _mix_ints(h, _acarry)
	h = _mix_ints(h, _ahp)
	h = _mix_ints(h, _adx)
	h = _mix_ints(h, _ady)
	h = _mix_ints(h, _px)
	h = _mix_ints(h, _py)
	h = _mix_ints(h, _php)
	h = _mix_ints(h, _palive)
	h = _mix_ints(h, _ptimer)
	h = _mix_ints(h, _food_stock)
	h = _mix_ints(h, _harvested)
	h = _mix_ints(h, _born)
	h = _mix_ints(h, _starve)
	h = _mix_ints(h, _dug)
	h = _mix_bytes(h, _phf.to_byte_array())
	h = _mix_bytes(h, _phh.to_byte_array())
	h = (h ^ (tick & 0xFFFFFFFF)) & 0x7FFFFFFFFFFFFFFF
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
## Packed grids/fields are base64 so the dictionary survives JSON.
func snapshot() -> Dictionary:
	return {
		"w": width, "h": height, "tick": tick, "winner": winner,
		"terrain": Marshalls.raw_to_base64(_terrain),
		"food_amt": Marshalls.raw_to_base64(_food_amt.to_byte_array()),
		"phf": Marshalls.raw_to_base64(_phf.to_byte_array()),
		"phh": Marshalls.raw_to_base64(_phh.to_byte_array()),
		"ax": Marshalls.raw_to_base64(_ax.to_byte_array()),
		"ay": Marshalls.raw_to_base64(_ay.to_byte_array()),
		"acolony": Marshalls.raw_to_base64(_acolony.to_byte_array()),
		"acaste": Marshalls.raw_to_base64(_acaste.to_byte_array()),
		"astate": Marshalls.raw_to_base64(_astate.to_byte_array()),
		"acarry": Marshalls.raw_to_base64(_acarry.to_byte_array()),
		"ahp": Marshalls.raw_to_base64(_ahp.to_byte_array()),
		"adx": Marshalls.raw_to_base64(_adx.to_byte_array()),
		"ady": Marshalls.raw_to_base64(_ady.to_byte_array()),
		"px": Marshalls.raw_to_base64(_px.to_byte_array()),
		"py": Marshalls.raw_to_base64(_py.to_byte_array()),
		"php": Marshalls.raw_to_base64(_php.to_byte_array()),
		"palive": Marshalls.raw_to_base64(_palive.to_byte_array()),
		"ptimer": Marshalls.raw_to_base64(_ptimer.to_byte_array()),
		"nest_x": Marshalls.raw_to_base64(_nest_x.to_byte_array()),
		"nest_y": Marshalls.raw_to_base64(_nest_y.to_byte_array()),
		"food_stock": Marshalls.raw_to_base64(_food_stock.to_byte_array()),
		"harvested": Marshalls.raw_to_base64(_harvested.to_byte_array()),
		"born": Marshalls.raw_to_base64(_born.to_byte_array()),
		"starve": Marshalls.raw_to_base64(_starve.to_byte_array()),
		"dug": Marshalls.raw_to_base64(_dug.to_byte_array()),
		"dig_zone": [_dig_zone.x, _dig_zone.y],
		"forage_zone": [_forage_zone.x, _forage_zone.y],
		"attack_zone": [_attack_zone.x, _attack_zone.y],
		"rng_seed": _rng.seed,
		"rng_state": _rng.state,
	}


func restore(d: Dictionary) -> void:
	width = int(d.get("w", width))
	height = int(d.get("h", height))
	n = width * height
	tick = int(d.get("tick", 0))
	winner = int(d.get("winner", -1))
	_terrain = Marshalls.base64_to_raw(String(d.get("terrain", "")))
	_food_amt = _ints(d.get("food_amt", ""))
	_phf = _floats(d.get("phf", ""))
	_phh = _floats(d.get("phh", ""))
	_ax = _ints(d.get("ax", ""))
	_ay = _ints(d.get("ay", ""))
	_acolony = _ints(d.get("acolony", ""))
	_acaste = _ints(d.get("acaste", ""))
	_astate = _ints(d.get("astate", ""))
	_acarry = _ints(d.get("acarry", ""))
	_ahp = _ints(d.get("ahp", ""))
	_adx = _ints(d.get("adx", ""))
	_ady = _ints(d.get("ady", ""))
	_px = _ints(d.get("px", ""))
	_py = _ints(d.get("py", ""))
	_php = _ints(d.get("php", ""))
	_palive = _ints(d.get("palive", ""))
	_ptimer = _ints(d.get("ptimer", ""))
	_nest_x = _ints(d.get("nest_x", ""))
	_nest_y = _ints(d.get("nest_y", ""))
	_food_stock = _ints(d.get("food_stock", ""))
	_harvested = _ints(d.get("harvested", ""))
	_born = _ints(d.get("born", ""))
	_starve = _ints(d.get("starve", ""))
	_dug = _ints(d.get("dug", ""))
	_dig_zone = _vec(d.get("dig_zone", [-1, -1]))
	_forage_zone = _vec(d.get("forage_zone", [-1, -1]))
	_attack_zone = _vec(d.get("attack_zone", [-1, -1]))
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(d.get("rng_seed", 0))
	_rng.state = int(d.get("rng_state", 0))


func _ints(v: Variant) -> PackedInt32Array:
	return Marshalls.base64_to_raw(String(v)).to_int32_array()


func _floats(v: Variant) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(String(v)).to_float32_array()


func _vec(v: Variant) -> Vector2i:
	var a := v as Array
	if a == null or a.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(a[0]), int(a[1]))
