class_name SandWorld
extends RefCounted
## res://scripts/sand_world.gd
## THE PURE ENGINE — a deterministic, seedable cellular-automata sandbox in the
## Noita / Powder-Toy / Sandspiel lineage. A grid of W×H CELLS, each holding a
## MATERIAL id (0..MATERIAL_COUNT-1) plus one byte of per-cell state (fire/gas
## lifetime, lava cool-timer). Every rule — falling, spreading, burning,
## reactions — is a pure function of (grid, tick, seeded RNG), so the same seed
## and the same scripted brush inputs always produce a BYTE-IDENTICAL grid after
## N steps. No engine/scene dependencies: this class is fully headless-testable.
##
## Storage is packed + serializable:
##   _cells : PackedByteArray  — material id per cell (row-major, i = y*width + x)
##   _aux   : PackedByteArray  — per-cell scalar (lifetime / cool-timer), 0 unused
##   _moved : PackedByteArray  — per-tick "already updated" mask (double-move guard)
##
## STEP DISCIPLINE (why it's deterministic AND double-move-free):
##   Each step() scans rows BOTTOM→TOP so a falling cell resolves in one pass,
##   and scans each row LEFT→RIGHT on even ticks / RIGHT→LEFT on odd ticks to
##   cancel directional bias — the scan order is a pure function of `tick`. A
##   cell that moves or transmutes is marked in `_moved` and is not touched again
##   this tick, so every cell updates AT MOST ONCE per step (bounded O(W·H), no
##   infinite loops). Every non-deterministic choice (which diagonal a grain
##   slides, whether fire spreads this tick, where a plant grows) is drawn from
##   the SEEDED RNG, whose state is part of save/load — so replays are exact.

# =====================================================================
#  Materials (>=10 with distinct behaviour)
# =====================================================================
const EMPTY := 0    ## air — nothing happens here
const SAND := 1     ## powder — falls, piles at a rest angle
const WATER := 2    ## liquid — falls, then spreads/levels horizontally
const STONE := 3    ## static solid / wall — immovable, inert
const WOOD := 4     ## static, FLAMMABLE — becomes fire when ignited
const PLANT := 5    ## static, FLAMMABLE — grows into empty next to water
const OIL := 6      ## liquid, very FLAMMABLE, lighter than water (floats)
const LAVA := 7     ## slow liquid — ignites flammables, cools to stone
const FIRE := 8     ## transient — spreads to flammables, lifetime→ash/empty+smoke
const SMOKE := 9    ## gas — rises, dissipates to empty
const STEAM := 10   ## gas — rises, condenses back to water on cooling
const ACID := 11    ## liquid — dissolves solids (and is depleted doing so)
const ICE := 12     ## static solid — melts to water near fire/lava
const ASH := 13     ## powder — inert residue left by fire, falls
const MATERIAL_COUNT := 14

## Which materials a player may paint (EMPTY is the eraser).
const PAINTABLE: PackedInt32Array = [
	EMPTY, SAND, WATER, STONE, WOOD, PLANT, OIL, LAVA, FIRE, ACID, ICE,
]

# =====================================================================
#  Physics tuning (auditable constants)
# =====================================================================
## Relative densities — a fluid/powder sinks through anything strictly lighter.
const DENSITY := {
	EMPTY: 0, SMOKE: 1, STEAM: 1, FIRE: 1,
	OIL: 3, WATER: 4, ACID: 4, LAVA: 5, ASH: 5, SAND: 6,
	STONE: 100, WOOD: 100, PLANT: 100, ICE: 100,
}

const FIRE_LIFE_MIN := 18   ## a fresh flame burns 18..34 ticks then dies
const FIRE_LIFE_MAX := 34
const SMOKE_LIFE := 40      ## smoke dissipates to EMPTY after this long
const STEAM_LIFE := 54      ## steam condenses back to WATER after this long
const LAVA_LIFE := 80       ## lava with no water contact cools to STONE

const FIRE_SPREAD := 0.85   ## chance/tick a flame ignites a flammable neighbour
const LAVA_IGNITE := 0.70   ## chance/tick lava ignites a flammable neighbour
const SMOKE_CHANCE := 0.25  ## chance/tick a flame emits smoke into empty above
const ASH_CHANCE := 0.15    ## chance a dying flame leaves ASH instead of EMPTY
const GROW_CHANCE := 0.22   ## chance/tick a watered plant grows into an empty cell

## Orthogonal (von-Neumann) neighbour offsets, deterministic order.
const NB4: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

# =====================================================================
#  State
# =====================================================================
var width: int = 0
var height: int = 0
var tick: int = 0
var _cells := PackedByteArray()
var _aux := PackedByteArray()
var _moved := PackedByteArray()
var _rng := RandomNumberGenerator.new()


