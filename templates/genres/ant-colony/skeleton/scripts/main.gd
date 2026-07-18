extends Node2D
## res://scripts/main.gd
## THE COLONY MAP (built entirely in code). Renders GameManager.world top-down —
## the surface band, dug tunnels + chambers, food sources, both nests, every ant
## coloured by colony + caste, the spider, and an optional FOOD-pheromone heat
## overlay — and advances the sim on a fixed tick. A ZONE palette selects Dig /
## Forage / Attack; click the map to designate that zone for YOUR colony (biasing
## its behaviour). A HUD shows your population by caste, food, the rival's pop, and
## the tick. All rules live in AntWorld; this only paints inputs in and reads state
## out, so the sim is fully playable AND headless-testable.

const CELL := 16                       ## pixels per grid cell
const ORIGIN := Vector2(24, 132)       ## grid top-left; HUD sits above it
const TICK_SECONDS := 0.12             ## real-time seconds between sim ticks

## Colony base colours (index == colony id).
const COLONY_COLOR: PackedColorArray = [
	Color(0.35, 0.75, 1.00),   # YOU   — cyan
	Color(1.00, 0.45, 0.38),   # RIVAL — red
]

# Real CC0 art (OpenGameArt): seamless ground tiles + top-down insect sprites.
var _tex_grass: Texture2D
var _tex_dirt: Texture2D
var _tex_tunnel: Texture2D
var _tex_food: Texture2D
var _tex_worker: Texture2D
var _tex_queen: Texture2D
var _tex_enemy: Texture2D
var _tex_enemy_queen: Texture2D

var _selected_zone := AntWorld.ZONE_FORAGE
var _zone_buttons: Array[Button] = []
var _pop_label: Label
var _econ_label: Label
var _log_label: Label
var _hint_label: Label
var _overlay_button: Button
var _paused := false
var _show_pheromone := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_art()
	_build_hud()
	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()
	GameManager.world_reset.connect(_on_world_reset)
	_refresh_hud()
	queue_redraw()


func _load_art() -> void:
	_tex_grass = load("res://assets/art/tile_grass.png")
	_tex_dirt = load("res://assets/art/tile_dirt.png")
	_tex_tunnel = load("res://assets/art/tile_tunnel.png")
	_tex_food = load("res://assets/art/food.png")
	_tex_worker = load("res://assets/art/ant_worker.png")
	_tex_queen = load("res://assets/art/ant_queen.png")
	_tex_enemy = load("res://assets/art/ant_enemy.png")
	_tex_enemy_queen = load("res://assets/art/ant_enemy_queen.png")


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
#  Rendering — terrain + pheromone overlay + actors
# =====================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.07, 0.07, 0.09), true)
	var w: AntWorld = GameManager.world
	if w == null:
		return
	for y in w.height:
		for x in w.width:
			var p := ORIGIN + Vector2(x * CELL, y * CELL)
			_draw_terrain(w, x, y, p)
			if _show_pheromone:
				var f := w.food_ph(AntWorld.YOU, x, y)
				if f > 0.5:
					var a := clampf(f / 40.0, 0.0, 0.7)
					draw_rect(Rect2(p, Vector2(CELL, CELL)), Color(0.2, 1.0, 0.4, a))
	# Designation zones (outlined discs on the grid).
	_draw_zone(w.forage_zone(), Color(0.4, 1.0, 0.5))
	_draw_zone(w.dig_zone(), Color(0.9, 0.7, 0.3))
	_draw_zone(w.attack_zone(), Color(1.0, 0.4, 0.4))
	# The spider(s).
	for i in w.predator_count():
		var pr := w.predator_info(i)
		if int(pr["alive"]) == 0:
			continue
		var pp := ORIGIN + Vector2(int(pr["x"]) * CELL + CELL * 0.5, int(pr["y"]) * CELL + CELL * 0.5)
		draw_circle(pp, CELL * 0.5, Color(0.15, 0.12, 0.16))
		draw_circle(pp, CELL * 0.34, Color(0.7, 0.15, 0.55))
	# Every ant (colony colour, brighter for soldiers, big for the queen).
	for i in w.ant_count():
		var a := w.ant_info(i)
		var ap := ORIGIN + Vector2(int(a["x"]) * CELL + CELL * 0.5, int(a["y"]) * CELL + CELL * 0.5)
		var colony := int(a["colony"])
		var caste := int(a["caste"])
		var mine := colony == AntWorld.YOU
		var tex: Texture2D
		var sz := CELL * 1.15
		if caste == AntWorld.QUEEN:
			tex = _tex_queen if mine else _tex_enemy_queen
			sz = CELL * 2.0
		else:
			tex = _tex_worker if mine else _tex_enemy
			if caste == AntWorld.SOLDIER:
				sz = CELL * 1.5
		if int(a["carry"]) == 1:
			draw_circle(ap, sz * 0.5 + 2.0, Color(0.95, 0.85, 0.3, 0.9))  # food halo
		if tex != null:
			var w2 := sz
			var h2 := sz * float(tex.get_height()) / float(maxi(1, tex.get_width()))
			draw_texture_rect(tex, Rect2(ap - Vector2(w2, h2) * 0.5, Vector2(w2, h2)), false)
		else:
			draw_circle(ap, CELL * 0.3, COLONY_COLOR[colony])


