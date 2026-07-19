extends Node2D
## res://scripts/horde_view.gd
## The playable horde auto-battler view — renders GameManager's HordeEngine (the wave/gold HUD, the
## recruit buttons, the current horde visualised as rows of little unit blocks by tier, and the last
## battle result) and drives recruiting + fighting. All rules live in HordeEngine; this is
## presentation + input only. Click recruit buttons to build your horde · click FIGHT to auto-battle
## the wave · T autoplay · R restart. (Coloured blocks are placeholders for real unit sprites.)

const TIER_COLOR := {"dude": Color(0.55, 0.75, 0.5), "brute": Color(0.85, 0.6, 0.35), "champion": Color(0.9, 0.4, 0.9)}

var eng: HordeEngine
var _rects: Array = []

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
		match event.keycode:
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_R:
				GameManager.new_run()
				eng = GameManager.engine
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not GameManager.autoplay:
		for r in _rects:
			if (r.rect as Rect2).has_point(event.position):
				if str(r.id) == "fight":
					GameManager.fight()
				else:
					GameManager.recruit(str(r.id))
				return

func _btn(x: float, y: float, w: float, h: float, label: String, id: String, col: Color, enabled: bool) -> void:
	var r := Rect2(x, y, w, h)
	_rects.append({"id": id, "rect": r})
	draw_rect(r, col if enabled else Color(0.16, 0.17, 0.20))
	draw_rect(r, Color(0.4, 0.5, 0.65), false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(x + 12, y + h * 0.5 + 6), label, HORIZONTAL_ALIGNMENT_LEFT, w - 16, 14,
		Color.WHITE if enabled else Color(0.5, 0.5, 0.55))

func _draw() -> void:
	if eng == null:
		return
	_rects = []
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(40, 44), "HORDE AUTO-BATTLER — how many dudes?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(40, 78), "Wave %d / %d    Gold %d    Horde %d (power %d)" % [
		min(eng.wave, HordeEngine.WAVES), HordeEngine.WAVES, eng.gold, eng.army_size(), eng.army_power()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 1.0))
	# recruit buttons
	var bx := 40.0
	for kind in HordeEngine.TIER_ORDER:
		var u: Dictionary = HordeEngine.UNITS[kind]
		_btn(bx, 104, 200, 40, "Recruit %s  ($%d)  x%d" % [str(kind).capitalize(), int(u.cost), eng.count_of(kind)],
			kind, Color(0.20, 0.30, 0.42), eng.can_buy(kind))
		bx += 214.0
	_btn(bx, 104, 200, 40, "► FIGHT WAVE %d" % min(eng.wave, HordeEngine.WAVES), "fight",
		Color(0.32, 0.24, 0.20), not eng.game_over and eng.army_size() > 0)
	# the horde visualised (blocks by tier)
	draw_string(font, Vector2(40, 178), "YOUR HORDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.9, 0.85))
	var i := 0
	for u in eng.army:
		var col: Color = TIER_COLOR.get(str(u.kind), Color.WHITE)
		var sz: float = 10.0 if str(u.kind) == "dude" else (16.0 if str(u.kind) == "brute" else 24.0)
		var px := 44.0 + (i % 40) * 30.0
		var py := 200.0 + (i / 40) * 32.0
		draw_rect(Rect2(px, py, sz, sz), col)
		i += 1
		if py > 560.0:
			break
	# last battle result
	if eng.last_result != "":
		var msg := "Last wave: %s — enemy %d, survivors %d" % [eng.last_result, eng.last_enemy_size, eng.last_survivors]
		draw_string(font, Vector2(40, 600), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.7))
	# recent log
	var ly := 626.0
	for line in eng.log_lines.slice(maxi(0, eng.log_lines.size() - 3), eng.log_lines.size()):
		draw_string(font, Vector2(40, ly), str(line), HORIZONTAL_ALIGNMENT_LEFT, 1100, 12, Color(0.6, 0.62, 0.68))
		ly += 16.0
	draw_string(font, Vector2(40, 700), "Recruit dudes/brutes/champions · FIGHT to auto-battle · T autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	if GameManager.autoplay:
		draw_string(font, Vector2(760, 78), "[AUTOPLAY — greedy commander]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.9, 0.6))
	if eng.game_over:
		var m := "VICTORY — all %d waves cleared! (horde %d) — press R" % [HordeEngine.WAVES, eng.army_size()] if eng.won else "THE HORDE FELL on wave %d — press R" % eng.wave
		draw_string(font, Vector2(0, 150), m, HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, Color(1, 0.85, 0.4))
