extends Node2D
## res://scripts/hidden_view.gd
## The playable hidden-object view — renders GameManager's HiddenEngine (the cluttered scene of
## objects, the find-list checklist, a timer bar, and the score/hints HUD) and turns clicks in
## the play area into finds. All rules live in HiddenEngine; this is presentation + input only.
## A hinted item pulses. Click objects to find them · H hint · T autoplay · R restart. (The
## coloured labelled circles are placeholders for real scene art + item sprites.)

const PALETTE := [
	Color(0.9, 0.4, 0.4), Color(0.4, 0.7, 0.95), Color(0.5, 0.85, 0.5), Color(0.9, 0.8, 0.35),
	Color(0.75, 0.5, 0.9), Color(0.95, 0.6, 0.35), Color(0.4, 0.85, 0.8), Color(0.85, 0.55, 0.7),
]
var eng: HiddenEngine

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if eng == null:
		return
	GameManager.advance(delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if eng == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_H: GameManager.hint()
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_R:
				GameManager.new_game()
				eng = GameManager.engine
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ap: Vector2 = event.position - HiddenEngine.AREA_ORIGIN
		if ap.x >= 0 and ap.y >= 0 and ap.x <= HiddenEngine.AREA.x and ap.y <= HiddenEngine.AREA.y:
			GameManager.click(ap)
		queue_redraw()

func _item_color(name: String) -> Color:
	var idx: int = maxi(0, HiddenEngine.ITEMS.find(name))
	return PALETTE[idx % PALETTE.size()]

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# play area
	draw_rect(Rect2(HiddenEngine.AREA_ORIGIN, HiddenEngine.AREA), Color(0.10, 0.12, 0.14))
	draw_rect(Rect2(HiddenEngine.AREA_ORIGIN, HiddenEngine.AREA), Color(0.3, 0.32, 0.4), false, 2.0)
	# objects
	for o in eng.objects:
		var sp: Vector2 = HiddenEngine.AREA_ORIGIN + o.pos
		var found: bool = bool(o.found)
		var col: Color = _item_color(str(o.name))
		if found:
			col = col.darkened(0.6)
		draw_circle(sp, HiddenEngine.OBJ_R * 0.8, col)
		draw_string(font, sp + Vector2(-HiddenEngine.OBJ_R, HiddenEngine.OBJ_R + 12), str(o.name),
			HORIZONTAL_ALIGNMENT_CENTER, HiddenEngine.OBJ_R * 2, 10, Color(0.75, 0.77, 0.8) if not found else Color(0.4, 0.4, 0.45))
		if found:
			draw_string(font, sp - Vector2(6, -6), "x", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.3, 0.9, 0.4))
		# hint pulse
		if int(o.id) == eng.hint_id and eng.hint_timer > 0:
			var r := HiddenEngine.OBJ_R + 6 + float((eng.hint_timer / 6) % 6)
			draw_arc(sp, r, 0, TAU, 24, Color(1, 1, 0.4, 0.9), 2.5)
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	# top bar
	draw_string(font, Vector2(120, 44), "Round %d / %d    Score %d    Hints %d    Misses %d" % [
		min(eng.round_no, HiddenEngine.MAX_ROUNDS), HiddenEngine.MAX_ROUNDS, eng.score, eng.hints_left, eng.misclicks],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	if GameManager.autoplay:
		draw_string(font, Vector2(700, 44), "AUTOPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.9, 0.7))
	# timer bar
	var tf: float = clampf(float(eng.time_left) / float(HiddenEngine.ROUND_TIME), 0.0, 1.0)
	draw_rect(Rect2(120, 90, HiddenEngine.AREA.x, 8), Color(0.2, 0.2, 0.24))
	draw_rect(Rect2(120, 90, HiddenEngine.AREA.x * tf, 8), Color(0.4, 0.8, 1.0) if tf > 0.25 else Color(0.95, 0.4, 0.4))
	# find-list checklist (right sidebar over the area's right edge)
	var lx := HiddenEngine.AREA_ORIGIN.x + HiddenEngine.AREA.x + 10
	draw_string(font, Vector2(lx - HiddenEngine.AREA.x - 4, 118), "FIND:", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.88, 0.92))
	var fx := 168.0
	for item in eng.find_list_status():
		var c: Color = Color(0.4, 0.4, 0.45) if bool(item.found) else _item_color(str(item.name))
		var label := ("[x] " if bool(item.found) else "[ ] ") + str(item.name)
		draw_string(font, Vector2(fx, 118), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
		fx += 110
		if fx > HiddenEngine.AREA.x:
			pass
	draw_string(font, Vector2(120, HiddenEngine.AREA_ORIGIN.y + HiddenEngine.AREA.y + 30),
		"Click objects in the scene to find them · H hint · T autoplay · R restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.64, 0.7))
	if eng.game_over:
		draw_string(font, Vector2(0, 360), "%s — press R" % ("ALL SCENES CLEAR!" if eng.won else "TIME'S UP"),
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 26, Color(1, 0.85, 0.4))
