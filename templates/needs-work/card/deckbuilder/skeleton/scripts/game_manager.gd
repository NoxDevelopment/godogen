extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager") AND the roguelike RUN
## engine. It carries the classic world flags (battles won, unlocks) AND owns
## the whole run: the player's persistent HP / gold / relics / deck, a generated
## branching node MAP across floors, where you are on it, and how combat results
## feed back into the run. Every rule here is pure, seedable, headless-testable
## logic — the map hub and the combat scene only read this state and forward
## clicks, exactly like the tcg-duel engine.
##
## Lives in the "game_manager" + "persistent" groups and implements the
## save_data()/load_data() contract from the NoxDev template ABI, so godotsmith's
## save_system drop-in persists the ENTIRE run (map, position, hp, gold, relics,
## deck) with no extra wiring.

signal run_changed  ## emitted whenever run state moves (map hub listens)

# --- run tuning ------------------------------------------------------------
const NUM_FLOORS := 6            ## floors 0..5; floor 5 is the boss.
const START_MAX_HP := 50
const REST_HEAL_FRACTION := 0.30 ## a campfire restores 30% of max HP.
const STARTING_DECK: Array[String] = [
	"strike", "strike", "strike", "strike", "strike",
	"defend", "defend", "defend", "defend",
	"cleave", "insight", "insight", "surge",
]
## Reward pool — the cards a victory can offer. Every id resolves through the
## combat scene's single-type effect table (attack/block/draw/energy), so adding
## a rarer card = a JSON in cards/ + one entry here (see TEMPLATE.md "How to
## extend"). Kept to the shipped five so the template stays self-contained.
const REWARD_POOL: Array[String] = ["strike", "cleave", "defend", "insight", "surge"]

## Relics — passive run modifiers the combat scene queries each fight. Stacking
## relics (energy/block/heal) may be granted more than once; unique ones once.
const RELICS := {
	"energy_core": {"name": "Energy Core", "desc": "+1 energy each turn.", "stacks": true},
	"iron_plate": {"name": "Iron Plate", "desc": "Start each combat with 5 block.", "stacks": true},
	"vampire_fang": {"name": "Vampire Fang", "desc": "Heal 3 HP whenever you kill the enemy.", "stacks": true},
	"gold_idol": {"name": "Gold Idol", "desc": "+50% gold from combat.", "stacks": false},
}

# --- run state -------------------------------------------------------------
var has_run := false
var run_over := false
var run_won := false
var max_hp := START_MAX_HP
var hp := START_MAX_HP
var gold := 0
var relics: Array[String] = []
var deck: Array[String] = []
## map[f] = Array of node Dictionaries {id:int, floor:int, col:int, type:String,
## next:Array[int]}. nodes = flat id -> node view (rebuilt on load).
var map: Array = []
var nodes: Dictionary = {}
var available: Array[int] = []   ## node ids you may enter next.
var current := -1                ## the node you are resolving (-1 = at the start gate).

# --- legacy flag store (unchanged public API) ------------------------------
var flags: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


# =====================================================================
#  Flags (unchanged — battles_won / unlocks / meta-progression)
# =====================================================================

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func clear_flag(flag: String) -> void:
	flags.erase(flag)


# =====================================================================
#  Run lifecycle
# =====================================================================

