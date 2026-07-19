extends Node3D
## res://scripts/course_editor3d.gd
## The in-game 3D COURSE DESIGNER — a real edit mode where a player builds an obby
## by hand from a TOP-DOWN ORTHOGRAPHIC view: click/drag on the X/Z ground plane
## to lay out box PLATFORMS and HAZARDS, drop ORDERED CHECKPOINTS (auto-numbered
## in placement order), set the START and the FINISH volume, all on a snap grid
## (GRID world-units in X/Z) at a chosen elevation (the Height slider drives the Y
## the next placement sits at). A palette toolbar (scalable_text buttons) picks
## the tool; a name field + Save writes the course into the CourseLibrary; Test
## loads it straight into the play level.
##
## The editor and the player share ONE course format: everything the designer
## does accumulates into plain state that `build_course_data()` turns into a
## CourseData3D — the exact class obby3d.gd builds a level from. There is no
## editor-only format, so a course authored here is guaranteed to load and play.
##
## Two ways to drive it, both real and identical in effect:
##   • Mouse/UI (a person editing): _unhandled_input → screen→ground raycast →
##     pointer_press/pointer_release.
##   • API (tools, tests, procedural authoring): set_tool / place_platform /
##     add_checkpoint / add_hazard / set_start / set_finish / delete_at.
## The mouse path calls the SAME API methods, so what you can do by hand you can
## do in code and vice-versa. It is course_editor.gd (the 2D template) with the
## drag-rect X/Y canvas swapped for a top-down X/Z ground plane + a Y elevation.

enum Tool { PLATFORM, HAZARD, CHECKPOINT, START, FINISH, DELETE }

const GRID := 1.0                         ## snap step in world units (X/Z).
const MIN_BOX := 0.5                      ## smallest footprint that counts as a box.
const CHECKPOINT_PICK_RADIUS := 1.4       ## XZ radius for delete-picking a checkpoint.
const SELECT_SCENE := "res://scenes/course_select.tscn"
const PLAY_SCENE := "res://scenes/obby3d.tscn"

const CAM_HEIGHT := 40.0                  ## ortho camera altitude above the plane.
const ZOOM_MIN := 8.0
const ZOOM_MAX := 90.0

# --- authored state (becomes a CourseData3D) ---------------------------------
var _platforms: Array[AABB] = []
var _hazards: Array[AABB] = []
var _checkpoints: Array[Vector3] = []
var _start: Vector3 = Vector3(0.0, 1.2, 0.0)
var _finish: AABB = AABB(Vector3.ZERO, Vector3.ZERO)  ## zero volume == not placed yet.
var _kill_y: float = -8.0

# --- placement controls ------------------------------------------------------
var _height: float = 0.0                  ## elevation (bottom Y) the next box/point sits at.
var _box_thickness: float = 1.0           ## Y size of placed boxes.

# --- editing session ---------------------------------------------------------
var _tool: int = Tool.PLATFORM
var _dragging := false
var _drag_start := Vector3.ZERO
var _drag_now := Vector3.ZERO
var _panning := false

var _camera: Camera3D
var _preview_root: Node3D
var _grid_mesh: MeshInstance3D
var _name_edit: LineEdit
var _status: Label
var _height_slider: HSlider
var _height_label: Label
var _tool_buttons: Dictionary = {}        ## Tool -> Button


func _ready() -> void:
	_build_environment()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 40.0
	_camera.position = Vector3(0.0, CAM_HEIGHT, 0.0)
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # look straight down (-Y)
	_camera.near = 0.05
	_camera.far = 200.0
	add_child(_camera)
	_camera.make_current()

	_preview_root = Node3D.new()
	_preview_root.name = "Preview"
	add_child(_preview_root)
	_build_grid()

	# If we arrived here to EDIT an existing course, adopt it.
	var lib := get_node_or_null("/root/CourseLibrary")
	if lib != null and lib.pending_course != null:
		load_course(lib.pending_course)
		lib.pending_course = null
		lib.pending_course_id = ""

	_build_ui()
	_refresh_tool_ui()
	_rebuild_preview()
	_set_status("Ready — pick a tool, click/drag the ground to build. Grid %.1fu." % GRID)
	print("DEBUG: course_editor3d ready — tool=%s grid=%.1f" % [_tool_name(_tool), GRID])


