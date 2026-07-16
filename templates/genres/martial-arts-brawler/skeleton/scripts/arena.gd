extends Control
## res://scripts/arena.gd
## THE PLAY SURFACE (built entirely in code). It renders the beat-'em-up stage —
## the two fighters as markers with HP + chi bars, the active attack hitbox, and a
## style/level HUD — via _draw(), drives a FIXED-timestep combat accumulator over
## GameManager's BrawlerEngine, reads the human's per-frame input (light/heavy/
## special/guard/walk + a mid-fight STYLE SWITCH), and exposes a LEARN panel to
## learn styles + spend technique points between fights. All combat + rules live in
## BrawlerEngine; this only reads state, forwards the chosen action, and renders.

## Fixed-timestep accumulator so the sim advances at BrawlerEngine.DT regardless of
## frame rate (deterministic given the input stream).
var _accum: float = 0.0
var _auto: bool = false           ## Auto-Fight toggle (AI drives side 0 too).

# world -> screen mapping
const STAGE_SCREEN_Y: float = 430.0
const WORLD_TO_SCREEN_X: float = 1.0

# HUD nodes
var _layer: CanvasLayer
var _title: Label
var _p_status: Label
var _f_status: Label
var _style_label: Label
var _rpg_label: Label
var _result: Label
var _controls: Label
var _log_box: VBoxContainer
var _style_buttons: Array = []
var _learn_box: VBoxContainer
var _guard_held: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if GameManager.engine.fighters.size() < 2 or GameManager.engine.campaign_over:
		GameManager.new_run(GameManager.DEFAULT_SEED)
	_build_ui()
	GameManager.changed.connect(_on_changed)
	_refresh()
	queue_redraw()
	print("DEBUG: arena ready — encounter=%d styles=%d" % [
		GameManager.engine.encounter_index, (GameManager.engine.player["known_styles"] as Array).size()])


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
		return
	if e.is_action_pressed(&"restart"):
		GameManager.new_run(GameManager.DEFAULT_SEED)
		return
	if e.is_action_pressed(&"atk_light"):
		GameManager.player_action({"type": "attack", "kind": "light"})
	elif e.is_action_pressed(&"atk_heavy"):
		GameManager.player_action({"type": "attack", "kind": "heavy"})
	elif e.is_action_pressed(&"atk_special"):
		GameManager.player_action({"type": "attack", "kind": "special"})
	elif e.is_action_pressed(&"move_left"):
		GameManager.player_action({"type": "walk", "dir": -1})
	elif e.is_action_pressed(&"move_right"):
		GameManager.player_action({"type": "walk", "dir": 1})
	elif e.is_action_pressed(&"switch_style"):
		_cycle_player_style()
	if e.is_action_pressed(&"guard"):
		_guard_held = true
	elif e.is_action_released(&"guard"):
		_guard_held = false


func _process(delta: float) -> void:
	var eng: BrawlerEngine = GameManager.engine
	if eng.campaign_over:
		return
	# hold-guard is a continuous input: re-issue it each accumulated step.
	_accum += delta
	var dt: float = BrawlerEngine.DT
	var guard: int = 8
	while _accum >= dt and guard > 0:
		_accum -= dt
		guard -= 1
		if _auto:
			# let the engine's own policy drive side 0 too (demo).
			GameManager.step()
		else:
			if _guard_held and not eng.fight_over:
				eng.request_action(0, {"type": "block"})
			GameManager.step()
		if eng.campaign_over:
			break
	queue_redraw()


func _on_changed() -> void:
	_refresh()
	queue_redraw()


