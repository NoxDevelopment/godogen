extends Node
## _probes/hype_probe.gd
## HYPE probe (the heart of the sim): a new release's DEMAND spikes the week it drops
## then DECAYS exponentially over the following weeks toward its evergreen baseline
## (peak > mid > late, and late converges to baseline; demand is 0 before release).
## And — the decision that matters — the SAME number of copies stocked on a HOT new
## release captures MORE rentals than on a COLD catalogue title, because customers
## want the hot title far more.

const HOT: int = 14   ## "Blade Horizon" — new release, drops on day 21, baseline 2.8.
const COLD: int = 9   ## "Letters Home" — evergreen catalogue title, baseline 1.2.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	var e: VideoStoreEngine = VideoStoreEngine.new()
	e.setup(20260716, {})
	var baseline: float = VideoStoreEngine.TITLE_BASEPOP[HOT]
	var rel: int = VideoStoreEngine.TITLE_RELEASE[HOT]

	# --- 1) demand is 0 before release ---
	var before: float = e.demand(HOT, rel - 1)
	if before != 0.0:
		fails += 1
		notes.append("demand-before-release(%f)" % before)

	# --- 2) the hype curve: peak at release, decaying over the weeks toward baseline ---
	var peak: float = e.demand(HOT, rel)               # week 0 — the spike.
	var mid: float = e.demand(HOT, rel + 14)           # ~2 weeks later.
	var late: float = e.demand(HOT, rel + 70)          # ~10 weeks later.
	if not (peak > mid and mid > late):
		fails += 1
		notes.append("not-monotone-decay(peak=%.2f mid=%.2f late=%.2f)" % [peak, mid, late])
	if not (peak > baseline * 3.0):
		fails += 1
		notes.append("peak-not-a-spike(peak=%.2f base=%.2f)" % [peak, baseline])
	if not (late < baseline * 1.15 and late >= baseline):
		fails += 1
		notes.append("late-not-converged(late=%.2f base=%.2f)" % [late, baseline])
	# strictly monotone decreasing across the first several weeks.
	var prev: float = peak
	for w in range(1, 8):
		var cur: float = e.demand(HOT, rel + w * 7)
		if cur >= prev:
			fails += 1
			notes.append("non-decreasing-week(%d)" % w)
			break
		prev = cur

	# --- 3) same copies capture MORE rentals on a hot release than a cold catalogue title ---
	# Advance to the day the hot title is fresh (no stocking yet, so inventory is empty),
	# then stock EQUAL copies of the hot and the cold title and serve one heavy day.
	var s: VideoStoreEngine = VideoStoreEngine.new()
	s.setup(20260716, {"base_traffic": 150, "start_staff": 5, "damage_chance": 0.0})
	for _i in (rel + 1):
		s.tick_day()   # reach day rel+1 with an EMPTY store (nothing bought).
	if not s.is_new_release(HOT, s.day):
		fails += 1
		notes.append("hot-not-new-release(day=%d)" % s.day)
	var dem_hot: float = s.demand(HOT, s.day)
	var dem_cold: float = s.demand(COLD, s.day)
	if not (dem_hot > dem_cold * 2.0):
		fails += 1
		notes.append("hot-demand-not-dominant(%.2f vs %.2f)" % [dem_hot, dem_cold])

	var copies: int = 8
	s.buy_copies(HOT, copies)
	s.buy_copies(COLD, copies)
	# Serve several days and total each title's captured rentals (copies turn over).
	var hot_rentals: int = 0
	var cold_rentals: int = 0
	for _i in 6:
		s.tick_day()
		hot_rentals += s.title_day_rentals(HOT)
		cold_rentals += s.title_day_rentals(COLD)
	if hot_rentals <= cold_rentals:
		fails += 1
		notes.append("hot-not-more-rentals(hot=%d cold=%d)" % [hot_rentals, cold_rentals])

	print("DEBUG: hype_probe peak=%.2f mid=%.2f late=%.2f base=%.2f hot_rent=%d cold_rent=%d notes=%s fails=%d => %s" % [
		peak, mid, late, baseline, hot_rentals, cold_rentals, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
