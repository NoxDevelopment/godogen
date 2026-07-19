extends Control
## res://scripts/port_map.gd
## THE PLAY SURFACE (built entirely in code). Draws the seeded Caribbean map — ports
## coloured by owner nation, the player's position, and a wind arrow — via _draw(),
## and lays a HUD over it: the CAPTAIN panel (gold/fame/land/morale/skills/reputation),
## the SHIP panel (hull/sails/cannons/crew/cargo), a TRADE panel (per-good buy/sell
## prices + a quantity slider + Buy/Sell), the PORT LIST (a Sail button per port), a
## COMBAT panel (the current encounter + stance buttons), crew actions (divide plunder,
## shore leave, recruit), quest/treasure + retire, an Auto-Step demo, and a log. A
## human plays; "Auto Step" steps the deterministic auto-play. All rules live in
## GameManager's PirateEngine; this only reads state + forwards the chosen action.

const NATION_COLOR: Dictionary = {
	"Crown":    Color(0.85, 0.30, 0.30),
	"Empire":   Color(0.35, 0.55, 0.95),
	"Republic": Color(0.40, 0.80, 0.45),
	"Company":  Color(0.90, 0.75, 0.35),
}

const MAP_ORIGIN: Vector2 = Vector2(24.0, 92.0)
const MAP_SCALE: Vector2 = Vector2(0.60, 0.60)

var _layer: CanvasLayer
var _title: Label
var _captain_lbl: Label
var _ship_lbl: Label
var _rep_lbl: Label
var _trade_lbl: Label
var _combat_lbl: Label
var _quest_lbl: Label
var _result_lbl: Label
var _log_box: VBoxContainer

var _good_opt: OptionButton
var _qty_slider: HSlider
var _qty_lbl: Label
var _port_opt: OptionButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine.ports.is_empty() and not GameManager.engine.career_over:
		GameManager.new_run(GameManager.DEFAULT_SEED)
	_build_ui()
	GameManager.changed.connect(_on_changed)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		GameManager.new_run(GameManager.DEFAULT_SEED)


func _on_changed() -> void:
	_refresh()
	queue_redraw()


