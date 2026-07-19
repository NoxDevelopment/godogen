extends RefCounted
class_name TopEngine
## res://scripts/top_engine.gd
## The PURE, seedable, headless-testable engine for a BEYBLADE-lineage SPINNING-TOP
## ARENA BATTLER: build a top from PARTS (an attack ring + a weight disk + a tip),
## launch it into a circular STADIUM, and collide to drain the opponent's STAMINA
## (spin-finish), knock it out of the RING (ring-out), or BURST it in one big hit —
## across a best-of match and a TOURNAMENT ladder of AI opponents. There is NO
## Godot-node dependency and NO RigidBody2D in here: the top-vs-top physics is our
## OWN fixed-timestep circle sim, so a whole battle (and the whole tournament)
## replays BYTE-IDENTICALLY from a seed and drives headlessly with no UI at all.
##
## WHY CUSTOM PHYSICS (the key design decision):
##   Godot's RigidBody2D solver is NOT guaranteed identical across runs/builds,
##   which would break byte-identical replays + probes. So a top is just a circle
##   (position, velocity, plus WEIGHT and SPIN which encodes STAMINA + a spin
##   DIRECTION) advanced at a FIXED dt inside a circular bowl. Motion is a pure
##   deterministic sum of a BOWL slope (a centre spring), passive FRICTION, an
##   aggression WANDER (a deterministic sine of the top's age, NOT an RNG), and a
##   SEEK toward the nearest opponent. Collisions are pure circle-circle geometry:
##   overlap -> weighted elastic momentum transfer along the contact normal + an
##   attack KNOCKBACK + a STAMINA drain scaled by attacker.attack vs defender.defense
##   and the same-spin/opposite-spin interaction. Given (part builds, launches,
##   seed) the trajectories, stamina curves, and result are 100% reproducible; the
##   ONLY randomness in the engine (tournament ladder, AI launch jitter) comes from
##   ONE seeded RNG whose state is part of save/load — the physics has ZERO
##   randomness. A MAX_STEPS cap bounds every battle -> a stamina tiebreak, never
##   an infinite spin.
##
## Layers:
##   * Parts    — PART_DB (>=14 parts) + build_top(): a combo -> EXACT derived
##                stats (attack, defense, stamina_max, weight, movement, friction).
##   * Physics  — simulate_battle(): the pure circle sim -> {winner, reason, steps,
##                checksum, tops}. Deterministic, bounded by MAX_STEPS.
##   * Match    — best-of points: spin-finish=1, ring-out=2, burst=2, timeout=1.
##   * Tournament — a ladder of AI opponents; win a match -> advance + unlock a
##                part; lose -> eliminated; beat the last rung -> WIN.
##   * Auto-play — auto_take_turn(): a deterministic heuristic that picks a counter
##                build + aims + launches, driving a whole tournament to WIN / LOSS.

# =====================================================================
#  Arena + physics tuning (auditable constants — swap for your own game)
# =====================================================================

const DT: float = 1.0 / 60.0        ## fixed physics timestep (seconds).
const ARENA_R: float = 240.0        ## ring-out radius — past this = RING-OUT.
const TOP_R: float = 15.0           ## a top's collision radius.
const START_OFFSET: float = 150.0   ## launch distance from centre (opposite sides).
const BASE_STAMINA: float = 100.0   ## every build's base spin stamina.

const BOWL_SLOPE_EDGE: float = 135.0  ## centre-spring accel (u/s^2) felt at the edge.
const FRICTION_BASE: float = 0.62     ## base velocity decay/s (scaled by a tip's friction).
const WANDER_ACCEL: float = 30.0      ## aggression wander accel (u/s^2), deterministic sine.
const SEEK_ACCEL: float = 66.0        ## aggression seek-the-opponent accel (u/s^2).

const PASSIVE_DRAIN: float = 2.10     ## stamina/s bled just by spinning (x a tip's drain).
const SPEED_DRAIN: float = 0.010      ## extra stamina/s per unit speed (x a tip's drain).
const CLOSE_CAP: float = 220.0        ## closing speed is capped here before it feeds a hit.
const DRAIN_ON_HIT: float = 0.30      ## collision stamina-drain scale.
const RESTITUTION: float = 0.55       ## normal velocity kept after a collision.
const KNOCKBACK: float = 10.5         ## attack-driven outward kick scale (can cause ring-outs).
const BURST_FRACTION: float = 0.42    ## a single hit >= this fraction of stamina_max BURSTS.

const SPIN_SAME: float = 0.72         ## same-spin collision drain factor (more knockback).
const SPIN_OPP: float = 1.42          ## opposite-spin drain factor (spin-steal, less knockback).
const SPIN_KNOCK_SAME: float = 1.30   ## same-spin knockback multiplier.
const SPIN_KNOCK_OPP: float = 0.70    ## opposite-spin knockback multiplier.

const LAUNCH_MIN: float = 70.0        ## launch speed at power 0.
const LAUNCH_RANGE: float = 150.0     ## added launch speed at power 1.
const AI_AIM_JITTER: float = 0.22     ## AI aim spread (rad) drawn from the seeded RNG.

const MAX_STEPS: int = 3600           ## hard cap (60 s) -> stamina tiebreak, never infinite.

