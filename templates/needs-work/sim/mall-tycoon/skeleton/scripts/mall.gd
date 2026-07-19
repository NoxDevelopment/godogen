extends Control
## res://scripts/mall.gd
## The MALL screen — a minimal but real management UI, built entirely in code so
## the scene stays a bare Control + script. Shows the mall GRID (units coloured by
## state / store type across floors), a HUD (cash, net worth, reputation, day /
## month, daily foot traffic + income), an ACTION panel (lease / operate / amenity
## / rent / marketing / loan / evict / next day / auto-play), and a tenant +
## finance readout. All rules live in GameManager.engine (MallEngine); this only
## reads state and forwards the player's chosen action.

# Colours by unit state / store type (80s-mall palette blockout).
const EMPTY_COLOR := Color(0.16, 0.16, 0.20)
const STORE_COLOR := [
	Color(0.85, 0.35, 0.45),  # Record Store
	Color(0.35, 0.55, 0.90),  # Arcade
	Color(0.55, 0.45, 0.80),  # Video Rental
	Color(0.95, 0.70, 0.30),  # Food Court
	Color(0.90, 0.85, 0.35),  # Department Store (anchor)
	Color(0.40, 0.80, 0.55),  # Toy Store
	Color(0.30, 0.75, 0.80),  # Electronics
	Color(0.80, 0.50, 0.70),  # Apparel
	Color(0.60, 0.70, 0.45),  # Bookstore
]

var _layer: CanvasLayer
var _grid_root: Control
var _cells: Array[Panel] = []
var _cell_labels: Array[Label] = []

var _cash_lbl: Label
var _worth_lbl: Label
var _rep_lbl: Label
var _time_lbl: Label
var _traffic_lbl: Label
var _banner: Label
var _readout: VBoxContainer
var _store_option: OptionButton
var _amenity_option: OptionButton

var _selected: int = 0
var _auto := false
var _auto_accum := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine.unit_count() == 0:
		GameManager.new_game(GameManager.DEFAULT_SEED)
	_build_ui()
	GameManager.changed.connect(_refresh)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		_auto = false
		GameManager.new_game(GameManager.DEFAULT_SEED)


func _process(delta: float) -> void:
	if not _auto:
		return
	_auto_accum += delta
	if _auto_accum >= 0.15:
		_auto_accum = 0.0
		if GameManager.engine.outcome == MallEngine.ONGOING:
			GameManager.auto_step()
		else:
			_auto = false


# =====================================================================
#  UI construction
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_header(Vector2(24, 16), "NEON PLAZA — Mall Tycoon", 24, Color(0.96, 0.72, 0.85))

	# HUD row.
	_cash_lbl = _mk_label(Vector2(24, 52), 16, Color(0.7, 0.95, 0.7))
	_worth_lbl = _mk_label(Vector2(300, 52), 16, Color(0.95, 0.9, 0.6))
	_rep_lbl = _mk_label(Vector2(600, 52), 16, Color(0.7, 0.85, 0.95))
	_time_lbl = _mk_label(Vector2(860, 52), 16, Color(0.85, 0.85, 0.85))
	_traffic_lbl = _mk_label(Vector2(24, 78), 15, Color(0.8, 0.8, 0.85))

	# Mall grid.
	_header(Vector2(24, 110), "MALL FLOOR PLAN  (click a unit)", 14, Color(0.75, 0.75, 0.8))
	_grid_root = Control.new()
	_grid_root.position = Vector2(24, 134)
	_layer.add_child(_grid_root)
	_build_grid()

	# Action panel.
	_build_action_panel(Vector2(24, 470))

	# Tenant / finance readout.
	_header(Vector2(760, 110), "TENANTS & FINANCE", 14, Color(0.75, 0.75, 0.8))
	_readout = VBoxContainer.new()
	_readout.position = Vector2(760, 134)
	_readout.add_theme_constant_override("separation", 3)
	_readout.custom_minimum_size = Vector2(490, 0)
	_layer.add_child(_readout)

	_banner = _mk_label(Vector2(24, 688), 18, Color(0.96, 0.78, 0.30))


func _build_grid() -> void:
	var e := GameManager.engine
	var cell := Vector2(112, 48)
	var pad := Vector2(8, 8)
	_cells.clear()
	_cell_labels.clear()
	for i in e.unit_count():
		var f := i / e.cols
		var c := i % e.cols
		var p := Panel.new()
		p.position = Vector2(c * (cell.x + pad.x), f * (cell.y + pad.y))
		p.custom_minimum_size = cell
		p.size = cell
		p.add_to_group(&"unit_cell")
		p.gui_input.connect(_on_cell_input.bind(i))
		_grid_root.add_child(p)
		_cells.append(p)

		var lbl := Label.new()
		lbl.position = Vector2(4, 2)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_to_group(&"scalable_text")
		p.add_child(lbl)
		_cell_labels.append(lbl)


