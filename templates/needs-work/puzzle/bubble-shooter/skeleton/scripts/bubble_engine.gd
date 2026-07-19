class_name BubbleEngine
extends RefCounted
## Pure, seedable BUBBLE-SHOOTER engine (Puzzle Bobble / Bust-a-Move lineage) run as a
## DETERMINISTIC sim: a hex-packed grid of coloured bubbles hangs from the ceiling; you AIM a
## shooter at the bottom and FIRE the current bubble, which flies, BOUNCES off the side walls,
## and STICKS where it lands. Landing next to 2+ of its own colour POPS the whole connected
## same-colour group; any bubbles left dangling (no path to the ceiling) then DROP. Clear the
## board to WIN; let the stack reach the bottom line and you LOSE. Every shot is resolved by a
## fixed-step ray-march + a nearest-empty-cell snap, so the whole match replays BYTE-IDENTICALLY
## from a seed (FNV-1a checksum over the quantized board). Node-free + Time-free; the scene
## (bubble_view.gd) + GameManager wrap this — all rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Geometry / rules
# --------------------------------------------------------------------------- #

const COLS := 11                    ## bubbles in an even row (odd rows hold COLS-1, offset by R)
const R := 16.0                     ## bubble radius
const D := 32.0                     ## bubble diameter / horizontal spacing
const ROWH := 27.7128129            ## vertical row spacing = D * sqrt(3)/2 (hex packing)
const TOP := 16.0                   ## y of the first row's centres (the ceiling)
const W := 352.0                    ## play-field width (COLS*D) — walls at [R, W-R]
const MAX_ROW := 11                 ## a bubble at or below this row means you LOSE
const START_ROWS := 5               ## rows dealt at match start
const SHOTS_PER_DROP := 4           ## after this many shots the whole field descends a row
const N_COLORS := 5                 ## palette size
const MARCH_STEP := 6.0             ## ray-march step length (px; < R so it can't tunnel a bubble)
const MARCH_GUARD := 2000           ## safety cap on march steps
const COLLIDE := 27.5               ## centre distance that counts as a hit (~0.86 * D)

# even-row hex neighbour offsets (odd rows shifted right)
const NB_EVEN := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(1, 0)]
const NB_ODD := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(1, 0), Vector2i(1, 1)]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var board: Dictionary = {}          ## Vector2i(r,c) -> color int
var current := 0                    ## colour loaded in the shooter
var next_color := 0                 ## colour on deck
var shots := 0
var score := 0
var popped := 0                     ## lifetime bubbles popped
var dropped := 0                    ## lifetime bubbles dropped (floaters)
var shooter := Vector2(W * 0.5, TOP + MAX_ROW * ROWH + 60.0)
var game_over := false
var won := false
var last_land := Vector2i(-9, -9)   ## last landing cell (for the view)
var last_popped: Array = []         ## cells popped by the last shot (for the view)
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	board = {}
	shots = 0
	score = 0
	popped = 0
	dropped = 0
	game_over = false
	won = false
	last_land = Vector2i(-9, -9)
	last_popped = []
	log_lines = []
	for r in range(START_ROWS):
		for c in range(cols_in_row(r)):
			board[Vector2i(r, c)] = rng.randi_range(0, N_COLORS - 1)
	current = _draw_color()
	next_color = _draw_color()

func cols_in_row(r: int) -> int:
	return COLS if (r % 2) == 0 else COLS - 1

func cell_center(cell: Vector2i) -> Vector2:
	var x := R + float(cell.y) * D + (R if (cell.x % 2) == 1 else 0.0)
	var y := TOP + float(cell.x) * ROWH
	return Vector2(x, y)

func neighbors(cell: Vector2i) -> Array:
	var offs: Array = NB_EVEN if (cell.x % 2) == 0 else NB_ODD
	var out: Array = []
	for o in offs:
		var nr: int = cell.x + int(o.x)
		var nc: int = cell.y + int(o.y)
		if nr < 0 or nr > MAX_ROW:
			continue
		if nc < 0 or nc >= cols_in_row(nr):
			continue
		out.append(Vector2i(nr, nc))
	return out