# =====================================================================
#  UI construction (all in code)
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_title = _mk_label(Vector2(24, 14), 22, Color(0.92, 0.86, 0.66))
	_p_status = _mk_label(Vector2(24, 46), 15, Color(0.70, 0.90, 0.72))
	_p_status.custom_minimum_size = Vector2(560, 22)
	_f_status = _mk_label(Vector2(660, 46), 15, Color(0.94, 0.72, 0.66))
	_f_status.custom_minimum_size = Vector2(560, 22)
	_style_label = _mk_label(Vector2(24, 74), 14, Color(0.80, 0.84, 0.94))
	_style_label.custom_minimum_size = Vector2(1180, 20)
	_rpg_label = _mk_label(Vector2(24, 96), 14, Color(0.86, 0.82, 0.62))
	_rpg_label.custom_minimum_size = Vector2(1180, 20)

	_result = _mk_label(Vector2(24, 540), 18, Color(0.96, 0.80, 0.42))
	_result.custom_minimum_size = Vector2(900, 26)

	# --- style-switch buttons (built from the player's learned styles) ---
	_mk_header(Vector2(24, 566), "ACTIVE STYLE (switch mid-fight)")
	var sb_box: HBoxContainer = HBoxContainer.new()
	sb_box.position = Vector2(24, 592)
	sb_box.add_theme_constant_override("separation", 8)
	_layer.add_child(sb_box)
	_style_buttons = []
	for sid in BrawlerEngine.STYLE_ORDER:
		var b: Button = Button.new()
		b.text = String(BrawlerEngine.STYLES[sid]["name"])
		b.add_to_group(&"scalable_text")
		b.pressed.connect(func() -> void: _pick_style(String(sid)))
		sb_box.add_child(b)
		_style_buttons.append({"id": sid, "btn": b})

	# --- action buttons ---
	_mk_header(Vector2(24, 636), "ACTIONS")
	var ab: HBoxContainer = HBoxContainer.new()
	ab.position = Vector2(24, 662)
	ab.add_theme_constant_override("separation", 8)
	_layer.add_child(ab)
	_mk_action_button(ab, "Light (J)", {"type": "attack", "kind": "light"})
	_mk_action_button(ab, "Heavy (K)", {"type": "attack", "kind": "heavy"})
	_mk_action_button(ab, "Special (L)", {"type": "attack", "kind": "special"})
	_mk_action_button(ab, "Guard (Spc)", {"type": "block"})
	_mk_action_button(ab, "< Back (A)", {"type": "walk", "dir": -1})
	_mk_action_button(ab, "Fwd > (D)", {"type": "walk", "dir": 1})

	var auto_btn: Button = Button.new()
	auto_btn.text = "Auto-Fight"
	auto_btn.add_to_group(&"scalable_text")
	auto_btn.pressed.connect(func() -> void: _auto = not _auto)
	ab.add_child(auto_btn)
	var camp_btn: Button = Button.new()
	camp_btn.text = "Auto Campaign"
	camp_btn.add_to_group(&"scalable_text")
	camp_btn.pressed.connect(func() -> void: GameManager.auto_campaign())
	ab.add_child(camp_btn)
	var restart_btn: Button = Button.new()
	restart_btn.text = "Restart"
	restart_btn.add_to_group(&"scalable_text")
	restart_btn.pressed.connect(func() -> void: GameManager.new_run(GameManager.DEFAULT_SEED))
	ab.add_child(restart_btn)

	# --- learn / technique panel ---
	_mk_header(Vector2(960, 96), "MASTERY (learn / upgrade)")
	_learn_box = VBoxContainer.new()
	_learn_box.position = Vector2(960, 122)
	_learn_box.add_theme_constant_override("separation", 4)
	_layer.add_child(_learn_box)

	# --- combat log ---
	_mk_header(Vector2(660, 566), "COMBAT LOG")
	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(660, 592)
	_log_box.add_theme_constant_override("separation", 1)
	_layer.add_child(_log_box)

	_controls = _mk_label(Vector2(24, 700), 12, Color(0.6, 0.62, 0.68))
	_controls.text = "J/K/L attack  ·  Space guard  ·  A/D step  ·  Q cycle style  ·  Esc pause  ·  Bksp restart"
	_controls.custom_minimum_size = Vector2(1200, 18)

	_rebuild_learn_panel()


