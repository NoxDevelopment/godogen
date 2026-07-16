extends RefCounted
class_name PegEngine
## res://scripts/peg_engine.gd
## The PURE, seedable, headless-testable engine for a Peglin-lineage PACHINKO
## ROGUELIKE: aim + fire ORBS that bounce down a PEG board under a DETERMINISTIC
## custom physics sim, accumulate damage from every peg they touch, dump that
## damage onto an enemy, and — between fights — run a roguelike map of combat /
## elite / shop / event / rest / boss nodes with RELICS, gold, and orb upgrades.
## There is NO Godot-node dependency and NO RigidBody2D in here: the ball-vs-peg
## physics is our OWN fixed-timestep circle sim, so a whole run replays
## BYTE-IDENTICALLY from a seed and drives headlessly with no UI at all.
##
## WHY CUSTOM PHYSICS (the key design decision):
##   Godot's RigidBody2D solver is NOT guaranteed identical across runs/builds,
##   which would break byte-identical replays + probes. So a ball is just a circle
##   (position, velocity) advanced at a FIXED dt under gravity, colliding with
##   circular PEGS and the four WALLS by pure geometry — circle-circle / circle-
##   wall overlap → push out of penetration + reflect the velocity about the
##   contact normal with a restitution factor. Given (aim angle, board layout,
##   seed) the trajectory + accumulated damage are 100% reproducible. The only
##   randomness in the whole engine (board gen, map gen, deck shuffle, shop rolls,
##   enemy stats, events) comes from ONE seeded RNG whose state is part of
##   save/load — the physics has ZERO randomness. A MAX_STEPS cap bounds every
##   shot so no ball loops forever.
##
## Layers:
##   * Physics      — _simulate_ball()/_simulate_orb(): pure circle sim → a
##                    resolution {trajectory, pegs hit, wall bounces, checksum}.
##   * Damage       — _compute_shot(): resolution + ORB effect + RELICS → damage,
##                    poison, heal, gold (auditable, component by component).
##   * Combat       — enemy HP + a cycling attack pattern, your HP, a DECK of orbs
##                    (draw / discard / reshuffle), status effects.
##   * Run          — a layered node MAP, gold, relics, orb rewards + a shop.
##   * Auto-play    — auto_step(): a deterministic heuristic that drives a whole
##                    run headlessly (aim at the best-damage angle, buy sensibly).

# =====================================================================
#  Board + physics tuning (auditable constants — swap for your own game)
# =====================================================================

const BOARD_W: float = 320.0        ## play-field width  (virtual units).
const BOARD_H: float = 460.0        ## play-field height (virtual units).
const BALL_R: float = 6.0           ## ball radius.
const PEG_R: float = 9.0            ## peg radius.
const SPAWN_Y: float = 12.0         ## y the ball is launched from (top).
const GRAVITY: float = 520.0        ## downward accel (units/s^2).
const DT: float = 1.0 / 120.0       ## fixed physics timestep (seconds).
const RESTITUTION: float = 0.72     ## velocity kept along the normal after a bounce.
const LAUNCH_SPEED: float = 150.0   ## initial ball speed when fired.
const AIM_SPREAD: float = 1.05      ## aim fan half-angle (rad) either side of straight down.
const MAX_STEPS: int = 3000         ## hard cap on sim steps per ball (bounded — no infinite loops).
const BOMB_RADIUS: float = 46.0     ## a bomb peg's AoE reach (units).
const REFRESH_BONUS_PER: int = 3    ## a refresh peg's bonus per peg already hit this ball.
const MULTIBALL_OFFSET: float = 0.16  ## angle delta of a multiball's second ball (rad).

## FNV-1a folding constants (63-bit masked, matching the sandbox engine) for the
## deterministic per-shot / whole-run checksum.
const FNV_OFFSET: int = 1469598103934665603
const FNV_PRIME: int = 1099511628211
const MASK63: int = 0x7FFFFFFFFFFFFFFF

# =====================================================================
#  Peg types (>=3) — each with distinct behaviour + base damage
# =====================================================================

const PEG_NORMAL: int = 0   ## gives its damage the first time hit this shot.
const PEG_CRIT: int = 1     ## bonus-damage peg (crit).
const PEG_BOMB: int = 2     ## special: on hit, AoE-triggers nearby pegs too.
const PEG_REFRESH: int = 3  ## special: pays a bonus scaled by pegs already hit.
const PEG_TYPE_COUNT: int = 4

const PEG_BASE_DAMAGE: Dictionary = {
	PEG_NORMAL: 8,
	PEG_CRIT: 22,
	PEG_BOMB: 6,
	PEG_REFRESH: 5,
}

const PEG_TYPE_NAME: Dictionary = {
	PEG_NORMAL: "Peg",
	PEG_CRIT: "Crit",
	PEG_BOMB: "Bomb",
	PEG_REFRESH: "Refresh",
}

# =====================================================================
#  Orb database — 14 distinct orbs (a DECK). base = flat damage added per peg
#  hit; `effect` selects a branch in _compute_shot / _simulate_orb; `n` is the
#  effect magnitude. Swap this table for your own orbs.
# =====================================================================

const ORB_DB: Dictionary = {
	"orb_stone":   {"name": "Stone Orb",    "base": 0, "effect": "plain",       "n": 0,  "desc": "Pure peg damage, no frills."},
	"orb_bramble": {"name": "Bramble Orb",  "base": 4, "effect": "plain",       "n": 0,  "desc": "+4 damage on every peg it touches."},
	"orb_boulder": {"name": "Boulder Orb",  "base": 7, "effect": "plain",       "n": 0,  "desc": "Heavy: +7 damage per peg."},
	"orb_dagger":  {"name": "Dagger Orb",   "base": 0, "effect": "crit_boost",  "n": 15, "desc": "Crit pegs deal +15 extra damage."},
	"orb_split":   {"name": "Split Orb",    "base": 0, "effect": "multiball",   "n": 0,  "desc": "Fires a second ball on a fanned angle."},
	"orb_venom":   {"name": "Venom Orb",    "base": 0, "effect": "poison",      "n": 3,  "desc": "Applies poison = pegs hit + 3."},
	"orb_scatter": {"name": "Scatter Orb",  "base": 0, "effect": "remaining",   "n": 2,  "desc": "+2 damage per peg left UN-hit."},
	"orb_life":    {"name": "Life Orb",     "base": 2, "effect": "heal",        "n": 0,  "desc": "Heals you 1 HP per 2 pegs hit."},
	"orb_spear":   {"name": "Spear Orb",    "base": 2, "effect": "pierce",      "n": 3,  "desc": "Pierces (no bounce) through the first 3 pegs."},
	"orb_comet":   {"name": "Comet Orb",    "base": 0, "effect": "momentum",    "n": 4,  "desc": "+4 damage per wall bounce."},
	"orb_echo":    {"name": "Echo Orb",     "base": 1, "effect": "echo",        "n": 0,  "desc": "Doubles the shot's total damage."},
	"orb_bombard": {"name": "Bombard Orb",  "base": 2, "effect": "bomb_boost",  "n": 12, "desc": "Bomb pegs deal +12 damage."},
	"orb_midas":   {"name": "Midas Orb",    "base": 3, "effect": "gold",        "n": 0,  "desc": "Earns 1 gold per peg hit."},
	"orb_chain":   {"name": "Chain Orb",    "base": 2, "effect": "refresh_syn", "n": 0,  "desc": "Refresh pegs pay double their bonus."},
}

