extends Node3D
## res://scripts/party.gd
## The party IS the camera (groups "player", "persistent"): a Node3D holding
## the first-person Camera3D + torch, moved in discrete grid steps
## (forward/back/strafe) and 90-degree turns, each smoothed with a short
## tween — the classic Lands of Lore / Eye of the Beholder illusion. Three
## members ride in it (two front-row melee, one back-row caster): each has
## HP/MP, a per-member attack cooldown, and the front row soaks enemy melee
## (the back row is only exposed once both fronts are down). Movement is
## pure grid logic against dungeon.gd — walking into a door bumps it open
## (locked doors consume a key), stepping onto a pickup collects it, and
## interact pulls the lever ahead. turn(), try_step(), warp_to(), attack(),
## use_potion(), interact() and take_enemy_hit() are public — the HUD
## buttons, hotkeys and the boot probe all drive the same routines.

signal message(text: String)
signal member_changed(index: int)
signal inventory_changed(keys: int, potions: int)
signal facing_changed(facing: int)
signal moved(cell: Vector2i)
signal party_defeated

## Facing 0..3 = N/E/S/W; DIRS[facing] is the grid step it maps to.
const DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]
const DIR_NAMES: Array[String] = ["N", "E", "S", "W"]

## The three-member roster: two front-row fighters (range 1 melee) and a
## back-row caster whose spark bolt reaches 3 cells down the facing line and
## costs MP. Adding a member = one more entry here + a portrait panel.
const MEMBER_DEFS: Array[Dictionary] = [
	{"name": "Aiden", "row": "front", "max_hp": 40, "max_mp": 4,
			"damage": 12, "cooldown": 1.2, "range": 1, "mp_cost": 0},
	{"name": "Brona", "row": "front", "max_hp": 38, "max_mp": 6,
			"damage": 10, "cooldown": 1.0, "range": 1, "mp_cost": 0},
	{"name": "Cael", "row": "back", "max_hp": 30, "max_mp": 16,
			"damage": 14, "cooldown": 1.8, "range": 3, "mp_cost": 2},
]

@export var step_time := 0.22
@export var turn_time := 0.18
@export var potion_heal := 25
## Seconds between repeated bump messages while holding a direction into a
## blocked cell (scaled by cooldown_scale like the attack cooldowns).
@export var bump_message_cooldown := 0.45
## Members regain 1 MP every this many seconds.
@export var mp_regen_interval := 4.0

## Multiplies every member cooldown + the bump guard — the boot probe
## compresses time through this (the mechanics are rate-independent).
var cooldown_scale := 1.0

var cell := Vector2i.ZERO
var facing := 0
var keys := 0
var potions := 0
var members: Array[Dictionary] = []

var _cooldowns: Array[float] = [0.0, 0.0, 0.0]
var _mp_clock := 0.0
var _bump_guard := 0.0
var _busy := false
var _defeated := false

@onready var _dungeon: Node3D = $"../Dungeon"


func _ready() -> void:
	for def in MEMBER_DEFS:
		members.append({
			"name": def["name"], "row": def["row"],
			"hp": def["max_hp"], "max_hp": def["max_hp"],
			"mp": def["max_mp"], "max_mp": def["max_mp"],
			"damage": def["damage"], "cooldown": def["cooldown"],
			"range": def["range"], "mp_cost": def["mp_cost"],
		})
	warp_to(_dungeon.start_cell, 0)


func _physics_process(delta: float) -> void:
	for i in _cooldowns.size():
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
	_bump_guard = maxf(_bump_guard - delta, 0.0)
	_tick_mp_regen(delta)
	if _defeated or _busy:
		return
	if Input.is_action_pressed(&"turn_left"):
		turn(-1)
	elif Input.is_action_pressed(&"turn_right"):
		turn(1)
	elif Input.is_action_pressed(&"move_forward"):
		try_step(0)
	elif Input.is_action_pressed(&"move_back"):
		try_step(2)
	elif Input.is_action_pressed(&"strafe_left"):
		try_step(3)
	elif Input.is_action_pressed(&"strafe_right"):
		try_step(1)


