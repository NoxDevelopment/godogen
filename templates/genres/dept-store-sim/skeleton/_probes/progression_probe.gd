extends Node
## _probes/progression_probe.gd
## PROGRESSION probe: the deterministic auto-play reaches a WIN (net-worth goal) on a
## healthy store AND a LOSS (bankruptcy) on a harsh one, and EVERY run terminates under
## the MAX_DAYS cap. Outcome only ever transitions ONCE (ONGOING -> terminal), and once
## terminal the store stops ticking (frozen — no further cash movement).

const WIN_CFG: Dictionary = {}   ## the default tuning is a winnable store.
const LOSS_CFG: Dictionary = {
	"base_traffic": 4, "overhead": 2600, "start_cash": 14000, "growth_goal": 400000,
	"bankruptcy_floor": -6000, "bankruptcy_patience": 30, "max_debt": 6000,
	"base_catalogue_demand": 3, "catalogue_capacity": 5,
}

func _play(cfg: Dictionary) -> DeptStoreEngine:
	var e: DeptStoreEngine = DeptStoreEngine.new()
	e.setup(20260716, cfg)
	e.auto_play_to_end()
	return e

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- WIN reachable ---
	var w: DeptStoreEngine = _play(WIN_CFG)
	if w.outcome != DeptStoreEngine.WON:
		fails += 1
		notes.append("no-win(outcome=%d nw=%d/%d day=%d)" % [w.outcome, w.net_worth(), w.win_target, w.day])
	if w.net_worth() < w.win_target:
		fails += 1
		notes.append("win-below-target(%d<%d)" % [w.net_worth(), w.win_target])
	if w.day > w.max_days:
		fails += 1
		notes.append("win-past-cap(%d)" % w.day)

	# --- LOSS reachable (bankruptcy) ---
	var l: DeptStoreEngine = _play(LOSS_CFG)
	if l.outcome != DeptStoreEngine.LOST:
		fails += 1
		notes.append("no-loss(outcome=%d cash=%d nw=%d day=%d)" % [l.outcome, l.cash, l.net_worth(), l.day])
	if l.day > l.max_days:
		fails += 1
		notes.append("loss-past-cap(%d)" % l.day)

	# --- termination under MAX_DAYS for several seeds + policies ---
	var term_fail: int = 0
	for seed_value in [1, 7, 20260716, 55555, 99999]:
		for policy in ["balanced", "aggressive"]:
			var e: DeptStoreEngine = DeptStoreEngine.new()
			e.setup(seed_value, {"policy": policy})
			var final: int = e.auto_play_to_end()
			if final == DeptStoreEngine.ONGOING:
				term_fail += 1
			if e.day > e.max_days:
				term_fail += 1
	if term_fail != 0:
		fails += 1
		notes.append("non-terminating(%d)" % term_fail)

	# --- once terminal, ticking is a no-op (outcome stable, no further cash movement) ---
	var frozen_cash: int = w.cash
	var frozen_day: int = w.day
	var d0: int = w.tick_day()
	var d1: int = w.auto_play_step()
	if d0 != 0 or d1 != 0 or w.cash != frozen_cash or w.day != frozen_day or w.outcome != DeptStoreEngine.WON:
		fails += 1
		notes.append("terminal-not-frozen")

	print("DEBUG: progression_probe WIN(nw=%d/%d day=%d) LOSS(outcome=%d cash=%d day=%d) term_fail=%d notes=%s fails=%d => %s" % [
		w.net_worth(), w.win_target, w.day, l.outcome, l.cash, l.day, term_fail, str(notes), fails,
		("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
