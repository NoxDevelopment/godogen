extends "res://scripts/enemy_base.gd"
## res://scripts/chaser.gd
## Chaser archetype: runs straight at the player while it is inside
## aggro_range (rooms are open blockouts, so no pathfinding is needed — add a
## NavigationAgent2D per the top-down-action enemy if your rooms grow
## obstacles). Touch damage, sword-killable and boomerang-stunnable via the
## shared chassis.

@export var aggro_range := 700.0


func _move(_delta: float, player: Node2D) -> void:
	if player == null \
			or global_position.distance_to(player.global_position) > aggro_range:
		velocity = Vector2.ZERO
		return
	velocity = (player.global_position - global_position).normalized() * move_speed
