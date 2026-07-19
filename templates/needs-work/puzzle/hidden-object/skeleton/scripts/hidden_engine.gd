class_name HiddenEngine
extends RefCounted
## Pure, seedable HIDDEN-OBJECT engine (seek-and-find casual lineage): a cluttered scene of
## seeded item placements, a FIND LIST to locate by clicking, DECOY items that punish misclicks,
## a limited HINT system, a per-round TIMER, combo + time-bonus scoring, and escalating rounds.
## Node-free + Time-free: one seeded RNG places the objects + picks the find list, so a whole
## game replays BYTE-IDENTICALLY from a seed (FNV-1a checksum) and drives headlessly. The scene
## (hidden_view.gd) + GameManager wrap this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const AREA := Vector2(1040, 560)
const AREA_ORIGIN := Vector2(120, 120)     ## top-left of the play area on screen
const OBJ_R := 22.0                        ## click hit radius
const MIN_SEP := 58.0                       ## min spacing between placed objects
const MAX_ROUNDS := 4
const FIND_BASE := 100
const MISCLICK_PENALTY := 40
const HINT_PENALTY := 60
const HINTS_PER_ROUND := 3
const HINT_REVEAL_TICKS := 150             ## 2.5s highlight
const ROUND_TIME := 60 * 45                 ## 45s per round
const TIME_BONUS_PER_SEC := 5

const ITEMS := ["key", "book", "cup", "ring", "coin", "apple", "candle", "gem",
	"clock", "boot", "hat", "fish", "star", "leaf", "bell", "mug"]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var round_no := 0
var objects: Array = []             ## {id, name, pos, is_target, found}
var find_list: Array = []           ## target object ids still to find
var found_count := 0
var score := 0
var combo := 0
var hints_left := 0
var hint_id := 0                    ## object currently revealed by a hint (0 = none)
var hint_timer := 0
var time_left := 0
var misclicks := 0
var game_over := false
var won := false
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	round_no = 0
	score = 0
	misclicks = 0
	game_over = false
	won = false
	log_lines = []
	_next_id = 1
	_start_round()

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

func _start_round() -> void:
	round_no += 1
	if round_no > MAX_ROUNDS:
		_finish(true)
		return
	objects = []
	find_list = []
	found_count = 0
	combo = 0
	hints_left = HINTS_PER_ROUND
	hint_id = 0
	hint_timer = 0
	time_left = ROUND_TIME
	# place a cluttered scene: (5 + round) targets + a wave of decoys
	var n_targets: int = 5 + round_no
	var n_decoys: int = 8 + round_no * 2
	var used_names := {}
	for i in range(n_targets):
		var name := _pick_item(used_names)
		var o := {"id": _new_id(), "name": name, "pos": _place(), "is_target": true, "found": false}
		objects.append(o)
		find_list.append(int(o.id))
	for i in range(n_decoys):
		objects.append({"id": _new_id(), "name": _rand_item(), "pos": _place(), "is_target": false, "found": false})
	_log("Round %d — find %d items among %d" % [round_no, n_targets, objects.size()])

func _pick_item(used: Dictionary) -> String:
	# unique-ish target names so the find list reads cleanly
	var guard := 0
	while guard < 40:
		guard += 1
		var n: String = ITEMS[rng.randi_range(0, ITEMS.size() - 1)]
		if not used.has(n):
			used[n] = true
			return n
	return ITEMS[rng.randi_range(0, ITEMS.size() - 1)]

func _rand_item() -> String:
	return ITEMS[rng.randi_range(0, ITEMS.size() - 1)]

func _place() -> Vector2:
	# rejection-sample a spot with min separation from existing objects
	for _try in range(60):
		var p := Vector2(rng.randf_range(OBJ_R, AREA.x - OBJ_R), rng.randf_range(OBJ_R, AREA.y - OBJ_R))
		var ok := true
		for o in objects:
			if p.distance_to(o.pos) < MIN_SEP:
				ok = false
				break
		if ok:
			return p
	return Vector2(rng.randf_range(OBJ_R, AREA.x - OBJ_R), rng.randf_range(OBJ_R, AREA.y - OBJ_R))

# --------------------------------------------------------------------------- #
# Lookups
# --------------------------------------------------------------------------- #

func object_by_id(id: int) -> Dictionary:
	for o in objects:
		if int(o.id) == id:
			return o
	return {}

## The find list as {id, name} for the UI checklist (found ones marked).
func find_list_status() -> Array:
	var out: Array = []
	for id in find_list:
		var o := object_by_id(id)
		if not o.is_empty():
			out.append({"id": int(o.id), "name": str(o.name), "found": bool(o.found)})
	return out

# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #

## Click at a position in AREA space (0..AREA). Returns "found"/"decoy"/"miss".
func click_at(p: Vector2) -> String:
	if game_over:
		return "miss"
	var hit := {}
	var bestd := OBJ_R + 1.0
	for o in objects:
		if bool(o.found):
			continue
		var d: float = p.distance_to(o.pos)
		if d <= OBJ_R and d < bestd:
			bestd = d
			hit = o
	if hit.is_empty():
		_misclick()
		return "miss"
	if not bool(hit.is_target):
		_misclick()
		return "decoy"
	# a target found
	hit.found = true
	found_count += 1
	combo += 1
	if int(hit.id) == hint_id:
		hint_id = 0
	var pts: int = FIND_BASE + (combo - 1) * 20
	score += pts
	_log("Found %s (+%d, combo %d)" % [str(hit.name), pts, combo])
	if found_count >= find_list.size():
		var bonus: int = int(time_left / 60) * TIME_BONUS_PER_SEC
		score += bonus
		_log("Round %d clear! +%d time bonus" % [round_no, bonus])
		_start_round()
	return "found"

func _misclick() -> void:
	misclicks += 1
	combo = 0
	score = max(0, score - MISCLICK_PENALTY)

func use_hint() -> bool:
	if game_over or hints_left <= 0:
		return false
	# reveal the first unfound target
	for id in find_list:
		var o := object_by_id(id)
		if not o.is_empty() and not bool(o.found):
			hints_left -= 1
			hint_id = int(o.id)
			hint_timer = HINT_REVEAL_TICKS
			score = max(0, score - HINT_PENALTY)
			_log("Hint used (%d left)" % hints_left)
			return true
	return false

## Fixed-timestep countdown for the interactive view — running out of time ends the game.
func tick() -> void:
	if game_over:
		return
	if hint_timer > 0:
		hint_timer -= 1
		if hint_timer == 0:
			hint_id = 0
	time_left -= 1
	if time_left <= 0:
		_finish(false)

func _finish(victory: bool) -> void:
	game_over = true
	won = victory
	_log("Game over: %s (score %d, round %d)" % [("all rounds clear!" if victory else "time up"), score, round_no])

# --------------------------------------------------------------------------- #
# Deterministic auto-play seat (probe / demo) — clicks each target it "knows"
# --------------------------------------------------------------------------- #

## The next action for the seat: click the position of the first unfound target (it can see
## the scene). Occasionally uses a hint to exercise that path. Deterministic.
func auto_step(_policy: String = "solver") -> void:
	if game_over:
		return
	# use a hint once per round for coverage, then just find items
	if hints_left == HINTS_PER_ROUND and found_count == 0:
		use_hint()
		return
	for id in find_list:
		var o := object_by_id(id)
		if not o.is_empty() and not bool(o.found):
			click_at(o.pos)
			return
	# nothing to click (shouldn't happen mid-round) — burn a tick
	tick()

func auto_play_to_end(policy: String = "solver") -> void:
	var guard := 0
	while not game_over and guard < 4000:
		auto_step(policy)
		guard += 1
	if not game_over:
		_finish(won)

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

func _q(v: float) -> int:
	return int(round(v))

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d|%d|%d|%d" % [round_no, int(game_over), int(won), score, combo,
		found_count, hints_left, misclicks, time_left]
	for o in objects:
		s += "|O%d,%s,%d,%d,%d,%d" % [int(o.id), str(o.name), _q(o.pos.x), _q(o.pos.y), int(o.is_target), int(o.found)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "round_no": round_no, "score": score, "combo": combo, "found_count": found_count,
		"hints_left": hints_left, "hint_id": hint_id, "hint_timer": hint_timer, "time_left": time_left,
		"misclicks": misclicks, "game_over": game_over, "won": won, "next_id": _next_id,
		"objects": objects.duplicate(true), "find_list": find_list.duplicate(),
		"seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	round_no = int(d.get("round_no", 0))
	score = int(d.get("score", 0))
	combo = int(d.get("combo", 0))
	found_count = int(d.get("found_count", 0))
	hints_left = int(d.get("hints_left", 0))
	hint_id = int(d.get("hint_id", 0))
	hint_timer = int(d.get("hint_timer", 0))
	time_left = int(d.get("time_left", 0))
	misclicks = int(d.get("misclicks", 0))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	_next_id = int(d.get("next_id", 1))
	objects = (d.get("objects", []) as Array).duplicate(true)
	find_list = (d.get("find_list", []) as Array).duplicate()
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
