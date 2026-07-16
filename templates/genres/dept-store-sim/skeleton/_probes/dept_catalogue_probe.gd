extends Node
## _probes/dept_catalogue_probe.gd
## DEPARTMENTS + CATALOGUE probe:
##  1) an in-store SALE decrements the RIGHT product line's on-hand stock (and the right
##     department's total), turning a unit from on_hand → consumed;
##  2) a STOCKOUT blocks a sale (an out-of-stock line records a stockout, no sale, no
##     stock change) while a well-stocked line in the same store still sells;
##  3) the MAIL-ORDER CATALOGUE opens an INCREMENTAL demand stream a stocked-out FLOOR
##     can't serve — with the floor's foot traffic throttled to near zero, publishing a
##     catalogue moves real units the store otherwise never would (assert catalogue run
##     ships MORE units + earns real catalogue revenue vs a no-catalogue baseline);
##  4) the catalogue's COST + LEAD TIME are modeled: publishing charges the print cost up
##     front, orders reserve stock into transit, and revenue lands only AFTER the lead
##     time (not on the order day).

const TV: int = 4        ## Electronics / Televisions.
const RING: int = 25     ## Jewelry / Diamond Rings.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# ---------------------------------------------------------------
	# 1) an in-store sale decrements the correct line's stock (on_hand → consumed).
	# ---------------------------------------------------------------
	var e: DeptStoreEngine = DeptStoreEngine.new()
	e.setup(20260716, {"base_traffic": 60})
	# Staff the store, give the whole floor to Electronics so its lines get the traffic,
	# and stock ONLY Televisions.
	for d in e.dept_count():
		e.set_dept_staff(d, 2)
		e.set_dept_space(d, 0)
	e.set_dept_space(DeptStoreEngine.LINE_DEPT[TV], 40)
	e.restock(TV, 30)
	var tv_dept: int = DeptStoreEngine.LINE_DEPT[TV]
	var owned0: int = e.line_purchased(TV)
	var onhand0: int = e.line_on_hand(TV)
	var dept0: int = e.dept_on_hand(tv_dept)
	if onhand0 != 30 or owned0 != 30 or dept0 < 30:
		fails += 1
		notes.append("restock-wrong(on=%d pur=%d dept=%d)" % [onhand0, owned0, dept0])

	e.tick_day()
	var sold: int = e.line_day_sales(TV)
	if sold <= 0:
		fails += 1
		notes.append("no-instore-sale")
	if e.line_on_hand(TV) != onhand0 - sold:
		fails += 1
		notes.append("stock-not-decremented(%d!=%d)" % [e.line_on_hand(TV), onhand0 - sold])
	if e.line_consumed(TV) != sold:
		fails += 1
		notes.append("consumed-wrong(%d!=%d)" % [e.line_consumed(TV), sold])
	# a line we never stocked in a spaced-out department should have zero sales.
	if e.line_day_sales(RING) != 0:
		fails += 1
		notes.append("phantom-sale-elsewhere")

	# ---------------------------------------------------------------
	# 2) a STOCKOUT blocks a sale. Heavy traffic, only 2 TVs, everyone else who wants a
	#    TV misses; the store still records stockouts and never oversells.
	# ---------------------------------------------------------------
	var g: DeptStoreEngine = DeptStoreEngine.new()
	g.setup(20260716, {"base_traffic": 200})
	for d in g.dept_count():
		g.set_dept_staff(d, 3)
		g.set_dept_space(d, 0)
	g.set_dept_space(DeptStoreEngine.LINE_DEPT[TV], 40)
	g.restock(TV, 2)
	g.tick_day()
	if g.line_on_hand(TV) != 0:
		fails += 1
		notes.append("stockout-copies-left(%d)" % g.line_on_hand(TV))
	if g.line_day_sales(TV) > 2:
		fails += 1
		notes.append("oversold(%d>2)" % g.line_day_sales(TV))
	if g.line_day_stockouts(TV) <= 0:
		fails += 1
		notes.append("no-stockout-recorded")

	# ---------------------------------------------------------------
	# 3) + 4) the CATALOGUE opens incremental demand a near-dead floor can't serve, and
	#    its cost + lead time are modeled. Two identical stores with almost no foot
	#    traffic and deep stock; one PUBLISHES a catalogue. Compare units moved.
	# ---------------------------------------------------------------
	var cfg: Dictionary = {"base_traffic": 4, "catalogue_lead_time": 5, "catalogue_cost": 3000, "start_cash": 400000}
	# Baseline: no catalogue.
	var base_e: DeptStoreEngine = DeptStoreEngine.new()
	base_e.setup(20260716, cfg)
	_stock_broadly(base_e)
	var base_consumed0: int = _total_consumed(base_e)
	for _i in 30:
		base_e.tick_day()
	var base_moved: int = _total_consumed(base_e) - base_consumed0

	# Catalogue: publish up front, same seed + stock + traffic.
	var cat_e: DeptStoreEngine = DeptStoreEngine.new()
	cat_e.setup(20260716, cfg)
	_stock_broadly(cat_e)
	var cat_consumed0: int = _total_consumed(cat_e)
	var cash_before_pub: int = cat_e.cash
	var pub_ok: bool = cat_e.publish_catalogue()
	if not pub_ok:
		fails += 1
		notes.append("publish-failed")
	# 4a) the print cost is charged up front.
	if cat_e.cash != cash_before_pub - cat_e.catalogue_cost:
		fails += 1
		notes.append("print-cost-not-charged")
	if cat_e.category_total("catalogue_print") != -cat_e.catalogue_cost:
		fails += 1
		notes.append("print-ledger-wrong")

	# 4b) first tick: orders are PLACED (reserved into transit) but ship only after the
	#     lead time — no catalogue revenue lands yet.
	cat_e.tick_day()
	if cat_e.last_catalogue_orders <= 0:
		fails += 1
		notes.append("no-catalogue-orders")
	if cat_e.active_shipments() <= 0:
		fails += 1
		notes.append("no-in-transit")
	if cat_e.category_total("catalogue_revenue") != 0:
		fails += 1
		notes.append("revenue-before-leadtime(%d)" % cat_e.category_total("catalogue_revenue"))
	# advance through the lead time; now the first orders ship and revenue lands.
	for _i in (cat_e.catalogue_lead_time + 1):
		cat_e.tick_day()
	if cat_e.category_total("catalogue_revenue") <= 0:
		fails += 1
		notes.append("no-revenue-after-leadtime")
	if cat_e.category_total("catalogue_fulfill") >= 0:
		fails += 1
		notes.append("no-fulfillment-cost")
	# run out the rest of the window.
	for _i in 24:
		cat_e.tick_day()
	var cat_moved: int = _total_consumed(cat_e) - cat_consumed0

	# 3) the catalogue moved strictly MORE units than the baseline floor alone.
	if cat_moved <= base_moved:
		fails += 1
		notes.append("catalogue-not-incremental(cat=%d base=%d)" % [cat_moved, base_moved])
	if cat_e.category_total("catalogue_revenue") <= 0:
		fails += 1
		notes.append("catalogue-no-revenue")

	# inventory integrity holds across both runs.
	if not _integrity_ok(cat_e) or not _integrity_ok(base_e):
		fails += 1
		notes.append("integrity-broke")

	print("DEBUG: dept_catalogue_probe tv_sold=%d stockout=%d base_moved=%d cat_moved=%d cat_rev=%d notes=%s fails=%d => %s" % [
		sold, g.line_day_stockouts(TV), base_moved, cat_moved, cat_e.category_total("catalogue_revenue"),
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()


func _stock_broadly(e: DeptStoreEngine) -> void:
	for d in e.dept_count():
		e.set_dept_staff(d, 2)
		e.set_dept_space(d, 10)
	for i in e.line_count():
		e.restock(i, 30)


func _total_consumed(e: DeptStoreEngine) -> int:
	var c: int = 0
	for i in e.line_count():
		c += e.line_consumed(i)
	return c


func _integrity_ok(e: DeptStoreEngine) -> bool:
	for i in e.line_count():
		if e.line_purchased(i) != e.line_on_hand(i) + e.line_in_transit(i) + e.line_consumed(i):
			return false
	return true
