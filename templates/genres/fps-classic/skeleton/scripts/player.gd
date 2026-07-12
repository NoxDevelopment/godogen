extends CharacterBody3D
## res://scripts/player.gd
## Quake-ish first-person controller (groups "player", "persistent"):
## WASD + mouselook (click captures the mouse, `pause` releases it), sprint,
## and the classic run-and-gun movement core — ground friction + Quake-style
## acceleration, a small air-speed cap that gives real air control and
## strafe-jump gain, and held-jump auto-hop that skips the landing-frame
## friction so bunny-hops keep their speed. Health + armor (armor absorbs a
## fraction of every hit while it lasts), rocket-splash knockback for rocket
## jumps. take_damage(), add_health(), add_armor(), apply_knockback() and
## face_point() are public — enemies, pickups, splash damage and the boot
## probe all drive the same routines gameplay uses. Weapons hang under the
## camera (see weapons.gd).

signal health_changed(health: int, armor: int)
signal took_damage(amount: int, cause: String)
signal died

## Ground wish speed, m/s.
@export var move_speed := 8.0
@export var sprint_multiplier := 1.35
## Quake accelerate: velocity gains accel * wish_speed per second toward the
## wish direction, capped so speed along it never exceeds wish_speed.
@export var ground_accel := 10.0
@export var ground_friction := 6.0
## Air acceleration + the classic small air-speed cap — the cap is what makes
## air control and strafe-jumping work (speed along the wish dir may only
## reach air_speed_cap, but *turning* re-aims the whole velocity).
@export var air_accel := 30.0
@export var air_speed_cap := 1.1
@export var jump_velocity := 5.2
@export var gravity := 15.5
@export var mouse_sensitivity := 0.0022
@export var max_health := 100
@export var max_armor := 100
## Fraction of incoming damage the armor eats while any armor remains.
@export var armor_absorb := 0.66

var health := 0
var armor := 0

var _pitch := 0.0
var _dead := false

@onready var _camera: Camera3D = $Camera3D
@onready var weapons: Node3D = $Camera3D/Weapons


func _ready() -> void:
	health = max_health


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
		_camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var axis := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var wish_dir := global_transform.basis * Vector3(axis.x, 0.0, axis.y)
	wish_dir.y = 0.0
	if wish_dir.length_squared() > 0.0:
		wish_dir = wish_dir.normalized()
	var wish_speed := move_speed
	if Input.is_action_pressed(&"sprint"):
		wish_speed *= sprint_multiplier

	if is_on_floor():
		if Input.is_action_pressed(&"jump"):
			# Auto-hop: jumping skips the landing-frame friction, so held-jump
			# bunny-hops carry their speed (the Quake pogo).
			velocity.y = jump_velocity
			_air_accelerate(wish_dir, wish_speed, delta)
		else:
			_apply_friction(delta)
			_accelerate(wish_dir, wish_speed, ground_accel, delta)
	else:
		velocity.y -= gravity * delta
		_air_accelerate(wish_dir, wish_speed, delta)

	move_and_slide()


## Apply a hit. Armor eats armor_absorb of it while it lasts; at 0 health the
## run is over (`died` — main.gd opens the summary).
func take_damage(amount: int, cause: String) -> void:
	if _dead or amount <= 0:
		return
	var absorbed := mini(roundi(amount * armor_absorb), armor)
	armor -= absorbed
	health -= amount - absorbed
	if health <= 0:
		health = 0
	took_damage.emit(amount, cause)
	health_changed.emit(health, armor)
	if health == 0:
		_dead = true
		died.emit()


## Pickup entry points: false when already full (the item is not consumed).
func add_health(amount: int) -> bool:
	if _dead or health >= max_health:
		return false
	health = mini(health + amount, max_health)
	health_changed.emit(health, armor)
	return true


func add_armor(amount: int) -> bool:
	if _dead or armor >= max_armor:
		return false
	armor = mini(armor + amount, max_armor)
	health_changed.emit(health, armor)
	return true


## Rocket-splash shove (self-splash included — this is the rocket jump).
func apply_knockback(impulse: Vector3) -> void:
	if _dead:
		return
	velocity += impulse


## Aim the body yaw + camera pitch straight at a world point (what mouselook
## does over time; bots and the boot probe aim through this).
func face_point(point: Vector3) -> void:
	var to := point - _camera.global_position
	rotation.y = atan2(-to.x, -to.z)
	_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.5, 1.5)
	_camera.rotation.x = _pitch


func is_dead() -> bool:
	return _dead


## "persistent" group contract (see templates ABI): return the state to save.
func save_data() -> Dictionary:
	return {
		"health": health,
		"armor": armor,
		"position": {"x": global_position.x, "y": global_position.y, "z": global_position.z},
		"ammo": weapons.ammo.duplicate(),
		"weapon": weapons.current,
	}


func load_data(data: Dictionary) -> void:
	health = int(data.get("health", health))
	armor = int(data.get("armor", armor))
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("y") and pos.has("z"):
		global_position = Vector3(pos.x, pos.y, pos.z)
	var saved_ammo: Dictionary = data.get("ammo", {})
	for ammo_type in saved_ammo:
		if weapons.ammo.has(ammo_type):
			weapons.ammo[ammo_type] = int(saved_ammo[ammo_type])
	weapons.switch_to(int(data.get("weapon", weapons.current)))
	health_changed.emit(health, armor)


func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current := velocity.dot(wish_dir)
	var add := wish_speed - current
	if add <= 0.0:
		return
	velocity += wish_dir * minf(accel * wish_speed * delta, add)


func _air_accelerate(wish_dir: Vector3, wish_speed: float, delta: float) -> void:
	var capped := minf(wish_speed, air_speed_cap)
	var current := velocity.dot(wish_dir)
	var add := capped - current
	if add <= 0.0:
		return
	velocity += wish_dir * minf(air_accel * wish_speed * delta, add)


func _apply_friction(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	var speed := flat.length()
	if speed < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var factor := maxf(speed - speed * ground_friction * delta, 0.0) / speed
	velocity.x *= factor
	velocity.z *= factor
