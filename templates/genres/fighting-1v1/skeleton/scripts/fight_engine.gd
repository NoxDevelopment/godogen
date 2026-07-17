class_name FightEngine
extends RefCounted
## Pure, seedable 1-v-1 FIGHTING-GAME engine (Street Fighter / Mortal Kombat lineage) run
## as a DETERMINISTIC FIXED-TIMESTEP sim at 60 ticks/sec with real FRAME DATA: every move
## has startup / active / recovery frames, hit/blockstun, range and a hit HEIGHT, so play
## is about frame advantage, spacing, blocking high/low, and combos — not ad-hoc timers.
## Node-free + Time-free: one private RNG seeds the AI personalities + a little starting
## jitter, and the sim is otherwise pure, so a whole best-of-3 replays BYTE-IDENTICALLY
## from a seed (FNV-1a checksum) and drives headlessly. The scene (fight_view.gd) +
## GameManager wrap this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const STAGE_W := 440
const FLOOR_Y := 0
const START_DIST := 150
const MAX_HP := 120
const ROUNDS_TO_WIN := 2
const ROUND_FRAMES := 3600            ## 60s at 60fps
const MATCH_FRAME_CAP := 60 * 60 * 6  ## hard safety bound (6 real minutes of ticks)

const WALK_SPEED := 3
const JUMP_VY := 16
const GRAVITY := 1
const CROUCH := "crouch"

# move → frame data. height: which block is required to defend (high/mid/low/air).
# cancelable: can be special-canceled during hit/active frames into another move.
const MOVES := {
	"LP": {"startup": 4, "active": 3, "recovery": 7, "dmg": 6, "hitstun": 14, "blockstun": 10, "range": 58, "height": "mid", "cancel": true, "push": 6, "proj": false},
	"HP": {"startup": 9, "active": 4, "recovery": 18, "dmg": 13, "hitstun": 20, "blockstun": 14, "range": 64, "height": "high", "cancel": false, "push": 10, "proj": false},
	"LK": {"startup": 6, "active": 3, "recovery": 10, "dmg": 7, "hitstun": 14, "blockstun": 10, "range": 72, "height": "low", "cancel": true, "push": 8, "proj": false},
	"HK": {"startup": 12, "active": 5, "recovery": 22, "dmg": 15, "hitstun": 22, "blockstun": 16, "range": 84, "height": "mid", "cancel": false, "push": 14, "proj": false},
	"SP": {"startup": 12, "active": 0, "recovery": 30, "dmg": 10, "hitstun": 24, "blockstun": 16, "range": 0, "height": "mid", "cancel": false, "push": 0, "proj": true},
}
const PROJ_SPEED := 5
const PROJ_W := 22

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var f := []                          ## two fighters [Dictionary, Dictionary]
var projectiles: Array = []          ## Array[Dictionary]
var round_no := 1
var wins := [0, 0]
var round_frame := 0
var frame := 0
var round_active := false
var game_over := false
var winner := -1
var round_winner := -1
var round_banner := 0                ## frames to hold a round-over banner before the next
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	round_no = 1
	wins = [0, 0]
	frame = 0
	game_over = false
	winner = -1
	log_lines = []
	# seeded AI personalities so different seeds play out differently (still deterministic)
	f = [_make_fighter(0), _make_fighter(1)]
	f[0]["aggr"] = 40 + rng.randi_range(0, 35)
	f[1]["aggr"] = 40 + rng.randi_range(0, 35)
	f[0]["react"] = 4 + rng.randi_range(0, 6)
	f[1]["react"] = 4 + rng.randi_range(0, 6)
	_start_round()

func _make_fighter(idx: int) -> Dictionary:
	return {
		"idx": idx, "x": 0, "y": 0, "vy": 0, "facing": 1,
		"hp": MAX_HP, "state": "idle", "move": "", "mframe": 0,
		"stun": 0, "block": false, "crouch": false, "airborne": false,
		"has_hit": false, "combo": 0, "aggr": 50, "react": 6,
	}

func _start_round() -> void:
	projectiles = []
	round_frame = 0
	round_active = true
	round_winner = -1
	round_banner = 0
	var mid := STAGE_W / 2
	var jit := rng.randi_range(-6, 6)
	_reset_fighter(f[0], mid - START_DIST / 2 + jit, 1)
	_reset_fighter(f[1], mid + START_DIST / 2 + jit, -1)
	_log("Round %d — fight!" % round_no)

func _reset_fighter(ft: Dictionary, x: int, facing: int) -> void:
	ft.x = x
	ft.y = 0
	ft.vy = 0
	ft.facing = facing
	ft.hp = MAX_HP
	ft.state = "idle"
	ft.move = ""
	ft.mframe = 0
	ft.stun = 0
	ft.block = false
	ft.crouch = false
	ft.airborne = false
	ft.has_hit = false
	ft.combo = 0

