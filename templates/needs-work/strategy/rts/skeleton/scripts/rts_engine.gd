class_name RtsEngine
extends RefCounted
## Pure, seedable REAL-TIME-STRATEGY engine (StarCraft/AoE-lite) run as a DETERMINISTIC
## FIXED-TIMESTEP lockstep sim: play advances in discrete ticks, commands are queued and
## applied in a fixed order, and a single private RNG drives everything (map, tie-breaks,
## AI). No Godot-node or Time dependency — the same seed + same commands reproduce a
## BYTE-IDENTICAL match (FNV-1a checksum) across processes. The scene (rts_view.gd) and
## GameManager wrap this; all rules + state live here (the NoxDev pure-engine ABI).
##
## Owners: 0 = the player, 1 = the AI opponent. Win = raze the enemy town hall; lose =
## yours falls. Economy: workers mine mineral patches, haul CARRY back to a town hall,
## and the owner spends minerals to train workers/soldiers and build a barracks. Combat:
## soldiers acquire the nearest enemy in vision, close to range, and trade blows on a
## cooldown. A weighted-heuristic macro AI can drive EITHER side (auto-play uses both).

# --------------------------------------------------------------------------- #
# Tunable constants (auditable at the top of the file)
# --------------------------------------------------------------------------- #

const W := 48
const H := 40
const TICK_CAP := 12000                 ## safety bound for auto_play_to_end

const OWNER_PLAYER := 0
const OWNER_AI := 1

# costs (minerals)
const COST_WORKER := 50
const COST_SOLDIER := 75
const COST_BARRACKS := 150

# economy
const CARRY := 5                        ## minerals a worker hauls per trip
const MINE_TICKS := 12                  ## ticks to fill a load at a patch
const START_MINERALS := 100
const PATCH_AMOUNT := 1500

# production (ticks)
const BUILD_WORKER_TICKS := 60
const BUILD_SOLDIER_TICKS := 90
const BUILD_BARRACKS_TICKS := 240

# unit / building stats
const WORKER_HP := 40
const WORKER_ATK := 3
const WORKER_RANGE := 1
const WORKER_SPEED := 2                 ## ticks per tile
const SOLDIER_HP := 100
const SOLDIER_ATK := 12
const SOLDIER_RANGE := 1
const SOLDIER_SPEED := 3
const ATTACK_COOLDOWN := 8
const VISION := 10

const TOWNHALL_HP := 800
const BARRACKS_HP := 500

# AI macro thresholds
const AI_TARGET_WORKERS := 6
const AI_ARMY_ATTACK := 6               ## push once this many soldiers exist

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var tick := 0
var game_over := false
var winner := -1

var minerals := [START_MINERALS, START_MINERALS]     ## per owner
var units: Array = []                                ## Array[Dictionary]
var buildings: Array = []                            ## Array[Dictionary]
var patches: Array = []                              ## Array[Dictionary] {id,x,y,amount}
var _next_id := 1
var _cmd_queue: Array = []                           ## commands applied at the next tick
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	tick = 0
	game_over = false
	winner = -1
	minerals = [START_MINERALS, START_MINERALS]
	units = []
	buildings = []
	patches = []
	_cmd_queue = []
	log_lines = []
	_next_id = 1
	_build_world()

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

func _build_world() -> void:
	# Two symmetric bases in opposite corners, each with a town hall, 3 workers and a
	# mineral field nearby. A little seeded jitter keeps matches from being identical.
	_spawn_base(OWNER_PLAYER, 6, 6, 1)
	_spawn_base(OWNER_AI, W - 7, H - 7, -1)

func _spawn_base(owner: int, hx: int, hy: int, dir: int) -> void:
	var hall := {
		"id": _new_id(), "owner": owner, "kind": "townhall",
		"x": hx, "y": hy, "hp": TOWNHALL_HP, "max_hp": TOWNHALL_HP,
		"progress": BUILD_BARRACKS_TICKS,      # complete
		"complete": true, "queue": [], "prod_left": 0, "prod_kind": "",
		"rally_x": hx + dir * 2, "rally_y": hy,
	}
	buildings.append(hall)
	# a mineral field of 4 patches offset from the hall
	for i in range(4):
		patches.append({
			"id": _new_id(), "x": hx + dir * (3 + i), "y": hy + 2 + (i % 2),
			"amount": PATCH_AMOUNT,
		})
	# three starting workers
	for i in range(3):
		units.append(_make_unit(owner, "worker", hx + dir * 1, hy + 1 + i))
	# a couple of seeded scout offsets so the two openings differ slightly by seed
	var jitter := rng.randi_range(0, 2)
	if jitter > 0:
		units.append(_make_unit(owner, "worker", hx + dir * 2, hy + jitter))

