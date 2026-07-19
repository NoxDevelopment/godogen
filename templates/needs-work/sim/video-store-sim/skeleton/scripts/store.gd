extends Control
## res://scripts/store.gd
## The STORE screen — a minimal but real management UI, built entirely in code so the
## scene stays a bare Control + script. Shows the HUD (cash, net worth, reputation,
## members, day/month, foot traffic + income), the CATALOG (each VHS title with its
## genre, current demand + new-release flag, copies owned / on-shelf / out, and
## today's rentals vs misses), an ACTION panel (title picker + a quantity slider to
## BUY COPIES, marketing / hire / fire / loan / late-fee actions, next-day +
## auto-play), and a finance readout. All rules live in GameManager.engine
## (VideoStoreEngine); this only reads state and forwards the player's chosen action.

const GENRE_COLOR: Array = [
	Color(0.85, 0.35, 0.40),  # Action
	Color(0.95, 0.80, 0.35),  # Comedy
	Color(0.55, 0.40, 0.80),  # Horror
	Color(0.45, 0.65, 0.90),  # Drama
	Color(0.45, 0.82, 0.55),  # Family
	Color(0.35, 0.78, 0.82),  # SciFi
]

var _layer: CanvasLayer

var _cash_lbl: Label
var _worth_lbl: Label
var _rep_lbl: Label
var _member_lbl: Label
var _time_lbl: Label
var _traffic_lbl: Label
var _banner: Label
var _catalog: VBoxContainer
var _readout: VBoxContainer

var _title_option: OptionButton
var _qty_slider: HSlider
var _qty_lbl: Label
var _fee_slider: HSlider
var _fee_lbl: Label

