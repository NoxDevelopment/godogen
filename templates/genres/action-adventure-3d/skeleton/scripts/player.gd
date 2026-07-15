extends CharacterBody3D
## res://scripts/player.gd
## Third-person action-adventure hero (Zelda-3D). World-relative movement under a
## fixed follow camera, a jump, a SWORD swing (a short-lived Area3D hitbox in
## front that damages any enemy it touches), and LOCK-ON (face + strafe a target).
## Health lives in GameManager — enemies call GameManager.damage_player on
## contact; this only reads is_over() to stop on death/win.

const SPEED := 6.0
const JUMP := 8.0
const GRAVITY := 22.0
const ATTACK_TIME := 0.22       ## how long the sword hitbox stays live.
const ATTACK_COOLDOWN := 0.45
const CAM_OFFSET := Vector3(0, 7.5, 8.0)

var _cam: Camera3D
var _sword: Area3D
var _attack_timer := 0.0
var _cooldown := 0.0
var _locked: Node3D = null


func _ready() -> void:
	add_to_group(&"player")
	# Follow camera — top_level so we place it in world space each frame.
	_cam = Camera3D.new()
	_cam.top_level = true
	add_child(_cam)
	_cam.current = true
	# Sword hitbox in front, off until a swing.
	_sword = Area3D.new()
	_sword.position = Vector3(0, 0.6, -1.3)
	_sword.monitoring = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.4, 1.8)
	cs.shape = box
	_sword.add_child(cs)
	_sword.body_entered.connect(_on_sword_hit)
	add_child(_sword)


func _physics_process(delta: float) -> void:
	if GameManager.is_over():
		velocity = Vector3.ZERO
		_place_camera()
		return

	var input := Vector3(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		0.0,
		Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"),
	)
	var dir := input.normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed(&"jump"):
		velocity.y = JUMP
	move_and_slide()

	_update_facing(dir)

	if Input.is_action_just_pressed(&"lock_on"):
		_toggle_lock()

	_cooldown = maxf(0.0, _cooldown - delta)
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_sword.monitoring = false
	if Input.is_action_just_pressed(&"attack") and _cooldown <= 0.0:
		_sword.monitoring = true
		_attack_timer = ATTACK_TIME
		_cooldown = ATTACK_COOLDOWN

	_place_camera()


func _update_facing(dir: Vector3) -> void:
	if _locked != null and is_instance_valid(_locked):
		var t := _locked.global_position
		t.y = global_position.y
		if global_position.distance_to(t) > 0.05:
			look_at(t, Vector3.UP)
	elif dir.length() > 0.05:
		look_at(global_position + Vector3(dir.x, 0.0, dir.z), Vector3.UP)


func _place_camera() -> void:
	_cam.global_position = global_position + CAM_OFFSET
	_cam.look_at(global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _toggle_lock() -> void:
	if _locked != null and is_instance_valid(_locked):
		_locked = null
		return
	var nearest: Node3D = null
	var best := INF
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e is Node3D:
			var d := global_position.distance_to((e as Node3D).global_position)
			if d < best:
				best = d
				nearest = e
	_locked = nearest


func _on_sword_hit(body: Node) -> void:
	if body != self and body.has_method("take_damage"):
		body.take_damage(1)
