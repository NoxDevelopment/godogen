extends Control
## res://scripts/board.gd
## THE PLAY SURFACE (built entirely in code). Draws the deterministic peg board +
## the ball's bounce path + an aim indicator via _draw(), and lays a HUD over it
## (your HP, enemy HP, gold, relics, the current orb + deck/discard counts) with
## an aim slider + Fire control and swappable MAP / SHOP / REWARD / EVENT / REST
## panels. A human plays; the "Auto Step" button steps the deterministic auto-play
## to demo a whole run. All rules live in GameManager's PegEngine; this only reads
## state and forwards the chosen action.

const BOARD_ORIGIN: Vector2 = Vector2(40.0, 96.0)
const BOARD_SCALE: float = 1.16

const PEG_COLOR: Dictionary = {
	0: Color(0.62, 0.66, 0.74),   # normal
	1: Color(0.98, 0.80, 0.32),   # crit  (gold)
	2: Color(0.95, 0.45, 0.35),   # bomb  (red)
	3: Color(0.45, 0.85, 0.70),   # refresh (teal)
}
const NODE_COLOR: Dictionary = {
	"combat": Color(0.70, 0.74, 0.80),
	"elite": Color(0.95, 0.55, 0.45),
	"shop": Color(0.55, 0.80, 0.95),
	"event": Color(0.80, 0.70, 0.95),
	"rest": Color(0.55, 0.90, 0.65),
	"boss": Color(0.98, 0.40, 0.40),
}

var _layer: CanvasLayer
var _title: Label
var _hp: Label
var _enemy: Label
var _orb: Label
var _piles: Label
var _shot: Label
var _relics: Label
var _phase_label: Label
var _panel: VBoxContainer
var _aim_slider: HSlider
var _fire_btn: Button
var _log_box: VBoxContainer

var _aim_angle: float = 0.0
var _anim_traj: PackedVector2Array = PackedVector2Array()
var _anim_i: int = 0
var _anim_hit: PackedByteArray = PackedByteArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine.deck.is_empty() and not GameManager.engine.run_over:
		GameManager.new_run(GameManager.DEFAULT_SEED)
	_build_ui()
	GameManager.changed.connect(_on_changed)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		GameManager.new_run(GameManager.DEFAULT_SEED)


func _process(_delta: float) -> void:
	if _anim_i < _anim_traj.size():
		_anim_i = mini(_anim_traj.size(), _anim_i + 4)
		queue_redraw()


func _on_changed() -> void:
	# Kick off a ball animation when a fresh shot's trajectory is available.
	var e: PegEngine = GameManager.engine
	if e.last_trajectory.size() > 0 and e.last_trajectory != _anim_traj:
		_anim_traj = e.last_trajectory
		_anim_hit = e.last_pegs_hit
		_anim_i = 0
	_refresh()
	queue_redraw()


# =====================================================================
#  Board rendering (custom _draw — beneath the HUD CanvasLayer)
# =====================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.11), true)
	var e: PegEngine = GameManager.engine
	var o := BOARD_ORIGIN
	var s := BOARD_SCALE
	var w := PegEngine.BOARD_W * s
	var h := PegEngine.BOARD_H * s
	# field frame + walls.
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.10, 0.12, 0.16))
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.30, 0.34, 0.42), false, 2.0)
	if e.phase != "combat" or e.peg_count() == 0:
		return
	# pegs (hit pegs dimmed).
	for i in e.peg_count():
		var p := o + Vector2(e.peg_x[i], e.peg_y[i]) * s
		var t := int(e.peg_type[i])
		var col: Color = PEG_COLOR.get(t, Color.WHITE)
		if i < _anim_hit.size() and _anim_hit[i] == 1 and _anim_i >= _anim_traj.size():
			col = col.darkened(0.55)
		draw_circle(p, PegEngine.PEG_R * s, col)
	# aim indicator (preview trajectory) when idle.
	if _anim_i >= _anim_traj.size():
		var preview := e.preview_trajectory(_aim_angle)
		var prev := o + Vector2(PegEngine.BOARD_W * 0.5, PegEngine.SPAWN_Y) * s
		for k in range(0, preview.size(), 3):
			var pt := o + preview[k] * s
			draw_line(prev, pt, Color(0.9, 0.9, 0.5, 0.35), 1.0)
			prev = pt
	# the ball's live path (animated).
	if _anim_traj.size() > 0:
		var upto := mini(_anim_i, _anim_traj.size())
		var prev2 := o + Vector2(PegEngine.BOARD_W * 0.5, PegEngine.SPAWN_Y) * s
		for k in upto:
			var pt2 := o + _anim_traj[k] * s
			draw_line(prev2, pt2, Color(0.55, 0.85, 0.98, 0.8), 2.0)
			prev2 = pt2
		if upto > 0:
			draw_circle(o + _anim_traj[mini(upto, _anim_traj.size()) - 1] * s, PegEngine.BALL_R * s, Color(0.90, 0.95, 1.0))


