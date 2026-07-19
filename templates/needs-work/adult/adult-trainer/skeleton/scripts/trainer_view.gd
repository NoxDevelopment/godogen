extends Node2D
## res://scripts/trainer_view.gd
## The playable adult-trainer (raiser) view — renders GameManager's TrainerEngine (the companion's
## five stat tracks, the week/resource HUD with money/stamina/mood/affection bars, and the weekly
## activity buttons) and picks each week's activity. All rules live in TrainerEngine; this is
## presentation + input only. Click an activity to spend the week · T autoplay · R restart.
## A `mature content gate` toggle is shown OFF by default — SYSTEMS only, no explicit content.

const ACT_ORDER := ["study", "etiquette", "combat", "art", "drill", "work", "rest", "outing"]
const ACT_LABEL := {"study": "Study (wit)", "etiquette": "Etiquette (grace)", "combat": "Combat (fitness)",
	"art": "Art (artistry)", "drill": "Drill (discipline)", "work": "Work (earn $)",
	"rest": "Rest (recover)", "outing": "Outing (affection)"}

var eng: TrainerEngine
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
				if str(r.id) == "mature":
					eng.mature_content = not eng.mature_content
				else:
					GameManager.choose(str(r.id))
				return

func _bar(x: float, y: float, w: float, frac: float, col: Color, label: String) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(x, y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.78, 0.85))
	draw_rect(Rect2(x, y, w, 12), Color(0.16, 0.17, 0.2))
	draw_rect(Rect2(x, y, w * clampf(frac, 0.0, 1.0), 12), col)

func _draw() -> void:
	if eng == null:
		return
	_rects = []
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(40, 44), "COMPANION TRAINER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(40, 78), "Week %d / %d" % [min(eng.week, TrainerEngine.WEEKS), TrainerEngine.WEEKS],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.9, 1.0))
	# resources
	_bar(40, 120, 260, float(eng.money) / 300.0, Color(0.9, 0.8, 0.3), "Money  $%d" % eng.money)
	_bar(40, 162, 260, eng.stamina / 100.0, Color(0.4, 0.8, 0.5), "Stamina  %d" % int(eng.stamina))
	_bar(40, 204, 260, eng.mood / 100.0, Color(0.5, 0.6, 0.9), "Mood  %d" % int(eng.mood))
	_bar(40, 246, 260, eng.affection / 100.0, Color(0.9, 0.4, 0.6), "Affection  %d  (target %d)" % [int(eng.affection), TrainerEngine.TARGET_AFFECTION])
	# stat tracks
	draw_string(font, Vector2(360, 116), "STAT TRACKS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.9, 0.85))
	var ty := 140.0
	for t in TrainerEngine.TRACKS:
		var mark: String = "  ◄ target %d" % TrainerEngine.TARGET_STAT if t == TrainerEngine.TARGET_TRACK else ""
		_bar(360, ty, 300, float(eng.stat(t)) / 100.0, Color(0.55, 0.75, 0.95), "%s  %d%s" % [str(t).capitalize(), eng.stat(t), mark])
		ty += 40.0
	# activity buttons
	draw_string(font, Vector2(720, 116), "THIS WEEK", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.9, 0.85))
	var by := 140.0
	for id in ACT_ORDER:
		var r := Rect2(720, by, 300, 36)
		_rects.append({"id": id, "rect": r})
		var afford := eng.can_afford(id) and not eng.game_over
		draw_rect(r, Color(0.20, 0.30, 0.42) if afford else Color(0.16, 0.17, 0.20))
		draw_rect(r, Color(0.4, 0.5, 0.65), false, 1.5)
		draw_string(font, Vector2(732, by + 24), str(ACT_LABEL[id]), HORIZONTAL_ALIGNMENT_LEFT, 288, 14,
			Color.WHITE if afford else Color(0.5, 0.5, 0.55))
		by += 42.0
	# mature-content gate toggle
	var mr := Rect2(720, by + 8, 300, 38)
	_rects.append({"id": "mature", "rect": mr})
	draw_rect(mr, Color(0.28, 0.16, 0.18))
	draw_rect(mr, Color(0.5, 0.35, 0.38), false, 1.5)
	draw_string(font, mr.position + Vector2(12, 24), "Mature content gate: %s" % ("ON" if eng.mature_content else "OFF (default)"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.7, 0.7))
	draw_string(font, Vector2(720, by + 66), "SYSTEMS-ONLY — the gate unlocks EMPTY hooks; no explicit content ships.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.5, 0.5))
	if eng.last_activity != "":
		draw_string(font, Vector2(40, 320), "Last: %s %s" % [eng.last_activity, eng.last_note], HORIZONTAL_ALIGNMENT_LEFT, 640, 13, Color(0.7, 0.72, 0.78))
	draw_string(font, Vector2(40, 700), "Click an activity to spend the week · T autoplay (greedy trainer) · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	if GameManager.autoplay:
		draw_string(font, Vector2(40, 96), "[AUTOPLAY — greedy trainer]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.9, 0.6))
	if eng.game_over:
		draw_string(font, Vector2(0, 360), "ENDING: %s%s — press R" % [eng.ending, ("  ★ target reached" if eng.won else "")],
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, Color(1, 0.85, 0.4))