## Draw a colour that is still present on the board when possible (so progress stays possible).
func _draw_color() -> int:
	var present: Dictionary = {}
	for col in board.values():
		present[int(col)] = true
	if present.is_empty():
		return rng.randi_range(0, N_COLORS - 1)
	var keys: Array = present.keys()
	keys.sort()
	return int(keys[rng.randi_range(0, keys.size() - 1)])

# --------------------------------------------------------------------------- #
# Shot resolution (ray-march + snap) — shared by real fire AND the AI probe
# --------------------------------------------------------------------------- #

## March a bubble from the shooter along `dir` (unit vector, pointing up-ish) through `b`,
## bouncing off the walls, and return the empty cell it snaps into (or Vector2i(-9,-9)).
func _march(b: Dictionary, dir: Vector2) -> Vector2i:
	# Precompute the front (lowest filled y) so the long lower stretch of flight skips the
	# per-cell collision scan entirely — the bubble can only hit something near the stack.
	var front_y := TOP
	for cell in b:
		var cy: float = TOP + float(cell.x) * ROWH
		if cy > front_y:
			front_y = cy
	var scan_below := front_y + D
	var pos := shooter
	var step := dir.normalized() * MARCH_STEP
	var c2 := COLLIDE * COLLIDE
	var guard := 0
	while guard < MARCH_GUARD:
		guard += 1
		pos += step
		if pos.x < R:
			pos.x = 2.0 * R - pos.x
			step.x = -step.x
		elif pos.x > W - R:
			pos.x = 2.0 * (W - R) - pos.x
			step.x = -step.x
		if pos.y <= TOP:
			return _snap(b, Vector2(pos.x, TOP))
		if pos.y <= scan_below:
			for cell in b:
				if pos.distance_squared_to(cell_center(cell)) < c2:
					return _snap(b, pos)
		if pos.y > shooter.y + 10.0:
			return Vector2i(-9, -9)      # flew off the bottom (only if aimed downward)
	return Vector2i(-9, -9)

## The empty, in-bounds cell nearest `pos` that is anchored (row 0 or adjacent to a filled cell).
func _snap(b: Dictionary, pos: Vector2) -> Vector2i:
	var best := Vector2i(-9, -9)
	var bestd := 1e20
	var r0: int = int(round((pos.y - TOP) / ROWH))
	for rr in range(max(0, r0 - 2), min(MAX_ROW, r0 + 2) + 1):
		for cc in range(cols_in_row(rr)):
			var cell := Vector2i(rr, cc)
			if b.has(cell):
				continue
			var anchored := (rr == 0)
			if not anchored:
				for nb in neighbors(cell):
					if b.has(nb):
						anchored = true
						break
			if not anchored:
				continue
			var dd := pos.distance_to(cell_center(cell))
			if dd < bestd:
				bestd = dd
				best = cell
	return best

## Same-colour connected group containing `cell` (flood over neighbours of equal colour).
func _same_group(b: Dictionary, cell: Vector2i) -> Array:
	return _group_with(b, cell, int(b[cell]))

## Same as _same_group but treats `cell` as colour `col` even if it is not yet in `b` — lets the
## AI score a hypothetical landing WITHOUT duplicating the whole board.
func _group_with(b: Dictionary, cell: Vector2i, col: int) -> Array:
	var seen: Dictionary = {cell: true}
	var stack: Array = [cell]
	var out: Array = [cell]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for nb in neighbors(cur):
			if seen.has(nb):
				continue
			if b.has(nb) and int(b[nb]) == col:
				seen[nb] = true
				stack.append(nb)
				out.append(nb)
	return out

## Cells NOT connected to the ceiling (row 0) through any adjacency — they will drop.
func _floaters(b: Dictionary) -> Array:
	var anchored: Dictionary = {}
	var stack: Array = []
	for cell in b:
		if cell.x == 0:
			anchored[cell] = true
			stack.append(cell)
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for nb in neighbors(cur):
			if b.has(nb) and not anchored.has(nb):
				anchored[nb] = true
				stack.append(nb)
	var out: Array = []
	for cell in b:
		if not anchored.has(cell):
			out.append(cell)
	return out

# --------------------------------------------------------------------------- #
# Firing
# --------------------------------------------------------------------------- #