# =====================================================================
#  Public authoring API (mouse + code both go through here)
# =====================================================================

func set_tool(tool: int) -> void:
	_tool = tool
	_refresh_tool_ui()
	_set_status("Tool: %s" % _tool_name(tool))


## Snap a world position to the editor grid in X/Z (Y untouched).
func snap_xz(pos: Vector3) -> Vector3:
	return Vector3(round(pos.x / GRID) * GRID, pos.y, round(pos.z / GRID) * GRID)


## Set the elevation (bottom Y) new boxes/points are placed at.
func set_height(y: float) -> void:
	_height = y
	if _height_slider != null and not is_equal_approx(_height_slider.value, y):
		_height_slider.value = y
	if _height_label != null:
		_height_label.text = "Height: %.1f" % _height


## Set the Y thickness of newly placed boxes.
func set_box_thickness(t: float) -> void:
	_box_thickness = maxf(t, 0.1)


## Add a platform. AABB is normalised to positive size and snapped in X/Z. Returns
## its index, or -1 if the footprint is too small to be a real platform.
func place_platform(box: AABB) -> int:
	var b := _norm_snap(box)
	if b.size.x < MIN_BOX or b.size.z < MIN_BOX:
		return -1
	_platforms.append(b)
	_rebuild_preview()
	return _platforms.size() - 1


## Add a hazard kill-volume. Same normalisation as platforms. Returns index or -1.
func add_hazard(box: AABB) -> int:
	var b := _norm_snap(box)
	if b.size.x < MIN_BOX or b.size.z < MIN_BOX:
		return -1
	_hazards.append(b)
	_rebuild_preview()
	return _hazards.size() - 1


## Drop the next checkpoint. Checkpoints are numbered by PLACEMENT ORDER — the
## returned index is the gate number (0,1,2,…) a run must clear it in.
func add_checkpoint(pos: Vector3) -> int:
	var p := snap_xz(pos)
	_checkpoints.append(p)
	_rebuild_preview()
	return _checkpoints.size() - 1


func set_start(pos: Vector3) -> void:
	_start = snap_xz(pos)
	_rebuild_preview()


func set_finish(box: AABB) -> void:
	_finish = _norm_snap(box)
	_rebuild_preview()


func set_kill_y(y: float) -> void:
	_kill_y = y


## Delete the topmost authored element under `pos` (checkpoint → hazard →
## platform → finish priority), picking by X/Z footprint (top-down). Returns true
## if something was removed.
func delete_at(pos: Vector3) -> bool:
	for i in range(_checkpoints.size() - 1, -1, -1):
		var cp := _checkpoints[i]
		if Vector2(cp.x - pos.x, cp.z - pos.z).length() <= CHECKPOINT_PICK_RADIUS:
			_checkpoints.remove_at(i)
			_rebuild_preview()
			return true
	for i in range(_hazards.size() - 1, -1, -1):
		if _xz_has_point(_hazards[i], pos):
			_hazards.remove_at(i)
			_rebuild_preview()
			return true
	for i in range(_platforms.size() - 1, -1, -1):
		if _xz_has_point(_platforms[i], pos):
			_platforms.remove_at(i)
			_rebuild_preview()
			return true
	if _finish.size != Vector3.ZERO and _xz_has_point(_finish, pos):
		_finish = AABB(Vector3.ZERO, Vector3.ZERO)
		_rebuild_preview()
		return true
	return false


## Wipe the canvas back to an empty course (start kept).
func clear_course() -> void:
	_platforms.clear()
	_hazards.clear()
	_checkpoints.clear()
	_finish = AABB(Vector3.ZERO, Vector3.ZERO)
	_rebuild_preview()


## Assemble the current canvas into a CourseData3D (the shared course format).
func build_course_data(course_name: String, author: String = "Anonymous") -> CourseData3D:
	var c := CourseData3D.create(course_name, author)
	c.start_spawn = _start
	c.kill_y = _kill_y
	c.finish = _finish
	var plats: Array[AABB] = []
	plats.append_array(_platforms)
	c.platforms = plats
	var hz: Array[AABB] = []
	hz.append_array(_hazards)
	c.hazards = hz
	var cps: Array[Vector3] = []
	cps.append_array(_checkpoints)
	c.checkpoints = cps
	return c


