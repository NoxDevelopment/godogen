class_name BlockEngine
extends RefCounted
## Pure, seedable FALLING-BLOCK PUZZLE engine (Tetris lineage) — a 10x20 well, the 7
## tetrominoes fed from a seeded 7-BAG randomizer, real collision + rotation with wall
## kicks, gravity that speeds up by level, line clears with the classic single/double/
## triple/tetris scoring, and top-out game over. Node-free + Time-free: the RNG only drives
## the bag, so a whole game replays BYTE-IDENTICALLY from a seed (FNV-1a checksum) and drives
## headlessly. Includes a Dellacherie-style placement AI. The scene (block_view.gd) +
## GameManager wrap this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const W := 10
const H := 20
const SPAWN_X := 3
const PIECE_CAP := 600                ## safety bound for auto_play_to_end (a good AI never tops out)
const LINES_PER_LEVEL := 10
const LINE_SCORE := [0, 100, 300, 500, 800]   ## by lines cleared at once
const SOFT_DROP_POINTS := 1
const HARD_DROP_POINTS := 2

# tetromino cell layouts per rotation state (x right, y down), origin at piece x,y
const SHAPES := {
	"O": [[[1, 0], [2, 0], [1, 1], [2, 1]]],
	"I": [[[0, 1], [1, 1], [2, 1], [3, 1]], [[2, 0], [2, 1], [2, 2], [2, 3]]],
	"T": [[[1, 0], [0, 1], [1, 1], [2, 1]], [[1, 0], [1, 1], [2, 1], [1, 2]], [[0, 1], [1, 1], [2, 1], [1, 2]], [[1, 0], [0, 1], [1, 1], [1, 2]]],
	"S": [[[1, 0], [2, 0], [0, 1], [1, 1]], [[1, 0], [1, 1], [2, 1], [2, 2]]],
	"Z": [[[0, 0], [1, 0], [1, 1], [2, 1]], [[2, 0], [1, 1], [2, 1], [1, 2]]],
	"J": [[[0, 0], [0, 1], [1, 1], [2, 1]], [[1, 0], [2, 0], [1, 1], [1, 2]], [[0, 1], [1, 1], [2, 1], [2, 2]], [[1, 0], [1, 1], [0, 2], [1, 2]]],
	"L": [[[2, 0], [0, 1], [1, 1], [2, 1]], [[1, 0], [1, 1], [1, 2], [2, 2]], [[0, 1], [1, 1], [2, 1], [0, 2]], [[0, 0], [1, 0], [1, 1], [1, 2]]],
}
const TYPES := ["I", "O", "T", "S", "Z", "J", "L"]
const KICKS := [0, -1, 1, -2, 2]     ## wall-kick x offsets tried in order on rotate

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var board: PackedByteArray = PackedByteArray()   ## W*H, 0 empty else type index+1
var bag: Array = []
var piece := {}                       ## {type, rot, x, y}
var next_type := ""
var score := 0
var lines := 0
var level := 1
var pieces := 0
var fall_timer := 0
var game_over := false
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	board = PackedByteArray()
	board.resize(W * H)
	bag = []
	score = 0
	lines = 0
	level = 1
	pieces = 0
	fall_timer = 0
	game_over = false
	log_lines = []
	next_type = _draw_type()
	_spawn()

func _cell(x: int, y: int) -> int:
	if x < 0 or x >= W or y < 0 or y >= H:
		return -1                     # out of bounds = solid
	return board[y * W + x]

func _put(x: int, y: int, v: int) -> void:
	if x >= 0 and x < W and y >= 0 and y < H:
		board[y * W + x] = v

# --------------------------------------------------------------------------- #
# Seeded 7-bag randomizer
# --------------------------------------------------------------------------- #

func _draw_type() -> String:
	if bag.is_empty():
		bag = TYPES.duplicate()
		# Fisher-Yates with the seeded RNG
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
	return str(bag.pop_back())

func _type_index(t: String) -> int:
	return TYPES.find(t) + 1

# --------------------------------------------------------------------------- #
# Piece geometry + collision
# --------------------------------------------------------------------------- #