## Aim angle in radians (0 = straight up, negative = left, positive = right).
func fire(angle: float) -> void:
	if game_over:
		return
	var a := clampf(angle, -1.35, 1.35)
	var dir := Vector2(sin(a), -cos(a))
	var land := _march(board, dir)
	last_popped = []
	if land.x >= 0:
		board[land] = current
		last_land = land
		var group := _same_group(board, land)
		if group.size() >= 3:
			for cell in group:
				board.erase(cell)
			popped += group.size()
			score += group.size() * 10
			last_popped = group.duplicate()
			var floats := _floaters(board)
			for cell in floats:
				board.erase(cell)
			dropped += floats.size()
			score += floats.size() * 20      # dangling drops are worth more
	shots += 1
	current = next_color
	next_color = _draw_color()
	if board.is_empty():
		won = true
		_finish("cleared")
		return
	if shots % SHOTS_PER_DROP == 0:
		_descend()
	# lose if any bubble reached the bottom line
	for cell in board:
		if cell.x >= MAX_ROW:
			_finish("overflow")
			return

## Push the whole field down one row and deal a fresh top row.
func _descend() -> void:
	var moved: Dictionary = {}
	for cell in board:
		moved[Vector2i(cell.x + 1, cell.y)] = board[cell]
	for c in range(cols_in_row(0)):
		moved[Vector2i(0, c)] = rng.randi_range(0, N_COLORS - 1)
	board = moved

func _finish(reason: String) -> void:
	game_over = true
	_log("Match over (%s): score %d, popped %d, dropped %d, shots %d" % [reason, score, popped, dropped, shots])

# --------------------------------------------------------------------------- #
# Deterministic aim auto-seat (probe / demo)
# --------------------------------------------------------------------------- #

## Evaluate a candidate angle on a COPY of the board: how many bubbles it would pop + drop,
## and how high it lands (smaller row = better when nothing pops).
func _eval_angle(a: float) -> Dictionary:
	var dir := Vector2(sin(a), -cos(a))
	var land := _march(board, dir)         # board is read-only here
	if land.x < 0:
		return {"ok": false, "pops": 0, "row": 99}
	var group := _group_with(board, land, current)   # score WITHOUT mutating the board
	var pops: int = group.size() if group.size() >= 3 else 0
	return {"ok": true, "pops": pops, "row": int(land.x)}

## Pick the best aim: maximise pops; if nothing pops, land as HIGH as possible; tie-break straight.
func ai_angle() -> float:
	var best_a := 0.0
	var best_pops := -1
	var best_row := 99
	var a := -1.30
	while a <= 1.30:
		var e := _eval_angle(a)
		if bool(e.ok):
			var pops: int = int(e.pops)
			var row: int = int(e.row)
			if pops > best_pops or (pops == best_pops and row < best_row) \
					or (pops == best_pops and row == best_row and absf(a) < absf(best_a)):
				best_pops = pops
				best_row = row
				best_a = a
		a += 0.04
	return best_a

func auto_step() -> void:
	if game_over:
		return
	fire(ai_angle())

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < 2000:
		auto_step()
		guard += 1
	if not game_over:
		_finish("guard")

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 20:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full board state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d|%d|%d" % [current, next_color, shots, score, popped, dropped,
		int(game_over), int(won)]
	var keys: Array = board.keys()
	keys.sort_custom(func(x, y): return (x.x * 100 + x.y) < (y.x * 100 + y.y))
	for cell in keys:
		s += "|B%d,%d,%d" % [cell.x, cell.y, int(board[cell])]
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	var flat: Array = []
	for cell in board:
		flat.append([cell.x, cell.y, int(board[cell])])
	return {"version": 1, "board": flat, "current": current, "next_color": next_color,
		"shots": shots, "score": score, "popped": popped, "dropped": dropped,
		"game_over": game_over, "won": won, "seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	board = {}
	for e in (d.get("board", []) as Array):
		board[Vector2i(int(e[0]), int(e[1]))] = int(e[2])
	current = int(d.get("current", 0))
	next_color = int(d.get("next_color", 0))
	shots = int(d.get("shots", 0))
	score = int(d.get("score", 0))
	popped = int(d.get("popped", 0))
	dropped = int(d.get("dropped", 0))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
