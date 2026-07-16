extends Node
## _probes/economy_probe.gd
## ECONOMY probe: strict INTEGER MONEY CONSERVATION. Over a long deterministic scripted
## run, cash == starting cash + Σ(named ledger flows) EVERY day; the per-day reported
## last_income equals the real cash delta of the TICK (player spending happens OUTSIDE
## the tick bracket); every ledger category is a DEFINED, named flow (no undefined path
## minted money); net worth is computed as cash + inventory − debt; and the UNIT
## INVENTORY INVARIANT purchased == on_hand + in_transit + consumed holds for every
## product line, every day (units are never minted or lost outside named transitions).

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# A high growth goal keeps the store ONGOING for the whole run so conservation is
	# exercised over many days rather than ending early on a win.
	var e: DeptStoreEngine = DeptStoreEngine.new()
	e.setup(20260716, {"growth_goal": 5000000, "max_days": 5000})
	var start_cash: int = e.category_total("seed_capital")

	var known: Dictionary = {
		"seed_capital": true, "instore_revenue": true, "catalogue_revenue": true,
		"restock": true, "wages": true, "overhead": true, "marketing": true,
		"catalogue_print": true, "catalogue_fulfill": true, "interest": true,
		"loan_draw": true, "loan_repay": true, "liquidation": true,
	}

	var days: int = 0
	var cons_fail: int = 0
	var income_fail: int = 0
	var integ_fail: int = 0
	var nw_fail: int = 0
	var undefined_cat: int = 0

	while e.outcome == DeptStoreEngine.ONGOING and days < 400:
		# --- deterministic PLAYER actions (OUTSIDE the tick bracket so last_income can
		#     be checked to equal the tick's cash movement alone) ---
		for d in e.dept_count():
			e.set_dept_staff(d, 2)
			e.set_dept_space(d, 10)
		# publish a fresh catalogue whenever the last one lapses.
		if e.catalogue_left == 0 and e.can_publish_catalogue():
			e.publish_catalogue()
		# marketing on a fixed cadence.
		if days % 50 == 11 and e.can_run_marketing():
			e.run_marketing()
		# modest restock of every line; exercise a markdown + a liquidation too.
		for i in e.line_count():
			var target: int = 6
			if e.line_on_hand(i) < target:
				var need: int = target - e.line_on_hand(i)
				var cost: int = need * DeptStoreEngine.LINE_COST[i]
				if e.cash - cost > 9000 and e.can_restock(i, need):
					e.restock(i, need)
		if days % 30 == 5:
			e.set_markdown(0, 3000)
		if days % 30 == 20:
			e.set_markdown(0, 0)
		if days % 45 == 9 and e.can_liquidate(1, 1):
			e.liquidate(1, 1)

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

		# 4) net worth == cash + inventory − debt.
		if e.net_worth() != e.cash + e.inventory_value() - e.debt:
			nw_fail += 1

		# 5) unit inventory integrity: purchased == on_hand + in_transit + consumed, per line.
		for i in e.line_count():
			if e.line_purchased(i) != e.line_on_hand(i) + e.line_in_transit(i) + e.line_consumed(i):
				integ_fail += 1
				break
			if e.line_on_hand(i) < 0:
				integ_fail += 1
				break

	if days < 60:
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
	if integ_fail != 0:
		fails += 1
		notes.append("inventory-integrity(%d)" % integ_fail)

	# The final books must still reconcile to the seed capital plus every flow.
	var final_ledger: int = 0
	for k in e.category_keys():
		final_ledger += e.category_total(String(k))
	if e.cash != final_ledger:
		fails += 1
		notes.append("final-books(%d!=%d)" % [e.cash, final_ledger])

	print("DEBUG: economy_probe days=%d start=%d cash=%d ledger=%d nw=%d cons_fail=%d income_fail=%d integ_fail=%d notes=%s fails=%d => %s" % [
		days, start_cash, e.cash, final_ledger, e.net_worth(), cons_fail, income_fail, integ_fail,
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
