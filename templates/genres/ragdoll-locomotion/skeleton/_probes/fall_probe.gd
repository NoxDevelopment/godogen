extends Node
## _probes/fall_probe.gd
## FALL / LOSS probe: a policy that tips the athlete ends the run as a FALL (the
## head/shoulder hits the floor or the torso exceeds the tilt limit — LOSS is
## reachable), the run is BOUNDED by MAX_STEPS in every case (never an infinite
## stagger), and a run that never falls ends as a timeout at the cap. Prints one
## DEBUG line, quits.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- 1) the fall policy TOPPLES the athlete (a real fall outcome) ---
	# the "hard" preset runs with a weak balance reflex, so the tip policy defeats
	# it and the athlete goes down (head / neck / tilt).
	var f: RagdollEngine = RagdollEngine.new()
	f.setup(20260716, {"preset": "hard"})
	var res: Dictionary = f.run_policy("fall")
	if String(res["outcome"]) != "fell":
		fails += 1
		notes.append("did-not-fall(%s)" % String(res["outcome"]))
	if not f.is_lost():
		fails += 1
		notes.append("is_lost-false")
	if String(res["fall_reason"]) == "":
		fails += 1
		notes.append("no-fall-reason")

	# a fall is also reachable on the normal track with the balance reflex turned
	# down (confirms the head-down loss condition, not just a weak preset).
	var f2: RagdollEngine = RagdollEngine.new()
	f2.setup(4242, {"preset": "normal", "balance_gain": 0.0})
	var r2: Dictionary = f2.run_policy("fall")
	if String(r2["outcome"]) != "fell":
		fails += 1
		notes.append("normal-balance0-not-fall(%s)" % String(r2["outcome"]))

	# --- 2) MAX_STEPS bounds EVERY run — even a perfectly standing athlete (no
	#        input) terminates at the cap as a timeout, never loops forever. ---
	var stand: RagdollEngine = RagdollEngine.new()
	stand.setup(20260716, {"preset": "easy", "max_steps": 1500})
	var guard: int = 0
	while not stand.finished and guard < 100000:
		stand.set_muscle_mask(0)
		stand.step()
		guard += 1
	if not stand.finished:
		fails += 1
		notes.append("unbounded-stand")
	if stand.step_count > 1500:
		fails += 1
		notes.append("exceeded-max-steps(%d)" % stand.step_count)

	# a full walk run is likewise bounded (never exceeds its cap).
	var w: RagdollEngine = RagdollEngine.new()
	w.setup(20260716, {"preset": "normal", "max_steps": 3000})
	w.run_policy("walk")
	if w.step_count > 3000:
		fails += 1
		notes.append("walk-exceeded-cap(%d)" % w.step_count)

	print("DEBUG: fall_probe hard=%s(reason=%s,step=%d) normal_bal0=%s stand_bounded=%s(%d) notes=%s fails=%d => %s" % [
		String(res["outcome"]), String(res["fall_reason"]), int(res["steps"]),
		String(r2["outcome"]), stand.finished, stand.step_count,
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