## Begin a fresh run. seed == 0 → a random shuffle; any other value gives a
## deterministic map + relic/reward rolls (tests + a fixed showcase).
func new_run(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	has_run = true
	run_over = false
	run_won = false
	max_hp = START_MAX_HP
	hp = START_MAX_HP
	gold = 0
	relics = []
	deck = STARTING_DECK.duplicate()
	current = -1
	_generate_map()
	run_changed.emit()


func is_run_over() -> bool:
	return run_over


## The node currently being resolved, or {} at the start gate / after load.
func current_node() -> Dictionary:
	return nodes.get(current, {})


# =====================================================================
#  Map generation — a connected floor-by-floor DAG, boss at the top
# =====================================================================

func _generate_map() -> void:
	map = []
	nodes = {}
	var next_id := 0
	for f in NUM_FLOORS:
		var width: int
		if f == NUM_FLOORS - 1:
			width = 1                        # the boss is a single node
		elif f == 0:
			width = 2                        # the opening choice
		else:
			width = 2 + (_rng.randi() % 2)   # 2 or 3 branches
		var row: Array = []
		for c in width:
			var node := {
				"id": next_id,
				"floor": f,
				"col": c,
				"type": _pick_type(f),
				"next": ([] as Array),
			}
			nodes[next_id] = node
			row.append(node)
			next_id += 1
		map.append(row)
	_wire_edges()
	available = []
	for n in map[0]:
		available.append(int(n["id"]))
	current = -1


func _pick_type(floor_index: int) -> String:
	if floor_index == NUM_FLOORS - 1:
		return "boss"
	if floor_index == 0:
		return "combat"                       # always open on a fair fight
	var roll := _rng.randi() % 100
	if floor_index == NUM_FLOORS - 2:
		# the floor before the boss: bias toward a heal so a run can prep.
		if roll < 45:
			return "rest"
		if roll < 65:
			return "elite"
		return "combat"
	if roll < 15 and floor_index >= 2:
		return "elite"
	if roll < 40:
		return "event"
	if roll < 55:
		return "rest"
	return "combat"


func _wire_edges() -> void:
	for f in NUM_FLOORS - 1:
		var cur_row: Array = map[f]
		var nxt_row: Array = map[f + 1]
		for cur in cur_row:
			var j := _project_col(int(cur["col"]), cur_row.size(), nxt_row.size())
			_link(cur, nxt_row[j])
			# a branch sometimes forks to an adjacent node on the next floor.
			if nxt_row.size() > 1 and (_rng.randi() % 100) < 45:
				var dir := 1 if (_rng.randi() % 2 == 0) else -1
				var j2 := clampi(j + dir, 0, nxt_row.size() - 1)
				_link(cur, nxt_row[j2])
		# guarantee every next-floor node is reachable (no orphan branch).
		for k in nxt_row.size():
			if not _has_incoming(int(nxt_row[k]["id"]), cur_row):
				var src := _project_col(k, nxt_row.size(), cur_row.size())
				_link(cur_row[src], nxt_row[k])


func _project_col(col: int, from_width: int, to_width: int) -> int:
	if from_width <= 1 or to_width <= 1:
		return 0 if to_width <= 1 else clampi(col, 0, to_width - 1)
	var ratio := float(col) / float(from_width - 1)
	return clampi(int(round(ratio * (to_width - 1))), 0, to_width - 1)


func _link(a: Dictionary, b: Dictionary) -> void:
	var bid := int(b["id"])
	var nxt: Array = a["next"]
	if not nxt.has(bid):
		nxt.append(bid)
		nxt.sort()


func _has_incoming(node_id: int, cur_row: Array) -> bool:
	for cur in cur_row:
		if (cur["next"] as Array).has(node_id):
			return true
	return false


# =====================================================================
#  Traversal — enter a node; combat resolves separately
# =====================================================================

## Enter a reachable node. rest/event resolve immediately (and advance the
## map); combat/elite/boss hand off to the combat scene, which calls
## resolve_combat() when the fight ends. Returns the node dict, or {} if the id
## was not reachable.
func enter_node(node_id: int) -> Dictionary:
	if run_over or not available.has(node_id):
		return {}
	var node: Dictionary = nodes[node_id]
	current = node_id
	match String(node["type"]):
		"rest":
			_rest_heal()
			_advance_from(node)
		"event":
			_resolve_event(node)
			_advance_from(node)
		_:
			pass  # combat/elite/boss: await resolve_combat()
	run_changed.emit()
	return node


func is_combat_node(node: Dictionary) -> bool:
	var t := String(node.get("type", ""))
	return t == "combat" or t == "elite" or t == "boss"


func _advance_from(node: Dictionary) -> void:
	var nxt: Array = node.get("next", [])
	available = []
	for v in nxt:
		available.append(int(v))
	current = -1


func _rest_heal() -> void:
	hp = mini(max_hp, hp + int(ceil(max_hp * REST_HEAL_FRACTION)))


func _resolve_event(node: Dictionary) -> void:
	# A compact treasure/event: mostly gold, occasionally a relic or a small heal.
	var roll := _rng.randi() % 100
	if roll < 45:
		gold += 25 + (int(node["floor"]) * 10)
	elif roll < 70:
		_grant_relic()
	else:
		hp = mini(max_hp, hp + 8)


# =====================================================================
#  Combat feedback — the scene reports the result back into the run
# =====================================================================

## The enemy the current combat node fields, scaled by floor + node kind.
func current_encounter() -> Dictionary:
	var node: Dictionary = current_node()
	var floor_index := int(node.get("floor", 0))
	var t := String(node.get("type", "combat"))
	var base_hp := 26 + floor_index * 8
	var base_atk := 7 + floor_index
	if t == "elite":
		return {"name": "Elite: Warden", "max_hp": int(base_hp * 1.6), "attack": base_atk + 3, "kind": "elite"}
	if t == "boss":
		return {"name": "Boss: The Archivist", "max_hp": 120, "attack": 16, "kind": "boss"}
	return {"name": "Cog-Golem", "max_hp": base_hp, "attack": base_atk, "kind": "combat"}


## Report a finished fight. win + surviving HP feed the run: HP persists, gold
## and relics are earned, the boss ends the run, a loss ends the run.
func resolve_combat(win: bool, hp_remaining: int) -> void:
	var node: Dictionary = current_node()
	if node.is_empty():
		return
	hp = clampi(hp_remaining, 0, max_hp)
	if not win or hp <= 0:
		run_over = true
		run_won = false
		run_changed.emit()
		return
	set_flag("battles_won", int(get_flag("battles_won", 0)) + 1)
	var t := String(node["type"])
	gold += _combat_gold(t)
	if t == "elite":
		_grant_relic()
	if t == "boss":
		_grant_relic()
		run_over = true
		run_won = true
		run_changed.emit()
		return
	_advance_from(node)
	run_changed.emit()


func _combat_gold(node_type: String) -> int:
	var base := 15
	if node_type == "elite":
		base = 35
	elif node_type == "boss":
		base = 100
	if relics.has("gold_idol"):
		base = int(base * 1.5)
	return base + (_rng.randi() % 6)


## Three distinct card choices after a win. The combat scene renders them and
## calls add_card() with the pick (or skips).
func roll_rewards() -> Array[String]:
	var pool := REWARD_POOL.duplicate()
	pool.shuffle()  # uses the global RNG; deterministic under a fixed seed
	var out: Array[String] = []
	for i in mini(3, pool.size()):
		out.append(pool[i])
	return out


func add_card(card_id: String) -> void:
	deck.append(card_id)
	run_changed.emit()


# =====================================================================
#  Relics
# =====================================================================

func _grant_relic() -> void:
	var candidates: Array[String] = []
	for id in RELICS.keys():
		var stacks: bool = RELICS[id]["stacks"]
		if stacks or not relics.has(id):
			candidates.append(id)
	if candidates.is_empty():
		return
	relics.append(candidates[_rng.randi() % candidates.size()])


func relic_bonus_energy() -> int:
	return relics.count("energy_core")


func relic_start_block() -> int:
	return relics.count("iron_plate") * 5


func relic_heal_on_kill() -> int:
	return relics.count("vampire_fang") * 3


# =====================================================================
#  Persistence — the WHOLE run + flags round-trip through save_system
# =====================================================================

func save_data() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"has_run": has_run,
		"run_over": run_over,
		"run_won": run_won,
		"max_hp": max_hp,
		"hp": hp,
		"gold": gold,
		"relics": relics.duplicate(),
		"deck": deck.duplicate(),
		"map": map.duplicate(true),
		"available": available.duplicate(),
		"current": current,
	}


func load_data(data: Dictionary) -> void:
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	has_run = bool(data.get("has_run", false))
	run_over = bool(data.get("run_over", false))
	run_won = bool(data.get("run_won", false))
	max_hp = int(data.get("max_hp", START_MAX_HP))
	hp = int(data.get("hp", max_hp))
	gold = int(data.get("gold", 0))
	relics = []
	for r in data.get("relics", []):
		relics.append(String(r))
	deck = []
	for c in data.get("deck", []):
		deck.append(String(c))
	# rebuild the map + the flat node index, coercing JSON floats back to ints.
	map = []
	nodes = {}
	for row_variant in data.get("map", []):
		var row: Array = []
		for n_variant in (row_variant as Array):
			var n: Dictionary = n_variant
			var nexts: Array[int] = []
			for v in n.get("next", []):
				nexts.append(int(v))
			var node := {
				"id": int(n["id"]),
				"floor": int(n["floor"]),
				"col": int(n["col"]),
				"type": String(n["type"]),
				"next": nexts,
			}
			nodes[int(n["id"])] = node
			row.append(node)
		map.append(row)
	available = []
	for v in data.get("available", []):
		available.append(int(v))
	current = int(data.get("current", -1))
	run_changed.emit()
