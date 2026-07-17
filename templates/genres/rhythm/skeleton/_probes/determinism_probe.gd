extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the rhythm engine. Proves the same seed reproduces a
## BYTE-IDENTICAL play-through (identical FNV-1a checksum) mid-song and at the end; different
## seeds produce different CHARTS; the perfect auto-seat full-combos the whole chart (all
## Perfects, grade S); and — critically — the TIMING WINDOWS actually matter: a late seat
## scores strictly worse. Prints `DEBUG full_chk=<n>` so the harness can confirm the checksum
## matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 6060


func _run(seed_value: int, policy: String) -> Dictionary:
	var e := RhythmEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end(policy)
	return {"chk": e.checksum(), "score": e.score, "grade": e.grade(), "max_combo": e.max_combo,
		"perfect": int(e.counts.perfect), "good": int(e.counts.good), "miss": int(e.counts.miss),
		"total": e.total_notes(), "over": e.game_over}


func _partial(seed_value: int, ticks: int) -> int:
	var e := RhythmEngine.new()
	e.setup(seed_value)
	for _i in range(ticks):
		if e.game_over:
			break
		e.auto_step("perfect")
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _run(SEED_A, "perfect")
	var a2 := _run(SEED_A, "perfect")
	if int(a1.chk) != int(a2.chk):
		ok = false
		push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])

	var b1 := _run(SEED_B, "perfect")
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds produced the same chart")

	var p1 := _partial(SEED_A, 400)
	var p2 := _partial(SEED_A, 400)
	if p1 != p2:
		ok = false
		push_error("partial play not deterministic")

	# a real chart got played to the end
	if int(a1.total) <= 0:
		ok = false
		push_error("empty chart")
	if not a1.over:
		ok = false
		push_error("song did not finish")
	# the perfect seat full-combos: every note a Perfect, no misses, grade S
	if int(a1.perfect) != int(a1.total) or int(a1.miss) != 0:
		ok = false
		push_error("perfect seat did not full-combo (perfect=%d good=%d miss=%d total=%d)" % [int(a1.perfect), int(a1.good), int(a1.miss), int(a1.total)])
	if int(a1.max_combo) != int(a1.total):
		ok = false
		push_error("combo did not reach full chart (%d/%d)" % [int(a1.max_combo), int(a1.total)])
	if str(a1.grade) != "S":
		ok = false
		push_error("perfect play was not graded S (got %s)" % str(a1.grade))

	# timing windows matter: a late seat scores strictly worse than perfect
	var late := _run(SEED_A, "late4")
	if int(late.score) >= int(a1.score):
		ok = false
		push_error("late play did not score worse (late=%d perfect=%d) — windows not enforced" % [int(late.score), int(a1.score)])

	print("DEBUG full_chk=%d total=%d score=%d grade=%s combo=%d  late_score=%d late_miss=%d" % [
		int(a1.chk), int(a1.total), int(a1.score), str(a1.grade), int(a1.max_combo), int(late.score), int(late.miss)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
