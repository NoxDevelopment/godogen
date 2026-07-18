extends Control
## res://scripts/arena.gd
## THE PLAY SURFACE (built entirely in code). Draws the circular stadium + the two
## spinning tops (markers ringed by a stamina arc) and replays the last battle's
## deterministic trajectory via _draw(), and lays a HUD over it: the PART-BUILDER
## (ring / disk / tip / spin pickers + the derived stats), a LAUNCH control (a
## power meter + an aim slider + Launch), the match score + the rung roster, and a
## log. A human plays; the "Auto Step" button steps the deterministic auto-play to
## demo a whole tournament. All rules live in GameManager's TopEngine; this only
## reads state and forwards the chosen action.

const ARENA_CENTER: Vector2 = Vector2(330.0, 360.0)
const ARENA_VIEW_R: float = 240.0

const SPIN_COLOR: Dictionary = {
	1: Color(0.45, 0.78, 0.98),   # right-spin: blue
	-1: Color(0.98, 0.62, 0.42),  # left-spin: orange
}

var _layer: CanvasLayer
var _title: Label
var _score: Label
var _stats: Label
var _result: Label
var _roster: Label
var _log_box: VBoxContainer

var _ring_opt: OptionButton
var _disk_opt: OptionButton
var _tip_opt: OptionButton
var _spin_opt: OptionButton
var _power_slider: HSlider
var _aim_slider: HSlider
var _launch_btn: Button

var _anim_trace: Array = []
var _anim_i: int = 0
var _final_tops: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine.owned_parts.is_empty() and not GameManager.engine.tournament_over:
		GameManager.new_run(GameManager.DEFAULT_SEED)
	_build_ui()
	GameManager.changed.connect(_on_changed)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		GameManager.new_run(GameManager.DEFAULT_SEED)


func _process(_delta: float) -> void:
	if _anim_i < _anim_trace.size():
		_anim_i = mini(_anim_trace.size(), _anim_i + 2)
		queue_redraw()


func _on_changed() -> void:
	var e: TopEngine = GameManager.engine
	if not e.last_trace.is_empty() and e.last_trace != _anim_trace:
		_anim_trace = e.last_trace
		_final_tops = e.last_tops
		_anim_i = 0
	_refresh()
	queue_redraw()


# =====================================================================
#  UI construction
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	# Backdrop is painted in _draw() (root canvas layer 0) so the arena stays
	# visible. A full-rect ColorRect in this front CanvasLayer would occlude it
	# (the bug that made only the builder UI show).

	_title = _mk_label(Vector2(24, 16), 22, Color(0.86, 0.92, 0.98))
	_score = _mk_label(Vector2(24, 48), 16, Color(0.90, 0.86, 0.55))

	# --- right-hand panel: builder + launch + roster ---
	var px: float = 700.0
	_mk_header(Vector2(px, 20), "BUILD YOUR TOP")
	_ring_opt = _mk_option(Vector2(px, 50), "ring")
	_disk_opt = _mk_option(Vector2(px, 88), "disk")
	_tip_opt = _mk_option(Vector2(px, 126), "tip")
	_spin_opt = _mk_option(Vector2(px, 164), "spin")
	_stats = _mk_label(Vector2(px, 204), 13, Color(0.72, 0.82, 0.74))
	_stats.custom_minimum_size = Vector2(540, 60)

	_mk_header(Vector2(px, 272), "LAUNCH")
	_mk_label_text(Vector2(px, 300), 12, Color(0.7, 0.7, 0.72), "Power")
	_power_slider = _mk_slider(Vector2(px + 60, 302), 0.0, 1.0, 0.9, 0.05)
	_mk_label_text(Vector2(px, 332), 12, Color(0.7, 0.7, 0.72), "Aim")
	_aim_slider = _mk_slider(Vector2(px + 60, 334), -1.2, 1.2, 0.0, 0.05)
	_launch_btn = _mk_button(Vector2(px, 366), "LAUNCH  ▶")
	_launch_btn.pressed.connect(_on_launch)

	var auto_btn := _mk_button(Vector2(px + 150, 366), "Auto Step")
	auto_btn.pressed.connect(func() -> void: GameManager.auto_step())
	var reset_btn := _mk_button(Vector2(px + 270, 366), "Restart")
	reset_btn.pressed.connect(func() -> void: GameManager.new_run(GameManager.DEFAULT_SEED))

	_result = _mk_label(Vector2(px, 408), 15, Color(0.96, 0.78, 0.40))
	_result.custom_minimum_size = Vector2(540, 24)

	_mk_header(Vector2(px, 444), "TOURNAMENT LADDER")
	_roster = _mk_label(Vector2(px, 472), 13, Color(0.78, 0.80, 0.88))
	_roster.custom_minimum_size = Vector2(540, 120)

	_mk_header(Vector2(px, 600), "LOG")
	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(px, 626)
	_log_box.add_theme_constant_override("separation", 1)
	_layer.add_child(_log_box)

	for opt in [_ring_opt, _disk_opt, _tip_opt, _spin_opt]:
		opt.item_selected.connect(func(_i: int) -> void: _apply_build())


