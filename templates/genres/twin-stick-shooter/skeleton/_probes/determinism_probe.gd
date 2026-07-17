extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the fixed-timestep twin-stick shooter. Proves the
## same seed reproduces a BYTE-IDENTICAL run (identical FNV-1a checksum) both mid-run and at
## the end; different seeds diverge (seeded spawns); and the kite-and-fire auto-seat plays a
## REAL run — kills enemies, clears at least a couple of waves, and reaches a genuine terminal
## (a clear or a death) rather than stalling. Prints `DEBUG full_chk=<n>` so the harness can
## confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 1212


func _full(seed_value: int) -> Dictionary:
	var e := ShooterEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("kite")
	return {"chk": e.checksum(), "frame": e.frame, "won": e.won, "over": e.game_over,
		"wave": e.wave, "score": e.score}


func _partial(seed_value: int, frames: int) -> int:
	var e := ShooterEngine.new()
	e.setup(seed_value)
	for _i in range(frames):
		if e.game_over:
			break
		e.auto_step("kite")
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
		push_error("different seeds converged to the same run")

	var p1 := _partial(SEED_A, 300)
	var p2 := _partial(SEED_A, 300)
	if p1 != p2:
		ok = false
		push_error("partial run not deterministic")

	# playability: the seat actually killed things (scored) and cleared past the first wave
	if int(a1.score) <= 0:
		ok = false
		push_error("no kills — score stayed 0 (shooting/collision broken)")
	if int(a1.wave) < 2:
		ok = false
		push_error("did not clear the first wave (wave=%d)" % int(a1.wave))
	if not a1.over:
		ok = false
		push_error("run did not reach a terminal")

	print("DEBUG full_chk=%d end_frame=%d won=%s wave=%d score=%d" % [
		int(a1.chk), int(a1.frame), str(a1.won), int(a1.wave), int(a1.score)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
