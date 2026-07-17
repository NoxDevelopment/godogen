extends Node
## DETERMINISM + PLAYABILITY probe for the adult-puzzle-dating (HuniePop-style match-3 → dating)
## engine. Same seed → byte-identical run (checksum) mid-run + at the end; different seeds fill a
## different board; and the greedy player plays a REAL run — matching preference-weighted tokens,
## buying gifts, and completing character routes — to a genuine terminal. Also asserts the
## mature_content GATE stays OFF the whole run (SYSTEMS ONLY — no explicit content ships). Prints
## DEBUG full_chk=<n> for cross-process checks.
const SEED_A := 20260717
const SEED_B := 99
func _run(sv: int) -> Dictionary:
	var e := PuzzleDateEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk": e.checksum(), "turns": e.turns, "routes": e.routes_done(),
		"aff0": e.chars[0].affection, "won": e.won, "mature": e.mature_content, "over": e.game_over}
func _partial(sv: int, n: int) -> int:
	var e := PuzzleDateEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.game_over: break
		e.auto_step()
	return e.checksum()
func _ready() -> void:
	var ok := true
	var a1 := _run(SEED_A); var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk): ok = false; push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])
	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk): ok = false; push_error("different seeds produced the same run")
	var p1 := _partial(SEED_A, 6); var p2 := _partial(SEED_A, 6)
	if p1 != p2: ok = false; push_error("partial run not deterministic")
	if not bool(a1.over): ok = false; push_error("run did not end")
	if not bool(a1.won): ok = false; push_error("player did not win (routes %d)" % int(a1.routes))
	if int(a1.routes) < 1: ok = false; push_error("no route completed — match/affection may be broken")
	if bool(a1.mature): ok = false; push_error("mature_content gate must stay OFF — this template ships SYSTEMS ONLY")
	print("DEBUG full_chk=%d turns=%d routes=%d aff0=%d won=%s mature=%s" % [
		int(a1.chk), int(a1.turns), int(a1.routes), int(a1.aff0), str(a1.won), str(a1.mature)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
