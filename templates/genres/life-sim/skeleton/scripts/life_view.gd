extends Node2D
## res://scripts/life_view.gd
## The playable life-sim view — renders GameManager's LifeEngine (the six need bars, the clock +
## money + mood, the relationship panel, the current action, an aspiration bar, and an event log)
## and turns clicks / number keys into action choices. Time advances in real time (speed-adjust
## via GameManager). All rules live in LifeEngine; this is presentation + input only. Click an
## action or press 1-7 · T autoplay · R restart.

const NEED_COLOR := {
	"hunger": Color(0.95, 0.6, 0.3), "energy": Color(0.4, 0.7, 1.0), "hygiene": Color(0.4, 0.85, 0.8),
	"fun": Color(0.9, 0.5, 0.9), "social": Color(0.5, 0.85, 0.5), "bladder": Color(0.9, 0.85, 0.4),
}
const BUTTONS := ["eat", "sleep", "shower", "toilet", "relax", "socialize", "work"]
var eng: LifeEngine
var _btn_rects: Array = []

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
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_7:
			GameManager.choose(BUTTONS[k - KEY_1])
		elif k == KEY_T:
			GameManager.autoplay = not GameManager.autoplay
		elif k == KEY_R:
			GameManager.new_life()
			eng = GameManager.engine
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(_btn_rects.size()):
			if (_btn_rects[i] as Rect2).has_point(event.position):
				GameManager.choose(BUTTONS[i])
				break
		queue_redraw()

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# top HUD
	draw_string(font, Vector2(40, 44), "Day %d   %02d:00   $%d   mood %.0f%s" % [
		eng.day, eng.hour(), eng.money, eng.mood, ("   [AUTOPLAY]" if GameManager.autoplay else "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(font, Vector2(40, 72), "Doing: %s" % (eng.action if eng.action != "" else "idle") + ("  (%d)" % eng.action_left if eng.action != "" else ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.6))
	# need bars
	draw_string(font, Vector2(40, 118), "NEEDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))
	var y := 138.0
	for n in LifeEngine.NEEDS:
		var v: float = float(eng.needs[n])
		var f: float = clampf(v / 100.0, 0.0, 1.0)
		var col: Color = NEED_COLOR.get(n, Color.GRAY)
		if v < 25.0:
			col = Color(0.95, 0.35, 0.35)
		draw_string(font, Vector2(40, y + 14), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.82, 0.86))
		draw_rect(Rect2(150, y, 300, 16), Color(0.15, 0.15, 0.18))
		draw_rect(Rect2(150, y, 300 * f, 16), col)
		draw_rect(Rect2(150, y, 300, 16), Color.BLACK, false, 1.0)
		y += 24
	# relationships
	draw_string(font, Vector2(520, 118), "FRIENDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))
	var ry := 138.0
	for npc in LifeEngine.NPCS:
		var rv: float = float(eng.rel[npc])
		draw_string(font, Vector2(520, ry + 14), npc, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.82, 0.86))
		draw_rect(Rect2(620, ry, 220, 16), Color(0.15, 0.15, 0.18))
		draw_rect(Rect2(620, ry, 220 * clampf(rv / 100.0, 0.0, 1.0), 16), Color(0.9, 0.55, 0.7))
		ry += 24
	# aspiration bar
	draw_string(font, Vector2(520, 230), "ASPIRATION  ($%d & a friend at %d)" % [LifeEngine.ASPIRE_MONEY, LifeEngine.ASPIRE_FRIEND],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.75, 0.95))
	var mp: float = clampf(float(eng.money) / float(LifeEngine.ASPIRE_MONEY), 0.0, 1.0)
	var fp: float = clampf(eng.best_friend() / float(LifeEngine.ASPIRE_FRIEND), 0.0, 1.0)
	draw_rect(Rect2(520, 248, 320, 8), Color(0.2, 0.2, 0.24))
	draw_rect(Rect2(520, 248, 320 * minf(mp, fp), 8), Color(0.7, 0.5, 0.95))
	if eng.aspiration:
		draw_string(font, Vector2(520, 278), "LIFE GOAL ACHIEVED!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.4))
	# action buttons
	_btn_rects = []
	var bx := 40.0
	for i in range(BUTTONS.size()):
		var r := Rect2(bx + i * 148, 340, 138, 54)
		_btn_rects.append(r)
		var disabled: bool = eng.action != "" or (BUTTONS[i] == "work" and (not eng.is_work_time() or eng.worked_today))
		draw_rect(r, Color(0.12, 0.14, 0.2) if not disabled else Color(0.09, 0.09, 0.11))
		draw_rect(r, Color(0.4, 0.55, 0.75) if not disabled else Color(0.2, 0.2, 0.24), false, 1.5)
		draw_string(font, r.position + Vector2(10, 24), "%d. %s" % [i + 1, BUTTONS[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE if not disabled else Color(0.5, 0.5, 0.55))
	# event log
	var ly := 430
	for i in range(max(0, eng.log_lines.size() - 5), eng.log_lines.size()):
		draw_string(font, Vector2(40, ly), str(eng.log_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.72, 0.74, 0.78))
		ly += 20
	draw_string(font, Vector2(40, 690), "Click an action or press 1-7 · T autoplay · R restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.64, 0.7))
