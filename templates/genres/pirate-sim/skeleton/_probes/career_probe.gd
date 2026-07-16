extends Node
## _probes/career_probe.gd
## CAREER probe: the deterministic auto-play reaches a WIN (retire at/above the rank
## threshold) AND a LOSS (ship sunk with no reserves, and crew mutiny), and every
## career terminates under the day cap. Also checks actions are rejected after the end.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- WIN via the merchant/trade policy ---
	var win: PirateEngine = PirateEngine.new()
	win.setup(20260715, {"policy": "trade"})
	var wr: Dictionary = win.auto_play_to_end()
	if not bool(wr["won"]):
		fails += 1
		notes.append("trade-not-won(cause=%s rank=%d score=%d)" % [String(wr["cause"]), int(wr["rank"]), int(wr["score"])])
	if String(wr["cause"]) != "retired":
		fails += 1
		notes.append("win-cause=%s" % String(wr["cause"]))
	if int(wr["rank"]) < win.WIN_RANK_INDEX:
		fails += 1
		notes.append("win-rank=%d<%d" % [int(wr["rank"]), win.WIN_RANK_INDEX])
	if int(wr["day"]) > win.MAX_CAREER_DAYS:
		fails += 1
		notes.append("win-overcap")

	# --- LOSS via the reckless (sink) policy ---
	var rk: PirateEngine = PirateEngine.new()
	rk.setup(20260715, {"policy": "reckless"})
	var rr: Dictionary = rk.auto_play_to_end()
	if bool(rr["won"]):
		fails += 1
		notes.append("reckless-won")
	if String(rr["cause"]) != "sunk":
		fails += 1
		notes.append("reckless-cause=%s" % String(rr["cause"]))
	if int(rr["day"]) > rk.MAX_CAREER_DAYS:
		fails += 1
		notes.append("reckless-overcap")

	# --- LOSS via the neglect (mutiny) policy ---
	var ng: PirateEngine = PirateEngine.new()
	ng.setup(20260715, {"policy": "neglect"})
	var nr: Dictionary = ng.auto_play_to_end()
	if bool(nr["won"]):
		fails += 1
		notes.append("neglect-won")
	if String(nr["cause"]) != "mutiny":
		fails += 1
		notes.append("neglect-cause=%s" % String(nr["cause"]))
	if int(nr["day"]) > ng.MAX_CAREER_DAYS:
		fails += 1
		notes.append("neglect-overcap")

	# --- actions rejected after the career is over ---
	if not win.career_over:
		fails += 1
		notes.append("win-not-over")
	var before_illegal: int = win.illegal_attempts
	win.sail_to(1)
	win.buy("rum", 5)
	win.attack("sink")
	win.retire()
	if win.illegal_attempts <= before_illegal:
		fails += 1
		notes.append("post-end-not-rejected")

	print("DEBUG: career_probe win=%s(rank=%d,score=%d) reckless=%s neglect=%s notes=%s fails=%d => %s" % [
		String(wr["cause"]), int(wr["rank"]), int(wr["score"]), String(rr["cause"]), String(nr["cause"]),
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
