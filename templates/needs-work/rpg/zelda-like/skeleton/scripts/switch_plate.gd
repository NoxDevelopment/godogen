extends Area2D
## res://scripts/switch_plate.gd
## Latching pressure plate: the first time the player steps on it, it locks
## in the pressed state, opens the door at target_door (door.open()), and
## records itself in GameManager.flags under flag_id — so the puzzle stays
## solved across room transitions and scene reloads. For hold-to-open plates,
## wire body_exited to a close() on the door instead of latching.

signal pressed

@export var target_door: NodePath
@export var flag_id := ""

var is_pressed := false

@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if not flag_id.is_empty() and GameManager.get_flag(flag_id):
		_latch()


## Press the plate (what the player's touch drives). Idempotent once latched.
func press() -> void:
	if not is_pressed:
		_latch()


func _latch() -> void:
	is_pressed = true
	_visual.color = Color(0.35, 0.7, 0.4)
	if not flag_id.is_empty():
		GameManager.set_flag(flag_id)
	var door := get_node_or_null(target_door)
	if door != null and door.has_method("open"):
		door.open()
	pressed.emit()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player"):
		press()
