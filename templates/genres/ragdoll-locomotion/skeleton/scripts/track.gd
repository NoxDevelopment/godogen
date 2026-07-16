extends Control
## res://scripts/track.gd
## THE PLAY SURFACE (built entirely in code). Renders the athlete + the ground +
## a distance HUD and reads the human's per-frame MUSCLE input (Q / W / O / P),
## then bridges to nox_netcode when a session is live — the same _net_active()
## seam the obby template uses:
##   • OFFLINE (no Net autoload, or Net.active == false): it drives ONE local
##     athlete through GameManager's RagdollEngine on a FIXED-timestep accumulator
##     and renders it — a complete single-player QWOP game with zero multiplayer
##     dependency. Byte-identical whether or not the netcode nodes are present.
##   • ONLINE (a nox_netcode session running): the NetSpawner child spawns one
##     net_athlete per peer (each peer sims its OWN athlete + syncs its body pose
##     via MultiplayerSpawner + MultiplayerSynchronizer) and the NetEvents child
##     arbitrates the authoritative finish order — a real ragdoll RACE.
## All physics + rules live in RagdollEngine; this only reads state + forwards the
## chosen muscle input and renders.

const ATHLETE_SCENE := preload("res://scenes/athlete.tscn")

## Fixed-timestep accumulator so the OFFLINE sim advances at RagdollEngine.DT
## regardless of frame rate (deterministic given the input stream).
var _accum: float = 0.0

## World -> screen: the camera scrolls with the athlete so it stays on-screen.
const GROUND_SCREEN_Y: float = 470.0
const VIEW_MARGIN_X: float = 360.0

var _avatars: Node2D
var _net_spawner: Node
var _net_events: Node

# HUD
var _layer: CanvasLayer
var _title: Label
var _dist_label: Label
var _status_label: Label
var _controls_label: Label
var _banner: Label

var _cam_x: float = 0.0
var _muscle_pressed: Array = [false, false, false, false]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_avatars = get_node_or_null("Avatars")
	if _avatars == null:
		_avatars = Node2D.new()
		_avatars.name = "Avatars"
		add_child(_avatars)

	_net_spawner = get_node_or_null("NetSpawner")
	_net_events = get_node_or_null("NetEvents")

	_build_hud()

	if _net_active():
		_wire_net()
	else:
		# fresh single-player run if none is in progress.
		if GameManager.engine.finished or GameManager.engine.step_count == 0:
			GameManager.new_run(GameManager.DEFAULT_SEED, {"preset": "normal"})
	GameManager.changed.connect(_refresh_hud)
	_refresh_hud()
	queue_redraw()
	print("DEBUG: track ready — net=%s goal=%.0fm avatars=%d" % [
		str(_net_active()), GameManager.engine.goal_distance, _local_athlete_count()])


func _local_athlete_count() -> int:
	if _net_active():
		return _avatars.get_child_count()
	return 1


# =====================================================================
#  Seam: online vs offline
# =====================================================================

func _net_active() -> bool:
	var n := get_node_or_null("/root/Net")
	return n != null and bool(n.active)


func _local_peer_id() -> int:
	var n := get_node_or_null("/root/Net")
	if n != null:
		return int(n.local_id())
	return 1


## The net_athlete this client controls (online: the node named after our peer).
func _local_avatar() -> Node2D:
	if not _net_active():
		return null
	return _avatars.get_node_or_null(NodePath(str(_local_peer_id()))) as Node2D


func _wire_net() -> void:
	if _net_spawner != null and "player_scene" in _net_spawner:
		_net_spawner.player_scene = ATHLETE_SCENE
	if _net_events != null and _net_events.has_method("start_race"):
		_net_events.start_race()


# =====================================================================
#  Input — per-frame muscle state
# =====================================================================

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		if not _net_active():
			GameManager.new_run(GameManager.DEFAULT_SEED, {"preset": "normal"})
			_cam_x = 0.0


## Read the four muscle actions into a local mask each frame (offline path forwards
## them to the engine; online each net_athlete reads its own input).
func _poll_muscles() -> void:
	_muscle_pressed[RagdollEngine.MUSCLE_Q] = Input.is_action_pressed(&"muscle_q")
	_muscle_pressed[RagdollEngine.MUSCLE_W] = Input.is_action_pressed(&"muscle_w")
	_muscle_pressed[RagdollEngine.MUSCLE_O] = Input.is_action_pressed(&"muscle_o")
	_muscle_pressed[RagdollEngine.MUSCLE_P] = Input.is_action_pressed(&"muscle_p")


# =====================================================================
#  Fixed-timestep offline update
# =====================================================================

func _physics_process(delta: float) -> void:
	if _net_active():
		# online: each net_athlete sims + syncs itself; just track the camera + HUD.
		var av := _local_avatar()
		if av != null and "dist" in av:
			_cam_x = float(av.dist) * RagdollEngine.PIXELS_PER_METER
		_refresh_hud()
		queue_redraw()
		return

	var e: RagdollEngine = GameManager.engine
	if not e.finished:
		_poll_muscles()
		for i in RagdollEngine.MUSCLE_COUNT:
			e.set_muscle(i, bool(_muscle_pressed[i]))
		# advance the sim on a fixed accumulator (deterministic).
		_accum += delta
		var guard: int = 0
		while _accum >= RagdollEngine.DT and not e.finished and guard < 8:
			e.step()
			_accum -= RagdollEngine.DT
			guard += 1
		_cam_x = (e.px[RagdollEngine.N_HIP] - e.start_hip_x)
		_refresh_hud()
	queue_redraw()


# =====================================================================
#  Rendering (all in code)
# =====================================================================