## FNV-1a folding constants (63-bit masked) for deterministic checksums.
const FNV_OFFSET: int = 1469598103934665603
const FNV_PRIME: int = 1099511628211
const MASK63: int = 0x7FFFFFFFFFFFFFFF

# =====================================================================
#  PART DATABASE (>=14 parts: 6 attack rings, 4 weight disks, 4 tips)
#  Each part contributes ADDITIVE integers to the derived stats, so a build's
#  stats are exact + auditable. Movement fields (agg/friction/drain/grip) are
#  floats. Swap this table for your own parts.
# =====================================================================

## Attack rings (>=6) — the top's outer layer: attack, some defense, stamina,
## weight, and an aggression bias (how much it wanders/seeks).
const ATTACK_RINGS: Dictionary = {
	"ring_storm":   {"name": "Storm Ring",   "atk": 34, "def": 10, "sta": 8,  "wt": 6,  "agg": 0.90, "desc": "Aggressive — huge attack, thin defense, erratic."},
	"ring_edge":    {"name": "Edge Ring",    "atk": 24, "def": 18, "sta": 14, "wt": 8,  "agg": 0.50, "desc": "Balanced all-rounder."},
	"ring_bastion": {"name": "Bastion Ring", "atk": 12, "def": 34, "sta": 6,  "wt": 12, "agg": 0.20, "desc": "Defensive wall — soaks hits, but a short spin."},
	"ring_fang":    {"name": "Fang Ring",    "atk": 40, "def": 6,  "sta": 6,  "wt": 5,  "agg": 1.00, "desc": "Glass cannon — top attack, no bulk."},
	"ring_orbit":   {"name": "Orbit Ring",   "atk": 18, "def": 16, "sta": 28, "wt": 9,  "agg": 0.35, "desc": "Stamina type — outlasts the field."},
	"ring_wave":    {"name": "Wave Ring",    "atk": 22, "def": 22, "sta": 16, "wt": 10, "agg": 0.55, "desc": "Counter — even attack + defense."},
}

## Weight disks (>=4) — the mid layer: weight, stamina, defense, and a small
## aggression trim (heavier = steadier).
const WEIGHT_DISKS: Dictionary = {
	"disk_light":   {"name": "Light Disk",   "wt": 6,  "sta": 16, "def": 2,  "agg": 0.15,  "desc": "Light frame — long spin, but easily launched."},
	"disk_medium":  {"name": "Medium Disk",  "wt": 12, "sta": 8,  "def": 6,  "agg": 0.00,  "desc": "Neutral ballast."},
	"disk_heavy":   {"name": "Heavy Disk",   "wt": 20, "sta": 2,  "def": 12, "agg": -0.10, "desc": "Heavy — steady + hard to move, but short spin."},
	"disk_ballast": {"name": "Ballast Disk", "wt": 28, "sta": -6, "def": 16, "agg": -0.20, "desc": "Max weight — a fortress that bleeds stamina fast."},
}

## Tips (>=4) — the contact point: movement style, friction (stamina bleed),
## drain multiplier, ring-out GRIP resistance, plus small stat trims.
const TIPS: Dictionary = {
	"tip_flat":   {"name": "Flat Tip",   "atk": 6, "def": 0,  "sta": 0,  "wt": 3, "agg": 0.50,  "friction": 1.40, "drain": 1.30, "grip": 0.55, "desc": "Aggressive & erratic — fast, drains fast, easy to ring-out."},
	"tip_ball":   {"name": "Ball Tip",   "atk": 0, "def": 6,  "sta": 4,  "wt": 8, "agg": -0.20, "friction": 0.70, "drain": 0.95, "grip": 1.35, "desc": "Defense — very hard to ring-out, but only a middling spin."},
	"tip_needle": {"name": "Needle Tip", "atk": 2, "def": 0,  "sta": 12, "wt": 4, "agg": 0.10,  "friction": 0.72, "drain": 0.64, "grip": 0.90, "desc": "Stamina — the longest spin, tight orbit, easy to ring-out."},
	"tip_spike":  {"name": "Spike Tip",  "atk": 8, "def": -2, "sta": 0,  "wt": 5, "agg": 0.35,  "friction": 1.10, "drain": 1.10, "grip": 0.80, "desc": "Attack — bites hard, trades stamina."},
}

## The parts a fresh account owns. Two premium parts (ring_fang, disk_ballast) are
## LOCKED and unlocked by winning tournament rungs — enough remains to build.
const START_PARTS: Array = [
	"ring_storm", "ring_edge", "ring_bastion", "ring_orbit", "ring_wave",
	"disk_light", "disk_medium", "disk_heavy",
	"tip_flat", "tip_ball", "tip_needle", "tip_spike",
]

## Parts handed out (in order) as rung-win rewards.
const UNLOCK_REWARDS: Array = ["ring_fang", "disk_ballast"]

# =====================================================================
#  Tournament ladder — AI opponents, increasing difficulty
# =====================================================================

const POINTS_TO_WIN: int = 4          ## first to 4 points takes the match.

