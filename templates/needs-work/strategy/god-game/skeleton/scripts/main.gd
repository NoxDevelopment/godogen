extends Node2D
## res://scripts/main.gd
## THE DEITY MAP (built entirely in code). Renders GameManager.world top-down —
## terrain height → colour (water below sea level, land shaded by elevation),
## forests + food sources, and villager/hut markers per tribe — and advances the
## sim on a fixed tick. A POWER palette selects a divine power; click the map to
## cast it on a cell (queued for the next tick, spending belief). A HUD shows the
## belief meter, both tribes' populations, and a running log. All rules live in
## GodWorld; this only paints inputs in and reads state out, so the sim is fully
## playable AND headless-testable.

const CELL := 10                       ## pixels per grid cell
const ORIGIN := Vector2(24, 96)        ## grid top-left; HUD sits above it
const TICK_SECONDS := 0.25             ## real-time seconds between sim ticks

## Tribe display colours (index == tribe id).
const TRIBE_COLOR: PackedColorArray = [
	Color(0.30, 0.80, 1.00),   # YOU   — cyan
	Color(1.00, 0.40, 0.34),   # RIVAL — red
]

var _selected_power := GodWorld.P_RAISE_LAND
var _power_buttons: Array[Button] = []
var _belief_label: Label
var _pop_label: Label
var _log_label: Label
var _hint_label: Label
var _paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()
	GameManager.world_reset.connect(_on_world_reset)
	_refresh_hud()
	queue_redraw()


func _on_world_reset() -> void:
	_refresh_hud()
	queue_redraw()


func _on_tick() -> void:
	if _paused or GameManager.world.winner != -1:
		return
	GameManager.world.tick_world()
	_refresh_hud()
	queue_redraw()


# =====================================================================
#  Rendering — terrain + resources + markers
# =====================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.09, 0.09, 0.12), true)
	var w: GodWorld = GameManager.world
	if w == null:
		return
	for y in w.height:
		for x in w.width:
			var p := ORIGIN + Vector2(x * CELL, y * CELL)
			draw_rect(Rect2(p, Vector2(CELL, CELL)), _cell_color(w, x, y))
	# Huts (filled squares) then villagers (dots) on top.
	for i in w.hut_count():
		var hut := w.hut_info(i)
		var hp := ORIGIN + Vector2(int(hut["x"]) * CELL, int(hut["y"]) * CELL)
		draw_rect(Rect2(hp - Vector2(1, 1), Vector2(CELL + 2, CELL + 2)),
			TRIBE_COLOR[int(hut["tribe"])])
		draw_rect(Rect2(hp + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)),
			Color(0.10, 0.10, 0.12))
	for i in w.villager_count():
		var v := w.villager_info(i)
		var vp := ORIGIN + Vector2(int(v["x"]) * CELL + CELL * 0.5, int(v["y"]) * CELL + CELL * 0.5)
		var col: Color = TRIBE_COLOR[int(v["tribe"])]
		if int(v["boost"]) > 0:
			col = col.lerp(Color.WHITE, 0.5)   # inspired followers glow
		draw_circle(vp, CELL * 0.34, col)


## Terrain colour: blue gradient under the sea, green→brown by elevation on land,
## with forests (dark green) and food (gold) drawn as their own tint.
func _cell_color(w: GodWorld, x: int, y: int) -> Color:
	var h := w.height_at(x, y)
	if h < GodWorld.SEA_LEVEL:
		var t := float(h) / float(GodWorld.SEA_LEVEL)
		return Color(0.05, 0.12 + 0.18 * t, 0.35 + 0.35 * t)
	var res := w.res_at(x, y)
	if res == GodWorld.RES_FOREST:
		return Color(0.10, 0.42, 0.14)
	if res == GodWorld.RES_FOOD:
		return Color(0.90, 0.80, 0.24)
	var e := float(h - GodWorld.SEA_LEVEL) / float(GodWorld.LAND_MAX - GodWorld.SEA_LEVEL)
	return Color(0.30 + 0.32 * e, 0.52 + 0.20 * e, 0.24 + 0.10 * e)