func _world_to_screen(p: Vector2, offset: float) -> Vector2:
	# shift so the athlete's hip sits near VIEW_MARGIN_X; ground pins to a screen row.
	return Vector2(p.x - offset + VIEW_MARGIN_X, p.y + (GROUND_SCREEN_Y - RagdollEngine.GROUND_Y))


func _draw() -> void:
	var size := get_size()
	# backdrop.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.11, 0.16))
	# sky band.
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, GROUND_SCREEN_Y)), Color(0.12, 0.15, 0.22))
	# ground.
	draw_rect(Rect2(Vector2(0, GROUND_SCREEN_Y), Vector2(size.x, size.y - GROUND_SCREEN_Y)), Color(0.16, 0.19, 0.16))
	draw_line(Vector2(0, GROUND_SCREEN_Y), Vector2(size.x, GROUND_SCREEN_Y), Color(0.4, 0.5, 0.4), 2.0)

	# distance markers every metre.
	var offset: float = _cam_x
	var start_m: int = int(floor((offset - VIEW_MARGIN_X) / RagdollEngine.PIXELS_PER_METER)) - 1
	for m in range(start_m, start_m + 24):
		var wx: float = float(m) * RagdollEngine.PIXELS_PER_METER
		var sx: float = wx - offset + VIEW_MARGIN_X
		if sx < -40 or sx > size.x + 40:
			continue
		draw_line(Vector2(sx, GROUND_SCREEN_Y), Vector2(sx, GROUND_SCREEN_Y + 12), Color(0.4, 0.5, 0.4), 1.0)
		if m >= 0 and m % 5 == 0:
			draw_string(ThemeDB.fallback_font, Vector2(sx - 6, GROUND_SCREEN_Y + 30),
				"%dm" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.65, 0.55))

	# goal line.
	var goal_wx: float = GameManager.engine.goal_distance * RagdollEngine.PIXELS_PER_METER
	var goal_sx: float = goal_wx - offset + VIEW_MARGIN_X
	if goal_sx > -60 and goal_sx < size.x + 60:
		draw_line(Vector2(goal_sx, 120), Vector2(goal_sx, GROUND_SCREEN_Y), Color(0.95, 0.82, 0.35, 0.8), 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(goal_sx + 6, 140), "GOAL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.82, 0.35))

	if _net_active():
		# online: the net_athlete nodes draw themselves; position them by camera.
		for child in _avatars.get_children():
			var c := child as Node2D
			if c != null:
				c.position = Vector2(-offset + VIEW_MARGIN_X, GROUND_SCREEN_Y - RagdollEngine.GROUND_Y)
		return

	# offline: draw the single athlete from GameManager's engine.
	_draw_athlete(GameManager.engine, offset)


func _draw_athlete(e: RagdollEngine, offset: float) -> void:
	var fallen: bool = e.is_lost()
	var limb: Color = Color(0.55, 0.78, 0.98) if not fallen else Color(0.85, 0.45, 0.45)
	var joint: Color = Color(0.85, 0.92, 1.0) if not fallen else Color(0.95, 0.7, 0.7)
	for seg in e.bone_segments():
		var a: Vector2 = _world_to_screen(seg[0], offset)
		var b: Vector2 = _world_to_screen(seg[1], offset)
		var w: float = 8.0 if String(seg[2]) == "torso" else 5.0
		draw_line(a, b, limb, w)
	for i in RagdollEngine.NODE_COUNT:
		draw_circle(_world_to_screen(e.node_position(i), offset), 4.0, joint)
	# head.
	draw_circle(_world_to_screen(e.node_position(RagdollEngine.N_HEAD), offset), 10.0, limb)


# =====================================================================
#  HUD
# =====================================================================

func _build_hud() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	_title = _mk_label(Vector2(24, 16), 22, Color(0.86, 0.92, 0.98))
	_title.text = "RAGDOLL LOCOMOTION"
	_dist_label = _mk_label(Vector2(24, 52), 30, Color(0.95, 0.86, 0.45))
	_status_label = _mk_label(Vector2(24, 96), 16, Color(0.72, 0.82, 0.9))
	_controls_label = _mk_label(Vector2(24, 128), 14, Color(0.6, 0.68, 0.78))
	_controls_label.text = "Q / W — thighs      O / P — calves      R — restart      Esc — pause"
	_banner = _mk_label(Vector2(24, 168), 24, Color(0.96, 0.78, 0.40))
	_banner.custom_minimum_size = Vector2(760, 30)


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _refresh_hud() -> void:
	if _dist_label == null:
		return
	var dist: float = 0.0
	var goal: float = GameManager.engine.goal_distance
	var outcome: String = "running"
	if _net_active():
		var av := _local_avatar()
		if av != null and "dist" in av:
			dist = float(av.dist)
			if bool(av.won):
				outcome = "won"
			elif bool(av.fallen):
				outcome = "fell"
	else:
		var e: RagdollEngine = GameManager.engine
		dist = e.best_distance
		outcome = e.outcome
	_dist_label.text = "%.1f m" % dist
	_status_label.text = "Goal %.0f m    %s" % [goal, ("RACE" if _net_active() else "Solo")]
	match outcome:
		"won":
			_banner.text = "GOAL REACHED — you walked %.1f m!  Press R to run again." % dist
			_banner.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
		"fell":
			_banner.text = "WIPEOUT at %.1f m.  Press R to try again." % dist
			_banner.add_theme_color_override("font_color", Color(0.95, 0.5, 0.5))
		"timeout":
			_banner.text = "Time up at %.1f m.  Press R to try again." % dist
			_banner.add_theme_color_override("font_color", Color(0.9, 0.8, 0.45))
		_:
			_banner.text = ""
