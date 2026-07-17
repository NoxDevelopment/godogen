extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the .io grow-arena engine. Proves the same seed reproduces
## a BYTE-IDENTICAL match (identical FNV-1a checksum) mid-match and at the end; different seeds
## place a different arena; and the grow AI plays a REAL match — swallowing objects to GROW well
## past the start size and score — to a decided winner. Prints `DEBUG full_chk=<n>` so the harness
## can confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 9753


func _run(seed_value: int) -> Dictionary:
	var e := DotIoEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end()
	var maxsize := 0.0
	for h in e.holes:
		maxsize = max(maxsize, float(h.size))
	return {"chk": e.checksum(), "winner": e.winner, "over": e.game_over, "tick": e.tick_no,
		"p_size": float(e.holes[0].size), "p_score": float(e.holes[0].score), "maxsize": maxsize}


func _partial(seed_value: int, ticks: int) -> int:
	var e := DotIoEngine.new()
	e.setup(seed_value)
	for _i in range(ticks):
		if e.game_over:
			break
		e.auto_step()
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _run(SEED_A)
	var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk):
		ok = false
		push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])

	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds produced the same arena")

	var p1 := _partial(SEED_A, 500)
	var p2 := _partial(SEED_A, 500)
	if p1 != p2:
		ok = false
		push_error("partial match not deterministic")

	# playability: the match reached time, a winner was decided, and holes actually GREW
	if not a1.over:
		ok = false
		push_error("match did not reach time")
	if int(a1.winner) < 0:
		ok = false
		push_error("no winner decided")
	if float(a1.maxsize) < DotIoEngine.HOLE_START * 2.0:
		ok = false
		push_error("no real growth (max size %.0f vs start %.0f) — swallowing may be broken" % [float(a1.maxsize), DotIoEngine.HOLE_START])

	print("DEBUG full_chk=%d winner=%d end_tick=%d player_size=%.0f player_score=%.0f max_size=%.0f" % [
		int(a1.chk), int(a1.winner), int(a1.tick), float(a1.p_size), float(a1.p_score), float(a1.maxsize)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
