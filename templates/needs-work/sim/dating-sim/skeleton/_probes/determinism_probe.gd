extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the dating-sim engine. Proves the same seed reproduces a
## BYTE-IDENTICAL playthrough (identical FNV-1a checksum) mid-run and at the end; different seeds
## roll different characters/preferences; and the pursue-a-partner AI completes a ROUTE — raising
## the right stats, giving liked gifts, going on preferred dates, crossing the affection
## milestones, and CONFESSING. Also confirms the `mature_content` gating flag defaults OFF. Prints
## `DEBUG full_chk=<n>` so the harness can confirm the checksum matches across two SEPARATE
## PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 9182


func _run(seed_value: int) -> Dictionary:
	var e := DatingEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end()
	var max_aff := 0.0
	var max_stat := 0.0
	for c in e.chars:
		max_aff = max(max_aff, float(c.affection))
	for s in DatingEngine.STATS:
		max_stat = max(max_stat, float(e.stats[s]))
	return {"chk": e.checksum(), "route": e.route_done, "partner": e.partner, "day": e.day,
		"max_aff": max_aff, "max_stat": max_stat, "mature": e.mature_content, "over": e.game_over}


func _partial(seed_value: int, steps: int) -> int:
	var e := DatingEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
		if e.game_over:
			break
		e.auto_step()
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _run(SEED_A)
	var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk):
		ok = false
		push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])

	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds produced the same playthrough")

	var p1 := _partial(SEED_A, 8)
	var p2 := _partial(SEED_A, 8)
	if p1 != p2:
		ok = false
		push_error("partial run not deterministic")

	# playability: a route completed via a confession, stats were raised, and the gate is OFF
	if not a1.over:
		ok = false
		push_error("playthrough did not end")
	if not a1.route:
		ok = false
		push_error("no route completed (max affection %.0f) — the pursue loop may be broken" % float(a1.max_aff))
	if str(a1.partner) == "":
		ok = false
		push_error("route completed but no partner recorded")
	if float(a1.max_stat) < 30.0:
		ok = false
		push_error("stats were not raised (max %.0f)" % float(a1.max_stat))
	if bool(a1.mature):
		ok = false
		push_error("mature_content gate should default OFF but was ON")

	print("DEBUG full_chk=%d route=%s partner=%s day=%d max_aff=%.0f max_stat=%.0f mature_gate=%s" % [
		int(a1.chk), str(a1.route), str(a1.partner), int(a1.day), float(a1.max_aff), float(a1.max_stat), str(a1.mature)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
