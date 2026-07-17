class_name ShooterEngine
extends RefCounted
## Pure, seedable TWIN-STICK SHOOTER engine (Enter the Gungeon / Nuclear Throne lineage) run
## as a DETERMINISTIC FIXED-TIMESTEP sim at 60 ticks/sec: the player MOVES with one stick and
## AIMS/FIRES with the other while waves of enemies spawn from the edges and close in. Two
## enemy archetypes beyond the chaser (a ranged shooter that fires bullets, a heavy brute),
## escalating waves, i-frames, score, and a survive-all-waves win. Node-free + Time-free: one
## private RNG seeds the spawns + enemy jitter and the sim is otherwise pure, so a whole run
## replays BYTE-IDENTICALLY from a seed (FNV-1a checksum) and drives headlessly. The scene
## (shooter_view.gd) + GameManager wrap this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const ARENA := Vector2(480, 320)
const FRAME_CAP := 60 * 60 * 8        ## hard safety bound (8 real minutes of ticks)
const MAX_WAVES := 6

const PLAYER_SPEED := 3.0
const PLAYER_HP := 100
const PLAYER_RADIUS := 8.0
const FIRE_CD := 8
const PLAYER_DMG := 6
const BULLET_SPEED := 7.0
const BULLET_LIFE := 84
const IFRAMES := 34

# enemy archetypes → {hp, speed, radius, contact, xp, shoot_cd, bshoot_speed, bdmg}
const ENEMY := {
	"chaser": {"hp": 12, "speed": 1.7, "radius": 9.0, "contact": 8, "xp": 10, "shoot_cd": 0, "bspeed": 0.0, "bdmg": 0},
	"shooter": {"hp": 10, "speed": 1.0, "radius": 9.0, "contact": 6, "xp": 14, "shoot_cd": 70, "bspeed": 4.2, "bdmg": 7},
	"brute": {"hp": 34, "speed": 1.25, "radius": 15.0, "contact": 16, "xp": 30, "shoot_cd": 0, "bspeed": 0.0, "bdmg": 0},
}

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var player := {}
var enemies: Array = []
var bullets: Array = []               ## {pos, vel, owner(0=player/1=enemy), dmg, life}
var wave := 0
var score := 0
var frame := 0
var game_over := false
var won := false
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	player = {
		"pos": ARENA * 0.5, "hp": PLAYER_HP, "max_hp": PLAYER_HP,
		"aim": Vector2(1, 0), "cd": 0, "iframe": 0,
	}
	enemies = []
	bullets = []
	wave = 0
	score = 0
	frame = 0
	game_over = false
	won = false
	log_lines = []
	_next_id = 1
	_start_wave()

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

# --------------------------------------------------------------------------- #
# Waves
# --------------------------------------------------------------------------- #

func _start_wave() -> void:
	wave += 1
	if wave > MAX_WAVES:
		_finish(true)
		return
	var count: int = 3 + wave * 2
	for i in range(count):
		enemies.append(_make_enemy(_wave_type(i)))
	_log("Wave %d — %d enemies!" % [wave, count])

func _wave_type(i: int) -> String:
	# escalate the roster: shooters from wave 2, brutes from wave 3, boss wave brute-heavy
	if wave >= MAX_WAVES:
		return "brute" if i % 2 == 0 else "shooter"
	if wave >= 3 and i % 4 == 0:
		return "brute"
	if wave >= 2 and i % 3 == 0:
		return "shooter"
	return "chaser"

func _make_enemy(kind: String) -> Dictionary:
	var d: Dictionary = ENEMY[kind]
	return {
		"id": _new_id(), "kind": kind, "pos": _edge_spawn(),
		"hp": int(d.hp), "max_hp": int(d.hp), "cd": rng.randi_range(0, 40),
	}

func _edge_spawn() -> Vector2:
	var side := rng.randi_range(0, 3)
	match side:
		0: return Vector2(rng.randf() * ARENA.x, -12)
		1: return Vector2(rng.randf() * ARENA.x, ARENA.y + 12)
		2: return Vector2(-12, rng.randf() * ARENA.y)
		_: return Vector2(ARENA.x + 12, rng.randf() * ARENA.y)

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

