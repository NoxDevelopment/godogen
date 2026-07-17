class_name MergeEngine
extends RefCounted
## Pure, seedable MERGE-PUZZLE engine (2048 lineage — the merge mechanic distilled): slide the
## board in a direction, equal tiles MERGE into the next tier, a new tile spawns, and you climb
## toward the target tile. Node-free + Time-free: one seeded RNG drives the tile spawns, so a
## whole game replays BYTE-IDENTICALLY from a seed (FNV-1a checksum). The scene (merge_view.gd) +
## GameManager wrap this; all rules live here (NoxDev ABI). The same slide-and-merge core
## generalises to a Merge-2/3 item board (see the doc's How-to-extend).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const N := 4                        ## 4x4 board
const WIN_TILE := 2048
const DIRS := {"left": 0, "right": 1, "up": 2, "down": 3}

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var grid: Array = []                ## N*N ints (0 = empty)
var score := 0
var moves := 0
var best_tile := 0
var won := false
var game_over := false
var last_merge := 0                 ## score gained by the last move (for popups)
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	grid = []
	grid.resize(N * N)
	for i in range(N * N):
		grid[i] = 0
	score = 0
	moves = 0
	best_tile = 0
	won = false
	game_over = false
	last_merge = 0
	log_lines = []
	_spawn()
	_spawn()
	_update_best()

func _idx(x: int, y: int) -> int:
	return y * N + x

func at(x: int, y: int) -> int:
	return int(grid[_idx(x, y)])

func _empty_cells() -> Array:
	var out: Array = []
	for i in range(N * N):
		if int(grid[i]) == 0:
			out.append(i)
	return out

func _spawn() -> void:
	var empties := _empty_cells()
	if empties.is_empty():
		return
	var cell: int = int(empties[rng.randi_range(0, empties.size() - 1)])
	grid[cell] = 4 if rng.randf() < 0.1 else 2

func _update_best() -> void:
	for i in range(N * N):
		if int(grid[i]) > best_tile:
			best_tile = int(grid[i])

# --------------------------------------------------------------------------- #
# Slide + merge
# --------------------------------------------------------------------------- #

## Collapse a line of N values toward index 0 (merging equal adjacent pairs once each).
## Returns [new_line, gained_score].
func _collapse(line: Array) -> Array:
	var nums: Array = []
	for v in line:
		if int(v) != 0:
			nums.append(int(v))
	var out: Array = []
	var gained := 0
	var i := 0
	while i < nums.size():
		if i + 1 < nums.size() and int(nums[i]) == int(nums[i + 1]):
			var m := int(nums[i]) * 2
			out.append(m)
			gained += m
			i += 2
		else:
			out.append(int(nums[i]))
			i += 1
	while out.size() < N:
		out.append(0)
	return [out, gained]

func _line(dir: int, k: int) -> Array:
	# read line k in the orientation so that "toward index 0" == the move direction
	var line: Array = []
	for i in range(N):
		match dir:
			0: line.append(at(i, k))              # left: row k, left→right
			1: line.append(at(N - 1 - i, k))      # right: row k reversed
			2: line.append(at(k, i))              # up: col k, top→bottom
			3: line.append(at(k, N - 1 - i))      # down: col k reversed
	return line

func _write_line(dir: int, k: int, line: Array) -> void:
	for i in range(N):
		var v := int(line[i])
		match dir:
			0: grid[_idx(i, k)] = v
			1: grid[_idx(N - 1 - i, k)] = v
			2: grid[_idx(k, i)] = v
			3: grid[_idx(k, N - 1 - i)] = v

## Move the board. Returns true if anything changed (and then a tile spawns).
func move(dir_name: String) -> bool:
	if game_over or not (dir_name in DIRS):
		return false
	var dir: int = int(DIRS[dir_name])
	var changed := false
	var gained := 0
	for k in range(N):
		var before := _line(dir, k)
		var res := _collapse(before)
		var after: Array = res[0]
		gained += int(res[1])
		for i in range(N):
			if int(before[i]) != int(after[i]):
				changed = true
		if changed:
			_write_line(dir, k, after)
	if not changed:
		return false
	score += gained
	last_merge = gained
	moves += 1
	_spawn()
	_update_best()
	if best_tile >= WIN_TILE and not won:
		won = true
		_log("Reached %d!" % WIN_TILE)
	if not _has_move():
		game_over = true
		_log("No moves left — final score %d (best tile %d)" % [score, best_tile])
	return true

func _has_move() -> bool:
	if not _empty_cells().is_empty():
		return true
	for y in range(N):
		for x in range(N):
			var v := at(x, y)
			if x + 1 < N and at(x + 1, y) == v:
				return true
			if y + 1 < N and at(x, y + 1) == v:
				return true
	return false

# --------------------------------------------------------------------------- #
# Deterministic auto-play seat (probe / demo) — a corner heuristic
# --------------------------------------------------------------------------- #

## Try directions in a fixed priority (down, left, right, up) — the classic keep-the-big-tile-
## in-a-corner strategy. Returns the move it would make, or "" if stuck.
func seat_move() -> String:
	for d in ["down", "left", "right", "up"]:
		if _would_change(d):
			return d
	return ""

func _would_change(dir_name: String) -> bool:
	var dir: int = int(DIRS[dir_name])
	for k in range(N):
		var before := _line(dir, k)
		var res := _collapse(before)
		var after: Array = res[0]
		for i in range(N):
			if int(before[i]) != int(after[i]):
				return true
	return false

func auto_step() -> void:
	if game_over:
		return
	var d := seat_move()
	if d == "":
		game_over = true
		return
	move(d)

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < 20000:
		auto_step()
		guard += 1

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 20:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d" % [score, moves, best_tile, int(won), int(game_over)]
	for v in grid:
		h = (h ^ int(v)) & mask
		h = (h * 1099511628211) & mask
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {"version": 1, "grid": grid.duplicate(), "score": score, "moves": moves,
		"best_tile": best_tile, "won": won, "game_over": game_over,
		"seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	grid = (d.get("grid", []) as Array).duplicate()
	score = int(d.get("score", 0))
	moves = int(d.get("moves", 0))
	best_tile = int(d.get("best_tile", 0))
	won = bool(d.get("won", false))
	game_over = bool(d.get("game_over", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