var _auto: bool = false
var _auto_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine.total_copies_owned() == 0 and GameManager.engine.day == 0 and GameManager.engine.cash == 0:
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
	if _auto_accum >= 0.12:
		_auto_accum = 0.0
		if GameManager.engine.outcome == VideoStoreEngine.ONGOING:
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
	bg.color = Color(0.06, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_header(Vector2(24, 14), "NEON VIDEO — VHS Rental Sim", 24, Color(0.96, 0.70, 0.86))

	# HUD row.
	_cash_lbl = _mk_label(Vector2(24, 50), 16, Color(0.7, 0.95, 0.7))
	_worth_lbl = _mk_label(Vector2(280, 50), 16, Color(0.95, 0.9, 0.6))
	_rep_lbl = _mk_label(Vector2(620, 50), 16, Color(0.7, 0.85, 0.95))
	_member_lbl = _mk_label(Vector2(820, 50), 16, Color(0.95, 0.75, 0.85))
	_time_lbl = _mk_label(Vector2(1010, 50), 16, Color(0.85, 0.85, 0.85))
	_traffic_lbl = _mk_label(Vector2(24, 76), 15, Color(0.8, 0.8, 0.85))

	# Catalog list.
	_header(Vector2(24, 108), "CATALOG  (title · genre · demand · copies · today)", 14, Color(0.75, 0.75, 0.8))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(24, 132)
	scroll.custom_minimum_size = Vector2(700, 480)
	scroll.size = Vector2(700, 480)
	_layer.add_child(scroll)
	_catalog = VBoxContainer.new()
	_catalog.add_theme_constant_override("separation", 2)
	_catalog.custom_minimum_size = Vector2(680, 0)
	scroll.add_child(_catalog)

	# Finance readout.
	_header(Vector2(756, 108), "FINANCE & OPERATIONS", 14, Color(0.75, 0.75, 0.8))
	_readout = VBoxContainer.new()
	_readout.position = Vector2(756, 132)
	_readout.add_theme_constant_override("separation", 3)
	_readout.custom_minimum_size = Vector2(500, 0)
	_layer.add_child(_readout)

	# Action panel.
	_build_action_panel(Vector2(756, 330))

	_banner = _mk_label(Vector2(24, 690), 18, Color(0.96, 0.78, 0.30))


func _build_action_panel(pos: Vector2) -> void:
	_header(pos, "ACTIONS", 14, Color(0.75, 0.75, 0.8))

	# Title picker.
	_title_option = OptionButton.new()
	_title_option.position = pos + Vector2(0, 26)
	_title_option.custom_minimum_size = Vector2(300, 0)
	for t in VideoStoreEngine.TITLE_COUNT:
		_title_option.add_item("%s [%s]" % [
			VideoStoreEngine.TITLE_NAME[t],
			VideoStoreEngine.GENRE_NAME[VideoStoreEngine.TITLE_GENRE[t]]], t)
	_title_option.add_to_group(&"scalable_text")
	_layer.add_child(_title_option)

	# Quantity slider.
	_qty_lbl = _mk_label(pos + Vector2(320, 26), 14, Color(0.85, 0.85, 0.9))
	_qty_slider = HSlider.new()
	_qty_slider.position = pos + Vector2(320, 50)
	_qty_slider.custom_minimum_size = Vector2(160, 16)
	_qty_slider.min_value = 1
	_qty_slider.max_value = 20
	_qty_slider.step = 1
	_qty_slider.value = 5
	_qty_slider.value_changed.connect(func(_v: float) -> void: _refresh_action_labels())
	_layer.add_child(_qty_slider)

	_action_button(pos + Vector2(0, 62), "Buy Copies", func() -> void:
		GameManager.buy_copies(_title_option.get_selected_id(), int(_qty_slider.value)))

	# Late-fee policy slider.
	_fee_lbl = _mk_label(pos + Vector2(0, 96), 14, Color(0.85, 0.85, 0.9))
	_fee_slider = HSlider.new()
	_fee_slider.position = pos + Vector2(0, 120)
	_fee_slider.custom_minimum_size = Vector2(200, 16)
	_fee_slider.min_value = 0
	_fee_slider.max_value = VideoStoreEngine.DEFAULTS["max_late_fee"]
	_fee_slider.step = 1
	_fee_slider.value = GameManager.engine.late_fee_per_day
	_fee_slider.value_changed.connect(func(v: float) -> void: GameManager.set_late_fee(int(v)))
	_layer.add_child(_fee_slider)

	_action_button(pos + Vector2(240, 96), "Marketing", func() -> void:
		GameManager.run_marketing())
	_action_button(pos + Vector2(360, 96), "Hire +1", func() -> void:
		GameManager.hire_staff(1))
	_action_button(pos + Vector2(450, 96), "Fire -1", func() -> void:
		GameManager.hire_staff(-1))

	_action_button(pos + Vector2(240, 130), "Loan +2000", func() -> void:
		GameManager.take_loan(2000))
	_action_button(pos + Vector2(370, 130), "Repay 2000", func() -> void:
		GameManager.repay_loan(2000))

	_action_button(pos + Vector2(0, 166), "> Next Day", func() -> void:
		GameManager.advance_day())
	var auto_btn: Button = _action_button(pos + Vector2(140, 166), ">> Auto-Play", func() -> void:
		_auto = not _auto)
	auto_btn.toggle_mode = true


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
	var e: VideoStoreEngine = GameManager.engine
	_cash_lbl.text = "CASH  $%d" % e.cash
	_worth_lbl.text = "NET WORTH  $%d / $%d" % [e.net_worth(), e.win_target]
	_rep_lbl.text = "REP  %.0f/100" % e.reputation
	_member_lbl.text = "MEMBERS  %d" % e.members
	var month: int = e.day / 30 + 1
	var day_of: int = e.day % 30 + 1
	_time_lbl.text = "M%d D%d" % [month, day_of]
	_traffic_lbl.text = "Traffic %d  ·  served %d  ·  rentals %d  ·  missed %d  ·  turned away %d  ·  income $%d  ·  debt $%d  ·  staff %d" % [
		e.last_traffic, e.last_served, e.last_rentals, e.last_missed, e.last_turned_away, e.last_income, e.debt, e.staff]

	_refresh_catalog()
	_refresh_readout()
	_refresh_action_labels()

	match e.outcome:
		VideoStoreEngine.WON:
			_banner.text = "* SUCCESS — net worth $%d cleared the $%d goal! The neon empire is yours." % [e.net_worth(), e.win_target]
			_banner.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
		VideoStoreEngine.LOST:
			_banner.text = "x BANKRUPT — be kind, rewind. The store went under. Press restart."
			_banner.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
		_:
			_banner.text = "Stock the hot new releases, keep the shelves full, grow your members."
			_banner.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))


