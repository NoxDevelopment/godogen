extends Node2D
## res://scripts/survival_view.gd
## The playable survival-crafting view — renders GameManager's SurvivalEngine (the world of
## resource nodes, campfires with a night warmth-glow, the player, a day/night tint) and a
## needs/inventory HUD, and turns held-move + one-shot keys into intents. All rules live in
## SurvivalEngine; this is presentation + input only. WASD move · E harvest nearest · Q eat ·
## X craft axe · C build campfire · V craft meal · B build shelter · F refuel fire · T autoplay
## · R restart. (Coloured shapes are placeholders for real world + item art.)

const SX := 1.68
const ORIGIN := Vector2(120.0, 40.0)
const NODE_COLOR := [Color(0.3, 0.7, 0.35), Color(0.55, 0.55, 0.6), Color(0.85, 0.35, 0.4)]

var eng: SurvivalEngine

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if eng == null:
		return
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A): mv.x -= 1
	if Input.is_key_pressed(KEY_D): mv.x += 1
	if Input.is_key_pressed(KEY_W): mv.y -= 1
	if Input.is_key_pressed(KEY_S): mv.y += 1
	GameManager.set_move(mv)
	GameManager.advance(delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or eng == null:
		return
	match event.keycode:
		KEY_E:
			var n := _nearest_in_range()
			if not n.is_empty():
				GameManager.queue_act("harvest", int(n.id))
		KEY_Q: GameManager.queue_act("eat")
		KEY_X: GameManager.queue_act("axe")
		KEY_C: GameManager.queue_act("campfire")
		KEY_V: GameManager.queue_act("meal")
		KEY_B: GameManager.queue_act("shelter")
		KEY_F: GameManager.queue_act("refuel")
		KEY_T: GameManager.autoplay = not GameManager.autoplay
		KEY_R:
			GameManager.new_run()
			eng = GameManager.engine

func _nearest_in_range() -> Dictionary:
	var best := {}
	var bd := SurvivalEngine.HARVEST_R + 1.0
	for n in eng.nodes:
		if int(n.amount) <= 0:
			continue
		var d: float = (n.pos as Vector2).distance_to(eng.pos)
		if d <= SurvivalEngine.HARVEST_R and d < bd:
			bd = d
			best = n
	return best

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _w(v: Vector2) -> Vector2:
	return ORIGIN + v * SX

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	var wsz: Vector2 = SurvivalEngine.WORLD * SX
	# ground
	draw_rect(Rect2(ORIGIN, wsz), Color(0.18, 0.26, 0.16))
	# fire warmth glow (visible at night)
	for f in eng.fires:
		if int(f.fuel) > 0:
			draw_circle(_w(f.pos), SurvivalEngine.FIRE_R * SX, Color(0.9, 0.5, 0.2, 0.16))
			draw_circle(_w(f.pos), 7, Color(1.0, 0.7, 0.25))
	# nodes
	for n in eng.nodes:
		if int(n.amount) <= 0:
			continue
		var col: Color = NODE_COLOR[int(n.kind)]
		var rr := 6.0 + 3.0 * float(int(n.amount))
		draw_circle(_w(n.pos), rr, col)
	# player
	draw_circle(_w(eng.pos), 9, Color(0.95, 0.9, 0.8))
	# night tint overlay
	if eng.is_night():
		var prog: float = clampf(float(eng.tick_of_day - SurvivalEngine.NIGHT_START) / float(SurvivalEngine.DAY_TICKS - SurvivalEngine.NIGHT_START), 0.0, 1.0)
		draw_rect(Rect2(ORIGIN, wsz), Color(0.02, 0.03, 0.10, 0.35 + 0.25 * sin(prog * PI)))
	draw_rect(Rect2(ORIGIN, wsz), Color(0.4, 0.45, 0.4, 0.5), false, 2.0)
	_draw_hud(font)

func _bar(x: float, y: float, label: String, v: float, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var f: float = clampf(v / 100.0, 0.0, 1.0)
	draw_string(font, Vector2(x, y + 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.85, 0.88))
	draw_rect(Rect2(x + 70, y, 160, 14), Color(0.15, 0.15, 0.18))
	draw_rect(Rect2(x + 70, y, 160 * f, 14), col if v > 25.0 else Color(0.95, 0.35, 0.35))

func _draw_hud(font: Font) -> void:
	draw_string(font, Vector2(120, 28), "Day %d / %d   %02d:00   %s" % [
		eng.day, SurvivalEngine.SURVIVE_DAYS, eng.hour(), ("NIGHT" if eng.is_night() else "day")]
		+ ("   [AUTOPLAY]" if GameManager.autoplay else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	_bar(120, 720 - 66, "Health", eng.health, Color(0.9, 0.35, 0.4))
	_bar(360, 720 - 66, "Hunger", eng.hunger, Color(0.95, 0.65, 0.3))
	_bar(600, 720 - 66, "Warmth", eng.warmth, Color(0.5, 0.75, 1.0))
	draw_string(font, Vector2(120, 720 - 34),
		"wood %d  stone %d  food %d  fiber %d  meal %d   %s%s" % [
			int(eng.inv.wood), int(eng.inv.stone), int(eng.inv.food), int(eng.inv.fiber), int(eng.inv.meal),
			("[axe] " if eng.has_axe else ""), ("[shelter]" if eng.has_shelter else "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))
	draw_string(font, Vector2(120, 720 - 12),
		"WASD move · E harvest · Q eat · X axe · C campfire · V meal · B shelter · F refuel · T autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.64, 0.7))
	if eng.log_lines.size() > 0:
		draw_string(font, Vector2(880, 28), str(eng.log_lines[eng.log_lines.size() - 1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.8, 0.84))
	if eng.game_over:
		draw_string(font, Vector2(0, 300), "%s — press R" % ("YOU SURVIVED!" if eng.won else "YOU DIED"),
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 26, Color(1, 0.85, 0.4))
