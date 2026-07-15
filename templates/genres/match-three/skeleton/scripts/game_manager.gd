extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager") AND the match-3 BOARD
## engine. A match-3 is a grid of gems: swap two adjacent gems, and if that makes
## a line of 3+ the line clears, gems above fall in, new gems drop from the top,
## and any new lines those make clear too (a cascade). This holds that board as
## pure, seedable, headless-testable logic — the board scene only reads it and
## forwards swaps.
##
## Lives in the "game_manager" + "persistent" groups and implements the
## save_data()/load_data() ABI contract, so godotsmith's save_system persists the
## exact board + score.

signal board_changed  ## a swap resolved / board reshuffled (the view rebuilds)

const WIDTH := 8
const HEIGHT := 8
const NUM_GEMS := 6          ## gem type ids 0..5.
const EMPTY := -1
const POINTS_PER_GEM := 10   ## × the cascade step (chain 1,2,3…) for a chain bonus.

var cells: Array[int] = []   ## flat WIDTH*HEIGHT board, row-major (y*WIDTH+x).
var score := 0
var moves := 0               ## legal swaps made.
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


# =====================================================================
#  Board lifecycle
# =====================================================================

## Start a fresh board. seed == 0 → random; any other value is deterministic
## (tests + a fixed opening). The board is generated with NO pre-made matches and
## is guaranteed to have at least one legal move.
func new_board(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	score = 0
	moves = 0
	_generate_no_match_board()
	if not has_legal_move():
		_reshuffle()
	board_changed.emit()


func _idx(x: int, y: int) -> int:
	return y * WIDTH + x


func gem_at(x: int, y: int) -> int:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return EMPTY
	return cells[_idx(x, y)]


## Fill the board so no cell completes a run of 3 with the two to its left / above.
func _generate_no_match_board() -> void:
	cells = []
	cells.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			var choices: Array[int] = []
			for g in NUM_GEMS:
				if _would_start_run(x, y, g):
					continue
				choices.append(g)
			if choices.is_empty():
				choices.append(_rng.randi() % NUM_GEMS)
			cells[_idx(x, y)] = choices[_rng.randi() % choices.size()]


func _would_start_run(x: int, y: int, g: int) -> bool:
	if x >= 2 and cells[_idx(x - 1, y)] == g and cells[_idx(x - 2, y)] == g:
		return true
	if y >= 2 and cells[_idx(x, y - 1)] == g and cells[_idx(x, y - 2)] == g:
		return true
	return false


# =====================================================================
#  Matching
# =====================================================================

## Every cell index that is part of a horizontal or vertical run of 3+.
func find_matches() -> Array[int]:
	var matched := {}
	# horizontal runs
	for y in HEIGHT:
		var run := 1
		for x in range(1, WIDTH + 1):
			var same := x < WIDTH and cells[_idx(x, y)] != EMPTY and cells[_idx(x, y)] == cells[_idx(x - 1, y)]
			if same:
				run += 1
			else:
				if run >= 3:
					for k in range(x - run, x):
						matched[_idx(k, y)] = true
				run = 1
	# vertical runs
	for x in WIDTH:
		var run := 1
		for y in range(1, HEIGHT + 1):
			var same := y < HEIGHT and cells[_idx(x, y)] != EMPTY and cells[_idx(x, y)] == cells[_idx(x, y - 1)]
			if same:
				run += 1
			else:
				if run >= 3:
					for k in range(y - run, y):
						matched[_idx(x, k)] = true
				run = 1
	var out: Array[int] = []
	for key in matched.keys():
		out.append(int(key))
	return out


# =====================================================================
#  Swapping + cascade resolution
# =====================================================================

## Attempt a swap of two ORTHOGONALLY-ADJACENT cells. If it makes a match the
## swap commits and all cascades resolve; otherwise the board is unchanged.
## Returns {legal, cleared, chains, gained} — legal=false means an illegal or
## non-matching swap (the board did not change).
func try_swap(x1: int, y1: int, x2: int, y2: int) -> Dictionary:
	if not _are_adjacent(x1, y1, x2, y2):
		return {"legal": false, "cleared": 0, "chains": 0, "gained": 0}
	_swap_cells(x1, y1, x2, y2)
	if find_matches().is_empty():
		_swap_cells(x1, y1, x2, y2)  # revert — a swap must make a match
		return {"legal": false, "cleared": 0, "chains": 0, "gained": 0}
	moves += 1
	var result := _resolve_cascades()
	if not has_legal_move():
		_reshuffle()
	board_changed.emit()
	return {"legal": true, "cleared": result[0], "chains": result[1], "gained": result[2]}


func _are_adjacent(x1: int, y1: int, x2: int, y2: int) -> bool:
	if x1 < 0 or x1 >= WIDTH or y1 < 0 or y1 >= HEIGHT:
		return false
	if x2 < 0 or x2 >= WIDTH or y2 < 0 or y2 >= HEIGHT:
		return false
	return abs(x1 - x2) + abs(y1 - y2) == 1


func _swap_cells(x1: int, y1: int, x2: int, y2: int) -> void:
	var a := _idx(x1, y1)
	var b := _idx(x2, y2)
	var tmp := cells[a]
	cells[a] = cells[b]
	cells[b] = tmp


## Clear matches → gravity → refill, repeating for cascades. Returns
## [total_cleared, chain_count, score_gained].
func _resolve_cascades() -> Array:
	var total_cleared := 0
	var chains := 0
	var gained := 0
	while true:
		var matches := find_matches()
		if matches.is_empty():
			break
		chains += 1
		total_cleared += matches.size()
		var step_gain := matches.size() * POINTS_PER_GEM * chains
		gained += step_gain
		score += step_gain
		for i in matches:
			cells[i] = EMPTY
		_apply_gravity_and_refill()
	return [total_cleared, chains, gained]


## Per column: non-empty gems fall to the bottom; empties at the top get new gems.
func _apply_gravity_and_refill() -> void:
	for x in WIDTH:
		var stack: Array[int] = []
		for y in range(HEIGHT - 1, -1, -1):  # bottom → top
			var g := cells[_idx(x, y)]
			if g != EMPTY:
				stack.append(g)
		# refill: write the surviving gems from the bottom up, new gems above.
		for y in range(HEIGHT - 1, -1, -1):
			var from_bottom := HEIGHT - 1 - y
			if from_bottom < stack.size():
				cells[_idx(x, y)] = stack[from_bottom]
			else:
				cells[_idx(x, y)] = _rng.randi() % NUM_GEMS


# =====================================================================
#  Legal-move detection + reshuffle (no dead boards)
# =====================================================================

## Is there ANY adjacent swap that would create a match?
func has_legal_move() -> bool:
	for y in HEIGHT:
		for x in WIDTH:
			if x < WIDTH - 1 and _swap_makes_match(x, y, x + 1, y):
				return true
			if y < HEIGHT - 1 and _swap_makes_match(x, y, x, y + 1):
				return true
	return false


func _swap_makes_match(x1: int, y1: int, x2: int, y2: int) -> bool:
	_swap_cells(x1, y1, x2, y2)
	var ok := not find_matches().is_empty()
	_swap_cells(x1, y1, x2, y2)  # always revert — this is a probe
	return ok


## Rebuild the board (keeping score) until it has no matches and a legal move.
func _reshuffle() -> void:
	var guard := 0
	while guard < 200:
		guard += 1
		_generate_no_match_board()
		if has_legal_move():
			return


# =====================================================================
#  Persistence
# =====================================================================

func save_data() -> Dictionary:
	return {"cells": cells.duplicate(), "score": score, "moves": moves}


func load_data(data: Dictionary) -> void:
	cells = []
	for v in data.get("cells", []):
		cells.append(int(v))
	if cells.size() != WIDTH * HEIGHT:
		_generate_no_match_board()
	score = int(data.get("score", 0))
	moves = int(data.get("moves", 0))
	board_changed.emit()