func _unhandled_input(event: InputEvent) -> void:
	if _defeated:
		return
	if event.is_action_pressed(&"attack_1"):
		attack(0)
	elif event.is_action_pressed(&"attack_2"):
		attack(1)
	elif event.is_action_pressed(&"attack_3"):
		attack(2)
	elif event.is_action_pressed(&"use_potion"):
		use_potion()
	elif event.is_action_pressed(&"interact"):
		interact()


## 90-degree turn: dir -1 = left, +1 = right. Tweened yaw, shortest way round.
func turn(dir: int) -> void:
	if _busy or _defeated:
		return
	facing = posmod(facing + dir, 4)
	_busy = true
	var target := -facing * PI / 2.0
	var diff := wrapf(target - rotation.y, -PI, PI)
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", rotation.y + diff, turn_time)
	tween.tween_callback(_end_turn)
	facing_changed.emit(facing)


## One grid step relative to facing: 0 forward, 1 right, 2 back, 3 left.
## Walking into a door bumps it (locked doors consume a key) instead of
## moving; walls and enemies block. Returns true when the step happened.
func try_step(rel: int) -> bool:
	if _busy or _defeated:
		return false
	var dir := posmod(facing + rel, 4)
	var target := cell + DIRS[dir]
	if not _dungeon.is_open(target):
		if _bump_guard <= 0.0:
			_bump_guard = bump_message_cooldown * cooldown_scale
			_dungeon.try_bump(target, self)
		return false
	if _dungeon.occupant(target) != null:
		if _bump_guard <= 0.0:
			_bump_guard = bump_message_cooldown * cooldown_scale
			message.emit("Something blocks the way!")
		return false
	cell = target
	_dungeon.party_cell = cell
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "position", _dungeon.world_pos(cell), step_time)
	tween.tween_callback(_end_move)
	return true


## Instant placement (level design, save restore, the boot probe).
func warp_to(target: Vector2i, new_facing: int) -> void:
	cell = target
	facing = posmod(new_facing, 4)
	position = _dungeon.world_pos(cell)
	rotation.y = -facing * PI / 2.0
	_dungeon.party_cell = cell
	_dungeon.collect_pickup(cell, self)
	facing_changed.emit(facing)
	moved.emit(cell)


## Member attack button (portrait click or hotkey 1/2/3). Front-row members
## hit the cell straight ahead; the back-row caster's bolt scans up to
## `range` open cells down the facing line and costs MP on a cast.
func attack(index: int) -> bool:
	if _defeated or index < 0 or index >= members.size():
		return false
	var member := members[index]
	if member["hp"] <= 0 or _cooldowns[index] > 0.0:
		return false
	if member["mp_cost"] > 0 and member["mp"] < member["mp_cost"]:
		message.emit("%s is out of mana!" % member["name"])
		return false
	_cooldowns[index] = member["cooldown"] * cooldown_scale
	var target: Node3D = null
	var scan := cell
	for i in int(member["range"]):
		scan += DIRS[facing]
		if not _dungeon.is_open(scan):
			break
		target = _dungeon.occupant(scan)
		if target != null:
			break
	if target == null:
		message.emit("%s swings at empty air." % member["name"])
		return false
	if member["mp_cost"] > 0:
		member["mp"] -= member["mp_cost"]
		message.emit("%s hurls a spark at the %s for %d!" % [
			member["name"], target.enemy_name, member["damage"],
		])
	else:
		message.emit("%s strikes the %s for %d!" % [
			member["name"], target.enemy_name, member["damage"],
		])
	member_changed.emit(index)
	target.take_hit(int(member["damage"]), String(member["name"]))
	return true


