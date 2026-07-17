extends Node2D
## res://scripts/puzzledate_view.gd
## The playable adult-puzzle-dating view — renders GameManager's PuzzleDateEngine (the match-3 board
## of affection tokens, the current date's affection/preference panel, the gift buttons, a
## currency/turn HUD) and drives token swaps + gift buys. All rules live in PuzzleDateEngine; this
## is presentation + input only. Click two adjacent tokens to swap · click a gift · T autoplay ·
## R restart. A `mature content gate` toggle is shown OFF by default — SYSTEMS only, no content.

const BX := 60.0
const BY := 120.0
const CELL := 62.0
const TYPE_COLOR := [
	Color(0.90, 0.32, 0.34), Color(0.35, 0.62, 0.95), Color(0.45, 0.82, 0.5),
	Color(0.92, 0.6, 0.85), Color(0.95, 0.83, 0.35)]

var eng: PuzzleDateEngine
var _rects: Array = []

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
		var p: Vector2 = event.position
		# gift / gate buttons
		for r in _rects:
			if (r.rect as Rect2).has_point(p):
				if str(r.id) == "gift":
					GameManager.buy_gift(int(r.arg))
				elif str(r.id) == "mature":
					eng.mature_content = not eng.mature_content
				return
		# board cell
		if p.x >= BX and p.y >= BY:
			var c := int((p.x - BX) / CELL)
			var rr := int((p.y - BY) / CELL)
			if rr >= 0 and rr < PuzzleDateEngine.GRID and c >= 0 and c < PuzzleDateEngine.GRID:
				GameManager.click_cell(rr, c)

func _draw() -> void:
	if eng == null:
		return
	_rects = []
	var font := ThemeDB.fallback_font
	# board
	for r in range(PuzzleDateEngine.GRID):
		for c in range(PuzzleDateEngine.GRID):
			var v := eng._at(r, c)
			var x := BX + c * CELL
			var y := BY + r * CELL
			var col: Color = TYPE_COLOR[v % TYPE_COLOR.size()] if v >= 0 else Color(0.1, 0.1, 0.12)
			draw_rect(Rect2(x + 3, y + 3, CELL - 6, CELL - 6), col)
			var seld: bool = GameManager.sel.x == r and GameManager.sel.y == c
			if seld:
				draw_rect(Rect2(x + 2, y + 2, CELL - 4, CELL - 4), Color(1, 1, 1, 0.9), false, 3.0)
	# HUD (right column)
	var hx := BX + PuzzleDateEngine.GRID * CELL + 40.0
	draw_string(font, Vector2(BX, 60), "MATCH-3 DATING", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(BX, 96), "Turn %d / %d    Munny %d" % [eng.turns, PuzzleDateEngine.MAX_TURNS, eng.currency],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.95))
	draw_string(font, Vector2(hx, 60), "DATE: %s" % str(eng.chars[eng.target].name), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.7, 0.85))
	# affection bar for current target
	var aff: float = float(eng.chars[eng.target].affection)
	draw_string(font, Vector2(hx, 96), "Affection %d / %d   mood x%.2f" % [int(aff), int(PuzzleDateEngine.THRESHOLD), float(eng.chars[eng.target].mood)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.8, 0.85))
	draw_rect(Rect2(hx, 108, 300, 14), Color(0.16, 0.17, 0.2))
	draw_rect(Rect2(hx, 108, 300 * clampf(aff / PuzzleDateEngine.THRESHOLD, 0.0, 1.0), 14), Color(0.9, 0.4, 0.6))
	# preference legend
	draw_string(font, Vector2(hx, 150), "%s likes:" % str(eng.chars[eng.target].name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.82, 0.88))
	var pref: Array = eng.chars[eng.target].pref
	for t in range(PuzzleDateEngine.TYPES):
		var y := 168.0 + t * 24.0
		draw_rect(Rect2(hx, y, 18, 18), TYPE_COLOR[t])
		draw_string(font, Vector2(hx + 26, y + 15), "%s  x%.1f" % [PuzzleDateEngine.TYPE_NAMES[t], float(pref[t])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.82, 0.88))
	# gift buttons
	draw_string(font, Vector2(hx, 310), "GIFTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.9, 0.85))
	for i in range(PuzzleDateEngine.GIFTS.size()):
		var g: Dictionary = PuzzleDateEngine.GIFTS[i]
		var r := Rect2(hx, 330 + i * 44, 300, 38)
		_rects.append({"id": "gift", "rect": r, "arg": i})
		var afford := eng.currency >= int(g.cost) and not eng.game_over
		draw_rect(r, Color(0.20, 0.30, 0.42) if afford else Color(0.16, 0.17, 0.20))
		draw_rect(r, Color(0.4, 0.5, 0.65), false, 1.5)
		draw_string(font, Vector2(hx + 12, 330 + i * 44 + 24), "%s  (%d munny · +%d aff)" % [str(g.name), int(g.cost), int(g.affection)],
			HORIZONTAL_ALIGNMENT_LEFT, 288, 13, Color.WHITE if afford else Color(0.5, 0.5, 0.55))
	# roster progress
	draw_string(font, Vector2(hx, 486), "ROUTES", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.82, 0.88))
	for i in range(eng.chars.size()):
		var mark := "✓" if bool(eng.chars[i].done) else "…"
		draw_string(font, Vector2(hx, 508 + i * 22), "%s %s  (%d)" % [mark, str(eng.chars[i].name), int(eng.chars[i].affection)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.9, 0.6) if bool(eng.chars[i].done) else Color(0.7, 0.72, 0.78))
	# mature-content gate
	var mr := Rect2(hx, 590, 300, 38)
	_rects.append({"id": "mature", "rect": mr, "arg": 0})
	draw_rect(mr, Color(0.28, 0.16, 0.18))
	draw_rect(mr, Color(0.5, 0.35, 0.38), false, 1.5)
	draw_string(font, mr.position + Vector2(12, 24), "Mature content gate: %s" % ("ON" if eng.mature_content else "OFF (default)"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.7, 0.7))
	draw_string(font, Vector2(hx, 646), "SYSTEMS-ONLY — the gate unlocks EMPTY hooks; no explicit content ships.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.5, 0.5))
	if GameManager.autoplay:
		draw_string(font, Vector2(BX, 700), "[AUTOPLAY — greedy player] · R restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.9, 0.6))
	else:
		draw_string(font, Vector2(BX, 700), "Click two adjacent tokens to swap · click a gift · T autoplay · R restart",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	if eng.game_over:
		var msg := "ALL ROUTES COMPLETE — press R" if eng.won else "DATES OVER (%d routes) — press R" % eng.routes_done()
		draw_string(font, Vector2(0, 90), msg, HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, Color(1, 0.85, 0.4))
