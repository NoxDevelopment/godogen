extends Node2D
## res://scripts/idle_view.gd
## The playable idle-clicker view — steps GameManager's IdleEngine at the physics rate (60Hz)
## and draws the big clickable cookie, the counter + cps, the generator shop, the available
## upgrades, and a golden bonus when it appears. Clicks are captured as events and applied on
## the next sim tick. All rules live in IdleEngine; this is presentation + input only. Click
## the cookie to earn · click a shop row to buy · click the golden bonus · T autoplay · R restart.

const COOKIE_C := Vector2(230, 340)
const COOKIE_R := 110.0

var eng: IdleEngine
var _pending := {"click": false, "buy_gen": -1, "buy_up": "", "tap": false}
var _gen_rects: Array = []
var _up_rects: Array = []
var _golden_pos := Vector2(560, 200)

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null:
		return
	if GameManager.autoplay:
		GameManager.advance({})
	else:
		GameManager.advance(_pending.duplicate())
	_pending = {"click": false, "buy_gen": -1, "buy_up": "", "tap": false}
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			GameManager.autoplay = not GameManager.autoplay
		elif event.keycode == KEY_R:
			GameManager.new_run()
			eng = GameManager.engine
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(event.position)

func _on_click(p: Vector2) -> void:
	if eng == null:
		return
	# golden bonus
	if eng.golden_active > 0 and p.distance_to(_golden_pos) <= 34.0:
		_pending.tap = true
		return
	# the cookie
	if p.distance_to(COOKIE_C) <= COOKIE_R:
		_pending.click = true
		return
	# shop rows
	for i in range(_gen_rects.size()):
		if (_gen_rects[i] as Rect2).has_point(p):
			_pending.buy_gen = i
			return
	for entry in _up_rects:
		if (entry.rect as Rect2).has_point(p):
			_pending.buy_up = str(entry.id)
			return

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _fmt(n: float) -> String:
	var a := absf(n)
	if a >= 1.0e12: return "%.2fT" % (n / 1.0e12)
	if a >= 1.0e9: return "%.2fB" % (n / 1.0e9)
	if a >= 1.0e6: return "%.2fM" % (n / 1.0e6)
	if a >= 1.0e3: return "%.2fK" % (n / 1.0e3)
	return "%.0f" % n

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# cookie
	var cc := Color(0.75, 0.55, 0.3)
	if eng.frenzy > 0:
		cc = Color(0.95, 0.75, 0.35)
	draw_circle(COOKIE_C, COOKIE_R, cc)
	draw_circle(COOKIE_C, COOKIE_R, Color(0.4, 0.28, 0.15), false, 4.0)
	for d in [Vector2(-40, -30), Vector2(30, -50), Vector2(50, 20), Vector2(-20, 40), Vector2(0, -5), Vector2(-55, 15)]:
		draw_circle(COOKIE_C + d, 9, Color(0.3, 0.2, 0.12))
	draw_string(font, Vector2(120, 170), _fmt(eng.cookies) + " cookies", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	draw_string(font, Vector2(150, 200), "%s / sec%s" % [_fmt(eng.cps()), ("   FRENZY!" if eng.frenzy > 0 else "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.9, 0.5))
	draw_string(font, Vector2(120, 500), "Total baked: %s   ×click %s" % [_fmt(eng.total_earned), _fmt(eng.click_mult)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.82, 0.86))
	# ascension progress
	var prog: float = clampf(float(eng.total_earned) / float(IdleEngine.ASCEND_GOAL), 0.0, 1.0)
	draw_rect(Rect2(120, 520, 300, 8), Color(0.2, 0.2, 0.24))
	draw_rect(Rect2(120, 520, 300 * prog, 8), Color(0.7, 0.5, 0.95))
	draw_string(font, Vector2(120, 548), "Ascension: %s / %s%s" % [_fmt(eng.total_earned), _fmt(IdleEngine.ASCEND_GOAL),
		("  — READY!" if eng.ascended else "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.7, 0.95))
	# generator shop
	_gen_rects = []
	var sx := 700.0
	draw_string(font, Vector2(sx, 40), "GENERATORS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	for i in range(IdleEngine.GENERATORS.size()):
		var g: Dictionary = IdleEngine.GENERATORS[i]
		var r := Rect2(sx, 52 + i * 54, 440, 48)
		_gen_rects.append(r)
		var cost := eng.gen_cost(i)
		var afford: bool = eng.cookies >= cost
		draw_rect(r, Color(0.14, 0.15, 0.2) if afford else Color(0.10, 0.10, 0.12))
		draw_rect(r, Color(0.35, 0.5, 0.7) if afford else Color(0.2, 0.2, 0.24), false, 1.5)
		draw_string(font, r.position + Vector2(10, 20), "%s  x%d" % [str(g.name), int(eng.counts[i])], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		draw_string(font, r.position + Vector2(10, 40), "cost %s   +%s/s each" % [_fmt(cost), _fmt(float(g.cps) * float(eng.gen_mult[i]))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.72, 0.78) if afford else Color(0.5, 0.5, 0.55))
	# upgrades (available only)
	_up_rects = []
	var uy := 52 + IdleEngine.GENERATORS.size() * 54 + 20
	draw_string(font, Vector2(sx, uy - 6), "UPGRADES", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	var col := 0
	for u in IdleEngine.UPGRADES:
		if not eng.upgrade_available(u):
			continue
		var r := Rect2(sx + col * 150, uy + 8, 140, 40)
		_up_rects.append({"id": str(u.id), "rect": r})
		var afford: bool = eng.cookies >= float(u.cost)
		draw_rect(r, Color(0.18, 0.16, 0.10) if afford else Color(0.10, 0.10, 0.12))
		draw_rect(r, Color(0.8, 0.7, 0.3) if afford else Color(0.25, 0.25, 0.28), false, 1.5)
		draw_string(font, r.position + Vector2(6, 16), str(u.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.85, 0.7))
		draw_string(font, r.position + Vector2(6, 32), _fmt(float(u.cost)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.75, 0.8))
		col += 1
		if col >= 3:
			col = 0
			uy += 46
	# golden bonus
	if eng.golden_active > 0:
		var gc := Color(1, 0.85, 0.3) if eng.golden_kind == "lump" else Color(0.5, 0.9, 1.0)
		draw_circle(_golden_pos, 30, gc)
		draw_string(font, _golden_pos - Vector2(46, -46), "click me! (%s)" % eng.golden_kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, gc)
	# footer
	draw_string(font, Vector2(120, 690), "Click the cookie · click a shop row to buy · grab golden bonuses · T autoplay · R restart%s" % (
		"   [AUTOPLAY]" if GameManager.autoplay else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.66, 0.68, 0.72))
