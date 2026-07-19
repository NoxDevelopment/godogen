extends Node
## _probes/progression_probe.gd
## PROGRESSION + LEARN probe: learning a style unlocks its moves; a technique
## upgrade increases that style's move damage; XP/level raises attributes; and the
## deterministic auto-play reaches a campaign WIN on the base difficulty AND a LOSS
## on a buffed difficulty, with the campaign always terminating.

func _move_dmg(style: String, kind: String, pts: int) -> float:
	return float(BrawlerEngine.STYLES[style]["moves"][kind]["damage"]) * (1.0 + BrawlerEngine.UPGRADE_DMG_STEP * float(pts))


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- learning a style unlocks it (its moves become usable) ---
	var e: BrawlerEngine = BrawlerEngine.new()
	e.setup(20260716, {"difficulty": "normal"})
	if e.knows_style("ghost_palm"):
		fails += 1
		notes.append("ghost-known-early")
	var learned: bool = e.learn_style("ghost_palm")
	if not learned or not e.knows_style("ghost_palm"):
		fails += 1
		notes.append("learn-failed")
	# learning the same style twice is rejected.
	if e.learn_style("ghost_palm"):
		fails += 1
		notes.append("double-learn")

	# --- a technique upgrade increases the move's damage ---
	var base_dmg: float = _move_dmg("ghost_palm", "heavy", 0)
	# grant a technique point (level up) then spend it on the learned style.
	e.award_xp(BrawlerEngine.XP_PER_LEVEL)  # level 1 needs 100 XP -> level 2 + points
	var pts_before: int = int(e.player["technique_points"])
	if pts_before <= 0:
		fails += 1
		notes.append("no-technique-points-after-level")
	var upgraded: bool = e.upgrade_technique("ghost_palm")
	if not upgraded:
		fails += 1
		notes.append("upgrade-failed")
	var new_pts: int = int((e.player["upgrades"] as Dictionary).get("ghost_palm", 0))
	var up_dmg: float = _move_dmg("ghost_palm", "heavy", new_pts)
	if not (up_dmg > base_dmg):
		fails += 1
		notes.append("upgrade-no-damage(%.2f<=%.2f)" % [up_dmg, base_dmg])
	# upgrading an UNKNOWN style is rejected + counted.
	var illegal_before: int = e.illegal_attempts
	if e.upgrade_technique("coiling_serpent"):
		fails += 1
		notes.append("upgraded-unknown")
	if e.illegal_attempts <= illegal_before:
		fails += 1
		notes.append("illegal-not-counted")

	# --- XP / level raises attributes ---
	var lp: BrawlerEngine = BrawlerEngine.new()
	lp.setup(20260716, {"difficulty": "normal"})
	var lvl0: int = int(lp.player["level"])
	var body0: int = int(lp.player["body"])
	var spirit0: int = int(lp.player["spirit"])
	lp.award_xp(BrawlerEngine.XP_PER_LEVEL * 3)  # several levels
	var leveled: bool = int(lp.player["level"]) > lvl0
	var attr_grew: bool = int(lp.player["body"]) > body0 or int(lp.player["spirit"]) > spirit0
	if not leveled:
		fails += 1
		notes.append("no-level")
	if not attr_grew:
		fails += 1
		notes.append("no-attr-growth")

	# --- auto-play WIN on base difficulty ---
	var win_e: BrawlerEngine = BrawlerEngine.new()
	win_e.setup(20260716, {"difficulty": "normal"})
	var win_res: String = win_e.run_campaign("skilled_counter")
	if win_res != "won":
		fails += 1
		notes.append("base-not-won(%s@enc%d)" % [win_res, win_e.encounter_index])
	if not win_e.campaign_over:
		fails += 1
		notes.append("win-not-terminated")

	# --- auto-play LOSS on a buffed difficulty ---
	var lose_e: BrawlerEngine = BrawlerEngine.new()
	lose_e.setup(20260716, {"difficulty": "buffed"})
	var lose_res: String = lose_e.run_campaign("skilled_counter")
	if lose_res != "lost":
		fails += 1
		notes.append("buffed-not-lost(%s)" % lose_res)
	if not lose_e.campaign_over:
		fails += 1
		notes.append("loss-not-terminated")

	print("DEBUG: progression_probe baseDmg=%.2f upDmg=%.2f lvl=%d winRes=%s loseRes=%s notes=%s fails=%d => %s" % [
		base_dmg, up_dmg, int(lp.player["level"]), win_res, lose_res, str(notes), fails,
		("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