## input = {move: Vector2 (-1..1 each axis), aim: Vector2 (direction), fire: bool}
func tick(input: Dictionary) -> void:
	if game_over:
		return
	_tick_player(input)
	_tick_enemies()
	_tick_bullets()
	_contact_damage()
	_cull()
	if enemies.is_empty():
		_start_wave()
	if int(player.hp) <= 0:
		_finish(false)
	frame += 1

func _tick_player(input: Dictionary) -> void:
	var mv: Vector2 = input.get("move", Vector2.ZERO)
	if mv.length() > 1.0:
		mv = mv.normalized()
	player.pos = (player.pos + mv * PLAYER_SPEED).clamp(Vector2(PLAYER_RADIUS, PLAYER_RADIUS), ARENA - Vector2(PLAYER_RADIUS, PLAYER_RADIUS))
	var aim: Vector2 = input.get("aim", Vector2.ZERO)
	if aim.length() > 0.1:
		player.aim = aim.normalized()
	if int(player.cd) > 0:
		player.cd = int(player.cd) - 1
	if int(player.iframe) > 0:
		player.iframe = int(player.iframe) - 1
	if bool(input.get("fire", false)) and int(player.cd) <= 0:
		bullets.append({"pos": player.pos, "vel": player.aim * BULLET_SPEED, "owner": 0, "dmg": PLAYER_DMG, "life": BULLET_LIFE})
		player.cd = FIRE_CD

func _tick_enemies() -> void:
	var ppos: Vector2 = player.pos
	for e in enemies:
		var d: Dictionary = ENEMY[str(e.kind)]
		var to_player: Vector2 = ppos - e.pos
		var dist: float = to_player.length()
		var dir: Vector2 = to_player.normalized() if dist > 0.01 else Vector2.RIGHT
		if str(e.kind) == "shooter":
			# keep mid-range and shoot
			if dist < 130.0:
				e.pos = e.pos - dir * float(d.speed)
			elif dist > 190.0:
				e.pos = e.pos + dir * float(d.speed)
			e.cd = int(e.cd) - 1
			if int(e.cd) <= 0:
				bullets.append({"pos": e.pos, "vel": dir * float(d.bspeed), "owner": 1, "dmg": int(d.bdmg), "life": 150})
				e.cd = int(d.shoot_cd)
		else:
			e.pos = e.pos + dir * float(d.speed)
		e.pos = e.pos.clamp(Vector2(-16, -16), ARENA + Vector2(16, 16))

func _tick_bullets() -> void:
	for b in bullets:
		b.pos = b.pos + b.vel
		b.life = int(b.life) - 1

func _contact_damage() -> void:
	var ppos: Vector2 = player.pos
	for e in enemies:
		var d: Dictionary = ENEMY[str(e.kind)]
		if ppos.distance_to(e.pos) <= PLAYER_RADIUS + float(d.radius):
			_hurt_player(int(d.contact))

func _hurt_player(dmg: int) -> void:
	if int(player.iframe) > 0:
		return
	player.hp = int(player.hp) - dmg
	player.iframe = IFRAMES
	if int(player.hp) <= 0:
		player.hp = 0

func _cull() -> void:
	# bullet collisions + lifetime
	var keep_b: Array = []
	for b in bullets:
		var bp: Vector2 = b.pos
		var alive: bool = int(b.life) > 0 and bp.x > -20.0 and bp.x < ARENA.x + 20.0 and bp.y > -20.0 and bp.y < ARENA.y + 20.0
		if not alive:
			continue
		var consumed: bool = false
		if int(b.owner) == 0:
			for e in enemies:
				var d: Dictionary = ENEMY[str(e.kind)]
				if b.pos.distance_to(e.pos) <= float(d.radius) + 3.0:
					e.hp = int(e.hp) - int(b.dmg)
					consumed = true
					break
		else:
			if int(player.iframe) <= 0 and b.pos.distance_to(player.pos) <= PLAYER_RADIUS + 3.0:
				_hurt_player(int(b.dmg))
				consumed = true
		if not consumed:
			keep_b.append(b)
	bullets = keep_b
	# dead enemies → score
	var keep_e: Array = []
	for e in enemies:
		if int(e.hp) > 0:
			keep_e.append(e)
		else:
			score += int(ENEMY[str(e.kind)].xp)
	enemies = keep_e

