extends StaticBody2D
## res://scripts/door.gd
## Dungeon door: a StaticBody2D blocking the doorway gap between two rooms.
## LOCKED opens when a player carrying a small key bumps it (the Sensor area
## drives try_open, which consumes the key — bump it again after finding one).
## SWITCH only opens via open(), wired from a pressure plate / switch.
## PASSAGE opens on first touch. Standing open is written to
## GameManager.flags under flag_id so the state survives room transitions and
## scene reloads (the door re-opens itself in _ready).

signal opened

enum Kind { PASSAGE, LOCKED, SWITCH }

@export var kind: Kind = Kind.LOCKED
## GameManager flag recording that this door stands open. Required in practice
## — leave empty only for doors that should re-lock on every boot.
@export var flag_id := ""

var is_open := false

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _visual: Polygon2D = $Visual
@onready var _sensor: Area2D = $Sensor


func _ready() -> void:
	match kind:
		Kind.LOCKED:
			_visual.color = Color(0.85, 0.68, 0.25)
		Kind.SWITCH:
			_visual.color = Color(0.4, 0.55, 0.85)
		Kind.PASSAGE:
			_visual.color = Color(0.45, 0.34, 0.24)
	_sensor.body_entered.connect(_on_sensor_body_entered)
	if not flag_id.is_empty() and GameManager.get_flag(flag_id):
		_set_open(true)


## The bump routine (what the Sensor calls when the player touches the door).
## Returns whether the door is open afterwards.
func try_open(by: Node) -> bool:
	if is_open:
		return true
	match kind:
		Kind.PASSAGE:
			_set_open(true)
		Kind.LOCKED:
			if by != null and by.has_method("use_key") and by.use_key():
				_set_open(true)
		Kind.SWITCH:
			pass  # switch doors only open via open()
	return is_open


## Unconditional open — what pressure plates and switches call.
func open() -> void:
	if not is_open:
		_set_open(true)


func _set_open(value: bool) -> void:
	is_open = value
	_shape.set_deferred(&"disabled", value)
	_visual.visible = not value
	if value:
		if not flag_id.is_empty():
			GameManager.set_flag(flag_id)
		opened.emit()


func _on_sensor_body_entered(body: Node) -> void:
	if body.is_in_group(&"player"):
		try_open(body)