# =====================================================================
#  Input → cast the selected power on the clicked cell
# =====================================================================

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		_paused = not _paused
		_refresh_hud()
		return
	if e.is_action_pressed(&"restart"):
		GameManager.new_world(0)
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(e.position)
		if cell.x >= 0:
			_cast_at(cell.x, cell.y)


func _cell_at(pos: Vector2) -> Vector2i:
	var local := pos - ORIGIN
	if local.x < 0 or local.y < 0:
		return Vector2i(-1, -1)
	var c := int(local.x / CELL)
	var r := int(local.y / CELL)
	if c >= GameManager.world.width or r >= GameManager.world.height:
		return Vector2i(-1, -1)
	return Vector2i(c, r)


func _cast_at(x: int, y: int) -> void:
	var ok := GameManager.world.queue_power(_selected_power, GodWorld.YOU, x, y)
	if ok:
		_log("Queued %s at (%d,%d)" % [GodWorld.POWER_NAME[_selected_power], x, y])
	else:
		_log("Illegal: %s at (%d,%d)" % [GodWorld.POWER_NAME[_selected_power], x, y])
	_refresh_hud()
	queue_redraw()


## Public helper the UI-build probe calls: cast a power immediately and repaint,
## so a headless test can assert the world changed and the view updated.
func debug_cast(power: int, x: int, y: int) -> bool:
	var ok := GameManager.world.cast_power(power, GodWorld.YOU, x, y)
	_refresh_hud()
	queue_redraw()
	return ok


# =====================================================================
#  HUD (built in code)
# =====================================================================

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Backdrop painted in _draw() (root layer 0), behind the terrain. A full-rect
	# ColorRect in this front CanvasLayer would occlude the whole map.

	var title := _mk_label(layer, Vector2(24, 16), 22, Color(0.92, 0.86, 0.60))
	title.text = "GOD GAME — shape the land, grow your tribe"

	_belief_label = _mk_label(layer, Vector2(24, 48), 17, Color(0.80, 0.90, 1.00))
	_pop_label = _mk_label(layer, Vector2(320, 48), 17, Color(0.86, 0.86, 0.82))

	# Power palette.
	var palette := HBoxContainer.new()
	palette.position = Vector2(24, 720)
	palette.add_theme_constant_override("separation", 8)
	palette.add_to_group(&"palette")
	layer.add_child(palette)
	_power_buttons.clear()
	for power in GodWorld.POWER_COUNT:
		var b := Button.new()
		b.text = "%s (%d)" % [GodWorld.POWER_NAME[power], GodWorld.POWER_COST[power]]
		b.toggle_mode = true
		b.button_pressed = (power == _selected_power)
		b.add_to_group(&"scalable_text")
		b.pressed.connect(_on_pick_power.bind(power))
		palette.add_child(b)
		_power_buttons.append(b)

	_hint_label = _mk_label(layer, Vector2(24, 700), 12, Color(0.68, 0.70, 0.74))
	_hint_label.text = "Pick a power, click the map to cast it · Esc pause · R restart"

	_log_label = _mk_label(layer, Vector2(720, 96), 13, Color(0.74, 0.78, 0.72))
	_log_label.text = "The world awakens…"


func _on_pick_power(power: int) -> void:
	_selected_power = power
	for i in _power_buttons.size():
		_power_buttons[i].button_pressed = (i == power)
	_refresh_hud()


func _refresh_hud() -> void:
	var w: GodWorld = GameManager.world
	if w == null:
		return
	_belief_label.text = "Belief %d   ·   Wood %d   ·   Power: %s" % [
		w.belief_of(GodWorld.YOU), w.wood_of(GodWorld.YOU),
		GodWorld.POWER_NAME[_selected_power]]
	var status := ""
	if w.winner == GodWorld.YOU:
		status = "   ·   YOU WIN"
	elif w.winner == GodWorld.RIVAL:
		status = "   ·   YOU LOSE"
	elif _paused:
		status = "   ·   PAUSED"
	_pop_label.text = "Tick %d   ·   Your tribe %d   ·   Rival %d%s" % [
		w.tick, w.population(GodWorld.YOU), w.population(GodWorld.RIVAL), status]


func _log(text: String) -> void:
	if _log_label:
		_log_label.text = text


func _mk_label(parent: Node, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	parent.add_child(l)
	return l
