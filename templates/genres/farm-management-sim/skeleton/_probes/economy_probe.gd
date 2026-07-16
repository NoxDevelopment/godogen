extends Node
## _probes/economy_probe.gd
## ECONOMY probe: strict INTEGER MONEY CONSERVATION. Over a long deterministic scripted run
## (multiple years), cash == starting cash + Σ(named ledger flows) EVERY day; the per-day
## reported last_income equals the real cash delta of the TICK (player spending / selling
## happens OUTSIDE the tick bracket); every ledger category is a DEFINED, named flow (no
## undefined path minted money); and net worth is computed as cash + land + machinery +
## stock − debt.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# A high growth goal keeps the farm ONGOING for the whole run so conservation is
	# exercised over many days rather than ending early on a win.
	# Huge goal + deep capital + an effectively-bottomless bankruptcy floor keep the farm
	# ONGOING for the whole multi-year run so conservation is exercised over many days.
	var e: FarmEngine = FarmEngine.new()
	e.setup(20260716, {"growth_goal": 50000000, "max_years": 8,
		"start_cash": 5000000, "bankruptcy_floor": -1000000000, "bankruptcy_patience": 100000})
	var start_cash: int = e.category_total("seed_capital")

	var known: Dictionary = {}
	for k in FarmEngine.LEDGER_CATEGORIES:
		known[String(k)] = true

	var days: int = 0
	var cons_fail: int = 0
	var income_fail: int = 0
	var nw_fail: int = 0
	var undefined_cat: int = 0

	# Buy a starter herd + machinery once, so feed / maintenance / depreciation flows run.
	e.buy_livestock(FarmEngine.A_CHICKENS, 30)
	e.buy_livestock(FarmEngine.A_CATTLE, 4)
	e.buy_machinery(FarmEngine.M_TRACTOR)

	while e.outcome == FarmEngine.ONGOING and days < 1200:
		# --- deterministic PLAYER actions (OUTSIDE the tick bracket so last_income can be
		#     checked to equal the tick's cash movement alone) ---
		# harvest whatever is ready, then sell all harvested stock.
		for f in e.field_count():
			if e.field_is_mature(f):
				e.harvest(f)
		for c in FarmEngine.COMMODITY_COUNT:
			if c == FarmEngine.C_FEED:
				continue
			if e.product_stock(c) > 0:
				e.sell_commodity(c, e.product_stock(c))
		# plant fallow fields (override season so the schedule is dense + deterministic).
		for f in e.field_count():
			if e.field_is_fallow(f) and e.work_remaining() > 0:
				var crop: int = (f + days) % FarmEngine.CROP_COUNT
				if e.cash - FarmEngine.CROP_SEED_COST[crop] > 3000 and e.can_plant(f, crop, true):
					e.plant(f, crop, true)
		# keep the herd fed.
		var need: int = e.daily_feed_need()
		if need > 0 and e.feed_stock() < need * 4:
			var batch: int = need * 6
			if e.can_buy_feed(batch):
				e.buy_feed(batch)
		# exercise fertilize + irrigation + a loan draw/repay on a cadence.
		if days % 40 == 7 and e.can_fertilize(0):
			e.fertilize(0)
		if days % 25 == 3:
			e.set_irrigation(1, true)
		if days % 25 == 15:
			e.set_irrigation(1, false)
		if days % 120 == 11 and e.can_take_loan(4000):
			e.take_loan(4000)
		if days % 120 == 80 and e.can_repay_loan(2000):
			e.repay_loan(2000)

		# --- the TICK: last_income must equal exactly the cash it moved ---
		var cash_before: int = e.cash
		var delta: int = e.tick_day()
		days += 1

		# 1) reported income equals the real change over the tick.
		if e.cash - cash_before != delta or delta != e.last_income:
			income_fail += 1

		# 2) conservation: cash == start + Σledger, recomputed from scratch.
		var ledger: int = 0
		for k in e.category_keys():
			ledger += e.category_total(String(k))
		if e.cash != ledger or not e.conservation_ok():
			cons_fail += 1

		# 3) every category is a DEFINED named flow.
		for k in e.category_keys():
			if not known.has(String(k)):
				undefined_cat += 1

		# 4) net worth == cash + land + machinery + stock − debt.
		if e.net_worth() != e.cash + e.land_value() + e.machinery_value() + e.stock_value() - e.debt:
			nw_fail += 1

	if days < 200:
		fails += 1
		notes.append("run-too-short(%d)" % days)
	if cons_fail != 0:
		fails += 1
		notes.append("conservation-broke(%d)" % cons_fail)
	if income_fail != 0:
		fails += 1
		notes.append("income-mismatch(%d)" % income_fail)
	if undefined_cat != 0:
		fails += 1
		notes.append("undefined-category(%d)" % undefined_cat)
	if nw_fail != 0:
		fails += 1
		notes.append("networth-wrong(%d)" % nw_fail)

	# The final books must still reconcile to the seed capital plus every flow.
	var final_ledger: int = 0
	for k in e.category_keys():
		final_ledger += e.category_total(String(k))
	if e.cash != final_ledger:
		fails += 1
		notes.append("final-books(%d!=%d)" % [e.cash, final_ledger])

	print("DEBUG: economy_probe days=%d start=%d cash=%d ledger=%d nw=%d cons_fail=%d income_fail=%d nw_fail=%d notes=%s fails=%d => %s" % [
		days, start_cash, e.cash, final_ledger, e.net_worth(), cons_fail, income_fail, nw_fail,
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
