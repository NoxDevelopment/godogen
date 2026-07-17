class_name SportsEngine
extends RefCounted
## Pure, seedable ARCADE-SPORT engine (top-down arcade SOCCER lineage) run as a DETERMINISTIC
## FIXED-TIMESTEP sim at 60 ticks/sec: two teams of 3 chase one ball, gain possession, dribble,
## PASS and SHOOT at goal, with ball friction/bounces, goal detection, kickoffs, a match timer,
## and a full team AI. Node-free + Time-free: one seeded RNG only sets kickoff jitter + per-team
## aggression, and the sim is otherwise pure, so a whole match replays BYTE-IDENTICALLY from a
## seed (FNV-1a checksum over quantized positions). The scene (sports_view.gd) + GameManager wrap
## this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const FIELD := Vector2(620, 380)
const GOAL_HALF := 58.0             ## goal-mouth half-height
const MATCH_TICKS := 60 * 90        ## 90-second match
const PLAYER_R := 10.0
const BALL_R := 6.0
const PLAYER_SPEED := 2.6
const CONTROL_R := 15.0             ## grab radius
const TACKLE_R := 11.0              ## an opponent this close to a carried ball steals it
const TACKLE_SETTLE := 10           ## ticks a fresh possession is safe from a re-tackle
const DRIBBLE_AHEAD := 12.0
const KICK_PASS := 6.5
const KICK_SHOOT := 10.5
const BALL_FRICTION := 0.972
const KICK_COOLDOWN := 30           ## ticks before anyone can re-grab (a shot outruns defenders)
const SHOOT_RANGE := 175.0          ## x-distance to goal to attempt a shot
const CLOSE_RANGE := 100.0          ## always shoot inside this, even under pressure
const N_PER_TEAM := 3

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var players: Array = []             ## {id, team, pos, home, role}
var ball := {}                      ## {pos, vel, owner, cd}
var score := [0, 0]
var tick_no := 0
var game_over := false
var winner := -1
var team_aggr := [55, 55]
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	players = []
	score = [0, 0]
	tick_no = 0
	game_over = false
	winner = -1
	log_lines = []
	_next_id = 1
	team_aggr = [45 + rng.randi_range(0, 30), 45 + rng.randi_range(0, 30)]
	_spawn_teams()
	_kickoff(0)

func _spawn_teams() -> void:
	# roles across the field depth; team 0 attacks +x, team 1 attacks -x
	var roles := ["def", "mid", "fwd"]
	for i in range(N_PER_TEAM):
		var fx: float = FIELD.x * (0.22 + 0.22 * i)
		var fy: float = FIELD.y * (0.25 + 0.25 * (i % 3))
		players.append(_make_player(0, roles[i], Vector2(fx, fy)))
		players.append(_make_player(1, roles[i], Vector2(FIELD.x - fx, FIELD.y - fy)))

func _make_player(team: int, role: String, home: Vector2) -> Dictionary:
	return {"id": _new_id(), "team": team, "role": role, "pos": home, "home": home}

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

func _kickoff(to_team: int) -> void:
	for p in players:
		p.pos = Vector2(p.home)
	var jit := Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
	ball = {"pos": FIELD * 0.5 + jit, "vel": Vector2.ZERO, "owner": 0, "cd": 30}
	# hand the ball to the nearest player of the receiving team
	var best := _nearest_player_to(FIELD * 0.5, to_team)
	ball.owner = int(best.id) if not best.is_empty() else 0

# --------------------------------------------------------------------------- #
# Lookups
# --------------------------------------------------------------------------- #

func player_by_id(id: int) -> Dictionary:
	for p in players:
		if int(p.id) == id:
			return p
	return {}

func team_players(team: int) -> Array:
	var out: Array = []
	for p in players:
		if int(p.team) == team:
			out.append(p)
	return out

func _nearest_player_to(pos: Vector2, team: int) -> Dictionary:
	var best := {}
	var bd := 1e20
	for p in players:
		if team >= 0 and int(p.team) != team:
			continue
		var d: float = (p.pos as Vector2).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best

## The team's ball-chaser: the player nearest the ball (or the current owner if on this team).
func chaser(team: int) -> Dictionary:
	if int(ball.owner) != 0:
		var o := player_by_id(int(ball.owner))
		if not o.is_empty() and int(o.team) == team:
			return o
	return _nearest_player_to(ball.pos, team)

func attack_goal_x(team: int) -> float:
	return FIELD.x if team == 0 else 0.0

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

## input = {dir: Vector2 (-1..1), pass: bool, shoot: bool} — steers team 0's active player.
func tick(input: Dictionary) -> void:
	if game_over:
		return
	var active := chaser(0)
	# move every player: the active team-0 player follows input; everyone else is AI
	for p in players:
		if not active.is_empty() and int(p.id) == int(active.id) and not bool(input.get("_ai", false)):
			_move_human(p, input)
		else:
			_ai_move(p)
	_update_ball()
	tick_no += 1
	if tick_no >= MATCH_TICKS:
		_finish()

