extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the tactics-SRPG engine. Proves the same seed
## reproduces a BYTE-IDENTICAL battle (identical FNV-1a checksum) both mid-battle and at
## the end — critically, WITH seeded hit/crit rolls in the mix; different seeds diverge;
## the map is seeded; and the two-team AI fights a REAL battle to a genuine WINNER (one
## army wiped out) rather than stalling. Prints `DEBUG full_chk=<n>` so the harness can
## confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 5150


func _full(seed_value: int) -> Dictionary:
	var e := SrpgEngine.new()
	e.setup(seed_value)
	var start_units := e.units.size()
	e.auto_play_to_end("both")
	return {"chk": e.checksum(), "round": e.round_no, "winner": e.winner, "over": e.game_over,
		"start_units": start_units, "end_units": e.units.size()}


func _partial(seed_value: int, phases: int) -> int:
	var e := SrpgEngine.new()
	e.setup(seed_value)
	for _i in range(phases):
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
		push_error("seed A not deterministic (%d != %d) — seeded rolls must replay" % [int(a1.chk), int(a2.chk)])

	var b1 := _full(SEED_B)
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds converged to the same battle")

	var p1 := _partial(SEED_A, 3)
	var p2 := _partial(SEED_A, 3)
	if p1 != p2:
		ok = false
		push_error("partial battle not deterministic")

	# seeded map: two seeds differ at the very first checksum
	var e1 := SrpgEngine.new()
	e1.setup(SEED_A)
	var e2 := SrpgEngine.new()
	e2.setup(SEED_B)
	if e1.checksum() == e2.checksum():
		ok = false
		push_error("map is not seeded (initial state identical across seeds)")

	# playability: combat actually happened (units died) and a side won
	if int(a1.end_units) >= int(a1.start_units):
		ok = false
		push_error("no combat resolved: no units died (start=%d end=%d)" % [int(a1.start_units), int(a1.end_units)])
	if not a1.over:
		ok = false
		push_error("battle did not end")
	if int(a1.winner) < 0:
		ok = false
		push_error("battle ended without a winner")

	print("DEBUG full_chk=%d end_round=%d winner=%d start_units=%d end_units=%d" % [
		int(a1.chk), int(a1.round), int(a1.winner), int(a1.start_units), int(a1.end_units)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
