class_name PuzzleDateEngine
extends RefCounted
## Pure, seedable ADULT-PUZZLE-DATING engine (a HuniePop-style MATCH-3 that FEEDS a dating meter)
## run as a DETERMINISTIC sim. This template ships the PUZZLE + DATING SYSTEMS ONLY — a real match-3
## board whose cleared tokens convert to AFFECTION for the current date, weighted by that
## character's PREFERENCES, plus a gift economy and route completion — PLUS a `mature_content`
## GATING FLAG (OFF by default) that only calls EMPTY author hooks. It ships NO explicit content; an
## author who adds mature content owns their own assets, an age-verification gate, and platform
## compliance. Node-free + Time-free: one seeded RNG fills + refills the board, so a whole date
## replays BYTE-IDENTICALLY from a seed (FNV-1a checksum). The scene (puzzledate_view.gd) +
## GameManager wrap this; all rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Rules
# --------------------------------------------------------------------------- #

const GRID := 7
const TYPES := 5                     ## affection token types (passion/talent/charm/romance/joy)
const TYPE_NAMES := ["Passion", "Talent", "Charm", "Romance", "Joy"]
const MAX_TURNS := 40
const THRESHOLD := 120.0             ## affection needed to complete a route
const BASE := 2.0                    ## affection per cleared token before preference/mood
const GIFTS := [
	{"name": "Flowers", "cost": 15, "affection": 8.0, "mood": 0.10},
	{"name": "Dinner", "cost": 30, "affection": 18.0, "mood": 0.15},
	{"name": "Jewelry", "cost": 60, "affection": 40.0, "mood": 0.20},
]
# fixed per-character preference vectors (weight per token type) — deterministic + readable
const CHARS := [
	{"name": "Aria", "pref": [3.0, 1.0, 0.5, 2.0, 1.0]},
	{"name": "Bess", "pref": [1.0, 3.0, 1.0, 0.5, 2.0]},
	{"name": "Cleo", "pref": [0.5, 1.0, 3.0, 1.0, 2.0]},
]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var board: Array = []                ## GRID*GRID ints (0..TYPES-1)
var chars: Array = []                ## {name, pref, affection, mood, done}
var target := 0                      ## current date (character index)
var currency := 0
var turns := 0
var last_cleared := 0
var last_gain := 0.0
var game_over := false
var won := false
var mature_content := false          ## GATE — OFF by default; only unlocks empty hooks
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	chars = []
	for c in CHARS:
		chars.append({"name": str(c.name), "pref": (c.pref as Array).duplicate(),
			"affection": 0.0, "mood": 1.0, "done": false})
	target = 0
	currency = 20
	turns = 0
	last_cleared = 0
	last_gain = 0.0
	game_over = false
	won = false
	mature_content = false
	log_lines = []
	_fill_board()

func _at(r: int, c: int) -> int:
	return int(board[r * GRID + c])

func _set_at(r: int, c: int, v: int) -> void:
	board[r * GRID + c] = v

## Fill with no pre-existing matches (avoid a third-in-a-row while placing).
func _fill_board() -> void:
	board = []
	board.resize(GRID * GRID)
	for r in range(GRID):
		for c in range(GRID):
			var v := rng.randi_range(0, TYPES - 1)
			var guard := 0
			while guard < 40 and _would_run(r, c, v):
				v = rng.randi_range(0, TYPES - 1)
				guard += 1
			board[r * GRID + c] = v

func _would_run(r: int, c: int, v: int) -> bool:
	if c >= 2 and _at(r, c - 1) == v and _at(r, c - 2) == v:
		return true
	if r >= 2 and _at(r - 1, c) == v and _at(r - 2, c) == v:
		return true
	return false

# --------------------------------------------------------------------------- #
# Match-3 core
# --------------------------------------------------------------------------- #

