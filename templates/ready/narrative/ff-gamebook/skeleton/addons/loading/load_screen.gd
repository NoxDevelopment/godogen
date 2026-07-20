extends Control
## load_screen — save-slot picker. Serves BOTH Load (from menu) and Save (in-game)
## via `mode`. Builds one card per slot from SaveManager.list_slots(): thumbnail,
## summary, timestamp. Empty slots read "Empty" (and, in save mode, are writable).
## Depends on SaveManager (save-system); typography/theme deferred to theme.tres.
##
## FF wiring: instanced as an OVERLAY (child of the menu or the pause layer), so Back
## simply closes it. In SAVE mode the card writes via SaveManager.capture_current().

enum Mode { LOAD, SAVE }
@export var mode: Mode = Mode.LOAD

@onready var _list: VBoxContainer = $Panel/VBox/Scroll/Slots
var _title: Label
var _dim: ColorRect

func _ready() -> void:
	# work while the tree is paused (the pause-menu Save overlay)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_install_chrome()
	_rebuild()

func _install_chrome() -> void:
	# a dim behind the panel so the picker reads as a modal (and eats clicks behind it)
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0.6)
	add_child(_dim)
	move_child(_dim, 0)
	# Vertical-only scrolling: without this the slot rows overflow HORIZONTALLY and the
	# trailing Load/Delete/Overwrite buttons are pushed past the panel edge and clipped
	# (unreachable). Constrain the rows to the viewport width so the buttons stay on-screen.
	var scroll := get_node_or_null("Panel/VBox/Scroll") as ScrollContainer
	if scroll != null:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# title reflects the mode + the active save mode
	_title = $Panel/VBox/Title
	_title.text = ("SAVE" if mode == Mode.SAVE else "LOAD") + _mode_suffix()
	# a Back button appended under the slot list
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_close)
	$Panel/VBox.add_child(back)

func _mode_suffix() -> String:
	var s := get_node_or_null("/root/FFSettings")
	if s != null and s.has_method("save_mode_name"):
		return "   ·   %s mode" % s.save_mode_name()
	return ""

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	if get_node_or_null("/root/SaveManager") == null:
		push_error("load_screen: SaveManager autoload missing")
		return
	for s in SaveManager.list_slots():
		_list.add_child(_make_card(s))

func _make_card(s: Dictionary) -> Control:
	var slot: int = int(s.get("slot", 0))
	var exists: bool = s.get("exists", false)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 84)
	row.add_theme_constant_override(&"separation", 12)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# clip/wrap so a long summary can never force the row wider than the panel (which
	# would shove the action buttons off the right edge — see _install_chrome).
	info.clip_contents = true
	var title := Label.new()
	title.text = str(s.get("label", "Slot %d" % slot)) + ("" if exists else "  —  Empty")
	title.add_theme_font_size_override(&"font_size", 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(title)
	if exists:
		var sub := Label.new()
		sub.text = "%s   ·   %s" % [str(s.get("summary", "")), _fmt_time(s.get("modified_time", 0))]
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(sub)
	row.add_child(info)

	var act := Button.new()
	act.custom_minimum_size = Vector2(120, 0)
	if mode == Mode.LOAD:
		act.text = "Load"
		act.disabled = not exists
		act.pressed.connect(func(): _on_load(slot))
	else:
		act.text = "Overwrite" if exists else "Save"
		act.pressed.connect(func(): _on_save(slot))
	row.add_child(act)

	if exists:
		var del := Button.new()
		del.text = "Delete"
		del.pressed.connect(func(): _on_delete(slot))
		row.add_child(del)
	return row

func _fmt_time(unix) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

func _on_load(slot: int) -> void:
	var data = SaveManager.load_from_slot(slot)
	if data == null:
		return
	get_tree().paused = false
	var target: String = data.scene_path if "scene_path" in data else ""
	if target != "" and get_node_or_null("/root/SceneLoader") != null:
		SceneLoader.change_scene(target)
	elif target != "":
		get_tree().change_scene_to_file(target)

func _on_save(slot: int) -> void:
	# Snapshot the live run (GDD §5 FFGameState) and write it atomically.
	SaveManager.save_to_slot(slot, SaveManager.capture_current())
	_rebuild()

func _on_delete(slot: int) -> void:
	SaveManager.delete_slot(slot)
	_rebuild()

func _close() -> void:
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		accept_event()
		_close()
