extends CharacterBody2D
## res://scripts/player.gd
## Zelda-like hero: 4-directional top-down movement (the dominant input axis
## wins — no diagonals, classic grid feel), a melee sword-arc sweep
## (distance + angle hit-test against the "enemies" group), an item button
## driving the equipped-item slot (ships the boomerang), an interact button for
## chests, hearts with a post-hit grace window, and small-key / item inventory.
## attack(), use_item(), interact() and face() are public — bots, cutscenes and
## the boot probe drive the hero through the exact routines the input actions
## call.

signal hearts_changed(current: int, max_hearts: int)
signal keys_changed(keys: int)
signal item_changed(item_id: String)
signal attacked(dir: Vector2)
signal died

const ACTION_UP := &"move_up"
const ACTION_DOWN := &"move_down"
const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"
const ACTION_ATTACK := &"attack"
const ACTION_ITEM := &"item"
const ACTION_INTERACT := &"interact"

const BODY_COLOR := Color(0.35, 0.72, 0.38)

@export var move_speed := 300.0
@export var max_hearts := 3
@export var sword_damage := 1
## Reach of the sword sweep, in pixels.
@export var sword_range := 60.0
## Full width of the sweep, centered on the facing direction.
@export var sword_arc_degrees := 130.0
@export var sword_cooldown := 0.35
## How close an "interactables" node must be for interact() to reach it.
@export var interact_range := 60.0
## Seconds of invulnerability after taking a hit.
@export var hurt_grace := 0.8

var hearts: int
var keys := 0
var equipped_item := ""
var inventory: Array[String] = []
var facing := Vector2.DOWN
var _spawn_position: Vector2
var _sword_cd_left := 0.0
var _swing_left := 0.0
var _grace_left := 0.0

@onready var _body_visual: Polygon2D = $Body
@onready var _facing_marker: Polygon2D = $FacingMarker
@onready var _sword_arc: Polygon2D = $SwordArc
@onready var _boomerang: Node2D = $Boomerang


func _ready() -> void:
	hearts = max_hearts
	_spawn_position = position
	_sword_arc.visible = false
	hearts_changed.emit(hearts, max_hearts)
	keys_changed.emit(keys)
	item_changed.emit(equipped_item)


func _physics_process(delta: float) -> void:
	_sword_cd_left = maxf(_sword_cd_left - delta, 0.0)
	_grace_left = maxf(_grace_left - delta, 0.0)
	if _swing_left > 0.0:
		_swing_left -= delta
		if _swing_left <= 0.0:
			_sword_arc.visible = false

	# 4-directional movement: the dominant axis wins, and moving sets facing.
	var axis := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	var dir := Vector2.ZERO
	if axis != Vector2.ZERO:
		dir = Vector2(signf(axis.x), 0.0) if absf(axis.x) >= absf(axis.y) \
				else Vector2(0.0, signf(axis.y))
		facing = dir
	velocity = dir * move_speed
	move_and_slide()
	_facing_marker.rotation = facing.angle()

	if Input.is_action_just_pressed(ACTION_ATTACK) and _sword_cd_left <= 0.0:
		attack()
	if Input.is_action_just_pressed(ACTION_ITEM):
		use_item()
	if Input.is_action_just_pressed(ACTION_INTERACT):
		interact()


## One sword-arc sweep in the facing direction: every "enemies" node within
## sword_range and inside the arc takes sword_damage. This is the exact routine
## the attack action drives (the cooldown lives in _physics_process).
func attack() -> void:
	_sword_cd_left = sword_cooldown
	_sword_arc.rotation = facing.angle()
	_sword_arc.visible = true
	_swing_left = 0.15
	var half_arc := deg_to_rad(sword_arc_degrees * 0.5)
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if not (enemy is Node2D) or not enemy.has_method("take_hit"):
			continue
		var to: Vector2 = (enemy as Node2D).global_position - global_position
		if to.length() <= sword_range and absf(facing.angle_to(to)) <= half_arc:
			enemy.take_hit(sword_damage, self)
	attacked.emit(facing)


## Use the equipped item in the facing direction. Returns true if the item
## actually fired (the boomerang no-ops while a throw is still in flight).
func use_item() -> bool:
	match equipped_item:
		"boomerang":
			return _boomerang.throw_from(self, facing)
	return false


## Interact with the nearest "interactables" node in range (chests, and any
## node implementing interact(by) -> bool). Returns true if something reacted.
func interact() -> bool:
	for node in get_tree().get_nodes_in_group(&"interactables"):
		if not (node is Node2D) or not node.has_method("interact"):
			continue
		if (node as Node2D).global_position.distance_to(global_position) <= interact_range:
			if node.interact(self):
				return true
	return false


## Snap facing to the cardinal direction closest to `dir`.
func face(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	facing = Vector2(signf(dir.x), 0.0) if absf(dir.x) >= absf(dir.y) \
			else Vector2(0.0, signf(dir.y))
	_facing_marker.rotation = facing.angle()


func gain_key(amount := 1) -> void:
	keys += amount
	keys_changed.emit(keys)


## Consume one small key. Locked doors call this; returns false when empty.
func use_key() -> bool:
	if keys <= 0:
		return false
	keys -= 1
	keys_changed.emit(keys)
	return true


## Grant an item (chest loot) and equip it in the item slot.
func give_item(item_id: String) -> void:
	if not inventory.has(item_id):
		inventory.append(item_id)
	equipped_item = item_id
	item_changed.emit(equipped_item)


func heal(amount: int) -> void:
	hearts = mini(hearts + amount, max_hearts)
	hearts_changed.emit(hearts, max_hearts)


func take_hit(damage: int, _from: Node) -> void:
	if _grace_left > 0.0:
		return
	_grace_left = hurt_grace
	hearts = maxi(hearts - damage, 0)
	hearts_changed.emit(hearts, max_hearts)
	_flash(Color(1.0, 0.35, 0.35))
	if hearts <= 0:
		_die()


## "persistent" group contract (see templates ABI): return the state to save.
func save_data() -> Dictionary:
	return {
		"position": {"x": position.x, "y": position.y},
		"hearts": hearts,
		"max_hearts": max_hearts,
		"keys": keys,
		"equipped_item": equipped_item,
		"inventory": inventory.duplicate(),
	}


func load_data(data: Dictionary) -> void:
	max_hearts = int(data.get("max_hearts", max_hearts))
	hearts = int(data.get("hearts", max_hearts))
	keys = int(data.get("keys", keys))
	equipped_item = str(data.get("equipped_item", equipped_item))
	inventory.assign(data.get("inventory", inventory))
	hearts_changed.emit(hearts, max_hearts)
	keys_changed.emit(keys)
	item_changed.emit(equipped_item)
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("y"):
		position = Vector2(pos.x, pos.y)


func _flash(color: Color) -> void:
	_body_visual.color = color
	var tween := create_tween()
	tween.tween_property(_body_visual, "color", BODY_COLOR, 0.25)


func _die() -> void:
	died.emit()
	# Classic adventure death: back to the spawn point with full hearts —
	# keys, items and world flags are kept.
	position = _spawn_position
	velocity = Vector2.ZERO
	hearts = max_hearts
	_grace_left = hurt_grace
	hearts_changed.emit(hearts, max_hearts)