func _make_unit(owner: int, kind: String, x: int, y: int) -> Dictionary:
	var is_worker := kind == "worker"
	return {
		"id": _new_id(), "owner": owner, "kind": kind,
		"x": x, "y": y,
		"hp": WORKER_HP if is_worker else SOLDIER_HP,
		"max_hp": WORKER_HP if is_worker else SOLDIER_HP,
		"atk": WORKER_ATK if is_worker else SOLDIER_ATK,
		"range": WORKER_RANGE if is_worker else SOLDIER_RANGE,
		"speed": WORKER_SPEED if is_worker else SOLDIER_SPEED,
		"state": "idle",              # idle|move|to_patch|mining|to_hall|building|attack
		"tx": x, "ty": y,             # move target
		"target_id": 0,               # patch / enemy / building being acted on
		"carrying": 0,
		"mine_left": 0,
		"cooldown": 0,
		"move_left": 0,               # ticks until next tile step
		"build_kind": "",
		"build_left": 0,
	}

# --------------------------------------------------------------------------- #
# Lookups
# --------------------------------------------------------------------------- #

func unit_by_id(id: int) -> Dictionary:
	for u in units:
		if u.id == id:
			return u
	return {}

func building_by_id(id: int) -> Dictionary:
	for b in buildings:
		if b.id == id:
			return b
	return {}

func patch_by_id(id: int) -> Dictionary:
	for p in patches:
		if p.id == id:
			return p
	return {}

func units_of(owner: int) -> Array:
	var out: Array = []
	for u in units:
		if u.owner == owner:
			out.append(u)
	return out

func buildings_of(owner: int) -> Array:
	var out: Array = []
	for b in buildings:
		if b.owner == owner:
			out.append(b)
	return out

func count_kind(owner: int, kind: String) -> int:
	var n := 0
	for u in units:
		if u.owner == owner and u.kind == kind:
			n += 1
	return n

func _townhall_of(owner: int) -> Dictionary:
	for b in buildings:
		if b.owner == owner and b.kind == "townhall":
			return b
	return {}

func _has_barracks(owner: int) -> bool:
	for b in buildings:
		if b.owner == owner and b.kind == "barracks" and b.complete:
			return true
	return false

# --------------------------------------------------------------------------- #
# Command API (queued, applied deterministically at the start of the next tick)
# --------------------------------------------------------------------------- #

func cmd_move(unit_id: int, x: int, y: int) -> void:
	_cmd_queue.append({"kind": "move", "unit": unit_id, "x": x, "y": y})

func cmd_gather(unit_id: int, patch_id: int) -> void:
	_cmd_queue.append({"kind": "gather", "unit": unit_id, "patch": patch_id})

func cmd_attack(unit_id: int, target_id: int) -> void:
	_cmd_queue.append({"kind": "attack", "unit": unit_id, "target": target_id})

func cmd_attack_move(unit_id: int, x: int, y: int) -> void:
	_cmd_queue.append({"kind": "attack_move", "unit": unit_id, "x": x, "y": y})

func cmd_train(building_id: int, unit_kind: String) -> void:
	_cmd_queue.append({"kind": "train", "building": building_id, "unit_kind": unit_kind})

func cmd_build(worker_id: int, building_kind: String, x: int, y: int) -> void:
	_cmd_queue.append({"kind": "build", "unit": worker_id, "building_kind": building_kind, "x": x, "y": y})

func _apply_commands() -> void:
	# deterministic order: sort by (kind, unit/building id) so replays match regardless
	# of the order the UI/AI queued them.
	_cmd_queue.sort_custom(func(a, b):
		var ka: String = str(a.kind)
		var kb: String = str(b.kind)
		if ka != kb:
			return ka < kb
		var ia: int = int(a.get("unit", a.get("building", 0)))
		var ib: int = int(b.get("unit", b.get("building", 0)))
		return ia < ib)
	for c in _cmd_queue:
		match c.kind:
			"move": _do_move(c)
			"gather": _do_gather(c)
			"attack": _do_attack(c)
			"attack_move": _do_attack_move(c)
			"train": _do_train(c)
			"build": _do_build(c)
	_cmd_queue = []

