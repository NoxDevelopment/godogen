extends CharacterBody3D
## res://scripts/enemy.gd
## A dungeon enemy (and, with is_boss, the boss). Chases the player when in range
## and deals contact damage on a cooldown; takes sword hits via take_damage().
## A normal enemy owns its own HP and reports its death to GameManager; the boss
## routes damage into GameManager (which gates it behind the open door and wins
## the run when the boss falls).

@export var is_boss := false
@export var max_hp := 3

const SPEED := 3.2
const GRAVITY := 22.0
const CONTACT_RANGE := 1.7
const AGGRO_RANGE := 18.0
const CONTACT_DAMAGE := 1
const CONTACT_COOLDOWN := 1.0

var hp := 3
var _cd := 0.0
var _player: Node3D


func _ready() -> void:
	hp = max_hp
	add_to_group(&"enemies")
	_player = get_tree().get_first_node_in_group(&"player")


func _physics_process(delta: float) -> void:
	if GameManager.is_over():
		velocity = Vector3.ZERO
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player")
	_cd = maxf(0.0, _cd - delta)

	if _player != null and is_instance_valid(_player):
		var to := _player.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > CONTACT_RANGE and d < AGGRO_RANGE:
			var dir := to.normalized()
			velocity.x = dir.x * SPEED
			velocity.z = dir.z * SPEED
			look_at(global_position + Vector3(dir.x, 0.0, dir.z), Vector3.UP)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		if d <= CONTACT_RANGE and _cd <= 0.0:
			GameManager.damage_player(CONTACT_DAMAGE)
			_cd = CONTACT_COOLDOWN
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()


## Take a sword hit. The boss defers to GameManager (door-gated + wins on kill);
## a normal enemy tracks its own HP and reports its death.
func take_damage(amount: int) -> void:
	_hit_react()
	if is_boss:
		GameManager.damage_boss(amount)
		if GameManager.boss_defeated:
			queue_free()
		return
	hp -= amount
	if hp <= 0:
		GameManager.register_enemy_defeated()
		queue_free()


func _hit_react() -> void:
	scale = Vector3(1.15, 1.15, 1.15)
	var t := get_tree().create_timer(0.09)
	t.timeout.connect(func() -> void:
		if is_instance_valid(self):
			scale = Vector3.ONE)
