extends Control
## res://scripts/farm.gd
## The FARM-OFFICE screen — a minimal but real farm-operation management UI, built entirely
## in code so the scene stays a bare Control + script. The root Control _draw()s the 3x3
## FIELD GRID (each cell coloured by its crop with a nitrogen-shaded soil tint, an
## irrigation border, and a maturity ring), while a CanvasLayer on top holds the HUD
## (cash / net worth / day-season-year / weather / work capacity), a MARKET panel
## (per-commodity price + your stock), a LIVESTOCK + MACHINERY readout, and an ACTION panel
## (field / crop / animal / commodity pickers, a quantity slider, and buttons to plant /
## harvest / fertilize / toggle irrigation / buy+sell livestock / buy feed / sell commodity
## / buy machinery / loan / advance-day + auto-play), plus a finance readout. All rules
## live in GameManager.engine (FarmEngine); this only reads state and forwards actions.

const CROP_COLOR: Array = [
	Color(0.93, 0.80, 0.28),  # Corn — gold
	Color(0.82, 0.72, 0.42),  # Wheat — wheat
	Color(0.45, 0.72, 0.40),  # Soybeans — green
	Color(0.92, 0.92, 0.86),  # Cotton — white
	Color(0.60, 0.78, 0.35),  # Hay — light green
	Color(0.85, 0.45, 0.45),  # Vegetables — red
]
const FALLOW_COLOR: Color = Color(0.36, 0.28, 0.20)   # bare turned soil.
const WEATHER_COLOR: Array = [
	Color(0.85, 0.85, 0.80),  # Clear
	Color(0.55, 0.70, 0.95),  # Rain
	Color(0.90, 0.65, 0.35),  # Drought
	Color(0.70, 0.85, 0.98),  # Frost
	Color(0.95, 0.55, 0.35),  # Heat
	Color(0.70, 0.55, 0.35),  # Pests
]

const GRID_ORIGIN: Vector2 = Vector2(28, 150)
const CELL_SIZE: Vector2 = Vector2(150, 118)
const CELL_GAP: float = 10.0

var _layer: CanvasLayer

var _cash_lbl: Label
var _worth_lbl: Label
var _time_lbl: Label
var _weather_lbl: Label
var _work_lbl: Label
var _banner: Label
var _market_box: VBoxContainer
var _readout: VBoxContainer

var _field_option: OptionButton
var _crop_option: OptionButton
var _animal_option: OptionButton
var _commodity_option: OptionButton
var _qty_slider: HSlider
var _qty_lbl: Label
var _field_lbl: Label

var _auto: bool = false
var _auto_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if GameManager.engine.day == 0 and GameManager.engine.cash == 0 and GameManager.engine.total_harvests == 0:
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
	if _auto_accum >= 0.08:
		_auto_accum = 0.0
		if GameManager.engine.outcome == FarmEngine.ONGOING:
			GameManager.auto_step()
		else:
			_auto = false


# =====================================================================
#  Field grid — drawn on the root Control (behind the CanvasLayer UI)
# =====================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.12, 0.09))
	var e: FarmEngine = GameManager.engine
	var font: Font = ThemeDB.fallback_font
	for f in FarmEngine.FIELD_COUNT:
		var col: int = f % FarmEngine.FIELD_COLS
		var row: int = f / FarmEngine.FIELD_COLS
		var pos: Vector2 = GRID_ORIGIN + Vector2(
			float(col) * (CELL_SIZE.x + CELL_GAP),
			float(row) * (CELL_SIZE.y + CELL_GAP))
		var crop: int = e.field_crop(f)
		# Base soil tint shaded by nitrogen (greener = richer, browner = depleted).
		var nfrac: float = clampf(e.field_nitrogen(f) / FarmEngine.NITROGEN_OPTIMAL, 0.0, 1.0)
		var base: Color = FALLOW_COLOR.lerp(Color(0.30, 0.45, 0.24), nfrac)
		draw_rect(Rect2(pos, CELL_SIZE), base)
		if crop >= 0:
			# A crop patch whose height tracks growth progress.
			var prog: float = e.field_progress(f)
			var patch_h: float = (CELL_SIZE.y - 30.0) * clampf(prog, 0.15, 1.0)
			var patch_pos: Vector2 = pos + Vector2(8, CELL_SIZE.y - 8 - patch_h)
			var patch_size: Vector2 = Vector2(CELL_SIZE.x - 16, patch_h)
			draw_rect(Rect2(patch_pos, patch_size), CROP_COLOR[crop])
		# Irrigation border.
		if e.field_irrigated(f):
			draw_rect(Rect2(pos, CELL_SIZE), Color(0.45, 0.70, 0.95), false, 3.0)
		else:
			draw_rect(Rect2(pos, CELL_SIZE), Color(0.05, 0.06, 0.05), false, 2.0)
		# Maturity ring.
		if e.field_is_mature(f):
			draw_circle(pos + Vector2(CELL_SIZE.x - 16, 16), 7.0, Color(0.55, 0.95, 0.55))
		# Field label + crop/nitrogen text.
		var label: String = "F%d" % f
		if crop >= 0:
			label += " %s" % FarmEngine.CROP_NAME[crop]
		draw_string(font, pos + Vector2(8, 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.92, 0.92, 0.88))
		draw_string(font, pos + Vector2(8, 34), "N %.0f" % e.field_nitrogen(f),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.80, 0.86, 0.70))
		if crop >= 0:
			draw_string(font, pos + Vector2(8, CELL_SIZE.y - 6),
				"~%d u" % e.projected_yield(f), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(0.95, 0.90, 0.70))