## Each rung: an AI build + a flat stat bonus that ramps the difficulty. `spin`
## is the AI's spin direction (+1 / -1). Swap for your own gauntlet.
const LADDER: Array = [
	{"name": "Rookie Gyro",  "ring": "ring_edge",    "disk": "disk_light",  "tip": "tip_needle", "spin": 1,  "bonus": 0},
	{"name": "Iron Waltz",   "ring": "ring_bastion", "disk": "disk_heavy",  "tip": "tip_ball",   "spin": -1, "bonus": 2},
	{"name": "Cyclone Fang", "ring": "ring_storm",   "disk": "disk_medium", "tip": "tip_flat",   "spin": 1,  "bonus": 4},
	{"name": "Wave Breaker", "ring": "ring_wave",    "disk": "disk_heavy",  "tip": "tip_spike",  "spin": -1, "bonus": 6},
	{"name": "Grand Vortex", "ring": "ring_storm",   "disk": "disk_ballast", "tip": "tip_spike", "spin": 1,  "bonus": 9},
]

# =====================================================================
#  Live tournament / match state
# =====================================================================

var phase: String = "build"          ## build | match | done.
var rung: int = 0                     ## current ladder index.
var owned_parts: Array = []           ## part ids the player owns.

var player_build: Dictionary = {}     ## the player's current top build (ids + spin).
var player_points: int = 0
var ai_points: int = 0
var round_no: int = 0

var last_result: Dictionary = {}      ## the most recent battle's result (for the HUD).
var last_tops: Array = []             ## the most recent battle's final top snapshots.
var last_trace: Array = []            ## sampled trajectory of the last battle (render).
var last_result_checksum: int = 0     ## persisted checksum of the last battle (survives save/load).

var tournament_over: bool = false
var tournament_won: bool = false

var illegal_attempts: int = 0
var log_lines: Array = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = 0
var _ai_stat_bonus: int = 0           ## extra difficulty added to every AI (config).
var _record: bool = true              ## sample the trajectory of the next battle.


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh tournament run. seed_value == 0 -> random; any other value
## replays byte-identically. `config` overrides difficulty:
##   ai_stat_bonus:int (added to every AI's attack+defense+stamina+weight),
##   start_parts:Array[String].
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	_seed = seed_value
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value
	_ai_stat_bonus = int(config.get("ai_stat_bonus", 0))
	owned_parts = []
	for pid in config.get("start_parts", START_PARTS):
		if _is_part(String(pid)) and not owned_parts.has(String(pid)):
			owned_parts.append(String(pid))
	rung = 0
	player_points = 0
	ai_points = 0
	round_no = 0
	player_build = {}
	last_result = {}
	last_tops = []
	last_trace = []
	last_result_checksum = 0
	tournament_over = false
	tournament_won = false
	illegal_attempts = 0
	log_lines = []
	# A sensible default build so the player can launch immediately.
	select_build("ring_edge", "disk_medium", "tip_needle", 1)
	phase = "build"
	_log("Tournament start — seed %d. Rung 1: %s." % [_seed, String(LADDER[0]["name"])])


# =====================================================================
#  Parts + building
# =====================================================================

func _is_ring(pid: String) -> bool:
	return ATTACK_RINGS.has(pid)

func _is_disk(pid: String) -> bool:
	return WEIGHT_DISKS.has(pid)

func _is_tip(pid: String) -> bool:
	return TIPS.has(pid)

func _is_part(pid: String) -> bool:
	return _is_ring(pid) or _is_disk(pid) or _is_tip(pid)


## Is (ring, disk, tip) a valid, OWNED combo? (one of each kind, all owned).
func is_valid_combo(ring: String, disk: String, tip: String) -> bool:
	if not (_is_ring(ring) and _is_disk(disk) and _is_tip(tip)):
		return false
	return owned_parts.has(ring) and owned_parts.has(disk) and owned_parts.has(tip)


## Derive the EXACT stats of a (ring, disk, tip, spin) build. Pure — no state.
## Returns {ring,disk,tip,spin, name, attack,defense,stamina_max,weight,
## aggression,friction,drain_mult,grip}.
func build_top(ring: String, disk: String, tip: String, spin: int, label: String = "") -> Dictionary:
	var r: Dictionary = ATTACK_RINGS[ring]
	var d: Dictionary = WEIGHT_DISKS[disk]
	var t: Dictionary = TIPS[tip]
	var attack: int = int(r["atk"]) + int(t["atk"])
	var defense: int = int(r["def"]) + int(d["def"]) + int(t["def"])
	var stamina_max: float = BASE_STAMINA + float(int(r["sta"]) + int(d["sta"]) + int(t["sta"]))
	var weight: int = int(r["wt"]) + int(d["wt"]) + int(t["wt"])
	var aggression: float = maxf(0.0, float(r["agg"]) + float(d["agg"]) + float(t["agg"]))
	return {
		"ring": ring, "disk": disk, "tip": tip, "spin": (1 if spin >= 0 else -1),
		"name": label if label != "" else "%s / %s / %s" % [String(r["name"]), String(d["name"]), String(t["name"])],
		"attack": attack,
		"defense": defense,
		"stamina_max": stamina_max,
		"weight": weight,
		"aggression": aggression,
		"friction": float(t["friction"]),
		"drain_mult": float(t["drain"]),
		"grip": float(t["grip"]),
	}


