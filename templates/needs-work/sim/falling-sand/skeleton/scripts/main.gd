extends Control
## res://scripts/main.gd
## THE SANDBOX SCREEN (built entirely in code). Renders GameManager.world to an
## ImageTexture — one pixel per cell, material→colour — shown on a TextureRect,
## and steps it on the physics tick. A material PALETTE (buttons) selects the
## brush; mouse-drag paints; a brush-size stepper + pause / step / clear controls
## drive the simulation. All physics lives in SandWorld; this only paints inputs
## in and reads cells out, so the sim is fully playable AND headless-testable.

## Material → display colour (index == material id).
const MAT_COLOR: PackedColorArray = [
	Color(0.05, 0.05, 0.08),   # EMPTY  — near-black air
	Color(0.85, 0.74, 0.42),   # SAND
	Color(0.24, 0.44, 0.86),   # WATER
	Color(0.42, 0.42, 0.46),   # STONE
	Color(0.48, 0.31, 0.16),   # WOOD
	Color(0.26, 0.62, 0.28),   # PLANT
	Color(0.36, 0.30, 0.12),   # OIL
	Color(0.92, 0.36, 0.11),   # LAVA
	Color(0.98, 0.66, 0.16),   # FIRE
	Color(0.55, 0.55, 0.58),   # SMOKE
	Color(0.80, 0.86, 0.92),   # STEAM
	Color(0.60, 0.90, 0.20),   # ACID
	Color(0.70, 0.88, 0.98),   # ICE
	Color(0.32, 0.30, 0.30),   # ASH
]

const MAT_NAME := {
	SandWorld.EMPTY: "Erase", SandWorld.SAND: "Sand", SandWorld.WATER: "Water",
	SandWorld.STONE: "Stone", SandWorld.WOOD: "Wood", SandWorld.PLANT: "Plant",
	SandWorld.OIL: "Oil", SandWorld.LAVA: "Lava", SandWorld.FIRE: "Fire",
	SandWorld.ACID: "Acid", SandWorld.ICE: "Ice",
}

const DISPLAY_SIZE := Vector2(800, 600)  ## the grid is drawn at this pixel size

var _layer: CanvasLayer
var _view: TextureRect
var _image: Image
var _texture: ImageTexture
var _rgb := PackedByteArray()
var _palette_box: HBoxContainer
var _status: Label
var _selected: int = SandWorld.SAND
var _brush: int = 3
var _paused: bool = false
var _painting: bool = false
var _scale: Vector2 = Vector2.ONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameManager.world_reset.connect(_on_world_reset)
	_on_world_reset()


func _on_world_reset() -> void:
	var w := GameManager.world.width
	var h := GameManager.world.height
	_scale = Vector2(DISPLAY_SIZE.x / float(w), DISPLAY_SIZE.y / float(h))
	_image = Image.create(w, h, false, Image.FORMAT_RGB8)
	_texture = ImageTexture.create_from_image(_image)
	_view.texture = _texture
	_rgb = PackedByteArray()
	_rgb.resize(w * h * 3)
	_render()


func _physics_process(_delta: float) -> void:
	if not _paused:
		GameManager.world.step()
	if _painting:
		_paint_at_mouse()
	_render()
	_update_status()


# =====================================================================
#  Rendering — cells → RGB8 image → texture
# =====================================================================

func _render() -> void:
	var world := GameManager.world
	var cells := world.get_cells()
	var n := cells.size()
	var p := 0
	for i in n:
		var col := MAT_COLOR[cells[i]]
		_rgb[p] = int(col.r * 255.0)
		_rgb[p + 1] = int(col.g * 255.0)
		_rgb[p + 2] = int(col.b * 255.0)
		p += 3
	_image.set_data(world.width, world.height, false, Image.FORMAT_RGB8, _rgb)
	_texture.update(_image)


# =====================================================================
#  Input → brush
# =====================================================================

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			if _painting:
				_paint_at_mouse()
	elif e.is_action_pressed(&"pause"):
		_paused = not _paused
	elif e.is_action_pressed(&"restart"):
		GameManager.new_world(0)