## Paint one terrain cell with a real seamless texture (region-sampled from the
## CC0 tile so adjacent cells form a continuous ground), tinted per terrain type.
func _draw_terrain(w: AntWorld, x: int, y: int, p: Vector2) -> void:
	var cell := Rect2(p, Vector2(CELL, CELL))
	var t := w.terrain_at(x, y)
	var tex: Texture2D = _tex_dirt
	var tint := Color.WHITE
	match t:
		AntWorld.OPEN:
			if y < AntWorld.SURFACE_ROWS:
				tex = _tex_grass
			else:
				tex = _tex_dirt
				tint = Color(0.72, 0.72, 0.78)   # dug-out underground air
		AntWorld.SOIL:
			tex = _tex_dirt
		AntWorld.TUNNEL:
			tex = _tex_tunnel
		AntWorld.CHAMBER:
			tex = _tex_tunnel
			tint = Color(1.08, 1.06, 0.98)
		AntWorld.FOOD:
			tex = _tex_grass
		AntWorld.ROCK:
			tex = _tex_dirt
			tint = Color(0.45, 0.45, 0.50)
		AntWorld.NEST:
			tex = _tex_tunnel
			tint = Color(0.70, 0.85, 1.10)
		AntWorld.RNEST:
			tex = _tex_tunnel
			tint = Color(1.10, 0.70, 0.65)
	if tex == null:
		draw_rect(cell, _cell_color(w, x, y))
		return
	var tw := tex.get_width()
	var th := tex.get_height()
	var src := Rect2((x * CELL) % tw, (y * CELL) % th, CELL, CELL)
	draw_texture_rect_region(tex, cell, src, tint)
	if t == AntWorld.FOOD and _tex_food != null:
		draw_texture_rect(_tex_food, cell, false)


func _cell_color(w: AntWorld, x: int, y: int) -> Color:
	match w.terrain_at(x, y):
		AntWorld.OPEN:
			return Color(0.16, 0.20, 0.30) if y < AntWorld.SURFACE_ROWS else Color(0.30, 0.22, 0.15)
		AntWorld.SOIL:
			return Color(0.24, 0.17, 0.11)
		AntWorld.ROCK:
			return Color(0.14, 0.13, 0.14)
		AntWorld.TUNNEL:
			return Color(0.42, 0.32, 0.22)
		AntWorld.CHAMBER:
			return Color(0.50, 0.40, 0.26)
		AntWorld.FOOD:
			return Color(0.55, 0.85, 0.30)
		AntWorld.NEST:
			return Color(0.30, 0.55, 0.85)
		AntWorld.RNEST:
			return Color(0.80, 0.35, 0.30)
		_:
			return Color.BLACK


func _draw_zone(z: Vector2i, color: Color) -> void:
	if z.x < 0:
		return
	var p := ORIGIN + Vector2(z.x * CELL, z.y * CELL)
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(CELL + 4, CELL + 4)), color, false, 2.0)


# =====================================================================
#  Input → designate the selected zone on the clicked cell
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
			_designate_at(cell.x, cell.y)


func _cell_at(pos: Vector2) -> Vector2i:
	var local := pos - ORIGIN
	if local.x < 0 or local.y < 0:
		return Vector2i(-1, -1)
	var c := int(local.x / CELL)
	var r := int(local.y / CELL)
	if c >= GameManager.world.width or r >= GameManager.world.height:
		return Vector2i(-1, -1)
	return Vector2i(c, r)


