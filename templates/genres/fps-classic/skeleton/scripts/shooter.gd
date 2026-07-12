extends "res://scripts/enemy_base.gd"
## res://scripts/shooter.gd
## Ranged shooter: holds a preferred band around the player (advances when
## too far, backs off when crowded) and fires a plasma bolt (projectile.gd,
## mask world|player) whenever the cooldown is up and world geometry does not
## block the line of sight. fire_at() is public — the boot probe and scripted
## encounters shoot through the same routine the AI uses.

const PROJECTILE := preload("res://scripts/projectile.gd")

@export var preferred_range := 9.0
@export var fire_cooldown := 1.4
@export var bolt_speed := 16.0
@export var bolt_damage := 8

var _cooldown := 0.6  # spawn grace: never fires the very first frame


func _init() -> void:
	max_health = 40
	move_speed = 4.5
	body_color = Color(0.55, 0.3, 0.8)


func _move(delta: float, player: CharacterBody3D) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := Vector3.ZERO
	if dist > preferred_range + 1.0:
		dir = _chase_direction(player)
	elif dist < preferred_range - 3.0 and dist > 0.001:
		dir = -to.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	if _cooldown == 0.0 and _has_los(player):
		fire_at(player)


## Fire one bolt at the player (the AI's own attack routine).
func fire_at(player: CharacterBody3D) -> void:
	_cooldown = fire_cooldown
	var origin := global_position + Vector3(0.0, 1.4, 0.0)
	var target := player.global_position + Vector3(0.0, 1.2, 0.0)
	var bolt := PROJECTILE.new()
	bolt.direction = (target - origin).normalized()
	bolt.speed = bolt_speed
	bolt.direct_damage = bolt_damage
	bolt.splash_radius = 0.0
	bolt.collision_mask = 1 | 2
	bolt.cause = "bolt"
	bolt.color = Color(0.45, 0.8, 1.0)
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = origin


func _has_los(player: CharacterBody3D) -> bool:
	var from := global_position + Vector3(0.0, 1.4, 0.0)
	var to := player.global_position + Vector3(0.0, 1.2, 0.0)
	var params := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(params).is_empty()