func _refresh_catalog() -> void:
	var e: VideoStoreEngine = GameManager.engine
	_clear(_catalog)
	for t in VideoStoreEngine.TITLE_COUNT:
		var released: bool = e.is_released(t, e.day)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var g: int = VideoStoreEngine.TITLE_GENRE[t]
		var name_lbl: Label = _cat_cell("%s" % VideoStoreEngine.TITLE_NAME[t], 200, GENRE_COLOR[g])
		row.add_child(name_lbl)
		if not released:
			row.add_child(_cat_cell("(releases day %d)" % VideoStoreEngine.TITLE_RELEASE[t], 240, Color(0.5, 0.5, 0.55)))
		else:
			var tag: String = "NEW!" if e.is_new_release(t, e.day) else "cat"
			row.add_child(_cat_cell("%s  dmd %.1f" % [tag, e.demand(t, e.day)], 130,
				Color(0.95, 0.7, 0.4) if e.is_new_release(t, e.day) else Color(0.7, 0.75, 0.7)))
			row.add_child(_cat_cell("own %d  shelf %d  out %d" % [e.title_owned(t), e.title_available(t), e.title_rented_out(t)], 200, Color(0.8, 0.82, 0.85)))
			row.add_child(_cat_cell("+%d  -%d" % [e.title_day_rentals(t), e.title_day_misses(t)],
				110, Color(0.6, 0.9, 0.6) if e.title_day_misses(t) == 0 else Color(0.95, 0.6, 0.5)))
		_catalog.add_child(row)


func _cat_cell(text: String, width: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


func _refresh_readout() -> void:
	var e: VideoStoreEngine = GameManager.engine
	_clear(_readout)
	_readout.add_child(_row("REVENUE", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  rental income (total)  $%d" % e.category_total("rental_income"), Color(0.7, 0.9, 0.7)))
	_readout.add_child(_row("  late fees (total)       $%d" % e.category_total("late_fees"), Color(0.7, 0.9, 0.7)))
	_readout.add_child(_row("COSTS", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  tape purchases  -$%d" % (-e.category_total("tape_purchase")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  storefront rent -$%d" % (-e.category_total("rent")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  staff wages     -$%d" % (-e.category_total("wages")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("  loan interest   -$%d" % (-e.category_total("interest")), Color(0.9, 0.7, 0.7)))
	_readout.add_child(_row("STORE", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  titles owned %d/%d  ·  copies %d  ·  on shelf %d" % [
		e.selection_breadth(), VideoStoreEngine.TITLE_COUNT, e.total_copies_owned(), e.total_copies_available()], Color(0.8, 0.8, 0.85)))
	_readout.add_child(_row("  active rentals %d  ·  returns today %d (late %d, damaged %d)" % [
		e.active_rentals(), e.last_returns, e.last_late, e.last_damaged], Color(0.8, 0.8, 0.85)))
	_readout.add_child(_row("  late fee policy $%d/day  ·  fill rate %.0f%%" % [
		e.late_fee_per_day, e.fill_rate() * 100.0], Color(0.8, 0.8, 0.85)))
	if e.marketing_left > 0:
		_readout.add_child(_row("  * MARKETING active (%d days left)" % e.marketing_left, Color(0.95, 0.7, 0.85)))


func _refresh_action_labels() -> void:
	if _qty_lbl != null and _qty_slider != null:
		var t: int = _title_option.get_selected_id() if _title_option != null else 0
		var each: int = VideoStoreEngine.TITLE_COST[t]
		_qty_lbl.text = "Buy qty %d  ($%d each = $%d)" % [int(_qty_slider.value), each, int(_qty_slider.value) * each]
	if _fee_lbl != null and _fee_slider != null:
		_fee_lbl.text = "Late fee policy: $%d / day overdue" % int(_fee_slider.value)


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