## Drink a potion: heals the alive member with the lowest HP.
func use_potion() -> bool:
	if _defeated or potions <= 0:
		return false
	var target := -1
	for i in members.size():
		var member := members[i]
		if member["hp"] <= 0 or member["hp"] >= member["max_hp"]:
			continue
		if target == -1 or member["hp"] < members[target]["hp"]:
			target = i
	if target == -1:
		message.emit("No one needs a potion right now.")
		return false
	potions -= 1
	var member := members[target]
	var healed: int = mini(int(member["hp"]) + potion_heal, int(member["max_hp"]))
	message.emit("%s drinks a potion (+%d HP)." % [
		member["name"], healed - int(member["hp"]),
	])
	member["hp"] = healed
	member_changed.emit(target)
	inventory_changed.emit(keys, potions)
	return true


## Pull the lever in the cell ahead (or the one underfoot).
func interact() -> bool:
	if _defeated:
		return false
	if _dungeon.pull_lever_at(cell + DIRS[facing]):
		return true
	return _dungeon.pull_lever_at(cell)


## Enemy melee lands here: the first alive front-row member takes it — the
## back row is only exposed once both fronts are down (row semantics).
func take_enemy_hit(damage: int, attacker: String) -> void:
	if _defeated:
		return
	var target := -1
	for i in members.size():
		if members[i]["row"] == "front" and members[i]["hp"] > 0:
			target = i
			break
	if target == -1:
		for i in members.size():
			if members[i]["hp"] > 0:
				target = i
				break
	if target == -1:
		return
	var member := members[target]
	member["hp"] = maxi(int(member["hp"]) - damage, 0)
	message.emit("The %s claws %s for %d!" % [attacker, member["name"], damage])
	member_changed.emit(target)
	if member["hp"] == 0:
		message.emit("%s falls!" % member["name"])
		if _all_down():
			_defeated = true
			party_defeated.emit()


func can_attack(index: int) -> bool:
	if index < 0 or index >= members.size():
		return false
	var member := members[index]
	return member["hp"] > 0 and _cooldowns[index] <= 0.0 \
			and (member["mp_cost"] == 0 or member["mp"] >= member["mp_cost"])


func gain_key() -> void:
	keys += 1
	inventory_changed.emit(keys, potions)


func spend_key() -> void:
	keys = maxi(keys - 1, 0)
	inventory_changed.emit(keys, potions)


func gain_potion() -> void:
	potions += 1
	inventory_changed.emit(keys, potions)


func facing_name() -> String:
	return DIR_NAMES[facing]


func is_busy() -> bool:
	return _busy


func is_defeated() -> bool:
	return _defeated


## "persistent" group contract (see templates ABI): return the state to save.
func save_data() -> Dictionary:
	return {
		"cell": {"x": cell.x, "y": cell.y},
		"facing": facing,
		"keys": keys,
		"potions": potions,
		"members": members.duplicate(true),
	}


func load_data(data: Dictionary) -> void:
	keys = int(data.get("keys", keys))
	potions = int(data.get("potions", potions))
	var saved_members: Array = data.get("members", [])
	for i in mini(saved_members.size(), members.size()):
		members[i] = saved_members[i].duplicate(true)
		member_changed.emit(i)
	var saved_cell: Dictionary = data.get("cell", {})
	if saved_cell.has("x") and saved_cell.has("y"):
		warp_to(Vector2i(int(saved_cell.x), int(saved_cell.y)),
				int(data.get("facing", facing)))
	inventory_changed.emit(keys, potions)


func _all_down() -> bool:
	for member in members:
		if member["hp"] > 0:
			return false
	return true


func _end_move() -> void:
	_busy = false
	_dungeon.collect_pickup(cell, self)
	moved.emit(cell)


func _end_turn() -> void:
	_busy = false


func _tick_mp_regen(delta: float) -> void:
	_mp_clock += delta
	if _mp_clock < mp_regen_interval:
		return
	_mp_clock -= mp_regen_interval
	for i in members.size():
		var member := members[i]
		if member["hp"] > 0 and member["mp"] < member["max_mp"]:
			member["mp"] = int(member["mp"]) + 1
			member_changed.emit(i)
