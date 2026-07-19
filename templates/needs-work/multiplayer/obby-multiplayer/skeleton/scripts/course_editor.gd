extends Node2D
## res://scripts/course_editor.gd
## The in-game COURSE DESIGNER — a real edit mode where a player builds an obby
## by hand: drag out PLATFORMS and HAZARDS, drop ORDERED CHECKPOINTS (auto-
## numbered in placement order), set the START and the FINISH, all on a snap grid
## (GRID px). A palette toolbar (scalable_text buttons) picks the tool; a name
## field + Save writes the course into the CourseLibrary; Test loads it straight
## into the play level.
##
## The editor and the player share ONE course format: everything the designer
## does accumulates into plain state that `build_course_data()` turns into a
## CourseData — the exact class obby.gd builds a level from. There is no editor-
## only format, so a course authored here is guaranteed to load and play.
##
## Two ways to drive it, both real and identical in effect:
##   • Mouse/UI (a person editing): _unhandled_input → pointer_press/release.
##   • API (tools, tests, procedural authoring): set_tool / place_platform /
##     add_checkpoint / add_hazard / set_start / set_finish / delete_at.
## The mouse path calls the SAME API methods, so what you can do by hand you can
## do in code and vice-versa.

enum Tool { PLATFORM, HAZARD, CHECKPOINT, START, FINISH, DELETE }

const GRID := 20.0                       ## snap step in world px.
const CHECKPOINT_SIZE := Vector2(36, 96) ## gate visual/logical size.
const MIN_RECT := 8.0                    ## smallest drag that counts as a rect.
const SELECT_SCENE := "res://scenes/course_select.tscn"
const PLAY_SCENE := "res://scenes/obby.tscn"

# --- authored state (becomes a CourseData) -----------------------------------
var _platforms: Array[Rect2] = []
var _hazards: Array[Rect2] = []
var _checkpoints: Array[Vector2] = []
var _start: Vector2 = Vector2(80, 400)
var _finish: Rect2 = Rect2(0, 0, 0, 0)   ## zero size == not placed yet.
var _kill_y: float = 700.0

# --- editing session ---------------------------------------------------------
var _tool: int = Tool.PLATFORM
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_now := Vector2.ZERO
var _panning := false

var _camera: Camera2D
var _name_edit: LineEdit
var _status: Label
var _tool_buttons: Dictionary = {}       ## Tool -> Button
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_camera = Camera2D.new()
	_camera.position = Vector2(640, 360)
	add_child(_camera)
	_camera.make_current()
	# If we arrived here to EDIT an existing course, adopt it.
	var lib := get_node_or_null("/root/CourseLibrary")
	if lib != null and lib.pending_course != null:
		load_course(lib.pending_course)
		lib.pending_course = null
		lib.pending_course_id = ""
	_build_ui()
	_refresh_tool_ui()
	_set_status("Ready — pick a tool, drag to build. Grid %dpx." % int(GRID))
	queue_redraw()
	print("DEBUG: course_editor ready — tool=%s grid=%d" % [_tool_name(_tool), int(GRID)])


# =====================================================================
#  Public authoring API (mouse + code both go through here)
# =====================================================================

func set_tool(tool: int) -> void:
	_tool = tool
	_refresh_tool_ui()
	_set_status("Tool: %s" % _tool_name(tool))
	queue_redraw()


## Snap a world position to the editor grid.
func snap(pos: Vector2) -> Vector2:
	return (pos / GRID).round() * GRID


## Add a platform. Rect is normalised to a positive size and snapped. Returns its
## index, or -1 if too small to be a real platform.
func place_platform(rect: Rect2) -> int:
	var r := _norm_snap(rect)
	if r.size.x < MIN_RECT or r.size.y < MIN_RECT:
		return -1
	_platforms.append(r)
	queue_redraw()
	return _platforms.size() - 1


## Add a hazard kill-zone. Same normalisation as platforms. Returns index or -1.
func add_hazard(rect: Rect2) -> int:
	var r := _norm_snap(rect)
	if r.size.x < MIN_RECT or r.size.y < MIN_RECT:
		return -1
	_hazards.append(r)
	queue_redraw()
	return _hazards.size() - 1


## Drop the next checkpoint. Checkpoints are numbered by PLACEMENT ORDER — the
## returned index is the gate number (0,1,2,…) a run must clear it in.
func add_checkpoint(pos: Vector2) -> int:
	_checkpoints.append(snap(pos))
	queue_redraw()
	return _checkpoints.size() - 1


func set_start(pos: Vector2) -> void:
	_start = snap(pos)
	queue_redraw()


func set_finish(rect: Rect2) -> void:
	_finish = _norm_snap(rect)
	queue_redraw()


func set_kill_y(y: float) -> void:
	_kill_y = y


