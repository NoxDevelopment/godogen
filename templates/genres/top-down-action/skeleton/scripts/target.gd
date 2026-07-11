extends StaticBody2D
## res://scripts/target.gd
## Shootable practice dummy. Takes hitscan damage from the player, flashes on
## hit, and frees itself when destroyed. Lives in the "targets" group so the
## arena can count survivors.

signal destroyed(target: Node)

@export var max_health := 3

var health: int

@onready var _visual: Polygon2D = $Visual

var _base_color: Color


func _ready() -> void:
	health = max_health
	_base_color = _visual.color


func take_hit(damage: int, _from: Node) -> void:
	health = maxi(health - damage, 0)
	_visual.color = Color(1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_visual, "color", _base_color, 0.15)
	if health <= 0:
		GameManager.set_flag(
			"targets_destroyed", int(GameManager.get_flag("targets_destroyed", 0)) + 1
		)
		destroyed.emit(self)
		queue_free()