## Cells that belong to any horizontal/vertical run of >=3. Returns {index: true}.
func _find_matches() -> Dictionary:
	var hit: Dictionary = {}
	# horizontal
	for r in range(GRID):
		var run := 1
		for c in range(1, GRID):
			if _at(r, c) == _at(r, c - 1) and _at(r, c) >= 0:
				run += 1
			else:
				if run >= 3:
					for k in range(c - run, c):
						hit[r * GRID + k] = true
				run = 1
		if run >= 3:
			for k in range(GRID - run, GRID):
				hit[r * GRID + k] = true
	# vertical
	for c in range(GRID):
		var run := 1
		for r in range(1, GRID):
			if _at(r, c) == _at(r - 1, c) and _at(r, c) >= 0:
				run += 1
			else:
				if run >= 3:
					for k in range(r - run, r):
						hit[k * GRID + c] = true
				run = 1
		if run >= 3:
			for k in range(GRID - run, GRID):
				hit[k * GRID + c] = true
	return hit

## Resolve all cascades from the current board, scoring affection for `who`. Mutates the board.
func _resolve(who: int) -> Dictionary:
	var total_cleared := 0
	var gain := 0.0
	var earned := 0
	var pref: Array = chars[who].pref
	var mood: float = float(chars[who].mood)
	while true:
		var hit := _find_matches()
		if hit.is_empty():
			break
		for idx in hit:
			var t := int(board[idx])
			total_cleared += 1
			earned += 1
			gain += BASE * float(pref[t]) * mood
			board[idx] = -1
		_apply_gravity()
	chars[who].affection = minf(999.0, float(chars[who].affection) + gain)
	currency += earned
	return {"cleared": total_cleared, "gain": gain}

## Tokens fall into empties; new tokens spawn at the top from the RNG.
func _apply_gravity() -> void:
	for c in range(GRID):
		var write := GRID - 1
		for r in range(GRID - 1, -1, -1):
			if _at(r, c) >= 0:
				_set_at(write, c, _at(r, c))
				write -= 1
		while write >= 0:
			_set_at(write, c, rng.randi_range(0, TYPES - 1))
			write -= 1

func _swap(a: int, b: int) -> void:
	var t := int(board[a])
	board[a] = board[b]
	board[b] = t

## Is (r,c)<->(r2,c2) a legal move (adjacent + creates a match)? Non-mutating.
func is_legal(r: int, c: int, r2: int, c2: int) -> bool:
	if abs(r - r2) + abs(c - c2) != 1:
		return false
	if r2 < 0 or r2 >= GRID or c2 < 0 or c2 >= GRID:
		return false
	var a := r * GRID + c
	var b := r2 * GRID + c2
	_swap(a, b)
	var ok := not _find_matches().is_empty()
	_swap(a, b)
	return ok

## Apply a move: swap, then resolve cascades scoring for the current target. Returns cleared count.
func play_move(r: int, c: int, r2: int, c2: int) -> int:
	if game_over or not is_legal(r, c, r2, c2):
		return 0
	_swap(r * GRID + c, r2 * GRID + c2)
	var res := _resolve(target)
	last_cleared = int(res.cleared)
	last_gain = float(res.gain)
	turns += 1
	_check_completion()
	if turns >= MAX_TURNS and not game_over:
		game_over = true
		won = _all_targets_possible()
	return last_cleared

func _check_completion() -> void:
	if not bool(chars[target].done) and float(chars[target].affection) >= THRESHOLD:
		chars[target].done = true
		_log("%s's route complete! (affection %.0f)" % [str(chars[target].name), float(chars[target].affection)])
		# GATED, EMPTY hook on route completion — no content ships in the template
		if mature_content:
			_mature_hook("route_complete", {"char": str(chars[target].name)})
		# advance to the next unfinished character, else win
		var nxt := _next_open()
		if nxt < 0:
			game_over = true
			won = true
			_log("All routes complete — you win!")
		else:
			target = nxt

func _next_open() -> int:
	for i in range(chars.size()):
		if not bool(chars[i].done):
			return i
	return -1

func _all_targets_possible() -> bool:
	# a "win at the buzzer" only if at least the first route completed
	for c in chars:
		if bool(c.done):
			return true
	return false

