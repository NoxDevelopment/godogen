extends Node2D
## res://scripts/shooter_view.gd
## The playable twin-stick view — steps GameManager's ShooterEngine at the physics rate
## (60Hz) sampling the human's move (WASD) + aim (mouse) + fire (hold), and draws the arena,
## player (with an aim line + i-frame flash), enemies (colour + HP by type), bullets, and a
## HUD (HP / wave / score). All rules live in ShooterEngine; this is presentation + input.
## Move WASD · aim with the mouse · hold left-mouse (or Space) to fire · T attract · R restart.

const SX := 2.2                        ## arena-unit → screen scale
const ORIGIN := Vector2(120.0, 40.0)
const ENEMY_COLOR := {"chaser": Color(1.0, 0.5, 0.4), "shooter": Color(0.9, 0.75, 0.3), "brute": Color(0.8, 0.35, 0.7)}

var eng: ShooterEngine

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null:
		return
	if not eng.game_over:
		GameManager.advance(_sample_input())
	queue_redraw()

func _sample_input() -> Dictionary:
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A): mv.x -= 1
	if Input.is_key_pressed(KEY_D): mv.x += 1
	if Input.is_key_pressed(KEY_W): mv.y -= 1
	if Input.is_key_pressed(KEY_S): mv.y += 1
	var ppos: Vector2 = eng.player.pos
	var pscreen: Vector2 = ORIGIN + ppos * SX
	var aim: Vector2 = get_global_mouse_position() - pscreen
	if aim.length() < 1.0:
		aim = eng.player.aim
	var fire := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)
	return {"move": mv, "aim": aim, "fire": fire}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			GameManager.player_auto = not GameManager.player_auto
		elif event.keycode == KEY_R:
			GameManager.new_run()
			eng = GameManager.engine

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _p(v: Vector2) -> Vector2:
	return ORIGIN + v * SX

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# arena
	draw_rect(Rect2(ORIGIN, ShooterEngine.ARENA * SX), Color(0.10, 0.11, 0.14))
	draw_rect(Rect2(ORIGIN, ShooterEngine.ARENA * SX), Color(0.3, 0.32, 0.4), false, 2.0)
	# bullets
	for b in eng.bullets:
		var c: Color = Color(0.5, 0.9, 1.0) if int(b.owner) == 0 else Color(1.0, 0.6, 0.25)
		draw_circle(_p(b.pos), 3.0, c)
	# enemies
	for e in eng.enemies:
		var col: Color = ENEMY_COLOR.get(str(e.kind), Color.RED)
		var d: Dictionary = ShooterEngine.ENEMY[str(e.kind)]
		draw_circle(_p(e.pos), float(d.radius) * SX * 0.5, col)
		var f: float = clampf(float(int(e.hp)) / float(int(e.max_hp)), 0.0, 1.0)
		if f < 1.0:
			draw_arc(_p(e.pos), float(d.radius) * SX * 0.5 + 3, -PI / 2, -PI / 2 + TAU * f, 16, Color(0.4, 1.0, 0.5), 2.0)
	# player
	var pp := _p(eng.player.pos)
	var pcol := Color(0.4, 0.8, 1.0)
	if int(eng.player.iframe) > 0 and (eng.frame / 3) % 2 == 0:
		pcol = Color(1, 1, 1, 0.5)
	draw_circle(pp, ShooterEngine.PLAYER_RADIUS * SX * 0.5, pcol)
	draw_line(pp, pp + Vector2(eng.player.aim) * 26.0, Color(1, 1, 0.5), 2.0)
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	# hp bar
	var f: float = clampf(float(int(eng.player.hp)) / float(ShooterEngine.PLAYER_HP), 0.0, 1.0)
	draw_rect(Rect2(120, 12, 260, 16), Color(0.2, 0.05, 0.05))
	draw_rect(Rect2(120, 12, 260 * f, 16), Color(0.3, 0.85, 0.4))
	draw_rect(Rect2(120, 12, 260, 16), Color.BLACK, false, 1.5)
	draw_string(font, Vector2(400, 26), "Wave %d/%d   Score %d   Enemies %d   %s" % [
		min(eng.wave, ShooterEngine.MAX_WAVES), ShooterEngine.MAX_WAVES, eng.score, eng.enemies.size(),
		("AUTO" if GameManager.player_auto else "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(font, Vector2(120, ORIGIN.y + ShooterEngine.ARENA.y * SX + 26),
		"WASD move · mouse aim · hold LMB/Space fire · T attract · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.66, 0.68, 0.72))
	if eng.log_lines.size() > 0:
		draw_string(font, Vector2(120, ORIGIN.y + ShooterEngine.ARENA.y * SX + 46),
			str(eng.log_lines[eng.log_lines.size() - 1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.8, 0.84))
	if eng.game_over:
		draw_string(font, Vector2(480, 300), "%s — press R" % ("YOU SURVIVED!" if eng.won else "YOU DIED"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.85, 0.4))