## Select the player's build for the current match. Rejects an illegal/unowned
## combo. spin is +1 (right) or -1 (left).
func select_build(ring: String, disk: String, tip: String, spin: int = 1) -> bool:
	if not is_legal({"type": "build", "ring": ring, "disk": disk, "tip": tip}):
		illegal_attempts += 1
		return false
	player_build = build_top(ring, disk, tip, spin, "Player")
	return true


## The AI opponent's build for the current rung, plus the difficulty bonus.
func _ai_build_for_rung(r: int) -> Dictionary:
	var spec: Dictionary = LADDER[r]
	var b := build_top(String(spec["ring"]), String(spec["disk"]), String(spec["tip"]),
		int(spec["spin"]), String(spec["name"]))
	var bonus: int = int(spec["bonus"]) + _ai_stat_bonus
	b["attack"] = int(b["attack"]) + bonus
	b["defense"] = int(b["defense"]) + bonus
	b["stamina_max"] = float(b["stamina_max"]) + float(bonus) * 2.0
	b["weight"] = int(b["weight"]) + bonus
	return b


# =====================================================================
#  Deterministic battle physics — the pure circle sim
# =====================================================================

## The stamina an `attacker` build drains from a `defender` build in ONE hit at a
## given `closing` speed — the exact formula the collision solver uses. Pure; used
## by the UI (matchup preview) and the parts/stats probe. High attack vs low
## defense (and opposite spin) drains far more.
func preview_hit_drain(attacker: Dictionary, defender: Dictionary, closing: float) -> float:
	var opposite: bool = int(attacker.get("spin", 1)) != int(defender.get("spin", 1))
	var drain_factor: float = SPIN_OPP if opposite else SPIN_SAME
	var impact: float = 6.0 + 0.06 * clampf(closing, 0.0, CLOSE_CAP)
	var wr: float = sqrt(float(attacker["weight"]) / float(defender["weight"]))
	return impact * (float(attacker["attack"]) / float(defender["defense"])) * wr * drain_factor * DRAIN_ON_HIT


## Make a fresh runtime top state from a build + a launch (power 0..1, aim rad)
## on a given side. side -1 = left start, +1 = right start.
func _spawn_top(build: Dictionary, owner: String, side: int, power: float, aim: float) -> Dictionary:
	var speed: float = LAUNCH_MIN + clampf(power, 0.0, 1.0) * LAUNCH_RANGE
	# start on the given side, on the x axis
	var start := Vector2(float(side) * START_OFFSET, 0.0)
	var vel := Vector2(cos(aim), sin(aim)) * speed
	return {
		"id": owner,
		"owner": owner,
		"name": String(build["name"]),
		"attack": float(int(build["attack"])),
		"defense": maxf(1.0, float(int(build["defense"]))),
		"stamina_max": float(build["stamina_max"]),
		"weight": maxf(1.0, float(int(build["weight"]))),
		"aggression": float(build["aggression"]),
		"friction": float(build["friction"]),
		"drain_mult": float(build["drain_mult"]),
		"grip": maxf(0.2, float(build["grip"])),
		"spin": int(build["spin"]),
		"px": start.x,
		"py": start.y,
		"vx": vel.x,
		"vy": vel.y,
		"stamina": float(build["stamina_max"]),
		"alive": true,
		"out_reason": "",
		"age": 0,
		"big_hit": 0.0,
	}


## Simulate a full battle between two builds + their launches. PURE + deterministic:
## given the builds, launches, and the CURRENT rng state (only used for AI aim
## jitter which is drawn BEFORE this call) the whole battle is byte-identical.
## Returns {winner, reason, steps, checksum, tops:[snapshot], collisions, trace}.
func simulate_battle(a_build: Dictionary, a_power: float, a_aim: float,
		b_build: Dictionary, b_power: float, b_aim: float, record: bool) -> Dictionary:
	var tops: Array = [
		_spawn_top(a_build, "player", -1, a_power, a_aim),
		_spawn_top(b_build, "ai", 1, b_power, b_aim),
	]
	var checksum: int = FNV_OFFSET
	var collisions: int = 0
	var steps: int = 0
	var trace: Array = []
	var winner: String = ""
	var reason: String = ""
	while steps < MAX_STEPS:
		steps += 1
		_step_motion(tops)
		collisions += _resolve_collisions(tops)
		_apply_drain_and_bounds(tops)
		# fold positions + stamina into the checksum (quantized -> stable).
		for tp in tops:
			checksum = _fold(checksum, int(round(float(tp["px"]) * 100.0)))
			checksum = _fold(checksum, int(round(float(tp["py"]) * 100.0)))
			checksum = _fold(checksum, int(round(float(tp["stamina"]) * 100.0)))
		if record and (steps % 3 == 0):
			var frame: Array = []
			for tp in tops:
				frame.append([float(tp["px"]), float(tp["py"]), float(tp["stamina"]),
					float(tp["stamina_max"]), bool(tp["alive"])])
			trace.append(frame)
		# end conditions
		var alive_ids: Array = []
		for tp in tops:
			if bool(tp["alive"]):
				alive_ids.append(String(tp["id"]))
		if alive_ids.size() <= 1:
			if alive_ids.size() == 1:
				winner = String(alive_ids[0])
				var loser: Dictionary = _other(tops, winner)
				reason = String(loser["out_reason"])
			else:
				# both out on the same tick -> higher final stamina wins (tiebreak).
				winner = _higher_stamina(tops)
				reason = "double"
			break
	if winner == "":
		# hit the cap with >1 alive -> stamina tiebreak (never an infinite battle).
		winner = _higher_stamina(tops)
		reason = "timeout"
	checksum = _fold(checksum, collisions)
	checksum = _fold(checksum, hash(winner))
	checksum = _fold(checksum, hash(reason))
	var snap: Array = []
	for tp in tops:
		snap.append({
			"id": String(tp["id"]), "name": String(tp["name"]),
			"stamina": float(tp["stamina"]), "stamina_max": float(tp["stamina_max"]),
			"alive": bool(tp["alive"]), "out_reason": String(tp["out_reason"]),
			"px": float(tp["px"]), "py": float(tp["py"]),
		})
	return {
		"winner": winner, "reason": reason, "steps": steps,
		"checksum": checksum, "tops": snap, "collisions": collisions, "trace": trace,
	}


