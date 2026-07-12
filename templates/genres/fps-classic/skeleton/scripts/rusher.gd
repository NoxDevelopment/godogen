extends "res://scripts/enemy_base.gd"
## res://scripts/rusher.gd
## Melee rusher: sprints straight at the player (feeler-bent around pillars)
## and claws on a cooldown once inside melee_range — the pinky/fiend
## archetype. Its whole attack is player.take_damage(), so armor absorption
## and the death flow come for free from the player contract.

@export var melee_range := 1.7
@export var melee_damage := 12
@export var melee_cooldown := 0.8

var _cooldown := 0.0


func _init() -> void:
	max_health = 60
	move_speed = 7.0
	body_color = Color(0.85, 0.28, 0.2)


func _move(delta: float, player: CharacterBody3D) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length() <= melee_range:
		velocity.x = 0.0
		velocity.z = 0.0
		if _cooldown == 0.0:
			_cooldown = melee_cooldown
			player.take_damage(melee_damage, "melee")
	else:
		var dir := _chase_direction(player)
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
