extends Node2D
## res://scripts/dotio_view.gd
## The playable .io grow-arena view — renders GameManager's DotIoEngine (the objects, the player
## + rival holes sized by mass, a leaderboard + timer) and steers the player hole toward the
## mouse. All rules live in DotIoEngine; this is presentation + input only. Move toward the mouse ·
## swallow smaller objects/holes to grow · T attract (all AI) · R restart. (Coloured circles are
## placeholders for real hole/object art.)

const SX := 1.65
const ORIGIN := Vector2(150.0, 60.0)
const RIVAL_COLORS := [Color(0.9, 0.45, 0.4), Color(0.5, 0.75, 0.95), Color(0.55, 0.85, 0.5), Color(0.9, 0.8, 0.4)]

var eng: DotIoEngine

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null:
		return
	if not GameManager.player_auto and eng.holes.size() > 0:
		var pscreen: Vector2 = ORIGIN + (eng.holes[0].pos as Vector2) * SX
		GameManager.set_move(get_global_mouse_position() - pscreen)
	GameManager.advance(_delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			GameManager.player_auto = not GameManager.player_auto
		elif event.keycode == KEY_R:
			GameManager.new_match()
			eng = GameManager.engine

func _w(v: Vector2) -> Vector2:
	return ORIGIN + v * SX

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	var asz: Vector2 = DotIoEngine.ARENA * SX
	draw_rect(Rect2(ORIGIN, asz), Color(0.11, 0.13, 0.15))
	draw_rect(Rect2(ORIGIN, asz), Color(0.3, 0.34, 0.4), false, 2.0)
	# objects
	for o in eng.objects:
		if bool(o.alive):
			draw_circle(_w(o.pos), maxf(2.0, float(o.size) * 0.18) * SX, Color(0.65, 0.7, 0.5))
	# holes (rivals then player on top)
	for i in range(eng.holes.size()):
		var h: Dictionary = eng.holes[i]
		var col: Color = Color(0.1, 0.1, 0.12) if int(i) == 0 else RIVAL_COLORS[i % RIVAL_COLORS.size()]
		draw_circle(_w(h.pos), eng.radius(float(h.size)) * SX, col)
		if int(i) == 0:
			draw_arc(_w(h.pos), eng.radius(float(h.size)) * SX, 0, TAU, 32, Color(0.9, 0.9, 1.0, 0.8), 2.0)
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	var p: Dictionary = eng.holes[0] if eng.holes.size() > 0 else {}
	var secs := int((DotIoEngine.MATCH_TICKS - eng.tick_no) / 60)
	draw_string(font, Vector2(150, 40), "Time %02d   You: size %.0f · score %.0f · rank %d/%d%s" % [
		max(0, secs), float(p.get("size", 0)), float(p.get("score", 0)), eng.rank(), eng.holes.size(),
		("   [ATTRACT]" if GameManager.player_auto else "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# leaderboard
	var order: Array = []
	for i in range(eng.holes.size()):
		order.append({"i": i, "score": float(eng.holes[i].score)})
	order.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var ly := 90
	draw_string(font, Vector2(ORIGIN.x + DotIoEngine.ARENA.x * SX + 16, ly - 4), "LEADERBOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.92))
	for e in order:
		var idx := int(e.i)
		var name := "YOU" if idx == 0 else "Rival %d" % idx
		var col: Color = Color(0.9, 0.9, 1.0) if idx == 0 else RIVAL_COLORS[idx % RIVAL_COLORS.size()]
		draw_string(font, Vector2(ORIGIN.x + DotIoEngine.ARENA.x * SX + 16, ly + 18), "%s  %.0f" % [name, float(e.score)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		ly += 22
	draw_string(font, Vector2(150, ORIGIN.y + DotIoEngine.ARENA.y * SX + 26),
		"Move toward the mouse · swallow smaller objects & holes to grow · T attract · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.64, 0.7))
	if eng.game_over:
		draw_string(font, Vector2(0, 340), "%s — press R" % ("YOU WIN!" if eng.winner == 0 else "Rival %d wins" % eng.winner),
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 26, Color(1, 0.85, 0.4))