func _do_move(c: Dictionary) -> void:
	var u := unit_by_id(int(c.unit))
	if u.is_empty():
		return
	u.state = "move"
	u.tx = int(c.x)
	u.ty = int(c.y)
	u.target_id = 0

func _do_gather(c: Dictionary) -> void:
	var u := unit_by_id(int(c.unit))
	if u.is_empty() or u.kind != "worker":
		return
	u.state = "to_patch"
	u.target_id = int(c.patch)

func _do_attack(c: Dictionary) -> void:
	var u := unit_by_id(int(c.unit))
	if u.is_empty():
		return
	u.state = "attack"
	u.target_id = int(c.target)

func _do_attack_move(c: Dictionary) -> void:
	var u := unit_by_id(int(c.unit))
	if u.is_empty():
		return
	u.state = "attack"
	u.target_id = 0            # acquire nearest as it advances
	u.tx = int(c.x)
	u.ty = int(c.y)

func _do_train(c: Dictionary) -> void:
	var b := building_by_id(int(c.building))
	if b.is_empty() or not b.complete:
		return
	var kind: String = str(c.unit_kind)
	if kind == "worker" and b.kind != "townhall":
		return
	if kind == "soldier" and b.kind != "barracks":
		return
	var cost: int = COST_WORKER if kind == "worker" else COST_SOLDIER
	if b.prod_left > 0:
		return                # one at a time per building (kept simple + deterministic)
	if minerals[b.owner] < cost:
		return
	minerals[b.owner] -= cost
	b.prod_kind = kind
	b.prod_left = BUILD_WORKER_TICKS if kind == "worker" else BUILD_SOLDIER_TICKS

func _do_build(c: Dictionary) -> void:
	var u := unit_by_id(int(c.unit))
	if u.is_empty() or u.kind != "worker":
		return
	var kind: String = str(c.building_kind)
	if kind != "barracks":
		return
	# keep to one barracks for the template's macro loop — reject if one exists, is
	# pending, or another worker is already building (backstop for the AI guard)
	if _pending_or_built_barracks(int(u.owner)) or _any_builder_busy(int(u.owner)):
		return
	if minerals[u.owner] < COST_BARRACKS:
		return
	minerals[u.owner] -= COST_BARRACKS
	u.state = "building"
	u.build_kind = kind
	u.tx = int(c.x)
	u.ty = int(c.y)

# --------------------------------------------------------------------------- #
# Fixed-timestep simulation
# --------------------------------------------------------------------------- #

func step() -> void:
	if game_over:
		return
	_apply_commands()
	_update_buildings()
	_update_units()
	_cleanup_dead()
	_check_victory()
	tick += 1

func _update_buildings() -> void:
	for b in buildings:
		if not b.complete:
			continue
		if b.prod_left > 0:
			b.prod_left -= 1
			if b.prod_left <= 0 and b.prod_kind != "":
				var spot := _free_tile_near(int(b.x), int(b.y))
				var nu := _make_unit(int(b.owner), str(b.prod_kind), spot.x, spot.y)
				# rally the fresh unit
				nu.state = "move"
				nu.tx = int(b.rally_x)
				nu.ty = int(b.rally_y)
				units.append(nu)
				b.prod_kind = ""

func _update_units() -> void:
	# iterate a snapshot by id so combat deaths mid-loop stay deterministic
	var ids: Array = []
	for u in units:
		ids.append(int(u.id))
	ids.sort()
	for id in ids:
		var u := unit_by_id(id)
		if u.is_empty() or u.hp <= 0:
			continue
		if u.cooldown > 0:
			u.cooldown -= 1
		match u.state:
			"idle": pass
			"move": _tick_move(u)
			"to_patch": _tick_to_patch(u)
			"mining": _tick_mining(u)
			"to_hall": _tick_to_hall(u)
			"building": _tick_building(u)
			"construct": _tick_construct(u)
			"attack": _tick_attack(u)

# ---- movement helpers ---- #

func _blocked(x: int, y: int, mover_id: int) -> bool:
	if x < 0 or x >= W or y < 0 or y >= H:
		return true
	for b in buildings:
		if int(b.x) == x and int(b.y) == y:
			return true
	return false

