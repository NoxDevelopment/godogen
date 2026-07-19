extends Node
## _probes/determinism_probe.gd
## DETERMINISM probe: the same seed reproduces a BYTE-IDENTICAL career (identical
## checksum over quantized state), both mid-career and at the end; a different seed
## diverges.

func _run(seed_value: int) -> int:
	var e: PirateEngine = PirateEngine.new()
	e.setup(seed_value, {"policy": "trade"})
	e.auto_play_to_end()
	return e.career_checksum()

func _run_n(seed_value: int, n: int) -> int:
	var e: PirateEngine = PirateEngine.new()
	e.setup(seed_value, {"policy": "reckless"})
	for _i in n:
		if e.career_over:
			break
		e.auto_step()
	return e.career_checksum()

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- same seed -> identical full-career checksum ---
	var a: int = _run(20260715)
	var b: int = _run(20260715)
	if a != b:
		fails += 1
		notes.append("full-mismatch(%d!=%d)" % [a, b])

	# --- same seed -> identical mid-career checksum (partial run) ---
	var m1: int = _run_n(4242, 5)
	var m2: int = _run_n(4242, 5)
	if m1 != m2:
		fails += 1
		notes.append("mid-mismatch(%d!=%d)" % [m1, m2])

	# --- a DIFFERENT seed diverges ---
	var c: int = _run(99999)
	if c == a:
		fails += 1
		notes.append("seed-collision")

	# --- initial-state checksums also differ by seed (world gen is seeded) ---
	var s1: PirateEngine = PirateEngine.new()
	s1.setup(111)
	var s2: PirateEngine = PirateEngine.new()
	s2.setup(222)
	if s1.career_checksum() == s2.career_checksum():
		fails += 1
		notes.append("worldgen-not-seeded")

	print("DEBUG: determinism_probe same=%d/%d diff=%d notes=%s fails=%d => %s" % [
		a, b, c, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