func _move_human(p: Dictionary, input: Dictionary) -> void:
	var dir: Vector2 = input.get("dir", Vector2.ZERO)
	if dir.length() > 1.0:
		dir = dir.normalized()
	p.pos = _clamp_field(p.pos + dir * PLAYER_SPEED)
	if int(ball.owner) == int(p.id):
		if bool(input.get("shoot", false)):
			_shoot(p)
		elif bool(input.get("pass", false)):
			_pass(p)

func _ai_move(p: Dictionary) -> void:
	var team: int = int(p.team)
	var ch := chaser(team)
	var is_chaser: bool = not ch.is_empty() and int(ch.id) == int(p.id)
	if int(ball.owner) == int(p.id):
		_ai_with_ball(p)
		return
	if is_chaser:
		_steer(p, ball.pos, PLAYER_SPEED)
		return
	# support: hold a formation position shifted toward the ball's x
	var target := Vector2(p.home)
	target.x = clampf(float(p.home.x) * 0.55 + float(ball.pos.x) * 0.45, PLAYER_R, FIELD.x - PLAYER_R)
	_steer(p, target, PLAYER_SPEED * 0.85)

func _ai_with_ball(p: Dictionary) -> void:
	var team: int = int(p.team)
	var gx := attack_goal_x(team)
	var goal := Vector2(gx, FIELD.y * 0.5)
	var dist_to_goal: float = absf(float(p.pos.x) - gx)
	# within shooting range → shoot; range widens with the team's seeded aggression so
	# different seeds play differently (aggressive teams shoot from farther out)
	var srange: float = SHOOT_RANGE * (0.72 + float(team_aggr[team]) / 120.0)
	if dist_to_goal < srange:
		_shoot(p)
		return
	# only a very tight mark forces a pass — otherwise keep dribbling toward goal
	var opp := _nearest_player_to(p.pos, 1 - team)
	var pressured: bool = not opp.is_empty() and (opp.pos as Vector2).distance_to(p.pos) < 18.0
	if pressured and _has_pass_option(p):
		_pass(p)
		return
	_steer(p, goal, PLAYER_SPEED)

func _steer(p: Dictionary, target: Vector2, speed: float) -> void:
	var to: Vector2 = target - p.pos
	if to.length() > 0.01:
		p.pos = _clamp_field(p.pos + to.normalized() * speed)

func _has_pass_option(p: Dictionary) -> bool:
	return not _best_pass_target(p).is_empty()

func _best_pass_target(p: Dictionary) -> Dictionary:
	var team: int = int(p.team)
	var gx := attack_goal_x(team)
	var best := {}
	var best_score := -1e20
	for m in team_players(team):
		if int(m.id) == int(p.id):
			continue
		# prefer teammates ahead (closer to the enemy goal) and not tightly marked
		var ahead: float = -absf(float(m.pos.x) - gx)
		var opp := _nearest_player_to(m.pos, 1 - team)
		var open: float = (opp.pos as Vector2).distance_to(m.pos) if not opp.is_empty() else 100.0
		var s := ahead + open * 1.5
		if s > best_score:
			best_score = s
			best = m
	return best

# --------------------------------------------------------------------------- #
# Ball + kicks
# --------------------------------------------------------------------------- #

func _update_ball() -> void:
	if int(ball.cd) > 0:
		ball.cd = int(ball.cd) - 1
	if int(ball.owner) != 0:
		var o := player_by_id(int(ball.owner))
		if o.is_empty():
			ball.owner = 0
		else:
			# TACKLE: an opponent within TACKLE_R of the ball steals it (after a settle window)
			if int(ball.cd) <= 0:
				var thief := _nearest_player_to(ball.pos, 1 - int(o.team))
				if not thief.is_empty() and (thief.pos as Vector2).distance_to(ball.pos) < TACKLE_R:
					ball.owner = int(thief.id)
					ball.cd = TACKLE_SETTLE
					o = thief
					_log("Tackle by team %d" % int(thief.team))
			# ball sits just ahead of the carrier toward their attacking goal
			var gx := attack_goal_x(int(o.team))
			var dir := Vector2(1 if gx > float(o.pos.x) else -1, 0)
			ball.pos = _clamp_field((o.pos as Vector2) + dir * DRIBBLE_AHEAD)
			ball.vel = Vector2.ZERO
			return
	# free ball: integrate + friction + wall bounce
	ball.pos = (ball.pos as Vector2) + ball.vel
	ball.vel = (ball.vel as Vector2) * BALL_FRICTION
	var bp: Vector2 = ball.pos
	if bp.y < BALL_R or bp.y > FIELD.y - BALL_R:
		ball.vel = Vector2(float(ball.vel.x), -float(ball.vel.y))
		bp.y = clampf(bp.y, BALL_R, FIELD.y - BALL_R)
		ball.pos = bp
	# goal-line checks. Team 0 attacks +x (right goal); team 1 attacks -x (left goal).
	if bp.x <= BALL_R:
		if absf(bp.y - FIELD.y * 0.5) <= GOAL_HALF:
			_goal(1)                          # ball in the LEFT goal → team 1 scores
			return
		ball.vel = Vector2(-float(ball.vel.x), float(ball.vel.y))
		bp.x = BALL_R
		ball.pos = bp
	elif bp.x >= FIELD.x - BALL_R:
		if absf(bp.y - FIELD.y * 0.5) <= GOAL_HALF:
			_goal(0)                          # ball in the RIGHT goal → team 0 scores
			return
		ball.vel = Vector2(-float(ball.vel.x), float(ball.vel.y))
		bp.x = FIELD.x - BALL_R
		ball.pos = bp
	# possession pickup
	if int(ball.cd) <= 0:
		var grabber := _nearest_player_to(ball.pos, -1)
		if not grabber.is_empty() and (grabber.pos as Vector2).distance_to(ball.pos) <= CONTROL_R:
			ball.owner = int(grabber.id)
			ball.vel = Vector2.ZERO

