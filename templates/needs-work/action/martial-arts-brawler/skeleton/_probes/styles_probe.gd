extends Node
## _probes/styles_probe.gd
## STYLES + MATCHUP probe: each of the >= 6 styles carries a 3-move set with real
## frame data; the matchup table is the genuine advantage triangle (fast>power>
## defensive>fast, with consistent extra spokes and NO mutual contradictions); the
## matchup multiplier measurably changes a controlled duel (the advantaged style
## leaves the foe with LESS HP than a disadvantaged style would, holding attributes
## + policy equal); and switching styles changes the available move set.

func _duel_profile(style: String) -> Dictionary:
	return {
		"name": "M_%s" % style, "body": 8, "mind": 4, "spirit": 8,
		"known_styles": [style], "upgrades": {}, "active_style": style,
		"policy": "foe_normal", "hp_mult": 1.0, "dmg_mult": 1.0,
	}


## Run a fixed-length spar of `player_style` vs a fixed foe; return the foe's
## remaining HP (lower = the player did more, i.e. a better matchup).
func _foe_hp_after(player_style: String, foe_style: String, steps: int) -> float:
	var e: BrawlerEngine = BrawlerEngine.new()
	e.setup(20260716, {"difficulty": "normal", "max_steps": steps})
	e.begin_fight(_duel_profile(player_style), _duel_profile(foe_style))
	for _i in steps:
		if e.fight_over:
			break
		e.step()
	var b: Dictionary = e.fighters[1]
	return maxf(0.0, float(b["hp"]))


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- every style has a 3-move set with real frame data ---
	var style_count: int = BrawlerEngine.STYLE_ORDER.size()
	if style_count < 6:
		fails += 1
		notes.append("too-few-styles(%d)" % style_count)
	for sid in BrawlerEngine.STYLE_ORDER:
		var moves: Array = BrawlerEngine.STYLES[sid]["moves"].values()
		if moves.size() != 3:
			fails += 1
			notes.append("%s-move-count(%d)" % [sid, moves.size()])
		for kind in BrawlerEngine.MOVE_KINDS:
			var mv: Dictionary = BrawlerEngine.STYLES[sid]["moves"][kind]
			if int(mv["startup"]) <= 0 or int(mv["active"]) <= 0 or int(mv["recovery"]) <= 0:
				fails += 1
				notes.append("%s-%s-frames" % [sid, kind])
			if float(mv["damage"]) <= 0.0 or float(mv["reach"]) <= 0.0:
				fails += 1
				notes.append("%s-%s-dmg-reach" % [sid, kind])

	# --- the matchup table is a consistent advantage relation (no A<->B mutual) ---
	var eng: BrawlerEngine = BrawlerEngine.new()
	eng.setup(1)
	# core triangle exactly as specified.
	if eng.matchup_multiplier("drunken_fist", "iron_ox") <= 1.0:   # fast beats power
		fails += 1
		notes.append("fast!>power")
	if eng.matchup_multiplier("iron_ox", "willow_guard") <= 1.0:   # power beats defensive
		fails += 1
		notes.append("power!>def")
	if eng.matchup_multiplier("willow_guard", "drunken_fist") <= 1.0:  # defensive beats fast
		fails += 1
		notes.append("def!>fast")
	# no mutual contradictions across all archetype pairs.
	for aa in BrawlerEngine.ARCHETYPES:
		for bb in BrawlerEngine.ARCHETYPES:
			if aa == bb:
				continue
			var ab: bool = (BrawlerEngine.BEATS[aa] as Array).has(bb)
			var ba: bool = (BrawlerEngine.BEATS[bb] as Array).has(aa)
			if ab and ba:
				fails += 1
				notes.append("mutual(%s,%s)" % [aa, bb])

	# --- the matchup MEASURABLY matters: countering power (fast) leaves the foe with
	#     less HP than a disadvantaged style (defensive) does, all else equal ---
	var foe: String = "iron_ox"  # power
	var counter_hp: float = _foe_hp_after("drunken_fist", foe, 900)   # fast beats power
	var bad_hp: float = _foe_hp_after("willow_guard", foe, 900)       # power beats defensive
	if not (counter_hp < bad_hp):
		fails += 1
		notes.append("matchup-cosmetic(counter=%.1f>=bad=%.1f)" % [counter_hp, bad_hp])

	# --- switching styles changes the available moves ---
	var s: BrawlerEngine = BrawlerEngine.new()
	s.setup(1)
	s.begin_fight(
		{"name": "P", "body": 6, "mind": 5, "spirit": 6,
			"known_styles": ["drunken_fist", "steel_crane"], "upgrades": {},
			"active_style": "drunken_fist", "policy": "dummy", "hp_mult": 1.0, "dmg_mult": 1.0},
		_duel_profile("iron_ox"))
	var before_ids: Array = []
	for mv in s.style_moves(String((s.fighters[0] as Dictionary)["active_style"])):
		before_ids.append(String((mv as Dictionary)["id"]))
	var switched: bool = s.switch_style(0, "steel_crane")
	var after_ids: Array = []
	for mv in s.style_moves(String((s.fighters[0] as Dictionary)["active_style"])):
		after_ids.append(String((mv as Dictionary)["id"]))
	if not switched:
		fails += 1
		notes.append("switch-rejected")
	if before_ids == after_ids:
		fails += 1
		notes.append("switch-same-moves")

	print("DEBUG: styles_probe styles=%d counterHP=%.1f badHP=%.1f switched=%s notes=%s fails=%d => %s" % [
		style_count, counter_hp, bad_hp, str(switched), str(notes), fails,
		("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