func _finish(victory: bool) -> void:
	game_over = true
	won = victory
	_log("Run over: %s (score %d, wave %d)" % [("VICTORY" if victory else "you died"), score, wave])

# --------------------------------------------------------------------------- #
# Heuristic auto-play seat (probe / attract) — kite + fire at the nearest enemy
# --------------------------------------------------------------------------- #

func ai_input() -> Dictionary:
	var near := _nearest_enemy()
	if near.is_empty():
		return {"move": Vector2.ZERO, "aim": player.aim, "fire": false}
	var to_e: Vector2 = near.pos - player.pos
	var dist: float = to_e.length()
	var aim: Vector2 = to_e.normalized() if dist > 0.01 else player.aim
	var mv := Vector2.ZERO
	if dist < 90.0:
		mv = -aim                                   # kite away when crowded
	elif dist > 170.0:
		mv = aim                                    # close the gap
	else:
		mv = Vector2(-aim.y, aim.x)                 # strafe at a comfortable range
	# nudge away from the arena walls so we don't get cornered
	if player.pos.x < 40:
		mv.x += 0.6
	elif player.pos.x > ARENA.x - 40:
		mv.x -= 0.6
	if player.pos.y < 40:
		mv.y += 0.6
	elif player.pos.y > ARENA.y - 40:
		mv.y -= 0.6
	# dodge the closest incoming enemy bullet
	var bd := _closest_threat_bullet()
	if not bd.is_empty():
		var away: Vector2 = (player.pos - bd.pos)
		if away.length() < 60.0 and away.length() > 0.01:
			mv = (mv + Vector2(-aim.y, aim.x) * 1.4).normalized()
	return {"move": mv, "aim": aim, "fire": true}

func _nearest_enemy() -> Dictionary:
	var best := {}
	var bd := 1e20
	for e in enemies:
		var d: float = player.pos.distance_squared_to(e.pos)
		if d < bd:
			bd = d
			best = e
	return best

func _closest_threat_bullet() -> Dictionary:
	var best := {}
	var bd := 1e20
	for b in bullets:
		if int(b.owner) != 1:
			continue
		var d: float = player.pos.distance_squared_to(b.pos)
		if d < bd:
			bd = d
			best = b
	return best

func auto_step(_policy: String = "kite") -> void:
	if game_over:
		return
	tick(ai_input())

func auto_play_to_end(policy: String = "kite") -> void:
	var guard := 0
	while not game_over and guard < FRAME_CAP:
		auto_step(policy)
		guard += 1
	if not game_over:
		_finish(won)

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[w%d] %s" % [wave, s])
	if log_lines.size() > 40:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func _qx(v: float) -> int:
	return int(round(v))

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d,%d,%d" % [frame, wave, int(game_over), int(won), score,
		_qx(player.pos.x), _qx(player.pos.y), int(player.hp)]
	for e in enemies:
		s += "|E%d,%s,%d,%d,%d" % [int(e.id), str(e.kind), _qx(e.pos.x), _qx(e.pos.y), int(e.hp)]
	for b in bullets:
		s += "|B%d,%d,%d,%d" % [int(b.owner), _qx(b.pos.x), _qx(b.pos.y), int(b.life)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "frame": frame, "wave": wave, "score": score,
		"game_over": game_over, "won": won, "next_id": _next_id,
		"seed": int(rng.seed), "rng_state": int(rng.state),
		"player": player.duplicate(true), "enemies": enemies.duplicate(true),
		"bullets": bullets.duplicate(true),
	}

func load_data(d: Dictionary) -> void:
	frame = int(d.get("frame", 0))
	wave = int(d.get("wave", 0))
	score = int(d.get("score", 0))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	_next_id = int(d.get("next_id", 1))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	player = (d.get("player", {}) as Dictionary).duplicate(true)
	enemies = (d.get("enemies", []) as Array).duplicate(true)
	bullets = (d.get("bullets", []) as Array).duplicate(true)