# ---- gifts ---- #

func buy_gift(idx: int) -> bool:
	if game_over or idx < 0 or idx >= GIFTS.size():
		return false
	var g: Dictionary = GIFTS[idx]
	if currency < int(g.cost):
		return false
	currency -= int(g.cost)
	chars[target].affection = minf(999.0, float(chars[target].affection) + float(g.affection))
	chars[target].mood = minf(3.0, float(chars[target].mood) + float(g.mood))
	_log("Gave %s a %s (+%.0f affection)" % [str(chars[target].name), str(g.name), float(g.affection)])
	_check_completion()
	return true

## INTENTIONALLY EMPTY. Author hook for gated mature milestones. Left empty on purpose — the
## template ships the puzzle + dating SYSTEMS + this gate, and NO explicit content. Wire your OWN
## age-verified, platform-compliant content here if you choose to.
func _mature_hook(_event: String, _ctx: Dictionary) -> void:
	pass

# --------------------------------------------------------------------------- #
# Deterministic player auto-seat (probe / demo)
# --------------------------------------------------------------------------- #

## Score a hypothetical swap by the preference-weighted count of the tokens it would immediately
## clear for the current target (non-mutating).
func _swap_score(a: int, b: int) -> float:
	_swap(a, b)
	var hit := _find_matches()
	var pref: Array = chars[target].pref
	var sc := 0.0
	for idx in hit:
		sc += float(pref[int(board[idx])])
	_swap(a, b)
	return sc

## Best legal move for the current target (max preference-weighted immediate clear).
func best_move() -> Array:
	var best: Array = []
	var best_sc := -1.0
	for r in range(GRID):
		for c in range(GRID):
			# right + down neighbours cover all adjacent swaps
			for d in [[0, 1], [1, 0]]:
				var r2: int = r + d[0]
				var c2: int = c + d[1]
				if r2 >= GRID or c2 >= GRID:
					continue
				var a := r * GRID + c
				var b := r2 * GRID + c2
				_swap(a, b)
				var has := not _find_matches().is_empty()
				_swap(a, b)
				if not has:
					continue
				var sc := _swap_score(a, b)
				if sc > best_sc:
					best_sc = sc
					best = [r, c, r2, c2]
	return best

func auto_step() -> void:
	if game_over:
		return
	# spend on the best affordable gift for the target when flush (accelerates a route)
	for gi in range(GIFTS.size() - 1, -1, -1):
		if currency >= int(GIFTS[gi].cost) and currency >= 60:
			buy_gift(gi)
			break
	var mv := best_move()
	if mv.is_empty():
		# no legal move (rare) — reshuffle deterministically and burn a turn
		_fill_board()
		turns += 1
		if turns >= MAX_TURNS:
			game_over = true
			won = _all_targets_possible()
		return
	play_move(int(mv[0]), int(mv[1]), int(mv[2]), int(mv[3]))

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < MAX_TURNS + 5:
		auto_step()
		guard += 1
	if not game_over:
		game_over = true

func routes_done() -> int:
	var n := 0
	for c in chars:
		if bool(c.done):
			n += 1
	return n

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
	var s := "%d|%d|%d|%d|%d|%d" % [target, currency, turns, int(game_over), int(won), int(mature_content)]
	for c in chars:
		s += "|%s%d,%d,%d" % [str(c.name), int(round(float(c.affection))), int(round(float(c.mood) * 100.0)), int(bool(c.done))]
	s += "|B"
	for v in board:
		s += str(int(v))
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {"version": 1, "board": board.duplicate(), "chars": chars.duplicate(true), "target": target,
		"currency": currency, "turns": turns, "game_over": game_over, "won": won,
		"mature_content": mature_content, "seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	board = (d.get("board", []) as Array).duplicate()
	chars = (d.get("chars", []) as Array).duplicate(true)
	target = int(d.get("target", 0))
	currency = int(d.get("currency", 0))
	turns = int(d.get("turns", 0))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	mature_content = bool(d.get("mature_content", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
