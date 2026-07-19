extends Node
## DETERMINISM + PLAYABILITY probe for the adult-trainer (raiser) engine. Same seed →
## byte-identical raise (checksum) mid-run + at the end; different seeds drive different events; and
## the greedy trainer plays a REAL 24-week raise — training the target stat, keeping stamina/mood/
## money above floors, and courting affection — to a stat-gated ending. Also asserts the
## mature_content GATE stays OFF the whole run (SYSTEMS ONLY — no explicit content ships). Prints
## DEBUG full_chk=<n> for cross-process checks.
const SEED_A := 20260717
const SEED_B := 99
func _run(sv: int) -> Dictionary:
	var e := TrainerEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk": e.checksum(), "ending": e.ending, "wit": e.stat(TrainerEngine.TARGET_TRACK),
		"aff": e.affection, "total": e.stat_total(), "won": e.won, "mature": e.mature_content, "over": e.game_over}
func _partial(sv: int, n: int) -> int:
	var e := TrainerEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.game_over: break
		e.auto_step()
	return e.checksum()
func _ready() -> void:
	var ok := true
	var a1 := _run(SEED_A); var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk): ok = false; push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])
	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk): ok = false; push_error("different seeds produced the same raise")
	var p1 := _partial(SEED_A, 12); var p2 := _partial(SEED_A, 12)
	if p1 != p2: ok = false; push_error("partial run not deterministic")
	if not bool(a1.over): ok = false; push_error("raise did not end")
	if not bool(a1.won): ok = false; push_error("trainer missed the target ending (%s wit=%d aff=%.0f)" % [str(a1.ending), int(a1.wit), float(a1.aff)])
	if str(a1.ending) == "Burnout": ok = false; push_error("bad (Burnout) ending")
	if bool(a1.mature): ok = false; push_error("mature_content gate must stay OFF — this template ships SYSTEMS ONLY")
	print("DEBUG full_chk=%d ending=%s wit=%d aff=%d total=%d won=%s mature=%s" % [
		int(a1.chk), str(a1.ending), int(a1.wit), int(a1.aff), int(a1.total), str(a1.won), str(a1.mature)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
