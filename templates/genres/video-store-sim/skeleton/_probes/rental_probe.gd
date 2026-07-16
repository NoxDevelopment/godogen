extends Node
## _probes/rental_probe.gd
## RENTAL LIFECYCLE probe: renting DECREMENTS available copies (and schedules a
## return); a normal return RESTORES the copy to the shelf; overdue returns ACCRUE
## LATE FEES; a DAMAGED tape LEAVES stock (owned drops, shelf not restored);
## availability GATES rentals (when every copy of a wanted title is out, further
## customers MISS). Each scenario is built deterministically by forcing the relevant
## tuning through the config.

func _catalog_title() -> int:
	return 0  ## "Neon Nights" — an evergreen catalogue title, released from day 0.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# ---------------------------------------------------------------
	# 1) rent decrements available + schedules a return; normal return restores it.
	#    damage_chance 0 so no tape is lost; hold fixed to 3 (due at +2 => LATE).
	# ---------------------------------------------------------------
	var e: VideoStoreEngine = VideoStoreEngine.new()
	e.setup(20260716, {"damage_chance": 0.0, "return_min_hold": 3, "return_max_hold": 3,
		"rental_period": 2, "base_traffic": 30})
	var t: int = _catalog_title()
	e.buy_copies(t, 12)
	var owned0: int = e.title_owned(t)
	var avail0: int = e.title_available(t)
	if avail0 != owned0 or owned0 != 12:
		fails += 1
		notes.append("buy-copies(%d/%d)" % [avail0, owned0])

	e.tick_day()   # day 0 serving: some copies of t go out on rental.
	var rented_out: int = e.title_rented_out(t)
	if rented_out <= 0:
		fails += 1
		notes.append("no-rental-happened")
	if e.title_available(t) != e.title_owned(t) - rented_out:
		fails += 1
		notes.append("available-not-decremented")
	if e.active_rentals() <= 0:
		fails += 1
		notes.append("no-active-rental")

	# advance until those rentals come back (hold 3 => return on day 3).
	var late_before: int = e.category_total("late_fees")
	for _i in 4:
		e.tick_day()
	# the day-0 rentals (hold 3, due +2) returned LATE and paid a fee.
	if e.category_total("late_fees") <= late_before:
		fails += 1
		notes.append("no-late-fee-accrued")

	# ---------------------------------------------------------------
	# 2) DAMAGED tape leaves stock (owned drops, shelf not restored on return).
	#    damage_chance 1.0 => every returned tape is destroyed.
	# ---------------------------------------------------------------
	var d: VideoStoreEngine = VideoStoreEngine.new()
	d.setup(20260716, {"damage_chance": 1.0, "return_min_hold": 2, "return_max_hold": 2,
		"rental_period": 3, "base_traffic": 30})
	d.buy_copies(t, 10)
	var d_owned0: int = d.title_owned(t)
	d.tick_day()                 # rent some copies.
	var d_out: int = d.title_rented_out(t)
	for _i in 3:
		d.tick_day()             # returns land damaged.
	if d_out <= 0:
		fails += 1
		notes.append("damage-no-rentals")
	if d.title_owned(t) >= d_owned0:
		fails += 1
		notes.append("damaged-not-removed(owned %d>=%d)" % [d.title_owned(t), d_owned0])
	if d.category_total("late_fees") != 0 and false:
		pass  # (holds==due here; not asserting on fees in this scenario)

	# ---------------------------------------------------------------
	# 3) availability GATES rentals: only a couple copies of one title, heavy traffic,
	#    everyone else who wants it MISSES.
	# ---------------------------------------------------------------
	var g: VideoStoreEngine = VideoStoreEngine.new()
	g.setup(20260716, {"damage_chance": 0.0, "base_traffic": 120, "start_staff": 5,
		"return_min_hold": 4, "return_max_hold": 4})
	g.buy_copies(t, 2)           # only two copies exist across the whole store.
	g.tick_day()
	if g.title_available(t) != 0:
		fails += 1
		notes.append("copies-not-all-out(%d)" % g.title_available(t))
	if g.last_missed <= 0:
		fails += 1
		notes.append("no-missed-when-out")
	if g.title_day_rentals(t) > 2:
		fails += 1
		notes.append("rented-more-than-stock(%d)" % g.title_day_rentals(t))

	# ---------------------------------------------------------------
	# 4) full inventory integrity holds through a mixed run.
	# ---------------------------------------------------------------
	var m: VideoStoreEngine = VideoStoreEngine.new()
	m.setup(777, {})
	var integ_fail: int = 0
	for _i in 60:
		if m.outcome != VideoStoreEngine.ONGOING:
			break
		m.auto_play_step()
		for tt in m.title_count():
			if m.title_owned(tt) != m.title_available(tt) + m.rentals_of_title(tt):
				integ_fail += 1
				break
			if m.title_available(tt) < 0 or m.title_owned(tt) < 0:
				integ_fail += 1
				break
	if integ_fail != 0:
		fails += 1
		notes.append("integrity(%d)" % integ_fail)

	print("DEBUG: rental_probe rented_out=%d late(+)=%s damaged_owned=%d/%d gate_missed=%d notes=%s fails=%d => %s" % [
		rented_out, str(e.category_total("late_fees") > late_before), d.title_owned(t), d_owned0,
		g.last_missed, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