## One motion sub-step: bowl slope + friction + aggression wander + seek, then
## integrate. Pure deterministic (the wander is a sine of age, NOT an RNG).
func _step_motion(tops: Array) -> void:
	var n: int = tops.size()
	for i in n:
		var tp: Dictionary = tops[i]
		if not bool(tp["alive"]):
			continue
		tp["age"] = int(tp["age"]) + 1
		var pos := Vector2(float(tp["px"]), float(tp["py"]))
		var vel := Vector2(float(tp["vx"]), float(tp["vy"]))
		var acc := Vector2.ZERO
		# 1) bowl slope: a centre spring, stronger farther out (keeps tops in).
		var dist: float = pos.length()
		if dist > 0.0001:
			acc += -pos / dist * (BOWL_SLOPE_EDGE * (dist / ARENA_R))
		# 2) aggression wander — deterministic sine of the top's age.
		var agg: float = float(tp["aggression"])
		if agg > 0.0:
			var ph: float = float(tp["age"]) * 0.11 + float(i) * 2.3
			acc += Vector2(cos(ph * 1.7), sin(ph)) * (WANDER_ACCEL * agg)
			# 3) seek the nearest opponent.
			var foe: Dictionary = _nearest_foe(tops, i)
			if not foe.is_empty():
				var to := Vector2(float(foe["px"]), float(foe["py"])) - pos
				if to.length() > 0.0001:
					acc += to.normalized() * (SEEK_ACCEL * agg)
		# 4) friction (velocity decay scaled by the tip).
		var fr: float = FRICTION_BASE * float(tp["friction"])
		vel *= maxf(0.0, 1.0 - fr * DT)
		# integrate
		vel += acc * DT
		pos += vel * DT
		tp["px"] = pos.x
		tp["py"] = pos.y
		tp["vx"] = vel.x
		tp["vy"] = vel.y