# =====================================================================
#  Lifecycle
# =====================================================================

## Allocate a fresh W×H world of EMPTY. seed == 0 → randomised; any other value
## is fully deterministic.
func setup(w: int, h: int, seed_value: int = 0) -> void:
	width = maxi(1, w)
	height = maxi(1, h)
	tick = 0
	var n := width * height
	_cells = PackedByteArray()
	_cells.resize(n)          # PackedByteArray.resize() zero-fills → all EMPTY
	_aux = PackedByteArray()
	_aux.resize(n)
	_moved = PackedByteArray()
	_moved.resize(n)
	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Wipe every cell back to EMPTY (keeps size + RNG stream).
func clear() -> void:
	for i in _cells.size():
		_cells[i] = EMPTY
		_aux[i] = 0


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


## Material at (x,y); OOB reads as STONE so the border behaves as an inert wall
## (nothing ever moves or reacts across the edge → nothing leaves the grid).
func material_at(x: int, y: int) -> int:
	if x < 0 or x >= width or y < 0 or y >= height:
		return STONE
	return _cells[y * width + x]


func get_cells() -> PackedByteArray:
	return _cells


func get_aux() -> PackedByteArray:
	return _aux


func get_rng_state() -> int:
	return _rng.state


## How many cells currently hold `mat` (used by conservation checks + UI).
func count_of(mat: int) -> int:
	var c := 0
	for i in _cells.size():
		if _cells[i] == mat:
			c += 1
	return c


# =====================================================================
#  Brush
# =====================================================================

## Stamp `mat` into a filled circle of `radius` centred at (cx,cy).
func paint(mat: int, cx: int, cy: int, radius: int) -> void:
	var r := maxi(0, radius)
	var r2 := r * r
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r2:
				var x := cx + dx
				var y := cy + dy
				if in_bounds(x, y):
					_set_cell(x, y, mat)


func _set_cell(x: int, y: int, mat: int) -> void:
	var i := y * width + x
	_cells[i] = mat
	_aux[i] = _initial_aux(mat)


func _initial_aux(mat: int) -> int:
	match mat:
		FIRE:
			return _fire_life()
		SMOKE:
			return SMOKE_LIFE
		STEAM:
			return STEAM_LIFE
		LAVA:
			return LAVA_LIFE
		_:
			return 0


func _fire_life() -> int:
	return _rng.randi_range(FIRE_LIFE_MIN, FIRE_LIFE_MAX)


# =====================================================================
#  The step — one deterministic tick over the whole grid
# =====================================================================

func step() -> void:
	tick += 1
	for i in _moved.size():
		_moved[i] = 0
	var left_to_right := (tick & 1) == 0
	# Bottom→top so a falling cell resolves in a single pass.
	for y in range(height - 1, -1, -1):
		if left_to_right:
			for x in range(0, width):
				_update_cell(x, y)
		else:
			for x in range(width - 1, -1, -1):
				_update_cell(x, y)


func _update_cell(x: int, y: int) -> void:
	var i := y * width + x
	if _moved[i] == 1:
		return
	var m := _cells[i]
	match m:
		SAND, ASH:
			_update_powder(x, y, i)
		WATER, OIL:
			_flow(x, y, i)
		ACID:
			_update_acid(x, y, i)
		LAVA:
			_update_lava(x, y, i)
		FIRE:
			_update_fire(x, y, i)
		SMOKE:
			_update_gas(x, y, i, false)
		STEAM:
			_update_gas(x, y, i, true)
		PLANT:
			_update_plant(x, y, i)
		ICE:
			_update_ice(x, y, i)
		_:
			# EMPTY / STONE / WOOD are passive: they never move on their own.
			# WOOD/STONE transmute only when an aggressor (fire, lava, acid)
			# reaches them, which that aggressor's own update handles.
			pass


# --- movement primitives ---------------------------------------------------

## Swap the contents of two in-bounds cells and mark both resolved this tick.
func _swap(i: int, j: int) -> void:
	var tm := _cells[i]
	_cells[i] = _cells[j]
	_cells[j] = tm
	var ta := _aux[i]
	_aux[i] = _aux[j]
	_aux[j] = ta
	_moved[i] = 1
	_moved[j] = 1


## True if a cell of density `dens` sinks into fluid `other` (other is a
## lighter fluid). Powders/liquids displace anything strictly less dense.
func _sinks_into(dens: int, other: int) -> bool:
	match other:
		EMPTY, SMOKE, STEAM, FIRE, OIL, WATER, ACID, LAVA:
			return dens > int(DENSITY[other])
		_:
			return false


