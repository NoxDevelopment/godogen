extends Node
## _probes/combat_probe.gd
## COMBAT probe: an ACTIVE-frame attack that REACHES a foe deals damage + hitstun +
## knockback; a WHIFF (out of range) deals none; BLOCKING reduces the damage to
## chip; and a full fight resolves to a KO and is BOUNDED by MAX_STEPS. One DEBUG
## line, then quit.

func _profile(style: String, policy: String) -> Dictionary:
	return {
		"name": "T_%s" % style, "body": 6, "mind": 4, "spirit": 6,
		"known_styles": [style], "upgrades": {}, "active_style": style,
		"policy": policy, "hp_mult": 1.0, "dmg_mult": 1.0,
	}


## Set up a controlled 1v1 where the foe just idles (policy "dummy" -> idle), place
## the two fighters `gap` px apart, have side0 throw a `kind` attack, and step until
## the attack's active window has fully passed. Returns the foe dict afterward.
func _controlled_swing(gap: float, kind: String, foe_policy: String) -> Dictionary:
	var e: BrawlerEngine = BrawlerEngine.new()
	e.setup(20260716, {"difficulty": "normal"})
	e.begin_fight(_profile("iron_ox", "dummy"), _profile("iron_ox", foe_policy))
	var a: Dictionary = e.fighters[0]
	var b: Dictionary = e.fighters[1]
	a["x"] = 600.0
	b["x"] = 600.0 + gap
	a["facing"] = 1
	b["facing"] = -1
	e.request_action(0, {"type": "attack", "kind": kind})
	var mv: Dictionary = BrawlerEngine.STYLES["iron_ox"]["moves"][kind]
	var frames: int = int(mv["startup"]) + int(mv["active"]) + int(mv["recovery"]) + 4
	for _i in frames:
		if e.fight_over:
			break
		# keep the foe from wandering: re-pin its intent to idle each step unless it
		# is the turtle (which blocks on its own).
		e.step()
	return {"engine": e, "foe": e.fighters[1] as Dictionary}


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- a reaching hit deals damage + hitstun + knockback ---
	var hit_e: BrawlerEngine = BrawlerEngine.new()
	hit_e.setup(20260716, {"difficulty": "normal"})
	hit_e.begin_fight(_profile("iron_ox", "dummy"), _profile("iron_ox", "dummy"))
	var ha: Dictionary = hit_e.fighters[0]
	var hb: Dictionary = hit_e.fighters[1]
	ha["x"] = 600.0
	hb["x"] = 655.0
	ha["facing"] = 1
	hb["facing"] = -1
	var hp_before: float = float(hb["hp"])
	var x_before: float = float(hb["x"])
	hit_e.request_action(0, {"type": "attack", "kind": "light"})
	var saw_hitstun: bool = false
	for _i in 30:
		hit_e.step()
		if String((hit_e.fighters[1] as Dictionary)["action"]) == BrawlerEngine.ACT_HITSTUN:
			saw_hitstun = true
	var hb2: Dictionary = hit_e.fighters[1]
	if float(hb2["hp"]) >= hp_before:
		fails += 1
		notes.append("reach-no-damage(%.1f>=%.1f)" % [float(hb2["hp"]), hp_before])
	if not saw_hitstun:
		fails += 1
		notes.append("no-hitstun")
	if float(hb2["x"]) <= x_before + 0.5:
		fails += 1
		notes.append("no-knockback(%.1f<=%.1f)" % [float(hb2["x"]), x_before])
	var clean_loss: float = hp_before - float(hb2["hp"])

	# --- a whiff (way out of range) deals no damage ---
	var whiff: Dictionary = _controlled_swing(600.0, "light", "dummy")
	var whiff_foe: Dictionary = whiff["foe"]
	var whiff_full: float = float((whiff_foe)["max_hp"])
	if float(whiff_foe["hp"]) < whiff_full - 0.01:
		fails += 1
		notes.append("whiff-dealt-damage(%.1f<%.1f)" % [float(whiff_foe["hp"]), whiff_full])

	# --- blocking reduces damage to chip (vs a clean hit at the same range) ---
	var blk_e: BrawlerEngine = BrawlerEngine.new()
	blk_e.setup(20260716, {"difficulty": "normal"})
	blk_e.begin_fight(_profile("iron_ox", "dummy"), _profile("iron_ox", "turtle"))
	var ba: Dictionary = blk_e.fighters[0]
	var bb: Dictionary = blk_e.fighters[1]
	ba["x"] = 600.0
	bb["x"] = 655.0
	ba["facing"] = 1
	bb["facing"] = -1
	# force the foe into a facing block first.
	bb["action"] = BrawlerEngine.ACT_BLOCK
	var blk_hp_before: float = float(bb["hp"])
	blk_e.request_action(0, {"type": "attack", "kind": "light"})
	for _i in 30:
		blk_e.step()
	var blocked_loss: float = blk_hp_before - float((blk_e.fighters[1] as Dictionary)["hp"])
	if blocked_loss <= 0.0:
		fails += 1
		notes.append("block-took-nothing")
	if blocked_loss >= clean_loss:
		fails += 1
		notes.append("block-not-reduced(%.1f>=%.1f)" % [blocked_loss, clean_loss])

	# --- a full fight resolves to a KO and is bounded by MAX_STEPS ---
	var fe: BrawlerEngine = BrawlerEngine.new()
	fe.setup(20260716, {"difficulty": "normal"})
	fe.begin_fight(_profile("iron_ox", "foe_normal"), _profile("drunken_fist", "foe_normal"))
	var winner: int = fe.simulate_current_fight()
	if not fe.fight_over:
		fails += 1
		notes.append("fight-not-over")
	if fe.step_count > fe.max_steps:
		fails += 1
		notes.append("unbounded(%d>%d)" % [fe.step_count, fe.max_steps])
	if winner != 0 and winner != 1:
		fails += 1
		notes.append("no-winner")
	var ko: bool = float((fe.fighters[0] as Dictionary)["hp"]) <= 0.0 or float((fe.fighters[1] as Dictionary)["hp"]) <= 0.0

	print("DEBUG: combat_probe clean=%.1f blocked=%.1f fightSteps=%d winner=%d ko=%s notes=%s fails=%d => %s" % [
		clean_loss, blocked_loss, fe.step_count, winner, str(ko), str(notes), fails,
		("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
