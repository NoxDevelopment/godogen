extends Node
## _probes/determinism_probe.gd
## DETERMINISM probe: the same seed + the same scripted input/AI sequence yields a
## BYTE-IDENTICAL checksum (FNV-1a over quantised fighter state), both mid-fight and
## across a whole auto-played campaign; a DIFFERENT input sequence diverges; and a
## different seed under AI jitter diverges. The printed CANON checksum is stable
## across separate processes (the build harness runs this twice and compares CANON).

func _profile(style: String, policy: String) -> Dictionary:
	return {
		"name": "D_%s" % style, "body": 8, "mind": 5, "spirit": 7,
		"known_styles": ["drunken_fist", "iron_ox", "willow_guard", "steel_crane"],
		"upgrades": {}, "active_style": style, "policy": policy,
		"hp_mult": 1.0, "dmg_mult": 1.0,
	}


## Run a canned fight: side0 issues actions[step % n] each step, side1 is a fixed
## AI foe, for up to `steps` steps. Returns the mid-fight checksum.
func _run_scripted(seed_value: int, actions: Array, steps: int) -> int:
	var e: BrawlerEngine = BrawlerEngine.new()
	e.setup(seed_value, {"difficulty": "normal"})
	e.begin_fight(_profile("drunken_fist", "human"), _profile("iron_ox", "foe_normal"))
	for i in steps:
		if e.fight_over:
			break
		var act: Dictionary = actions[i % actions.size()]
		e.request_action(0, act)
		e.step()
	return e.fight_checksum()


## A full auto-played campaign checksum for a given seed + difficulty.
func _run_campaign_ck(seed_value: int, difficulty: String) -> int:
	var e: BrawlerEngine = BrawlerEngine.new()
	e.setup(seed_value, {"difficulty": difficulty})
	e.run_campaign("skilled_counter")
	return e.run_checksum()


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	var script_a: Array = [
		{"type": "walk", "dir": 1}, {"type": "attack", "kind": "light"},
		{"type": "block"}, {"type": "attack", "kind": "heavy"},
	]
	var script_b: Array = [
		{"type": "walk", "dir": 1}, {"type": "attack", "kind": "special"},
		{"type": "idle"}, {"type": "block"},
	]

	# --- same seed + same script -> identical mid-fight checksum ---
	var m1: int = _run_scripted(20260716, script_a, 600)
	var m2: int = _run_scripted(20260716, script_a, 600)
	if m1 != m2:
		fails += 1
		notes.append("mid-mismatch(%d!=%d)" % [m1, m2])

	# --- a DIFFERENT script diverges (same seed) ---
	var m3: int = _run_scripted(20260716, script_b, 600)
	if m3 == m1:
		fails += 1
		notes.append("script-collision")

	# --- same seed + same difficulty -> identical FULL-campaign checksum ---
	var c1: int = _run_campaign_ck(4242, "normal")
	var c2: int = _run_campaign_ck(4242, "normal")
	if c1 != c2:
		fails += 1
		notes.append("campaign-mismatch(%d!=%d)" % [c1, c2])

	# --- a different difficulty (buffed) diverges ---
	var c3: int = _run_campaign_ck(4242, "buffed")
	if c3 == c1:
		fails += 1
		notes.append("difficulty-collision")

	# --- AI jitter: different seeds diverge under the same script ---
	var ja: BrawlerEngine = BrawlerEngine.new()
	ja.setup(111, {"difficulty": "normal", "ai_jitter": 22.0})
	ja.begin_fight(_profile("drunken_fist", "foe_normal"), _profile("iron_ox", "foe_normal"))
	for _i in 300:
		if ja.fight_over:
			break
		ja.step()
	var jb: BrawlerEngine = BrawlerEngine.new()
	jb.setup(222, {"difficulty": "normal", "ai_jitter": 22.0})
	jb.begin_fight(_profile("drunken_fist", "foe_normal"), _profile("iron_ox", "foe_normal"))
	for _i in 300:
		if jb.fight_over:
			break
		jb.step()
	if ja.fight_checksum() == jb.fight_checksum():
		fails += 1
		notes.append("seed-jitter-collision")

	# The canonical cross-process value: a fixed seed + canned scripted fight.
	var canon: int = _run_scripted(20260716, script_a, 800)

	print("DEBUG: determinism_probe CANON=%d mid=%d campaign=%d diffScript=%d fails=%d => %s" % [
		canon, m1, c1, m3, fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