func _mk_header(pos: Vector2, text: String) -> void:
	_mk_label_text(pos, 15, Color(0.62, 0.70, 0.82), text)


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _mk_label_text(pos: Vector2, size: int, color: Color, text: String) -> Label:
	var l := _mk_label(pos, size, color)
	l.text = text
	return l


func _mk_button(pos: Vector2, text: String) -> Button:
	var b := Button.new()
	b.position = pos
	b.text = text
	b.add_to_group(&"scalable_text")
	_layer.add_child(b)
	return b


func _mk_option(pos: Vector2, _kind: String) -> OptionButton:
	var o := OptionButton.new()
	o.position = pos
	o.custom_minimum_size = Vector2(280, 0)
	o.add_to_group(&"scalable_text")
	_layer.add_child(o)
	return o


func _mk_slider(pos: Vector2, mn: float, mx: float, val: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.position = pos
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(200, 16)
	_layer.add_child(s)
	return s


# =====================================================================
#  Builder wiring
# =====================================================================

func _populate_options() -> void:
	var e: TopEngine = GameManager.engine
	_fill_option(_ring_opt, e.owned_of_kind("ring"))
	_fill_option(_disk_opt, e.owned_of_kind("disk"))
	_fill_option(_tip_opt, e.owned_of_kind("tip"))
	if _spin_opt.item_count == 0:
		_spin_opt.add_item("Spin ▶ Right", 1)
		_spin_opt.add_item("Spin ◀ Left", 0)


func _fill_option(opt: OptionButton, ids: Array) -> void:
	var prev: String = ""
	if opt.item_count > 0 and opt.selected >= 0:
		prev = opt.get_item_metadata(opt.selected)
	opt.clear()
	var e: TopEngine = GameManager.engine
	for pid in ids:
		var idx := opt.item_count
		opt.add_item(e.part_name(String(pid)))
		opt.set_item_metadata(idx, String(pid))
		if String(pid) == prev:
			opt.select(idx)


func _apply_build() -> void:
	if _ring_opt.selected < 0 or _disk_opt.selected < 0 or _tip_opt.selected < 0:
		return
	var ring: String = _ring_opt.get_item_metadata(_ring_opt.selected)
	var disk: String = _disk_opt.get_item_metadata(_disk_opt.selected)
	var tip: String = _tip_opt.get_item_metadata(_tip_opt.selected)
	var spin: int = 1 if _spin_opt.get_selected_id() == 1 else -1
	GameManager.select_build(ring, disk, tip, spin)


# =====================================================================
#  Refresh
# =====================================================================

func _refresh() -> void:
	var e: TopEngine = GameManager.engine
	_populate_options()
	_title.text = "SPINNING TOP BATTLER — %s" % (
		"TOURNAMENT WON" if e.tournament_won else ("ELIMINATED" if e.tournament_over else "Rung %d/%d: %s" % [e.rung + 1, e.LADDER.size(), e.rung_name()]))
	_score.text = "Match  YOU %d — %d AI   (first to %d)   ·   round %d" % [
		e.player_points, e.ai_points, e.POINTS_TO_WIN, e.round_no]
	var b: Dictionary = e.player_build
	if not b.is_empty():
		_stats.text = "Your top: ATK %d   DEF %d   STA %d   WT %d   agg %.2f   friction %.2f   drain %.2f   grip %.2f" % [
			int(b["attack"]), int(b["defense"]), int(b["stamina_max"]), int(b["weight"]),
			float(b["aggression"]), float(b["friction"]), float(b["drain_mult"]), float(b["grip"])]
	var ai: Dictionary = e.ai_rung_build()
	_roster.text = "Now: %s — ATK %d DEF %d STA %d WT %d\nOwned parts: %d   (win a rung to unlock more)" % [
		String(ai["name"]), int(ai["attack"]), int(ai["defense"]), int(ai["stamina_max"]), int(ai["weight"]),
		e.owned_parts.size()]
	if not e.last_result.is_empty():
		var r: Dictionary = e.last_result
		_result.text = "Last battle: %s wins by %s in %d steps (%d hits)." % [
			"YOU" if String(r["winner"]) == "player" else "AI",
			e._reason_label(String(r["reason"])), int(r["steps"]), int(r["collisions"])]
	_launch_btn.disabled = e.tournament_over
	_rebuild_log()


func _rebuild_log() -> void:
	for c in _log_box.get_children():
		_log_box.remove_child(c)
		c.queue_free()
	for line in GameManager.engine.recent_log(8):
		var l := Label.new()
		l.text = String(line)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.66, 0.70, 0.76))
		l.add_to_group(&"scalable_text")
		_log_box.add_child(l)


