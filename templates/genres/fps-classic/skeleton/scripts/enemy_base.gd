extends CharacterBody3D
## res://scripts/enemy_base.gd
## Shared enemy chassis (group "enemies", layer 3): capsule body built in
## code, health + the take_hit() contract every weapon path calls, gravity,
## and direct-chase steering with a raycast feeler — when the straight line
## to the player is blocked by world geometry the chase bends 40 degrees
## around it (robust headless: no navigation bake required). Subclasses
## implement _move(delta, player); `active` gates the AI (probe freezes,
## cutscenes) while damage and gravity keep working.

signal died(enemy: CharacterBody3D)
signal damaged(amount: int, cause: String)

@export var max_health := 60
@export var move_speed := 6.0
@export var body_color := Color(0.85, 0.25, 0.2)
@export var gravity := 15.5
## AI gate — inactive enemies stand down but still take damage.
@export var active := true

var health := 0


func _ready() -> void:
	add_to_group(&"enemies")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	health = max_health
	_build_body()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var player := _find_player()
	if active and player and not player.is_dead():
		_move(delta, player)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()


## The damage contract: shotgun pellets, rockets and splash all land here.
func take_hit(damage: int, cause: String) -> void:
	if health <= 0:
		return
	health -= damage
	damaged.emit(damage, cause)
	if health <= 0:
		died.emit(self)
		queue_free()


## Subclasses implement their archetype here (only called while active).
func _move(_delta: float, _player: CharacterBody3D) -> void:
	pass


## Chase direction with a 2m raycast feeler against world geometry: straight
## at the player when clear, bent 40 degrees around a blocker otherwise.
func _chase_direction(player: CharacterBody3D) -> Vector3:
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return Vector3.ZERO
	var dir := to.normalized()
	if not _path_blocked(dir):
		return dir
	var left := dir.rotated(Vector3.UP, 0.7)
	if not _path_blocked(left):
		return left
	var right := dir.rotated(Vector3.UP, -0.7)
	if not _path_blocked(right):
		return right
	return dir


func _path_blocked(dir: Vector3) -> bool:
	var from := global_position + Vector3(0.0, 0.9, 0.0)
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 2.0, 1)
	return not get_world_3d().direct_space_state.intersect_ray(params).is_empty()


func _find_player() -> CharacterBody3D:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return null
	return players[0] as CharacterBody3D


func _build_body() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	capsule.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = capsule
	mesh.position = Vector3(0.0, 0.9, 0.0)
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.8
	shape.shape = capsule_shape
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)
