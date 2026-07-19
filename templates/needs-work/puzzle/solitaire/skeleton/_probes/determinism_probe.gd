extends Node
## DETERMINISM + PLAYABILITY probe for the Klondike solitaire engine. Same seed → byte-identical
## game (checksum) mid-game + at the end; different seeds deal a different game; and the greedy
## solver plays a REAL game to a genuine terminal (a full solve, or a stall). SEED_A=10 is a deal
## the greedy solver SOLVES outright (52/52 home) — proof the whole move set (draw/recycle,
## tableau runs, uncovering, foundations) actually works end-to-end. Prints DEBUG full_chk=<n>.
const SEED_A := 10          ## a deal the greedy solver wins (found by a 400-seed sweep)
const SEED_B := 2           ## a different deal (does not win; used only for the divergence check)
func _run(sv: int) -> Dictionary:
	var e := SolitaireEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk": e.checksum(), "ft": e.foundation_total(), "moves": e.moves,
		"redeals": e.redeals, "won": e.won, "stuck": e.stuck}
func _partial(sv: int, n: int) -> int:
	var e := SolitaireEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.won or e.stuck: break
		e.auto_step()
	return e.checksum()
func _ready() -> void:
	var ok := true
	var a1 := _run(SEED_A); var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk): ok = false; push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])
	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk): ok = false; push_error("different seeds produced the same game")
	var p1 := _partial(SEED_A, 40); var p2 := _partial(SEED_A, 40)
	if p1 != p2: ok = false; push_error("partial run not deterministic")
	if not bool(a1.won): ok = false; push_error("solver did not solve seed A (ft=%d) — move set may be broken" % int(a1.ft))
	if int(a1.ft) != 52: ok = false; push_error("win but foundations != 52 (%d)" % int(a1.ft))
	# the losing deal must still be a legitimate terminal with real progress
	if not bool(b1.stuck) and not bool(b1.won): ok = false; push_error("seed B did not terminate")
	if int(b1.ft) <= 0: ok = false; push_error("seed B made no progress")
	print("DEBUG full_chk=%d ft=%d/52 moves=%d redeals=%d won=%s  |  seedB ft=%d stuck=%s" % [
		int(a1.chk), int(a1.ft), int(a1.moves), int(a1.redeals), str(a1.won), int(b1.ft), str(b1.stuck)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
