extends Control
## res://scripts/store_floor.gd
## The STORE-FLOOR screen — a minimal but real management UI, built entirely in code so
## the scene stays a bare Control + script. Shows the HUD (cash, net worth, reputation,
## day/month + season, foot traffic + in-store/catalogue income), a per-DEPARTMENT panel
## (season, staff, floor space, on-hand, today's sales/stockouts), a per-LINE catalogue
## of the SELECTED department (cost / shelf price / on-hand / age / markdown / today),
## and an ACTION panel (line picker + quantity slider to RESTOCK, markdown slider,
## hire/space +/- for the selected department, publish-catalogue, marketing, loan,
## next-day + auto-play), plus a finance readout. All rules live in GameManager.engine
## (DeptStoreEngine); this only reads state and forwards the player's chosen action.

const DEPT_COLOR: Array = [
	Color(0.85, 0.45, 0.55),  # Apparel
	Color(0.45, 0.65, 0.95),  # Electronics
	Color(0.95, 0.75, 0.35),  # Toys
	Color(0.55, 0.70, 0.75),  # Appliances
	Color(0.50, 0.82, 0.55),  # Home & Garden
	Color(0.80, 0.55, 0.40),  # Automotive
	Color(0.75, 0.55, 0.90),  # Jewelry
	Color(0.40, 0.80, 0.82),  # Sporting Goods
]

var _layer: CanvasLayer

var _cash_lbl: Label
var _worth_lbl: Label
var _rep_lbl: Label
var _time_lbl: Label
var _traffic_lbl: Label
var _catalogue_lbl: Label
var _banner: Label
var _depts_box: VBoxContainer
var _lines_box: VBoxContainer
var _readout: VBoxContainer

var _dept_option: OptionButton
var _line_option: OptionButton
var _qty_slider: HSlider
var _qty_lbl: Label
var _md_slider: HSlider
var _md_lbl: Label

var _auto: bool = false
var _auto_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine.total_on_hand() == 0 and GameManager.engine.day == 0 and GameManager.engine.cash == 0:
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
	if _auto_accum >= 0.10:
		_auto_accum = 0.0
		if GameManager.engine.outcome == DeptStoreEngine.ONGOING:
			GameManager.auto_step()
		else:
			_auto = false


# =====================================================================
#  UI construction
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_header(Vector2(24, 12), "NOX MERCANTILE — Department Store & Mail-Order Sim", 22, Color(0.96, 0.82, 0.60))

	# HUD row.
	_cash_lbl = _mk_label(Vector2(24, 46), 16, Color(0.7, 0.95, 0.7))
	_worth_lbl = _mk_label(Vector2(280, 46), 16, Color(0.95, 0.9, 0.6))
	_rep_lbl = _mk_label(Vector2(640, 46), 16, Color(0.7, 0.85, 0.95))
	_time_lbl = _mk_label(Vector2(840, 46), 16, Color(0.85, 0.85, 0.85))
	_traffic_lbl = _mk_label(Vector2(24, 72), 14, Color(0.8, 0.8, 0.85))
	_catalogue_lbl = _mk_label(Vector2(24, 92), 14, Color(0.90, 0.78, 0.95))

	# Departments panel.
	_header(Vector2(24, 120), "DEPARTMENTS  (season · staff · space · on-hand · today +sold/-out)", 13, Color(0.75, 0.75, 0.8))
	var d_scroll: ScrollContainer = ScrollContainer.new()
	d_scroll.position = Vector2(24, 142)
	d_scroll.custom_minimum_size = Vector2(700, 250)
	d_scroll.size = Vector2(700, 250)
	_layer.add_child(d_scroll)
	_depts_box = VBoxContainer.new()
	_depts_box.add_theme_constant_override("separation", 2)
	_depts_box.custom_minimum_size = Vector2(680, 0)
	d_scroll.add_child(_depts_box)

	# Product-line list (of the selected department).
	_header(Vector2(24, 404), "PRODUCT LINES  (cost · price · on-hand · age · markdown · today)", 13, Color(0.75, 0.75, 0.8))
	var l_scroll: ScrollContainer = ScrollContainer.new()
	l_scroll.position = Vector2(24, 426)
	l_scroll.custom_minimum_size = Vector2(700, 230)
	l_scroll.size = Vector2(700, 230)
	_layer.add_child(l_scroll)
	_lines_box = VBoxContainer.new()
	_lines_box.add_theme_constant_override("separation", 2)
	_lines_box.custom_minimum_size = Vector2(680, 0)
	l_scroll.add_child(_lines_box)

	# Finance readout.
	_header(Vector2(748, 120), "FINANCE & OPERATIONS", 13, Color(0.75, 0.75, 0.8))
	_readout = VBoxContainer.new()
	_readout.position = Vector2(748, 142)
	_readout.add_theme_constant_override("separation", 3)
	_readout.custom_minimum_size = Vector2(500, 0)
	_layer.add_child(_readout)

	# Action panel.
	_build_action_panel(Vector2(748, 372))

	_banner = _mk_label(Vector2(24, 690), 17, Color(0.96, 0.78, 0.30))