# --------------------------------------------------------------------------- #
# Input application (the actionable fighter interprets an input each tick)
# --------------------------------------------------------------------------- #

## An input is {dir:-1/0/1, up:bool, down:bool, atk:""|LP|HP|LK|HK|SP}. `dir` is world-space;
## holding away from the opponent = block. Applied only when the fighter can act.
func _apply_input(ft: Dictionary, inp: Dictionary) -> void:
	if int(ft.stun) > 0 or str(ft.state) in ["hitstun", "blockstun", "knockdown"]:
		return
	# mid-move: allow a special-cancel out of a cancelable move that has connected
	if str(ft.state) == "attack":
		var md: Dictionary = MOVES[str(ft.move)]
		if bool(md.cancel) and bool(ft.has_hit) and str(inp.get("atk", "")) != "" and str(inp.atk) != str(ft.move):
			_start_move(ft, str(inp.atk))
		return
	if bool(ft.airborne):
		return                      # committed to the jump arc
	# grounded + actionable
	var atk: String = str(inp.get("atk", ""))
	if atk != "" and atk in MOVES:
		_start_move(ft, atk)
		return
	if bool(inp.get("up", false)):
		ft.state = "jump"
		ft.airborne = true
		ft.vy = JUMP_VY
		ft.crouch = false
		return
	ft.crouch = bool(inp.get("down", false))
	var dir: int = int(inp.get("dir", 0))
	var away: int = -int(ft.facing)
	ft.block = dir == away          # holding away from the opponent = guarding
	if dir != 0 and not ft.block and not ft.crouch:
		ft.x = int(ft.x) + dir * WALK_SPEED
		ft.state = "walk"
	else:
		ft.state = "crouch" if ft.crouch else ("block" if ft.block else "idle")
	ft.x = clampi(int(ft.x), 12, STAGE_W - 12)

func _start_move(ft: Dictionary, name: String) -> void:
	ft.state = "attack"
	ft.move = name
	ft.mframe = 0
	ft.has_hit = false
	if bool(MOVES[name].proj):
		pass                        # projectile spawns when startup elapses

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

func tick(inp0: Dictionary, inp1: Dictionary) -> void:
	if game_over:
		return
	if not round_active:
		if round_banner > 0:
			round_banner -= 1
			if round_banner == 0:
				_next_round()
		frame += 1
		return
	_face_off()
	_apply_input(f[0], inp0)
	_apply_input(f[1], inp1)
	_advance_fighter(f[0])
	_advance_fighter(f[1])
	_resolve_attacks()
	_advance_projectiles()
	_separate()
	round_frame += 1
	frame += 1
	if round_frame >= ROUND_FRAMES:
		_end_round_by_timeout()

func _face_off() -> void:
	if int(f[0].x) <= int(f[1].x):
		f[0].facing = 1
		f[1].facing = -1
	else:
		f[0].facing = -1
		f[1].facing = 1

func _advance_fighter(ft: Dictionary) -> void:
	if int(ft.stun) > 0:
		ft.stun = int(ft.stun) - 1
		if int(ft.stun) == 0 and str(ft.state) in ["hitstun", "blockstun"]:
			ft.state = "idle"
			ft.combo = 0
	# gravity / jump arc
	if bool(ft.airborne):
		ft.y = int(ft.y) + int(ft.vy)
		ft.vy = int(ft.vy) - GRAVITY
		if int(ft.y) <= 0:
			ft.y = 0
			ft.vy = 0
			ft.airborne = false
			if str(ft.state) == "jump":
				ft.state = "idle"
	# advance an attack through startup→active→recovery
	if str(ft.state) == "attack":
		ft.mframe = int(ft.mframe) + 1
		var md: Dictionary = MOVES[str(ft.move)]
		var total: int = int(md.startup) + int(md.active) + int(md.recovery)
		if bool(md.proj) and int(ft.mframe) == int(md.startup):
			_spawn_projectile(ft)
		if int(ft.mframe) >= total:
			ft.state = "idle"
			ft.move = ""
			ft.mframe = 0
			ft.has_hit = false

func _in_active(ft: Dictionary) -> bool:
	if str(ft.state) != "attack":
		return false
	var md: Dictionary = MOVES[str(ft.move)]
	if bool(md.proj):
		return false
	return int(ft.mframe) > int(md.startup) and int(ft.mframe) <= int(md.startup) + int(md.active)

