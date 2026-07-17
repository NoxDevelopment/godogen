extends Node2D
## res://scripts/sandbox_view.gd
## The playable adult-sandbox view — renders GameManager's SandboxEngine (the location map, the
## day/block clock, the player's needs bars, the NPCs present here + their relationship stages, and
## the context actions) and drives travel + actions. All rules live in SandboxEngine; this is
## presentation + input only. Click a location to travel · click an action · T autoplay · R restart.
## A `mature content gate` toggle is shown OFF by default — SYSTEMS only, no explicit content.

const BLOCK_NAMES := ["Morning", "Midday", "Afternoon", "Evening", "Night", "Late"]

var eng: SandboxEngine
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
				var id := str(r.id)
				if id == "travel":
					GameManager.travel(int(r.arg))
				elif id == "mature":
					eng.mature_content = not eng.mature_content
				else:
					GameManager.act(id, int(r.get("arg", -1)))
				return

func _btn(x: float, y: float, w: float, h: float, label: String, id: String, arg: int, col: Color, enabled: bool) -> void:
	var r := Rect2(x, y, w, h)
	_rects.append({"id": id, "rect": r, "arg": arg})
	draw_rect(r, col if enabled else Color(0.16, 0.17, 0.20))
	draw_rect(r, Color(0.4, 0.5, 0.65), false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(x + 10, y + h * 0.5 + 6), label, HORIZONTAL_ALIGNMENT_LEFT, w - 14, 14,
		Color.WHITE if enabled else Color(0.5, 0.5, 0.55))

func _bar(x: float, y: float, w: float, frac: float, col: Color, label: String) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(x, y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.78, 0.85))
	draw_rect(Rect2(x, y, w, 10), Color(0.16, 0.17, 0.2))
	draw_rect(Rect2(x, y, w * clampf(frac, 0.0, 1.0), 10), col)

func _draw() -> void:
	if eng == null:
		return
	_rects = []
	var font := ThemeDB.fallback_font
	# clock + needs
	draw_string(font, Vector2(40, 44), "LIFE SANDBOX", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(40, 76), "Day %d / %d  ·  %s  ·  at the %s" % [min(eng.day, SandboxEngine.DAYS),
		SandboxEngine.DAYS, BLOCK_NAMES[min(eng.block, BLOCK_NAMES.size() - 1)], SandboxEngine.LOCATIONS[eng.location]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.9, 1.0))
	_bar(40, 116, 200, eng.energy / 100.0, Color(0.4, 0.8, 0.5), "Energy %d" % int(eng.energy))
	_bar(40, 150, 200, float(eng.money) / 300.0, Color(0.9, 0.8, 0.3), "Money $%d" % eng.money)
	_bar(40, 184, 200, eng.fitness / 100.0, Color(0.55, 0.75, 0.95), "Fitness %d" % int(eng.fitness))
	_bar(40, 218, 200, eng.mood / 100.0, Color(0.5, 0.6, 0.9), "Mood %d" % int(eng.mood))
	draw_string(font, Vector2(40, 250), "Gifts: %d    Progress: %d" % [eng.gifts, eng.progress()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.72, 0.78))
	# map (travel buttons)
	draw_string(font, Vector2(300, 106), "MAP — click to travel (free)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.9, 0.85))
	for i in range(SandboxEngine.LOCATIONS.size()):
		var col := Color(0.24, 0.34, 0.28) if i == eng.location else Color(0.20, 0.24, 0.30)
		var who := ""
		for n in range(eng.npcs.size()):
			if eng.npc_location(n, eng.day, eng.block) == i:
				who += ("" if who == "" else ",") + str(eng.npcs[n].name).substr(0, 1)
		_btn(300 + (i % 4) * 150, 124 + (i / 4) * 54, 140, 46,
			"%s%s" % [str(SandboxEngine.LOCATIONS[i]).capitalize(), ("  [" + who + "]" if who != "" else "")],
			"travel", i, col, true)
	# NPCs present here + relationship stages
	draw_string(font, Vector2(300, 250), "HERE NOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.9, 0.85))
	var py := 272.0
	var present := eng.present_npcs()
	if present.is_empty():
		draw_string(font, Vector2(316, py + 14), "(no one here this block — travel or wait)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	for i in present:
		var n = eng.npcs[i]
		draw_string(font, Vector2(316, py + 16), "%s — %s (%d)" % [str(n.name), eng.stage_name(float(n.rel)), int(n.rel)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.8, 0.85))
		_btn(560, py, 130, 28, "Socialize", "socialize", i, Color(0.20, 0.30, 0.42), eng.energy >= 10.0)
		_btn(700, py, 110, 28, "Gift (%d)" % eng.gifts, "gift", i, Color(0.30, 0.22, 0.40), eng.gifts > 0)
		py += 34.0
	# context actions for the current location
	draw_string(font, Vector2(880, 106), "ACTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.9, 0.85))
	var ay := 124.0
	if eng.location == SandboxEngine.HOME:
		_btn(880, ay, 300, 34, "Sleep (recover · next day)", "sleep", -1, Color(0.20, 0.30, 0.42), true); ay += 40
	if eng.location == SandboxEngine.WORK:
		_btn(880, ay, 300, 34, "Work (+$40 · -energy)", "work", -1, Color(0.20, 0.30, 0.42), eng.energy >= 20.0); ay += 40
	if eng.location == SandboxEngine.GYM:
		_btn(880, ay, 300, 34, "Train (+fitness · -energy)", "train", -1, Color(0.20, 0.30, 0.42), eng.energy >= 18.0); ay += 40
	if eng.location == SandboxEngine.SHOP:
		_btn(880, ay, 300, 34, "Buy gift (-$30)", "buy", -1, Color(0.20, 0.30, 0.42), eng.money >= 30); ay += 40
	if eng.location != SandboxEngine.HOME and eng.location != SandboxEngine.WORK:
		_btn(880, ay, 300, 34, "Relax (+mood)", "relax", -1, Color(0.20, 0.30, 0.42), true); ay += 40
	_btn(880, ay, 300, 34, "Wait (pass a block)", "wait", -1, Color(0.18, 0.20, 0.26), true); ay += 46
	# mature-content gate toggle
	var mr := Rect2(880, ay, 300, 38)
	_rects.append({"id": "mature", "rect": mr, "arg": 0})
	draw_rect(mr, Color(0.28, 0.16, 0.18))
	draw_rect(mr, Color(0.5, 0.35, 0.38), false, 1.5)
	draw_string(font, mr.position + Vector2(12, 24), "Mature content gate: %s" % ("ON" if eng.mature_content else "OFF (default)"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.7, 0.7))
	draw_string(font, Vector2(880, ay + 58), "SYSTEMS-ONLY — the gate unlocks EMPTY hooks; no explicit content ships.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.5, 0.5))
	# footer
	if GameManager.autoplay:
		draw_string(font, Vector2(40, 700), "[AUTOPLAY — greedy resident] · R restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.9, 0.6))
	else:
		draw_string(font, Vector2(40, 700), "Click a location to travel · click an action · T autoplay · R restart",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	if eng.game_over:
		draw_string(font, Vector2(0, 300), "SANDBOX OVER — progress %d, best relationship %s — press R" % [eng.progress(), eng.stage_name(eng.max_rel())],
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, Color(1, 0.85, 0.4))
