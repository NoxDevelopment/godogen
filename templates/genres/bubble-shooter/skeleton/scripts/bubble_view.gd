extends Node2D
## res://scripts/bubble_view.gd
## The playable bubble-shooter view — renders GameManager's BubbleEngine (the hex-packed board,
## the shooter with its aim line, the current + on-deck bubbles, a score/shots HUD) and sets the
## aim from the mouse. All rules live in BubbleEngine; this is presentation + input only.
## Move the mouse to aim · click / Space to fire · T autoplay · R restart.
## (Coloured circles are placeholders for themed bubble art.)

const OX := 460.0                  ## field draw origin x (centres the 352-wide field)
const OY := 20.0
const PALETTE := [
	Color(0.90, 0.30, 0.32), Color(0.32, 0.62, 0.95), Color(0.42, 0.80, 0.42),
	Color(0.95, 0.80, 0.30), Color(0.72, 0.45, 0.90)]

var eng: BubbleEngine

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
	if event is InputEventMouseMotion and not GameManager.autoplay:
		var m: Vector2 = event.position
		var a := atan2(m.x - (OX + eng.shooter.x), -(m.y - (OY + eng.shooter.y)))
		GameManager.set_aim(a)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not GameManager.autoplay:
			GameManager.shoot()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if not GameManager.autoplay:
					GameManager.shoot()
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_R:
				GameManager.new_match()
				eng = GameManager.engine

func _fp(v: Vector2) -> Vector2:
	return Vector2(OX + v.x, OY + v.y)

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# field frame + lose line
	draw_rect(Rect2(OX, OY, BubbleEngine.W, BubbleEngine.TOP + BubbleEngine.MAX_ROW * BubbleEngine.ROWH + 70.0),
		Color(0.10, 0.11, 0.14))
	var lose_y := OY + BubbleEngine.TOP + float(BubbleEngine.MAX_ROW) * BubbleEngine.ROWH
	draw_line(Vector2(OX, lose_y), Vector2(OX + BubbleEngine.W, lose_y), Color(0.8, 0.3, 0.3, 0.6), 2.0)
	# bubbles
	for cell in eng.board:
		var col: Color = PALETTE[int(eng.board[cell]) % PALETTE.size()]
		var p := _fp(eng.cell_center(cell))
		draw_circle(p, BubbleEngine.R - 1.0, col)
		draw_arc(p, BubbleEngine.R - 1.0, 0, TAU, 20, Color(0, 0, 0, 0.25), 1.0)
	# aim line
	var sp := _fp(eng.shooter)
	var dir := Vector2(sin(GameManager.aim), -cos(GameManager.aim))
	draw_line(sp, sp + dir * 120.0, Color(1, 1, 1, 0.35), 2.0)
	# shooter current + on-deck
	var cur: Color = PALETTE[eng.current % PALETTE.size()]
	draw_circle(sp, BubbleEngine.R, cur)
	var nxt: Color = PALETTE[eng.next_color % PALETTE.size()]
	draw_circle(sp + Vector2(46, 6), BubbleEngine.R - 3.0, nxt)
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	draw_string(font, Vector2(40, 60), "BUBBLE SHOOTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(40, 100), "Score  %d" % eng.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 1.0))
	draw_string(font, Vector2(40, 128), "Popped %d   Dropped %d" % [eng.popped, eng.dropped],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.75, 0.8))
	draw_string(font, Vector2(40, 152), "Shots  %d   (drop every %d)" % [eng.shots, BubbleEngine.SHOTS_PER_DROP],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.75, 0.8))
	if GameManager.autoplay:
		draw_string(font, Vector2(40, 180), "[AUTOPLAY]", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 0.9, 0.6))
	draw_string(font, Vector2(40, 690), "Mouse aim · click/Space fire · T autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	if eng.game_over:
		var msg := "BOARD CLEARED — press R" if eng.won else "STACK REACHED THE LINE — press R"
		draw_string(font, Vector2(0, 360), msg, HORIZONTAL_ALIGNMENT_CENTER, 1280, 26, Color(1, 0.85, 0.4))
