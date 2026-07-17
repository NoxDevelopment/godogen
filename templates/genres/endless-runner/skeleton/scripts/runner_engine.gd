class_name RunnerEngine
extends RefCounted
## Pure, seedable ENDLESS-RUNNER engine (Subway Surfers / Temple Run lineage) run as a
## DETERMINISTIC FIXED-TIMESTEP sim: you auto-run forward down 3 LANES, SWITCH lanes / JUMP /
## SLIDE to dodge seeded obstacles, grab coins, and survive as the speed ramps up. Node-free +
## Time-free: one seeded RNG lays out the obstacles + coins ahead, so a whole run replays
## BYTE-IDENTICALLY from a seed (FNV-1a checksum over quantized state). The scene (runner_view.gd)
## + GameManager wrap this; all rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const LANES := 3
const START_SPEED := 5.0
const MAX_SPEED := 14.0
const SPEED_RAMP := 0.0016          ## speed gained per unit distance
const HIT_Z := 3.0                  ## collision depth window
const JUMP_TICKS := 26
const SLIDE_TICKS := 24
const SPAWN_GAP := 26.0             ## base distance between obstacle rows
const DIST_CAP := 6000.0            ## a very long run == "survived" (bounds the probe)

# obstacle kinds: "block" (must not share the lane), "hurdle" (must be jumping), "duck" (must be sliding)
const KINDS := ["block", "hurdle", "duck"]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var distance := 0.0
var speed := START_SPEED
var lane := 1
var jump_t := 0
var slide_t := 0
var coins := 0
var obstacles: Array = []           ## {dist, lane, kind}
var pickups: Array = []             ## {dist, lane, got}
var _spawn_at := 0.0
var game_over := false
var survived := false
var crashed_on := ""
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	distance = 0.0
	speed = START_SPEED
	lane = 1
	jump_t = 0
	slide_t = 0
	coins = 0
	obstacles = []
	pickups = []
	_spawn_at = 40.0
	game_over = false
	survived = false
	crashed_on = ""
	log_lines = []
	_spawn_ahead()

func _spawn_ahead() -> void:
	# keep the track populated ~200 units ahead of the player
	while _spawn_at < distance + 200.0:
		_spawn_row(_spawn_at)
		_spawn_at += SPAWN_GAP - clampf(distance * 0.002, 0.0, 10.0)   # rows tighten with distance

func _spawn_row(at: float) -> void:
	# never block all lanes: obstacles cover at most LANES-1 lanes, leaving a safe path.
	var n_obst := 1 + (1 if rng.randf() < clampf(distance / 4000.0, 0.0, 0.55) else 0)
	var lanes_free := [0, 1, 2]
	for i in range(n_obst):
		if lanes_free.size() <= 1:
			break
		var li := rng.randi_range(0, lanes_free.size() - 1)
		var ln: int = int(lanes_free[li])
		lanes_free.remove_at(li)
		obstacles.append({"dist": at, "lane": ln, "kind": str(KINDS[rng.randi_range(0, KINDS.size() - 1)])})
	# a coin, often on a free lane just past the row
	if rng.randf() < 0.7 and lanes_free.size() > 0:
		var cl: int = int(lanes_free[rng.randi_range(0, lanes_free.size() - 1)])
		pickups.append({"dist": at + 6.0, "lane": cl, "got": false})

# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #

func move_lane(dir: int) -> void:
	if game_over:
		return
	lane = clampi(lane + dir, 0, LANES - 1)

func jump() -> void:
	if game_over or jump_t > 0 or slide_t > 0:
		return
	jump_t = JUMP_TICKS

func slide() -> void:
	if game_over or slide_t > 0 or jump_t > 0:
		return
	slide_t = SLIDE_TICKS

func is_jumping() -> bool:
	return jump_t > 0

func is_sliding() -> bool:
	return slide_t > 0

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

## input = {dir: -1/0/1 (lane change, edge), jump: bool, slide: bool}
func tick(input: Dictionary) -> void:
	if game_over:
		return
	if int(input.get("dir", 0)) != 0:
		move_lane(int(input.dir))
	if bool(input.get("jump", false)):
		jump()
	if bool(input.get("slide", false)):
		slide()
	if jump_t > 0:
		jump_t -= 1
	if slide_t > 0:
		slide_t -= 1
	distance += speed
	speed = minf(MAX_SPEED, speed + SPEED_RAMP * speed)
	_spawn_ahead()
	_check_hits()
	_cull()
	if distance >= DIST_CAP and not game_over:
		survived = true
		_finish("cap")

func _check_hits() -> void:
	for o in obstacles:
		if int(o.lane) != lane:
			continue
		if absf(float(o.dist) - distance) > HIT_Z:
			continue
		var kind := str(o.kind)
		var safe := false
		if kind == "hurdle":
			safe = is_jumping()
		elif kind == "duck":
			safe = is_sliding()
		else:
			safe = false                # a block always hits if you share its lane
		if not safe:
			crashed_on = kind
			_finish("crash")
			return
	for c in pickups:
		if bool(c.got):
			continue
		if int(c.lane) == lane and absf(float(c.dist) - distance) <= HIT_Z + 2.0:
			c.got = true
			coins += 1