## Delete the topmost authored element under `pos` (checkpoint → hazard →
## platform priority). Returns true if something was removed.
func delete_at(pos: Vector2) -> bool:
	for i in range(_checkpoints.size() - 1, -1, -1):
		var cp_rect := Rect2(_checkpoints[i] - CHECKPOINT_SIZE / 2.0, CHECKPOINT_SIZE)
		if cp_rect.has_point(pos):
			_checkpoints.remove_at(i)
			queue_redraw()
			return true
	for i in range(_hazards.size() - 1, -1, -1):
		if _hazards[i].has_point(pos):
			_hazards.remove_at(i)
			queue_redraw()
			return true
	for i in range(_platforms.size() - 1, -1, -1):
		if _platforms[i].has_point(pos):
			_platforms.remove_at(i)
			queue_redraw()
			return true
	if _finish.size != Vector2.ZERO and _finish.has_point(pos):
		_finish = Rect2(0, 0, 0, 0)
		queue_redraw()
		return true
	return false


## Wipe the canvas back to an empty course (start kept).
func clear_course() -> void:
	_platforms.clear()
	_hazards.clear()
	_checkpoints.clear()
	_finish = Rect2(0, 0, 0, 0)
	queue_redraw()


## Assemble the current canvas into a CourseData (the shared course format).
func build_course_data(course_name: String, author: String = "Anonymous") -> CourseData:
	var c := CourseData.create(course_name, author)
	c.start_spawn = _start
	c.kill_y = _kill_y
	c.finish = _finish
	var plats: Array[Rect2] = []
	plats.append_array(_platforms)
	c.platforms = plats
	var hz: Array[Rect2] = []
	hz.append_array(_hazards)
	c.hazards = hz
	var cps: Array[Vector2] = []
	cps.append_array(_checkpoints)
	c.checkpoints = cps
	return c


## Adopt an existing course into the editor for further editing.
func load_course(course: CourseData) -> void:
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
	queue_redraw()


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
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				pointer_press(get_global_mouse_position())
			else:
				pointer_release(get_global_mouse_position())
			return
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _panning:
			_camera.position -= mm.relative
			queue_redraw()
		elif _dragging:
			_drag_now = get_global_mouse_position()
			queue_redraw()


## Begin an action at `world_pos`. Point tools (checkpoint/start/delete) act
## immediately; rect tools (platform/hazard/finish) start a drag.
func pointer_press(world_pos: Vector2) -> void:
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


## Finish a rect drag at `world_pos`, committing the rect to the active tool.
func pointer_release(world_pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	var rect := _rect_from(_drag_start, world_pos)
	match _tool:
		Tool.PLATFORM:
			place_platform(rect)
		Tool.HAZARD:
			add_hazard(rect)
		Tool.FINISH:
			set_finish(rect)
	queue_redraw()


# =====================================================================
#  Rendering
# =====================================================================

func _draw() -> void:
	_draw_grid()
	for r in _platforms:
		draw_rect(r, Color(0.36, 0.40, 0.48))
		draw_rect(r, Color(0.7, 0.75, 0.85, 0.6), false, 1.0)
	for r in _hazards:
		draw_rect(r, Color(0.9, 0.35, 0.35, 0.85))
	if _finish.size != Vector2.ZERO:
		draw_rect(_finish, Color(0.95, 0.86, 0.45, 0.7))
		draw_string(_font, _finish.position + Vector2(4, 16), "FINISH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
	for i in _checkpoints.size():
		var pos := _checkpoints[i]
		var cp_rect := Rect2(pos - CHECKPOINT_SIZE / 2.0, CHECKPOINT_SIZE)
		draw_rect(cp_rect, Color(0.45, 0.85, 0.55, 0.55))
		draw_string(_font, pos + Vector2(-6, -CHECKPOINT_SIZE.y / 2.0 - 4), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 1.0, 0.9))
	# start marker
	draw_circle(_start, 8.0, Color(0.45, 0.72, 0.95))
	draw_string(_font, _start + Vector2(10, 4), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.85, 1.0))
	# fall line
	draw_line(Vector2(_camera.position.x - 2000, _kill_y), Vector2(_camera.position.x + 2000, _kill_y), Color(0.8, 0.3, 0.3, 0.5), 1.0)
	# live drag preview
	if _dragging:
		var preview := _rect_from(_drag_start, _drag_now)
		var col := Color(0.7, 0.8, 1.0, 0.4)
		if _tool == Tool.HAZARD:
			col = Color(0.95, 0.5, 0.5, 0.4)
		elif _tool == Tool.FINISH:
			col = Color(0.95, 0.9, 0.5, 0.4)
		draw_rect(preview, col)


func _draw_grid() -> void:
	var view := Rect2(_camera.position - Vector2(700, 420), Vector2(1400, 840))
	var col := Color(1, 1, 1, 0.05)
	var x: float = floor(view.position.x / GRID) * GRID
	while x < view.position.x + view.size.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.position.y + view.size.y), col, 1.0)
		x += GRID
	var y: float = floor(view.position.y / GRID) * GRID
	while y < view.position.y + view.size.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.position.x + view.size.x, y), col, 1.0)
		y += GRID


# =====================================================================
#  UI (palette toolbar + name field + actions)
# =====================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "EditorUI"
	add_child(layer)

	var root := VBoxContainer.new()
	root.position = Vector2(12, 8)
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

	# Name + actions
	var actions := HBoxContainer.new()
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

func _norm_snap(rect: Rect2) -> Rect2:
	var r := rect.abs()
	var tl := snap(r.position)
	var br := snap(r.position + r.size)
	return Rect2(tl, br - tl)


func _rect_from(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(a, b - a).abs()


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
