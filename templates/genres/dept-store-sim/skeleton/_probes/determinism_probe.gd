extends Node
## _probes/determinism_probe.gd
## DETERMINISM probe: the same seed reproduces a BYTE-IDENTICAL store (identical FNV-1a
## checksum over quantised state), both mid-run and at the end; a DIFFERENT seed
## diverges; and world/setup state is itself seeded. The printed CANON= value is a
## fixed-seed full-run checksum that is STABLE ACROSS SEPARATE PROCESSES — the build
## harness runs this probe twice and compares CANON=, proving cross-process
## reproducibility.

func _run_to_end(seed_value: int) -> int:
	var e: DeptStoreEngine = DeptStoreEngine.new()
	e.setup(seed_value, {})
	e.auto_play_to_end()
	return e.state_checksum()

func _run_n(seed_value: int, n: int) -> int:
	var e: DeptStoreEngine = DeptStoreEngine.new()
	e.setup(seed_value, {"policy": "aggressive", "growth_goal": 5000000, "max_days": 5000})
	for _i in n:
		if e.outcome != DeptStoreEngine.ONGOING:
			break
		e.auto_play_step()
	return e.state_checksum()

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- same seed -> identical full-run checksum ---
	var a: int = _run_to_end(20260716)
	var b: int = _run_to_end(20260716)
	if a != b:
		fails += 1
		notes.append("full-mismatch(%d!=%d)" % [a, b])

	# --- same seed -> identical mid-run checksum (partial run) ---
	var m1: int = _run_n(4242, 60)
	var m2: int = _run_n(4242, 60)
	if m1 != m2:
		fails += 1
		notes.append("mid-mismatch(%d!=%d)" % [m1, m2])

	# --- a DIFFERENT seed diverges ---
	var c: int = _run_to_end(99999)
	if c == a:
		fails += 1
		notes.append("seed-collision")

	# --- initial-state checksums also differ by seed (world gen is seeded) ---
	var s1: DeptStoreEngine = DeptStoreEngine.new()
	s1.setup(111, {"growth_goal": 5000000, "max_days": 5000})
	for _i in 40:
		s1.auto_play_step()
	var s2: DeptStoreEngine = DeptStoreEngine.new()
	s2.setup(222, {"growth_goal": 5000000, "max_days": 5000})
	for _i in 40:
		s2.auto_play_step()
	if s1.state_checksum() == s2.state_checksum():
		fails += 1
		notes.append("worldgen-not-seeded")

	# The canonical cross-process value: a fixed seed, full deterministic auto-play.
	var canon: int = _run_to_end(20260716)

	print("DEBUG: determinism_probe CANON=%d same=%d/%d mid=%d/%d diff=%d notes=%s fails=%d => %s" % [
		canon, a, b, m1, m2, c, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