## Resolve every circle-circle collision this step. Returns the number of NEW
## contacts. Weighted elastic momentum transfer + attack knockback + stamina drain
## (attacker.attack vs defender.defense, scaled by the same/opposite-spin factor),
## with a BURST when one hit drains too much at once.
func _resolve_collisions(tops: Array) -> int:
	var hits: int = 0
	var n: int = tops.size()
	for i in n:
		for j in range(i + 1, n):
			var a: Dictionary = tops[i]
			var b: Dictionary = tops[j]
			if not (bool(a["alive"]) and bool(b["alive"])):
				continue
			var pa := Vector2(float(a["px"]), float(a["py"]))
			var pb := Vector2(float(b["px"]), float(b["py"]))
			var delta := pa - pb
			var d: float = delta.length()
			var min_d: float = TOP_R * 2.0
			if d >= min_d:
				continue
			hits += 1
			var nrm: Vector2 = (delta / d) if d > 0.0001 else Vector2(1.0, 0.0)
			var va := Vector2(float(a["vx"]), float(a["vy"]))
			var vb := Vector2(float(b["vx"]), float(b["vy"]))
			var ma: float = float(a["weight"])
			var mb: float = float(b["weight"])
			# closing speed along the normal (>0 == approaching), capped so a hot
			# first clash can't explode the whole battle in one tick.
			var v1n: float = va.dot(nrm)
			var v2n: float = vb.dot(nrm)
			var closing: float = clampf(v2n - v1n, 0.0, CLOSE_CAP)  # b moving into a
			# weighted elastic exchange along the normal (tangential kept).
			var new_v1n: float = (v1n * (ma - mb) + 2.0 * mb * v2n) / (ma + mb)
			var new_v2n: float = (v2n * (mb - ma) + 2.0 * ma * v1n) / (ma + mb)
			va += nrm * ((new_v1n - v1n) * RESTITUTION)
			vb += nrm * ((new_v2n - v2n) * RESTITUTION)
			# spin interaction.
			var opposite: bool = int(a["spin"]) != int(b["spin"])
			var drain_factor: float = SPIN_OPP if opposite else SPIN_SAME
			var knock_factor: float = SPIN_KNOCK_OPP if opposite else SPIN_KNOCK_SAME
			var impact: float = 6.0 + 0.06 * closing  # a floor so grazes still bite.
			# stamina drain: each side hurts the other per attack/defense ratio,
			# scaled by the sqrt of the weight advantage (heavier presses harder).
			var wr_ab: float = sqrt(ma / mb)
			var wr_ba: float = sqrt(mb / ma)
			var drain_to_b: float = impact * (float(a["attack"]) / float(b["defense"])) * wr_ab * drain_factor * DRAIN_ON_HIT
			var drain_to_a: float = impact * (float(b["attack"]) / float(a["defense"])) * wr_ba * drain_factor * DRAIN_ON_HIT
			b["stamina"] = float(b["stamina"]) - drain_to_b
			a["stamina"] = float(a["stamina"]) - drain_to_a
			b["big_hit"] = maxf(float(b["big_hit"]), drain_to_b)
			a["big_hit"] = maxf(float(a["big_hit"]), drain_to_a)
			# attack knockback (outward along the normal), softened by weight+grip;
			# a hard smash from a high-attack top can eject a light one (ring-out).
			var kb: float = 0.4 + 0.004 * closing
			var kick_b: float = kb * float(a["attack"]) / (sqrt(float(b["weight"])) * float(b["grip"])) * KNOCKBACK * knock_factor
			var kick_a: float = kb * float(b["attack"]) / (sqrt(float(a["weight"])) * float(a["grip"])) * KNOCKBACK * knock_factor
			vb -= nrm * kick_b
			va += nrm * kick_a
			# push the pair apart so they don't stick (inverse-weight split).
			var overlap: float = min_d - d
			var total_m: float = ma + mb
			pa += nrm * (overlap * (mb / total_m))
			pb -= nrm * (overlap * (ma / total_m))
			# BURST: one hit that drains too much at once knocks a top out instantly.
			if drain_to_b >= BURST_FRACTION * float(b["stamina_max"]):
				b["stamina"] = 0.0
				b["alive"] = false
				b["out_reason"] = "burst"
			if drain_to_a >= BURST_FRACTION * float(a["stamina_max"]):
				a["stamina"] = 0.0
				a["alive"] = false
				a["out_reason"] = "burst"
			a["px"] = pa.x
			a["py"] = pa.y
			a["vx"] = va.x
			a["vy"] = va.y
			b["px"] = pb.x
			b["py"] = pb.y
			b["vx"] = vb.x
			b["vy"] = vb.y
	return hits


## Passive stamina bleed + ring-out / spin-finish bounds check.
func _apply_drain_and_bounds(tops: Array) -> void:
	for tp in tops:
		if not bool(tp["alive"]):
			continue
		var speed: float = Vector2(float(tp["vx"]), float(tp["vy"])).length()
		var bleed: float = (PASSIVE_DRAIN + SPEED_DRAIN * speed) * float(tp["drain_mult"]) * DT
		tp["stamina"] = float(tp["stamina"]) - bleed
		# ring-out: knocked past the arena edge.
		var dist: float = Vector2(float(tp["px"]), float(tp["py"])).length()
		if dist + TOP_R > ARENA_R:
			tp["alive"] = false
			tp["out_reason"] = "ring"
		elif float(tp["stamina"]) <= 0.0:
			tp["stamina"] = 0.0
			tp["alive"] = false
			tp["out_reason"] = "spin"


func _nearest_foe(tops: Array, i: int) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = 1.0e20
	var pi := Vector2(float(tops[i]["px"]), float(tops[i]["py"]))
	for j in tops.size():
		if j == i or not bool(tops[j]["alive"]):
			continue
		var d: float = pi.distance_to(Vector2(float(tops[j]["px"]), float(tops[j]["py"])))
		if d < best_d:
			best_d = d
			best = tops[j]
	return best


func _other(tops: Array, id: String) -> Dictionary:
	for tp in tops:
		if String(tp["id"]) != id:
			return tp
	return tops[0]


func _higher_stamina(tops: Array) -> String:
	var best_id: String = String(tops[0]["id"])
	var best_s: float = float(tops[0]["stamina"])
	for k in range(1, tops.size()):
		if float(tops[k]["stamina"]) > best_s:
			best_s = float(tops[k]["stamina"])
			best_id = String(tops[k]["id"])
	return best_id


# =====================================================================
#  Match — the player launches a round; the AI answers; points are scored
# =====================================================================

## Points a win by `reason` is worth: spin-finish/timeout=1, ring-out/burst=2.
func points_for(reason: String) -> int:
	match reason:
		"ring", "burst":
			return 2
		"spin", "timeout", "double":
			return 1
	return 1


