extends Node2D
## res://scripts/quiz_view.gd
## The playable quiz view — renders GameManager's QuizEngine (the current question, four
## answer buttons, a timer bar, and a live score/streak HUD) and, on the end screen, a
## per-category report card + grade. Drives the per-question countdown each physics tick. All
## rules live in QuizEngine; this is presentation + input only. Click an answer or press 1-4 ·
## T autoplay · R restart.

const CHOICE_COLORS := [Color(0.30, 0.42, 0.62), Color(0.55, 0.35, 0.55), Color(0.35, 0.55, 0.45), Color(0.6, 0.5, 0.3)]
var eng: QuizEngine
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
		match event.keycode:
			KEY_1: GameManager.choose(0)
			KEY_2: GameManager.choose(1)
			KEY_3: GameManager.choose(2)
			KEY_4: GameManager.choose(3)
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_R:
				GameManager.new_quiz()
				eng = GameManager.engine
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(_btn_rects.size()):
			if (_btn_rects[i] as Rect2).has_point(event.position):
				GameManager.choose(i)
				break
		queue_redraw()

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	if eng.done:
		_draw_results(font)
		return
	# HUD
	draw_string(font, Vector2(40, 44), "Question %d / %d" % [min(eng.idx + 1, QuizEngine.N_QUESTIONS), QuizEngine.N_QUESTIONS],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(font, Vector2(900, 44), "Score %d    Streak %d    Diff %d" % [eng.score, eng.streak, eng.difficulty],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.9, 0.5))
	if GameManager.autoplay:
		draw_string(font, Vector2(900, 66), "AUTOPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.9, 0.7))
	# timer bar
	var tf: float = clampf(float(eng.time_left) / float(QuizEngine.TIME_LIMIT), 0.0, 1.0)
	draw_rect(Rect2(40, 66, 800, 8), Color(0.2, 0.2, 0.24))
	draw_rect(Rect2(40, 66, 800 * tf, 8), Color(0.4, 0.8, 1.0) if tf > 0.3 else Color(0.95, 0.4, 0.4))
	# prompt
	if not eng.question.is_empty():
		draw_string(font, Vector2(60, 200), str(eng.question.prompt), HORIZONTAL_ALIGNMENT_CENTER, 1160, 30, Color.WHITE)
		# answer buttons 2x2
		_btn_rects = []
		var choices: Array = eng.question.choices
		for i in range(choices.size()):
			var col := i % 2
			var row := i / 2
			var r := Rect2(180 + col * 500, 300 + row * 120, 460, 96)
			_btn_rects.append(r)
			draw_rect(r, CHOICE_COLORS[i % CHOICE_COLORS.size()])
			draw_rect(r, Color(1, 1, 1, 0.25), false, 2.0)
			draw_string(font, r.position + Vector2(20, 56), "%d.  %s" % [i + 1, str(choices[i])], HORIZONTAL_ALIGNMENT_LEFT, 430, 22, Color.WHITE)
	# last-result flash + category
	if eng.last_result != "":
		var fc := Color(0.4, 1.0, 0.5)
		var txt := "Correct!"
		if eng.last_result == "wrong":
			fc = Color(1, 0.4, 0.4); txt = "Wrong"
		elif eng.last_result == "timeout":
			fc = Color(1, 0.7, 0.3); txt = "Time!"
		draw_string(font, Vector2(40, 560), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, fc)
	if not eng.question.is_empty():
		draw_string(font, Vector2(40, 640), "Category: %s" % str(eng.question.cat), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.72, 0.78))
	draw_string(font, Vector2(40, 680), "Click an answer or press 1-4 · T autoplay · R restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.64, 0.7))

func _draw_results(font: Font) -> void:
	draw_string(font, Vector2(0, 120), "QUIZ COMPLETE", HORIZONTAL_ALIGNMENT_CENTER, 1280, 34, Color.WHITE)
	draw_string(font, Vector2(0, 180), "Grade %s   —   %d / %d correct   (%.0f%%)" % [eng.grade(), eng.correct, QuizEngine.N_QUESTIONS, eng.accuracy()],
		HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, Color(1, 0.9, 0.5))
	draw_string(font, Vector2(0, 218), "Score %d   ·   best streak %d   ·   %s" % [eng.score, eng.max_streak, ("PASS" if eng.passed() else "needs review")],
		HORIZONTAL_ALIGNMENT_CENTER, 1280, 16, Color(0.85, 0.88, 0.92))
	# report card
	draw_string(font, Vector2(0, 290), "REPORT CARD", HORIZONTAL_ALIGNMENT_CENTER, 1280, 18, Color.WHITE)
	var y := 320
	for row in eng.report_card():
		var tot: int = int(row.total)
		var cor: int = int(row.correct)
		var pct: float = (float(cor) / float(tot) * 100.0) if tot > 0 else 0.0
		draw_string(font, Vector2(0, y), "%s — %d/%d  (%.0f%%)" % [str(row.cat), cor, tot, pct], HORIZONTAL_ALIGNMENT_CENTER, 1280, 16, Color(0.8, 0.85, 0.9))
		y += 30
	draw_string(font, Vector2(0, y + 40), "press R to try a new quiz", HORIZONTAL_ALIGNMENT_CENTER, 1280, 15, Color(0.7, 0.72, 0.78))
