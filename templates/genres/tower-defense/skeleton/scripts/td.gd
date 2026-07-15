extends Node2D
## res://scripts/td.gd
## The tower-defense playfield + interaction. Enemies walk a fixed lane; towers
## placed on buildable cells auto-fire at the nearest enemy in range; waves scale
## up; gold comes from kills and lives are lost to leaks. Meta-state (gold/lives/
## wave/towers) lives in the GameManager autoload (persistent + save/load); this
## script runs the real-time movement/firing and the HUD. UI + shapes are built
## in code so the scene stays a bare Node2D + script.

const CELL := 48
const ORIGIN := Vector2(40, 120)
const COLS := 20
const ROWS := 9
const SPAWN_INTERVAL := 0.7
const ENEMY_SPEED := 85.0
const PATH_CLEARANCE := CELL * 0.75  ## cells this close to the lane aren't buildable

var _path: PackedVector2Array
var _enemies: Array = []      ## each: {pos:Vector2, seg:int, hp:int, max_hp:int}
var _pending := 0             ## enemies still to spawn this wave
var _spawn_hp := 6
var _spawn_cd := 0.0
var _wave_active := false
var _selected := "arrow"
var _tower_cd := {}           ## tower key -> seconds until it can fire
var _fire_fx: Array = []      ## transient [from:Vector2, to:Vector2, ttl:float]

var _res_labels := {}
var _palette_buttons := {}
var _wave_button: Button
var _pause_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_path()
	_build_hud()
	GameManager.changed.connect(_refresh_hud)
	_refresh_hud()
	queue_redraw()


func _build_path() -> void:
	var y_top := ORIGIN.y + 2 * CELL + CELL * 0.5
	var y_bot := ORIGIN.y + 6 * CELL + CELL * 0.5
	_path = PackedVector2Array([
		Vector2(ORIGIN.x, y_top),
		Vector2(ORIGIN.x + 6 * CELL, y_top),
		Vector2(ORIGIN.x + 6 * CELL, y_bot),
		Vector2(ORIGIN.x + 13 * CELL, y_bot),
		Vector2(ORIGIN.x + 13 * CELL, y_top),
		Vector2(ORIGIN.x + COLS * CELL, y_top),
	])


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_spawn_step(delta)
	_move_enemies(delta)
	_fire_towers(delta)
	# Wave clears when nothing is left to spawn and no enemies remain.
	if _wave_active and _pending == 0 and _enemies.is_empty():
		_wave_active = false
		if _wave_button:
			_wave_button.disabled = false
	for fx in _fire_fx:
		fx[2] -= delta
	_fire_fx = _fire_fx.filter(func(fx): return fx[2] > 0.0)
	queue_redraw()


# --- waves + enemies -------------------------------------------------------

func _start_wave() -> void:
	if _wave_active or GameManager.is_defeated():
		return
	var w := GameManager.begin_wave()
	_pending = GameManager.enemy_count_for_wave(w)
	_spawn_hp = GameManager.enemy_hp_for_wave(w)
	_spawn_cd = 0.0
	_wave_active = true
	if _wave_button:
		_wave_button.disabled = true


func _spawn_step(delta: float) -> void:
	if _pending <= 0:
		return
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_enemies.append({"pos": _path[0], "seg": 0, "hp": _spawn_hp, "max_hp": _spawn_hp})
		_pending -= 1
		_spawn_cd = SPAWN_INTERVAL


func _move_enemies(delta: float) -> void:
	var keep: Array = []
	for e in _enemies:
		var target: Vector2 = _path[e["seg"] + 1]
		var to_target: Vector2 = target - e["pos"]
		var dist := to_target.length()
		var step := ENEMY_SPEED * delta
		if step >= dist:
			e["pos"] = target
			e["seg"] += 1
			if e["seg"] >= _path.size() - 1:
				GameManager.lose_life()  # leaked
				continue
		else:
			e["pos"] += to_target / dist * step
		keep.append(e)
	_enemies = keep


func _fire_towers(delta: float) -> void:
	for key in GameManager.towers:
		var cd: float = _tower_cd.get(key, 0.0) - delta
		if cd > 0.0:
			_tower_cd[key] = cd
			continue
		var t: Dictionary = GameManager.TOWER_TYPES[GameManager.towers[key]]
		var origin := _cell_center(key)
		var victim: Variant = _nearest_enemy(origin, float(t["range"]))
		if victim == null:
			_tower_cd[key] = 0.0  # ready, waiting for a target
			continue
		victim["hp"] -= int(t["damage"])
		_fire_fx.append([origin, victim["pos"], 0.08])
		if victim["hp"] <= 0:
			_enemies.erase(victim)
			GameManager.award_kill()
		_tower_cd[key] = float(t["fire_rate"])


func _nearest_enemy(from: Vector2, radius: float) -> Variant:
	var best: Variant = null
	var best_d := radius
	for e in _enemies:
		var d: float = from.distance_to(e["pos"])
		if d <= best_d:
			best_d = d
			best = e
	return best


