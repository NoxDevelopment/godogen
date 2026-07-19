extends Node3D
## res://scripts/world.gd
## The dungeon — the game's entry scene. Builds the room + boss chamber, the key,
## the locked door, the player, the room enemies, and the boss entirely in code
## from GameManager's quest state, then wires the objective HUD. The quest chain
## it stages: clear the room → grab the KEY → touch the DOOR to unlock it → step
## into the boss chamber and defeat the BOSS. All rules live in GameManager.

const PLAYER := preload("res://scenes/player.tscn")
const ENEMY := preload("res://scenes/enemy.tscn")

var _door: StaticBody3D
var _hearts: Label
var _objective: Label
var _banner: Label


func _ready() -> void:
	GameManager.reset_quest(2)  # two room enemies + the boss
	_build_environment()
	_build_room()
	_build_key(Vector3(7, 1, -4))
	_door = _build_door(Vector3(0, 1.5, -10))

	var p := PLAYER.instantiate()
	p.position = Vector3(0, 1.2, 6)
	add_child(p)

	_spawn_enemy(Vector3(-4, 1.2, -2), false, 3)
	_spawn_enemy(Vector3(4, 1.2, 0), false, 3)
	_spawn_enemy(Vector3(0, 1.2, -18), true, GameManager.BOSS_MAX_HP)  # boss

	_build_hud()
	GameManager.state_changed.connect(_refresh)
	GameManager.state_changed.connect(_update_door)
	GameManager.player_died.connect(func() -> void: _end("YOU DIED — Enter to retry"))
	GameManager.quest_won.connect(func() -> void: _end("DUNGEON CLEARED — the boss falls! Enter to replay"))
	_refresh()
	print("DEBUG: action-adventure-3d ready — enemies=%d boss_hp=%d has_key=%s door_open=%s" % [
		GameManager.enemies_total, GameManager.boss_hp, str(GameManager.has_key), str(GameManager.door_open)])


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()


# --- world construction ----------------------------------------------------

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.36, 0.42)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)


func _build_room() -> void:
	# floor spanning the room + boss chamber (z: 8 → -24)
	_box(Vector3(0, -0.5, -8), Vector3(24, 1, 34), Color(0.30, 0.32, 0.38), true)
	# outer walls
	_box(Vector3(-11, 2, -8), Vector3(1, 5, 34), Color(0.24, 0.25, 0.30), true)  # left
	_box(Vector3(11, 2, -8), Vector3(1, 5, 34), Color(0.24, 0.25, 0.30), true)   # right
	_box(Vector3(0, 2, 9), Vector3(24, 5, 1), Color(0.24, 0.25, 0.30), true)     # back
	_box(Vector3(0, 2, -25), Vector3(24, 5, 1), Color(0.24, 0.25, 0.30), true)   # front (boss end)
	# divider wall at z=-10 with a doorway gap (x: -2..2)
	_box(Vector3(-6.5, 2, -10), Vector3(9, 5, 1), Color(0.26, 0.27, 0.33), true)
	_box(Vector3(6.5, 2, -10), Vector3(9, 5, 1), Color(0.26, 0.27, 0.33), true)


func _build_key(pos: Vector3) -> void:
	var area := Area3D.new()
	area.position = pos
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.8
	cs.shape = sph
	area.add_child(cs)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.8, 0.4)
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.95, 0.82, 0.35))
	area.add_child(mesh)
	area.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group(&"player") and not GameManager.has_key:
			GameManager.collect_key()
			area.queue_free())
	add_child(area)


func _build_door(pos: Vector3) -> StaticBody3D:
	var door := StaticBody3D.new()
	door.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 1)
	cs.shape = box
	door.add_child(cs)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 3, 1)
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.55, 0.38, 0.22))
	door.add_child(mesh)
	# a trigger so touching the door with the key opens it.
	var trig := Area3D.new()
	var tcs := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(4.5, 3, 2.2)
	tcs.shape = tb
	trig.add_child(tcs)
	trig.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group(&"player"):
			GameManager.try_open_door())
	door.add_child(trig)
	add_child(door)
	return door


func _update_door() -> void:
	if _door == null or not is_instance_valid(_door):
		return
	_door.visible = not GameManager.door_open
	for c in _door.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = GameManager.door_open


func _spawn_enemy(pos: Vector3, is_boss: bool, hp: int) -> void:
	var e := ENEMY.instantiate()
	e.position = pos
	e.is_boss = is_boss
	e.max_hp = hp
	if is_boss:
		e.scale = Vector3(1.8, 1.8, 1.8)
	add_child(e)


func _box(pos: Vector3, size: Vector3, color: Color, solid: bool) -> void:
	var node := StaticBody3D.new() if solid else Node3D.new()
	node.position = pos
	if solid:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		node.add_child(cs)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _mat(color)
	node.add_child(mesh)
	add_child(node)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


# --- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hearts = _label(layer, Vector2(24, 18), 26, Color(0.95, 0.4, 0.42))
	_objective = _label(layer, Vector2(24, 56), 17, Color(0.9, 0.9, 0.86))
	_banner = _label(layer, Vector2(24, 92), 22, Color(0.96, 0.86, 0.5))


func _label(layer: CanvasLayer, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	layer.add_child(l)
	return l


func _refresh() -> void:
	if _hearts == null:
		return
	var full := GameManager.player_hp
	var empty := GameManager.PLAYER_MAX_HP - full
	_hearts.text = "♥".repeat(full) + "♡".repeat(empty)
	if GameManager.won:
		_objective.text = "Victory!"
	elif not GameManager.has_key:
		_objective.text = "Objective: find the golden key (defeat the guards)."
	elif not GameManager.door_open:
		_objective.text = "Objective: take the key to the boss door to unlock it."
	else:
		_objective.text = "Objective: defeat the boss   (boss HP %d/%d)" % [GameManager.boss_hp, GameManager.BOSS_MAX_HP]


func _end(text: String) -> void:
	if _banner != null:
		_banner.text = text
