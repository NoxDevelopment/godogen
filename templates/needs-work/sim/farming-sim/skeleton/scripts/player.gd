extends CharacterBody2D
## res://scripts/player.gd
## Farmer: 4/8-directional top-down movement plus one contextual `interact`
## action (E) on the tile the farmer stands on — grass tills, tilled soil
## plants the equipped crop, a mature crop harvests. The Stardew tool wheel
## collapses to this one action in the skeleton; split it into tool-specific
## actions as tools land.

signal interacted(cell: Vector2i, what: String)

const ACTION_UP := &"move_up"
const ACTION_DOWN := &"move_down"
const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"
const ACTION_INTERACT := &"interact"

@export var move_speed := 200.0
@export var acceleration := 2400.0
@export var friction := 2000.0
## The crop planted on interact (swap per hotbar slot later).
@export var equipped_crop: Crop

@onready var _farm: TileMapLayer = get_parent().get_node(^"Farm") as TileMapLayer


func _physics_process(delta: float) -> void:
	var axis := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	if axis != Vector2.ZERO:
		velocity = velocity.move_toward(axis * move_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

	if Input.is_action_just_pressed(ACTION_INTERACT):
		interact_here()


## The tile the farmer is standing on, in farm coordinates.
func current_cell() -> Vector2i:
	return _farm.local_to_map(_farm.to_local(global_position))


## Contextual action on the current tile: harvest > plant > till.
## Also the probe/AI entry point. Returns what happened.
func interact_here() -> String:
	var cell := current_cell()
	var what := "none"
	if _farm.has_crop(cell) and _farm.harvest(cell) > 0:
		what = "harvest"
	elif _farm.is_tilled(cell) and not _farm.has_crop(cell) \
			and equipped_crop and _farm.plant(cell, equipped_crop):
		what = "plant"
	elif _farm.till(cell):
		what = "till"
	if what != "none":
		interacted.emit(cell, what)
	return what


## "persistent" group contract (see templates ABI).
func save_data() -> Dictionary:
	return {"position": {"x": position.x, "y": position.y}}


func load_data(data: Dictionary) -> void:
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("y"):
		position = Vector2(pos.x, pos.y)
