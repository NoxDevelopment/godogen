extends Node2D
## res://scripts/match3.gd
## The match-3 BOARD view. Draws the grid of gems from GameManager (the engine),
## lets you click a gem then an adjacent gem to swap, and rebuilds after each
## resolved swap. All rules — matching, cascades, gravity, refill, reshuffle —
## live in GameManager; this only renders state and forwards the swap. UI is
## built in code so the scene stays a bare Node2D + script.

const CELL := 60
const PAD := 6
const GEM_COLORS := [
	Color(0.90, 0.35, 0.38),  # 0 red
	Color(0.35, 0.62, 0.92),  # 1 blue
	Color(0.55, 0.82, 0.45),  # 2 green
	Color(0.95, 0.80, 0.35),  # 3 yellow
	Color(0.70, 0.50, 0.90),  # 4 purple
	Color(0.40, 0.82, 0.80),  # 5 teal
]
const SEED := 20260714  ## a stable opening board; New board rolls fresh.

var _sel_x := -1
var _sel_y := -1

var _layer: CanvasLayer
var _grid: GridContainer
var _buttons: Array = []  ## flat WIDTH*HEIGHT of Buttons
var _score_label: Label
var _banner: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.new_board(SEED)
	_build_ui()
	GameManager.board_changed.connect(_rebuild)
	_rebuild()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		GameManager.new_board(0)


# --- static layout ---------------------------------------------------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_score_label = _mk_label(Vector2(28, 18), 22)
	_banner = _mk_label(Vector2(28, 50), 16)
	_banner.modulate = Color(0.95, 0.86, 0.45)

	_grid = GridContainer.new()
	_grid.columns = GameManager.WIDTH
	_grid.position = Vector2(28, 90)
	_grid.add_theme_constant_override("h_separation", PAD)
	_grid.add_theme_constant_override("v_separation", PAD)
	_layer.add_child(_grid)

	_buttons = []
	for i in GameManager.WIDTH * GameManager.HEIGHT:
		var b := Button.new()
		b.custom_minimum_size = Vector2(CELL, CELL)
		b.add_to_group(&"scalable_text")
		var x := i % GameManager.WIDTH
		var y := i / GameManager.WIDTH
		b.pressed.connect(_on_cell.bind(x, y))
		_grid.add_child(b)
		_buttons.append(b)

	var newbtn := Button.new()
	newbtn.position = Vector2(28, 90 + GameManager.HEIGHT * (CELL + PAD) + 12)
	newbtn.text = "New board"
	newbtn.add_to_group(&"scalable_text")
	newbtn.pressed.connect(func() -> void: GameManager.new_board(0))
	_layer.add_child(newbtn)


func _mk_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


# --- rebuild ---------------------------------------------------------------

func _rebuild() -> void:
	_score_label.text = "Score %d    Moves %d" % [GameManager.score, GameManager.moves]
	for i in _buttons.size():
		var x := i % GameManager.WIDTH
		var y := i / GameManager.WIDTH
		var g := GameManager.gem_at(x, y)
		var b: Button = _buttons[i]
		var col: Color = GEM_COLORS[g] if g >= 0 and g < GEM_COLORS.size() else Color(0.2, 0.2, 0.2)
		if x == _sel_x and y == _sel_y:
			b.modulate = Color(1, 1, 1)
			col = col.lightened(0.35)
		else:
			b.modulate = Color(1, 1, 1)
		b.add_theme_color_override("font_color", Color(0, 0, 0, 0))  # hide any text
		_tint(b, col)


func _tint(b: Button, col: Color) -> void:
	for s in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(s, sb)


# --- interaction -----------------------------------------------------------

func _on_cell(x: int, y: int) -> void:
	if _sel_x < 0:
		_sel_x = x
		_sel_y = y
		_rebuild()
		return
	if _sel_x == x and _sel_y == y:
		_sel_x = -1  # deselect
		_sel_y = -1
		_rebuild()
		return
	if abs(_sel_x - x) + abs(_sel_y - y) == 1:
		var res := GameManager.try_swap(_sel_x, _sel_y, x, y)
		_sel_x = -1
		_sel_y = -1
		if res["legal"]:
			var chains := int(res["chains"])
			_banner.text = ("Chain x%d!  +%d" % [chains, int(res["gained"])]) if chains > 1 \
				else "+%d" % int(res["gained"])
		else:
			_banner.text = "No match — try another swap."
		# board_changed already fired the rebuild on a legal swap; force one otherwise.
		if not res["legal"]:
			_rebuild()
	else:
		# not adjacent → reselect the new cell
		_sel_x = x
		_sel_y = y
		_rebuild()
