extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the survival-crafting engine. Proves the same seed
## reproduces a BYTE-IDENTICAL run (identical FNV-1a checksum) mid-run and at the end; different
## seeds place a different world; and the survival AI plays the FULL LOOP — gathers, crafts an
## axe + a campfire, cooks/eats, keeps a fire lit through the cold nights — and SURVIVES all the
## days. Prints `DEBUG full_chk=<n>` so the harness can confirm the checksum matches across two
## SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 8642


func _run(seed_value: int) -> Dictionary:
	var e := SurvivalEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end()
	return {"chk": e.checksum(), "won": e.won, "day": e.day, "health": e.health,
		"axe": e.has_axe, "fires": e.fires.size(), "wood": int(e.inv.wood), "over": e.game_over}


func _partial(seed_value: int, ticks: int) -> int:
	var e := SurvivalEngine.new()
	e.setup(seed_value)
	for _i in range(ticks):
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
		push_error("different seeds produced the same world")

	var p1 := _partial(SEED_A, 500)
	var p2 := _partial(SEED_A, 500)
	if p1 != p2:
		ok = false
		push_error("partial run not deterministic")

	# playability: the AI crafted (axe + a campfire) and SURVIVED all the days with health left
	if not a1.over:
		ok = false
		push_error("run did not reach a terminal")
	if not a1.axe:
		ok = false
		push_error("AI never crafted an axe — the gather/craft loop may be broken")
	if int(a1.fires) < 1:
		ok = false
		push_error("AI never built a campfire — it cannot survive the night")
	if not a1.won:
		ok = false
		push_error("AI did not survive all %d days (died day %d, hp %.0f)" % [SurvivalEngine.SURVIVE_DAYS, int(a1.day), float(a1.health)])

	print("DEBUG full_chk=%d won=%s day=%d health=%.0f axe=%s fires=%d wood=%d" % [
		int(a1.chk), str(a1.won), int(a1.day), float(a1.health), str(a1.axe), int(a1.fires), int(a1.wood)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