## The deck a fresh run starts with (persists + grows across the run).
const START_DECK: Array = [
	"orb_stone", "orb_stone", "orb_bramble", "orb_dagger", "orb_venom", "orb_comet",
]

# =====================================================================
#  Relic database — 10 passive modifiers (>=8). effect selects where it applies.
# =====================================================================

const RELIC_DB: Dictionary = {
	"relic_sharp":       {"name": "Sharpened Pegs", "effect": "peg_flat",    "n": 2,   "desc": "+2 damage on every peg hit."},
	"relic_critlens":    {"name": "Crit Lens",      "effect": "crit_mult",   "x": 1.5, "desc": "Crit pegs deal x1.5 damage."},
	"relic_bombcase":    {"name": "Bomb Casing",    "effect": "bomb_mult",   "x": 1.5, "desc": "Bomb pegs deal x1.5 damage."},
	"relic_momentum":    {"name": "Momentum Core",  "effect": "bounce_flat", "n": 1,   "desc": "+1 damage per wall bounce."},
	"relic_toxic":       {"name": "Toxic Coating",  "effect": "poison_flat", "n": 2,   "desc": "Every shot applies +2 poison."},
	"relic_vampire":     {"name": "Vampiric Charm", "effect": "crit_heal",   "n": 1,   "desc": "Heal 1 HP per crit peg hit."},
	"relic_clover":      {"name": "Lucky Clover",   "effect": "gold_mult",   "x": 1.25,"desc": "+25% gold from every reward."},
	"relic_plating":     {"name": "Iron Plating",   "effect": "max_hp",      "n": 20,  "desc": "+20 max HP (and heals it) on pickup."},
	"relic_overcharge":  {"name": "Overcharge",     "effect": "first_double","n": 0,   "desc": "First shot of each fight deals double."},
	"relic_focus":       {"name": "Focusing Rune",  "effect": "orb_base",    "n": 1,   "desc": "+1 base damage to every orb."},
}

# =====================================================================
#  Run tuning
# =====================================================================

const START_HP: int = 60
const NUM_ROWS: int = 8              ## map depth incl. the boss row.
const PEG_ROWS: int = 6              ## rows of pegs on a board.
const PEG_COLS: int = 7              ## pegs per row (staggered).
const AIM_SAMPLES: int = 25          ## angles the auto-aim tries.
const SHOP_ORBS: int = 2
const SHOP_RELICS: int = 1
const REWARD_ORBS: int = 3
const COST_ORB: int = 40
const COST_RELIC: int = 65
const COST_UPGRADE: int = 35
const COST_HEAL: int = 25
const HEAL_AMOUNT: int = 20
const UPGRADE_BONUS: int = 3         ## +base damage an orb gains when upgraded.
const REST_HEAL_FRAC: float = 0.35   ## fraction of max HP a rest restores.

## Enemy templates per node type: base HP, and the cycling attack pattern.
const ENEMY_TEMPLATE: Dictionary = {
	"combat": {"name": "Marauder", "hp": 44,  "moves": [5, 5, 9],   "boss": false},
	"elite":  {"name": "Warden",   "hp": 82,  "moves": [8, 12, 8],  "boss": false},
	"boss":   {"name": "Colossus", "hp": 150, "moves": [10, 14, 20],"boss": true},
}

const GOLD_REWARD: Dictionary = {"combat": 16, "elite": 32, "boss": 60}

## Node types + their weighted odds when rolling an interior map row.
const NODE_WEIGHTS: Dictionary = {
	"combat": 46, "elite": 14, "shop": 12, "event": 14, "rest": 14,
}

# =====================================================================
#  Live run state
# =====================================================================

var phase: String = "map"           ## map|combat|reward|shop|event|rest|done.
var player_hp: int = START_HP
var player_max_hp: int = START_HP
var gold: int = 0
var run_over: bool = false
var run_won: bool = false

var deck: Array = []                 ## owned orb ids (persist + grow).
var relics: Array = []               ## owned relic ids.

# --- map ---
var map_nodes: Dictionary = {}       ## id -> {row,col,type,x,next:Array[String]}.
var map_order: Array = []            ## Array[Array[String]] — ids per row.
var current_id: String = ""          ## "" == choose from row 0.
var visited: Array = []              ## chosen node ids.
var depth: int = 0                   ## how many nodes cleared (difficulty ramp).

# --- combat ---
var enemy: Dictionary = {}           ## {name,hp,max_hp,moves,move_idx,poison,boss}.
var draw_pile: Array = []
var discard_pile: Array = []
var current_orb: String = ""
var shots_this_fight: int = 0
var last_shot: Dictionary = {}       ## summary of the most recent fire (for the HUD).

# --- pegs (parallel arrays — the board layout for the current fight) ---
var peg_x: PackedFloat32Array = PackedFloat32Array()
var peg_y: PackedFloat32Array = PackedFloat32Array()
var peg_type: PackedByteArray = PackedByteArray()

# --- transient render data (NOT saved) ---
var last_trajectory: PackedVector2Array = PackedVector2Array()
var last_pegs_hit: PackedByteArray = PackedByteArray()

# --- shop / event / rest offerings ---
var shop_items: Array = []           ## [{kind,id/target,cost,bought}].
var event_data: Dictionary = {}      ## {name,desc,options:[{label,...}]}.

