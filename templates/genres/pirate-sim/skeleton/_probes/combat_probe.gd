extends Node
## _probes/combat_probe.gd
## SEA-COMBAT probe: broadsides deal damage, duels are bounded by the turn cap, both
## SINK and BOARD outcomes are reachable across matchups, shot types hit the right
## subsystem (round->hull, chain->sails, grape->crew), and a fixed matchup is
## deterministic.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []
	var outcomes: Dictionary = {}

	# --- run a spread of matchups; collect outcomes; check bounded + damage ---
	var e: PirateEngine = PirateEngine.new()
	e.setup(20260715)
	var tiers: Array = ["merchant", "sloop", "frigate", "man_o_war"]
	var stances: Array = ["sink", "cripple", "board"]
	for tier in tiers:
		for stance in stances:
			var enemy: Dictionary = e._make_enemy(String(tier), "Crown")
			var start_hull: float = float(enemy["hull"])
			var start_sails: float = float(enemy["sails"])
			var start_crew: int = int(enemy["crew"])
			var res: Dictionary = e.simulate_combat(enemy, String(stance))
			var oc: String = String(res["outcome"])
			outcomes[oc] = int(outcomes.get(oc, 0)) + 1
			if int(res["turns"]) > e.MAX_COMBAT_TURNS:
				fails += 1
				notes.append("unbounded(%s/%s=%d)" % [tier, stance, int(res["turns"])])
			# SOME damage must have been dealt — to hull, sails, OR crew (shot type
			# depends on the stance), on either the enemy or the player.
			var enemy_dmg: float = (start_hull - float(res["enemy"]["hull"])) \
				+ (start_sails - float(res["enemy"]["sails"])) \
				+ float(start_crew - int(res["enemy"]["crew"]))
			var player_dmg: float = float(e.ship["hull_max"]) - float(res["player"]["hull"])
			if enemy_dmg <= 0.0 and player_dmg <= 0.0:
				fails += 1
				notes.append("no-damage(%s/%s)" % [tier, stance])

	# a sink AND a boarding must both be reachable somewhere in the spread.
	var sink_reached: bool = int(outcomes.get("enemy_sunk", 0)) + int(outcomes.get("player_sunk", 0)) > 0
	var board_reached: bool = int(outcomes.get("boarding", 0)) > 0
	if not sink_reached:
		fails += 1
		notes.append("no-sink")
	if not board_reached:
		fails += 1
		notes.append("no-board")

	# --- shot types hit the right subsystem ---
	var e2: PirateEngine = PirateEngine.new()
	e2.setup(20260715)
	var t1: Dictionary = e2._make_enemy("frigate", "Empire")
	var t2: Dictionary = t1.duplicate(true)
	var t3: Dictionary = t1.duplicate(true)
	var shooter: Dictionary = {"cannons": 20, "gunnery": 2.5}
	e2._fire_broadside(shooter, t1, "round", e2.RANGE_SHORT, 0.0)
	e2._fire_broadside(shooter, t2, "chain", e2.RANGE_SHORT, 0.0)
	e2._fire_broadside(shooter, t3, "grape", e2.RANGE_SHORT, 0.0)
	if float(t1["hull"]) >= float(t1["hull_max"]):
		fails += 1
		notes.append("round-no-hull")
	if float(t2["sails"]) >= float(t2["sails_max"]):
		fails += 1
		notes.append("chain-no-sails")
	if int(t3["crew"]) >= int(t3["crew_max"]):
		fails += 1
		notes.append("grape-no-crew")

	# --- determinism: a fixed matchup replays identically ---
	var d1: PirateEngine = PirateEngine.new()
	d1.setup(20260715)
	var en1: Dictionary = d1._make_enemy("frigate", "Crown")
	var r1: Dictionary = d1.simulate_combat(en1, "sink")
	var d2: PirateEngine = PirateEngine.new()
	d2.setup(20260715)
	var en2: Dictionary = d2._make_enemy("frigate", "Crown")
	var r2: Dictionary = d2.simulate_combat(en2, "sink")
	if String(r1["outcome"]) != String(r2["outcome"]) or int(r1["turns"]) != int(r2["turns"]) \
		or int(round(float(r1["enemy"]["hull"]) * 100.0)) != int(round(float(r2["enemy"]["hull"]) * 100.0)):
		fails += 1
		notes.append("combat-nondeterministic")

	print("DEBUG: combat_probe outcomes=%s notes=%s fails=%d => %s" % [
		str(outcomes), str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