func _build_action_panel(pos: Vector2) -> void:
	_header(pos, "ACTIONS", 13, Color(0.75, 0.75, 0.8))

	# Department picker (drives which department the line list + staff/space act on).
	_dept_option = OptionButton.new()
	_dept_option.position = pos + Vector2(0, 24)
	_dept_option.custom_minimum_size = Vector2(200, 0)
	for d in DeptStoreEngine.DEPT_COUNT:
		_dept_option.add_item(DeptStoreEngine.DEPT_NAME[d], d)
	_dept_option.add_to_group(&"scalable_text")
	_dept_option.item_selected.connect(func(_i: int) -> void:
		_rebuild_line_options()
		_refresh())
	_layer.add_child(_dept_option)

	_action_button(pos + Vector2(210, 24), "Hire +1", func() -> void:
		GameManager.hire_staff(_dept_option.get_selected_id(), 1))
	_action_button(pos + Vector2(300, 24), "Fire -1", func() -> void:
		GameManager.hire_staff(_dept_option.get_selected_id(), -1))
	_action_button(pos + Vector2(390, 24), "Space +2", func() -> void:
		var d: int = _dept_option.get_selected_id()
		GameManager.set_dept_space(d, GameManager.engine.dept_space(d) + 2))
	_action_button(pos + Vector2(490, 24), "Space -2", func() -> void:
		var d: int = _dept_option.get_selected_id()
		GameManager.set_dept_space(d, maxi(0, GameManager.engine.dept_space(d) - 2)))

	# Product-line picker + quantity slider (restock).
	_line_option = OptionButton.new()
	_line_option.position = pos + Vector2(0, 58)
	_line_option.custom_minimum_size = Vector2(200, 0)
	_line_option.add_to_group(&"scalable_text")
	_line_option.item_selected.connect(func(_i: int) -> void: _refresh_action_labels())
	_layer.add_child(_line_option)
	_rebuild_line_options()

	_qty_lbl = _mk_label(pos + Vector2(210, 58), 13, Color(0.85, 0.85, 0.9))
	_qty_slider = HSlider.new()
	_qty_slider.position = pos + Vector2(210, 80)
	_qty_slider.custom_minimum_size = Vector2(180, 16)
	_qty_slider.min_value = 1
	_qty_slider.max_value = 40
	_qty_slider.step = 1
	_qty_slider.value = 8
	_qty_slider.value_changed.connect(func(_v: float) -> void: _refresh_action_labels())
	_layer.add_child(_qty_slider)

	_action_button(pos + Vector2(410, 58), "Restock", func() -> void:
		GameManager.restock(_line_option.get_selected_id(), int(_qty_slider.value)))
	_action_button(pos + Vector2(500, 58), "Liquidate", func() -> void:
		GameManager.liquidate(_line_option.get_selected_id(), int(_qty_slider.value)))

	# Markdown slider (of the selected line).
	_md_lbl = _mk_label(pos + Vector2(0, 104), 13, Color(0.85, 0.85, 0.9))
	_md_slider = HSlider.new()
	_md_slider.position = pos + Vector2(0, 126)
	_md_slider.custom_minimum_size = Vector2(200, 16)
	_md_slider.min_value = 0
	_md_slider.max_value = DeptStoreEngine.DEFAULTS["max_markdown_bp"]
	_md_slider.step = 500
	_md_slider.value = 0
	_md_slider.value_changed.connect(func(v: float) -> void:
		GameManager.set_markdown(_line_option.get_selected_id(), int(v)))
	_layer.add_child(_md_slider)

	_action_button(pos + Vector2(240, 104), "Publish Catalogue", func() -> void:
		GameManager.publish_catalogue())
	_action_button(pos + Vector2(400, 104), "Marketing", func() -> void:
		GameManager.run_marketing())

	_action_button(pos + Vector2(240, 138), "Loan +6000", func() -> void:
		GameManager.take_loan(6000))
	_action_button(pos + Vector2(360, 138), "Repay 6000", func() -> void:
		GameManager.repay_loan(6000))

	_action_button(pos + Vector2(0, 168), "> Next Day", func() -> void:
		GameManager.advance_day())
	var auto_btn: Button = _action_button(pos + Vector2(140, 168), ">> Auto-Play", func() -> void:
		_auto = not _auto)
	auto_btn.toggle_mode = true