# =====================================================================
#  UI construction
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	# Backdrop painted in _draw() (root layer 0), behind the port map. A full-rect
	# ColorRect in this front CanvasLayer would occlude the whole map.

	_title = _mk_label(Vector2(24, 14), 22, Color(0.90, 0.86, 0.62))
	_result_lbl = _mk_label(Vector2(24, 46), 15, Color(0.96, 0.72, 0.42))
	_result_lbl.custom_minimum_size = Vector2(760, 22)

	# --- right column: captain + ship + reputation ---
	var rx: float = 700.0
	_mk_header(Vector2(rx, 16), "CAPTAIN")
	_captain_lbl = _mk_label(Vector2(rx, 42), 13, Color(0.82, 0.88, 0.80))
	_captain_lbl.custom_minimum_size = Vector2(560, 96)

	_mk_header(Vector2(rx, 150), "SHIP")
	_ship_lbl = _mk_label(Vector2(rx, 176), 13, Color(0.78, 0.86, 0.92))
	_ship_lbl.custom_minimum_size = Vector2(560, 74)

	_mk_header(Vector2(rx, 258), "NATION STANDING")
	_rep_lbl = _mk_label(Vector2(rx, 284), 13, Color(0.86, 0.82, 0.72))
	_rep_lbl.custom_minimum_size = Vector2(560, 44)

	# --- trade panel ---
	_mk_header(Vector2(rx, 336), "TRADE AT PORT")
	_good_opt = _mk_option(Vector2(rx, 362))
	for gid in GameManager.engine.GOOD_IDS:
		var idx: int = _good_opt.item_count
		_good_opt.add_item(GameManager.engine.good_name(gid))
		_good_opt.set_item_metadata(idx, gid)
	_qty_lbl = _mk_label(Vector2(rx + 250, 366), 13, Color(0.75, 0.78, 0.82))
	_qty_slider = _mk_slider(Vector2(rx, 396), 1.0, 60.0, 10.0, 1.0)
	_qty_slider.value_changed.connect(func(_v: float) -> void: _refresh())
	var buy_btn: Button = _mk_button(Vector2(rx, 424), "BUY")
	buy_btn.pressed.connect(_on_buy)
	var sell_btn: Button = _mk_button(Vector2(rx + 90, 424), "SELL")
	sell_btn.pressed.connect(_on_sell)
	_trade_lbl = _mk_label(Vector2(rx, 458), 12, Color(0.72, 0.80, 0.74))
	_trade_lbl.custom_minimum_size = Vector2(560, 40)

	# --- combat panel ---
	_mk_header(Vector2(rx, 508), "THESE WATERS")
	_combat_lbl = _mk_label(Vector2(rx, 534), 12, Color(0.94, 0.70, 0.64))
	_combat_lbl.custom_minimum_size = Vector2(560, 40)
	var sink_btn: Button = _mk_button(Vector2(rx, 578), "Fire (Sink)")
	sink_btn.pressed.connect(func() -> void: GameManager.attack("sink"))
	var crip_btn: Button = _mk_button(Vector2(rx + 110, 578), "Chain (Cripple)")
	crip_btn.pressed.connect(func() -> void: GameManager.attack("cripple"))
	var board_btn: Button = _mk_button(Vector2(rx + 260, 578), "Board")
	board_btn.pressed.connect(func() -> void: GameManager.attack("board"))

	# --- crew + career actions (bottom left, under the map) ---
	var by: float = 470.0
	_mk_header(Vector2(24, by), "CREW & CAREER")
	var plunder_btn: Button = _mk_button(Vector2(24, by + 26), "Divide Plunder")
	plunder_btn.pressed.connect(func() -> void: GameManager.divide_plunder(60))
	var shore_btn: Button = _mk_button(Vector2(160, by + 26), "Shore Leave")
	shore_btn.pressed.connect(func() -> void: GameManager.shore_leave())
	var recruit_btn: Button = _mk_button(Vector2(290, by + 26), "Recruit +10")
	recruit_btn.pressed.connect(func() -> void: GameManager.recruit_crew(10))
	var dig_btn: Button = _mk_button(Vector2(420, by + 26), "Dig Treasure")
	dig_btn.pressed.connect(func() -> void: GameManager.dig_treasure())
	var retire_btn: Button = _mk_button(Vector2(556, by + 26), "Retire")
	retire_btn.pressed.connect(func() -> void: GameManager.retire())
	_quest_lbl = _mk_label(Vector2(24, by + 60), 12, Color(0.80, 0.82, 0.66))
	_quest_lbl.custom_minimum_size = Vector2(640, 34)

	# --- sail-to control ---
	_mk_header(Vector2(24, by + 100), "SET SAIL")
	_port_opt = _mk_option(Vector2(24, by + 126))
	_port_opt.custom_minimum_size = Vector2(300, 0)
	var sail_btn: Button = _mk_button(Vector2(340, by + 126), "SAIL ▶")
	sail_btn.pressed.connect(_on_sail)
	var auto_btn: Button = _mk_button(Vector2(430, by + 126), "Auto Step")
	auto_btn.pressed.connect(func() -> void: GameManager.auto_step())
	var restart_btn: Button = _mk_button(Vector2(540, by + 126), "Restart")
	restart_btn.pressed.connect(func() -> void: GameManager.new_run(GameManager.DEFAULT_SEED))

	# --- log ---
	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(24, by + 168)
	_log_box.add_theme_constant_override("separation", 1)
	_layer.add_child(_log_box)