## Powder: fall straight, else slide to an open down-diagonal (this is what
## builds the ~45° rest-angle pile). Sinks through lighter fluids.
func _update_powder(x: int, y: int, i: int) -> void:
	var dens := int(DENSITY[_cells[i]])
	var by := y + 1
	if by < height:
		var below := _cells[i + width]
		if below == EMPTY or _sinks_into(dens, below):
			_swap(i, i + width)
			return
		var first := -1 if (_rng.randi() & 1) == 0 else 1
		for dx: int in [first, -first]:
			var nx := x + dx
			if nx >= 0 and nx < width:
				var j := by * width + nx
				var t := _cells[j]
				if t == EMPTY or _sinks_into(dens, t):
					_swap(i, j)
					return


## Liquid / lava flow: fall straight, then a down-diagonal, then spread
## horizontally into empty (levelling). Density lets water sink through oil.
func _flow(x: int, y: int, i: int) -> void:
	var dens := int(DENSITY[_cells[i]])
	var by := y + 1
	var first := -1 if (_rng.randi() & 1) == 0 else 1
	if by < height:
		var below := _cells[i + width]
		if below == EMPTY or _sinks_into(dens, below):
			_swap(i, i + width)
			return
		for dx: int in [first, -first]:
			var nx := x + dx
			if nx >= 0 and nx < width:
				var j := by * width + nx
				var t := _cells[j]
				if t == EMPTY or _sinks_into(dens, t):
					_swap(i, j)
					return
	for dx: int in [first, -first]:
		var nx := x + dx
		if nx >= 0 and nx < width:
			var j := y * width + nx
			if _cells[j] == EMPTY:
				_swap(i, j)
				return


## Gas: rise straight, else an up-diagonal, else sideways. Countdown its
## lifetime; on expiry SMOKE→EMPTY (dissipates) and STEAM→WATER (condenses).
func _update_gas(x: int, y: int, i: int, is_steam: bool) -> void:
	var life := _aux[i]
	if life <= 1:
		_cells[i] = WATER if is_steam else EMPTY
		_aux[i] = 0
		_moved[i] = 1
		return
	_aux[i] = life - 1
	var uy := y - 1
	var first := -1 if (_rng.randi() & 1) == 0 else 1
	if uy >= 0:
		if _cells[i - width] == EMPTY:
			_swap(i, i - width)
			return
		for dx: int in [first, -first]:
			var nx := x + dx
			if nx >= 0 and nx < width:
				var j := uy * width + nx
				if _cells[j] == EMPTY:
					_swap(i, j)
					return
	for dx: int in [first, -first]:
		var nx := x + dx
		if nx >= 0 and nx < width:
			var j := y * width + nx
			if _cells[j] == EMPTY:
				_swap(i, j)
				return
	_moved[i] = 1


func _is_flammable(m: int) -> bool:
	return m == WOOD or m == PLANT or m == OIL


func _is_dissolvable(m: int) -> bool:
	return m == STONE or m == WOOD or m == SAND or m == PLANT or m == ICE or m == ASH


## Fire: ignite flammable orthogonal neighbours (fuel becomes fire), emit smoke
## upward, and burn down — expiring to ASH (residue) or EMPTY. Stays in place.
func _update_fire(x: int, y: int, i: int) -> void:
	for off in NB4:
		var nx := x + off.x
		var ny := y + off.y
		if nx >= 0 and nx < width and ny >= 0 and ny < height:
			var j := ny * width + nx
			if _moved[j] == 0 and _is_flammable(_cells[j]):
				if _rng.randf() < FIRE_SPREAD:
					_cells[j] = FIRE
					_aux[j] = _fire_life()
					_moved[j] = 1
	if y - 1 >= 0:
		var up := i - width
		if _cells[up] == EMPTY and _rng.randf() < SMOKE_CHANCE:
			_cells[up] = SMOKE
			_aux[up] = SMOKE_LIFE
			_moved[up] = 1
	var life := _aux[i]
	if life <= 1:
		if _rng.randf() < ASH_CHANCE:
			_cells[i] = ASH
		else:
			_cells[i] = EMPTY
		_aux[i] = 0
	else:
		_aux[i] = life - 1
	_moved[i] = 1