func _build_action_panel(pos: Vector2) -> void:
	var e := GameManager.engine
	_header(pos, "ACTIONS  (selected unit shown in the readout)", 14, Color(0.75, 0.75, 0.8))

	# Store type picker.
	_store_option = OptionButton.new()
	_store_option.position = pos + Vector2(0, 26)
	for s in MallEngine.STORE_COUNT:
		_store_option.add_item("%s ($%d rent)" % [MallEngine.STORE_NAME[s], MallEngine.STORE_RENT[s]], s)
	_store_option.add_to_group(&"scalable_text")
	_layer.add_child(_store_option)

	_action_button(pos + Vector2(300, 26), "Lease", func() -> void:
		GameManager.lease(_selected, _store_option.get_selected_id()))
	_action_button(pos + Vector2(400, 26), "Operate", func() -> void:
		GameManager.operate(_selected, _store_option.get_selected_id()))
	_action_button(pos + Vector2(510, 26), "Evict", func() -> void:
		GameManager.evict(_selected))

	# Amenity picker.
	_amenity_option = OptionButton.new()
	_amenity_option.position = pos + Vector2(0, 66)
	for a in MallEngine.AMENITY_COUNT:
		_amenity_option.add_item("%s ($%d)" % [MallEngine.AMENITY_NAME[a], MallEngine.AMENITY_COST[a]], a)
	_amenity_option.add_to_group(&"scalable_text")
	_layer.add_child(_amenity_option)

	_action_button(pos + Vector2(300, 66), "Add Amenity", func() -> void:
		GameManager.add_amenity(_amenity_option.get_selected_id()))
	_action_button(pos + Vector2(440, 66), "Restock 40", func() -> void:
		GameManager.buy_stock(_selected, 40))
	_action_button(pos + Vector2(560, 66), "Hire +1", func() -> void:
		GameManager.hire_staff(_selected, 1))

	_action_button(pos + Vector2(0, 106), "Marketing", func() -> void:
		GameManager.run_marketing())
	_action_button(pos + Vector2(120, 106), "Loan +5000", func() -> void:
		GameManager.take_loan(5000))
	_action_button(pos + Vector2(260, 106), "Repay 5000", func() -> void:
		GameManager.repay_loan(5000))
	_action_button(pos + Vector2(390, 106), "Rent -100", func() -> void:
		GameManager.set_rent(_selected, maxi(0, e.unit_rent(_selected) - 100)))
	_action_button(pos + Vector2(500, 106), "Rent +100", func() -> void:
		GameManager.set_rent(_selected, e.unit_rent(_selected) + 100))

	_action_button(pos + Vector2(0, 146), "▶ Next Day", func() -> void:
		GameManager.advance_day())
	var auto_btn := _action_button(pos + Vector2(140, 146), "⏩ Auto-Play", func() -> void:
		_auto = not _auto)
	auto_btn.toggle_mode = true


func _action_button(pos: Vector2, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.position = pos
	b.text = text
	b.add_to_group(&"scalable_text")
	b.add_to_group(&"action_button")
	b.pressed.connect(cb)
	_layer.add_child(b)
	return b


func _header(pos: Vector2, text: String, size: int, color: Color) -> void:
	var l := _mk_label(pos, size, color)
	l.text = text


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	l.add_to_group(&"hud")
	_layer.add_child(l)
	return l


# =====================================================================
#  Interaction
# =====================================================================

func _on_cell_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = index
		_refresh()


# =====================================================================
#  Refresh
# =====================================================================

func _refresh() -> void:
	var e := GameManager.engine
	_cash_lbl.text = "CASH  $%d" % e.cash
	_worth_lbl.text = "NET WORTH  $%d / $%d" % [e.net_worth(), e.win_target]
	_rep_lbl.text = "REP  %.0f/100" % e.reputation
	var month := e.day / 30 + 1
	var day_of := e.day % 30 + 1
	_time_lbl.text = "MONTH %d  DAY %d" % [month, day_of]
	_traffic_lbl.text = "Foot traffic today: %d    ·    Daily income: $%d    ·    Debt: $%d    ·    Occupancy: %.0f%%" % [
		e.last_traffic, e.last_income, e.debt, e.occupancy_rate() * 100.0]

	_refresh_grid()
	_refresh_readout()

	match e.outcome:
		MallEngine.WON:
			_banner.text = "★ SUCCESS — net worth $%d reached the $%d goal! The plaza is yours." % [e.net_worth(), e.win_target]
			_banner.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
		MallEngine.LOST:
			_banner.text = "✖ BANKRUPT — the mall went under. Press restart to try again."
			_banner.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
		_:
			_banner.text = "Lease units, add amenities, keep the crowd happy. Selected unit: #%d" % _selected
			_banner.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))