## Launch the player's selected build at (power 0..1, aim rad). The AI answers
## with its rung build + a heuristic launch (aim at the player + a seeded jitter),
## the battle is simulated deterministically, and the round is scored. Returns the
## battle result, or {} if illegal.
func launch(power: float, aim: float) -> Dictionary:
	if not is_legal({"type": "launch"}):
		illegal_attempts += 1
		return {}
	var ai_build := _ai_build_for_rung(rung)
	# AI heuristic: aim from its start (+x side) back toward the centre/player,
	# with a small seeded jitter; power scales with its rung.
	var ai_jitter: float = _rng.randf_range(-AI_AIM_JITTER, AI_AIM_JITTER)
	var ai_aim: float = PI + ai_jitter
	var ai_power: float = clampf(0.55 + 0.08 * float(rung), 0.0, 1.0)
	var res := simulate_battle(player_build, clampf(power, 0.0, 1.0), aim,
		ai_build, ai_power, ai_aim, _record)
	last_result = res
	last_tops = res["tops"]
	last_trace = res["trace"]
	last_result_checksum = int(res["checksum"])
	round_no += 1
	var pts := points_for(String(res["reason"]))
	if String(res["winner"]) == "player":
		player_points += pts
		_log("Round %d: WON by %s (+%d). %d–%d." % [round_no, _reason_label(String(res["reason"])), pts, player_points, ai_points])
	else:
		ai_points += pts
		_log("Round %d: lost by %s (AI +%d). %d–%d." % [round_no, _reason_label(String(res["reason"])), pts, player_points, ai_points])
	_check_match_over()
	return res


func _check_match_over() -> void:
	if player_points >= POINTS_TO_WIN:
		_win_match()
	elif ai_points >= POINTS_TO_WIN:
		_lose_match()


func _win_match() -> void:
	_log("MATCH WON vs %s (%d–%d)." % [String(LADDER[rung]["name"]), player_points, ai_points])
	# reward: unlock a part if any remain.
	var reward_idx: int = rung
	if reward_idx < UNLOCK_REWARDS.size():
		var pid := String(UNLOCK_REWARDS[reward_idx])
		if not owned_parts.has(pid):
			owned_parts.append(pid)
			_log("Unlocked part: %s." % _part_name(pid))
	if rung >= LADDER.size() - 1:
		tournament_over = true
		tournament_won = true
		phase = "done"
		_log("FINAL RUNG CLEARED — TOURNAMENT WON.")
		return
	rung += 1
	player_points = 0
	ai_points = 0
	round_no = 0
	phase = "build"
	_log("Advance to rung %d: %s." % [rung + 1, String(LADDER[rung]["name"])])


func _lose_match() -> void:
	tournament_over = true
	tournament_won = false
	phase = "done"
	_log("MATCH LOST vs %s (%d–%d) — ELIMINATED." % [String(LADDER[rung]["name"]), player_points, ai_points])


# =====================================================================
#  Legality
# =====================================================================

## Is `action` legal now? Rejects launching with no/invalid build, building an
## unowned combo, or acting after the tournament is over.
func is_legal(action: Dictionary) -> bool:
	if tournament_over:
		return false
	match String(action.get("type", "")):
		"build":
			return is_valid_combo(String(action.get("ring", "")),
				String(action.get("disk", "")), String(action.get("tip", "")))
		"launch":
			return phase in ["build", "match"] and not player_build.is_empty() \
				and is_valid_combo(String(player_build.get("ring", "")),
					String(player_build.get("disk", "")), String(player_build.get("tip", "")))
	return false


# =====================================================================
#  Auto-play heuristic (drives a whole tournament headlessly)
# =====================================================================

## Pick the OWNED build that scores best against the current AI rung, by a quick
## deterministic dry-simulation of a handful of candidate builds. Mutates nothing.
func best_counter_build() -> Dictionary:
	var ai_build := _ai_build_for_rung(rung)
	var rings: Array = []
	for pid in owned_parts:
		if _is_ring(pid):
			rings.append(pid)
	var disks: Array = []
	for pid in owned_parts:
		if _is_disk(pid):
			disks.append(pid)
	var tips: Array = []
	for pid in owned_parts:
		if _is_tip(pid):
			tips.append(pid)
	rings.sort()
	disks.sort()
	tips.sort()
	if disks.is_empty():
		disks = ["disk_medium"]
	var best: Dictionary = {}
	var best_margin: float = -1.0e20
	# Try each ring x disk x tip x spin at the SAME launch the auto-play will use
	# (power 0.92, aim 0.0) vs the AI's rung launch — a bounded, deterministic
	# search that actually predicts the round outcome.
	var ai_power: float = clampf(0.55 + 0.08 * float(rung), 0.0, 1.0)
	for r in rings:
		for dk in disks:
			for t in tips:
				for sp in [1, -1]:
					var cand := build_top(String(r), String(dk), String(t), sp)
					var res := simulate_battle(cand, 0.92, 0.0, ai_build, ai_power, PI, false)
					var margin: float = _margin_of(res)
					if margin > best_margin:
						best_margin = margin
						best = cand
	if best.is_empty():
		best = build_top("ring_edge", "disk_medium", "tip_needle", 1)
	return best


## A signed score for a battle result from the player's view: + if the player won
## (bigger for a stronger finish + surviving stamina), - if they lost.
func _margin_of(res: Dictionary) -> float:
	var sign_v: float = 1.0 if String(res["winner"]) == "player" else -1.0
	var pts: float = float(points_for(String(res["reason"])))
	var surv: float = 0.0
	for tp in res["tops"]:
		if String(tp["id"]) == "player":
			surv = float(tp["stamina"])
	return sign_v * (pts * 30.0 + surv)


