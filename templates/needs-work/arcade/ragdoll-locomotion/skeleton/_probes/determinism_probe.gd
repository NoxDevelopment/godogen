extends Node
## _probes/determinism_probe.gd
## DETERMINISM probe: the same seed + the same canned muscle-input sequence yields
## a BYTE-IDENTICAL body-state checksum (FNV-1a over quantised positions +
## velocities), both mid-run and at the end; a DIFFERENT input sequence diverges.
## The printed CANON checksum is stable across separate processes (the build
## harness runs this twice and compares the CANON= value), proving cross-process
## reproducibility.

func _run_canned(seed_value: int, which: String, steps: int) -> int:
	var e: RagdollEngine = RagdollEngine.new()
	e.setup(seed_value, {"preset": "normal"})
	e.run_policy_steps(which, steps)
	return e.body_checksum()


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- same seed + same canned input -> identical mid-run checksum ---
	var a: int = _run_canned(20260716, "walk", 800)
	var b: int = _run_canned(20260716, "walk", 800)
	if a != b:
		fails += 1
		notes.append("mid-mismatch(%d!=%d)" % [a, b])

	# --- same seed + same canned input -> identical FULL-run checksum ---
	var fa: RagdollEngine = RagdollEngine.new()
	fa.setup(4242, {"preset": "easy"})
	fa.run_policy("walk")
	var fb: RagdollEngine = RagdollEngine.new()
	fb.setup(4242, {"preset": "easy"})
	fb.run_policy("walk")
	if fa.run_checksum() != fb.run_checksum():
		fails += 1
		notes.append("full-mismatch(%d!=%d)" % [fa.run_checksum(), fb.run_checksum()])

	# --- a DIFFERENT input sequence diverges (same seed) ---
	var c: int = _run_canned(20260716, "fall", 800)
	if c == a:
		fails += 1
		notes.append("input-collision")

	# --- a DIFFERENT seed diverges under the same input (optional jitter is seeded) ---
	var j1: RagdollEngine = RagdollEngine.new()
	j1.setup(111, {"preset": "normal", "jitter": 3.0})
	j1.run_policy_steps("walk", 300)
	var j2: RagdollEngine = RagdollEngine.new()
	j2.setup(222, {"preset": "normal", "jitter": 3.0})
	j2.run_policy_steps("walk", 300)
	if j1.body_checksum() == j2.body_checksum():
		fails += 1
		notes.append("seed-jitter-collision")

	# The canonical cross-process value: a fixed seed + canned walk of 1000 steps.
	var canon: int = _run_canned(20260716, "walk", 1000)

	print("DEBUG: determinism_probe CANON=%d mid=%d full=%d diff=%d notes=%s fails=%d => %s" % [
		canon, a, fa.run_checksum(), c, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
