extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the turn-based 4X engine. Proves the same seed
## reproduces a BYTE-IDENTICAL game (identical FNV-1a checksum) both mid-game and at the
## end; different seeds diverge; the map is seeded; and the two-civ macro AI plays a REAL
## game — it eXpands (founds cities), eXploits (research completes), fights, and reaches a
## genuine WINNER — rather than doing nothing. Prints `DEBUG full_chk=<n>` so the harness
## can confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 8080


func _full(seed_value: int) -> Dictionary:
	var e := TbsEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("both")
	# tally activity for the playability assertions
	var max_cities: int = 0
	for civ in range(TbsEngine.N_CIVS):
		max_cities = maxi(max_cities, e.cities_of(civ).size())
	var max_tech: int = maxi(e.civ_techs[0].size(), e.civ_techs[1].size())
	return {"chk": e.checksum(), "turn": e.turn, "winner": e.winner, "over": e.game_over,
		"max_cities": max_cities, "max_tech": max_tech}


func _partial(seed_value: int, steps: int) -> int:
	var e := TbsEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
		if e.game_over:
			break
		e.auto_step("both")
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _full(SEED_A)
	var a2 := _full(SEED_A)
	if int(a1.chk) != int(a2.chk):
		ok = false
		push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])

	var b1 := _full(SEED_B)
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds converged to the same game")

	var p1 := _partial(SEED_A, 30)
	var p2 := _partial(SEED_A, 30)
	if p1 != p2:
		ok = false
		push_error("partial game not deterministic")

	# seeded map: two seeds differ at the very first checksum
	var e1 := TbsEngine.new()
	e1.setup(SEED_A)
	var e2 := TbsEngine.new()
	e2.setup(SEED_B)
	if e1.checksum() == e2.checksum():
		ok = false
		push_error("map is not seeded (initial state identical across seeds)")

	# playability: the AI actually eXpanded and researched
	if int(a1.max_cities) < 2:
		ok = false
		push_error("no expansion: no civ founded a second city (max_cities=%d)" % int(a1.max_cities))
	if int(a1.max_tech) < 1:
		ok = false
		push_error("no research completed (max_tech=%d)" % int(a1.max_tech))

	# a genuine decision
	if not a1.over:
		ok = false
		push_error("game did not end")
	if int(a1.winner) < 0:
		ok = false
		push_error("game ended without a winner")

	print("DEBUG full_chk=%d end_turn=%d winner=%d max_cities=%d max_tech=%d" % [
		int(a1.chk), int(a1.turn), int(a1.winner), int(a1.max_cities), int(a1.max_tech)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