# =====================================================================
#  HUD construction (all in code)
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	# Backdrop is painted in _draw() (root canvas layer 0) so the peg board stays
	# visible. A full-rect ColorRect in this front CanvasLayer would occlude it
	# (the bug that hid the shot behind the HUD).

	_title = _mk_label(Vector2(40, 18), 24, Color(0.95, 0.86, 0.55))
	_title.text = "PEG ROGUELIKE — bounce, bank, boss"
	_phase_label = _mk_label(Vector2(40, 54), 15, Color(0.72, 0.78, 0.86))

	# right-hand HUD column.
	_hp = _mk_label(Vector2(560, 96), 18, Color(0.70, 0.92, 0.72))
	_enemy = _mk_label(Vector2(560, 126), 18, Color(0.96, 0.62, 0.55))
	_orb = _mk_label(Vector2(560, 168), 16, Color(0.86, 0.86, 0.60))
	_piles = _mk_label(Vector2(560, 194), 14, Color(0.66, 0.70, 0.78))
	_shot = _mk_label(Vector2(560, 220), 14, Color(0.72, 0.86, 0.72))
	_relics = _mk_label(Vector2(560, 254), 14, Color(0.80, 0.74, 0.95))
	_relics.custom_minimum_size = Vector2(500, 0)
	_relics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# aim + fire (shown only in combat via _refresh).
	_mk_header(Vector2(560, 300), "AIM")
	_aim_slider = HSlider.new()
	_aim_slider.position = Vector2(560, 324)
	_aim_slider.custom_minimum_size = Vector2(300, 20)
	_aim_slider.min_value = -PegEngine.AIM_SPREAD
	_aim_slider.max_value = PegEngine.AIM_SPREAD
	_aim_slider.step = 0.01
	_aim_slider.value = 0.0
	_aim_slider.value_changed.connect(func(v: float) -> void:
		_aim_angle = v
		queue_redraw())
	_layer.add_child(_aim_slider)
	_fire_btn = _mk_button(Vector2(560, 356), "FIRE ORB")
	_fire_btn.pressed.connect(_on_fire)
	var auto_aim_btn := _mk_button(Vector2(680, 356), "Auto-Aim")
	auto_aim_btn.pressed.connect(func() -> void:
		_aim_slider.value = GameManager.engine.best_aim())

	# phase panel (map / shop / reward / event / rest option buttons).
	_mk_header(Vector2(560, 404), "CHOICES")
	_panel = VBoxContainer.new()
	_panel.position = Vector2(560, 428)
	_panel.custom_minimum_size = Vector2(500, 0)
	_panel.add_theme_constant_override("separation", 4)
	_layer.add_child(_panel)

	# global controls.
	var auto_btn := _mk_button(Vector2(560, 630), "Auto Step")
	auto_btn.pressed.connect(func() -> void: GameManager.auto_step())
	var newrun_btn := _mk_button(Vector2(680, 630), "New Run")
	newrun_btn.pressed.connect(func() -> void: GameManager.new_run(GameManager.DEFAULT_SEED))

	# log.
	_mk_header(Vector2(900, 96), "LOG")
	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(900, 120)
	_log_box.custom_minimum_size = Vector2(360, 0)
	_log_box.add_theme_constant_override("separation", 2)
	_layer.add_child(_log_box)


func _mk_header(pos: Vector2, text: String) -> void:
	var l := _mk_label(pos, 15, Color(0.66, 0.70, 0.76))
	l.text = text


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _mk_button(pos: Vector2, text: String) -> Button:
	var b := Button.new()
	b.position = pos
	b.text = text
	b.add_to_group(&"scalable_text")
	_layer.add_child(b)
	return b


# =====================================================================
#  Refresh — read engine state, rebuild HUD + the phase panel
# =====================================================================

func _refresh() -> void:
	var e: PegEngine = GameManager.engine
	_phase_label.text = "Phase: %s   ·   Depth %d   ·   Seed run%s" % [
		e.phase.to_upper(), e.depth, "  (OVER)" if e.run_over else ""]
	_hp.text = "You:  %d / %d HP        Gold %d" % [maxi(0, e.player_hp), e.player_max_hp, e.gold]
	_enemy.text = e.enemy_label() if e.phase == "combat" else (
		("RUN WON!" if e.run_won else "RUN LOST") if e.run_over else "")
	if e.phase == "combat" and e.current_orb != "":
		_orb.text = "Orb:  %s — %s" % [e.orb_name(e.current_orb), e.orb_desc(e.current_orb)]
		_piles.text = "Deck %d   ·   Draw %d   ·   Discard %d" % [
			e.deck.size(), e.draw_pile.size(), e.discard_pile.size()]
	else:
		_orb.text = ""
		_piles.text = "Deck: %d orbs" % e.deck.size()
	if not e.last_shot.is_empty() and e.phase == "combat":
		_shot.text = "Last shot: %d dmg, %d pegs, %d crit, %d bounce" % [
			int(e.last_shot.get("damage", 0)), int(e.last_shot.get("pegs", 0)),
			int(e.last_shot.get("crit", 0)), int(e.last_shot.get("bounces", 0))]
	else:
		_shot.text = ""
	_relics.text = "Relics: " + (", ".join(e.relics.map(func(r: String) -> String: return e.relic_name(r))) if not e.relics.is_empty() else "(none)")

	var combat := e.phase == "combat" and not e.run_over
	_aim_slider.visible = combat
	_fire_btn.visible = combat
	_fire_btn.disabled = not combat or e.current_orb == ""

	_rebuild_panel(e)
	_rebuild_log(e)