## Adopt an existing course into the editor for further editing.
func load_course(course: CourseData3D) -> void:
	if course == null:
		return
	_start = course.start_spawn
	_kill_y = course.kill_y
	_finish = course.finish
	_platforms = course.platforms.duplicate()
	_hazards = course.hazards.duplicate()
	_checkpoints = course.checkpoints.duplicate()
	if _name_edit != null:
		_name_edit.text = course.name
	_rebuild_preview()


## Save the current canvas to the library under `course_name`. Returns the
## library id ("user:<slug>") or "" if invalid / write failed.
func save_as(course_name: String) -> String:
	var c := build_course_data(course_name, _author())
	if not c.is_valid():
		_set_status("Cannot save: " + ", ".join(c.validation_errors()))
		return ""
	var lib := get_node_or_null("/root/CourseLibrary")
	if lib == null:
		_set_status("Cannot save: CourseLibrary autoload missing")
		return ""
	var id: String = lib.save_course(c)
	if id.is_empty():
		_set_status("Save failed (write error)")
	else:
		_set_status("Saved \"%s\" → %s" % [course_name, id])
	return id


## Build the current canvas and load it straight into the play level. Returns
## false (and reports why) if the course is not yet playable.
func test_course(course_name: String = "Test Course") -> bool:
	var c := build_course_data(course_name, _author())
	if not c.is_valid():
		_set_status("Cannot test: " + ", ".join(c.validation_errors()))
		return false
	var lib := get_node_or_null("/root/CourseLibrary")
	if lib != null:
		lib.set_pending(c, "")   # custom course → sent as full JSON online
	get_tree().change_scene_to_file.call_deferred(PLAY_SCENE)
	return true


# =====================================================================
#  Mouse / keyboard editing (routes through the API above)
# =====================================================================

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_camera.size = clampf(_camera.size * 0.9, ZOOM_MIN, ZOOM_MAX)
			_build_grid()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_camera.size = clampf(_camera.size * 1.1, ZOOM_MIN, ZOOM_MAX)
			_build_grid()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var ground := _ground_point(mb.position)
			if mb.pressed:
				pointer_press(ground)
			else:
				pointer_release(ground)
			return
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _panning:
			# Screen drag → move the camera across the X/Z plane (ortho: 1px scales
			# with the visible size / viewport width).
			var vp := get_viewport().get_visible_rect().size
			var world_per_px := _camera.size / maxf(vp.x, 1.0)
			_camera.position += Vector3(-mm.relative.x * world_per_px, 0.0, -mm.relative.y * world_per_px)
			_build_grid()
		elif _dragging:
			_drag_now = _ground_point(mm.position)
			_rebuild_preview()


## Begin an action at ground point `world_pos`. Point tools (checkpoint/start/
## delete) act immediately; box tools (platform/hazard/finish) start a drag.
func pointer_press(world_pos: Vector3) -> void:
	match _tool:
		Tool.CHECKPOINT:
			add_checkpoint(world_pos)
		Tool.START:
			set_start(world_pos)
		Tool.DELETE:
			delete_at(world_pos)
		_:
			_dragging = true
			_drag_start = world_pos
			_drag_now = world_pos


## Finish a box drag at ground point `world_pos`, committing the box to the tool.
func pointer_release(world_pos: Vector3) -> void:
	if not _dragging:
		return
	_dragging = false
	var box := _box_from(_drag_start, world_pos)
	match _tool:
		Tool.PLATFORM:
			place_platform(box)
		Tool.HAZARD:
			add_hazard(box)
		Tool.FINISH:
			set_finish(box)
	_rebuild_preview()


# =====================================================================
#  Screen → world ground plane
# =====================================================================

