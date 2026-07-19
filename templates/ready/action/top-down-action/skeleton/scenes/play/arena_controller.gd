extends GameManager
## ArenaController — extends the base GameManager so player spawn/death/game-over
## all still work, then layers the "full game" on top: arms the player, scales the
## wave by GameFlow.current (extra + tougher enemies), tracks kills for scoring,
## shows the score HUD, and reveals a level exit once every enemy is down.

const ENEMY_SCENE := preload("res://characters/enemies/melee/minion/EnemyMinion.tscn")
const SCORE_HUD := preload("res://ui/score_hud.tscn")

## Nav-mesh extent of the arena floor (see NavigationMesh in the scene).
const SPAWN_MIN := Vector3(-13.0, 0.5, -13.0)
const SPAWN_MAX := Vector3(13.0, 0.5, 9.0)

var _enemies: Array = []
var _total := 0
var _cleared := false
var _exit: Area3D = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	super._ready()  # base: find/spawn player, wire game-over menu
	_rng.randomize()
	# Give the player their weapon so the wave is actually winnable.
	var p := GameManager.get_player()
	if p and not p.inventory.has("toygun"):
		p.inventory.append("toygun")
	if p and p.has_signal("is_dead"):
		p.is_dead.connect(GameFlow.pause_timer)

	# Collect the enemies already placed in the scene.
	_gather_enemies(self)
	# Escalate: +3 enemies per wave beyond the first, and tougher each wave.
	var extra := (GameFlow.current - 1) * 3
	for i in extra:
		_spawn_enemy()
	var bonus_hp := GameFlow.current - 1
	if bonus_hp > 0:
		for e in _enemies:
			if is_instance_valid(e) and "health_points" in e:
				e.health_points += bonus_hp
	_total = _enemies.size()
	GameFlow.enemies_left = _total

	# HUD
	add_child(SCORE_HUD.instantiate())

	# Build the level exit (hidden until the wave is cleared).
	_build_exit()

func _process(_delta: float) -> void:
	if _cleared:
		return
	var alive := 0
	for e in _enemies:
		if is_instance_valid(e) and e.get("health_points") != null and e.health_points > 0:
			alive += 1
	GameFlow.enemies_left = alive
	GameFlow.wave_kills = _total - alive
	if _total > 0 and alive == 0:
		_on_wave_cleared()

func _gather_enemies(node: Node) -> void:
	for c in node.get_children():
		if c is CharacterBody3D and "health_points" in c:
			_enemies.append(c)
		if c.get_child_count() > 0:
			_gather_enemies(c)

func _spawn_enemy() -> void:
	var e := ENEMY_SCENE.instantiate()
	add_child(e)
	e.global_position = Vector3(
		_rng.randf_range(SPAWN_MIN.x, SPAWN_MAX.x),
		SPAWN_MIN.y,
		_rng.randf_range(SPAWN_MIN.z, SPAWN_MAX.z)
	)
	_enemies.append(e)

func _build_exit() -> void:
	_exit = Area3D.new()
	_exit.name = "LevelExit"
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 3.0, 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0)
	mat.emission_energy_multiplier = 2.5
	box.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	_exit.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(2.5, 3.0, 2.5)
	shape.shape = bshape
	_exit.add_child(shape)
	_exit.position = Vector3(0.0, 1.5, 8.0)
	_exit.monitoring = false
	_exit.visible = false
	_exit.body_entered.connect(_on_exit_body)
	add_child(_exit)

func _on_wave_cleared() -> void:
	_cleared = true
	if _exit:
		_exit.visible = true
		_exit.monitoring = true

func _on_exit_body(body: Node3D) -> void:
	if body is PlayerEntity:
		GameFlow.next_level()