func _paint_at_mouse() -> void:
	var local := _view.get_local_mouse_position()
	if local.x < 0 or local.y < 0 or local.x >= DISPLAY_SIZE.x or local.y >= DISPLAY_SIZE.y:
		return
	var cx := int(local.x / _scale.x)
	var cy := int(local.y / _scale.y)
	GameManager.world.paint(_selected, cx, cy, _brush)


## Public helper used by the UI-build probe: paint at a cell, refresh the frame.
func paint_cell(mat: int, cx: int, cy: int, radius: int) -> void:
	GameManager.world.paint(mat, cx, cy, radius)
	_render()


## The CPU-side rendered frame (what feeds the texture). Exposed so a headless
## probe can verify the render without an unreliable GPU texture read-back.
func get_render_image() -> Image:
	return _image


# =====================================================================
#  UI construction (all in code)
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_header(Vector2(24, 16), "FALLING SAND — cellular-automata sandbox", 22,
		Color(0.90, 0.86, 0.66))

	_view = TextureRect.new()
	_view.position = Vector2(24, 56)
	_view.custom_minimum_size = DISPLAY_SIZE
	_view.size = DISPLAY_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.add_to_group(&"grid_view")
	_layer.add_child(_view)

	# --- material palette ---------------------------------------------------
	_header(Vector2(24, 668), "MATERIAL", 15, Color(0.8, 0.8, 0.78))
	_palette_box = HBoxContainer.new()
	_palette_box.position = Vector2(120, 664)
	_palette_box.add_theme_constant_override("separation", 6)
	_palette_box.add_to_group(&"palette")
	_layer.add_child(_palette_box)
	for mat in SandWorld.PAINTABLE:
		var b := Button.new()
		b.text = String(MAT_NAME.get(mat, "?"))
		b.toggle_mode = true
		b.button_pressed = (mat == _selected)
		b.add_theme_color_override("font_color", MAT_COLOR[mat] if mat != SandWorld.EMPTY \
			else Color(0.8, 0.8, 0.8))
		b.add_to_group(&"scalable_text")
		b.pressed.connect(_on_pick.bind(mat, b))
		_palette_box.add_child(b)

	# --- controls -----------------------------------------------------------
	var ctrl := HBoxContainer.new()
	ctrl.position = Vector2(844, 56)
	ctrl.add_theme_constant_override("separation", 8)
	_layer.add_child(ctrl)

	var pause_btn := _tool_button("Pause / Play")
	pause_btn.pressed.connect(func() -> void: _paused = not _paused)
	ctrl.add_child(pause_btn)
	var step_btn := _tool_button("Step")
	step_btn.pressed.connect(func() -> void:
		GameManager.world.step()
		_render())
	ctrl.add_child(step_btn)
	var clear_btn := _tool_button("Clear")
	clear_btn.pressed.connect(func() -> void:
		GameManager.world.clear()
		_render())
	ctrl.add_child(clear_btn)

	var brush_row := HBoxContainer.new()
	brush_row.position = Vector2(844, 100)
	brush_row.add_theme_constant_override("separation", 8)
	_layer.add_child(brush_row)
	var minus := _tool_button("Brush -")
	minus.pressed.connect(func() -> void: _brush = maxi(0, _brush - 1))
	brush_row.add_child(minus)
	var plus := _tool_button("Brush +")
	plus.pressed.connect(func() -> void: _brush = mini(24, _brush + 1))
	brush_row.add_child(plus)

	_status = _mk_label(Vector2(844, 148), 14, Color(0.72, 0.74, 0.78))


func _on_pick(mat: int, btn: Button) -> void:
	_selected = mat
	for c in _palette_box.get_children():
		if c is Button:
			(c as Button).button_pressed = (c == btn)


func _update_status() -> void:
	var w := GameManager.world
	_status.text = "%s   ·   brush r=%d   ·   %s\ntick %d   ·   sand %d  water %d  fire %d" % [
		String(MAT_NAME.get(_selected, "?")), _brush,
		"PAUSED" if _paused else "running", w.tick,
		w.count_of(SandWorld.SAND), w.count_of(SandWorld.WATER),
		w.count_of(SandWorld.FIRE)]


func _tool_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_to_group(&"scalable_text")
	return b


func _header(pos: Vector2, text: String, size: int, color: Color) -> void:
	var l := _mk_label(pos, size, color)
	l.text = text


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l
