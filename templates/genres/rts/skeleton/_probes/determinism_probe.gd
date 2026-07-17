extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the fixed-timestep RTS lockstep sim. Proves the
## same seed reproduces a BYTE-IDENTICAL match (identical FNV-1a checksum) both mid-match
## and at the end; different seeds diverge; world-gen is seeded; and the two-sided macro
## AI plays a REAL match to a genuine victory (a town hall is razed) rather than stalling
## to the tick cap. Prints `DEBUG full_chk=<n>` so the harness can also confirm the
## checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 4242


func _full(seed_value: int) -> Dictionary:
	var e := RtsEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("both")
	return {"chk": e.checksum(), "tick": e.tick, "winner": e.winner, "over": e.game_over}


func _partial(seed_value: int, ticks: int) -> int:
	var e := RtsEngine.new()
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

	var p1 := _partial(SEED_A, 500)
	var p2 := _partial(SEED_A, 500)
	if p1 != p2:
		ok = false
		push_error("partial match not deterministic")

	# seeded world-gen: two seeds differ at the very first tick's checksum
	var e1 := RtsEngine.new()
	e1.setup(SEED_A)
	var e2 := RtsEngine.new()
	e2.setup(SEED_B)
	if e1.checksum() == e2.checksum():
		ok = false
		push_error("world-gen is not seeded (initial state identical across seeds)")

	# the economy actually runs: a worker deposits minerals within a reasonable window
	var e3 := RtsEngine.new()
	e3.setup(SEED_A)
	var start_min: int = int(e3.minerals[0]) + int(e3.minerals[1])
	for _i in range(1200):
		e3.auto_step("both")
	var mid_min: int = int(e3.minerals[0]) + int(e3.minerals[1])
	# minerals were both spent (units/buildings made) AND earned — assert real activity:
	# at least one side built a barracks or fielded a soldier by now.
	var made_army := false
	for u in e3.units:
		if u.kind == "soldier":
			made_army = true
	var made_rax := false
	for b in e3.buildings:
		if b.kind == "barracks":
			made_rax = true
	if not (made_army or made_rax):
		ok = false
		push_error("economy stalled: no barracks and no soldier after 1200 ticks (start=%d mid=%d)" % [start_min, mid_min])

	# a full match reaches a genuine decision (a town hall razed), not the tick cap
	if not a1.over:
		ok = false
		push_error("match did not end")
	if int(a1.winner) < 0:
		ok = false
		push_error("match ended without a winner (stalled to a draw at the cap)")

	print("DEBUG full_chk=%d end_tick=%d winner=%d rax=%s army=%s" % [
		int(a1.chk), int(a1.tick), int(a1.winner), str(made_rax), str(made_army)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
