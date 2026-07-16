extends Node
## _probes/economy_probe.gd
## ECONOMY probe: strict INTEGER MONEY CONSERVATION. Over a long deterministic
## auto-play run, cash == starting cash + Σ(named ledger flows) EVERY day; the
## per-day reported last_income equals the real cash delta; every ledger category is
## a DEFINED, named flow (no undefined path minted money); net worth is computed as
## cash + inventory − debt; and the inventory integrity invariant
## owned == available + rented holds for every title, every day.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	var e: VideoStoreEngine = VideoStoreEngine.new()
	e.setup(20260716, {})
	var start_cash: int = e.category_total("seed_capital")

	var known: Dictionary = {
		"seed_capital": true, "rental_income": true, "late_fees": true,
		"tape_purchase": true, "tape_salvage": true, "rent": true, "wages": true,
		"interest": true, "marketing": true, "loan_draw": true, "loan_repay": true,
	}

	var days: int = 0
	var cons_fail: int = 0
	var income_fail: int = 0
	var integ_fail: int = 0
	var nw_fail: int = 0
	var undefined_cat: int = 0

	while e.outcome == VideoStoreEngine.ONGOING and days < 400:
		# --- deterministic PLAYER actions (spending happens OUTSIDE the tick bracket
		#     so last_income can be checked to equal the tick's cash movement alone) ---
		e.set_staff(2)
		e.set_late_fee(2)
		if days % 40 == 7 and e.can_run_marketing():
			e.run_marketing()
		for t in e.title_count():
			if not e.is_released(t, e.day):
				continue
			var target: int = 5 if e.is_new_release(t, e.day) else 4
			if e.title_owned(t) < target:
				var need: int = target - e.title_owned(t)
				var cost: int = need * VideoStoreEngine.TITLE_COST[t]
				if e.cash - cost > 1200 and e.can_buy_copies(t, need):
					e.buy_copies(t, need)
		if e.cash < 200 and e.net_worth() > 3000 and e.can_take_loan(2000):
			e.take_loan(2000)

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

		# 5) inventory integrity: owned == available + rented, per title.
		for t in e.title_count():
			if e.title_owned(t) != e.title_available(t) + e.rentals_of_title(t):
				integ_fail += 1
				break

	if days < 50:
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