# =====================================================================
#  Interaction
# =====================================================================

func _on_launch() -> void:
	GameManager.launch(_power_slider.value, _aim_slider.value)


# =====================================================================
#  Draw — the stadium + the animated battle trajectory
# =====================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.11), true)
	# stadium bowl
	draw_circle(ARENA_CENTER, ARENA_VIEW_R, Color(0.12, 0.14, 0.19))
	draw_arc(ARENA_CENTER, ARENA_VIEW_R, 0.0, TAU, 96, Color(0.55, 0.60, 0.72), 3.0, true)
	draw_arc(ARENA_CENTER, ARENA_VIEW_R * 0.62, 0.0, TAU, 72, Color(0.24, 0.27, 0.34), 1.5, true)
	draw_circle(ARENA_CENTER, 5.0, Color(0.35, 0.40, 0.50))

	if _anim_trace.is_empty():
		return
	var frame_idx: int = clampi(_anim_i, 0, _anim_trace.size() - 1)
	# draw the path traced so far for each top
	for slot in 2:
		var path := PackedVector2Array()
		for fi in range(0, frame_idx + 1):
			var frame: Array = _anim_trace[fi]
			if slot < frame.size():
				var p: Array = frame[slot]
				path.append(ARENA_CENTER + Vector2(float(p[0]), float(p[1])))
		if path.size() >= 2:
			var col: Color = SPIN_COLOR.get(1 if slot == 0 else -1, Color.WHITE)
			col.a = 0.35
			draw_polyline(path, col, 1.5, true)
	# draw the tops at the current frame with a stamina ring
	var frame: Array = _anim_trace[frame_idx]
	for slot in frame.size():
		var p: Array = frame[slot]
		var pos: Vector2 = ARENA_CENTER + Vector2(float(p[0]), float(p[1]))
		var stamina: float = float(p[2])
		var stamina_max: float = maxf(1.0, float(p[3]))
		var alive: bool = bool(p[4])
		var base: Color = SPIN_COLOR.get(1 if slot == 0 else -1, Color.WHITE)
		if not alive:
			base = Color(0.4, 0.4, 0.44)
		draw_circle(pos, 15.0, base)
		draw_circle(pos, 8.0, Color(0.08, 0.09, 0.12))
		# stamina arc
		var frac: float = clampf(stamina / stamina_max, 0.0, 1.0)
		if frac > 0.0:
			draw_arc(pos, 20.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40,
				Color(0.55, 0.92, 0.60) if frac > 0.35 else Color(0.95, 0.55, 0.40), 3.0, true)
