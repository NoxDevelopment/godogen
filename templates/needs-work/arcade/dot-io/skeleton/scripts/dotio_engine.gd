class_name DotIoEngine
extends RefCounted
## Pure, seedable .IO GROW-ARENA engine (Hole.io / Agar.io lineage) run as a DETERMINISTIC
## FIXED-TIMESTEP sim: steer your "hole", SWALLOW objects (and rival holes) smaller than you to
## GROW, and out-mass the AI rivals before the timer ends. Node-free + Time-free: one seeded RNG
## places the objects + drives the rival AI, so a whole match replays BYTE-IDENTICALLY from a
## seed (FNV-1a checksum over quantized state). The scene (dotio_view.gd) + GameManager wrap this;
## all rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const ARENA := Vector2(620, 400)
const MATCH_TICKS := 60 * 60        ## 60-second match
const N_RIVALS := 3
const N_OBJECTS := 44
const HOLE_START := 22.0
const SPEED := 2.7
const OBJ_GROWTH := 0.14           ## fraction of a swallowed object's size added to the hole
const HOLE_EAT_RATIO := 1.12       ## you must be this much bigger to swallow a rival hole

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var holes: Array = []               ## [{id, is_player, pos, size, score}] index 0 = player
var objects: Array = []             ## [{pos, size, alive}]
var tick_no := 0
var game_over := false
var winner := -1
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	holes = []
	objects = []
	tick_no = 0
	game_over = false
	winner = -1
	log_lines = []
	_next_id = 1
	holes.append(_make_hole(true))
	for i in range(N_RIVALS):
		holes.append(_make_hole(false))
	for i in range(N_OBJECTS):
		objects.append(_make_object())

func _make_hole(is_player: bool) -> Dictionary:
	return {"id": _new_id(), "is_player": is_player,
		"pos": Vector2(rng.randf_range(40, ARENA.x - 40), rng.randf_range(40, ARENA.y - 40)),
		"size": HOLE_START, "score": 0.0}

func _make_object() -> Dictionary:
	# a spread of object sizes; small ones are easy early, big ones are late-game meals
	var sz := 5.0 + float(rng.randi_range(0, 3)) * 8.0 + float(rng.randi_range(0, 6)) * 4.0
	return {"pos": Vector2(rng.randf_range(8, ARENA.x - 8), rng.randf_range(8, ARENA.y - 8)),
		"size": sz, "alive": true}

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

func radius(size: float) -> float:
	return sqrt(size) * 2.4

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

## input = {move: Vector2} — steers the player hole (index 0).
func tick(input: Dictionary) -> void:
	if game_over:
		return
	for i in range(holes.size()):
		var h: Dictionary = holes[i]
		var mv: Vector2
		if int(i) == 0 and not bool(input.get("_ai", false)):
			mv = input.get("move", Vector2.ZERO)
		else:
			mv = _ai_dir(h)
		if mv.length() > 0.01:
			h.pos = (h.pos + mv.normalized() * SPEED).clamp(Vector2.ZERO, ARENA)
	_resolve_swallows()
	tick_no += 1
	if tick_no >= MATCH_TICKS:
		_finish()

func _resolve_swallows() -> void:
	for h in holes:
		var rr := radius(float(h.size))
		# objects
		for o in objects:
			if not bool(o.alive):
				continue
			if float(o.size) <= float(h.size) and (h.pos as Vector2).distance_to(o.pos) < rr:
				o.alive = false
				h.size = float(h.size) + float(o.size) * OBJ_GROWTH
				h.score = float(h.score) + float(o.size)
				# respawn the object elsewhere to keep the arena stocked (endless growth)
				o.pos = Vector2(rng.randf_range(8, ARENA.x - 8), rng.randf_range(8, ARENA.y - 8))
				o.size = 5.0 + float(rng.randi_range(0, 3)) * 8.0 + float(rng.randi_range(0, 6)) * 4.0
				o.alive = true
	# hole-vs-hole (bigger swallows smaller)
	for a in holes:
		for b in holes:
			if int(a.id) == int(b.id):
				continue
			if float(a.size) > float(b.size) * HOLE_EAT_RATIO and (a.pos as Vector2).distance_to(b.pos) < radius(float(a.size)) * 0.8:
				a.size = float(a.size) + float(b.size) * 0.25
				a.score = float(a.score) + float(b.size)
				if bool(b.is_player):
					_log("You were swallowed! (respawn)")
				# respawn the smaller hole
				b.size = HOLE_START
				b.pos = Vector2(rng.randf_range(40, ARENA.x - 40), rng.randf_range(40, ARENA.y - 40))