func _mk_header(pos: Vector2, text: String) -> void:
	var l: Label = _mk_label(pos, 15, Color(0.60, 0.72, 0.84))
	l.text = text


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _mk_button(pos: Vector2, text: String) -> Button:
	var b: Button = Button.new()
	b.position = pos
	b.text = text
	b.add_to_group(&"scalable_text")
	_layer.add_child(b)
	return b


func _mk_option(pos: Vector2) -> OptionButton:
	var o: OptionButton = OptionButton.new()
	o.position = pos
	o.custom_minimum_size = Vector2(230, 0)
	o.add_to_group(&"scalable_text")
	_layer.add_child(o)
	return o


func _mk_slider(pos: Vector2, mn: float, mx: float, val: float, step: float) -> HSlider:
	var s: HSlider = HSlider.new()
	s.position = pos
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(220, 16)
	_layer.add_child(s)
	return s


# =====================================================================
#  Interaction
# =====================================================================

func _current_good() -> String:
	if _good_opt.selected < 0:
		return String(GameManager.engine.GOOD_IDS[0])
	return String(_good_opt.get_item_metadata(_good_opt.selected))


func _on_buy() -> void:
	GameManager.buy(_current_good(), int(_qty_slider.value))


func _on_sell() -> void:
	GameManager.sell(_current_good(), int(_qty_slider.value))


func _on_sail() -> void:
	if _port_opt.selected >= 0:
		GameManager.sail_to(int(_port_opt.get_item_metadata(_port_opt.selected)))


# =====================================================================
#  Refresh
# =====================================================================

func _refresh() -> void:
	var e: PirateEngine = GameManager.engine
	var status: String = ""
	if e.career_over:
		status = ("RETIRED — %s (WON)" % e.rank_name(e.retirement_rank)) if e.career_won \
			else ("CAREER OVER — %s (%s)" % [e.rank_name(e.retirement_rank), e.end_cause])
	else:
		status = "%s · %s (%s)" % [e.port_name(e.location), e.captain_name, e.phase]
	_title.text = "PIRATE CAREER SIM — Day %d/%d — %s" % [e.day, e.MAX_CAREER_DAYS, status]

	_captain_lbl.text = "Gold %d    Fame %d    Land %d    Age %.1f\nMorale %.0f%%    Marque: %s\nSkills — Nav %.1f  Gun %.1f  Fenc %.1f  Wit %.1f\nScore %d    Rank: %s" % [
		e.gold, e.fame, e.land, e.age, e.morale * 100.0, (e.marque if e.marque != "" else "none"),
		float(e.skills["navigation"]), float(e.skills["gunnery"]), float(e.skills["fencing"]), float(e.skills["wit"]),
		e.final_score(), e.rank_name(e.rank_for_score(e.final_score()))]

	var sh: Dictionary = e.ship
	_ship_lbl.text = "%s (%s)  Hull %d/%d  Sails %d/%d\nCannons %d   Crew %d/%d   Cargo %d/%d" % [
		String(sh["name"]), String(sh["class"]), int(sh["hull"]), int(sh["hull_max"]),
		int(sh["sails"]), int(sh["sails_max"]), int(sh["cannons"]),
		int(sh["crew"]), int(sh["crew_max"]), e.cargo_used(), int(sh["cargo_cap"])]

	var rep_parts: Array = []
	for n in e.NATIONS:
		rep_parts.append("%s %+d" % [n, int(float(e.reputation[n]))])
	_rep_lbl.text = "   ".join(rep_parts)

	var good: String = _current_good()
	_qty_lbl.text = "Qty: %d" % int(_qty_slider.value)
	var buy_p: int = e.port_buy_price(good)
	var sell_p: int = e.port_sell_price(good)
	_trade_lbl.text = "%s — buy %d / sell %d gold per unit  (cargo free %d)" % [
		e.good_name(good), buy_p, sell_p, e.cargo_free()]

	if e.encounter.is_empty():
		_combat_lbl.text = "Clear seas — no ship in range."
	else:
		var en: Dictionary = e.encounter
		_combat_lbl.text = "%s spotted! Hull %d  Cannons %d  Crew %d" % [
			String(en["name"]), int(en["hull"]), int(en["cannons"]), int(en["crew"])]

	_quest_lbl.text = "Quest %d/%d: %s   ·   Treasure fragments %d/%d%s" % [
		mini(e.quest_step + 1, e.QUEST_CHAIN.size()), e.QUEST_CHAIN.size(),
		(String(e.QUEST_CHAIN[e.quest_step]["desc"]) if e.quest_step < e.QUEST_CHAIN.size() else "saga complete"),
		e.fragments, e.FRAGMENTS_FOR_MAP,
		("   (map ready — dig!)" if e.fragments >= e.FRAGMENTS_FOR_MAP and not e.treasure_found else "")]

	if not e.last_combat.is_empty():
		_result_lbl.text = "Last battle: %s in %d turns (stance %s)." % [
			String(e.last_combat["outcome"]), int(e.last_combat["turns"]), String(e.last_combat["stance"])]

	_populate_ports()
	_rebuild_log()


