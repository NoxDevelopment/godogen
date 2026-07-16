extends Node
## _probes/determinism_probe.gd
## DETERMINISM probe — the same seed reproduces a BYTE-IDENTICAL run (identical FNV-1a
## checksum), both mid-run and at the end; a different seed diverges; and world-gen is
## seeded (initial checksums differ by seed). The DEBUG line prints `full_chk=<n>` so
## the run harness can additionally confirm the checksum is identical ACROSS TWO
## SEPARATE PROCESSES (byte-identical replays across process boundaries).

const SEED_A := 20260716
const SEED_B := 4242


func _full(seed_value: int, policy: String) -> int:
	var e: WarrenEngine = WarrenEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end(policy)
	return e.checksum()


func _partial(seed_value: int, steps: int, policy: String) -> int:
	var e: WarrenEngine = WarrenEngine.new()
	e.setup(seed_value)
	for _i in steps:
		if e.game_over:
			break
		e.auto_step(policy)
	return e.checksum()


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# same seed -> identical full-run checksum (in-process)
	var a: int = _full(SEED_A, "balanced")
	var b: int = _full(SEED_A, "balanced")
	if a != b:
		fails += 1
		notes.append("full(%d!=%d)" % [a, b])

	# same seed -> identical mid-run checksum
	var m1: int = _partial(SEED_B, 8, "balanced")
	var m2: int = _partial(SEED_B, 8, "balanced")
	if m1 != m2:
		fails += 1
		notes.append("mid(%d!=%d)" % [m1, m2])

	# a DIFFERENT seed diverges
	var c: int = _full(99999, "balanced")
	if c == a:
		fails += 1
		notes.append("seed-collision")

	# world-gen is seeded: initial-state checksums differ by seed
	var s1: WarrenEngine = WarrenEngine.new()
	s1.setup(111)
	var s2: WarrenEngine = WarrenEngine.new()
	s2.setup(222)
	if s1.checksum() == s2.checksum():
		fails += 1
		notes.append("worldgen-not-seeded")

	# reckless is deterministic too
	var r1: int = _full(SEED_A, "reckless")
	var r2: int = _full(SEED_A, "reckless")
	if r1 != r2:
		fails += 1
		notes.append("reckless(%d!=%d)" % [r1, r2])

	print("DEBUG: determinism_probe full_chk=%d mid_chk=%d diff_chk=%d notes=%s fails=%d => %s" % [
		a, m1, c, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
