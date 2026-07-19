extends Node
## res://_probes/rules_probe.gd
## Headless self-test for the FF rules core (Phase-1 verify gate). Proves, in one
## deterministic seeded process:
##   1. Provisions default is 10 (GDD §3) — the ruleset is the single source.
##   2. The never-exceed-Initial cap is enforced in the ENGINE clamp (IFState),
##      not a parallel store: apply_delta AND a raw state.add_attr both stop at cap.
##   3. apply_delta triggers death when STAMINA reaches 0.
##   4. one 2d6+SKILL combat round resolves the wound math correctly.
##   5. FF checks are MIGRATED onto the ruleset's resolutionRules via IFResolver:
##      test-luck ALWAYS spends one LUCK (pass or fail, floored at 0) and its
##      Lucky/Unlucky banding matches canonical roll-under+doubles; test-skill /
##      test-stamina (the generic `test` rule) are NOT consumed and band correctly.
##   6. Potion of Fortune is the sanctioned exception that raises Initial LUCK.
## Prints one `DEBUG: ... fails=N` line and quits.

const RULESET_PATH := "res://addons/nox_if_engine/data/rulesets/ff-2d6.json"


func _ready() -> void:
	var fails := 0
	var notes: Array[String] = []

	var ruleset := IFRuleset.from_file(RULESET_PATH)
	if ruleset.id != "ff-2d6":
		fails += 1
		notes.append("ruleset_load")

	# --- 1) Provisions default 10 (GDD §3) ------------------------------------
	var s := FFAdventureSheet.new()
	var d := IFDice.new(); d.set_seed(12345)
	s.roll_up(ruleset, d)
	var prov_ok := s.provisions == 10
	if not prov_ok:
		fails += 1
	notes.append("provisions[%d ok=%s]" % [s.provisions, prov_ok])

	# --- 2) cap enforced IN THE ENGINE CLAMP (unified store) ------------------
	var skill_init := s.init_of("skill")
	# via apply_delta (the funnel): +5 over cap -> clipped, overflow reported.
	var cap_report := s.apply_delta({"skill": 5})
	var cap_ok := s.cur("skill") == skill_init and int(cap_report.overflow.get("skill", 0)) == 5
	# via a RAW state write: the clamp lives in IFState, so the sheet's cap holds
	# even when something writes the attribute directly (proves ONE store/one clamp).
	s.state.add_attr("SKILL", 5)
	var engine_clamp_ok := int(s.state.get_attr("SKILL")) == skill_init
	if not (cap_ok and engine_clamp_ok):
		fails += 1
	notes.append("cap[cur=%d init=%d overflow=%d apply_ok=%s engine_ok=%s]" % [
		s.cur("skill"), skill_init, int(cap_report.overflow.get("skill", 0)), cap_ok, engine_clamp_ok])

	# Wound then partial heal stays under cap.
	s.apply_delta({"skill": -3})
	var heal_report := s.apply_delta({"skill": 10})
	var heal_ok := s.cur("skill") == skill_init and int(heal_report.overflow.get("skill", 0)) == 7
	if not heal_ok:
		fails += 1
	notes.append("heal_cap[cur=%d ok=%s]" % [s.cur("skill"), heal_ok])

	# --- 3) death at STAMINA 0 ------------------------------------------------
	var stam_init := s.init_of("stamina")
	var death_report := s.apply_delta({"stamina": -(stam_init + 10)})
	var death_ok := s.cur("stamina") == 0 and bool(death_report.died) and s.is_dead()
	if not death_ok:
		fails += 1
	notes.append("death[stam=%d died=%s ok=%s]" % [s.cur("stamina"), s.is_dead(), death_ok])

	# --- 4) one 2d6+SKILL combat round ---------------------------------------
	var fighter := FFAdventureSheet.new()
	var fd := IFDice.new(); fd.set_seed(999)
	fighter.roll_up(ruleset, fd)
	var fighter_skill := fighter.cur("skill")
	var enemy := FFCombat.make_enemy("Test Drone", 6, 8)
	var predict := IFDice.new(); predict.set_seed(4242)
	var pf := predict.roll("2d6")
	var ef := predict.roll("2d6")
	var exp_player := int(pf.total) + fighter_skill
	var exp_enemy := int(ef.total) + 6
	var enemy_stam_before := int(enemy.stamina)
	var pstam_before := fighter.cur("stamina")

	var round_dice := IFDice.new(); round_dice.set_seed(4242)
	var res := FFCombat.attack_round(fighter, enemy, round_dice)
	var totals_ok := int(res.player_total) == exp_player and int(res.enemy_total) == exp_enemy
	var wound_ok := false
	if exp_player > exp_enemy:
		wound_ok = str(res.outcome) == "player_wounds" \
			and int(enemy.stamina) == enemy_stam_before - 2 \
			and fighter.cur("stamina") == pstam_before
	elif exp_enemy > exp_player:
		wound_ok = str(res.outcome) == "enemy_wounds" \
			and fighter.cur("stamina") == pstam_before - 2 \
			and int(enemy.stamina) == enemy_stam_before
	else:
		wound_ok = str(res.outcome) == "tie" \
			and int(enemy.stamina) == enemy_stam_before \
			and fighter.cur("stamina") == pstam_before
	if not (totals_ok and wound_ok):
		fails += 1
	notes.append("combat[you=%d foe=%d -> %s totals_ok=%s wound_ok=%s]" % [
		exp_player, exp_enemy, str(res.outcome), totals_ok, wound_ok])

	# --- 5) MIGRATED checks via IFResolver (test-luck / test-skill / test-stamina)
	var luck_rule := ruleset.rule("test-luck")
	var test_rule := ruleset.rule("test")
	var luck_ok := true
	var band_ok := true
	var saw_lucky := false
	var saw_unlucky := false
	for seed_i in range(1, 60):
		var st := IFState.new(ruleset)
		var rd := IFDice.new(); rd.set_seed(seed_i)
		st.init_sheet(ruleset.generate_sheet(rd))
		var lres_dice := IFDice.new(); lres_dice.set_seed(seed_i * 7 + 1)
		var lresolver := IFResolver.new(ruleset, lres_dice)
		var before := int(st.get_attr("LUCK"))
		var r := lresolver.resolve(luck_rule, st)
		# always -1 LUCK (floored at 0) via the rule's postEffect
		if int(st.get_attr("LUCK")) != maxi(before - 1, 0):
			luck_ok = false
		# banding matches canonical roll-under + doubles crit
		var faces: Array = r.faces
		var total := int(r.total)
		var crit_lucky := faces.size() == 2 and int(faces[0]) == 1 and int(faces[1]) == 1
		var crit_unlucky := faces.size() == 2 and int(faces[0]) == 6 and int(faces[1]) == 6
		var expect_lucky := crit_lucky or (not crit_unlucky and total <= before)
		if (str(r.band) == "success") != expect_lucky:
			band_ok = false
		if str(r.band) == "success": saw_lucky = true
		else: saw_unlucky = true
	# floor-at-0
	var zst := IFState.new(ruleset)
	var zd := IFDice.new(); zd.set_seed(3)
	zst.init_sheet(ruleset.generate_sheet(zd))
	zst.set_attr("LUCK", 0)
	var zresolver := IFResolver.new(ruleset, IFDice.new())
	zresolver.resolve(luck_rule, zst)
	var floor_ok := int(zst.get_attr("LUCK")) == 0
	# test-skill / test-stamina: NOT consumed + correct band
	var noconsume_ok := true
	var testband_ok := true
	for seed_j in range(1, 40):
		var st2 := IFState.new(ruleset)
		var rd2 := IFDice.new(); rd2.set_seed(seed_j * 13 + 5)
		st2.init_sheet(ruleset.generate_sheet(rd2))
		var tres_dice := IFDice.new(); tres_dice.set_seed(seed_j * 17 + 2)
		var tresolver := IFResolver.new(ruleset, tres_dice)
		for stat_key in ["SKILL", "STAMINA"]:
			var before_v := int(st2.get_attr(stat_key))
			var tr := tresolver.resolve(test_rule, st2, {"attr": stat_key})
			if int(st2.get_attr(stat_key)) != before_v:
				noconsume_ok = false   # a test must not spend the attribute
			var f: Array = tr.faces
			var t := int(tr.total)
			var cs := f.size() == 2 and int(f[0]) == 1 and int(f[1]) == 1
			var cf := f.size() == 2 and int(f[0]) == 6 and int(f[1]) == 6
			var expect := cs or (not cf and t <= before_v)
			if (str(tr.band) == "success") != expect:
				testband_ok = false
	if not (luck_ok and band_ok and saw_lucky and saw_unlucky and floor_ok and noconsume_ok and testband_ok):
		fails += 1
	notes.append("migrated[luck-1=%s band=%s lucky=%s unlucky=%s floor0=%s test_noconsume=%s test_band=%s]" % [
		luck_ok, band_ok, saw_lucky, saw_unlucky, floor_ok, noconsume_ok, testband_ok])

	# --- 6) Potion of Fortune raises Initial LUCK (sanctioned exception) ------
	var ps := FFAdventureSheet.new()
	var pd := IFDice.new(); pd.set_seed(77)
	ps.roll_up(ruleset, pd)
	var luck_init_before := ps.init_of("luck")
	ps.apply_delta({"luck": -2})   # spend some first
	ps.drink_potion()               # default potion is Fortune
	var fortune_ok := ps.init_of("luck") == luck_init_before + 1 \
		and ps.cur("luck") == luck_init_before + 1
	if not fortune_ok:
		fails += 1
	notes.append("fortune[init=%d->%d cur=%d ok=%s]" % [
		luck_init_before, ps.init_of("luck"), ps.cur("luck"), fortune_ok])

	print("DEBUG: ff-gamebook rules core — %s  fails=%d" % [" ".join(notes), fails])
	get_tree().quit(0 if fails == 0 else 1)
