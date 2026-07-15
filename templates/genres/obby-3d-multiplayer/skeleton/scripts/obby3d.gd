extends Node3D
## res://scripts/obby3d.gd
## The obby LEVEL — a 3D obstacle course built entirely in code from the COURSE
## data below (platforms, ordered checkpoints, hazards, a finish, a kill line).
## It drives GameManager (the run state) and bridges to nox_netcode when a
## session is live:
##   • OFFLINE (no Net autoload, or Net.active == false): it spawns ONE local
##     avatar and handles checkpoint / respawn / finish itself — a complete
##     single-player obby with zero multiplayer dependency.
##   • ONLINE (nox_netcode injected + a session running): the NetSpawner3D child
##     spawns one avatar per peer, and checkpoint/respawn/finish route through
##     the NetEvents child so the host arbitrates an authoritative race.
## The seam is `_net_active()` + `_report_*` — the rest of the level is identical
## either way, which is the whole point of the drop-in. It is obby.gd (the 2D
## template) with Node2D→Node3D, Vector2→Vector3, and Rect2→AABB; the offline↔
## online seam is byte-identical in spirit.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const KILL_Y := -8.0             ## fall below this (Y is up in 3D) → respawn.
const START_SPAWN := Vector3(0.0, 1.2, 0.0)

## Platforms: AABB(min_corner, size) static floor pieces (X across, Z forward,
## Y up). The course climbs a staircase of pads along -Z to the finish deck.
const PLATFORMS: Array[AABB] = [
	AABB(Vector3(-3.0, -0.5, -3.0), Vector3(6.0, 1.0, 6.0)),      # start deck
	AABB(Vector3(-1.5, 0.25, -10.0), Vector3(3.0, 0.5, 3.0)),
	AABB(Vector3(-1.5, 1.25, -15.0), Vector3(3.0, 0.5, 3.0)),
	AABB(Vector3(-1.5, 2.25, -20.0), Vector3(3.0, 0.5, 3.0)),
	AABB(Vector3(-1.5, 1.75, -25.0), Vector3(3.0, 0.5, 3.0)),
	AABB(Vector3(-1.5, 2.25, -30.0), Vector3(3.0, 0.5, 3.0)),
	AABB(Vector3(-2.0, 2.75, -35.0), Vector3(4.0, 0.5, 4.0)),
	AABB(Vector3(-3.0, 3.0, -41.0), Vector3(6.0, 1.0, 6.0)),      # finish deck
]
## Checkpoints in ORDER — the gate positions (a run must clear them 0,1,2,…).
const CHECKPOINTS: Array[Vector3] = [
	Vector3(0.0, 2.5, -15.0),
	Vector3(0.0, 3.0, -25.0),
	Vector3(0.0, 3.5, -35.0),
]
## Hazards: AABB kill zones (touch → respawn), e.g. a lava patch beside the path.
const HAZARDS: Array[AABB] = [
	AABB(Vector3(2.0, 0.0, -19.0), Vector3(2.0, 0.5, 2.0)),
]
const FINISH := AABB(Vector3(-2.0, 3.5, -43.0), Vector3(4.0, 2.5, 4.0))

var _avatars: Node
var _net_spawner: Node
var _net_events: Node
var _camera: Camera3D
var _local_avatar: CharacterBody3D  ## offline: the one avatar we spawned.
var _respawning := false

## Fixed follow-camera offset (behind and above the avatar).
const CAM_OFFSET := Vector3(0.0, 9.0, 11.0)

# HUD
var _hud_progress: Label
var _hud_stats: Label
var _banner: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_avatars = $Avatars
	_net_spawner = get_node_or_null("NetSpawner")
	_net_events = get_node_or_null("NetEvents")
	_build_environment()
	_build_course()
	_build_hud()
	_camera = Camera3D.new()
	_camera.position = START_SPAWN + CAM_OFFSET
	add_child(_camera)
	_camera.look_at(START_SPAWN, Vector3.UP)
	_camera.make_current()

	GameManager.begin_course(CHECKPOINTS.size())
	GameManager.course_changed.connect(_refresh_hud)

	if _net_active():
		_wire_net_events()
	else:
		_spawn_local_avatar()

	_refresh_hud()
	print("DEBUG: obby3d ready — platforms=%d checkpoints=%d hazards=%d net=%s local_avatar=%s" % [
		PLATFORMS.size(), CHECKPOINTS.size(), HAZARDS.size(), str(_net_active()),
		str(_current_avatar() != null),
	])


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		_restart()


func _physics_process(delta: float) -> void:
	if not _net_active():
		GameManager.tick(delta)
	var av := _current_avatar()
	if av == null:
		return
	# camera trails the local avatar.
	var target := av.global_position + CAM_OFFSET
	_camera.global_position = _camera.global_position.lerp(target, 0.15)
	_camera.look_at(av.global_position, Vector3.UP)
	# fall line → respawn.
	if av.global_position.y < KILL_Y and not _respawning:
		_trigger_respawn()


# --- seam: online vs offline ----------------------------------------------

func _net_active() -> bool:
	var n := get_node_or_null("/root/Net")
	return n != null and bool(n.active)


func _local_peer_name() -> String:
	var n := get_node_or_null("/root/Net")
	if n != null:
		return str(n.local_id())
	return "1"


## The avatar this client controls (offline: the one we spawned; online: the
## node the spawner named after our peer id).
func _current_avatar() -> CharacterBody3D:
	if not _net_active():
		return _local_avatar
	return _avatars.get_node_or_null(NodePath(_local_peer_name())) as CharacterBody3D


func _is_local(body: Node) -> bool:
	return body != null and body == _current_avatar()


# --- course construction (all in code) -------------------------------------