func _mk_label(pos: Vector2, sz: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _mk_header(pos: Vector2, text: String) -> void:
	var l: Label = _mk_label(pos, 14, Color(0.55, 0.58, 0.66))
	l.text = text


func _mk_action_button(box: HBoxContainer, text: String, action: Dictionary) -> void:
	var b: Button = Button.new()
	b.text = text
	b.add_to_group(&"scalable_text")
	b.pressed.connect(func() -> void: GameManager.player_action(action))
	box.add_child(b)


func _rebuild_learn_panel() -> void:
	for c in _learn_box.get_children():
		c.queue_free()
	var eng: BrawlerEngine = GameManager.engine
	for sid in BrawlerEngine.STYLE_ORDER:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_l: Label = Label.new()
		var st: Dictionary = BrawlerEngine.STYLES[sid]
		var known: bool = eng.knows_style(String(sid))
		var pts: int = int((eng.player["upgrades"] as Dictionary).get(sid, 0))
		name_l.text = "%s [%s]%s" % [String(st["name"]), String(st["archetype"]),
			(" +%d" % pts) if pts > 0 else ""]
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color",
			Color(0.82, 0.86, 0.72) if known else Color(0.5, 0.5, 0.54))
		name_l.custom_minimum_size = Vector2(220, 18)
		name_l.add_to_group(&"scalable_text")
		row.add_child(name_l)
		var up: Button = Button.new()
		up.text = "Upgrade" if known else "Locked"
		up.disabled = not known
		up.add_theme_font_size_override("font_size", 11)
		up.add_to_group(&"scalable_text")
		var this_sid: String = String(sid)
		up.pressed.connect(func() -> void:
			GameManager.upgrade_technique(this_sid)
			_rebuild_learn_panel())
		row.add_child(up)
		_learn_box.add_child(row)


# =====================================================================
#  Input helpers
# =====================================================================

func _cycle_player_style() -> void:
	var eng: BrawlerEngine = GameManager.engine
	var known: Array = eng.player["known_styles"] as Array
	if known.size() < 2 or eng.fighters.size() < 2:
		return
	var cur: String = String((eng.fighters[0] as Dictionary)["active_style"])
	var idx: int = known.find(cur)
	var next_style: String = String(known[(idx + 1) % known.size()])
	GameManager.player_switch_style(next_style)


func _pick_style(style_id: String) -> void:
	GameManager.player_switch_style(style_id)


# =====================================================================
#  HUD refresh
# =====================================================================

func _refresh() -> void:
	var eng: BrawlerEngine = GameManager.engine
	var enc: Dictionary = eng.current_encounter()
	var enc_name: String = String(enc.get("name", "—")) if not enc.is_empty() else "—"
	_title.text = "MARTIAL ARTS BRAWLER — Encounter %d/%d: %s" % [
		mini(eng.encounter_index + 1, BrawlerEngine.CAMPAIGN.size()),
		BrawlerEngine.CAMPAIGN.size(), enc_name]

	if eng.fighters.size() >= 2:
		var a: Dictionary = eng.fighters[0]
		var b: Dictionary = eng.fighters[1]
		_p_status.text = "%s  HP %.0f/%.0f  Chi %.0f  [%s]" % [
			String(a["name"]), float(a["hp"]), float(a["max_hp"]), float(a["chi"]),
			String(BrawlerEngine.STYLES[String(a["active_style"])]["name"])]
		_f_status.text = "%s  HP %.0f/%.0f  [%s / %s]" % [
			String(b["name"]), float(b["hp"]), float(b["max_hp"]),
			String(BrawlerEngine.STYLES[String(b["active_style"])]["name"]),
			eng.style_archetype(String(b["active_style"]))]
		var mult: float = eng.matchup_multiplier(String(a["active_style"]), String(b["active_style"]))
		var tag: String = "ADVANTAGE" if mult > 1.0 else ("disadvantage" if mult < 1.0 else "even")
		_style_label.text = "Matchup: your %s vs their %s -> x%.2f (%s)" % [
			eng.style_archetype(String(a["active_style"])),
			eng.style_archetype(String(b["active_style"])), mult, tag]

	_rpg_label.text = "Lv %d  XP %d  |  Body %d  Mind %d  Spirit %d  |  Technique pts %d  |  Continues %d" % [
		int(eng.player["level"]), int(eng.player["xp"]),
		int(eng.player["body"]), int(eng.player["mind"]), int(eng.player["spirit"]),
		int(eng.player["technique_points"]), eng.continues_left]

	if eng.campaign_over:
		_result.text = "CAMPAIGN %s" % ("WON — you are the Grandmaster!" if eng.is_campaign_won() else "LOST — your journey ends.")
	elif eng.fighters.size() >= 2 and eng.fight_over:
		_result.text = "Fight over — %s" % ("you win the bout" if eng.fight_winner() == 0 else "you were defeated")
	else:
		_result.text = ""

	# highlight the active style button.
	if eng.fighters.size() >= 2:
		var cur: String = String((eng.fighters[0] as Dictionary)["active_style"])
		for entry in _style_buttons:
			var b: Button = (entry as Dictionary)["btn"]
			var sid: String = String((entry as Dictionary)["id"])
			b.disabled = not eng.knows_style(sid)
			b.modulate = Color(1.0, 0.9, 0.4) if sid == cur else Color(1, 1, 1)

	_rebuild_log()
	_rebuild_learn_panel()