func _resolve_attacks() -> void:
	for i in range(2):
		var a: Dictionary = f[i]
		var d: Dictionary = f[1 - i]
		if not _in_active(a) or bool(a.has_hit):
			continue
		var md: Dictionary = MOVES[str(a.move)]
		var dist: int = abs(int(a.x) - int(d.x))
		if dist > int(md.range):
			continue
		a.has_hit = true
		_hit(a, d, md)

func _hit(a: Dictionary, d: Dictionary, md: Dictionary) -> void:
	# blocking: correct guard for the move's height while holding away and not mid-move
	var can_block: bool = bool(d.block) and int(d.stun) <= 0 and not bool(d.airborne) and str(d.state) != "attack"
	var height: String = str(md.height)
	var guarded := false
	if can_block:
		if height == "high":
			guarded = not bool(d.crouch)          # overhead — must stand-block
		elif height == "low":
			guarded = bool(d.crouch)              # low — must crouch-block
		else:
			guarded = true                        # mid — any block works
	if guarded:
		d.state = "blockstun"
		d.stun = int(md.blockstun)
		var chip: int = max(1, int(md.dmg) / 6)
		d.hp = int(d.hp) - chip
		_pushback(a, d, int(md.push))
		_log("P%d blocks P%d's %s" % [int(d.idx) + 1, int(a.idx) + 1, str(a.move)])
	else:
		d.combo = int(d.combo) + 1
		d.state = "hitstun"
		d.stun = int(md.hitstun)
		d.hp = int(d.hp) - int(md.dmg)
		d.crouch = false
		_pushback(a, d, int(md.push))
		_log("P%d hits P%d's %s (%d)%s" % [int(a.idx) + 1, int(d.idx) + 1, str(a.move), int(md.dmg),
			(" combo x%d" % int(d.combo) if int(d.combo) > 1 else "")])
	if int(d.hp) <= 0:
		d.hp = 0
		_end_round(int(a.idx))

func _pushback(a: Dictionary, d: Dictionary, amount: int) -> void:
	var dir := 1 if int(d.x) >= int(a.x) else -1
	d.x = clampi(int(d.x) + dir * amount, 12, STAGE_W - 12)

# ---- projectiles ---- #

func _spawn_projectile(ft: Dictionary) -> void:
	projectiles.append({"owner": int(ft.idx), "x": int(ft.x) + int(ft.facing) * 26,
		"y": 20, "dir": int(ft.facing)})
	_log("P%d throws a projectile" % [int(ft.idx) + 1])

func _advance_projectiles() -> void:
	var keep: Array = []
	for p in projectiles:
		p.x = int(p.x) + int(p.dir) * PROJ_SPEED
		var target: Dictionary = f[1 - int(p.owner)]
		var hit: bool = absi(int(p.x) - int(target.x)) <= PROJ_W and int(target.y) < 40
		if hit:
			var md: Dictionary = MOVES["SP"]
			# a fresh has_hit gate so the projectile lands regardless of the owner's move state
			var mock := {"idx": int(p.owner), "x": int(p.x), "move": "SP"}
			_hit(mock, target, md)
			continue                 # consumed
		if int(p.x) < 0 or int(p.x) > STAGE_W:
			continue                 # off-stage
		keep.append(p)
	projectiles = keep

func _separate() -> void:
	# keep the two bodies from overlapping
	var dist: int = abs(int(f[0].x) - int(f[1].x))
	if dist < 24:
		var push := (24 - dist) / 2 + 1
		if int(f[0].x) <= int(f[1].x):
			f[0].x = clampi(int(f[0].x) - push, 12, STAGE_W - 12)
			f[1].x = clampi(int(f[1].x) + push, 12, STAGE_W - 12)
		else:
			f[0].x = clampi(int(f[0].x) + push, 12, STAGE_W - 12)
			f[1].x = clampi(int(f[1].x) - push, 12, STAGE_W - 12)

# --------------------------------------------------------------------------- #
# Round / match flow
# --------------------------------------------------------------------------- #

func _end_round(win_idx: int) -> void:
	if not round_active:
		return
	round_active = false
	round_winner = win_idx
	wins[win_idx] = int(wins[win_idx]) + 1
	round_banner = 90
	_log("Round %d to P%d! (%d-%d)" % [round_no, win_idx + 1, int(wins[0]), int(wins[1])])
	if int(wins[win_idx]) >= ROUNDS_TO_WIN:
		game_over = true
		winner = win_idx
		round_banner = 0
		_log("P%d WINS THE MATCH" % [win_idx + 1])