# =====================================================================
#  UI construction
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	_header(Vector2(28, 12), "NOX ACRES — Farm Operation & Commodity Sim", 22, Color(0.85, 0.92, 0.55))

	# HUD row.
	_cash_lbl = _mk_label(Vector2(28, 46), 16, Color(0.7, 0.95, 0.7))
	_worth_lbl = _mk_label(Vector2(300, 46), 16, Color(0.95, 0.9, 0.6))
	_time_lbl = _mk_label(Vector2(720, 46), 15, Color(0.85, 0.85, 0.85))
	_weather_lbl = _mk_label(Vector2(28, 72), 15, Color(0.8, 0.85, 0.95))
	_work_lbl = _mk_label(Vector2(360, 72), 14, Color(0.82, 0.82, 0.7))
	_header(Vector2(28, 122), "FIELDS  (crop · nitrogen · projected yield)", 13, Color(0.75, 0.8, 0.72))

	# Market panel (top-right).
	_header(Vector2(700, 122), "COMMODITY MARKET  (price · your stock)", 13, Color(0.75, 0.8, 0.72))
	_market_box = VBoxContainer.new()
	_market_box.position = Vector2(700, 144)
	_market_box.add_theme_constant_override("separation", 2)
	_market_box.custom_minimum_size = Vector2(540, 0)
	_layer.add_child(_market_box)

	# Livestock + machinery + finance readout (mid-right).
	_header(Vector2(700, 320), "HERDS · MACHINERY · FINANCE", 13, Color(0.75, 0.8, 0.72))
	_readout = VBoxContainer.new()
	_readout.position = Vector2(700, 342)
	_readout.add_theme_constant_override("separation", 3)
	_readout.custom_minimum_size = Vector2(540, 0)
	_layer.add_child(_readout)

	_build_action_panel(Vector2(28, 566))

	_banner = _mk_label(Vector2(28, 694), 16, Color(0.9, 0.85, 0.4))


