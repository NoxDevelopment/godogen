extends Node2D
## res://scripts/obby.gd
## The obby LEVEL — a 2D obstacle course built entirely in code from a CourseData
## instance (scripts/course_data.gd): platforms, ordered checkpoints, hazards, a
## finish, a kill line, a start. The course is DATA-DRIVEN — it comes from
## CourseLibrary.pending_course (set by the course-select screen or the editor's
## Test action) and falls back to the built-in 'Starter Climb' (the original
## hardcoded obby, verbatim) when nothing is selected, so running this scene
## directly is byte-identical to the pre-refactor level.
##
## It drives GameManager (the run state) and bridges to nox_netcode when a
## session is live:
##   • OFFLINE (no Net autoload, or Net.active == false): it spawns ONE local
##     avatar and handles checkpoint / respawn / finish itself — a complete
##     single-player obby with zero multiplayer dependency.
##   • ONLINE (nox_netcode injected + a session running): the NetSpawner child
##     spawns one avatar per peer, checkpoint/respawn/finish route through the
##     NetEvents child so the host arbitrates an authoritative race, AND the
##     CourseSync child makes every peer build the HOST's chosen course.
## The seam is `_net_active()` + `_report_*` — the rest of the level is identical
## either way, which is the whole point of the drop-in.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

## The course this level is currently built from (data-driven). Resolved in
## _ready(); rebuilt in place when the host's course arrives online.
var _course: CourseData

var _course_root: Node2D            ## container holding all built course nodes.
var _avatars: Node
var _net_spawner: Node
var _net_events: Node
var _course_sync: Node
var _camera: Camera2D
var _local_avatar: CharacterBody2D  ## offline: the one avatar we spawned.
var _respawning := false

# HUD
var _hud_progress: Label
var _hud_stats: Label
var _banner: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_avatars = $Avatars
	_net_spawner = get_node_or_null("NetSpawner")
	_net_events = get_node_or_null("NetEvents")
	_course_sync = get_node_or_null("CourseSync")

	_course = _resolve_course()
	_course_root = Node2D.new()
	_course_root.name = "Course"
	add_child(_course_root)
	_build_course()
	_build_hud()

	_camera = Camera2D.new()
	_camera.position = _course.start_spawn
	add_child(_camera)
	_camera.make_current()

	GameManager.begin_course(_course.checkpoints.size())
	GameManager.course_changed.connect(_refresh_hud)

	if _net_active():
		_wire_net_events()
		_wire_course_sync()
	else:
		_spawn_local_avatar()

	_refresh_hud()
	print("DEBUG: obby ready — course=\"%s\" platforms=%d checkpoints=%d hazards=%d net=%s local_avatar=%s" % [
		_course.name, _course.platforms.size(), _course.checkpoints.size(),
		_course.hazards.size(), str(_net_active()), str(_current_avatar() != null),
	])


## Pick the course to build: the pending selection (from the select screen or the
## editor's Test), else the built-in default. Guards against an invalid pending
## course so a corrupt hand-off can never brick the level.
func _resolve_course() -> CourseData:
	var lib := get_node_or_null("/root/CourseLibrary")
	if lib != null and lib.pending_course != null:
		var pending: CourseData = lib.pending_course
		if pending.is_valid():
			return pending
		push_error("[obby] pending course invalid (%s) — using default" % ", ".join(pending.validation_errors()))
	return CourseLibrary.default_course()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		_restart()
	elif e.is_action_pressed(&"ui_cancel") and not _net_active():
		# Back to the course browser (offline only — never yank out of a live session).
		get_tree().paused = false
		get_tree().change_scene_to_file.call_deferred("res://scenes/course_select.tscn")


func _physics_process(delta: float) -> void:
	if not _net_active():
		GameManager.tick(delta)
	var av := _current_avatar()
	if av == null:
		return
	# camera trails the local avatar.
	_camera.position = _camera.position.lerp(av.global_position, 0.15)
	# fall line → respawn.
	if av.global_position.y > _course.kill_y and not _respawning:
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
func _current_avatar() -> CharacterBody2D:
	if not _net_active():
		return _local_avatar
	return _avatars.get_node_or_null(NodePath(_local_peer_name())) as CharacterBody2D


func _is_local(body: Node) -> bool:
	return body != null and body == _current_avatar()


# --- course construction (all in code, from CourseData) --------------------