func _end_round_by_timeout() -> void:
	var w := 0 if int(f[0].hp) >= int(f[1].hp) else 1
	if int(f[0].hp) == int(f[1].hp):
		# double-KO-ish timeout → give it to the fighter nearer center (deterministic)
		w = 0 if abs(int(f[0].x) - STAGE_W / 2) <= abs(int(f[1].x) - STAGE_W / 2) else 1
	_end_round(w)

func _next_round() -> void:
	if game_over:
		return
	round_no += 1
	_start_round()

# --------------------------------------------------------------------------- #
# Heuristic AI — produces an input for a fighter. Deterministic (seeded personality).
# --------------------------------------------------------------------------- #

func ai_input(idx: int) -> Dictionary:
	var me: Dictionary = f[idx]
	var op: Dictionary = f[1 - idx]
	var inp := {"dir": 0, "up": false, "down": false, "atk": ""}
	if int(me.stun) > 0 or str(me.state) in ["hitstun", "blockstun", "knockdown", "attack"] or bool(me.airborne):
		return inp
	var dist: int = abs(int(me.x) - int(op.x))
	var toward: int = 1 if int(op.x) > int(me.x) else -1
	var away: int = -toward
	# block when the opponent is attacking in range (reaction gated by personality)
	if str(op.state) == "attack" and dist < 96 and (int(frame) % 12) < int(me.react):
		inp.dir = away
		# guess low/high: crouch-block unless they're clearly airborne
		inp.down = not bool(op.airborne) and (int(frame) % 3 == 0)
		return inp
	# anti-air with HP when the opponent is jumping in
	if bool(op.airborne) and dist < 90:
		inp.atk = "HP"
		return inp
	var aggr: int = int(me.aggr)
	if dist <= 84:
		# in range → poke / combo. Prefer a light (fast) then it may cancel into special.
		var pick: int = (int(frame) + idx * 7 + aggr) % 100
		if pick < 30:
			inp.atk = "LK"          # low
		elif pick < 55:
			inp.atk = "LP"
		elif pick < 72:
			inp.atk = "HK"
		elif pick < 84:
			inp.atk = "HP"
		else:
			inp.atk = "SP"
		return inp
	if dist <= 150 and (int(frame) % 90) < 12:
		inp.atk = "SP"              # fireball to control space
		return inp
	# approach (aggressive personalities close in more often)
	if (int(frame) % 100) < aggr:
		inp.dir = toward
	else:
		inp.dir = away              # hang back / whiff-punish spacing
	return inp

# --------------------------------------------------------------------------- #
# Deterministic auto-play (probe / an AI seat) — both fighters driven by the AI
# --------------------------------------------------------------------------- #

func auto_step(_policy: String = "both") -> void:
	if game_over:
		return
	tick(ai_input(0), ai_input(1))

func auto_play_to_end(policy: String = "both") -> void:
	var guard := 0
	while not game_over and guard < MATCH_FRAME_CAP:
		auto_step(policy)
		guard += 1
	if not game_over:
		# decide by rounds then HP (bounded safety)
		game_over = true
		winner = 0 if int(wins[0]) > int(wins[1]) else (1 if int(wins[1]) > int(wins[0]) else (0 if int(f[0].hp) >= int(f[1].hp) else 1))

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[%d] %s" % [round_no, s])
	if log_lines.size() > 60:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d,%d" % [frame, round_no, int(game_over), winner, round_frame, int(wins[0]), int(wins[1])]
	for ft in f:
		s += "|F%d,%d,%d,%d,%d,%s,%d,%d" % [int(ft.idx), int(ft.x), int(ft.y), int(ft.hp),
			int(ft.facing), str(ft.state), int(ft.stun), int(ft.combo)]
	for p in projectiles:
		s += "|P%d,%d,%d" % [int(p.owner), int(p.x), int(p.dir)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "frame": frame, "round_no": round_no, "wins": wins.duplicate(),
		"round_frame": round_frame, "round_active": round_active, "round_banner": round_banner,
		"game_over": game_over, "winner": winner, "round_winner": round_winner,
		"seed": int(rng.seed), "rng_state": int(rng.state),
		"f": f.duplicate(true), "projectiles": projectiles.duplicate(true),
	}

func load_data(d: Dictionary) -> void:
	frame = int(d.get("frame", 0))
	round_no = int(d.get("round_no", 1))
	wins = (d.get("wins", [0, 0]) as Array).duplicate()
	round_frame = int(d.get("round_frame", 0))
	round_active = bool(d.get("round_active", true))
	round_banner = int(d.get("round_banner", 0))
	game_over = bool(d.get("game_over", false))
	winner = int(d.get("winner", -1))
	round_winner = int(d.get("round_winner", -1))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	f = (d.get("f", []) as Array).duplicate(true)
	projectiles = (d.get("projectiles", []) as Array).duplicate(true)