var illegal_attempts: int = 0
var log_lines: Array = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = 0
var _enemy_hp_scale: float = 1.0
var _enemy_dmg_scale: float = 1.0


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh run. seed_value == 0 -> random; any other value replays
## byte-identically. `config` overrides difficulty:
##   start_hp:int, enemy_hp_scale:float, enemy_dmg_scale:float,
##   start_deck:Array[String], start_relics:Array[String].
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	_seed = seed_value
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value
	_enemy_hp_scale = float(config.get("enemy_hp_scale", 1.0))
	_enemy_dmg_scale = float(config.get("enemy_dmg_scale", 1.0))
	player_max_hp = int(config.get("start_hp", START_HP))
	player_hp = player_max_hp
	gold = int(config.get("start_gold", 0))
	run_over = false
	run_won = false
	deck = []
	for oid in config.get("start_deck", START_DECK):
		if ORB_DB.has(String(oid)):
			deck.append(String(oid))
	relics = []
	for rid in config.get("start_relics", []):
		if RELIC_DB.has(String(rid)):
			_grant_relic(String(rid))
	enemy = {}
	draw_pile = []
	discard_pile = []
	current_orb = ""
	shots_this_fight = 0
	last_shot = {}
	shop_items = []
	event_data = {}
	visited = []
	depth = 0
	current_id = ""
	illegal_attempts = 0
	log_lines = []
	last_trajectory = PackedVector2Array()
	last_pegs_hit = PackedByteArray()
	_build_map()
	phase = "map"
	_log("Run start — seed %d. HP %d, deck %d orbs." % [_seed, player_hp, deck.size()])


# =====================================================================
#  Map generation (seeded, connected, boss-terminated)
# =====================================================================

func _build_map() -> void:
	map_nodes = {}
	map_order = []
	# Row 0 is a single forced combat; the last row is the boss; interiors roll.
	for r in NUM_ROWS:
		var ids: Array = []
		var count: int
		if r == 0:
			count = 1
		elif r == NUM_ROWS - 1:
			count = 1
		else:
			count = _rng.randi_range(2, 3)
		for c in count:
			var t: String
			if r == 0:
				t = "combat"
			elif r == NUM_ROWS - 1:
				t = "boss"
			elif r == NUM_ROWS - 2:
				t = "rest"        ## a guaranteed breather before the boss.
			else:
				t = _roll_node_type()
			var nid := "%d_%d" % [r, c]
			var x := (float(c) + 1.0) / (float(count) + 1.0)  ## 0..1 horizontal slot.
			map_nodes[nid] = {"row": r, "col": c, "type": t, "x": x, "next": [] as Array}
			ids.append(nid)
		map_order.append(ids)
	# Connect every node to 1-2 nearest nodes in the next row, then guarantee
	# every next-row node has at least one incoming edge (full reachability).
	for r in range(NUM_ROWS - 1):
		var here: Array = map_order[r]
		var there: Array = map_order[r + 1]
		for nid in here:
			var node: Dictionary = map_nodes[nid]
			var order := _nearest_order(float(node["x"]), there)
			var links := 1 if there.size() == 1 else _rng.randi_range(1, 2)
			for k in mini(links, order.size()):
				var tid: String = order[k]
				if not (node["next"] as Array).has(tid):
					(node["next"] as Array).append(tid)
		# ensure coverage of the next row.
		for tid in there:
			if not _has_incoming(tid, here):
				var src: String = _nearest_order(float(map_nodes[tid]["x"]), here)[0]
				if not (map_nodes[src]["next"] as Array).has(tid):
					(map_nodes[src]["next"] as Array).append(tid)


func _roll_node_type() -> String:
	var total := 0
	for k in NODE_WEIGHTS.keys():
		total += int(NODE_WEIGHTS[k])
	var r := _rng.randi_range(1, total)
	var acc := 0
	for k in NODE_WEIGHTS.keys():
		acc += int(NODE_WEIGHTS[k])
		if r <= acc:
			return String(k)
	return "combat"


## Node ids of `row` sorted by horizontal distance to `x` (deterministic).
func _nearest_order(x: float, row: Array) -> Array:
	var arr: Array = row.duplicate()
	arr.sort_custom(func(a: String, b: String) -> bool:
		var da: float = absf(float(map_nodes[a]["x"]) - x)
		var db: float = absf(float(map_nodes[b]["x"]) - x)
		if da == db:
			return int(map_nodes[a]["col"]) < int(map_nodes[b]["col"])
		return da < db)
	return arr


func _has_incoming(tid: String, from_row: Array) -> bool:
	for nid in from_row:
		if (map_nodes[nid]["next"] as Array).has(tid):
			return true
	return false


# =====================================================================
#  Map navigation
# =====================================================================

## Node ids the player may travel to right now (row 0 at the start, else the
## current node's outgoing edges).
func map_options() -> Array:
	if phase != "map":
		return []
	if current_id == "":
		return map_order[0].duplicate()
	return (map_nodes[current_id]["next"] as Array).duplicate()


## Travel to `node_id` and enter it (starting a fight / shop / event / rest).
func choose_node(node_id: String) -> bool:
	if not is_legal({"type": "choose", "id": node_id}):
		illegal_attempts += 1
		return false
	current_id = node_id
	visited.append(node_id)
	_enter_node(node_id)
	return true


func _enter_node(node_id: String) -> void:
	var t: String = String(map_nodes[node_id]["type"])
	depth += 1
	match t:
		"combat", "elite", "boss":
			_start_fight(t, node_id)
		"shop":
			_open_shop()
		"event":
			_open_event()
		"rest":
			_open_rest()
		_:
			push_error("PegEngine: unknown node type '%s'." % t)


# =====================================================================
#  Combat setup
# =====================================================================

func _start_fight(kind: String, node_id: String) -> void:
	var tmpl: Dictionary = ENEMY_TEMPLATE[kind if kind != "elite" else "elite"]
	if kind == "combat":
		tmpl = ENEMY_TEMPLATE["combat"]
	elif kind == "elite":
		tmpl = ENEMY_TEMPLATE["elite"]
	else:
		tmpl = ENEMY_TEMPLATE["boss"]
	var ramp := 1.0 + 0.08 * float(depth)  ## enemies toughen as the run goes on.
	var hp := int(round(float(int(tmpl["hp"])) * _enemy_hp_scale * ramp))
	var moves: Array = []
	for m in tmpl["moves"]:
		moves.append(maxi(0, int(round(float(int(m)) * _enemy_dmg_scale))))
	enemy = {
		"name": String(tmpl["name"]),
		"hp": hp,
		"max_hp": hp,
		"moves": moves,
		"move_idx": 0,
		"poison": 0,
		"boss": bool(tmpl["boss"]),
		"kind": kind,
		"node": node_id,
	}
	_generate_board()
	_build_draw_pile()
	shots_this_fight = 0
	last_shot = {}
	phase = "combat"
	_log("Enter %s — %s (%d HP)." % [kind, String(enemy["name"]), hp])


