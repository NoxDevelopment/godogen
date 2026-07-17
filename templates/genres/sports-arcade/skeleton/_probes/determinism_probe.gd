extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the fixed-timestep arcade-soccer engine. Proves the same
## seed reproduces a BYTE-IDENTICAL match (identical FNV-1a checksum) mid-match and at the end;
## different seeds diverge (seeded kickoff jitter + aggression); and the two-AI match actually
## plays SOCCER — goals are scored — reaching full time with a result. Prints `DEBUG full_chk=<n>`
## so the harness can confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 5454


func _full(seed_value: int) -> Dictionary:
	var e := SportsEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("both")
	return {"chk": e.checksum(), "s0": int(e.score[0]), "s1": int(e.score[1]), "winner": e.winner,
		"over": e.game_over, "tick": e.tick_no}


func _partial(seed_value: int, ticks: int) -> int:
	var e := SportsEngine.new()
	e.setup(seed_value)
	for _i in range(ticks):
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
		push_error("different seeds converged to the same match")

	var p1 := _partial(SEED_A, 900)
	var p2 := _partial(SEED_A, 900)
	if p1 != p2:
		ok = false
		push_error("partial match not deterministic")

	# playability: the match reached full time AND real soccer happened (goals were scored)
	if not a1.over:
		ok = false
		push_error("match did not reach full time")
	if int(a1.s0) + int(a1.s1) < 1:
		ok = false
		push_error("no goals scored across the whole match — possession/shooting/goal-detect may be broken")

	print("DEBUG full_chk=%d final=%d-%d winner=%d end_tick=%d" % [
		int(a1.chk), int(a1.s0), int(a1.s1), int(a1.winner), int(a1.tick)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
