extends Node
## DETERMINISM + PLAYABILITY probe for the bubble-shooter engine. Same seed → byte-identical
## match (checksum) mid-match + at the end; different seeds deal a different board; and the aim
## AI plays a REAL match — popping seeded bubbles and dropping floaters — to a genuine terminal
## (clearing the board, or the stack reaching the bottom line). Prints DEBUG full_chk=<n> for
## cross-process checks.
const SEED_A := 20260717
const SEED_B := 991
func _run(sv: int) -> Dictionary:
	var e := BubbleEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk": e.checksum(), "score": e.score, "popped": e.popped, "dropped": e.dropped,
		"shots": e.shots, "won": e.won, "over": e.game_over}
func _partial(sv: int, n: int) -> int:
	var e := BubbleEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.game_over: break
		e.auto_step()
	return e.checksum()
func _ready() -> void:
	var ok := true
	var a1 := _run(SEED_A); var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk): ok = false; push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])
	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk): ok = false; push_error("different seeds produced the same board")
	var p1 := _partial(SEED_A, 12); var p2 := _partial(SEED_A, 12)
	if p1 != p2: ok = false; push_error("partial run not deterministic")
	if not a1.over: ok = false; push_error("match did not end")
	if int(a1.popped) < 6: ok = false; push_error("too few bubbles popped (%d) — aim/pop may be broken" % int(a1.popped))
	if int(a1.score) <= 0: ok = false; push_error("no score")
	print("DEBUG full_chk=%d score=%d popped=%d dropped=%d shots=%d won=%s" % [
		int(a1.chk), int(a1.score), int(a1.popped), int(a1.dropped), int(a1.shots), str(a1.won)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
