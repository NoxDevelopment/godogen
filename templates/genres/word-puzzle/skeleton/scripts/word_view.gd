extends Node2D
## res://scripts/word_view.gd
## The playable word-puzzle view — renders GameManager's WordEngine (the guess grid with
## HIT/PRESENT/ABSENT colouring, the current round + streak + score HUD, an on-screen keyboard
## coloured by known letters) and collects the player's typed guess. All rules live in WordEngine;
## this is presentation + input only. Type A-Z · Backspace · Enter to submit · T autoplay · R restart.

const OX := 470.0
const OY := 90.0
const CELL := 62.0
const GAP := 8.0
const C_HIT := Color(0.36, 0.66, 0.38)
const C_PRESENT := Color(0.82, 0.70, 0.30)
const C_ABSENT := Color(0.24, 0.25, 0.29)
const C_EMPTY := Color(0.14, 0.15, 0.18)
const KEYS := ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]

var eng: WordEngine

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
		var kc: int = event.keycode
		if kc == KEY_T:
			GameManager.autoplay = not GameManager.autoplay
		elif kc == KEY_R:
			GameManager.new_run()
			eng = GameManager.engine
		elif GameManager.autoplay:
			return
		elif kc == KEY_ENTER or kc == KEY_KP_ENTER:
			GameManager.submit_typed()
		elif kc == KEY_BACKSPACE:
			GameManager.backspace()
		elif kc >= KEY_A and kc <= KEY_Z:
			GameManager.type_letter(char(kc))

## Best-known status of a letter across the current round's feedback (for keyboard colouring).
func _letter_status(ch: String) -> int:
	var best := -1
	for i in range(eng.guesses.size()):
		var g := str(eng.guesses[i])
		for p in range(g.length()):
			if g[p] == ch:
				best = maxi(best, int(eng.feedbacks[i][p]))
	return best

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# guess grid
	for r in range(WordEngine.MAX_GUESSES):
		for c in range(WordEngine.WORD_LEN):
			var x := OX + c * (CELL + GAP)
			var y := OY + r * (CELL + GAP)
			var col := C_EMPTY
			var letter := ""
			if r < eng.guesses.size():
				var g := str(eng.guesses[r])
				letter = g[c]
				var st: int = int(eng.feedbacks[r][c])
				col = C_HIT if st == WordEngine.HIT else (C_PRESENT if st == WordEngine.PRESENT else C_ABSENT)
			elif r == eng.guesses.size() and c < GameManager.typed.length() and not GameManager.autoplay:
				letter = GameManager.typed[c]
			draw_rect(Rect2(x, y, CELL, CELL), col)
			draw_rect(Rect2(x, y, CELL, CELL), Color(0, 0, 0, 0.3), false, 2.0)
			if letter != "":
				draw_string(font, Vector2(x + 18, y + 44), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	_draw_keyboard(font)
	_draw_hud(font)

func _draw_keyboard(font: Font) -> void:
	var ky := OY + WordEngine.MAX_GUESSES * (CELL + GAP) + 24.0
	for row in range(KEYS.size()):
		var line: String = KEYS[row]
		var kw := 40.0
		var rowx := OX + (WordEngine.WORD_LEN * (CELL + GAP) - line.length() * (kw + 4.0)) * 0.5 + row * 12.0
		for i in range(line.length()):
			var ch := line[i]
			var st := _letter_status(ch)
			var col := Color(0.30, 0.32, 0.37)
			if st == WordEngine.HIT: col = C_HIT
			elif st == WordEngine.PRESENT: col = C_PRESENT
			elif st == WordEngine.ABSENT: col = C_ABSENT
			var x := rowx + i * (kw + 4.0)
			draw_rect(Rect2(x, ky + row * (kw + 6.0), kw, kw), col)
			draw_string(font, Vector2(x + 12, ky + row * (kw + 6.0) + 28), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

func _draw_hud(font: Font) -> void:
	draw_string(font, Vector2(40, 60), "WORD PUZZLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	draw_string(font, Vector2(40, 110), "Round  %d / %d" % [eng.round_idx + 1, WordEngine.ROUNDS],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 1.0))
	draw_string(font, Vector2(40, 140), "Score  %d" % eng.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.85, 0.95))
	draw_string(font, Vector2(40, 168), "Streak %d  (best %d)" % [eng.streak, eng.best_streak],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.75, 0.8))
	draw_string(font, Vector2(40, 196), "Solved %d" % eng.rounds_solved(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.75, 0.8))
	if GameManager.autoplay:
		draw_string(font, Vector2(40, 224), "[AUTOPLAY — solver]", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 0.9, 0.6))
	draw_string(font, Vector2(40, 690), "Type A-Z · Backspace · Enter submit · T autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	if eng.game_over:
		var msg := "MARATHON DONE — %d / %d solved, %d pts — press R" % [eng.rounds_solved(), WordEngine.ROUNDS, eng.score]
		draw_string(font, Vector2(0, 40), msg, HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, Color(1, 0.85, 0.4))