func _ai_dir(h: Dictionary) -> Vector2:
	# head for the nearest swallowable object; flee a much bigger hole nearby
	var danger := _nearest_bigger_hole(h)
	if not danger.is_empty() and (danger.pos as Vector2).distance_to(h.pos) < radius(float(danger.size)) * 1.6:
		return (h.pos as Vector2) - (danger.pos as Vector2)
	var target := _nearest_object(h, true)
	if target.is_empty():
		target = _nearest_object(h, false)
	if target.is_empty():
		return Vector2.ZERO
	return (target.pos as Vector2) - (h.pos as Vector2)

func _nearest_object(h: Dictionary, swallowable_only: bool) -> Dictionary:
	var best := {}
	var bd := 1e20
	for o in objects:
		if not bool(o.alive):
			continue
		if swallowable_only and float(o.size) > float(h.size):
			continue
		var d: float = (h.pos as Vector2).distance_squared_to(o.pos)
		if d < bd:
			bd = d
			best = o
	return best

func _nearest_bigger_hole(h: Dictionary) -> Dictionary:
	var best := {}
	var bd := 1e20
	for o in holes:
		if int(o.id) == int(h.id) or float(o.size) <= float(h.size) * HOLE_EAT_RATIO:
			continue
		var d: float = (h.pos as Vector2).distance_squared_to(o.pos)
		if d < bd:
			bd = d
			best = o
	return best

func _finish() -> void:
	game_over = true
	var best := 0
	var bs := -1.0
	for i in range(holes.size()):
		if float(holes[i].score) > bs:
			bs = float(holes[i].score)
			best = i
	winner = best
	_log("Time! Winner: %s (score %.0f)" % [("YOU" if winner == 0 else "rival %d" % winner), bs])

func player() -> Dictionary:
	return holes[0] if holes.size() > 0 else {}

func rank() -> int:
	var p := float(holes[0].score) if holes.size() > 0 else 0.0
	var r := 1
	for i in range(1, holes.size()):
		if float(holes[i].score) > p:
			r += 1
	return r

# --------------------------------------------------------------------------- #
# Deterministic auto-play (probe / attract) — all holes AI
# --------------------------------------------------------------------------- #

func auto_step() -> void:
	if game_over:
		return
	tick({"_ai": true})

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < MATCH_TICKS + 4:
		auto_step()
		guard += 1
	if not game_over:
		_finish()

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[%02ds] %s" % [int(tick_no / 60), s])
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
	var s := "%d|%d|%d" % [tick_no, int(game_over), winner]
	for ho in holes:
		s += "|H%d,%d,%d,%d" % [_q(ho.pos.x), _q(ho.pos.y), _q(ho.size), _q(ho.score)]
	for o in objects:
		s += "|O%d,%d,%d" % [_q(o.pos.x), _q(o.pos.y), _q(o.size)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {"version": 1, "holes": holes.duplicate(true), "objects": objects.duplicate(true),
		"tick_no": tick_no, "game_over": game_over, "winner": winner, "next_id": _next_id,
		"seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	holes = (d.get("holes", []) as Array).duplicate(true)
	objects = (d.get("objects", []) as Array).duplicate(true)
	tick_no = int(d.get("tick_no", 0))
	game_over = bool(d.get("game_over", false))
	winner = int(d.get("winner", -1))
	_next_id = int(d.get("next_id", 1))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