# --- placement -------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
		if _pause_label:
			_pause_label.visible = get_tree().paused
		return
	if get_tree().paused:
		return
	if ev is InputEventMouseButton and ev.pressed:
		var cell := _cell_at(ev.position)
		if cell.x < 0:
			return
		var key := "%d,%d" % [cell.x, cell.y]
		if ev.button_index == MOUSE_BUTTON_LEFT and _is_buildable(cell):
			GameManager.place_tower(key, _selected)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			GameManager.demolish_tower(key)
			_tower_cd.erase(key)


func _cell_at(pos: Vector2) -> Vector2i:
	var local := pos - ORIGIN
	if local.x < 0 or local.y < 0:
		return Vector2i(-1, -1)
	var c := int(local.x / CELL)
	var r := int(local.y / CELL)
	if c >= COLS or r >= ROWS:
		return Vector2i(-1, -1)
	return Vector2i(c, r)


func _cell_center(key: String) -> Vector2:
	var parts := key.split(",")
	return ORIGIN + Vector2(int(parts[0]) * CELL + CELL * 0.5, int(parts[1]) * CELL + CELL * 0.5)


## A cell is buildable when its centre is clear of the lane corridor.
func _is_buildable(cell: Vector2i) -> bool:
	var center := ORIGIN + Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)
	return _dist_to_path(center) > PATH_CLEARANCE


func _dist_to_path(p: Vector2) -> float:
	var best := INF
	for i in range(_path.size() - 1):
		var cp := Geometry2D.get_closest_point_to_segment(p, _path[i], _path[i + 1])
		best = minf(best, p.distance_to(cp))
	return best


# --- drawing ---------------------------------------------------------------

func _draw() -> void:
	# buildable cells (faint)
	for r in range(ROWS):
		for c in range(COLS):
			if _is_buildable(Vector2i(c, r)):
				var p := ORIGIN + Vector2(c * CELL, r * CELL)
				draw_rect(Rect2(p, Vector2(CELL - 2, CELL - 2)), Color(0.14, 0.16, 0.13))
	# the lane
	draw_polyline(_path, Color(0.30, 0.27, 0.22), CELL * 0.7)
	draw_polyline(_path, Color(0.38, 0.34, 0.27), 4.0)
	# towers + their range
	for key in GameManager.towers:
		var t: Dictionary = GameManager.TOWER_TYPES[GameManager.towers[key]]
		var ctr := _cell_center(key)
		draw_circle(ctr, float(t["range"]), Color(t["color"].r, t["color"].g, t["color"].b, 0.06))
		draw_rect(Rect2(ctr - Vector2(CELL * 0.35, CELL * 0.35), Vector2(CELL * 0.7, CELL * 0.7)), t["color"])
	# enemies + hp bars
	for e in _enemies:
		draw_circle(e["pos"], 10.0, Color(0.80, 0.30, 0.28))
		var frac: float = float(e["hp"]) / float(e["max_hp"])
		draw_rect(Rect2(e["pos"] + Vector2(-12, -18), Vector2(24, 3)), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(e["pos"] + Vector2(-12, -18), Vector2(24 * frac, 3)), Color(0.4, 0.85, 0.4))
	# fire flashes
	for fx in _fire_fx:
		draw_line(fx[0], fx[1], Color(1, 0.9, 0.5, 0.8), 2.0)


# --- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var res := HBoxContainer.new()
	res.position = Vector2(40, 22)
	res.add_theme_constant_override("separation", 28)
	layer.add_child(res)
	for res_name in ["gold", "lives", "wave"]:
		var lbl := Label.new()
		lbl.add_to_group(&"scalable_text")
		lbl.add_theme_font_size_override("font_size", 18)
		res.add_child(lbl)
		_res_labels[res_name] = lbl

	var bar := HBoxContainer.new()
	bar.position = Vector2(40, 56)
	bar.add_theme_constant_override("separation", 8)
	layer.add_child(bar)
	for type_id in GameManager.TOWER_TYPES:
		var t: Dictionary = GameManager.TOWER_TYPES[type_id]
		var b := Button.new()
		b.text = "%s — %d g" % [t["name"], int(t["cost"])]
		b.add_to_group(&"scalable_text")
		b.pressed.connect(_select.bind(type_id))
		bar.add_child(b)
		_palette_buttons[type_id] = b
	_wave_button = Button.new()
	_wave_button.text = "Start wave"
	_wave_button.add_to_group(&"scalable_text")
	_wave_button.pressed.connect(_start_wave)
	bar.add_child(_wave_button)

	var hint := Label.new()
	hint.position = Vector2(40, 92)
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.7, 0.72, 0.68)
	hint.text = "Left-click a buildable cell to place · right-click to sell · Start wave to send enemies · Esc pauses"
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
	if _res_labels.has("lives"):
		_res_labels["lives"].text = "Lives  %d" % GameManager.lives
	if _res_labels.has("wave"):
		_res_labels["wave"].text = "Wave  %d" % GameManager.wave
	for type_id in _palette_buttons:
		var b: Button = _palette_buttons[type_id]
		b.disabled = not GameManager.can_afford(type_id) and type_id != _selected
		b.modulate = Color(1, 1, 1) if type_id == _selected else Color(0.72, 0.72, 0.72)