func _rebuild_line_options() -> void:
	if _line_option == null:
		return
	_line_option.clear()
	var d: int = _dept_option.get_selected_id() if _dept_option != null else 0
	for i in DeptStoreEngine.LINE_COUNT:
		if DeptStoreEngine.LINE_DEPT[i] == d:
			_line_option.add_item(DeptStoreEngine.LINE_NAME[i], i)
	if _line_option.item_count > 0:
		_line_option.select(0)
	_refresh_action_labels()


func _action_button(pos: Vector2, text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.position = pos
	b.text = text
	b.add_to_group(&"scalable_text")
	b.add_to_group(&"action_button")
	b.pressed.connect(cb)
	_layer.add_child(b)
	return b


func _header(pos: Vector2, text: String, size: int, color: Color) -> void:
	var l: Label = _mk_label(pos, size, color)
	l.text = text


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	l.add_to_group(&"hud")
	_layer.add_child(l)
	return l


# =====================================================================
#  Refresh
# =====================================================================

func _refresh() -> void:
	var e: DeptStoreEngine = GameManager.engine
	_cash_lbl.text = "CASH  $%d" % e.cash
	_worth_lbl.text = "NET WORTH  $%d / $%d" % [e.net_worth(), e.win_target]
	_rep_lbl.text = "REP  %.0f/100" % e.reputation
	var month: int = e.day / DeptStoreEngine.MONTH_DAYS % 12 + 1
	var year: int = e.day / DeptStoreEngine.YEAR_DAYS + 1
	var day_of: int = e.day % DeptStoreEngine.MONTH_DAYS + 1
	_time_lbl.text = "Y%d M%d D%d  ·  season x%.2f" % [year, month, day_of, e.season_total(e.day)]
	_traffic_lbl.text = "Floor: traffic %d · sold %d ($%d) · stockouts %d · turned away %d  |  income $%d · debt $%d · staff %d/%d" % [
		e.last_traffic, e.last_instore_sales, e.last_instore_revenue, e.last_stockouts,
		e.last_turned_away, e.last_income, e.debt, e.total_staff(), e.max_staff_total]
	if e.catalogue_left > 0:
		_catalogue_lbl.text = "Catalogue ACTIVE (%d days left) · orders %d · shipped %d ($%d) · missed %d · in-transit %d" % [
			e.catalogue_left, e.last_catalogue_orders, e.last_catalogue_shipped,
			e.last_catalogue_revenue, e.last_catalogue_stockouts, e.active_shipments()]
	else:
		_catalogue_lbl.text = "Catalogue: not published (catalogue-season x%.2f) · in-transit %d" % [
			e.catalogue_season(e.day), e.active_shipments()]

	_refresh_depts()
	_refresh_lines()
	_refresh_readout()
	_refresh_action_labels()

	match e.outcome:
		DeptStoreEngine.WON:
			_banner.text = "* SUCCESS — net worth $%d cleared the $%d goal! The mercantile empire is yours." % [e.net_worth(), e.win_target]
			_banner.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
		DeptStoreEngine.LOST:
			_banner.text = "x BANKRUPT — the doors are chained. Press restart."
			_banner.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
		_:
			_banner.text = "Stock each department ahead of its season, work the catalogue, clear the leftovers."
			_banner.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))


func _refresh_depts() -> void:
	var e: DeptStoreEngine = GameManager.engine
	_clear(_depts_box)
	for d in DeptStoreEngine.DEPT_COUNT:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_cell("%s" % DeptStoreEngine.DEPT_NAME[d], 150, DEPT_COLOR[d]))
		row.add_child(_cell("sea %.2f" % e.season_mult(d, e.day), 80,
			Color(0.95, 0.7, 0.4) if e.season_mult(d, e.day) > 1.3 else Color(0.7, 0.75, 0.7)))
		row.add_child(_cell("staff %d" % e.dept_staff(d), 80, Color(0.8, 0.82, 0.85)))
		row.add_child(_cell("space %d" % e.dept_space(d), 80, Color(0.8, 0.82, 0.85)))
		row.add_child(_cell("stock %d" % e.dept_on_hand(d), 90, Color(0.8, 0.82, 0.85)))
		row.add_child(_cell("+%d" % e.dept_day_sales(d), 60, Color(0.6, 0.9, 0.6)))
		_depts_box.add_child(row)