## Build (or rebuild) every course node from `_course`. Clears any previously
## built geometry first so an online course-swap rebuilds cleanly in place.
func _build_course() -> void:
	for child in _course_root.get_children():
		child.queue_free()
	# spawn points are children of the level root (the net_spawn_point group);
	# clear the old ones before laying the new start down.
	for m in get_tree().get_nodes_in_group(&"net_spawn_point"):
		if is_instance_valid(m):
			m.queue_free()

	for rect in _course.platforms:
		_add_platform(rect)
	for i in _course.checkpoints.size():
		_add_checkpoint(i, _course.checkpoints[i])
	for rect in _course.hazards:
		_add_hazard(rect)
	_add_finish(_course.finish)
	# one spawn point per potential peer, spread along the start.
	for i in 8:
		var m := Marker2D.new()
		m.position = _course.start_spawn + Vector2(i * 28, 0)
		m.add_to_group(&"net_spawn_point")
		add_child(m)


func _add_platform(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size / 2.0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	body.add_child(col)
	var vis := ColorRect.new()
	vis.color = Color(0.36, 0.40, 0.48)
	vis.size = rect.size
	vis.position = -rect.size / 2.0
	body.add_child(vis)
	_course_root.add_child(body)


func _add_checkpoint(index: int, pos: Vector2) -> void:
	var area := Area2D.new()
	area.position = pos
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(36, 96)
	col.shape = shape
	area.add_child(col)
	var pole := ColorRect.new()
	pole.color = Color(0.45, 0.85, 0.55, 0.55)
	pole.size = Vector2(36, 96)
	pole.position = Vector2(-18, -48)
	area.add_child(pole)
	area.body_entered.connect(_on_checkpoint.bind(index))
	_course_root.add_child(area)


func _add_hazard(rect: Rect2) -> void:
	var area := Area2D.new()
	area.position = rect.position + rect.size / 2.0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	area.add_child(col)
	var vis := ColorRect.new()
	vis.color = Color(0.9, 0.35, 0.35)
	vis.size = rect.size
	vis.position = -rect.size / 2.0
	area.add_child(vis)
	area.body_entered.connect(_on_hazard)
	_course_root.add_child(area)


func _add_finish(rect: Rect2) -> void:
	var area := Area2D.new()
	area.position = rect.position + rect.size / 2.0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	area.add_child(col)
	var vis := ColorRect.new()
	vis.color = Color(0.95, 0.86, 0.45, 0.7)
	vis.size = rect.size
	vis.position = -rect.size / 2.0
	area.add_child(vis)
	area.body_entered.connect(_on_finish)
	_course_root.add_child(area)


# --- avatar spawn -----------------------------------------------------------

func _spawn_local_avatar() -> void:
	_local_avatar = PLAYER_SCENE.instantiate()
	_local_avatar.name = "1"
	_local_avatar.position = _course.start_spawn
	_avatars.add_child(_local_avatar)


func _checkpoint_position(index: int) -> Vector2:
	if index < 0 or index >= _course.checkpoints.size():
		return _course.start_spawn
	return _course.checkpoints[index] + Vector2(0, -12)


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


func _teleport(avatar: CharacterBody2D, pos: Vector2) -> void:
	if avatar == null:
		return
	avatar.velocity = Vector2.ZERO
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


# --- course-sync bridge (online only): host's course wins on every peer ------

func _wire_course_sync() -> void:
	if _course_sync == null:
		return
	_course_sync.course_ready.connect(_on_course_synced)
	var n := get_node_or_null("/root/Net")
	if n != null and n.has_method("is_host") and bool(n.is_host()):
		# Host: publish our resolved course so every client builds it. Built-ins
		# go by id (compact); custom/imported courses go as full JSON.
		var lib := get_node_or_null("/root/CourseLibrary")
		var builtin_id := ""
		if lib != null and _course_is_pending(lib):
			builtin_id = _pending_builtin_id(lib)
		_course_sync.publish(_course, builtin_id)
	else:
		# Client: build the host's course as soon as it arrives; ask now in case
		# the host already started before this scene loaded.
		_course_sync.request_from_host()


func _course_is_pending(lib: Node) -> bool:
	return lib.pending_course != null and lib.pending_course == _course


func _pending_builtin_id(lib: Node) -> String:
	var id := str(lib.pending_course_id)
	return id if id.begins_with(CourseLibrary.BUILTIN_PREFIX) else ""


## The host's course arrived (client) — rebuild the level to match it exactly.
func _on_course_synced(course: CourseData) -> void:
	if course == null or not course.is_valid():
		return
	if _course != null and _course.equals(course):
		return  # already building this course (e.g. host's call_local echo)
	_course = course
	_build_course()
	_camera.position = _course.start_spawn
	GameManager.begin_course(_course.checkpoints.size())
	_refresh_hud()


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
	_hud_progress.text = "%s — Checkpoint %d / %d" % [
		_course.name, GameManager.current_checkpoint + 1, GameManager.checkpoint_count,
	]
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
	GameManager.begin_course(_course.checkpoints.size())
	_teleport(_current_avatar(), _course.start_spawn)
	_refresh_hud()
