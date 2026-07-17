extends Node2D
## res://scripts/venue_view.gd
## The playable adult-management (venue tycoon) view — renders GameManager's VenueMgmtEngine (the
## staff roster with skill/stamina/mood/popularity bars, the stations, a cash/reputation/day HUD,
## and management buttons) and drives management actions. All rules live in VenueMgmtEngine; this is
## presentation + input only. Buttons: Hire · Open station · Upgrade · Marketing · Advance day.
## A `mature content gate` toggle is shown OFF by default — this template ships the SYSTEMS, no
## explicit content. T autoplay · R restart. (Coloured bars/rects are placeholders for real art.)

var eng: VenueMgmtEngine
var _rects: Array = []               ## {id, rect, arg}

func _ready() -> void:
	eng = GameManager.engine
	set_process(true)

func _process(_delta: float) -> void:
	if eng == null:
		return
	if GameManager.autoplay:
		GameManager.step_autoplay()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_R:
				GameManager.new_run()
				eng = GameManager.engine
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not GameManager.autoplay:
		for r in _rects:
			if (r.rect as Rect2).has_point(event.position):
				_do(str(r.id), int(r.get("arg", -1)))
				return

func _do(id: String, arg: int) -> void:
	match id:
		"hire": GameManager.hire()
		"room": GameManager.add_room()
		"upgrade": GameManager.upgrade_room(arg)
		"marketing": GameManager.run_marketing()
		"advance": GameManager.advance_day()
		"mature": eng.mature_content = not eng.mature_content

func _button(x: float, y: float, w: float, label: String, id: String, arg: int, enabled: bool) -> void:
	var r := Rect2(x, y, w, 40)
	_rects.append({"id": id, "rect": r, "arg": arg})
	draw_rect(r, Color(0.20, 0.30, 0.42) if enabled else Color(0.16, 0.17, 0.20))
	draw_rect(r, Color(0.4, 0.5, 0.65), false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(x + 12, y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, w - 16, 15,
		Color.WHITE if enabled else Color(0.5, 0.5, 0.55))

func _bar(x: float, y: float, w: float, frac: float, col: Color) -> void:
	draw_rect(Rect2(x, y, w, 8), Color(0.16, 0.17, 0.2))
	draw_rect(Rect2(x, y, w * clampf(frac, 0.0, 1.0), 8), col)

func _draw() -> void:
	if eng == null:
		return
	_rects = []
	var font := ThemeDB.fallback_font
	# HUD
	draw_string(font, Vector2(40, 44), "VENUE MANAGEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(40, 80), "Day %d / %d    Cash $%d    Reputation %d/100" % [
		eng.day, VenueMgmtEngine.DAY_CAP, int(eng.cash), int(eng.reputation)], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.9, 1.0))
	draw_string(font, Vector2(40, 106), "Goal: $%d + rep %d    Last shift: served %d for $%d" % [
		int(VenueMgmtEngine.CASH_GOAL), int(VenueMgmtEngine.REP_GOAL), eng.last_served, int(eng.last_income)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.75, 0.82))
	# staff roster
	draw_string(font, Vector2(40, 150), "STAFF (%d/%d)" % [eng.staff.size(), VenueMgmtEngine.MAX_STAFF], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.9, 0.85))
	var y := 172.0
	for s in eng.staff:
		draw_string(font, Vector2(56, y + 14), "%s  skill %d  $%d/day" % [str(s.name), int(s.skill), int(s.wage)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		_bar(320, y + 4, 120, float(s.stamina) / 100.0, Color(0.4, 0.8, 0.5))
		_bar(452, y + 4, 120, float(s.mood) / 100.0, Color(0.5, 0.6, 0.9))
		_bar(584, y + 4, 120, float(s.popularity) / 100.0, Color(0.9, 0.7, 0.4))
		y += 30.0
	draw_string(font, Vector2(320, 166), "stamina", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 0.55))
	draw_string(font, Vector2(452, 166), "mood", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.6, 0.8))
	draw_string(font, Vector2(584, 166), "popularity", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.65, 0.45))
	# stations + upgrade buttons
	var sy := y + 24.0
	draw_string(font, Vector2(40, sy), "STATIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.9, 0.85))
	sy += 14.0
	for i in range(eng.rooms.size()):
		_button(56, sy, 220, "Station %d — L%d  (upgrade $%d)" % [i + 1, int(eng.rooms[i].level), int(VenueMgmtEngine.UPGRADE_COST)],
			"upgrade", i, eng.cash >= VenueMgmtEngine.UPGRADE_COST and int(eng.rooms[i].level) < VenueMgmtEngine.MAX_ROOM_LVL)
		sy += 46.0
	# action buttons (right column)
	var bx := 880.0
	_button(bx, 150, 300, "Hire staff  ($%d)" % int(VenueMgmtEngine.HIRE_COST), "hire", -1, eng.cash >= VenueMgmtEngine.HIRE_COST and eng.staff.size() < VenueMgmtEngine.MAX_STAFF)
	_button(bx, 200, 300, "Open station  ($%d)" % int(VenueMgmtEngine.UPGRADE_COST), "room", -1, eng.cash >= VenueMgmtEngine.UPGRADE_COST and eng.rooms.size() < 4)
	_button(bx, 250, 300, "Marketing campaign  ($%d)" % int(VenueMgmtEngine.MARKETING_COST), "marketing", -1, eng.cash >= VenueMgmtEngine.MARKETING_COST)
	_button(bx, 316, 300, "► ADVANCE DAY (run shift)", "advance", -1, not eng.game_over)
	# mature-content gate toggle
	var mr := Rect2(bx, 386, 300, 40)
	_rects.append({"id": "mature", "rect": mr})
	draw_rect(mr, Color(0.28, 0.16, 0.18))
	draw_rect(mr, Color(0.5, 0.35, 0.38), false, 1.5)
	draw_string(font, mr.position + Vector2(12, 24), "Mature content gate: %s" % ("ON" if eng.mature_content else "OFF (default)"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.7, 0.7))
	draw_string(font, Vector2(bx, 446), "SYSTEMS-ONLY template — the gate unlocks EMPTY author hooks;", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.5, 0.5))
	draw_string(font, Vector2(bx, 462), "no explicit content ships. Author your own gated, age-verified content.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.5, 0.5))
	# footer + terminal
	draw_string(font, Vector2(40, 700), "Click buttons to manage · Advance day to run the shift · T autoplay (greedy manager) · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	if eng.game_over:
		var msg := "GOAL MET on day %d — press R" % eng.day if eng.won else "OUT OF BUSINESS — press R"
		draw_string(font, Vector2(0, 120), msg, HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, Color(1, 0.85, 0.4))
	if GameManager.autoplay:
		draw_string(font, Vector2(bx, 130), "[AUTOPLAY — greedy manager]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.9, 0.6))
