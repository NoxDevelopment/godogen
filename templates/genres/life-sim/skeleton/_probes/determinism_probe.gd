extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the life-sim engine. Proves the same seed reproduces a
## BYTE-IDENTICAL life (identical FNV-1a checksum) mid-run and at the end; different seeds diverge
## (seeded start jitter + daily events); and the routine AI lives a FUNCTIONAL life over several
## weeks — earning money from a job, building a best-friend relationship, keeping needs up (rare
## collapses), and reaching the ASPIRATION goal. Prints `DEBUG full_chk=<n>` so the harness can
## confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 7171
const DAYS := 26


func _run(seed_value: int) -> Dictionary:
	var e := LifeEngine.new()
	e.setup(seed_value)
	e.auto_play_days(DAYS)
	return {"chk": e.checksum(), "money": e.money, "day": e.day, "friend": e.best_friend(),
		"aspire": e.aspiration, "collapses": e.collapses, "mood": e.mood}


func _partial(seed_value: int, days: int) -> int:
	var e := LifeEngine.new()
	e.setup(seed_value)
	e.auto_play_days(days)
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
		push_error("different seeds converged to the same life")

	var p1 := _partial(SEED_A, 5)
	var p2 := _partial(SEED_A, 5)
	if p1 != p2:
		ok = false
		push_error("partial run not deterministic")

	# playability: the AI earned money (worked), grew a best friend, stayed mostly stable, and
	# reached the aspiration goal
	if int(a1.money) <= 0:
		ok = false
		push_error("no money earned — the job loop may be broken")
	if float(a1.friend) < 40.0:
		ok = false
		push_error("no real friendship grew (best=%.0f)" % float(a1.friend))
	if int(a1.collapses) > 6:
		ok = false
		push_error("too many exhaustion collapses (%d) — the AI can't keep up" % int(a1.collapses))
	if not a1.aspire:
		ok = false
		push_error("aspiration not reached (money=%d friend=%.0f) in %d days" % [int(a1.money), float(a1.friend), DAYS])

	print("DEBUG full_chk=%d day=%d money=%d best_friend=%.0f aspire=%s collapses=%d mood=%.0f" % [
		int(a1.chk), int(a1.day), int(a1.money), float(a1.friend), str(a1.aspire), int(a1.collapses), float(a1.mood)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