func _populate_ports() -> void:
	var e: PirateEngine = GameManager.engine
	var prev: int = -1
	if _port_opt.item_count > 0 and _port_opt.selected >= 0:
		prev = int(_port_opt.get_item_metadata(_port_opt.selected))
	_port_opt.clear()
	for i in e.ports.size():
		if i == e.location:
			continue
		var days: int = e.travel_days_to(i)
		var hostile: String = "  [HOSTILE]" if e.port_hostile(i) else ""
		var idx: int = _port_opt.item_count
		_port_opt.add_item("%s (%s) — %dd%s" % [e.port_name(i), String(e.ports[i]["nation"]), days, hostile])
		_port_opt.set_item_metadata(idx, i)
		if i == prev:
			_port_opt.select(idx)


func _rebuild_log() -> void:
	for c in _log_box.get_children():
		_log_box.remove_child(c)
		c.queue_free()
	for line in GameManager.engine.recent_log(7):
		var l: Label = Label.new()
		l.text = String(line)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.66, 0.72, 0.78))
		l.add_to_group(&"scalable_text")
		_log_box.add_child(l)


# =====================================================================
#  Draw — the seeded map (ports by nation, the player, the wind)
# =====================================================================

func _map_point(p: Vector2) -> Vector2:
	return MAP_ORIGIN + Vector2(p.x * MAP_SCALE.x, p.y * MAP_SCALE.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.10, 0.15), true)
	var e: PirateEngine = GameManager.engine
	if e.ports.is_empty():
		return
	# sea backdrop for the map region.
	var sea_rect: Rect2 = Rect2(MAP_ORIGIN, Vector2(e.SEA_W * MAP_SCALE.x, e.SEA_H * MAP_SCALE.y))
	draw_rect(sea_rect, Color(0.09, 0.16, 0.24), true)
	draw_rect(sea_rect, Color(0.30, 0.45, 0.58), false, 2.0)
	# wind arrow (top-left of the map).
	var wc: Vector2 = MAP_ORIGIN + Vector2(30, 20)
	var wd: float = e.current_wind_arrow()
	draw_line(wc, wc + Vector2(cos(wd), sin(wd)) * 22.0, Color(0.7, 0.85, 0.95), 2.0)
	# ports.
	for i in e.ports.size():
		var pos: Vector2 = _map_point(e.port_pos(i))
		var col: Color = NATION_COLOR.get(String(e.ports[i]["nation"]), Color.WHITE)
		if e.port_hostile(i):
			draw_arc(pos, 10.0, 0.0, TAU, 20, Color(0.95, 0.3, 0.3), 2.0, true)
		draw_circle(pos, 6.0, col)
	# player marker.
	var ppos: Vector2 = _map_point(e.port_pos(e.location))
	draw_arc(ppos, 12.0, 0.0, TAU, 24, Color(0.95, 0.92, 0.55), 2.5, true)
