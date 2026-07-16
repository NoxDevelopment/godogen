extends Node
## _probes/locomotion_probe.gd
## LOCOMOTION probe: the scripted QWOP walk policy actually WALKS — it advances the
## athlete's horizontal distance by a positive amount driven by stepping (feet
## leave + re-plant, NOT a frictionless slide), the motion is bounded to a
## physical speed (no teleport/launch), and on the EASY setting it reaches the WIN
## goal. Prints one DEBUG line, quits.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- 1) the walk policy advances a POSITIVE distance on the normal track ---
	var e: RagdollEngine = RagdollEngine.new()
	e.setup(20260716, {"preset": "normal"})
	var peak_speed: float = 0.0  # m/s of the hip, to prove it never teleports.
	var prev_x: float = e.px[RagdollEngine.N_HIP]
	for _s in 2400:
		if e.finished:
			break
		e.set_muscle_mask(e.policy_walk(e.step_count))
		e.step()
		var v: float = absf(e.px[RagdollEngine.N_HIP] - prev_x) / RagdollEngine.DT / RagdollEngine.PIXELS_PER_METER
		if v > peak_speed:
			peak_speed = v
		prev_x = e.px[RagdollEngine.N_HIP]
	var walked: float = e.best_distance
	if walked <= 1.0:
		fails += 1
		notes.append("no-forward-progress(%.2fm)" % walked)
	# real WALKING: a foot must have left the floor (a step), not skated the whole way.
	if not e.feet_lifted:
		fails += 1
		notes.append("no-step-detected")
	# physical speed cap: the hip never moves faster than the node speed limit
	# (proves the distance is walked, not launched/slid). 700 px/s = 7 m/s ceiling.
	if peak_speed > 7.5:
		fails += 1
		notes.append("teleport(%.1fm/s)" % peak_speed)

	# --- 2) the EASY setting is WINNABLE by the scripted policy ---
	var easy: RagdollEngine = RagdollEngine.new()
	easy.setup(20260716, {"preset": "easy"})
	var res: Dictionary = easy.run_policy("walk")
	if String(res["outcome"]) != "won":
		fails += 1
		notes.append("easy-not-won(%s@%.2fm)" % [String(res["outcome"]), float(res["best_distance"])])
	if float(res["best_distance"]) < float(res["goal_distance"]):
		fails += 1
		notes.append("easy-short-of-goal")
	# and the win took a realistic number of steps (a slide-to-win in a handful of
	# frames would betray sliding; real walking needs many strides).
	if int(res["steps"]) < 120:
		fails += 1
		notes.append("easy-win-too-fast(%d steps)" % int(res["steps"]))

	print("DEBUG: locomotion_probe normal_walk=%.2fm peak=%.1fm/s stepped=%s easy=%s@%.2fm(%dsteps) notes=%s fails=%d => %s" % [
		walked, peak_speed, e.feet_lifted, String(res["outcome"]), float(res["best_distance"]),
		int(res["steps"]), str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
