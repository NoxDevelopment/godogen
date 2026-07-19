extends Node2D
## res://scripts/fight_view.gd
## The playable fighting-game view — steps GameManager's FightEngine at the physics rate
## (60Hz fixed-timestep) sampling P1's held inputs, and draws the stage, both fighters (with
## the ACTIVE-frame hitbox extended so spacing reads), health bars, round pips, the timer and
## projectiles. All rules + frame data live in FightEngine; this is presentation + input only.
## P1: A/D move (hold away = block) · W jump · S crouch · F light-punch · G heavy-punch ·
## V light-kick · B heavy-kick · H special. Toggle attract mode with T · restart with R.

const SX := 2.6                        ## engine-unit → screen scale
const OX := 60.0                       ## stage left on screen
const FLOOR_SY := 560.0                ## screen y of the floor
const TEAM := [Color(0.40, 0.66, 1.0), Color(1.0, 0.50, 0.42)]
const ATK_KEYS := {KEY_F: "LP", KEY_G: "HP", KEY_V: "LK", KEY_B: "HK", KEY_H: "SP"}

var eng: FightEngine
var _prev_atk := {}                    ## edge-trigger tracking for attack keys

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null:
		return
	if not eng.game_over:
		GameManager.advance(_sample_p1())
	queue_redraw()

func _sample_p1() -> Dictionary:
	var inp := {"dir": 0, "up": false, "down": false, "atk": ""}
	if Input.is_key_pressed(KEY_A):
		inp.dir -= 1
	if Input.is_key_pressed(KEY_D):
		inp.dir += 1
	inp.up = Input.is_key_pressed(KEY_W)
	inp.down = Input.is_key_pressed(KEY_S)
	for k in ATK_KEYS:
		var down: bool = Input.is_key_pressed(k)
		if down and not bool(_prev_atk.get(k, false)) and str(inp.atk) == "":
			inp.atk = str(ATK_KEYS[k])
		_prev_atk[k] = down
	return inp

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

func _ex(x: int) -> float:
	return OX + float(x) * SX

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# stage
	draw_rect(Rect2(Vector2(OX, 120), Vector2(FightEngine.STAGE_W * SX, FLOOR_SY - 120 + 24)), Color(0.12, 0.13, 0.17))
	draw_line(Vector2(OX, FLOOR_SY), Vector2(OX + FightEngine.STAGE_W * SX, FLOOR_SY), Color(0.4, 0.42, 0.48), 2.0)
	# projectiles
	for p in eng.projectiles:
		var pc := Vector2(_ex(int(p.x)), FLOOR_SY - 20.0 * SX - float(int(p.y)) * SX)
		draw_circle(pc, 9, Color(0.9, 0.8, 0.3))
	# fighters
	for i in range(2):
		_draw_fighter(eng.f[i], TEAM[i])
	# HUD
	_draw_hud(font)

func _draw_fighter(ft: Dictionary, col: Color) -> void:
	var bx := _ex(int(ft.x))
	var h := 84.0 if not bool(ft.crouch) else 54.0
	var top := FLOOR_SY - h - float(int(ft.y)) * SX
	var body := Rect2(bx - 16, top, 32, h)
	var c := col
	if str(ft.state) == "hitstun":
		c = Color(1, 1, 1)
	elif str(ft.state) == "blockstun":
		c = col.darkened(0.3)
	draw_rect(body, c)
	# facing pip
	draw_rect(Rect2(bx + int(ft.facing) * 10 - 3, top + 12, 6, 6), Color.BLACK)
	# active-frame hitbox (the extended limb) so spacing/whiffs read
	if str(ft.state) == "attack":
		var md: Dictionary = FightEngine.MOVES[str(ft.move)]
		var active: bool = int(ft.mframe) > int(md.startup) and int(ft.mframe) <= int(md.startup) + int(md.active)
		if active and not bool(md.proj):
			var reach := float(int(md.range)) * SX
			var hy := top + (18.0 if str(md.height) == "high" else (h - 20.0 if str(md.height) == "low" else h * 0.4))
			var hx: float = (bx + 16.0) if int(ft.facing) > 0 else (bx - 16.0 - reach)
			draw_rect(Rect2(hx, hy, reach, 10), Color(1, 0.85, 0.3, 0.85))
		elif int(ft.mframe) <= int(md.startup):
			# startup telegraph
			draw_rect(Rect2(bx - 16, top - 6, 32, 4), Color(1, 0.6, 0.2, 0.8))

func _draw_hud(font: Font) -> void:
	# health bars
	for i in range(2):
		var ft: Dictionary = eng.f[i]
		var frac: float = clampf(float(int(ft.hp)) / float(FightEngine.MAX_HP), 0.0, 1.0)
		var w := 480.0
		var x := 40.0 if i == 0 else 1240.0 - w
		draw_rect(Rect2(x, 30, w, 22), Color(0.2, 0.05, 0.05))
		var fw := w * frac
		var fx := x if i == 0 else x + (w - fw)
		draw_rect(Rect2(fx, 30, fw, 22), Color(0.85, 0.75, 0.25))
		draw_rect(Rect2(x, 30, w, 22), Color.BLACK, false, 1.5)
		# round pips
		for r in range(FightEngine.ROUNDS_TO_WIN):
			var on: bool = int(eng.wins[i]) > r
			var px := x + r * 20.0 if i == 0 else x + w - 16 - r * 20.0
			draw_circle(Vector2(px + 6, 66), 6, Color(1, 0.85, 0.3) if on else Color(0.3, 0.3, 0.32))
	# timer + labels
	var secs := int((FightEngine.ROUND_FRAMES - eng.round_frame) / 60)
	draw_string(font, Vector2(600, 48), "%02d" % max(0, secs), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	draw_string(font, Vector2(40, 80), "P1 %s" % ("(AI)" if GameManager.player_auto else "(you)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEAM[0])
	draw_string(font, Vector2(1160, 80), "P2 (AI)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEAM[1])
	draw_string(font, Vector2(40, FLOOR_SY + 44),
		"A/D move (hold back=block) · W jump · S crouch · F LP · G HP · V LK · B HK · H special · T attract · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.66, 0.68, 0.72))
	# log
	if eng.log_lines.size() > 0:
		draw_string(font, Vector2(40, FLOOR_SY + 24), str(eng.log_lines[eng.log_lines.size() - 1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.82, 0.86))
	# banners
	if not eng.round_active and not eng.game_over and eng.round_winner >= 0:
		draw_string(font, Vector2(500, 300), "ROUND TO P%d" % (eng.round_winner + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 0.85, 0.4))
	if eng.game_over:
		draw_string(font, Vector2(470, 300), "P%d WINS — press R" % (eng.winner + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 0.85, 0.4))
