extends Node
## _probes/determinism_probe.gd
## DETERMINISM probe — the same seed reproduces a BYTE-IDENTICAL run (identical FNV-1a
## checksum) both mid-run and at the end; different seeds diverge; and world-gen is
## seeded (initial checksums differ by seed). Prints `DEBUG full_chk=<n>` so the run
## harness can also confirm the checksum is identical across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 9931


func _full(seed_value: int) -> int:
	var e := RogueEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("greedy")
	return e.checksum()


func _partial(seed_value: int, steps: int) -> int:
	var e := RogueEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
		if e.game_over:
			break
		e.auto_step("greedy")
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _full(SEED_A)
	var a2 := _full(SEED_A)
	if a1 != a2:
		ok = false
		push_error("seed A not deterministic (%d != %d)" % [a1, a2])

	var b1 := _full(SEED_B)
	if a1 == b1:
		ok = false
		push_error("different seeds converged to the same run")

	var p1 := _partial(SEED_A, 40)
	var p2 := _partial(SEED_A, 40)
	if p1 != p2:
		ok = false
		push_error("partial run not deterministic")

	var e1 := RogueEngine.new()
	e1.setup(SEED_A)
	var e2 := RogueEngine.new()
	e2.setup(SEED_B)
	if e1.checksum() == e2.checksum():
		ok = false
		push_error("world-gen is not seeded (initial state identical across seeds)")

	# the run actually plays (reaches game_over) and produces log output
	var e3 := RogueEngine.new()
	e3.setup(SEED_A)
	e3.auto_play_to_end("greedy")
	if not e3.game_over:
		ok = false
		push_error("auto_play_to_end did not terminate")

	print("DEBUG full_chk=%d depth=%d turn=%d won=%s" % [a1, e3.depth, e3.turn, str(e3.won)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