func _designate_at(x: int, y: int) -> void:
	var ok := GameManager.world.designate(_selected_zone, x, y)
	if ok:
		_log("%s zone → (%d,%d)" % [AntWorld.ZONE_NAME[_selected_zone], x, y])
	else:
		_log("Illegal designation at (%d,%d)" % [x, y])
	_refresh_hud()
	queue_redraw()


## Public helper the UI-build probe calls: designate immediately and repaint, so a
## headless test can assert the world changed and the view updated.
func debug_designate(kind: int, x: int, y: int) -> bool:
	var ok := GameManager.world.designate(kind, x, y)
	_refresh_hud()
	queue_redraw()
	return ok


# =====================================================================
#  HUD (built in code)
# =====================================================================

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Backdrop is painted in _draw() (root canvas layer 0), behind the colony map.
	# A full-rect ColorRect in this front CanvasLayer would occlude the entire
	# map — the bug that left only the HUD visible over a black void.

	var title := _mk_label(layer, Vector2(24, 14), 22, Color(0.90, 0.82, 0.55))
	title.text = "ANT COLONY — forage, tunnel, raise castes, war the rival"

	_pop_label = _mk_label(layer, Vector2(24, 46), 16, Color(0.80, 0.90, 1.00))
	_econ_label = _mk_label(layer, Vector2(24, 70), 16, Color(0.86, 0.86, 0.82))

	# Zone palette.
	var palette := HBoxContainer.new()
	palette.position = Vector2(24, 96)
	palette.add_theme_constant_override("separation", 8)
	palette.add_to_group(&"palette")
	layer.add_child(palette)
	_zone_buttons.clear()
	for zone in AntWorld.ZONE_COUNT:
		var b := Button.new()
		b.text = AntWorld.ZONE_NAME[zone]
		b.toggle_mode = true
		b.button_pressed = (zone == _selected_zone)
		b.add_to_group(&"scalable_text")
		b.pressed.connect(_on_pick_zone.bind(zone))
		palette.add_child(b)
		_zone_buttons.append(b)

	_overlay_button = Button.new()
	_overlay_button.text = "Pheromone overlay: off"
	_overlay_button.position = Vector2(330, 96)
	_overlay_button.add_to_group(&"scalable_text")
	_overlay_button.pressed.connect(_on_toggle_overlay)
	layer.add_child(_overlay_button)

	_hint_label = _mk_label(layer, Vector2(600, 100), 12, Color(0.68, 0.70, 0.74))
	_hint_label.text = "Pick a zone, click the map to designate · Esc pause · R restart"

	_log_label = _mk_label(layer, Vector2(600, 46), 13, Color(0.74, 0.78, 0.72))
	_log_label.text = "The colony stirs…"


func _on_pick_zone(zone: int) -> void:
	_selected_zone = zone
	for i in _zone_buttons.size():
		_zone_buttons[i].button_pressed = (i == zone)
	_refresh_hud()


func _on_toggle_overlay() -> void:
	_show_pheromone = not _show_pheromone
	_overlay_button.text = "Pheromone overlay: %s" % ("on" if _show_pheromone else "off")
	queue_redraw()


func _refresh_hud() -> void:
	var w: AntWorld = GameManager.world
	if w == null:
		return
	_pop_label.text = "You  Q%d  W%d  S%d  (pop %d)     Rival pop %d" % [
		w.caste_pop(AntWorld.YOU, AntWorld.QUEEN),
		w.caste_pop(AntWorld.YOU, AntWorld.WORKER),
		w.caste_pop(AntWorld.YOU, AntWorld.SOLDIER),
		w.population(AntWorld.YOU), w.population(AntWorld.RIVAL)]
	var status := ""
	if w.winner == AntWorld.YOU:
		status = "   ·   YOU WIN"
	elif w.winner == AntWorld.RIVAL:
		status = "   ·   YOU LOSE"
	elif _paused:
		status = "   ·   PAUSED"
	_econ_label.text = "Food %d   ·   Foraged %d   ·   Tunnels %d   ·   Tick %d%s" % [
		w.food_stock_of(AntWorld.YOU), w.harvested_of(AntWorld.YOU),
		w.dug_of(AntWorld.YOU), w.tick, status]


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
