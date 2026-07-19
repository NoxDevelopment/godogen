extends Node
## _probes/seasonal_probe.gd
## SEASONAL DEMAND + MARKDOWN probe:
##  A) each department's demand tracks its SEASONAL CURVE — Toys & Electronics PEAK in
##     the Christmas window and trough in late winter; Home & Garden peaks in SPRING and
##     troughs in winter; Jewelry peaks at Valentine's. Asserted on the computed
##     season_mult() formula AND on realized product-line demand() (which folds season
##     in), plus the department's SHARE of total demand rising in its season.
##  B) a MARKDOWN clears AGING stock: from an identical aged inventory state, marking a
##     line down moves MORE units and leaves LESS on the shelf (clears the stock), at a
##     LOWER price / thinner margin (cuts margin) while still recovering more cash per
##     unit than dumping to a jobber (liquidation salvage) — recovers cash.

const CHRISTMAS: int = 345
const TROUGH: int = 60      ## early March — post-holiday slump.
const SPRING: int = 135
const WINTER: int = 350
const VALENTINE: int = 44

const TOY_LINE: int = 9     ## Board Games.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	var e: DeptStoreEngine = DeptStoreEngine.new()
	e.setup(20260716, {})

	# ---------------------------------------------------------------
	# A) seasonal curve: peaks vs troughs, per department.
	# ---------------------------------------------------------------
	var toy_peak: float = e.season_mult(DeptStoreEngine.D_TOYS, CHRISTMAS)
	var toy_trough: float = e.season_mult(DeptStoreEngine.D_TOYS, TROUGH)
	if not (toy_peak > toy_trough * 1.5):
		fails += 1
		notes.append("toys-not-christmas-peaked(peak=%.2f trough=%.2f)" % [toy_peak, toy_trough])
	if not (toy_peak > 2.0):
		fails += 1
		notes.append("toys-peak-too-flat(%.2f)" % toy_peak)

	var elec_peak: float = e.season_mult(DeptStoreEngine.D_ELECTRONICS, CHRISTMAS)
	var elec_trough: float = e.season_mult(DeptStoreEngine.D_ELECTRONICS, TROUGH)
	if not (elec_peak > elec_trough * 1.3):
		fails += 1
		notes.append("electronics-not-christmas-peaked(peak=%.2f trough=%.2f)" % [elec_peak, elec_trough])

	var garden_spring: float = e.season_mult(DeptStoreEngine.D_HOMEGARDEN, SPRING)
	var garden_winter: float = e.season_mult(DeptStoreEngine.D_HOMEGARDEN, WINTER)
	if not (garden_spring > garden_winter * 1.4):
		fails += 1
		notes.append("garden-not-spring-peaked(spring=%.2f winter=%.2f)" % [garden_spring, garden_winter])

	var jewel_val: float = e.season_mult(DeptStoreEngine.D_JEWELRY, VALENTINE)
	var jewel_off: float = e.season_mult(DeptStoreEngine.D_JEWELRY, 90)
	if not (jewel_val > jewel_off * 1.3):
		fails += 1
		notes.append("jewelry-not-valentine-peaked(val=%.2f off=%.2f)" % [jewel_val, jewel_off])

	# realized product-line demand (folds season in) tracks the curve too.
	if not (e.demand(TOY_LINE, CHRISTMAS) > e.demand(TOY_LINE, TROUGH) * 1.5):
		fails += 1
		notes.append("toy-line-demand-not-seasonal")

	# a department's SHARE of total demand rises in its season.
	var toys_share_xmas: float = e.dept_demand(DeptStoreEngine.D_TOYS, CHRISTMAS) / _total_demand(e, CHRISTMAS)
	var toys_share_trough: float = e.dept_demand(DeptStoreEngine.D_TOYS, TROUGH) / _total_demand(e, TROUGH)
	if not (toys_share_xmas > toys_share_trough):
		fails += 1
		notes.append("toys-share-not-rising(xmas=%.3f trough=%.3f)" % [toys_share_xmas, toys_share_trough])

	# ---------------------------------------------------------------
	# B) markdown clears aging stock.
	# ---------------------------------------------------------------
	# Build an AGED state: stock all Toys lines deep, route traffic there, and run long
	# enough that stock ages past the markdown threshold while some remains unsold.
	var aged: DeptStoreEngine = DeptStoreEngine.new()
	aged.setup(20260716, {"base_traffic": 30, "growth_goal": 5000000, "max_days": 5000, "start_cash": 200000})
	for d in aged.dept_count():
		aged.set_dept_staff(d, 1)
		aged.set_dept_space(d, 0)
	aged.set_dept_space(DeptStoreEngine.D_TOYS, 40)
	for i in aged.line_count():
		if DeptStoreEngine.LINE_DEPT[i] == DeptStoreEngine.D_TOYS:
			aged.restock(i, 1000)
	for _i in 55:
		aged.tick_day()
	if aged.line_age(TOY_LINE) < float(aged.markdown_age_threshold):
		fails += 1
		notes.append("stock-did-not-age(%.0f)" % aged.line_age(TOY_LINE))
	if aged.line_on_hand(TOY_LINE) <= 0:
		fails += 1
		notes.append("nothing-left-to-clear")

	# Clone the aged state into two branches via save/load.
	var snapshot: Dictionary = aged.save_data()
	var mark: DeptStoreEngine = DeptStoreEngine.new()
	mark.load_data(snapshot)
	var keep: DeptStoreEngine = DeptStoreEngine.new()
	keep.load_data(snapshot)

	# One branch marks the aging line down deeply; the other leaves it at full price.
	mark.set_markdown(TOY_LINE, 5000)
	var mark_price: int = mark.effective_price(TOY_LINE)
	var keep_price: int = keep.effective_price(TOY_LINE)
	if not (mark_price < DeptStoreEngine.LINE_PRICE[TOY_LINE]):
		fails += 1
		notes.append("markdown-price-not-cut(%d)" % mark_price)
	if not (mark.unit_margin(TOY_LINE) < keep.unit_margin(TOY_LINE)):
		fails += 1
		notes.append("markdown-margin-not-cut(%d>=%d)" % [mark.unit_margin(TOY_LINE), keep.unit_margin(TOY_LINE)])

	var mark_sold0: int = mark.line_consumed(TOY_LINE)
	var keep_sold0: int = keep.line_consumed(TOY_LINE)
	var mark_cash0: int = mark.cash
	var keep_cash0: int = keep.cash
	for _i in 20:
		mark.tick_day()
		keep.tick_day()
	var mark_moved: int = mark.line_consumed(TOY_LINE) - mark_sold0
	var keep_moved: int = keep.line_consumed(TOY_LINE) - keep_sold0

	# markdown moves MORE units of the aging line…
	if not (mark_moved > keep_moved):
		fails += 1
		notes.append("markdown-not-clearing(mark=%d keep=%d)" % [mark_moved, keep_moved])
	# …leaving LESS on the shelf (cleared more)…
	if not (mark.line_on_hand(TOY_LINE) < keep.line_on_hand(TOY_LINE)):
		fails += 1
		notes.append("markdown-more-leftover(%d>=%d)" % [mark.line_on_hand(TOY_LINE), keep.line_on_hand(TOY_LINE)])
	# …recovers real cash from the aging stock (cleared units × marked price > 0), and
	#    each cleared unit still beats dumping to a jobber (salvage value).
	var clearance_cash: int = mark_moved * mark_price
	if not (clearance_cash > 0):
		fails += 1
		notes.append("markdown-no-cash-recovered")
	if not (mark_price > mark.unit_salvage_value(TOY_LINE)):
		fails += 1
		notes.append("markdown-worse-than-salvage(%d<=%d)" % [mark_price, mark.unit_salvage_value(TOY_LINE)])

	print("DEBUG: seasonal_probe toy_peak=%.2f/%.2f elec=%.2f/%.2f garden=%.2f/%.2f mark_moved=%d keep_moved=%d mark_left=%d keep_left=%d notes=%s fails=%d => %s" % [
		toy_peak, toy_trough, elec_peak, elec_trough, garden_spring, garden_winter,
		mark_moved, keep_moved, mark.line_on_hand(TOY_LINE), keep.line_on_hand(TOY_LINE),
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()


func _total_demand(e: DeptStoreEngine, at_day: int) -> float:
	var s: float = 0.0
	for i in e.line_count():
		s += e.demand(i, at_day)
	return s
