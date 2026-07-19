extends Node2D
## res://scripts/city.gd
## The city view + interaction. Draws the build grid and placed buildings
## (blockout colours — swap for sprites later), handles placement/demolish, runs
## the economy tick, and shows a resource HUD + a building palette. All state
## lives in the GameManager autoload (persistent + save/load); this is the view.
## UI is built in code so the scene file stays a bare Node2D + script.

const COLS := 16
const ROWS := 9
const CELL := 48
const ORIGIN := Vector2(40, 120)  ## grid top-left; HUD sits above it
const TICK_SECONDS := 1.0

var _selected := "house"
var _palette_buttons := {}  ## type_id -> Button
var _res_labels := {}       ## resource -> Label
var _pause_label: Label


func _ready() -> void:
	# Receive the pause toggle even while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()

	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()

	GameManager.changed.connect(_on_changed)
	_refresh_hud()
	queue_redraw()


func _on_tick() -> void:
	if get_tree().paused:
		return
	GameManager.tick()


func _on_changed() -> void:
	_refresh_hud()
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
		if _pause_label:
			_pause_label.visible = get_tree().paused
		return
	if get_tree().paused:
		return
	if e is InputEventMouseButton and e.pressed:
		var cell := _cell_at(e.position)
		if cell.x < 0:
			return
		var key := "%d,%d" % [cell.x, cell.y]
		if e.button_index == MOUSE_BUTTON_LEFT:
			GameManager.place(key, _selected)  # emits changed → redraw
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			GameManager.demolish(key)


func _cell_at(pos: Vector2) -> Vector2i:
	var local := pos - ORIGIN
	if local.x < 0 or local.y < 0:
		return Vector2i(-1, -1)
	var c := int(local.x / CELL)
	var r := int(local.y / CELL)
	if c >= COLS or r >= ROWS:
		return Vector2i(-1, -1)
	return Vector2i(c, r)


func _draw() -> void:
	# empty cells
	for r in range(ROWS):
		for c in range(COLS):
			var p := ORIGIN + Vector2(c * CELL, r * CELL)
			draw_rect(Rect2(p, Vector2(CELL - 2, CELL - 2)), Color(0.15, 0.17, 0.14))
	# placed buildings
	for key in GameManager.buildings:
		var parts := (key as String).split(",")
		if parts.size() != 2:
			continue
		var c := int(parts[0])
		var r := int(parts[1])
		var t: Dictionary = GameManager.BUILDING_TYPES[GameManager.buildings[key]]
		var p := ORIGIN + Vector2(c * CELL + 4, r * CELL + 4)
		draw_rect(Rect2(p, Vector2(CELL - 10, CELL - 10)), t["color"])


# --- HUD (built in code) ---------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var resources := HBoxContainer.new()
	resources.position = Vector2(40, 22)
	resources.add_theme_constant_override("separation", 28)
	layer.add_child(resources)
	for res_name in ["gold", "food", "population"]:
		var lbl := Label.new()
		lbl.add_to_group(&"scalable_text")
		lbl.add_theme_font_size_override("font_size", 18)
		resources.add_child(lbl)
		_res_labels[res_name] = lbl

	var palette := HBoxContainer.new()
	palette.position = Vector2(40, 56)
	palette.add_theme_constant_override("separation", 8)
	layer.add_child(palette)
	for type_id in GameManager.BUILDING_TYPES:
		var t: Dictionary = GameManager.BUILDING_TYPES[type_id]
		var b := Button.new()
		b.text = "%s — %d g" % [t["name"], int(t["cost"])]
		b.add_to_group(&"scalable_text")
		b.pressed.connect(_select.bind(type_id))
		palette.add_child(b)
		_palette_buttons[type_id] = b

	var hint := Label.new()
	hint.position = Vector2(40, 92)
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.7, 0.72, 0.68)
	hint.text = "Left-click a cell to build the selected · right-click to demolish · Esc to pause"
	layer.add_child(hint)

	_pause_label = Label.new()
	_pause_label.position = Vector2(40, 92)
	_pause_label.add_theme_font_size_override("font_size", 12)
	_pause_label.modulate = Color(0.9, 0.75, 0.3)
	_pause_label.text = "PAUSED — Esc to resume"
	_pause_label.visible = false
	layer.add_child(_pause_label)


func _select(type_id: String) -> void:
	_selected = type_id
	_refresh_hud()


func _refresh_hud() -> void:
	if _res_labels.has("gold"):
		_res_labels["gold"].text = "Gold  %d" % GameManager.gold
	if _res_labels.has("food"):
		_res_labels["food"].text = "Food  %d" % GameManager.food
	if _res_labels.has("population"):
		_res_labels["population"].text = "Pop  %d" % GameManager.population
	for type_id in _palette_buttons:
		var b: Button = _palette_buttons[type_id]
		var affordable: bool = GameManager.can_afford(type_id)
		b.disabled = not affordable and type_id != _selected
		b.modulate = Color(1, 1, 1) if type_id == _selected else Color(0.72, 0.72, 0.72)
