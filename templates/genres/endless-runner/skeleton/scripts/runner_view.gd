extends Node2D
## res://scripts/runner_view.gd
## The playable endless-runner view — renders GameManager's RunnerEngine (the 3 lanes, the player
## with jump/slide posture, scrolling obstacles + coins, a distance/coins/score HUD) and queues
## the player's lane/jump/slide intent. All rules live in RunnerEngine; this is presentation +
## input only. A/D (or ←/→) switch lanes · W/↑/Space jump · S/↓ slide · T autoplay · R restart.
## (Coloured rects are placeholders for a runner character + themed obstacles/coins.)

const LANE_X := [480.0, 640.0, 800.0]
const PLAYER_Y := 560.0
const PXPERM := 3.0                 ## pixels per metre of look-ahead
const KIND_COLOR := {"block": Color(0.85, 0.35, 0.35), "hurdle": Color(0.9, 0.8, 0.35), "duck": Color(0.55, 0.5, 0.9)}

var eng: RunnerEngine

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null:
		return
	GameManager.advance(_delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_A, KEY_LEFT: GameManager.queue_dir(-1)
			KEY_D, KEY_RIGHT: GameManager.queue_dir(1)
			KEY_W, KEY_UP, KEY_SPACE: GameManager.queue_jump()
			KEY_S, KEY_DOWN: GameManager.queue_slide()
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_R:
				GameManager.new_run()
				eng = GameManager.engine

func _screen_y(item_dist: float) -> float:
	return PLAYER_Y - (item_dist - eng.distance) * PXPERM

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# lanes
	for l in range(RunnerEngine.LANES):
		draw_rect(Rect2(LANE_X[l] - 70, 40, 140, 620), Color(0.12, 0.13, 0.16))
		draw_rect(Rect2(LANE_X[l] - 70, 40, 140, 620), Color(0.25, 0.27, 0.32), false, 1.5)
	# coins
	for c in eng.pickups:
		if bool(c.got):
			continue
		var y := _screen_y(float(c.dist))
		if y < 20 or y > 700:
			continue
		draw_circle(Vector2(LANE_X[int(c.lane)], y), 10, Color(0.95, 0.82, 0.3))
	# obstacles
	for o in eng.obstacles:
		var y := _screen_y(float(o.dist))
		if y < 10 or y > 700:
			continue
		var col: Color = KIND_COLOR.get(str(o.kind), Color.RED)
		var x: float = LANE_X[int(o.lane)]
		match str(o.kind):
			"block": draw_rect(Rect2(x - 60, y - 44, 120, 88), col)
			"hurdle": draw_rect(Rect2(x - 60, y + 8, 120, 22), col)     # low bar → jump
			"duck": draw_rect(Rect2(x - 60, y - 60, 120, 22), col)     # high bar → slide
	# player
	var px: float = LANE_X[eng.lane]
	var py := PLAYER_Y
	var col := Color(0.4, 0.8, 1.0)
	if eng.is_jumping():
		py -= 34
		col = Color(0.5, 0.9, 1.0)
	if eng.is_sliding():
		draw_rect(Rect2(px - 30, py + 8, 60, 22), col)
	else:
		draw_rect(Rect2(px - 26, py - 44, 52, 52), col)
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	draw_string(font, Vector2(40, 44), "Distance %.0f m    Coins %d    Score %d    Speed %.1f%s" % [
		eng.distance, eng.coins, eng.score(), eng.speed, ("   [AUTOPLAY]" if GameManager.autoplay else "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_string(font, Vector2(40, 690), "A/D lanes · W/↑/Space jump (hurdle) · S/↓ slide (duck) · T autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.64, 0.7))
	if eng.game_over:
		var msg := "YOU RAN %.0f m — press R" % eng.distance
		if not eng.survived:
			msg = "CRASHED on a %s at %.0f m — press R" % [eng.crashed_on, eng.distance]
		draw_string(font, Vector2(0, 320), msg, HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, Color(1, 0.85, 0.4))