## Raycast the pointer onto the horizontal plane Y = _height and snap it in X/Z.
## Works for the top-down ortho camera (the ray points straight down).
func _ground_point(screen_pos: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.000001:
		return snap_xz(Vector3(origin.x, _height, origin.z))
	var t := (_height - origin.y) / dir.y
	var hit := origin + dir * t
	return snap_xz(Vector3(hit.x, _height, hit.z))


# =====================================================================
#  Rendering (real preview meshes, rebuilt on change)
# =====================================================================

func _rebuild_preview() -> void:
	if _preview_root == null:
		return
	for child in _preview_root.get_children():
		child.queue_free()
	for b in _platforms:
		_add_box_preview(b, Color(0.36, 0.40, 0.48), 0.9)
	for b in _hazards:
		_add_box_preview(b, Color(0.9, 0.35, 0.35), 0.65)
	if _finish.size != Vector3.ZERO:
		_add_box_preview(_finish, Color(0.95, 0.86, 0.45), 0.55)
		_add_label(_finish.position + _finish.size / 2.0, "FINISH", Color(0.95, 0.86, 0.45))
	for i in _checkpoints.size():
		var pos := _checkpoints[i]
		_add_box_preview(AABB(pos + Vector3(-0.25, 0.0, -0.25), Vector3(0.5, 3.0, 0.5)),
			Color(0.45, 0.85, 0.55), 0.55)
		_add_label(pos + Vector3(0.0, 3.2, 0.0), str(i), Color(0.85, 1.0, 0.9))
	# start marker
	_add_box_preview(AABB(_start + Vector3(-0.4, -0.4, -0.4), Vector3(0.8, 0.8, 0.8)),
		Color(0.45, 0.72, 0.95), 0.8)
	_add_label(_start + Vector3(0.0, 1.0, 0.0), "START", Color(0.7, 0.85, 1.0))
	# live drag preview
	if _dragging:
		var preview := _box_from(_drag_start, _drag_now)
		var col := Color(0.7, 0.8, 1.0)
		if _tool == Tool.HAZARD:
			col = Color(0.95, 0.5, 0.5)
		elif _tool == Tool.FINISH:
			col = Color(0.95, 0.9, 0.5)
		if preview.size.x >= MIN_BOX and preview.size.z >= MIN_BOX:
			_add_box_preview(preview, col, 0.35)


func _add_box_preview(box: AABB, color: Color, alpha: float) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.position = box.position + box.size / 2.0
	mesh.material_override = _mat(color, alpha)
	_preview_root.add_child(mesh)


func _add_label(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.02
	_preview_root.add_child(l)


func _mat(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _build_grid() -> void:
	if _grid_mesh != null and is_instance_valid(_grid_mesh):
		_grid_mesh.queue_free()
	_grid_mesh = MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.08)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = false
	var half: float = clampf(_camera.size, ZOOM_MIN, ZOOM_MAX) if _camera != null else 40.0
	var cx: float = round((_camera.position.x if _camera != null else 0.0) / GRID) * GRID
	var cz: float = round((_camera.position.z if _camera != null else 0.0) / GRID) * GRID
	var lines := int(half / GRID) + 2
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var i := -lines
	while i <= lines:
		var x := cx + float(i) * GRID
		im.surface_add_vertex(Vector3(x, 0.0, cz - float(lines) * GRID))
		im.surface_add_vertex(Vector3(x, 0.0, cz + float(lines) * GRID))
		var z := cz + float(i) * GRID
		im.surface_add_vertex(Vector3(cx - float(lines) * GRID, 0.0, z))
		im.surface_add_vertex(Vector3(cx + float(lines) * GRID, 0.0, z))
		i += 1
	im.surface_end()
	_grid_mesh.mesh = im
	add_child(_grid_mesh)


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.08, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.68)
	e.ambient_light_energy = 1.0
	world.environment = e
	add_child(world)


# =====================================================================
#  UI (palette toolbar + height + name field + actions)
# =====================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "EditorUI"
	add_child(layer)

	var root := VBoxContainer.new()
	root.position = Vector2(12, 8)
	root.add_theme_constant_override("separation", 6)
	layer.add_child(root)

	# Tool palette
	var palette := HBoxContainer.new()
	root.add_child(palette)
	for tool in [Tool.PLATFORM, Tool.HAZARD, Tool.CHECKPOINT, Tool.START, Tool.FINISH, Tool.DELETE]:
		var b := Button.new()
		b.text = _tool_name(tool)
		b.add_to_group(&"scalable_text")
		b.pressed.connect(set_tool.bind(tool))
		palette.add_child(b)
		_tool_buttons[tool] = b

	# Height (elevation) + box thickness controls
	var placement := HBoxContainer.new()
	placement.add_theme_constant_override("separation", 8)
	root.add_child(placement)
	_height_label = Label.new()
	_height_label.text = "Height: %.1f" % _height
	_height_label.add_to_group(&"scalable_text")
	placement.add_child(_height_label)
	_height_slider = HSlider.new()
	_height_slider.min_value = -10.0
	_height_slider.max_value = 20.0
	_height_slider.step = 0.5
	_height_slider.value = _height
	_height_slider.custom_minimum_size = Vector2(180, 0)
	_height_slider.value_changed.connect(func(v): set_height(v))
	placement.add_child(_height_slider)
	var thick_label := Label.new()
	thick_label.text = "Box H:"
	thick_label.add_to_group(&"scalable_text")
	placement.add_child(thick_label)
	var thick := SpinBox.new()
	thick.min_value = 0.1
	thick.max_value = 10.0
	thick.step = 0.1
	thick.value = _box_thickness
	thick.value_changed.connect(func(v): set_box_thickness(v))
	placement.add_child(thick)

	# Name + actions
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	root.add_child(actions)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.add_to_group(&"scalable_text")
	actions.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.text = "My Course"
	_name_edit.custom_minimum_size = Vector2(220, 0)
	actions.add_child(_name_edit)
	_action_button(actions, "Save", _on_save)
	_action_button(actions, "Test", _on_test)
	_action_button(actions, "Clear", func(): clear_course(); _set_status("Cleared."))
	_action_button(actions, "Back", _on_back)

	_status = Label.new()
	_status.add_to_group(&"scalable_text")
	_status.modulate = Color(0.9, 0.95, 1.0)
	root.add_child(_status)


func _action_button(parent: Node, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.add_to_group(&"scalable_text")
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_save() -> void:
	save_as(_course_name())


func _on_test() -> void:
	test_course(_course_name())


func _on_back() -> void:
	get_tree().change_scene_to_file.call_deferred(SELECT_SCENE)


func _refresh_tool_ui() -> void:
	for tool in _tool_buttons:
		var b := _tool_buttons[tool] as Button
		b.modulate = Color(1, 1, 0.6) if tool == _tool else Color(1, 1, 1)


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# =====================================================================
#  Helpers
# =====================================================================

## Normalise + snap a box: positive size, min corner + far corner snapped in X/Z,
## Y (elevation) and Y-size (thickness) kept as authored.
func _norm_snap(box: AABB) -> AABB:
	var b := box.abs()
	var min_x: float = round(b.position.x / GRID) * GRID
	var min_z: float = round(b.position.z / GRID) * GRID
	var max_x: float = round((b.position.x + b.size.x) / GRID) * GRID
	var max_z: float = round((b.position.z + b.size.z) / GRID) * GRID
	return AABB(
		Vector3(min_x, b.position.y, min_z),
		Vector3(max_x - min_x, b.size.y, max_z - min_z),
	)


## Build a box from two ground points: XZ footprint between them, bottom at
## _height, thickness _box_thickness.
func _box_from(a: Vector3, b: Vector3) -> AABB:
	var min_x := minf(a.x, b.x)
	var min_z := minf(a.z, b.z)
	var sx := absf(a.x - b.x)
	var sz := absf(a.z - b.z)
	return AABB(Vector3(min_x, _height, min_z), Vector3(sx, _box_thickness, sz))


## Does `pos` fall inside `box`'s X/Z footprint (Y ignored — top-down picking)?
func _xz_has_point(box: AABB, pos: Vector3) -> bool:
	return pos.x >= box.position.x and pos.x <= box.position.x + box.size.x \
		and pos.z >= box.position.z and pos.z <= box.position.z + box.size.z


func _course_name() -> String:
	if _name_edit != null and not _name_edit.text.strip_edges().is_empty():
		return _name_edit.text.strip_edges()
	return "My Course"


func _author() -> String:
	var n := get_node_or_null("/root/Net")
	if n != null and "local_name" in n and not str(n.local_name).is_empty():
		return str(n.local_name)
	return "Anonymous"


func _tool_name(tool: int) -> String:
	match tool:
		Tool.PLATFORM: return "Platform"
		Tool.HAZARD: return "Hazard"
		Tool.CHECKPOINT: return "Checkpoint"
		Tool.START: return "Start"
		Tool.FINISH: return "Finish"
		Tool.DELETE: return "Delete"
	return "?"