func _refresh_grid() -> void:
	var e := GameManager.engine
	for i in e.unit_count():
		var p := _cells[i]
		var lbl := _cell_labels[i]
		var sb := StyleBoxFlat.new()
		var col := EMPTY_COLOR
		var text := "empty\n%.0f%%" % (e.unit_desir(i) * 100.0)
		if e.unit_state(i) != MallEngine.U_EMPTY:
			col = STORE_COLOR[e.unit_store(i)]
			var kind := "lease" if e.unit_state(i) == MallEngine.U_LEASED else "OWN"
			text = "%s\n%s" % [MallEngine.STORE_NAME[e.unit_store(i)], kind]
		sb.bg_color = col.darkened(0.15)
		sb.set_border_width_all(3 if i == _selected else 1)
		sb.border_color = Color(1, 1, 1, 0.9) if i == _selected else Color(0, 0, 0, 0.4)
		sb.set_corner_radius_all(4)
		p.add_theme_stylebox_override("panel", sb)
		lbl.text = text
		lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08) if e.unit_state(i) != MallEngine.U_EMPTY else Color(0.6, 0.6, 0.65))


func _refresh_readout() -> void:
	var e := GameManager.engine
	_clear(_readout)
	# Selected unit detail.
	var i := _selected
	var head := "UNIT #%d  ·  desirability %.0f%%" % [i, e.unit_desir(i) * 100.0]
	_readout.add_child(_row(head, Color(0.95, 0.9, 0.6)))
	match e.unit_state(i):
		MallEngine.U_EMPTY:
			_readout.add_child(_row("  vacant — Lease or Operate to fill it", Color(0.7, 0.7, 0.72)))
		MallEngine.U_LEASED:
			_readout.add_child(_row("  LEASED: %s  ·  rent $%d/mo" % [MallEngine.STORE_NAME[e.unit_store(i)], e.unit_rent(i)], Color(0.8, 0.85, 0.7)))
			_readout.add_child(_row("  tenant satisfaction %.0f/100  ·  today's sales $%d" % [e.unit_satisfaction(i), e.unit_day_revenue(i)], Color(0.75, 0.8, 0.7)))
		MallEngine.U_OWNER:
			_readout.add_child(_row("  OWNER: %s  ·  stock %d  ·  staff %d" % [MallEngine.STORE_NAME[e.unit_store(i)], e.unit_stock(i), e.unit_staff(i)], Color(0.7, 0.85, 0.85)))
			_readout.add_child(_row("  today's revenue $%d" % e.unit_day_revenue(i), Color(0.7, 0.85, 0.85)))

	_readout.add_child(_row(" ", Color.WHITE))
	_readout.add_child(_row("FINANCE", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  rent income (total)   $%d" % e.category_total("rent_income"), Color(0.7, 0.9, 0.7)))
	_readout.add_child(_row("  store revenue (total) $%d" % e.category_total("store_revenue"), Color(0.7, 0.9, 0.7)))
	_readout.add_child(_row("  maintenance           -$%d" % (-e.category_total("maintenance")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  staff wages           -$%d" % (-e.category_total("wages")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  amenity upkeep        -$%d" % (-e.category_total("amenity_upkeep")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  loan interest         -$%d" % (-e.category_total("interest")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row(" ", Color.WHITE))
	_readout.add_child(_row("MALL", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  occupancy %d/%d  ·  variety %d  ·  anchors %d" % [e.occupied_count(), e.unit_count(), e.store_variety(), e.anchor_count()], Color(0.8, 0.8, 0.85)))
	var amen := ""
	for a in MallEngine.AMENITY_COUNT:
		if e.amenity_owned(a):
			amen += MallEngine.AMENITY_NAME[a] + " "
	_readout.add_child(_row("  amenities: %s" % (amen if amen != "" else "(none)"), Color(0.8, 0.8, 0.85)))
	if e.marketing_left > 0:
		_readout.add_child(_row("  ★ MARKETING active (%d days left)" % e.marketing_left, Color(0.95, 0.7, 0.85)))


func _row(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
