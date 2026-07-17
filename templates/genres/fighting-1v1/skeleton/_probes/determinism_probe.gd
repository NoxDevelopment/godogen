extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the fixed-timestep fighting engine. Proves the same
## seed reproduces a BYTE-IDENTICAL best-of-3 (identical FNV-1a checksum) both mid-match and
## at the end; different seeds diverge (seeded AI personalities); and the two-AI auto-play
## fights a REAL match — damage is dealt, at least one round is won, and the match reaches a
## genuine WINNER (2 rounds) — rather than stalling. Prints `DEBUG full_chk=<n>` so the
## harness can confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 9090


func _full(seed_value: int) -> Dictionary:
	var e := FightEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("both")
	return {"chk": e.checksum(), "frame": e.frame, "winner": e.winner, "over": e.game_over,
		"w0": int(e.wins[0]), "w1": int(e.wins[1]), "hp0": int(e.f[0].hp), "hp1": int(e.f[1].hp)}


func _partial(seed_value: int, frames: int) -> int:
	var e := FightEngine.new()
	e.setup(seed_value)
	for _i in range(frames):
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
		push_error("different seeds converged to the same match (AI personalities not seeded?)")

	var p1 := _partial(SEED_A, 400)
	var p2 := _partial(SEED_A, 400)
	if p1 != p2:
		ok = false
		push_error("partial match not deterministic")

	# a real match: rounds were actually won and the match has a winner (someone hit 2)
	if not a1.over:
		ok = false
		push_error("match did not end")
	if int(a1.winner) < 0:
		ok = false
		push_error("match ended without a winner")
	if int(a1.w0) + int(a1.w1) < 2:
		ok = false
		push_error("no real rounds resolved (wins %d-%d)" % [int(a1.w0), int(a1.w1)])
	if max(int(a1.w0), int(a1.w1)) < 2:
		ok = false
		push_error("winner did not take the best-of-3 (wins %d-%d)" % [int(a1.w0), int(a1.w1)])

	print("DEBUG full_chk=%d end_frame=%d winner=%d rounds=%d-%d" % [
		int(a1.chk), int(a1.frame), int(a1.winner), int(a1.w0), int(a1.w1)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
