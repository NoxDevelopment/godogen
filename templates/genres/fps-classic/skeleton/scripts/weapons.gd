extends Node3D
## res://scripts/weapons.gd
## The weapon rack, a child of the first-person camera: two classic arena
## weapons on shared ammo pools — a pellet-spread hitscan shotgun and a
## projectile rocket launcher with splash (see projectile.gd). Hold `fire`
## to shoot (per-weapon cooldowns), Q cycles, 1/2 select directly. fire(),
## switch_to() and add_ammo() are public — pickups, bots and the boot probe
## drive the exact routines the input actions call. The pellet spread RNG is
## seedable (set_seed) so tests are deterministic. A color-coded blockout
## viewmodel shows the held weapon.

signal fired(weapon_id: String)
signal weapon_switched(weapon_id: String)
signal ammo_changed(ammo_type: String, amount: int)

const PROJECTILE := preload("res://scripts/projectile.gd")

const WEAPONS: Array[Dictionary] = [
	{
		"id": "shotgun", "ammo": "shells", "shot_cost": 1, "cooldown": 0.9,
		"pellets": 8, "pellet_damage": 12, "spread_deg": 2.5, "reach": 60.0,
		"color": Color(0.5, 0.55, 0.62),
	},
	{
		"id": "rocket_launcher", "ammo": "rockets", "shot_cost": 1, "cooldown": 0.8,
		"projectile": true,
		"color": Color(0.85, 0.4, 0.18),
	},
]
const MAX_AMMO := {"shells": 40, "rockets": 20}

@export var rocket_speed := 26.0
@export var rocket_direct_damage := 80
@export var rocket_splash_radius := 4.0
@export var rocket_splash_damage := 60
@export var rocket_knockback := 9.0

var current := 0
var ammo := {"shells": 12, "rockets": 5}

var _cooldowns := {}
var _rng := RandomNumberGenerator.new()
var _viewmodel: MeshInstance3D
var _viewmodel_material: StandardMaterial3D

@onready var _camera: Camera3D = get_parent() as Camera3D


func _ready() -> void:
	_rng.randomize()
	_build_viewmodel()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"weapon_next"):
		switch_to((current + 1) % WEAPONS.size())
	elif event.is_action_pressed(&"weapon_1"):
		switch_to(0)
	elif event.is_action_pressed(&"weapon_2"):
		switch_to(1)


func _physics_process(delta: float) -> void:
	for weapon_id in _cooldowns:
		_cooldowns[weapon_id] = maxf(float(_cooldowns[weapon_id]) - delta, 0.0)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed(&"fire"):
		fire()


## Fire the held weapon (the exact routine the `fire` action drives). False
## when the cooldown is still running or the ammo pool is dry.
func fire() -> bool:
	var weapon := WEAPONS[current]
	var weapon_id: String = weapon["id"]
	if float(_cooldowns.get(weapon_id, 0.0)) > 0.0:
		return false
	var ammo_type: String = weapon["ammo"]
	if int(ammo[ammo_type]) < int(weapon["shot_cost"]):
		return false
	ammo[ammo_type] = int(ammo[ammo_type]) - int(weapon["shot_cost"])
	_cooldowns[weapon_id] = float(weapon["cooldown"])
	if bool(weapon.get("projectile", false)):
		_fire_rocket()
	else:
		_fire_hitscan(weapon)
	fired.emit(weapon_id)
	ammo_changed.emit(ammo_type, int(ammo[ammo_type]))
	return true


func switch_to(index: int) -> void:
	var target := clampi(index, 0, WEAPONS.size() - 1)
	if target == current:
		return
	current = target
	_apply_weapon_visual()
	weapon_switched.emit(current_weapon_id())


func current_weapon_id() -> String:
	return WEAPONS[current]["id"]


func current_ammo_type() -> String:
	return WEAPONS[current]["ammo"]


func current_ammo() -> int:
	return int(ammo[current_ammo_type()])


## Pickup entry point: false when the pool is already full (the item is not
## consumed).
func add_ammo(ammo_type: String, amount: int) -> bool:
	if not ammo.has(ammo_type):
		return false
	var cap: int = MAX_AMMO[ammo_type]
	var pool: int = ammo[ammo_type]
	if pool >= cap:
		return false
	ammo[ammo_type] = mini(pool + amount, cap)
	ammo_changed.emit(ammo_type, int(ammo[ammo_type]))
	return true


## Deterministic pellet spread for tests (main.set_seed forwards here).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func _fire_hitscan(weapon: Dictionary) -> void:
	var space := get_world_3d().direct_space_state
	var origin := _camera.global_position
	var cam_basis := _camera.global_transform.basis
	var spread := deg_to_rad(float(weapon["spread_deg"]))
	for i in int(weapon["pellets"]):
		var dir := (-cam_basis.z) \
				.rotated(cam_basis.x, _rng.randf_range(-spread, spread)) \
				.rotated(cam_basis.y, _rng.randf_range(-spread, spread))
		var params := PhysicsRayQueryParameters3D.create(
				origin, origin + dir * float(weapon["reach"]), 1 | 4)
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			continue
		var collider: Object = hit["collider"]
		if collider is Node and (collider as Node).is_in_group(&"enemies"):
			collider.take_hit(int(weapon["pellet_damage"]), "shotgun")


func _fire_rocket() -> void:
	var rocket := PROJECTILE.new()
	rocket.direction = -_camera.global_transform.basis.z
	rocket.speed = rocket_speed
	rocket.direct_damage = rocket_direct_damage
	rocket.splash_radius = rocket_splash_radius
	rocket.splash_damage = rocket_splash_damage
	rocket.knockback = rocket_knockback
	rocket.collision_mask = 1 | 4
	rocket.cause = "rocket"
	rocket.color = Color(1.0, 0.55, 0.15)
	get_tree().current_scene.add_child(rocket)
	rocket.global_position = _camera.global_position + rocket.direction * 0.8


func _build_viewmodel() -> void:
	_viewmodel = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.14, 0.14, 0.55)
	_viewmodel_material = StandardMaterial3D.new()
	box.material = _viewmodel_material
	_viewmodel.mesh = box
	_viewmodel.position = Vector3(0.32, -0.28, -0.55)
	add_child(_viewmodel)
	_apply_weapon_visual()


func _apply_weapon_visual() -> void:
	if _viewmodel_material:
		_viewmodel_material.albedo_color = WEAPONS[current]["color"]