func _shape(t: String, rot: int) -> Array:
	var states: Array = SHAPES[t]
	return states[rot % states.size()]

func cells_of(t: String, rot: int, px: int, py: int) -> Array:
	var out: Array = []
	for c in _shape(t, rot):
		out.append(Vector2i(px + int(c[0]), py + int(c[1])))
	return out

func _valid(t: String, rot: int, px: int, py: int) -> bool:
	for c in cells_of(t, rot, px, py):
		if c.x < 0 or c.x >= W or c.y >= H:
			return false
		if c.y >= 0 and board[c.y * W + c.x] != 0:
			return false
	return true

func current_cells() -> Array:
	if piece.is_empty():
		return []
	return cells_of(str(piece.type), int(piece.rot), int(piece.x), int(piece.y))

# --------------------------------------------------------------------------- #
# Spawn / lock / clear
# --------------------------------------------------------------------------- #

func _spawn() -> void:
	var t := next_type
	next_type = _draw_type()
	piece = {"type": t, "rot": 0, "x": SPAWN_X, "y": 0}
	pieces += 1
	if not _valid(t, 0, SPAWN_X, 0):
		game_over = true
		piece = {}
		_log("Top out — game over (score %d, lines %d)" % [score, lines])

func _lock() -> void:
	var idx := _type_index(str(piece.type))
	for c in current_cells():
		if c.y >= 0:
			_put(c.x, c.y, idx)
	_clear_lines()
	piece = {}
	if not game_over:
		_spawn()

func _clear_lines() -> void:
	var cleared := 0
	var y := H - 1
	while y >= 0:
		var full := true
		for x in range(W):
			if board[y * W + x] == 0:
				full = false
				break
		if full:
			cleared += 1
			# shift everything above down by one
			for yy in range(y, 0, -1):
				for x in range(W):
					board[yy * W + x] = board[(yy - 1) * W + x]
			for x in range(W):
				board[x] = 0
			# re-check the same row (now filled from above)
		else:
			y -= 1
	if cleared > 0:
		lines += cleared
		score += int(LINE_SCORE[clampi(cleared, 0, 4)]) * level
		var new_level: int = 1 + lines / LINES_PER_LEVEL
		if new_level > level:
			level = new_level
		_log("Cleared %d (score %d, level %d)" % [cleared, score, level])

# --------------------------------------------------------------------------- #
# Player actions
# --------------------------------------------------------------------------- #

func move(dx: int) -> bool:
	if game_over or piece.is_empty():
		return false
	if _valid(str(piece.type), int(piece.rot), int(piece.x) + dx, int(piece.y)):
		piece.x = int(piece.x) + dx
		return true
	return false

func rotate(dir: int) -> bool:
	if game_over or piece.is_empty():
		return false
	var nrot: int = (int(piece.rot) + dir + 4) % 4
	for k in KICKS:
		if _valid(str(piece.type), nrot, int(piece.x) + k, int(piece.y)):
			piece.rot = nrot
			piece.x = int(piece.x) + k
			return true
	return false

func soft_drop() -> bool:
	if game_over or piece.is_empty():
		return false
	if _valid(str(piece.type), int(piece.rot), int(piece.x), int(piece.y) + 1):
		piece.y = int(piece.y) + 1
		score += SOFT_DROP_POINTS
		return true
	_lock()
	return false

func hard_drop() -> void:
	if game_over or piece.is_empty():
		return
	var dist := 0
	while _valid(str(piece.type), int(piece.rot), int(piece.x), int(piece.y) + 1):
		piece.y = int(piece.y) + 1
		dist += 1
	score += dist * HARD_DROP_POINTS
	_lock()

func _fall_interval() -> int:
	# frames per gravity step; speeds up with level (60fps → ~1s at lvl1 down to fast)
	return max(4, 48 - (level - 1) * 4)

## Fixed-timestep gravity for the interactive view. input = {dx, rot, soft, hard}.
func tick(input: Dictionary) -> void:
	if game_over:
		return
	if int(input.get("dx", 0)) != 0:
		move(int(input.dx))
	if int(input.get("rot", 0)) != 0:
		rotate(int(input.rot))
	if bool(input.get("hard", false)):
		hard_drop()
		return
	var soft: bool = bool(input.get("soft", false))
	fall_timer += 1
	if soft or fall_timer >= _fall_interval():
		fall_timer = 0
		soft_drop()