func _rebuild_panel(e: PegEngine) -> void:
	_clear(_panel)
	if e.run_over:
		_panel.add_child(_pill("Run over — New Run to play again.", Color(0.8, 0.8, 0.6)))
		return
	match e.phase:
		"map":
			for id in e.map_options():
				var t := e.node_type_of(id)
				var b := Button.new()
				b.text = "Travel -> %s" % t.capitalize()
				b.add_theme_color_override("font_color", NODE_COLOR.get(t, Color.WHITE))
				b.add_to_group(&"scalable_text")
				b.pressed.connect(func() -> void: GameManager.choose_node(id))
				_panel.add_child(b)
		"reward":
			for i in e.shop_items.size():
				var oid := String(e.shop_items[i]["id"])
				var b := Button.new()
				b.text = "Take %s — %s" % [e.orb_name(oid), e.orb_desc(oid)]
				b.add_to_group(&"scalable_text")
				b.pressed.connect(func() -> void: GameManager.choose_reward(i))
				_panel.add_child(b)
			var skip := Button.new()
			skip.text = "Skip reward"
			skip.add_to_group(&"scalable_text")
			skip.pressed.connect(func() -> void: GameManager.choose_reward(-1))
			_panel.add_child(skip)
		"shop":
			for i in e.shop_items.size():
				var item: Dictionary = e.shop_items[i]
				var b := Button.new()
				b.text = _shop_label(e, item)
				b.disabled = bool(item.get("bought", false)) or not e.is_legal({"type": "buy", "index": i})
				b.add_to_group(&"scalable_text")
				b.pressed.connect(func() -> void: GameManager.buy(i))
				_panel.add_child(b)
			var leave := Button.new()
			leave.text = "Leave shop -> map"
			leave.add_to_group(&"scalable_text")
			leave.pressed.connect(func() -> void: GameManager.leave_shop())
			_panel.add_child(leave)
		"event":
			_panel.add_child(_pill("%s — %s" % [String(e.event_data.get("name", "")), String(e.event_data.get("desc", ""))], Color(0.82, 0.78, 0.62)))
			var opts: Array = e.event_data.get("options", [])
			for i in opts.size():
				var b := Button.new()
				b.text = String(opts[i]["label"])
				b.add_to_group(&"scalable_text")
				b.pressed.connect(func() -> void: GameManager.choose_event(i))
				_panel.add_child(b)
		"rest":
			var heal := Button.new()
			heal.text = "Rest — heal %d%% max HP" % int(round(PegEngine.REST_HEAL_FRAC * 100.0))
			heal.add_to_group(&"scalable_text")
			heal.pressed.connect(func() -> void: GameManager.rest_choose("heal"))
			_panel.add_child(heal)
			var up := Button.new()
			up.text = "Rest — upgrade your first orb (+%d base)" % PegEngine.UPGRADE_BONUS
			up.add_to_group(&"scalable_text")
			up.pressed.connect(func() -> void: GameManager.rest_choose("upgrade"))
			_panel.add_child(up)
		"combat":
			_panel.add_child(_pill("Aim with the slider, then FIRE. (Auto-Aim finds the best angle.)", Color(0.7, 0.74, 0.8)))


func _shop_label(e: PegEngine, item: Dictionary) -> String:
	var tag := "[SOLD] " if bool(item.get("bought", false)) else ""
	match String(item["kind"]):
		"orb":
			return "%sOrb: %s — %d g" % [tag, e.orb_name(String(item["id"])), int(item["cost"])]
		"relic":
			return "%sRelic: %s — %d g" % [tag, e.relic_name(String(item["id"])), int(item["cost"])]
		"heal":
			return "%sHeal %d HP — %d g" % [tag, PegEngine.HEAL_AMOUNT, int(item["cost"])]
		"upgrade":
			return "%sUpgrade first orb — %d g" % [tag, int(item["cost"])]
	return "?"


func _rebuild_log(e: PegEngine) -> void:
	_clear(_log_box)
	for line in e.recent_log(16):
		_log_box.add_child(_pill(String(line), Color(0.70, 0.72, 0.76)))


func _pill(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(360, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_to_group(&"scalable_text")
	return l


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _on_fire() -> void:
	GameManager.fire(_aim_angle)
