extends Node2D
## res://scripts/sports_view.gd
## The playable arcade-soccer view — steps GameManager's SportsEngine at the physics rate
## (60Hz) sampling the human's move/pass/shoot, and draws the pitch, both teams (the active
## team-0 player highlighted), the ball, goals, and a scoreboard + clock. All rules live in
## SportsEngine; this is presentation + input only. Move WASD/arrows · Space shoot · X pass ·
## T attract (both AI) · R restart. (Coloured circles are placeholders for real player sprites.)

const SX := 1.55
const ORIGIN := Vector2(150.0, 90.0)
const TEAM := [Color(0.40, 0.66, 1.0), Color(1.0, 0.48, 0.42)]

var eng: SportsEngine

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null:
		return
	if not eng.game_over:
		GameManager.advance(_sample())
	queue_redraw()

func _sample() -> Dictionary:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	return {"dir": dir, "shoot": Input.is_key_pressed(KEY_SPACE), "pass": Input.is_key_pressed(KEY_X)}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			GameManager.player_auto = not GameManager.player_auto
		elif event.keycode == KEY_R:
			GameManager.new_match()
			eng = GameManager.engine

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _f(v: Vector2) -> Vector2:
	return ORIGIN + v * SX

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	var fsz: Vector2 = SportsEngine.FIELD * SX
	# pitch
	draw_rect(Rect2(ORIGIN, fsz), Color(0.15, 0.40, 0.20))
	draw_rect(Rect2(ORIGIN, fsz), Color(0.7, 0.8, 0.7, 0.5), false, 2.0)
	draw_line(ORIGIN + Vector2(fsz.x / 2, 0), ORIGIN + Vector2(fsz.x / 2, fsz.y), Color(0.7, 0.8, 0.7, 0.4), 1.5)
	draw_arc(ORIGIN + fsz / 2, 46, 0, TAU, 32, Color(0.7, 0.8, 0.7, 0.4), 1.5)
	# goals (mouths on left + right)
	var gh := SportsEngine.GOAL_HALF * SX
	var cy := ORIGIN.y + fsz.y / 2
	for gx in [ORIGIN.x, ORIGIN.x + fsz.x]:
		draw_line(Vector2(gx, cy - gh), Vector2(gx, cy + gh), Color(1, 1, 0.5), 4.0)
	# active team-0 player
	var active := eng.chaser(0)
	var active_id: int = int(active.id) if not active.is_empty() else -1
	# players
	for p in eng.players:
		var sp := _f(p.pos)
		var col: Color = TEAM[int(p.team)]
		draw_circle(sp, SportsEngine.PLAYER_R * SX, col)
		if int(p.id) == int(eng.ball.owner):
			draw_arc(sp, SportsEngine.PLAYER_R * SX + 3, 0, TAU, 20, Color(1, 1, 1, 0.8), 1.5)
		if int(p.id) == active_id and not GameManager.player_auto:
			draw_arc(sp, SportsEngine.PLAYER_R * SX + 6, 0, TAU, 20, Color(1, 1, 0.3), 2.0)
	# ball
	draw_circle(_f(eng.ball.pos), SportsEngine.BALL_R * SX, Color(0.97, 0.97, 0.97))
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	# scoreboard + clock
	var secs := int(eng.tick_no / 60)
	draw_string(font, Vector2(0, 50), "%d   -   %d" % [int(eng.score[0]), int(eng.score[1])], HORIZONTAL_ALIGNMENT_CENTER, 1280, 30, Color.WHITE)
	draw_string(font, Vector2(0, 78), "%02d:%02d" % [secs / 60, secs % 60], HORIZONTAL_ALIGNMENT_CENTER, 1280, 16, Color(0.85, 0.88, 0.92))
	draw_string(font, Vector2(60, 50), "BLUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEAM[0])
	draw_string(font, Vector2(1160, 50), "RED", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEAM[1])
	if GameManager.player_auto:
		draw_string(font, Vector2(0, 100), "ATTRACT (both AI)", HORIZONTAL_ALIGNMENT_CENTER, 1280, 13, Color(0.6, 0.9, 0.7))
	draw_string(font, Vector2(150, ORIGIN.y + SportsEngine.FIELD.y * SX + 30),
		"WASD/arrows move · Space shoot · X pass · T attract · R restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.66, 0.68, 0.72))
	if eng.log_lines.size() > 0:
		draw_string(font, Vector2(150, ORIGIN.y + SportsEngine.FIELD.y * SX + 52), str(eng.log_lines[eng.log_lines.size() - 1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.8, 0.84))
	if eng.game_over:
		var msg := "FULL TIME — %d-%d — %s" % [int(eng.score[0]), int(eng.score[1]),
			("DRAW" if eng.winner < 0 else ("BLUE WINS" if eng.winner == 0 else "RED WINS"))]
		draw_string(font, Vector2(0, ORIGIN.y + SportsEngine.FIELD.y * SX / 2), msg + " — press R", HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, Color(1, 0.85, 0.4))
