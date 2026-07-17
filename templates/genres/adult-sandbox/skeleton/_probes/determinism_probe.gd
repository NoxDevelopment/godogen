extends Node
## DETERMINISM + PLAYABILITY probe for the adult-sandbox (open life/relationship sandbox) engine.
## Same seed → byte-identical run (checksum) mid-run + at the end; different seeds lay out different
## NPC schedules (→ different relationship outcomes); and the greedy resident plays a REAL run —
## navigating the map, working, resting, keeping fit, and deepening multi-NPC relationships to their
## stages — to the end of the sandbox. Also asserts the mature_content GATE stays OFF the whole run
## (SYSTEMS ONLY — no explicit content ships). Prints DEBUG full_chk=<n> for cross-process checks.
const SEED_A := 20260717
const SEED_B := 99
func _run(sv: int) -> Dictionary:
	var e := SandboxEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk": e.checksum(), "day": e.day, "prog": e.progress(), "best": e.stage_name(e.max_rel()),
		"maxrel": e.max_rel(), "won": e.won, "mature": e.mature_content, "over": e.game_over}
func _partial(sv: int, n: int) -> int:
	var e := SandboxEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.game_over: break
		e.ai_step()
	return e.checksum()
func _ready() -> void:
	var ok := true
	var a1 := _run(SEED_A); var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk): ok = false; push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])
	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk): ok = false; push_error("different seeds produced the same run")
	var p1 := _partial(SEED_A, 30); var p2 := _partial(SEED_A, 30)
	if p1 != p2: ok = false; push_error("partial run not deterministic")
	if not bool(a1.over): ok = false; push_error("sandbox did not end")
	if not bool(a1.won): ok = false; push_error("resident never reached a Close relationship (best %s)" % str(a1.best))
	if float(a1.maxrel) < 70.0: ok = false; push_error("top relationship too low (%.0f)" % float(a1.maxrel))
	if bool(a1.mature): ok = false; push_error("mature_content gate must stay OFF — this template ships SYSTEMS ONLY")
	print("DEBUG full_chk=%d day=%d progress=%d best=%s maxrel=%d won=%s mature=%s" % [
		int(a1.chk), int(a1.day), int(a1.prog), str(a1.best), int(a1.maxrel), str(a1.won), str(a1.mature)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