func _cull() -> void:
	var keep_o: Array = []
	for o in obstacles:
		if float(o.dist) > distance - 20.0:
			keep_o.append(o)
	obstacles = keep_o
	var keep_p: Array = []
	for c in pickups:
		if float(c.dist) > distance - 20.0:
			keep_p.append(c)
	pickups = keep_p

func _finish(reason: String) -> void:
	game_over = true
	_log("Run over (%s): %.0fm, %d coins, score %d" % [reason, distance, coins, score()])

func score() -> int:
	return int(distance) + coins * 10

# --------------------------------------------------------------------------- #
# Deterministic dodge auto-seat (probe / demo)
# --------------------------------------------------------------------------- #

func _next_obstacle_in(l: int) -> Dictionary:
	var best := {}
	var bd := 1e20
	for o in obstacles:
		if int(o.lane) != l:
			continue
		var d := float(o.dist) - distance
		if d > -HIT_Z and d < bd:
			bd = d
			best = o
	return best

## The lane nearest to the current one with NO obstacle within a window of `rowdist`
## (there is always at least one clear lane — a row never blocks them all).
func _nearest_clear_lane(rowdist: float) -> int:
	var best := lane
	var bestcost := 999
	for l in range(LANES):
		var clear := true
		for o in obstacles:
			if int(o.lane) == l and absf(float(o.dist) - rowdist) < HIT_Z * 2.2:
				clear = false
				break
		if clear:
			var cost: int = absi(l - lane)
			if cost < bestcost:
				bestcost = cost
				best = l
	return best

## Choose an action that survives the nearest threat, and drift toward a coin when safe.
func ai_input() -> Dictionary:
	var inp := {"dir": 0, "jump": false, "slide": false}
	var threat := _next_obstacle_in(lane)
	if not threat.is_empty():
		var d := float(threat.dist) - distance
		if d < speed * 3.6 + HIT_Z:
			# prefer routing to a fully-clear lane (dodges blocks AND avoids needing a jump/slide)
			var safe := _nearest_clear_lane(float(threat.dist))
			if safe != lane and d > speed * 1.1:
				inp.dir = signi(safe - lane)
				return inp
			# already aligned / too close to switch → clear it by posture
			var kind := str(threat.kind)
			if kind == "hurdle":
				inp.jump = true
				return inp
			if kind == "duck":
				inp.slide = true
				return inp
			# a block with no time — last-resort lane hop toward safety
			if safe != lane:
				inp.dir = signi(safe - lane)
			return inp
	# no threat → drift toward the nearest coin in an adjacent lane, if that lane is clear
	for cand in [lane - 1, lane + 1]:
		if cand < 0 or cand >= LANES:
			continue
		for c in pickups:
			if int(c.lane) == cand and not bool(c.got) and (float(c.dist) - distance) < 40.0 and (float(c.dist) - distance) > 0.0:
				var blocker := _next_obstacle_in(cand)
				if blocker.is_empty() or (float(blocker.dist) - distance) > speed * 3.6:
					inp.dir = cand - lane
					return inp
	return inp

func auto_step() -> void:
	if game_over:
		return
	tick(ai_input())

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < 40000:
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
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func _q(v: float) -> int:
	return int(round(v))

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d|%d|%d|%s" % [_q(distance), _q(speed * 10.0), lane, jump_t, slide_t,
		coins, int(game_over), int(survived), crashed_on]
	for o in obstacles:
		s += "|O%d,%d,%s" % [_q(o.dist), int(o.lane), str(o.kind)]
	for c in pickups:
		s += "|C%d,%d,%d" % [_q(c.dist), int(c.lane), int(c.got)]
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {"version": 1, "distance": distance, "speed": speed, "lane": lane, "jump_t": jump_t,
		"slide_t": slide_t, "coins": coins, "obstacles": obstacles.duplicate(true),
		"pickups": pickups.duplicate(true), "spawn_at": _spawn_at, "game_over": game_over,
		"survived": survived, "crashed_on": crashed_on, "seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	distance = float(d.get("distance", 0.0))
	speed = float(d.get("speed", START_SPEED))
	lane = int(d.get("lane", 1))
	jump_t = int(d.get("jump_t", 0))
	slide_t = int(d.get("slide_t", 0))
	coins = int(d.get("coins", 0))
	obstacles = (d.get("obstacles", []) as Array).duplicate(true)
	pickups = (d.get("pickups", []) as Array).duplicate(true)
	_spawn_at = float(d.get("spawn_at", 0.0))
	game_over = bool(d.get("game_over", false))
	survived = bool(d.get("survived", false))
	crashed_on = str(d.get("crashed_on", ""))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
