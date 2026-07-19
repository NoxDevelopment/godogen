extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the idle-clicker engine. Proves the same seed
## reproduces a BYTE-IDENTICAL run (identical FNV-1a checksum) mid-run and at the end;
## different seeds diverge (the seeded golden-bonus schedule differs); and the greedy seat
## plays a REAL economy — cookies grow, generators + upgrades get bought, golden bonuses
## fire — reaching the ascension goal. Prints `DEBUG full_chk=<n>` so the harness can confirm
## the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 4141
const SIM_TICKS := 60 * 60 * 12     ## 12 minutes of sim


func _run(seed_value: int) -> Dictionary:
	var e := IdleEngine.new()
	e.setup(seed_value)
	e.auto_play_ticks(SIM_TICKS)
	var total_buildings := 0
	for c in e.counts:
		total_buildings += int(c)
	return {"chk": e.checksum(), "total": e.total_earned, "cookies": e.cookies,
		"buildings": total_buildings, "upgrades": e.bought.size(), "ascended": e.ascended, "cps": e.cps()}


func _partial(seed_value: int, n: int) -> int:
	var e := IdleEngine.new()
	e.setup(seed_value)
	e.auto_play_ticks(n)
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
		push_error("different seeds converged (golden schedule not seeded?)")

	var p1 := _partial(SEED_A, 3000)
	var p2 := _partial(SEED_A, 3000)
	if p1 != p2:
		ok = false
		push_error("partial run not deterministic")

	# playability: real economy — growth, buying, upgrades, and the ascension goal reached
	if float(a1.total) <= 0.0:
		ok = false
		push_error("no cookies earned")
	if int(a1.buildings) < 20:
		ok = false
		push_error("too few generators bought (%d)" % int(a1.buildings))
	if int(a1.upgrades) < 3:
		ok = false
		push_error("too few upgrades bought (%d)" % int(a1.upgrades))
	if not a1.ascended:
		ok = false
		push_error("ascension goal not reached (total=%.0f) — economy underpowered" % float(a1.total))

	print("DEBUG full_chk=%d total=%.0f cookies=%.0f cps=%.1f buildings=%d upgrades=%d ascended=%s" % [
		int(a1.chk), float(a1.total), float(a1.cookies), float(a1.cps),
		int(a1.buildings), int(a1.upgrades), str(a1.ascended)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