func _refresh_lines() -> void:
	var e: DeptStoreEngine = GameManager.engine
	_clear(_lines_box)
	var d: int = _dept_option.get_selected_id() if _dept_option != null else 0
	for i in DeptStoreEngine.LINE_COUNT:
		if DeptStoreEngine.LINE_DEPT[i] != d:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_cell(DeptStoreEngine.LINE_NAME[i], 150, DEPT_COLOR[d]))
		row.add_child(_cell("$%d>$%d" % [DeptStoreEngine.LINE_COST[i], e.effective_price(i)], 110, Color(0.8, 0.82, 0.85)))
		row.add_child(_cell("on %d" % e.line_on_hand(i), 70, Color(0.8, 0.82, 0.85)))
		row.add_child(_cell("age %.0f" % e.line_age(i), 70,
			Color(0.95, 0.6, 0.5) if e.line_age(i) > 40.0 else Color(0.7, 0.75, 0.7)))
		var md: int = e.line_markdown_bp(i)
		row.add_child(_cell(("-%d%%" % (md / 100)) if md > 0 else "--", 70,
			Color(0.95, 0.75, 0.4) if md > 0 else Color(0.55, 0.55, 0.6)))
		row.add_child(_cell("+%d -%d" % [e.line_day_sales(i), e.line_day_stockouts(i)], 90,
			Color(0.6, 0.9, 0.6) if e.line_day_stockouts(i) == 0 else Color(0.95, 0.6, 0.5)))
		_lines_box.add_child(row)


func _cell(text: String, width: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


func _refresh_readout() -> void:
	var e: DeptStoreEngine = GameManager.engine
	_clear(_readout)
	_readout.add_child(_row("REVENUE", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  in-store sales (total)   $%d" % e.category_total("instore_revenue"), Color(0.7, 0.9, 0.7)))
	_readout.add_child(_row("  catalogue sales (total)  $%d" % e.category_total("catalogue_revenue"), Color(0.7, 0.9, 0.7)))
	_readout.add_child(_row("  liquidation (total)      $%d" % e.category_total("liquidation"), Color(0.7, 0.9, 0.7)))
	_readout.add_child(_row("COSTS", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  restock purchases  -$%d" % (-e.category_total("restock")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  overhead           -$%d" % (-e.category_total("overhead")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  staff wages        -$%d" % (-e.category_total("wages")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  catalogue print    -$%d" % (-e.category_total("catalogue_print")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  catalogue fulfill  -$%d" % (-e.category_total("catalogue_fulfill")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  marketing          -$%d" % (-e.category_total("marketing")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  loan interest      -$%d" % (-e.category_total("interest")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("STORE", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  on-hand %d · in-transit %d · fill rate %.0f%%" % [
		e.total_on_hand(), e.total_in_transit(), e.fill_rate() * 100.0], Color(0.8, 0.8, 0.85)))
	_readout.add_child(_row("  catalogues published %d · floor %d/%d" % [
		e.catalogues_published, e.total_space(), e.floor_total], Color(0.8, 0.8, 0.85)))
	if e.marketing_left > 0:
		_readout.add_child(_row("  * MARKETING active (%d days left)" % e.marketing_left, Color(0.95, 0.7, 0.85)))


func _refresh_action_labels() -> void:
	if _qty_lbl != null and _qty_slider != null and _line_option != null:
		var i: int = _line_option.get_selected_id()
		if i >= 0 and i < DeptStoreEngine.LINE_COUNT:
			var each: int = DeptStoreEngine.LINE_COST[i]
			_qty_lbl.text = "Restock qty %d  ($%d each = $%d)" % [int(_qty_slider.value), each, int(_qty_slider.value) * each]
	if _md_lbl != null and _md_slider != null and _line_option != null:
		var i2: int = _line_option.get_selected_id()
		if i2 >= 0 and i2 < DeptStoreEngine.LINE_COUNT:
			_md_lbl.text = "Markdown %d%%  (price now $%d)" % [int(_md_slider.value) / 100, GameManager.engine.effective_price(i2)]


func _row(text: String, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