## One greedy tile step toward (tx,ty), sliding along a blocked axis. Deterministic.
func _step_toward(u: Dictionary, tx: int, ty: int) -> bool:
	if u.move_left > 0:
		u.move_left -= 1
		return false
	u.move_left = int(u.speed)
	var cx: int = int(u.x)
	var cy: int = int(u.y)
	if cx == tx and cy == ty:
		return true
	var sx: int = signi(tx - cx)
	var sy: int = signi(ty - cy)
	# prefer the axis with the greater remaining distance
	var order: Array
	if abs(tx - cx) >= abs(ty - cy):
		order = [Vector2i(sx, 0), Vector2i(0, sy), Vector2i(sx, sy)]
	else:
		order = [Vector2i(0, sy), Vector2i(sx, 0), Vector2i(sx, sy)]
	for d in order:
		if d == Vector2i.ZERO:
			continue
		var nx: int = cx + d.x
		var ny: int = cy + d.y
		if not _blocked(nx, ny, int(u.id)):
			u.x = nx
			u.y = ny
			return nx == tx and ny == ty
	return false

func _tick_move(u: Dictionary) -> void:
	if _step_toward(u, int(u.tx), int(u.ty)):
		u.state = "idle"

# ---- worker economy ---- #

func _tick_to_patch(u: Dictionary) -> void:
	var p := patch_by_id(int(u.target_id))
	if p.is_empty() or int(p.amount) <= 0:
		u.state = "idle"
		u.target_id = _nearest_patch_id(u)
		if u.target_id != 0:
			u.state = "to_patch"
		return
	if _adjacent(int(u.x), int(u.y), int(p.x), int(p.y)):
		u.state = "mining"
		u.mine_left = MINE_TICKS
		return
	_step_toward(u, int(p.x), int(p.y))

func _tick_mining(u: Dictionary) -> void:
	if u.mine_left > 0:
		u.mine_left -= 1
		return
	var p := patch_by_id(int(u.target_id))
	if p.is_empty():
		u.state = "idle"
		return
	var got: int = min(CARRY, int(p.amount))
	p.amount = int(p.amount) - got
	u.carrying = got
	u.state = "to_hall"

func _tick_to_hall(u: Dictionary) -> void:
	var hall := _townhall_of(int(u.owner))
	if hall.is_empty():
		u.state = "idle"
		return
	if _adjacent(int(u.x), int(u.y), int(hall.x), int(hall.y)):
		minerals[int(u.owner)] += int(u.carrying)
		u.carrying = 0
		# resume mining the same (or nearest) patch
		var p := patch_by_id(int(u.target_id))
		if p.is_empty() or int(p.amount) <= 0:
			u.target_id = _nearest_patch_id(u)
		u.state = "to_patch" if u.target_id != 0 else "idle"
		return
	_step_toward(u, int(hall.x), int(hall.y))

func _tick_building(u: Dictionary) -> void:
	if _adjacent(int(u.x), int(u.y), int(u.tx), int(u.ty)) or (int(u.x) == int(u.tx) and int(u.y) == int(u.ty)):
		# lay the foundation and construct in place over BUILD_BARRACKS_TICKS
		var spot := _free_tile_near(int(u.tx), int(u.ty))
		var b := {
			"id": _new_id(), "owner": int(u.owner), "kind": "barracks",
			"x": spot.x, "y": spot.y, "hp": BARRACKS_HP, "max_hp": BARRACKS_HP,
			"progress": 0, "complete": false, "queue": [],
			"prod_left": 0, "prod_kind": "",
			"rally_x": spot.x, "rally_y": spot.y + 2,
		}
		buildings.append(b)
		u.state = "construct"
		u.target_id = int(b.id)
		u.build_left = BUILD_BARRACKS_TICKS
		# fold construct into the same handler next tick
		_tick_construct(u)
		return
	_step_toward(u, int(u.tx), int(u.ty))

func _tick_construct(u: Dictionary) -> void:
	var b := building_by_id(int(u.target_id))
	if b.is_empty():
		u.state = "idle"
		return
	b.progress = int(b.progress) + 1
	if int(b.progress) >= BUILD_BARRACKS_TICKS:
		b.complete = true
		u.state = "idle"
		u.build_kind = ""

# ---- combat ---- #

func _tick_attack(u: Dictionary) -> void:
	var tgt := _resolve_attack_target(u)
	if tgt.is_empty():
		# nothing in range/vision — advance toward the ordered point, else idle
		if int(u.tx) != int(u.x) or int(u.ty) != int(u.y):
			_step_toward(u, int(u.tx), int(u.ty))
		else:
			u.state = "idle"
		return
	var tx: int = int(tgt.x)
	var ty: int = int(tgt.y)
	if _within(int(u.x), int(u.y), tx, ty, int(u.range)):
		if u.cooldown <= 0:
			tgt.hp = int(tgt.hp) - int(u.atk)
			u.cooldown = ATTACK_COOLDOWN
	else:
		_step_toward(u, tx, ty)