func _build_course() -> void:
	for box in PLATFORMS:
		_add_platform(box)
	for i in CHECKPOINTS.size():
		_add_checkpoint(i, CHECKPOINTS[i])
	for box in HAZARDS:
		_add_hazard(box)
	_add_finish(FINISH)
	# one spawn point per potential peer, spread across the start deck.
	for i in 8:
		var m := Marker3D.new()
		m.position = START_SPAWN + Vector3(float(i) * 0.6 - 2.1, 0.0, 0.0)
		m.add_to_group(&"net_spawn_point")
		add_child(m)


func _add_platform(box: AABB) -> void:
	var body := StaticBody3D.new()
	body.position = box.position + box.size / 2.0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.36, 0.40, 0.48))
	body.add_child(mesh)
	add_child(body)


func _add_checkpoint(index: int, pos: Vector3) -> void:
	var area := Area3D.new()
	area.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 3.0, 2.4)
	col.shape = shape
	area.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 3.0, 0.5)
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.45, 0.85, 0.55), 0.55)
	area.add_child(mesh)
	area.body_entered.connect(_on_checkpoint.bind(index))
	add_child(area)


func _add_hazard(box: AABB) -> void:
	var area := Area3D.new()
	area.position = box.position + box.size / 2.0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	area.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.9, 0.35, 0.35))
	area.add_child(mesh)
	area.body_entered.connect(_on_hazard)
	add_child(area)


func _add_finish(box: AABB) -> void:
	var area := Area3D.new()
	area.position = box.position + box.size / 2.0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	area.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.95, 0.86, 0.45), 0.7)
	area.add_child(mesh)
	area.body_entered.connect(_on_finish)
	add_child(area)


func _mat(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var world := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.36, 0.42)
	e.ambient_light_energy = 0.6
	world.environment = e
	add_child(world)


# --- avatar spawn -----------------------------------------------------------

func _spawn_local_avatar() -> void:
	_local_avatar = PLAYER_SCENE.instantiate()
	_local_avatar.name = "1"
	_local_avatar.position = START_SPAWN
	_avatars.add_child(_local_avatar)


func _checkpoint_position(index: int) -> Vector3:
	if index < 0 or index >= CHECKPOINTS.size():
		return START_SPAWN
	return CHECKPOINTS[index] + Vector3(0.0, 0.3, 0.0)


# --- events (offline handled here; online routed through NetEvents) ---------

func _on_checkpoint(body: Node, index: int) -> void:
	if not _is_local(body):
		return
	if _net_active():
		if _net_events != null:
			_net_events.report_checkpoint(index)
	else:
		GameManager.reach_checkpoint(index)


func _on_hazard(body: Node) -> void:
	if _is_local(body):
		_trigger_respawn()


func _on_finish(body: Node) -> void:
	if not _is_local(body):
		return
	if _net_active():
		if _net_events != null:
			_net_events.report_finish()
	else:
		GameManager.finish(GameManager.elapsed)
		_refresh_hud()


func _trigger_respawn() -> void:
	if _respawning:
		return
	if _net_active():
		if _net_events != null:
			_net_events.request_respawn()
		return
	_respawning = true
	GameManager.die()
	_teleport(_current_avatar(), _checkpoint_position(GameManager.respawn_index()))
	_respawning = false


func _teleport(avatar: CharacterBody3D, pos: Vector3) -> void:
	if avatar == null:
		return
	avatar.velocity = Vector3.ZERO
	avatar.global_position = pos


# --- nox_netcode signal bridge (online only) -------------------------------

func _wire_net_events() -> void:
	if _net_events == null:
		return
	if _net_spawner != null and "player_scene" in _net_spawner:
		_net_spawner.player_scene = PLAYER_SCENE
	_net_events.player_respawned.connect(_on_net_respawn)
	_net_events.player_finished.connect(_on_net_finish)
	_net_events.checkpoint_confirmed.connect(_on_net_checkpoint)
	if _net_events.has_method("start_race"):
		_net_events.start_race()


func _on_net_checkpoint(peer: int, checkpoint_id: int) -> void:
	if peer == int(_local_peer_name()):
		GameManager.reach_checkpoint(checkpoint_id)


func _on_net_respawn(peer: int, checkpoint_id: int) -> void:
	if peer == int(_local_peer_name()):
		GameManager.die()
		_teleport(_current_avatar(), _checkpoint_position(checkpoint_id))


func _on_net_finish(peer: int, _place: int, finish_time: float) -> void:
	if peer == int(_local_peer_name()):
		GameManager.finish(finish_time)
		_refresh_hud()


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_progress = _mk_label(layer, Vector2(20, 16), 20)
	_hud_stats = _mk_label(layer, Vector2(20, 44), 16)
	_banner = _mk_label(layer, Vector2(20, 84), 22)
	_banner.modulate = Color(0.95, 0.86, 0.45)


func _mk_label(layer: CanvasLayer, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_to_group(&"scalable_text")
	layer.add_child(l)
	return l


func _refresh_hud() -> void:
	if _hud_progress == null:
		return
	_hud_progress.text = "Checkpoint %d / %d" % [GameManager.current_checkpoint + 1, GameManager.checkpoint_count]
	var t := GameManager.finish_time if GameManager.finished else GameManager.elapsed
	_hud_stats.text = "Time %.1fs   Deaths %d   Best %s" % [
		t, GameManager.deaths,
		("%.1fs" % GameManager.best_time) if GameManager.best_time >= 0.0 else "—",
	]
	if GameManager.finished:
		_banner.text = "Finished in %.1fs!  Press Enter for a new run." % GameManager.finish_time
	else:
		_banner.text = ""


func _restart() -> void:
	GameManager.begin_course(CHECKPOINTS.size())
	_teleport(_current_avatar(), START_SPAWN)
	_refresh_hud()
