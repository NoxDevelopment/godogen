extends Node2D
## res://scripts/dating_view.gd
## The playable dating-sim view — renders GameManager's DatingEngine (player stats + money +
## calendar, the romanceable characters with affection + their preferences, and an event log) and
## turns clicks into day-actions. Turn-based: each action advances the calendar a day. Click a
## character to select, then Date / Gift / Confess targets them. A `mature_content` toggle is shown
## OFF by default — it only unlocks empty author hooks (this template ships systems, not content).
## Buttons or keys 1-4 (train/work) · A autoplay · R restart.

var eng: DatingEngine
var sel := 0                        ## selected character index
var _rects: Array = []              ## {id, rect}
var _char_rects: Array = []

func _ready() -> void:
	eng = GameManager.engine
	set_process(true)

func _process(delta: float) -> void:
	if eng == null:
		return
	GameManager.advance(delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if eng == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_A: GameManager.autoplay = not GameManager.autoplay
			KEY_R:
				GameManager.new_game()
				eng = GameManager.engine
				sel = 0
			KEY_1: _do("train_charm")
			KEY_2: _do("train_wit")
			KEY_3: _do("train_fitness")
			KEY_4: _do("work")
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for cr in _char_rects:
			if (cr.rect as Rect2).has_point(event.position):
				sel = int(cr.id)
		for b in _rects:
			if (b.rect as Rect2).has_point(event.position):
				_do(str(b.id))
		queue_redraw()

func _do(id: String) -> void:
	if eng == null or eng.game_over or GameManager.autoplay:
		if id == "mature":
			eng.mature_content = not eng.mature_content
		return
	var c: Dictionary = eng.chars[sel] if sel < eng.chars.size() else {}
	match id:
		"train_charm": eng.train("charm")
		"train_wit": eng.train("wit")
		"train_fitness": eng.train("fitness")
		"work": eng.work()
		"date": if not c.is_empty(): eng.go_on_date(str(c.name), str(c.pref_date))
		"gift": if not c.is_empty(): eng.give_gift(str(c.name), str(c.liked_gift))
		"confess": if not c.is_empty(): eng.confess(str(c.name))
		"mature": eng.mature_content = not eng.mature_content

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# header: stats + money + day
	draw_string(font, Vector2(40, 40), "Day %d / %d    $%d%s" % [
		min(eng.day, DatingEngine.SEMESTER), DatingEngine.SEMESTER, eng.money,
		("    [AUTOPLAY]" if GameManager.autoplay else "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	var sx := 40.0
	for s in DatingEngine.STATS:
		_statbar(sx, 62, s, float(eng.stats[s]))
		sx += 260
	# character cards
	_char_rects = []
	for i in range(eng.chars.size()):
		var c: Dictionary = eng.chars[i]
		var r := Rect2(40 + i * 400, 130, 380, 160)
		_char_rects.append({"id": i, "rect": r})
		var bg := Color(0.13, 0.14, 0.18) if i == sel else Color(0.10, 0.11, 0.14)
		draw_rect(r, bg)
		draw_rect(r, Color(1, 0.7, 0.8) if i == sel else Color(0.3, 0.3, 0.36), false, 2.0)
		draw_string(font, r.position + Vector2(14, 28), str(c.name) + ("  ♥" if bool(c.confessed) else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.9))
		# affection bar
		var af: float = clampf(float(c.affection) / 100.0, 0.0, 1.0)
		draw_rect(Rect2(r.position + Vector2(14, 44), Vector2(352, 16)), Color(0.2, 0.1, 0.14))
		draw_rect(Rect2(r.position + Vector2(14, 44), Vector2(352 * af, 16)), Color(0.95, 0.45, 0.6))
		draw_string(font, r.position + Vector2(14, 90), "likes: %s · %s · %s date" % [str(c.liked_stat), str(c.liked_gift), str(c.pref_date)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.82, 0.86))
		draw_string(font, r.position + Vector2(14, 116), "affection %.0f   milestones %d/3" % [float(c.affection), int(c.milestones)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.92))
	# action buttons
	_rects = []
	var acts := [["train_charm", "Train charm (1)"], ["train_wit", "Train wit (2)"], ["train_fitness", "Train fitness (3)"], ["work", "Work (4)"],
		["date", "Date"], ["gift", "Give gift"], ["confess", "Confess"]]
	for i in range(acts.size()):
		var col := i % 4
		var row := i / 4
		var r := Rect2(40 + col * 220, 340 + row * 62, 205, 50)
		_rects.append({"id": acts[i][0], "rect": r})
		draw_rect(r, Color(0.14, 0.15, 0.2))
		draw_rect(r, Color(0.5, 0.4, 0.55), false, 1.5)
		draw_string(font, r.position + Vector2(12, 30), str(acts[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# mature-content gate toggle
	var mr := Rect2(920, 340, 320, 50)
	_rects.append({"id": "mature", "rect": mr})
	draw_rect(mr, Color(0.16, 0.12, 0.12))
	draw_rect(mr, Color(0.6, 0.4, 0.4), false, 1.5)
	draw_string(font, mr.position + Vector2(12, 22), "Mature content gate: %s" % ("ON" if eng.mature_content else "OFF (default)"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.8, 0.8))
	draw_string(font, mr.position + Vector2(12, 40), "(unlocks empty author hooks only)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.6, 0.6))
	# log + result
	var ly := 480
	for i in range(max(0, eng.log_lines.size() - 6), eng.log_lines.size()):
		draw_string(font, Vector2(40, ly), str(eng.log_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.74, 0.76, 0.8))
		ly += 20
	draw_string(font, Vector2(40, 700), "Click a character to select · click an action (each takes a day) · A autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.64, 0.7))
	if eng.game_over:
		var msg := "♥ You're now with %s! ♥" % eng.partner if eng.route_done else "The semester ended — no confession"
		draw_string(font, Vector2(0, 300), msg + " — press R", HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, Color(1, 0.75, 0.85))

func _statbar(x: float, y: float, label: String, v: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(x, y + 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.85, 0.88))
	draw_rect(Rect2(x + 80, y, 150, 14), Color(0.15, 0.15, 0.18))
	draw_rect(Rect2(x + 80, y, 150 * clampf(v / 100.0, 0.0, 1.0), 14), Color(0.5, 0.75, 1.0))