## Pick the current target: an explicit target_id if still valid + visible, else the
## nearest enemy unit, else the nearest enemy building. Deterministic (id order breaks ties).
func _resolve_attack_target(u: Dictionary) -> Dictionary:
	if int(u.target_id) != 0:
		var t := unit_by_id(int(u.target_id))
		if t.is_empty():
			t = building_by_id(int(u.target_id))
		if not t.is_empty() and int(t.hp) > 0:
			return t
		u.target_id = 0
	var best := {}
	var bd := 1 << 30
	for e in units:
		if int(e.owner) == int(u.owner) or int(e.hp) <= 0:
			continue
		var d: int = _cheb(int(u.x), int(u.y), int(e.x), int(e.y))
		if d <= VISION and d < bd:
			bd = d
			best = e
	if best.is_empty():
		for e in buildings:
			if int(e.owner) == int(u.owner) or int(e.hp) <= 0:
				continue
			var d: int = _cheb(int(u.x), int(u.y), int(e.x), int(e.y))
			if d < bd:
				bd = d
				best = e
	return best

func _cleanup_dead() -> void:
	var alive_u: Array = []
	for u in units:
		if int(u.hp) > 0:
			alive_u.append(u)
		else:
			_log("%s of P%d destroyed" % [u.kind, int(u.owner)])
	units = alive_u
	var alive_b: Array = []
	for b in buildings:
		if int(b.hp) > 0:
			alive_b.append(b)
		else:
			_log("%s of P%d razed" % [b.kind, int(b.owner)])
	buildings = alive_b

func _check_victory() -> void:
	var p_hall := not _townhall_of(OWNER_PLAYER).is_empty()
	var a_hall := not _townhall_of(OWNER_AI).is_empty()
	if p_hall and not a_hall:
		game_over = true
		winner = OWNER_PLAYER
	elif a_hall and not p_hall:
		game_over = true
		winner = OWNER_AI
	elif not p_hall and not a_hall:
		game_over = true
		winner = -1

# --------------------------------------------------------------------------- #
# Geometry helpers
# --------------------------------------------------------------------------- #

func _cheb(ax: int, ay: int, bx: int, by: int) -> int:
	return max(abs(ax - bx), abs(ay - by))

func _adjacent(ax: int, ay: int, bx: int, by: int) -> bool:
	return _cheb(ax, ay, bx, by) <= 1

func _within(ax: int, ay: int, bx: int, by: int, r: int) -> bool:
	return _cheb(ax, ay, bx, by) <= r

func _free_tile_near(cx: int, cy: int) -> Vector2i:
	if not _occupied(cx, cy):
		return Vector2i(cx, cy)
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nx: int = cx + dx
				var ny: int = cy + dy
				if nx < 0 or nx >= W or ny < 0 or ny >= H:
					continue
				if not _occupied(nx, ny):
					return Vector2i(nx, ny)
	return Vector2i(clampi(cx, 0, W - 1), clampi(cy, 0, H - 1))

func _occupied(x: int, y: int) -> bool:
	for b in buildings:
		if int(b.x) == x and int(b.y) == y:
			return true
	return false

func _nearest_patch_id(u: Dictionary) -> int:
	var best := 0
	var bd := 1 << 30
	for p in patches:
		if int(p.amount) <= 0:
			continue
		var d: int = _cheb(int(u.x), int(u.y), int(p.x), int(p.y))
		if d < bd:
			bd = d
			best = int(p.id)
	return best

# --------------------------------------------------------------------------- #
# Heuristic macro AI — can drive EITHER owner (auto-play drives both)
# --------------------------------------------------------------------------- #

