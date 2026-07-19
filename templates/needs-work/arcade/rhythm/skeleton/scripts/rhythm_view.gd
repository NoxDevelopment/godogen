extends Node2D
## res://scripts/rhythm_view.gd
## The playable rhythm view — steps GameManager's RhythmEngine at the physics rate (60Hz)
## with EDGE-triggered lane taps, and draws the 4-lane note highway (notes scroll down to a
## hit line), the score/combo/multiplier/accuracy/grade HUD, and a judgment flash. All rules
## live in RhythmEngine; this is presentation + input only. Tap D/F/J/K (or ←↓↑→) as each
## note reaches the line. T autoplay · R restart.

const LANE_KEYS := [KEY_D, KEY_F, KEY_J, KEY_K]
const LANE_ALT := [KEY_LEFT, KEY_DOWN, KEY_UP, KEY_RIGHT]
const LANE_X := [490.0, 590.0, 690.0, 790.0]
const LANE_W := 84.0
const TOP_Y := 80.0
const HIT_Y := 560.0
const PX_PER_TICK := 10.0            ## (HIT_Y - TOP_Y) / SCROLL_TICKS
const LANE_COLOR := [Color(0.4, 0.7, 1.0), Color(1.0, 0.5, 0.55), Color(0.55, 1.0, 0.6), Color(1.0, 0.8, 0.4)]

var eng: RhythmEngine
var _prev := [false, false, false, false]
var _flash := [0, 0, 0, 0]            ## per-lane press flash timers

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null:
		return
	var lanes := [false, false, false, false]
	for l in range(4):
		var down: bool = Input.is_key_pressed(LANE_KEYS[l]) or Input.is_key_pressed(LANE_ALT[l])
		if down and not bool(_prev[l]):
			lanes[l] = true
			_flash[l] = 6
		_prev[l] = down
		if int(_flash[l]) > 0:
			_flash[l] = int(_flash[l]) - 1
	if not eng.game_over:
		if GameManager.autoplay:
			GameManager.advance({})
		else:
			GameManager.advance({"lanes": lanes})
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			GameManager.autoplay = not GameManager.autoplay
		elif event.keycode == KEY_R:
			GameManager.new_song()
			eng = GameManager.engine
			_prev = [false, false, false, false]

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# lanes + hit line
	for l in range(4):
		var x: float = float(LANE_X[l]) - LANE_W / 2
		draw_rect(Rect2(x, TOP_Y, LANE_W, HIT_Y - TOP_Y + 40), Color(0.10, 0.11, 0.14))
		var tcol: Color = LANE_COLOR[l]
		var target := Rect2(x, HIT_Y, LANE_W, 12)
		draw_rect(target, tcol.darkened(0.5) if int(_flash[l]) == 0 else tcol)
		draw_rect(target, tcol, false, 2.0)
	draw_line(Vector2(LANE_X[0] - LANE_W / 2 - 4, HIT_Y), Vector2(LANE_X[3] + LANE_W / 2 + 4, HIT_Y), Color(1, 1, 1, 0.5), 2.0)
	# notes
	for n in eng.visible_notes():
		var l: int = int(n.lane)
		var y: float = HIT_Y - float(int(n.time) - eng.playhead) * PX_PER_TICK
		var x: float = float(LANE_X[l]) - LANE_W / 2 + 6
		draw_rect(Rect2(x, y - 8, LANE_W - 12, 16), LANE_COLOR[l])
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	draw_string(font, Vector2(40, 40), "Score %d" % eng.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(40, 72), "Combo %d   x%d" % [eng.combo, eng.mult()], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.5))
	draw_string(font, Vector2(40, 98), "Acc %.1f%%   Grade %s" % [eng.accuracy(), eng.grade()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.85, 0.9))
	draw_string(font, Vector2(1000, 40), "P %d  G %d  M %d" % [int(eng.counts.perfect), int(eng.counts.good), int(eng.counts.miss)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.78, 0.82))
	if GameManager.autoplay:
		draw_string(font, Vector2(1000, 64), "AUTOPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.9, 0.7))
	# progress bar
	var prog: float = clampf(float(eng.playhead) / float(max(1, eng.song_end)), 0.0, 1.0)
	draw_rect(Rect2(40, 118, 300, 6), Color(0.2, 0.2, 0.24))
	draw_rect(Rect2(40, 118, 300 * prog, 6), Color(0.5, 0.8, 1.0))
	# judgment flash (recent)
	if eng.playhead - eng.last_judge_tick < 18 and eng.last_judge != "":
		var jc := Color(0.4, 1.0, 0.5)
		if eng.last_judge == "GOOD": jc = Color(1, 0.9, 0.4)
		elif eng.last_judge == "MISS": jc = Color(1, 0.4, 0.4)
		draw_string(font, Vector2(540, 300), eng.last_judge, HORIZONTAL_ALIGNMENT_CENTER, 200, 30, jc)
	draw_string(font, Vector2(40, HIT_Y + 70), "Tap D F J K (or arrow keys) on the line · T autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.66, 0.68, 0.72))
	if eng.game_over:
		draw_string(font, Vector2(480, 340), "SONG CLEAR — %s  (%d) — press R" % [eng.grade(), eng.score],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.85, 0.4))
