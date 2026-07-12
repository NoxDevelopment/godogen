extends Node2D
## res://scripts/enemy.gd
## Pooled swarm enemy: pure data + a blockout visual. Movement and contact
## damage are driven by the spawner's single swarm loop (enemy_spawner.gd) —
## no physics body, no per-enemy _physics_process — which is what keeps 200+
## of these cheap. Implements the house take_hit(damage, from) contract;
## death emits `killed` and the spawner returns the node to its pool.

signal killed(enemy: Node2D)

var max_health := 2
var health := 2
var speed := 70.0
var damage := 1
var contact_cd_left := 0.0
var active := false

var _base_color: Color

@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	_base_color = _visual.color


## Reset a fresh-or-pooled enemy into the swarm at `pos`.
func activate(pos: Vector2, hp: int, spd: float, dmg: int) -> void:
	global_position = pos
	max_health = hp
	health = hp
	speed = spd
	damage = dmg
	contact_cd_left = 0.0
	active = true
	visible = true
	_visual.color = _base_color


func deactivate() -> void:
	active = false
	visible = false


func take_hit(hit_damage: int, _from: Node) -> void:
	if not active:
		return
	health = maxi(health - hit_damage, 0)
	_visual.color = Color(1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_visual, "color", _base_color, 0.15)
	if health <= 0:
		killed.emit(self)