## Lava: quench on water contact (lava→stone, water→steam), ignite flammables,
## cool to stone when its timer runs out, and otherwise creep (slow liquid).
func _update_lava(x: int, y: int, i: int) -> void:
	for off in NB4:
		var nx := x + off.x
		var ny := y + off.y
		if nx >= 0 and nx < width and ny >= 0 and ny < height:
			var j := ny * width + nx
			if _cells[j] == WATER:
				_cells[i] = STONE
				_aux[i] = 0
				_moved[i] = 1
				_cells[j] = STEAM
				_aux[j] = STEAM_LIFE
				_moved[j] = 1
				return
	for off in NB4:
		var nx2 := x + off.x
		var ny2 := y + off.y
		if nx2 >= 0 and nx2 < width and ny2 >= 0 and ny2 < height:
			var j2 := ny2 * width + nx2
			if _moved[j2] == 0 and _is_flammable(_cells[j2]) and _rng.randf() < LAVA_IGNITE:
				_cells[j2] = FIRE
				_aux[j2] = _fire_life()
				_moved[j2] = 1
	var life := _aux[i]
	if life <= 1:
		_cells[i] = STONE
		_aux[i] = 0
		_moved[i] = 1
		return
	_aux[i] = life - 1
	if (tick & 1) == 0:
		_flow(x, y, i)   # creeps only every other tick → visibly slow
	else:
		_moved[i] = 1


## Acid: dissolve one adjacent solid — BOTH the solid and this acid cell are
## consumed (acid depletes), so a puddle eats away at a wall over time. If it
## touches nothing dissolvable, it flows like a liquid.
func _update_acid(x: int, y: int, i: int) -> void:
	for off in NB4:
		var nx := x + off.x
		var ny := y + off.y
		if nx >= 0 and nx < width and ny >= 0 and ny < height:
			var j := ny * width + nx
			if _moved[j] == 0 and _is_dissolvable(_cells[j]):
				_cells[j] = EMPTY
				_aux[j] = 0
				_moved[j] = 1
				_cells[i] = EMPTY
				_aux[i] = 0
				_moved[i] = 1
				return
	_flow(x, y, i)


## Plant: static + flammable. When touching water it grows into an adjacent
## empty cell (seeded), so vegetation creeps along a waterline.
func _update_plant(x: int, y: int, i: int) -> void:
	var near_water := false
	var empties: Array[int] = []
	for off in NB4:
		var nx := x + off.x
		var ny := y + off.y
		if nx >= 0 and nx < width and ny >= 0 and ny < height:
			var j := ny * width + nx
			var t := _cells[j]
			if t == WATER:
				near_water = true
			elif t == EMPTY and _moved[j] == 0:
				empties.append(j)
	if near_water and not empties.is_empty() and _rng.randf() < GROW_CHANCE:
		var pick: int = empties[_rng.randi() % empties.size()]
		_cells[pick] = PLANT
		_aux[pick] = 0
		_moved[pick] = 1
	_moved[i] = 1


## Ice: static solid that melts to water the moment fire or lava is adjacent.
func _update_ice(x: int, y: int, i: int) -> void:
	for off in NB4:
		var nx := x + off.x
		var ny := y + off.y
		if nx >= 0 and nx < width and ny >= 0 and ny < height:
			var t := _cells[ny * width + nx]
			if t == FIRE or t == LAVA:
				_cells[i] = WATER
				_aux[i] = 0
				_moved[i] = 1
				return
	_moved[i] = 1


# =====================================================================
#  Determinism helper + persistence
# =====================================================================

## Order-independent-of-machine checksum of the whole world (cells+aux+tick).
## Two worlds are byte-identical iff their checksums AND arrays match.
func checksum() -> int:
	var h: int = 1469598103934665603
	var n := _cells.size()
	for i in n:
		h = (h ^ int(_cells[i])) * 1099511628211
		h = h & 0x7FFFFFFFFFFFFFFF
	for i in n:
		h = (h ^ int(_aux[i])) * 1099511628211
		h = h & 0x7FFFFFFFFFFFFFFF
	h = (h ^ tick) & 0x7FFFFFFFFFFFFFFF
	return h


## JSON/binary-portable snapshot of the ENTIRE world including RNG state, so a
## reload replays byte-for-byte. Packed grids are base64 so it survives JSON.
func snapshot() -> Dictionary:
	return {
		"w": width,
		"h": height,
		"tick": tick,
		"cells": Marshalls.raw_to_base64(_cells),
		"aux": Marshalls.raw_to_base64(_aux),
		"rng_seed": _rng.seed,
		"rng_state": _rng.state,
	}


func restore(d: Dictionary) -> void:
	width = int(d.get("w", width))
	height = int(d.get("h", height))
	tick = int(d.get("tick", 0))
	_cells = Marshalls.base64_to_raw(String(d.get("cells", "")))
	_aux = Marshalls.base64_to_raw(String(d.get("aux", "")))
	var n := width * height
	if _cells.size() != n:
		_cells.resize(n)
	if _aux.size() != n:
		_aux.resize(n)
	_moved = PackedByteArray()
	_moved.resize(n)
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(d.get("rng_seed", 0))
	_rng.state = int(d.get("rng_state", 0))
