extends Node
## _probes/economy_probe.gd
## ECONOMY probe: supply/demand pricing spreads across ports (producers cheap,
## consumers dear), buying/selling MOVES the local price (price impact), a real
## arbitrage route is profitable, and a fleeced market DRIFTS back toward equilibrium.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []
	var e: PirateEngine = PirateEngine.new()
	e.setup(20260715, {"policy": "trade"})

	# --- 1) supply/demand pricing: the same good is much cheaper somewhere than elsewhere ---
	var spread_ok: bool = false
	for gid in e.GOOD_IDS:
		var lo: int = 1000000
		var hi: int = 0
		for pi in e.ports.size():
			var mid: int = e.unit_price(pi, gid, "buy")
			lo = mini(lo, mid)
			hi = maxi(hi, mid)
		if float(hi) >= float(lo) * 1.8:
			spread_ok = true
	if not spread_ok:
		fails += 1
		notes.append("no-price-spread")

	# --- 2) price impact: buying raises the local buy price ---
	# sail to a cheap PRODUCER port for a good, buy a chunk, watch the price climb.
	e.gold = 1000000
	var pg: Dictionary = _find_producer(e)
	e.location = int(pg["port"])
	var g: String = String(pg["good"])
	var buy_before: int = e.port_buy_price(g)
	var bought: bool = e.buy(g, 60)
	var buy_after: int = e.port_buy_price(g)
	if not bought:
		fails += 1
		notes.append("buy-failed")
	if buy_after <= buy_before:
		fails += 1
		notes.append("impact-buy(before=%d after=%d)" % [buy_before, buy_after])
	# selling into a hungry CONSUMER port lowers its sell price (dumping the market).
	var cg: Dictionary = _find_consumer(e)
	e.location = int(cg["port"])
	var g2: String = String(cg["good"])
	e.cargo[g2] = 200
	var sell_before: int = e.port_sell_price(g2)
	e.sell(g2, 80)
	var sell_after: int = e.port_sell_price(g2)
	if sell_after >= sell_before:
		fails += 1
		notes.append("impact-sell(before=%d after=%d)" % [sell_before, sell_after])

	# --- 3) arbitrage is profitable (a real buy-low / sail / sell-high route) ---
	var e2: PirateEngine = PirateEngine.new()
	e2.setup(20260715, {"policy": "trade"})
	e2.gold = 100000
	var route: Dictionary = e2._best_trade_route()
	if route.is_empty() or int(route.get("profit", 0)) <= 0:
		fails += 1
		notes.append("no-arbitrage")
	else:
		# execute it and confirm the realised profit is positive.
		var good: String = String(route["good"])
		var dest: int = int(route["dest"])
		var qty: int = int(route["qty"])
		var cost: int = e2.quote_buy(good, qty)
		e2.buy(good, qty)
		var gold_after_buy: int = e2.gold
		e2.sail_to(dest)
		var got: bool = e2.sell(good, qty)
		var realised: int = e2.gold - gold_after_buy
		if not got or realised <= 0:
			fails += 1
			notes.append("arb-realised=%d(cost=%d)" % [realised, cost])

	# --- 4) drift-back: fleece a market, then let it relax toward equilibrium ---
	var e3: PirateEngine = PirateEngine.new()
	e3.setup(20260715, {"policy": "trade"})
	e3.gold = 1000000
	var pg3: Dictionary = _find_producer(e3)
	e3.location = int(pg3["port"])
	var gid2: String = String(pg3["good"])
	var base_price: int = e3.port_buy_price(gid2)
	e3.buy(gid2, 80)                         ## depletes stock -> price spikes.
	var spiked: int = e3.port_buy_price(gid2)
	for _d in 500:
		e3._drift_economy()                  ## time passes; the market recovers.
	var drifted: int = e3.port_buy_price(gid2)
	if spiked <= base_price:
		fails += 1
		notes.append("no-spike(base=%d spike=%d)" % [base_price, spiked])
	if drifted >= spiked:
		fails += 1
		notes.append("no-driftback(spike=%d drift=%d)" % [spiked, drifted])

	print("DEBUG: economy_probe spread_ok=%s buy(%d->%d) drift(base=%d spike=%d drift=%d) notes=%s fails=%d => %s" % [
		str(spread_ok), buy_before, buy_after, base_price, spiked, drifted, str(notes), fails,
		("OK" if fails == 0 else "FAIL")])
	get_tree().quit()


## Find a (port, good) where the good is cheaply over-supplied (a producer) — an
## unclamped price well above the floor so buying visibly moves it.
func _find_producer(e: PirateEngine) -> Dictionary:
	var best: Dictionary = {"port": 0, "good": String(e.GOOD_IDS[0])}
	var best_stock: float = 0.0
	for pi in e.ports.size():
		for gid in e.GOOD_IDS:
			var st: float = float(e.ports[pi]["econ"][gid]["stock"])
			var price: int = e.unit_price(pi, gid, "buy")
			var floor_price: float = float(e.GOODS[gid]["base"]) * e.PRICE_MIN_MULT
			if st > best_stock and float(price) > floor_price * 1.25:
				best_stock = st
				best = {"port": pi, "good": gid}
	return best


## Find a (port, good) where the good is dear + scarce (a consumer) — an unclamped
## price below the ceiling so dumping stock visibly lowers it.
func _find_consumer(e: PirateEngine) -> Dictionary:
	var best: Dictionary = {"port": 0, "good": String(e.GOOD_IDS[0])}
	var best_price: float = 0.0
	for pi in e.ports.size():
		for gid in e.GOOD_IDS:
			var price: int = e.unit_price(pi, gid, "sell")
			var ceil_price: float = float(e.GOODS[gid]["base"]) * e.PRICE_MAX_MULT
			if float(price) > best_price and float(price) < ceil_price * 0.9:
				best_price = float(price)
				best = {"port": pi, "good": gid}
	return best
