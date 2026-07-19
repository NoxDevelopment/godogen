extends Node
## DETERMINISM + PLAYABILITY probe for the adult-management (venue tycoon) engine. Same seed →
## byte-identical run (checksum) mid-run + at the end; different seeds drive a different client
## flow; and the greedy manager plays a REAL run — hiring, upgrading, running seeded shifts, and
## growing cash + reputation — to a genuine terminal (the revenue+reputation goal, or day cap /
## bankruptcy). Also asserts the mature_content GATE stays OFF through a full run (SYSTEMS ONLY —
## no explicit content ships). Prints DEBUG full_chk=<n> for cross-process checks.
const SEED_A := 20260717
const SEED_B := 99
func _run(sv: int) -> Dictionary:
	var e := VenueMgmtEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk": e.checksum(), "day": e.day, "cash": e.cash, "rep": e.reputation,
		"staff": e.staff.size(), "rooms": e.rooms.size(), "won": e.won, "mature": e.mature_content, "over": e.game_over}
func _partial(sv: int, n: int) -> int:
	var e := VenueMgmtEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.game_over: break
		e.ai_day()
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
	if not bool(a1.won): ok = false; push_error("manager did not hit the goal (cash %.0f rep %.0f)" % [float(a1.cash), float(a1.rep)])
	if bool(a1.mature): ok = false; push_error("mature_content gate must stay OFF — this template ships SYSTEMS ONLY")
	if int(a1.staff) < 3 or int(a1.rooms) < 2: ok = false; push_error("manager never grew the venue")
	print("DEBUG full_chk=%d day=%d cash=%d rep=%d staff=%d rooms=%d won=%s mature=%s" % [
		int(a1.chk), int(a1.day), int(a1.cash), int(a1.rep), int(a1.staff), int(a1.rooms), str(a1.won), str(a1.mature)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