## Take one deterministic auto-play step. In "build" it selects the best counter;
## in "match"/"build" with a build set it launches straight at the opponent.
func auto_take_turn() -> void:
	if tournament_over:
		return
	if phase == "build" or phase == "match":
		# Lock in a counter build for this rung once per rung.
		if phase == "build":
			var counter := best_counter_build()
			select_build(String(counter["ring"]), String(counter["disk"]),
				String(counter["tip"]), int(counter["spin"]))
			phase = "match"
		# aim from the player's start (-x side) toward the centre/opponent (0 rad),
		# high power.
		launch(0.92, 0.0)


# =====================================================================
#  Queries for the view
# =====================================================================

func part_name(pid: String) -> String:
	return _part_name(pid)

func _part_name(pid: String) -> String:
	if _is_ring(pid):
		return String(ATTACK_RINGS[pid]["name"])
	if _is_disk(pid):
		return String(WEIGHT_DISKS[pid]["name"])
	if _is_tip(pid):
		return String(TIPS[pid]["name"])
	return "?"


func part_desc(pid: String) -> String:
	if _is_ring(pid):
		return String(ATTACK_RINGS[pid]["desc"])
	if _is_disk(pid):
		return String(WEIGHT_DISKS[pid]["desc"])
	if _is_tip(pid):
		return String(TIPS[pid]["desc"])
	return ""


func owned_of_kind(kind: String) -> Array:
	var out: Array = []
	for pid in owned_parts:
		if (kind == "ring" and _is_ring(pid)) or (kind == "disk" and _is_disk(pid)) or (kind == "tip" and _is_tip(pid)):
			out.append(String(pid))
	out.sort()
	return out


func ai_rung_build() -> Dictionary:
	return _ai_build_for_rung(rung)


func rung_name() -> String:
	return String(LADDER[rung]["name"]) if rung < LADDER.size() else "?"


func _reason_label(reason: String) -> String:
	match reason:
		"ring": return "RING-OUT"
		"burst": return "BURST"
		"spin": return "spin-finish"
		"timeout": return "time-tiebreak"
		"double": return "double-out"
	return reason


func recent_log(n: int = 14) -> Array:
	var out: Array = []
	var start: int = maxi(0, log_lines.size() - n)
	for i in range(start, log_lines.size()):
		out.append(log_lines[i])
	return out


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 240:
		log_lines.remove_at(0)


func _fold(h: int, v: int) -> int:
	h = (h ^ v) * FNV_PRIME
	return h & MASK63


# =====================================================================
#  Determinism checksum — folds the WHOLE tournament state into one int
# =====================================================================

## Order-stable checksum of the entire run: two engines are equal iff this matches
## (used by the determinism + save/load probes).
func run_checksum() -> int:
	var h: int = FNV_OFFSET
	h = _fold(h, _seed)
	h = _fold(h, int(_rng.state & MASK63))
	h = _fold(h, hash(phase))
	h = _fold(h, rung)
	h = _fold(h, player_points)
	h = _fold(h, ai_points)
	h = _fold(h, round_no)
	h = _fold(h, _ai_stat_bonus)
	h = _fold(h, 1 if tournament_over else 0)
	h = _fold(h, 1 if tournament_won else 0)
	h = _fold(h, illegal_attempts)
	for pid in owned_parts:
		h = _fold(h, hash(String(pid)))
	if not player_build.is_empty():
		h = _fold(h, hash(String(player_build["ring"])))
		h = _fold(h, hash(String(player_build["disk"])))
		h = _fold(h, hash(String(player_build["tip"])))
		h = _fold(h, int(player_build["spin"]))
	h = _fold(h, last_result_checksum)
	return h


# =====================================================================
#  Save / load — the WHOLE run round-trips (JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	return {
		"seed": _seed,
		"rng_state": str(_rng.state),
		"ai_stat_bonus": _ai_stat_bonus,
		"phase": phase,
		"rung": rung,
		"owned_parts": owned_parts.duplicate(true),
		"player_build": player_build.duplicate(true),
		"player_points": player_points,
		"ai_points": ai_points,
		"round_no": round_no,
		"tournament_over": tournament_over,
		"tournament_won": tournament_won,
		"illegal_attempts": illegal_attempts,
		"last_result_checksum": last_result_checksum,
	}


func from_dict(data: Dictionary) -> void:
	_seed = int(data.get("seed", 0))
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	_ai_stat_bonus = int(data.get("ai_stat_bonus", 0))
	phase = String(data.get("phase", "build"))
	rung = int(data.get("rung", 0))
	owned_parts = []
	for pid in data.get("owned_parts", []):
		owned_parts.append(String(pid))
	player_build = (data.get("player_build", {}) as Dictionary).duplicate(true)
	player_points = int(data.get("player_points", 0))
	ai_points = int(data.get("ai_points", 0))
	round_no = int(data.get("round_no", 0))
	tournament_over = bool(data.get("tournament_over", false))
	tournament_won = bool(data.get("tournament_won", false))
	illegal_attempts = int(data.get("illegal_attempts", 0))
	last_result_checksum = int(data.get("last_result_checksum", 0))
	last_result = {}
	last_tops = []
	last_trace = []