## Issues a batch of commands for `owner` based on the current board. Deterministic
## (counts + id order, seeded only for the rare coin-flip). Called every AI_TICK ticks.
func ai_take_turn(owner: int) -> void:
	if game_over:
		return
	var hall := _townhall_of(owner)
	if hall.is_empty():
		return
	# 1) keep every idle worker mining
	for u in units_of(owner):
		if u.kind == "worker" and (u.state == "idle" or u.state == "move"):
			var pid := _nearest_patch_id(u)
			if pid != 0:
				cmd_gather(int(u.id), pid)
	# 2) train workers up to the target, from the town hall
	var workers := count_kind(owner, "worker")
	if workers < AI_TARGET_WORKERS and int(hall.prod_left) <= 0 and minerals[owner] >= COST_WORKER:
		cmd_train(int(hall.id), "worker")
	# 3) once the economy is up, get a barracks — but only if none exists, none is
	#    pending, and no worker is already walking out to build one (else we'd re-issue
	#    the order every AI tick during the walk and double-charge minerals)
	if workers >= 4 and not _pending_or_built_barracks(owner) and not _any_builder_busy(owner) and minerals[owner] >= COST_BARRACKS:
		var bw := _free_builder(owner)
		if bw != 0:
			var bx: int = int(hall.x) + (3 if owner == OWNER_PLAYER else -3)
			var by: int = int(hall.y) + 4
			cmd_build(bw, "barracks", clampi(bx, 0, W - 1), clampi(by, 0, H - 1))
	# 4) pump soldiers from the barracks
	for b in buildings_of(owner):
		if b.kind == "barracks" and b.complete and int(b.prod_left) <= 0 and minerals[owner] >= COST_SOLDIER:
			cmd_train(int(b.id), "soldier")
	# 5) when the army is big enough, push the enemy town hall
	var army: Array = []
	for u in units_of(owner):
		if u.kind == "soldier":
			army.append(u)
	if army.size() >= AI_ARMY_ATTACK:
		var ehall := _townhall_of(1 - owner)
		if not ehall.is_empty():
			for u in army:
				cmd_attack_move(int(u.id), int(ehall.x), int(ehall.y))

func _free_builder(owner: int) -> int:
	for u in units_of(owner):
		if u.kind == "worker" and u.state != "building" and u.state != "construct":
			return int(u.id)
	return 0

func _pending_or_built_barracks(owner: int) -> bool:
	for b in buildings:
		if int(b.owner) == owner and b.kind == "barracks":
			return true            # complete OR under construction
	return false

func _any_builder_busy(owner: int) -> bool:
	for u in units_of(owner):
		if u.kind == "worker" and (u.state == "building" or u.state == "construct"):
			return true
	return false

# --------------------------------------------------------------------------- #
# Deterministic auto-play (probe / an AI seat) — both sides driven by the macro AI
# --------------------------------------------------------------------------- #

const AI_TICK := 10                     ## AI re-plans every N ticks

func auto_step(_policy: String = "both") -> void:
	if game_over:
		return
	if tick % AI_TICK == 0:
		ai_take_turn(OWNER_PLAYER)
		ai_take_turn(OWNER_AI)
	step()

func auto_play_to_end(policy: String = "both") -> void:
	var guard := 0
	while not game_over and guard < TICK_CAP:
		auto_step(policy)
		guard += 1
	if not game_over:
		game_over = true            # bounded — treat as a draw/stall

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[t%d] %s" % [tick, s])
	if log_lines.size() > 60:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d" % [tick, int(game_over), winner, int(minerals[0]), int(minerals[1])]
	for b in buildings:
		s += "|B%d,%d,%d,%d,%d,%d,%d" % [int(b.id), int(b.owner), _kind_code(str(b.kind)),
			int(b.x), int(b.y), int(b.hp), int(b.progress)]
	for u in units:
		s += "|U%d,%d,%d,%d,%d,%d,%s,%d" % [int(u.id), int(u.owner), _kind_code(str(u.kind)),
			int(u.x), int(u.y), int(u.hp), str(u.state), int(u.carrying)]
	for p in patches:
		s += "|P%d,%d,%d,%d" % [int(p.id), int(p.x), int(p.y), int(p.amount)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func _kind_code(k: String) -> int:
	match k:
		"worker": return 1
		"soldier": return 2
		"townhall": return 3
		"barracks": return 4
	return 0

func save_data() -> Dictionary:
	return {
		"version": 1, "tick": tick, "game_over": game_over, "winner": winner,
		"minerals": minerals.duplicate(), "next_id": _next_id,
		"units": units.duplicate(true), "buildings": buildings.duplicate(true),
		"patches": patches.duplicate(true), "seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	tick = int(d.get("tick", 0))
	game_over = bool(d.get("game_over", false))
	winner = int(d.get("winner", -1))
	minerals = (d.get("minerals", [START_MINERALS, START_MINERALS]) as Array).duplicate()
	_next_id = int(d.get("next_id", 1))
	units = (d.get("units", []) as Array).duplicate(true)
	buildings = (d.get("buildings", []) as Array).duplicate(true)
	patches = (d.get("patches", []) as Array).duplicate(true)
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	_cmd_queue = []
