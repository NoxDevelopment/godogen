extends Node
## _probes/livestock_market_probe.gd
## LIVESTOCK + COMMODITY-MARKET probe:
##  A) LIVESTOCK consume FEED and produce SELLABLE goods. A fed herd draws down the feed
##     stock every day and accumulates milk / eggs / meat into commodity stock; a
##     well-fed herd BREEDS (head count grows); those products SELL for real cash booked to
##     the livestock_sales ledger. An UNFED herd stops producing and suffers mortality.
##  B) the COMMODITY MARKET price VARIES over time (a real computed wave, not a constant),
##     so SELL-TIMING changes revenue: selling the SAME stock on a high-price day earns
##     strictly more than on a low-price day.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# ---------------------------------------------------------------
	# A) livestock eat feed + produce sellable goods + breed.
	# ---------------------------------------------------------------
	var e: FarmEngine = FarmEngine.new()
	e.setup(20260716, {"growth_goal": 50000000, "max_years": 6, "start_cash": 400000})
	e.buy_livestock(FarmEngine.A_CHICKENS, 60)
	e.buy_livestock(FarmEngine.A_CATTLE, 8)
	e.buy_livestock(FarmEngine.A_PIGS, 10)
	e.buy_feed(9000)                       # deep feed reserve → herd stays fully fed.

	var feed_before: int = e.feed_stock()
	var chickens_before: int = e.herd(FarmEngine.A_CHICKENS)
	var eggs_before: int = e.product_stock(FarmEngine.C_EGGS)
	var milk_before: int = e.product_stock(FarmEngine.C_MILK)
	var meat_before: int = e.product_stock(FarmEngine.C_MEAT)
	var births_total: int = 0
	var consumed_total: int = 0
	for _i in 80:
		e.tick_day()
		births_total += e.last_livestock_births
		consumed_total += e.last_feed_consumed

	if not (e.feed_stock() < feed_before):
		fails += 1
		notes.append("feed-not-consumed(%d>=%d)" % [e.feed_stock(), feed_before])
	if not (consumed_total > 0):
		fails += 1
		notes.append("no-feed-drawn")
	if not (e.product_stock(FarmEngine.C_EGGS) > eggs_before):
		fails += 1
		notes.append("no-eggs")
	if not (e.product_stock(FarmEngine.C_MILK) > milk_before):
		fails += 1
		notes.append("no-milk")
	if not (e.product_stock(FarmEngine.C_MEAT) > meat_before):
		fails += 1
		notes.append("no-meat")
	if not (births_total > 0 or e.herd(FarmEngine.A_CHICKENS) > chickens_before):
		fails += 1
		notes.append("no-breeding")

	# products SELL for real cash into livestock_sales.
	var eggs: int = e.product_stock(FarmEngine.C_EGGS)
	var cash_before_sale: int = e.cash
	var ok_sell: bool = e.sell_commodity(FarmEngine.C_EGGS, eggs)
	if not ok_sell or e.cash <= cash_before_sale:
		fails += 1
		notes.append("egg-sale-no-cash")
	if e.category_total("livestock_sales") <= 0:
		fails += 1
		notes.append("livestock-sales-not-booked")

	# an UNFED herd (no feed bought) stops producing + loses head to mortality.
	var starve: FarmEngine = FarmEngine.new()
	starve.setup(20260716, {"growth_goal": 50000000, "max_years": 6, "start_cash": 400000})
	starve.buy_livestock(FarmEngine.A_CHICKENS, 80)
	# no feed → herd goes hungry.
	var starve_start: int = starve.herd(FarmEngine.A_CHICKENS)
	var eggs_s0: int = starve.product_stock(FarmEngine.C_EGGS)
	for _i in 60:
		starve.tick_day()
	if not (starve.herd(FarmEngine.A_CHICKENS) < starve_start):
		fails += 1
		notes.append("starving-herd-no-mortality(%d>=%d)" % [starve.herd(FarmEngine.A_CHICKENS), starve_start])
	if not (starve.product_stock(FarmEngine.C_EGGS) == eggs_s0):
		fails += 1
		notes.append("starving-herd-still-produced")

	# ---------------------------------------------------------------
	# B) market price varies over time; sell-timing changes revenue.
	# ---------------------------------------------------------------
	var mkt: FarmEngine = FarmEngine.new()
	mkt.setup(20260716, {"growth_goal": 50000000, "max_years": 4, "start_cash": 400000})
	var lo_price: int = 1 << 30
	var hi_price: int = 0
	var lo_day: int = 0
	var hi_day: int = 0
	for d in FarmEngine.YEAR_DAYS:
		var p: int = mkt.market_price(FarmEngine.C_GRAIN, d)
		if p < lo_price:
			lo_price = p
			lo_day = d
		if p > hi_price:
			hi_price = p
			hi_day = d
	if not (hi_price > lo_price):
		fails += 1
		notes.append("price-flat(%d==%d)" % [hi_price, lo_price])
	# the swing is material (> 15% of the low).
	if not (hi_price - lo_price > lo_price / 6):
		fails += 1
		notes.append("price-swing-small(%d..%d)" % [lo_price, hi_price])

	# stock some grain by harvesting a forced-clear cycle, then sell at each day via clones.
	mkt.setup(20260716, {"weather_override": FarmEngine.W_NORMAL,
		"growth_goal": 50000000, "max_years": 4, "start_cash": 400000})
	for f in mkt.field_count():
		mkt.plant(f, FarmEngine.CR_CORN, true)
	for _i in FarmEngine.CROP_DURATION[FarmEngine.CR_CORN]:
		mkt.tick_day()
	for f in mkt.field_count():
		if mkt.field_is_mature(f):
			mkt.harvest(f)
	var grain: int = mkt.product_stock(FarmEngine.C_GRAIN)
	if grain < 10:
		fails += 1
		notes.append("no-grain-to-sell(%d)" % grain)

	var sell_units: int = grain / 2
	var blob: Dictionary = mkt.save_data()

	var sell_lo: FarmEngine = FarmEngine.new()
	sell_lo.load_data(blob)
	sell_lo.day = lo_day
	var lo_cash0: int = sell_lo.cash
	sell_lo.sell_commodity(FarmEngine.C_GRAIN, sell_units)
	var lo_rev: int = sell_lo.cash - lo_cash0

	var sell_hi: FarmEngine = FarmEngine.new()
	sell_hi.load_data(blob)
	sell_hi.day = hi_day
	var hi_cash0: int = sell_hi.cash
	sell_hi.sell_commodity(FarmEngine.C_GRAIN, sell_units)
	var hi_rev: int = sell_hi.cash - hi_cash0

	if not (hi_rev > lo_rev):
		fails += 1
		notes.append("sell-timing-flat(hi=%d lo=%d)" % [hi_rev, lo_rev])
	if sell_lo.category_total("crop_sales") <= 0:
		fails += 1
		notes.append("crop-sales-not-booked")

	print("DEBUG: livestock_market_probe fed_consumed=%d eggs=%d milk=%d meat=%d births=%d price=%d..%d(day %d/%d) rev lo=%d hi=%d notes=%s fails=%d => %s" % [
		consumed_total, e.product_stock(FarmEngine.C_EGGS), e.product_stock(FarmEngine.C_MILK),
		e.product_stock(FarmEngine.C_MEAT), births_total, lo_price, hi_price, lo_day, hi_day,
		lo_rev, hi_rev, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