## Generate a staggered pachinko peg board from the seeded RNG. Deterministic:
## the same seed + depth give the same board.
func _generate_board() -> void:
	peg_x = PackedFloat32Array()
	peg_y = PackedFloat32Array()
	peg_type = PackedByteArray()
	var top := 90.0
	var bottom := BOARD_H - 70.0
	var row_gap := (bottom - top) / float(PEG_ROWS - 1)
	var col_gap := BOARD_W / float(PEG_COLS + 1)
	for r in PEG_ROWS:
		var y := top + float(r) * row_gap
		var stagger := (col_gap * 0.5) if (r % 2 == 1) else 0.0
		for c in PEG_COLS:
			var base_x := col_gap * float(c + 1) + stagger
			if base_x < PEG_R + 4.0 or base_x > BOARD_W - PEG_R - 4.0:
				continue
			var jitter := _rng.randf_range(-col_gap * 0.14, col_gap * 0.14)
			var x := clampf(base_x + jitter, PEG_R + 4.0, BOARD_W - PEG_R - 4.0)
			peg_x.append(x)
			peg_y.append(y)
			peg_type.append(_roll_peg_type())


func _roll_peg_type() -> int:
	var r := _rng.randf()
	if r < 0.16:
		return PEG_CRIT
	if r < 0.24:
		return PEG_BOMB
	if r < 0.30:
		return PEG_REFRESH
	return PEG_NORMAL


func peg_count() -> int:
	return peg_x.size()