func _shoot(p: Dictionary) -> void:
	if int(ball.owner) != int(p.id):
		return
	var gx := attack_goal_x(int(p.team))
	# aim at the goal with a DISTANCE-SCALED spread: long-range shots are wilder (and miss the
	# mouth more often). Deterministic pseudo-spread from tick + player id.
	var dist: float = absf(float(p.pos.x) - gx)
	var spread: float = clampf(dist / 3.2, 6.0, GOAL_HALF * 1.7)
	var noise: float = float((int(p.id) * 37 + tick_no * 13) % 200 - 100) / 100.0     # -1..1
	var aim_y: float = clampf(FIELD.y * 0.5 + noise * spread, 6.0, FIELD.y - 6.0)
	var dir: Vector2 = (Vector2(gx, aim_y) - (p.pos as Vector2)).normalized()
	ball.vel = dir * KICK_SHOOT
	ball.owner = 0
	ball.cd = KICK_COOLDOWN

func _pass(p: Dictionary) -> void:
	if int(ball.owner) != int(p.id):
		return
	var tgt := _best_pass_target(p)
	if tgt.is_empty():
		_shoot(p)
		return
	var dir: Vector2 = ((tgt.pos as Vector2) - (p.pos as Vector2)).normalized()
	ball.vel = dir * KICK_PASS
	ball.owner = 0
	ball.cd = KICK_COOLDOWN

func _goal(scoring_team: int) -> void:
	score[scoring_team] = int(score[scoring_team]) + 1
	_log("GOAL! team %d (%d-%d)" % [scoring_team, int(score[0]), int(score[1])])
	_kickoff(1 - scoring_team)

func _clamp_field(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, PLAYER_R, FIELD.x - PLAYER_R), clampf(v.y, PLAYER_R, FIELD.y - PLAYER_R))

func _finish() -> void:
	game_over = true
	winner = 0 if int(score[0]) > int(score[1]) else (1 if int(score[1]) > int(score[0]) else -1)
	_log("Full time: %d-%d (%s)" % [int(score[0]), int(score[1]), ("draw" if winner < 0 else "team %d wins" % winner)])

# --------------------------------------------------------------------------- #
# Deterministic auto-play (probe / attract) — both teams AI
# --------------------------------------------------------------------------- #

func auto_step(_policy: String = "both") -> void:
	if game_over:
		return
	tick({"_ai": true})

func auto_play_to_end(policy: String = "both") -> void:
	var guard := 0
	while not game_over and guard < MATCH_TICKS + 4:
		auto_step(policy)
		guard += 1
	if not game_over:
		_finish()

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[%02d:%02d] %s" % [int(tick_no / 3600), int((tick_no / 60) % 60), s])
	if log_lines.size() > 40:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func _q(v: float) -> int:
	return int(round(v))

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d,%d|%d,%d,%d,%d" % [tick_no, int(game_over), winner, int(score[0]), int(score[1]),
		_q(ball.pos.x), _q(ball.pos.y), int(ball.owner), int(ball.cd)]
	for p in players:
		s += "|P%d,%d,%d,%d" % [int(p.id), int(p.team), _q(p.pos.x), _q(p.pos.y)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "score": score.duplicate(), "tick_no": tick_no, "game_over": game_over,
		"winner": winner, "team_aggr": team_aggr.duplicate(), "next_id": _next_id,
		"players": players.duplicate(true), "ball": ball.duplicate(true),
		"seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	score = (d.get("score", [0, 0]) as Array).duplicate()
	tick_no = int(d.get("tick_no", 0))
	game_over = bool(d.get("game_over", false))
	winner = int(d.get("winner", -1))
	team_aggr = (d.get("team_aggr", [55, 55]) as Array).duplicate()
	_next_id = int(d.get("next_id", 1))
	players = (d.get("players", []) as Array).duplicate(true)
	ball = (d.get("ball", {}) as Dictionary).duplicate(true)
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