# --------------------------------------------------------------------------- #
# Placement AI (Dellacherie-style) — used by the auto-seat
# --------------------------------------------------------------------------- #

## Compute the best (rot, x) for the current piece and execute it (hard drop + lock).
func ai_place() -> void:
	if game_over or piece.is_empty():
		return
	var t := str(piece.type)
	var best_rot := 0
	var best_x := int(piece.x)
	var best_score := -1e30
	var n_rot: int = (SHAPES[t] as Array).size()
	for rot in range(n_rot):
		for x in range(-2, W):
			if not _valid(t, rot, x, 0):
				continue
			# drop to rest
			var y := 0
			while _valid(t, rot, x, y + 1):
				y += 1
			var s := _eval_placement(t, rot, x, y)
			if s > best_score:
				best_score = s
				best_rot = rot
				best_x = x
	piece.rot = best_rot
	piece.x = best_x
	# guard: if the chosen x is somehow invalid at the top, keep current
	if not _valid(t, best_rot, best_x, int(piece.y)):
		piece.rot = 0
	hard_drop()

func _eval_placement(t: String, rot: int, px: int, py: int) -> float:
	# simulate landing on a scratch copy, then score with Dellacherie-ish weights
	var scratch := board.duplicate()
	var idx := _type_index(t)
	for c in cells_of(t, rot, px, py):
		if c.y >= 0 and c.y < H and c.x >= 0 and c.x < W:
			scratch[c.y * W + c.x] = idx
	# count lines that would clear
	var cleared := 0
	for y in range(H):
		var full := true
		for x in range(W):
			if scratch[y * W + x] == 0:
				full = false
				break
		if full:
			cleared += 1
	var agg_height := 0
	var holes := 0
	var bump := 0
	var prev_h := -1
	for x in range(W):
		var col_h := 0
		var seen_block := false
		for y in range(H):
			if scratch[y * W + x] != 0:
				if not seen_block:
					col_h = H - y
					seen_block = true
			elif seen_block:
				holes += 1
		agg_height += col_h
		if prev_h >= 0:
			bump += abs(col_h - prev_h)
		prev_h = col_h
	return -0.510066 * agg_height + 0.760666 * cleared - 0.35663 * holes - 0.184483 * bump

# --------------------------------------------------------------------------- #
# Deterministic auto-play (probe / attract)
# --------------------------------------------------------------------------- #

func auto_step(_policy: String = "ai") -> void:
	if game_over:
		return
	ai_place()

func auto_play_to_end(policy: String = "ai") -> void:
	var guard := 0
	while not game_over and guard < PIECE_CAP:
		auto_step(policy)
		guard += 1

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 30:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var pt: String = str(piece.get("type", "")) if not piece.is_empty() else ""
	var s := "%d|%d|%d|%d|%d|%s|%s|%d,%d,%d" % [int(game_over), score, lines, level, pieces,
		pt, next_type,
		int(piece.get("rot", 0)), int(piece.get("x", 0)), int(piece.get("y", 0))]
	for b in board:
		h = (h ^ int(b)) & mask
		h = (h * 1099511628211) & mask
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "score": score, "lines": lines, "level": level, "pieces": pieces,
		"fall_timer": fall_timer, "game_over": game_over, "next_type": next_type,
		"seed": int(rng.seed), "rng_state": int(rng.state),
		"board": board, "bag": bag.duplicate(), "piece": piece.duplicate(),
	}

func load_data(d: Dictionary) -> void:
	score = int(d.get("score", 0))
	lines = int(d.get("lines", 0))
	level = int(d.get("level", 1))
	pieces = int(d.get("pieces", 0))
	fall_timer = int(d.get("fall_timer", 0))
	game_over = bool(d.get("game_over", false))
	next_type = str(d.get("next_type", ""))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	board = d.get("board", PackedByteArray())
	bag = (d.get("bag", []) as Array).duplicate()
	piece = (d.get("piece", {}) as Dictionary).duplicate()
