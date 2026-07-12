extends Node2D
## res://scripts/main.gd
## Adventure shell: watches which screen-grid room the player stands in and
## snaps the camera + per-room enemy activity on transitions (classic Zelda
## room changes), drives the hearts/keys/item HUD, rolls heart drops when
## enemies die, and emits the boot probe proving the loop headless: key picked
## up, sword kill, locked door opened with the key, room transition fired,
## plate puzzle opened the switch door, the chest granted + equipped the
## boomerang, and a boomerang throw stunned the chaser.

const ROOM_SIZE := Vector2(1152, 648)

@export var heart_drop_chance := 0.5

var _current_coords := Vector2i(999, 999)
var _transitions := -1  # the initial room activation is not a transition
var _rooms := {}
var _rng := RandomNumberGenerator.new()
var _heart_scene: PackedScene = preload("res://scenes/heart_pickup.tscn")

@onready var _player: CharacterBody2D = $Player
@onready var _camera: Camera2D = $Camera2D
@onready var _door_ab: StaticBody2D = $Doors/DoorAB
@onready var _door_bc: StaticBody2D = $Doors/DoorBC
@onready var _key: Area2D = $RoomA/KeyPickup
@onready var _patroller: CharacterBody2D = $RoomA/Patroller
@onready var _plate: Area2D = $RoomB/SwitchPlate
@onready var _chest: StaticBody2D = $RoomC/Chest
@onready var _chaser: CharacterBody2D = $RoomC/Chaser
@onready var _hearts_row: HBoxContainer = $HUD/Margin/Rows/HeartsRow
@onready var _keys_label: Label = $HUD/Margin/Rows/KeysLabel
@onready var _item_icon: ColorRect = $HUD/Margin/Rows/ItemRow/ItemIcon
@onready var _item_label: Label = $HUD/Margin/Rows/ItemRow/ItemLabel
@onready var _hint_label: Label = $HUD/Margin/Rows/HintLabel


func _ready() -> void:
	_rng.randomize()
	for room in get_tree().get_nodes_in_group(&"rooms"):
		_rooms[room.coords] = room
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.destroyed.connect(_on_enemy_destroyed)
	_player.hearts_changed.connect(_on_hearts_changed)
	_player.keys_changed.connect(_on_keys_changed)
	_player.item_changed.connect(_on_item_changed)
	_hint_label.text = "WASD: move   Space: sword   Shift: item   E: open"
	_on_hearts_changed(_player.hearts, _player.max_hearts)
	_on_keys_changed(_player.keys)
	_on_item_changed(_player.equipped_item)
	_update_room()

	_emit_boot_probe.call_deferred()


func _physics_process(_delta: float) -> void:
	_update_room()


## The screen-grid coordinates of the room the player currently stands in.
func current_room() -> Vector2i:
	return _current_coords


## Deterministic heart drops for tests.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func _update_room() -> void:
	var coords := Vector2i(
		floori(_player.global_position.x / ROOM_SIZE.x),
		floori(_player.global_position.y / ROOM_SIZE.y),
	)
	if coords == _current_coords or not _rooms.has(coords):
		return
	if _rooms.has(_current_coords):
		_rooms[_current_coords].set_active(false)
	_current_coords = coords
	var room := _rooms[coords] as Node2D
	room.set_active(true)
	_camera.position = room.position + ROOM_SIZE * 0.5
	_transitions += 1
	GameManager.set_flag("current_room", [coords.x, coords.y])


func _on_enemy_destroyed(_enemy: Node, pos: Vector2) -> void:
	if _rng.randf() >= heart_drop_chance:
		return
	var heart := _heart_scene.instantiate() as Node2D
	add_child(heart)
	heart.global_position = pos


func _on_hearts_changed(current: int, max_hearts: int) -> void:
	while _hearts_row.get_child_count() < max_hearts:
		var heart := ColorRect.new()
		heart.custom_minimum_size = Vector2(22, 18)
		_hearts_row.add_child(heart)
	for i in _hearts_row.get_child_count():
		var heart := _hearts_row.get_child(i) as ColorRect
		heart.visible = i < max_hearts
		heart.color = Color(0.85, 0.2, 0.25) if i < current else Color(0.25, 0.12, 0.14)


func _on_keys_changed(keys: int) -> void:
	_keys_label.text = "Keys: %d" % keys


func _on_item_changed(item_id: String) -> void:
	if item_id.is_empty():
		_item_icon.color = Color(0.3, 0.32, 0.36)
		_item_label.text = "Item: —"
	else:
		_item_icon.color = Color(0.55, 0.85, 0.9)
		_item_label.text = "Item: %s" % item_id.capitalize()


func _emit_boot_probe() -> void:
	for i in 4:
		await get_tree().physics_frame

	# 1. Small key: park the hero on the pickup and let its Area2D fire.
	_player.global_position = _key.global_position
	var key_picked := false
	for i in 30:
		if _player.keys > 0:
			key_picked = true
			break
		await get_tree().physics_frame

	# 2. Sword: attack() is the exact routine the attack action drives — two
	# arc sweeps kill the 2 HP patroller (it moves, so re-park each swing).
	var sword_kill := false
	for i in 10:
		if not is_instance_valid(_patroller):
			sword_kill = true
			break
		_player.global_position = _patroller.global_position + Vector2(-44.0, 0.0)
		_player.face(Vector2.RIGHT)
		_player.attack()
		await get_tree().physics_frame

	# 3. Locked door: try_open is what the door's bump sensor calls; it
	# consumes the small key.
	var locked_door: bool = not _door_ab.is_open \
			and _door_ab.try_open(_player) and _player.keys == 0

	# 4. Room transition: step through the opened doorway into room B and let
	# the room watcher snap the camera + enemy activity across.
	_player.global_position = Vector2(ROOM_SIZE.x + 64.0, ROOM_SIZE.y * 0.5)
	var transitioned := false
	for i in 30:
		if _current_coords == Vector2i(1, 0):
			transitioned = true
			break
		await get_tree().physics_frame

	# 5. Switch puzzle: stand on the pressure plate; it latches and opens the
	# switch door to room C.
	_player.global_position = _plate.global_position
	var switch_solved := false
	for i in 30:
		if _door_bc.is_open:
			switch_solved = true
			break
		await get_tree().physics_frame

	# 6. Treasure chest: walk into room C (second transition) and open it —
	# the boomerang lands in the equipped item slot.
	_player.global_position = _chest.global_position + Vector2(-56.0, 0.0)
	for i in 10:
		if _current_coords == Vector2i(2, 0):
			break
		await get_tree().physics_frame
	_player.face(Vector2.RIGHT)
	_player.interact()
	var chest_item: String = _player.equipped_item \
			if not _player.equipped_item.is_empty() else "none"

	# 7. Boomerang: face the chaser and throw; the flight stuns on contact.
	if is_instance_valid(_chaser):
		_player.global_position = _chaser.global_position + Vector2(-160.0, 0.0)
		_player.face(Vector2.RIGHT)
		_player.use_item()
	var stunned := false
	for i in 90:
		if is_instance_valid(_chaser) and _chaser.is_stunned():
			stunned = true
			break
		await get_tree().physics_frame

	print("DEBUG: zelda-like core loop ready — key_picked=%s sword_kill=%s locked_door=%s room_transition=%s switch_door=%s chest_item=%s boomerang_stun=%s transitions=%d" % [
		key_picked, sword_kill, locked_door, transitioned, switch_solved,
		chest_item, stunned, _transitions,
	])
