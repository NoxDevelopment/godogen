extends Node3D
## res://scripts/projectile.gd
## Shared straight-flight projectile for both sides: the player's rockets
## (splash + knockback, mask world|enemies) and the shooter's plasma bolts
## (direct hit only, mask world|player). Flight is a per-physics-frame ray
## sweep from the previous position to the next — no physics body, so it is
## robust headless and never tunnels. Direct hits damage whatever the ray
## found (enemies via take_hit, the player via take_damage); a splash_radius
## > 0 adds distance-falloff area damage around the impact and shoves the
## player (self-splash at self_splash_factor = the rocket jump). The spawner
## configures the exported fields, then adds it to the scene.

signal exploded(position: Vector3)

@export var speed := 26.0
@export var direct_damage := 60
## 0 = no splash (plain bolt).
@export var splash_radius := 0.0
@export var splash_damage := 0
## Player shove at the splash center, m/s (scaled by distance falloff).
@export var knockback := 9.0
## Fraction of splash damage the owner eats from their own rocket.
@export var self_splash_factor := 0.5
@export var lifetime := 5.0
@export var color := Color(1.0, 0.55, 0.15)

var direction := Vector3.FORWARD
var collision_mask := 1
var cause := "rocket"

var _age := 0.0


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	sphere.material = material
	mesh.mesh = sphere
	add_child(mesh)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	var from := global_position
	var to := from + direction * speed * delta
	var params := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		global_position = to
		return
	_impact(hit["position"], hit["collider"])


func _impact(point: Vector3, collider: Object) -> void:
	if collider is Node:
		var node := collider as Node
		if node.is_in_group(&"enemies"):
			node.take_hit(direct_damage, cause)
		elif node.is_in_group(&"player"):
			node.take_damage(direct_damage, cause)
	if splash_radius > 0.0:
		_splash(point, collider)
	exploded.emit(point)
	queue_free()


func _splash(point: Vector3, direct_target: Object) -> void:
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy == direct_target:
			continue
		var dist: float = (enemy.global_position - point).length()
		if dist <= splash_radius:
			enemy.take_hit(int(splash_damage * (1.0 - dist / splash_radius)), cause)
	for player in get_tree().get_nodes_in_group(&"player"):
		if player == direct_target:
			continue
		var dist: float = (player.global_position - point).length()
		if dist > splash_radius:
			continue
		var falloff := 1.0 - dist / splash_radius
		var damage := int(splash_damage * falloff * self_splash_factor)
		if damage > 0:
			player.take_damage(damage, cause)
		var away: Vector3 = player.global_position + Vector3.UP * 0.5 - point
		player.apply_knockback(away.normalized() * knockback * falloff)