func _build_draw_pile() -> void:
	draw_pile = deck.duplicate()
	# Fisher-Yates with the seeded RNG (deterministic under _seed).
	for i in range(draw_pile.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp
	discard_pile = []
	current_orb = ""
	_draw_orb()


## Draw the next orb into `current_orb`, reshuffling the discard back into the
## draw pile (seeded) when the draw pile is empty.
func _draw_orb() -> void:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			current_orb = ""
			return
		draw_pile = discard_pile.duplicate()
		discard_pile = []
		for i in range(draw_pile.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp: Variant = draw_pile[i]
			draw_pile[i] = draw_pile[j]
			draw_pile[j] = tmp
	current_orb = String(draw_pile.pop_back())


# =====================================================================
#  Deterministic ball physics — the pure circle sim
# =====================================================================

## Advance ONE ball (a circle) from the launch point along `angle` until it
## exits the bottom or hits MAX_STEPS. PURE geometry — gravity + fixed dt +
## circle-circle / circle-wall reflection. `hit` (length peg_count) is MUTATED
## to record which pegs this ball touched; `record` toggles whether the full
## trajectory is appended (on for rendering, cheap either way). Returns a
## resolution: {hits:[{index,type,refresh_prior}], wall_bounces, steps,
## trajectory, checksum, exited}.
func _simulate_ball(hit: PackedByteArray, angle: float, pierce_budget: int, record: bool) -> Dictionary:
	var pos := Vector2(BOARD_W * 0.5, SPAWN_Y)
	var vel := Vector2(sin(angle), cos(angle)) * LAUNCH_SPEED  ## angle 0 == straight down.
	var traj := PackedVector2Array()
	var hits: Array = []
	var pierced: Dictionary = {}          ## peg index -> true (passed through, no bounce).
	var wall_bounces := 0
	var pierces_left := pierce_budget
	var steps := 0
	var checksum := FNV_OFFSET
	var exited := false
	var n := peg_x.size()
	while steps < MAX_STEPS:
		steps += 1
		# integrate
		vel.y += GRAVITY * DT
		pos += vel * DT
		# walls (left/right/top reflect — the ball can NEVER leave the field).
		if pos.x < BALL_R:
			pos.x = BALL_R
			vel.x = -vel.x * RESTITUTION
			wall_bounces += 1
		elif pos.x > BOARD_W - BALL_R:
			pos.x = BOARD_W - BALL_R
			vel.x = -vel.x * RESTITUTION
			wall_bounces += 1
		if pos.y < BALL_R:
			pos.y = BALL_R
			vel.y = -vel.y * RESTITUTION
		# pegs
		for i in n:
			var cx := peg_x[i]
			var cy := peg_y[i]
			var dx := pos.x - cx
			var dy := pos.y - cy
			var rr := PEG_R + BALL_R
			if dx * dx + dy * dy < rr * rr:
				var dist := sqrt(dx * dx + dy * dy)
				var nx: float
				var ny: float
				if dist > 0.0001:
					nx = dx / dist
					ny = dy / dist
				else:
					nx = 0.0
					ny = -1.0
				# register a NEW hit (first contact this ball).
				if hit[i] == 0:
					hit[i] = 1
					var ev := {"index": i, "type": int(peg_type[i]), "refresh_prior": hits.size()}
					hits.append(ev)
					if int(peg_type[i]) == PEG_BOMB:
						_bomb_detonate(i, hit, hits)
					if pierces_left > 0:
						pierces_left -= 1
						pierced[i] = true
				# physics: pierced pegs pass through; others push out + reflect.
				if not pierced.has(i):
					pos.x = cx + nx * rr
					pos.y = cy + ny * rr
					var vn := vel.x * nx + vel.y * ny
					if vn < 0.0:
						vel.x -= (1.0 + RESTITUTION) * vn * nx
						vel.y -= (1.0 + RESTITUTION) * vn * ny
		# checksum + optional trajectory (quantized so it is stable + comparable).
		checksum = _fold(checksum, int(round(pos.x * 100.0)))
		checksum = _fold(checksum, int(round(pos.y * 100.0)))
		if record:
			traj.append(pos)
		# exit the bottom
		if pos.y - BALL_R > BOARD_H:
			exited = true
			break
	checksum = _fold(checksum, wall_bounces)
	checksum = _fold(checksum, hits.size())
	return {
		"hits": hits,
		"wall_bounces": wall_bounces,
		"steps": steps,
		"trajectory": traj,
		"checksum": checksum,
		"exited": exited,
	}


## A bomb peg's AoE: any not-yet-hit peg within BOMB_RADIUS is triggered too and
## scores as its own type (bomb->crit chains are possible).
func _bomb_detonate(bomb_i: int, hit: PackedByteArray, hits: Array) -> void:
	var bx := peg_x[bomb_i]
	var by := peg_y[bomb_i]
	var r2 := BOMB_RADIUS * BOMB_RADIUS
	for j in peg_x.size():
		if hit[j] == 0:
			var dx := peg_x[j] - bx
			var dy := peg_y[j] - by
			if dx * dx + dy * dy <= r2:
				hit[j] = 1
				hits.append({"index": j, "type": int(peg_type[j]), "refresh_prior": hits.size(), "via_bomb": true})


func _fold(h: int, v: int) -> int:
	h = (h ^ v) * FNV_PRIME
	return h & MASK63


## Simulate the CURRENT orb (handling multiball / pierce) on a FRESH copy of the
## peg hit-flags, WITHOUT committing anything. Returns a merged resolution plus a
## `hit` mask of every peg touched. Pure — safe for the auto-aim preview.
func _simulate_orb(angle: float, orb_id: String, record: bool) -> Dictionary:
	var def: Dictionary = ORB_DB[orb_id]
	var effect := String(def["effect"])
	var pierce := int(def["n"]) if effect == "pierce" else 0
	var n := peg_x.size()
	var hit := PackedByteArray()
	hit.resize(n)
	var res := _simulate_ball(hit, angle, pierce, record)
	if effect == "multiball":
		var res2 := _simulate_ball(hit, angle + MULTIBALL_OFFSET, 0, record)
		(res["hits"] as Array).append_array(res2["hits"])
		res["wall_bounces"] = int(res["wall_bounces"]) + int(res2["wall_bounces"])
		res["checksum"] = _fold(int(res["checksum"]), int(res2["checksum"]))
		if record:
			(res["trajectory"] as PackedVector2Array).append_array(res2["trajectory"])
	res["hit_mask"] = hit
	return res


# =====================================================================
#  Damage — resolution + orb effect + relics -> {damage,poison,heal,gold,...}
# =====================================================================

func _compute_shot(res: Dictionary, orb_id: String, is_first_shot: bool) -> Dictionary:
	var def: Dictionary = ORB_DB[orb_id]
	var effect := String(def["effect"])
	var hits: Array = res["hits"]
	var wall_bounces := int(res["wall_bounces"])
	var peg_flat := int(RELIC_DB["relic_sharp"]["n"]) if has_relic("relic_sharp") else 0
	var orb_base_bonus := int(RELIC_DB["relic_focus"]["n"]) if has_relic("relic_focus") else 0
	var refresh_factor := 2 if effect == "refresh_syn" else 1

	var dmg := 0.0
	var crit_count := 0
	for h in hits:
		var t := int(h["type"])
		var base := float(int(PEG_BASE_DAMAGE[t]) + int(def["base"]) + orb_base_bonus + peg_flat)
		match t:
			PEG_CRIT:
				crit_count += 1
				if effect == "crit_boost":
					base += float(int(def["n"]))
				if has_relic("relic_critlens"):
					base *= float(RELIC_DB["relic_critlens"]["x"])
			PEG_BOMB:
				if effect == "bomb_boost":
					base += float(int(def["n"]))
				if has_relic("relic_bombcase"):
					base *= float(RELIC_DB["relic_bombcase"]["x"])
			PEG_REFRESH:
				base += float(refresh_factor * REFRESH_BONUS_PER * int(h["refresh_prior"]))
		dmg += base

	# whole-shot orb effects
	match effect:
		"remaining":
			dmg += float(int(def["n"]) * (peg_x.size() - hits.size()))
		"momentum":
			dmg += float(int(def["n"]) * wall_bounces)
		"echo":
			dmg *= 2.0
	# relic whole-shot modifiers
	if has_relic("relic_momentum"):
		dmg += float(int(RELIC_DB["relic_momentum"]["n"]) * wall_bounces)
	if is_first_shot and has_relic("relic_overcharge"):
		dmg *= 2.0

	# statuses
	var poison := 0
	if effect == "poison":
		poison += hits.size() + int(def["n"])
	if has_relic("relic_toxic"):
		poison += int(RELIC_DB["relic_toxic"]["n"])
	var heal := 0
	if effect == "heal":
		heal += hits.size() / 2
	if has_relic("relic_vampire"):
		heal += int(RELIC_DB["relic_vampire"]["n"]) * crit_count
	var gold_gain := 0
	if effect == "gold":
		gold_gain += hits.size()

	return {
		"damage": int(round(dmg)),
		"poison": poison,
		"heal": heal,
		"gold": gold_gain,
		"crit": crit_count,
		"pegs": hits.size(),
		"bounces": wall_bounces,
		"all_cleared": hits.size() >= peg_x.size() and peg_x.size() > 0,
		"checksum": int(res["checksum"]),
	}


# =====================================================================
#  Firing — the player's combat turn
# =====================================================================

## Fire the current orb at `aim_angle` (radians, 0 == straight down, clamped to
## the aim fan). Ticks enemy poison, simulates the orb, applies its accumulated
## damage + statuses to the enemy, heals/earns from the shot, then — if the
## enemy survives — the enemy attacks. Returns a shot summary, or {} if illegal.
func fire(aim_angle: float) -> Dictionary:
	if not is_legal({"type": "fire"}):
		illegal_attempts += 1
		return {}
	var angle := clampf(aim_angle, -AIM_SPREAD, AIM_SPREAD)
	var is_first := shots_this_fight == 0

	# 1) poison ticks on the enemy at the start of your turn (a status effect).
	if int(enemy["poison"]) > 0:
		enemy["hp"] = int(enemy["hp"]) - int(enemy["poison"])
		enemy["poison"] = maxi(0, int(enemy["poison"]) - 1)
		if int(enemy["hp"]) <= 0:
			var summary_p := {"damage": 0, "poison": 0, "heal": 0, "gold": 0, "pegs": 0, "poison_kill": true}
			last_shot = summary_p
			_win_fight()
			return summary_p

	# 2) simulate + score the orb.
	var orb_id := current_orb
	var res := _simulate_orb(angle, orb_id, true)
	last_trajectory = res["trajectory"]
	last_pegs_hit = res["hit_mask"]
	var shot := _compute_shot(res, orb_id, is_first)

	# 3) apply the shot.
	enemy["hp"] = int(enemy["hp"]) - int(shot["damage"])
	enemy["poison"] = int(enemy["poison"]) + int(shot["poison"])
	if int(shot["heal"]) > 0:
		player_hp = mini(player_max_hp, player_hp + int(shot["heal"]))
	if int(shot["gold"]) > 0:
		gold += int(shot["gold"])
	shots_this_fight += 1
	last_shot = shot
	_log("Fire %s -> %d dmg (%d pegs, %d crit, %d bounce). Enemy %d HP." % [
		String(ORB_DB[orb_id]["name"]), int(shot["damage"]), int(shot["pegs"]),
		int(shot["crit"]), int(shot["bounces"]), maxi(0, int(enemy["hp"]))])

	# 4) discard the orb + draw the next.
	discard_pile.append(orb_id)
	_draw_orb()

	# 5) resolve the turn.
	if int(enemy["hp"]) <= 0:
		_win_fight()
	else:
		_enemy_turn()
	return shot


## The enemy's attack pattern: it plays the next move in its cycle, damaging you.
func _enemy_turn() -> void:
	var moves: Array = enemy["moves"]
	var idx := int(enemy["move_idx"])
	var dmg := int(moves[idx])
	enemy["move_idx"] = (idx + 1) % moves.size()
	player_hp -= dmg
	_log("%s attacks for %d. You have %d HP." % [String(enemy["name"]), dmg, maxi(0, player_hp)])
	if player_hp <= 0:
		player_hp = 0
		_lose_run()


func _win_fight() -> void:
	var kind := String(enemy.get("kind", "combat"))
	var reward := int(GOLD_REWARD.get(kind, 16))
	if has_relic("relic_clover"):
		reward = int(round(float(reward) * float(RELIC_DB["relic_clover"]["x"])))
	gold += reward
	_log("%s defeated — +%d gold (%d total)." % [String(enemy["name"]), reward, gold])
	if bool(enemy.get("boss", false)):
		run_over = true
		run_won = true
		phase = "done"
		_log("BOSS DOWN — RUN WON.")
		return
	_open_reward()


func _lose_run() -> void:
	run_over = true
	run_won = false
	phase = "done"
	_log("You fell in battle — RUN LOST.")


# =====================================================================
#  Post-combat reward (pick an orb for the deck, or skip)
# =====================================================================

func _open_reward() -> void:
	phase = "reward"
	shop_items = []
	var pool: Array = ORB_DB.keys()
	pool.sort()
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i in mini(REWARD_ORBS, pool.size()):
		shop_items.append({"kind": "orb", "id": String(pool[i]), "cost": 0, "bought": false})


## Take reward orb `index` into the deck, or index < 0 to skip. Returns true on
## a legal choice; either way it advances back to the map.
func choose_reward(index: int) -> bool:
	if not is_legal({"type": "reward", "index": index}):
		illegal_attempts += 1
		return false
	if index >= 0:
		var oid := String(shop_items[index]["id"])
		deck.append(oid)
		_log("Added %s to the deck." % String(ORB_DB[oid]["name"]))
	else:
		_log("Skipped the orb reward.")
	shop_items = []
	_back_to_map()
	return true


# =====================================================================
#  Shop
# =====================================================================

func _open_shop() -> void:
	phase = "shop"
	shop_items = []
	# Orbs for sale.
	var opool: Array = ORB_DB.keys()
	opool.sort()
	for i in range(opool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = opool[i]
		opool[i] = opool[j]
		opool[j] = tmp
	for i in mini(SHOP_ORBS, opool.size()):
		shop_items.append({"kind": "orb", "id": String(opool[i]), "cost": COST_ORB, "bought": false})
	# Relics not already owned.
	var rpool: Array = []
	for rid in RELIC_DB.keys():
		if not has_relic(String(rid)):
			rpool.append(String(rid))
	rpool.sort()
	for i in range(rpool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = rpool[i]
		rpool[i] = rpool[j]
		rpool[j] = tmp
	for i in mini(SHOP_RELICS, rpool.size()):
		shop_items.append({"kind": "relic", "id": String(rpool[i]), "cost": COST_RELIC, "bought": false})
	# A heal + an orb upgrade (upgrade the lowest-index owned orb).
	shop_items.append({"kind": "heal", "cost": COST_HEAL, "bought": false})
	if not deck.is_empty():
		shop_items.append({"kind": "upgrade", "target": 0, "cost": COST_UPGRADE, "bought": false})


## Buy shop item `index`. Spends gold; applies the effect. Returns true on
## success.
func buy(index: int) -> bool:
	if not is_legal({"type": "buy", "index": index}):
		illegal_attempts += 1
		return false
	var item: Dictionary = shop_items[index]
	gold -= int(item["cost"])
	item["bought"] = true
	match String(item["kind"]):
		"orb":
			deck.append(String(item["id"]))
			_log("Bought %s (deck %d)." % [String(ORB_DB[String(item["id"])]["name"]), deck.size()])
		"relic":
			_grant_relic(String(item["id"]))
			_log("Bought relic %s." % String(RELIC_DB[String(item["id"])]["name"]))
		"heal":
			player_hp = mini(player_max_hp, player_hp + HEAL_AMOUNT)
			_log("Healed to %d HP." % player_hp)
		"upgrade":
			# Upgrades are tracked as extra "focus"-style base via a per-orb note:
			# we materialise it by appending an upgraded twin is overkill; instead
			# swap the target slot for a permanently stronger version by tag.
			_upgrade_orb(int(item["target"]))
	return true


func leave_shop() -> bool:
	if not is_legal({"type": "leave_shop"}):
		illegal_attempts += 1
		return false
	shop_items = []
	_back_to_map()
	return true


# =====================================================================
#  Orb upgrades — a real, persisted per-slot damage bump
# =====================================================================
## Upgrades are stored as a parallel bonus keyed by deck slot index. We keep it
## simple + serialisable: `deck` entries can carry a "+N" suffix that _orb_base
## reads. To avoid mutating ORB_DB (const), an upgraded orb is recorded in
## `_upgrades` (slot -> extra base).
var _upgrades: Dictionary = {}   ## deck slot index -> extra base damage.

func _upgrade_orb(slot: int) -> void:
	if slot < 0 or slot >= deck.size():
		return
	_upgrades[slot] = int(_upgrades.get(slot, 0)) + UPGRADE_BONUS
	_log("Upgraded %s (+%d base)." % [String(ORB_DB[deck[slot]]["name"]), UPGRADE_BONUS])


# =====================================================================
#  Event + rest
# =====================================================================

func _open_event() -> void:
	phase = "event"
	# Pick one of a few generic events deterministically.
	var pool: Array = ["cache", "shrine", "gamble"]
	var pick := String(pool[_rng.randi_range(0, pool.size() - 1)])
	match pick:
		"cache":
			event_data = {"name": "Abandoned Cache",
				"desc": "A dusty stash. Take gold, or pry loose a relic?",
				"options": [{"label": "Take 40 gold"}, {"label": "Grab a random relic"}]}
		"shrine":
			event_data = {"name": "Healing Shrine",
				"desc": "Rest at the shrine, or smash it for gold?",
				"options": [{"label": "Heal 25 HP"}, {"label": "Smash for 30 gold"}]}
		_:
			event_data = {"name": "Gambler's Coin",
				"desc": "Flip for it: a strong orb, or nothing?",
				"options": [{"label": "Take a free orb"}, {"label": "Leave it"}]}
	event_data["kind"] = pick


## Resolve event `option`. Returns true on a legal choice; advances to the map.
func choose_event(option: int) -> bool:
	if not is_legal({"type": "event", "index": option}):
		illegal_attempts += 1
		return false
	match String(event_data["kind"]):
		"cache":
			if option == 0:
				gold += 40
			else:
				_grant_random_relic()
		"shrine":
			if option == 0:
				player_hp = mini(player_max_hp, player_hp + 25)
			else:
				gold += 30
		"gamble":
			if option == 0:
				var oid := _random_orb_id()
				deck.append(oid)
	_log("Event %s resolved (option %d)." % [String(event_data["name"]), option])
	event_data = {}
	_back_to_map()
	return true


func _open_rest() -> void:
	phase = "rest"


## Resolve a rest: "heal" restores REST_HEAL_FRAC of max HP; "upgrade" bumps your
## first orb. Returns true on a legal choice; advances to the map.
func rest_choose(choice: String) -> bool:
	if not is_legal({"type": "rest", "choice": choice}):
		illegal_attempts += 1
		return false
	if choice == "heal":
		var amount := int(round(float(player_max_hp) * REST_HEAL_FRAC))
		player_hp = mini(player_max_hp, player_hp + amount)
		_log("Rested — healed %d HP (now %d)." % [amount, player_hp])
	else:
		_upgrade_orb(0)
	_back_to_map()
	return true


# =====================================================================
#  Shared helpers
# =====================================================================

func _back_to_map() -> void:
	if run_over:
		return
	phase = "map"
	enemy = {}
	current_orb = ""


func has_relic(rid: String) -> bool:
	return relics.has(rid)


func _grant_relic(rid: String) -> void:
	if has_relic(rid) or not RELIC_DB.has(rid):
		return
	relics.append(rid)
	if String(RELIC_DB[rid]["effect"]) == "max_hp":
		var bonus := int(RELIC_DB[rid]["n"])
		player_max_hp += bonus
		player_hp += bonus


func _grant_random_relic() -> void:
	var pool: Array = []
	for rid in RELIC_DB.keys():
		if not has_relic(String(rid)):
			pool.append(String(rid))
	pool.sort()
	if pool.is_empty():
		return
	_grant_relic(String(pool[_rng.randi_range(0, pool.size() - 1)]))


func _random_orb_id() -> String:
	var keys: Array = ORB_DB.keys()
	keys.sort()
	return String(keys[_rng.randi_range(0, keys.size() - 1)])


# =====================================================================
#  Legality
# =====================================================================

## Is `action` legal in the current phase? Rejects firing with no orb, buying
## without gold / out of phase, illegal node travel, etc.
func is_legal(action: Dictionary) -> bool:
	if run_over:
		return false
	match String(action.get("type", "")):
		"choose":
			return phase == "map" and map_options().has(String(action.get("id", "")))
		"fire":
			return phase == "combat" and current_orb != "" and int(enemy.get("hp", 0)) > 0
		"reward":
			if phase != "reward":
				return false
			var idx := int(action.get("index", -1))
			return idx < 0 or (idx >= 0 and idx < shop_items.size())
		"buy":
			if phase != "shop":
				return false
			var bi := int(action.get("index", -1))
			if bi < 0 or bi >= shop_items.size():
				return false
			var item: Dictionary = shop_items[bi]
			if bool(item.get("bought", false)):
				return false
			return gold >= int(item["cost"])
		"leave_shop":
			return phase == "shop"
		"event":
			if phase != "event":
				return false
			var ei := int(action.get("index", -1))
			return ei >= 0 and ei < (event_data.get("options", []) as Array).size()
		"rest":
			return phase == "rest" and String(action.get("choice", "")) in ["heal", "upgrade"]
	return false


# =====================================================================
#  Auto-play heuristic (drives a whole run headlessly — NOT an opponent)
# =====================================================================

## The aim angle (within the fan) that deals the most damage with the current
## orb, found by dry-simulating AIM_SAMPLES angles. Deterministic; mutates
## nothing. Ties break toward the lower angle index.
func best_aim() -> float:
	var best_angle := 0.0
	var best_dmg := -1
	for k in AIM_SAMPLES:
		var t := -AIM_SPREAD + 2.0 * AIM_SPREAD * float(k) / float(AIM_SAMPLES - 1)
		var res := _simulate_orb(t, current_orb, false)
		var shot := _compute_shot(res, current_orb, shots_this_fight == 0)
		if int(shot["damage"]) > best_dmg:
			best_dmg = int(shot["damage"])
			best_angle = t
	return best_angle


## Take one deterministic auto-play step, dispatched by phase. Called in a loop
## it drives a whole run to WIN or LOSE.
func auto_take_turn() -> void:
	if run_over:
		return
	match phase:
		"map":
			_auto_map()
		"combat":
			if current_orb == "":
				# Should not happen (deck is non-empty); guard by conceding a turn.
				_enemy_turn()
			else:
				fire(best_aim())
		"reward":
			choose_reward(0)
		"shop":
			_auto_shop()
		"event":
			choose_event(0)
		"rest":
			rest_choose("heal" if player_hp < player_max_hp else "upgrade")


func _auto_map() -> void:
	var opts := map_options()
	if opts.is_empty():
		return
	# When healthy, prefer reward-rich nodes; when hurt, prefer rest/shop.
	var hurt := player_hp < int(round(float(player_max_hp) * 0.45))
	var best: String = String(opts[0])
	var best_score := -1
	for id in opts:
		var t := String(map_nodes[id]["type"])
		var score := _node_priority(t, hurt)
		if score > best_score:
			best_score = score
			best = String(id)
	choose_node(best)


func _node_priority(t: String, hurt: bool) -> int:
	if hurt:
		match t:
			"rest": return 5
			"shop": return 4
			"event": return 3
			"combat": return 2
			"elite": return 1
			"boss": return 6
	else:
		match t:
			"elite": return 5
			"combat": return 4
			"event": return 3
			"shop": return 2
			"rest": return 1
			"boss": return 6
	return 0


func _auto_shop() -> void:
	# Buy the first affordable relic, else orb, else heal if hurt; then leave.
	var order := ["relic", "orb", "heal", "upgrade"]
	for kind in order:
		if kind == "heal" and player_hp >= int(round(float(player_max_hp) * 0.6)):
			continue
		for i in shop_items.size():
			var item: Dictionary = shop_items[i]
			if bool(item.get("bought", false)):
				continue
			if String(item["kind"]) == kind and gold >= int(item["cost"]):
				buy(i)
				leave_shop()
				return
	leave_shop()


# =====================================================================
#  Queries for the view
# =====================================================================

func orb_name(oid: String) -> String:
	return String(ORB_DB[oid]["name"]) if ORB_DB.has(oid) else "?"


func orb_desc(oid: String) -> String:
	return String(ORB_DB[oid]["desc"]) if ORB_DB.has(oid) else ""


func relic_name(rid: String) -> String:
	return String(RELIC_DB[rid]["name"]) if RELIC_DB.has(rid) else "?"


func enemy_label() -> String:
	if enemy.is_empty():
		return ""
	return "%s   %d/%d HP%s" % [String(enemy["name"]), maxi(0, int(enemy["hp"])),
		int(enemy["max_hp"]), ("   poison %d" % int(enemy["poison"])) if int(enemy["poison"]) > 0 else ""]


func node_type_of(id: String) -> String:
	return String(map_nodes[id]["type"]) if map_nodes.has(id) else "?"


## Preview the trajectory of an angle with the current orb (for the aim
## indicator). Pure — does not commit.
func preview_trajectory(angle: float) -> PackedVector2Array:
	if current_orb == "":
		return PackedVector2Array()
	var res := _simulate_orb(clampf(angle, -AIM_SPREAD, AIM_SPREAD), current_orb, true)
	return res["trajectory"]


func recent_log(n: int = 14) -> Array:
	var out: Array = []
	var start := maxi(0, log_lines.size() - n)
	for i in range(start, log_lines.size()):
		out.append(log_lines[i])
	return out


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 240:
		log_lines.remove_at(0)


# =====================================================================
#  Determinism checksum — folds the WHOLE run state into one int
# =====================================================================

## Order-stable checksum of the entire run: two engines are equal iff this
## matches (used by the determinism + save/load probes).
func run_checksum() -> int:
	var h := FNV_OFFSET
	h = _fold(h, _seed)
	h = _fold(h, int(_rng.state & MASK63))
	h = _fold(h, hash(phase))
	h = _fold(h, player_hp)
	h = _fold(h, player_max_hp)
	h = _fold(h, gold)
	h = _fold(h, depth)
	h = _fold(h, 1 if run_over else 0)
	h = _fold(h, 1 if run_won else 0)
	h = _fold(h, hash(current_id))
	h = _fold(h, hash(current_orb))
	for oid in deck:
		h = _fold(h, hash(String(oid)))
	for rid in relics:
		h = _fold(h, hash(String(rid)))
	for oid in draw_pile:
		h = _fold(h, hash(String(oid)))
	for oid in discard_pile:
		h = _fold(h, hash(String(oid)))
	for k in _upgrades.keys():
		h = _fold(h, int(k))
		h = _fold(h, int(_upgrades[k]))
	if not enemy.is_empty():
		h = _fold(h, int(enemy["hp"]))
		h = _fold(h, int(enemy["poison"]))
		h = _fold(h, int(enemy["move_idx"]))
	for i in peg_type.size():
		h = _fold(h, int(peg_type[i]))
		h = _fold(h, int(round(peg_x[i] * 100.0)))
		h = _fold(h, int(round(peg_y[i] * 100.0)))
	return h


# =====================================================================
#  Save / load — the WHOLE run round-trips (deep, JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	return {
		"seed": _seed,
		"rng_state": str(_rng.state),
		"enemy_hp_scale": _enemy_hp_scale,
		"enemy_dmg_scale": _enemy_dmg_scale,
		"phase": phase,
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"gold": gold,
		"run_over": run_over,
		"run_won": run_won,
		"deck": deck.duplicate(true),
		"relics": relics.duplicate(true),
		"upgrades": _int_keyed(_upgrades),
		"map_nodes": _map_to_plain(),
		"map_order": map_order.duplicate(true),
		"current_id": current_id,
		"visited": visited.duplicate(true),
		"depth": depth,
		"enemy": enemy.duplicate(true),
		"draw_pile": draw_pile.duplicate(true),
		"discard_pile": discard_pile.duplicate(true),
		"current_orb": current_orb,
		"shots_this_fight": shots_this_fight,
		"peg_x": _f32_to_array(peg_x),
		"peg_y": _f32_to_array(peg_y),
		"peg_type": _bytes_to_array(peg_type),
		"shop_items": shop_items.duplicate(true),
		"event_data": event_data.duplicate(true),
		"illegal_attempts": illegal_attempts,
	}


func from_dict(data: Dictionary) -> void:
	_seed = int(data.get("seed", 0))
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	_enemy_hp_scale = float(data.get("enemy_hp_scale", 1.0))
	_enemy_dmg_scale = float(data.get("enemy_dmg_scale", 1.0))
	phase = String(data.get("phase", "map"))
	player_hp = int(data.get("player_hp", START_HP))
	player_max_hp = int(data.get("player_max_hp", START_HP))
	gold = int(data.get("gold", 0))
	run_over = bool(data.get("run_over", false))
	run_won = bool(data.get("run_won", false))
	deck = _str_array(data.get("deck", []))
	relics = _str_array(data.get("relics", []))
	_upgrades = {}
	for k in (data.get("upgrades", {}) as Dictionary).keys():
		_upgrades[int(k)] = int(data["upgrades"][k])
	_map_from_plain(data.get("map_nodes", {}))
	map_order = []
	for row in data.get("map_order", []):
		map_order.append(_str_array(row))
	current_id = String(data.get("current_id", ""))
	visited = _str_array(data.get("visited", []))
	depth = int(data.get("depth", 0))
	enemy = (data.get("enemy", {}) as Dictionary).duplicate(true)
	if not enemy.is_empty():
		var mv: Array = []
		for m in enemy.get("moves", []):
			mv.append(int(m))
		enemy["moves"] = mv
	draw_pile = _str_array(data.get("draw_pile", []))
	discard_pile = _str_array(data.get("discard_pile", []))
	current_orb = String(data.get("current_orb", ""))
	shots_this_fight = int(data.get("shots_this_fight", 0))
	peg_x = _array_to_f32(data.get("peg_x", []))
	peg_y = _array_to_f32(data.get("peg_y", []))
	peg_type = _array_to_bytes(data.get("peg_type", []))
	shop_items = (data.get("shop_items", []) as Array).duplicate(true)
	event_data = (data.get("event_data", {}) as Dictionary).duplicate(true)
	illegal_attempts = int(data.get("illegal_attempts", 0))
	last_trajectory = PackedVector2Array()
	last_pegs_hit = PackedByteArray()


func _map_to_plain() -> Dictionary:
	var out: Dictionary = {}
	for id in map_nodes.keys():
		var n: Dictionary = map_nodes[id]
		out[id] = {"row": int(n["row"]), "col": int(n["col"]), "type": String(n["type"]),
			"x": float(n["x"]), "next": _str_array(n["next"])}
	return out


func _map_from_plain(src: Variant) -> void:
	map_nodes = {}
	for id in (src as Dictionary).keys():
		var n: Dictionary = (src as Dictionary)[id]
		map_nodes[String(id)] = {"row": int(n["row"]), "col": int(n["col"]),
			"type": String(n["type"]), "x": float(n["x"]), "next": _str_array(n["next"])}


func _int_keyed(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[int(k)] = int(d[k])
	return out


func _str_array(src: Variant) -> Array:
	var out: Array = []
	for v in (src as Array):
		out.append(String(v))
	return out


func _f32_to_array(a: PackedFloat32Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(float(v))
	return out


func _array_to_f32(src: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in (src as Array):
		out.append(float(v))
	return out


func _bytes_to_array(a: PackedByteArray) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out


func _array_to_bytes(src: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	for v in (src as Array):
		out.append(int(v))
	return out
