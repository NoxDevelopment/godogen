extends Node3D
## res://scripts/arena.gd
## Code-built arena room (one StaticBody3D on layer 1 "world"): a 40x40m
## floor, 5m perimeter walls, four cover pillars, and a ramp up to a raised
## platform along the north wall (the rocket-ammo perch). Everything is
## BoxMesh + BoxShape3D pairs from _add_box(), so replacing the blockout with
## real level geometry means swapping the builders — gameplay only cares
## about layer 1.

const ARENA_SIZE := 40.0
const WALL_HEIGHT := 5.0

const FLOOR_COLOR := Color(0.25, 0.26, 0.3)
const WALL_COLOR := Color(0.35, 0.36, 0.42)
const PILLAR_COLOR := Color(0.45, 0.33, 0.3)
const DECK_COLOR := Color(0.3, 0.38, 0.34)


func _ready() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Floor (top face at y = 0).
	_add_box(body, Vector3(0.0, -0.5, 0.0),
			Vector3(ARENA_SIZE, 1.0, ARENA_SIZE), FLOOR_COLOR)

	# Perimeter walls.
	var half := ARENA_SIZE * 0.5
	var wall_y := WALL_HEIGHT * 0.5
	_add_box(body, Vector3(0.0, wall_y, -half),
			Vector3(ARENA_SIZE, WALL_HEIGHT, 1.0), WALL_COLOR)
	_add_box(body, Vector3(0.0, wall_y, half),
			Vector3(ARENA_SIZE, WALL_HEIGHT, 1.0), WALL_COLOR)
	_add_box(body, Vector3(-half, wall_y, 0.0),
			Vector3(1.0, WALL_HEIGHT, ARENA_SIZE), WALL_COLOR)
	_add_box(body, Vector3(half, wall_y, 0.0),
			Vector3(1.0, WALL_HEIGHT, ARENA_SIZE), WALL_COLOR)

	# Cover pillars.
	for x in [-7.0, 7.0]:
		for z in [-7.0, 7.0]:
			_add_box(body, Vector3(x, 2.25, z),
					Vector3(2.0, 4.5, 2.0), PILLAR_COLOR)

	# Raised platform against the north wall + the ramp up to it.
	_add_box(body, Vector3(0.0, 2.95, -17.0),
			Vector3(10.0, 0.5, 6.0), DECK_COLOR)
	_add_box(body, Vector3(0.0, 1.35, -9.5),
			Vector3(4.0, 0.5, 9.6), DECK_COLOR, 0.342)


func _add_box(parent: StaticBody3D, pos: Vector3, size: Vector3,
		color: Color, tilt_x := 0.0) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation.x = tilt_x
	parent.add_child(mesh)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = pos
	collider.rotation.x = tilt_x
	parent.add_child(collider)