func _rebuild_log() -> void:
	for c in _log_box.get_children():
		c.queue_free()
	for line in GameManager.engine.recent_log(10):
		var l: Label = Label.new()
		l.text = String(line)
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(0.74, 0.76, 0.82))
		l.add_to_group(&"scalable_text")
		_log_box.add_child(l)


# =====================================================================
#  Stage rendering
# =====================================================================

func _draw() -> void:
	var eng: BrawlerEngine = GameManager.engine
	# stage floor
	draw_line(Vector2(BrawlerEngine.STAGE_MIN, STAGE_SCREEN_Y),
		Vector2(BrawlerEngine.STAGE_MAX, STAGE_SCREEN_Y), Color(0.30, 0.32, 0.40), 3.0)
	draw_line(Vector2(BrawlerEngine.STAGE_MIN, 150.0),
		Vector2(BrawlerEngine.STAGE_MIN, STAGE_SCREEN_Y), Color(0.20, 0.22, 0.28), 2.0)
	draw_line(Vector2(BrawlerEngine.STAGE_MAX, 150.0),
		Vector2(BrawlerEngine.STAGE_MAX, STAGE_SCREEN_Y), Color(0.20, 0.22, 0.28), 2.0)

	if eng.fighters.size() < 2:
		return
	_draw_fighter(eng, 0, Color(0.45, 0.85, 0.55))
	_draw_fighter(eng, 1, Color(0.90, 0.50, 0.45))


func _draw_fighter(eng: BrawlerEngine, side: int, col: Color) -> void:
	var f: Dictionary = eng.fighters[side]
	var x: float = float(f["x"])
	var facing: int = int(f["facing"])
	var top: float = STAGE_SCREEN_Y - 90.0
	# body
	var body_rect: Rect2 = Rect2(x - 16.0, top, 32.0, 90.0)
	draw_rect(body_rect, col, true)
	# head
	draw_circle(Vector2(x, top - 12.0), 12.0, col)
	# facing pip
	draw_circle(Vector2(x + float(facing) * 10.0, top - 12.0), 3.0, Color(0.1, 0.1, 0.12))
	# HP bar
	var hp_frac: float = clampf(float(f["hp"]) / maxf(1.0, float(f["max_hp"])), 0.0, 1.0)
	var bar_w: float = 90.0
	draw_rect(Rect2(x - bar_w * 0.5, top - 40.0, bar_w, 7.0), Color(0.2, 0.05, 0.05), true)
	draw_rect(Rect2(x - bar_w * 0.5, top - 40.0, bar_w * hp_frac, 7.0), Color(0.85, 0.30, 0.30), true)
	# chi bar
	var chi_frac: float = clampf(float(f["chi"]) / maxf(1.0, float(f["max_chi"])), 0.0, 1.0)
	draw_rect(Rect2(x - bar_w * 0.5, top - 30.0, bar_w, 5.0), Color(0.05, 0.1, 0.2), true)
	draw_rect(Rect2(x - bar_w * 0.5, top - 30.0, bar_w * chi_frac, 5.0), Color(0.35, 0.6, 0.95), true)

	# active hitbox (during active frames)
	if String(f["action"]) == BrawlerEngine.ACT_ATTACK:
		var mv: Dictionary = BrawlerEngine.STYLES[String(f["active_style"])]["moves"][String(f["move_kind"])]
		var frame: int = int(f["action_frame"])
		var su: int = int(mv["startup"])
		var ac: int = int(mv["active"])
		if frame >= su and frame < su + ac:
			var front: float = x + float(facing) * BrawlerEngine.FRONT_OFFSET
			var lo: float
			var hi: float
			if bool(mv["projectile"]):
				var traveled: float = float(frame - su) * float(mv["proj_speed"])
				var c: float = front + float(facing) * traveled
				lo = c - BrawlerEngine.PROJ_HALF
				hi = c + BrawlerEngine.PROJ_HALF
			else:
				var far: float = front + float(facing) * float(mv["reach"])
				lo = minf(front, far)
				hi = maxf(front, far)
			draw_rect(Rect2(lo, top + 20.0, hi - lo, 22.0), Color(1.0, 0.85, 0.3, 0.55), true)