func _build_action_panel(pos: Vector2) -> void:
	_header(pos, "ACTIONS", 13, Color(0.75, 0.8, 0.72))

	# Field picker (drives field-scoped actions) + crop picker (for planting).
	_field_option = OptionButton.new()
	_field_option.position = pos + Vector2(0, 22)
	_field_option.custom_minimum_size = Vector2(110, 0)
	for f in FarmEngine.FIELD_COUNT:
		_field_option.add_item("Field %d" % f, f)
	_field_option.add_to_group(&"scalable_text")
	_field_option.item_selected.connect(func(_i: int) -> void: _refresh())
	_layer.add_child(_field_option)

	_crop_option = OptionButton.new()
	_crop_option.position = pos + Vector2(120, 22)
	_crop_option.custom_minimum_size = Vector2(130, 0)
	for c in FarmEngine.CROP_COUNT:
		_crop_option.add_item(FarmEngine.CROP_NAME[c], c)
	_crop_option.add_to_group(&"scalable_text")
	_crop_option.item_selected.connect(func(_i: int) -> void: _refresh())
	_layer.add_child(_crop_option)

	_action_button(pos + Vector2(260, 22), "Plant", func() -> void:
		GameManager.plant(_field_option.get_selected_id(), _crop_option.get_selected_id()))
	_action_button(pos + Vector2(330, 22), "Harvest", func() -> void:
		GameManager.harvest(_field_option.get_selected_id()))
	_action_button(pos + Vector2(420, 22), "Fertilize", func() -> void:
		GameManager.fertilize(_field_option.get_selected_id()))
	_action_button(pos + Vector2(520, 22), "Irrigate", func() -> void:
		var f: int = _field_option.get_selected_id()
		GameManager.set_irrigation(f, not GameManager.engine.field_irrigated(f)))

	# Animal + commodity pickers, quantity slider.
	_animal_option = OptionButton.new()
	_animal_option.position = pos + Vector2(0, 56)
	_animal_option.custom_minimum_size = Vector2(110, 0)
	for a in FarmEngine.ANIMAL_COUNT:
		_animal_option.add_item(FarmEngine.ANIMAL_NAME[a], a)
	_animal_option.add_to_group(&"scalable_text")
	_layer.add_child(_animal_option)

	_commodity_option = OptionButton.new()
	_commodity_option.position = pos + Vector2(120, 56)
	_commodity_option.custom_minimum_size = Vector2(130, 0)
	for c in FarmEngine.COMMODITY_COUNT:
		if c == FarmEngine.C_FEED:
			continue
		_commodity_option.add_item(FarmEngine.COMMODITY_NAME[c], c)
	_commodity_option.add_to_group(&"scalable_text")
	_layer.add_child(_commodity_option)

	_qty_lbl = _mk_label(pos + Vector2(260, 52), 13, Color(0.85, 0.85, 0.9))
	_qty_slider = HSlider.new()
	_qty_slider.position = pos + Vector2(260, 74)
	_qty_slider.custom_minimum_size = Vector2(180, 16)
	_qty_slider.min_value = 1
	_qty_slider.max_value = 200
	_qty_slider.step = 1
	_qty_slider.value = 10
	_qty_slider.value_changed.connect(func(_v: float) -> void: _refresh_action_labels())
	_layer.add_child(_qty_slider)

	_action_button(pos + Vector2(460, 56), "Buy Herd", func() -> void:
		GameManager.buy_livestock(_animal_option.get_selected_id(), int(_qty_slider.value)))
	_action_button(pos + Vector2(560, 56), "Sell Herd", func() -> void:
		GameManager.sell_livestock(_animal_option.get_selected_id(), int(_qty_slider.value)))

	_action_button(pos + Vector2(0, 92), "Buy Feed", func() -> void:
		GameManager.buy_feed(int(_qty_slider.value)))
	_action_button(pos + Vector2(100, 92), "Sell Commodity", func() -> void:
		GameManager.sell_commodity(_commodity_option.get_selected_id(), int(_qty_slider.value)))
	_action_button(pos + Vector2(250, 92), "Buy Tractor", func() -> void:
		GameManager.buy_machinery(FarmEngine.M_TRACTOR))
	_action_button(pos + Vector2(370, 92), "Buy Harvester", func() -> void:
		GameManager.buy_machinery(FarmEngine.M_HARVESTER))
	_action_button(pos + Vector2(510, 92), "Loan +6000", func() -> void:
		GameManager.take_loan(6000))
	_action_button(pos + Vector2(620, 92), "Repay 6000", func() -> void:
		GameManager.repay_loan(6000))

	_field_lbl = _mk_label(pos + Vector2(0, 122), 13, Color(0.82, 0.82, 0.72))

	_action_button(pos + Vector2(300, 118), "> Next Day", func() -> void:
		GameManager.advance_day())
	var auto_btn: Button = _action_button(pos + Vector2(430, 118), ">> Auto-Play", func() -> void:
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


func _header(pos: Vector2, text: String, fsize: int, color: Color) -> void:
	var l: Label = _mk_label(pos, fsize, color)
	l.text = text


func _mk_label(pos: Vector2, fsize: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	l.add_to_group(&"hud")
	_layer.add_child(l)
	return l


# =====================================================================
#  Refresh
# =====================================================================

func _refresh() -> void:
	var e: FarmEngine = GameManager.engine
	_cash_lbl.text = "CASH  $%d" % e.cash
	_worth_lbl.text = "NET WORTH  $%d / $%d" % [e.net_worth(), e.win_target]
	var season: int = e.season_of(e.day)
	_time_lbl.text = "Year %d · %s · Day %d/%d" % [
		e.year_of(e.day), FarmEngine.SEASON_NAME[season], e.day_of_year(e.day) + 1, FarmEngine.YEAR_DAYS]
	var wx: int = e.last_weather
	_weather_lbl.text = "Weather: %s   |   income $%d · debt $%d" % [
		FarmEngine.WEATHER_NAME[wx], e.last_income, e.debt]
	_weather_lbl.add_theme_color_override("font_color", WEATHER_COLOR[wx])
	_work_lbl.text = "Work today %d/%d · harvests %d · feed %d" % [
		e.work_used, e.work_capacity(), e.total_harvests, e.feed_stock()]

	_refresh_market()
	_refresh_readout()
	_refresh_action_labels()
	queue_redraw()

	match e.outcome:
		FarmEngine.WON:
			_banner.text = "* PROSPERITY — net worth $%d cleared the $%d goal! The farm thrives." % [
				e.net_worth(), e.win_target]
			_banner.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
		FarmEngine.LOST:
			_banner.text = "x FORECLOSED — the bank has called the loan. Press restart."
			_banner.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
		_:
			_banner.text = "Rotate your fields, watch the weather and the market, keep the herds fed."
			_banner.add_theme_color_override("font_color", Color(0.85, 0.85, 0.7))


func _refresh_market() -> void:
	var e: FarmEngine = GameManager.engine
	_clear(_market_box)
	for c in FarmEngine.COMMODITY_COUNT:
		var price: int = e.market_price(c, e.day)
		var avg: int = e.average_price(c)
		var hot: bool = price >= avg
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_cell(FarmEngine.COMMODITY_NAME[c], 90, Color(0.85, 0.85, 0.9)))
		row.add_child(_cell("$%d" % price, 70,
			Color(0.6, 0.95, 0.6) if hot else Color(0.95, 0.7, 0.6)))
		row.add_child(_cell("avg $%d" % avg, 90, Color(0.7, 0.72, 0.72)))
		var stock: int = e.feed_stock() if c == FarmEngine.C_FEED else e.product_stock(c)
		row.add_child(_cell("stock %d" % stock, 100, Color(0.82, 0.82, 0.7)))
		_market_box.add_child(row)


func _refresh_readout() -> void:
	var e: FarmEngine = GameManager.engine
	_clear(_readout)
	_readout.add_child(_row("HERDS  (need %d feed/day)" % e.daily_feed_need(), Color(0.95, 0.9, 0.6)))
	for a in FarmEngine.ANIMAL_COUNT:
		_readout.add_child(_row("  %s: %d / %d head" % [
			FarmEngine.ANIMAL_NAME[a], e.herd(a), FarmEngine.ANIMAL_CAP[a]], Color(0.8, 0.85, 0.75)))
	_readout.add_child(_row("  last: +%d product · %d births · %d deaths" % [
		e.last_livestock_product, e.last_livestock_births, e.last_livestock_deaths], Color(0.72, 0.78, 0.72)))
	_readout.add_child(_row("MACHINERY", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  tractors %d · harvesters %d · value $%d · harv-eff %.0f%%" % [
		e.tractor_count(), e.harvester_count(), e.machinery_value(), e.harvest_efficiency() * 100.0],
		Color(0.8, 0.85, 0.75)))
	_readout.add_child(_row("FINANCE", Color(0.95, 0.9, 0.6)))
	_readout.add_child(_row("  crop sales $%d · livestock sales $%d" % [
		e.category_total("crop_sales"), e.category_total("livestock_sales")], Color(0.7, 0.9, 0.7)))
	_readout.add_child(_row("  seed -$%d · feed -$%d · fert -$%d · irrig -$%d" % [
		-e.category_total("seed_purchase"), -e.category_total("feed_purchase"),
		-e.category_total("fertilizer"), -e.category_total("irrigation")], Color(0.9, 0.72, 0.72)))
	_readout.add_child(_row("  wages -$%d · overhead -$%d · maint -$%d · interest -$%d" % [
		-e.category_total("wages"), -e.category_total("overhead"),
		-e.category_total("maintenance"), -e.category_total("interest")], Color(0.9, 0.72, 0.72)))
	_readout.add_child(_row("  land $%d · machinery $%d · stock $%d" % [
		e.land_value(), e.machinery_value(), e.stock_value()], Color(0.78, 0.8, 0.85)))


func _refresh_action_labels() -> void:
	var e: FarmEngine = GameManager.engine
	if _qty_lbl != null and _qty_slider != null:
		_qty_lbl.text = "Qty %d" % int(_qty_slider.value)
	if _field_lbl != null and _field_option != null:
		var f: int = _field_option.get_selected_id()
		if f >= 0 and f < FarmEngine.FIELD_COUNT:
			var crop: int = e.field_crop(f)
			var crop_txt: String = "fallow" if crop < 0 else FarmEngine.CROP_NAME[crop]
			_field_lbl.text = "Field %d: %s · N %.0f · soil %.2f · %s" % [
				f, crop_txt, e.field_nitrogen(f), e.field_soil(f),
				"irrigated" if e.field_irrigated(f) else "dry"]


func _cell(text: String, width: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


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
