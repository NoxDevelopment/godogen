extends Control
## res://scripts/course_select.gd
## The course-SELECT screen — the front door to the library. It lists every
## course (built-in + user-saved + imported) from CourseLibrary, and lets the
## player:
##   • PLAY the highlighted course (sets it pending → loads the obby level),
##   • NEW to open the designer on a blank canvas,
##   • EDIT the highlighted course in the designer,
##   • IMPORT a shared .json from a path into the library, and
##   • EXPORT the highlighted course to a portable .json to hand to someone.
##
## Selecting a course sets CourseLibrary.pending_course (+ its id), which is the
## single hand-off obby.gd reads — the SAME mechanism the editor's Test uses, so
## there is one path into the level regardless of where a course came from.
##
## UI is standard Button/ItemList/LineEdit widgets with `scalable_text` labels,
## so the ui-theme / settings_system drop-ins re-skin it with no code change.

const EDITOR_SCENE := "res://scenes/course_editor.tscn"
const PLAY_SCENE := "res://scenes/obby.tscn"

var _list: ItemList
var _path_edit: LineEdit
var _status: Label
var _entries: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_list()
	print("DEBUG: course_select ready — courses=%d" % _entries.size())


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "Choose a Course"
	title.add_theme_font_size_override("font_size", 28)
	title.add_to_group(&"scalable_text")
	rows.add_child(title)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 280)
	_list.item_activated.connect(func(_i): _on_play())
	rows.add_child(_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	rows.add_child(actions)
	_button(actions, "Play", _on_play)
	_button(actions, "New", _on_new)
	_button(actions, "Edit", _on_edit)
	_button(actions, "Export", _on_export)
	_button(actions, "Refresh", _refresh_list)

	var import_row := HBoxContainer.new()
	import_row.add_theme_constant_override("separation", 8)
	rows.add_child(import_row)
	var lbl := Label.new()
	lbl.text = "Share path (.json):"
	lbl.add_to_group(&"scalable_text")
	import_row.add_child(lbl)
	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "user://shared/course.json"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_row.add_child(_path_edit)
	_button(import_row, "Import", _on_import)

	_status = Label.new()
	_status.add_to_group(&"scalable_text")
	_status.modulate = Color(0.85, 0.92, 1.0)
	rows.add_child(_status)


func _button(parent: Node, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.add_to_group(&"scalable_text")
	b.pressed.connect(cb)
	parent.add_child(b)


func _refresh_list() -> void:
	var lib := get_node_or_null("/root/CourseLibrary")
	if lib == null:
		_set_status("CourseLibrary autoload missing")
		return
	_entries = lib.list_courses()
	_list.clear()
	for e in _entries:
		var tag := "built-in" if e["source"] == "builtin" else "user"
		_list.add_item("%s   —   by %s   [%s]" % [e["name"], e["author"], tag])
	if _list.item_count > 0:
		_list.select(0)
	_set_status("%d course(s). Pick one and Play, or make your own." % _entries.size())


func _selected_entry() -> Dictionary:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return {}
	var idx := sel[0]
	if idx < 0 or idx >= _entries.size():
		return {}
	return _entries[idx]


func _on_play() -> void:
	var e := _selected_entry()
	if e.is_empty():
		_set_status("Select a course first.")
		return
	var lib := get_node_or_null("/root/CourseLibrary")
	var course: CourseData = lib.load_course(str(e["id"]))
	if course == null:
		_set_status("Could not load \"%s\"." % e.get("name", "?"))
		return
	lib.set_pending(course, str(e["id"]))
	get_tree().change_scene_to_file.call_deferred(PLAY_SCENE)


func _on_new() -> void:
	var lib := get_node_or_null("/root/CourseLibrary")
	if lib != null:
		lib.set_pending(null, "")  # blank canvas
	get_tree().change_scene_to_file.call_deferred(EDITOR_SCENE)


func _on_edit() -> void:
	var e := _selected_entry()
	if e.is_empty():
		_set_status("Select a course to edit.")
		return
	var lib := get_node_or_null("/root/CourseLibrary")
	var course: CourseData = lib.load_course(str(e["id"]))
	if course == null:
		_set_status("Could not load \"%s\"." % e.get("name", "?"))
		return
	# Edit a COPY so editing a built-in saves a new user course, never mutates it.
	lib.set_pending(course.duplicate_course(), "")
	get_tree().change_scene_to_file.call_deferred(EDITOR_SCENE)


func _on_export() -> void:
	var e := _selected_entry()
	if e.is_empty():
		_set_status("Select a course to export.")
		return
	var lib := get_node_or_null("/root/CourseLibrary")
	var course: CourseData = lib.load_course(str(e["id"]))
	if course == null:
		_set_status("Could not load \"%s\"." % e.get("name", "?"))
		return
	var dest := _path_edit.text.strip_edges()
	if dest.is_empty():
		dest = "user://shared/%s.json" % CourseLibrary.slugify(course.name)
		_path_edit.text = dest
	var err: int = lib.export_course(course, dest)
	if err == OK:
		_set_status("Exported \"%s\" → %s" % [course.name, dest])
	else:
		_set_status("Export failed (err %d)." % err)


func _on_import() -> void:
	var src := _path_edit.text.strip_edges()
	if src.is_empty():
		_set_status("Enter a .json path to import.")
		return
	var lib := get_node_or_null("/root/CourseLibrary")
	var course: CourseData = lib.import_course(src)
	if course == null:
		_set_status("Import failed: could not read/parse %s" % src)
		return
	_set_status("Imported \"%s\"." % course.name)
	_refresh_list()


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
