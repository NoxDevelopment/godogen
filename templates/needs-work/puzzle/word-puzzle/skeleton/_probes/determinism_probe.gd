extends Node
## DETERMINISM + PLAYABILITY probe for the word-puzzle engine. Same seed → byte-identical
## marathon (checksum) mid-run + at the end; different seeds pick a different target sequence; and
## the filtering solver plays a REAL marathon, deducing seeded target words from per-letter
## feedback and banking a streak, to the end of the rounds. Prints DEBUG full_chk=<n> for
## cross-process checks.
const SEED_A := 20260717
const SEED_B := 4242
func _run(sv: int) -> Dictionary:
	var e := WordEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk": e.checksum(), "score": e.score, "solved": e.rounds_solved(),
		"best": e.best_streak, "over": e.game_over}
func _partial(sv: int, n: int) -> int:
	var e := WordEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.game_over: break
		e.auto_step()
	return e.checksum()
func _ready() -> void:
	var ok := true
	var a1 := _run(SEED_A); var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk): ok = false; push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])
	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk): ok = false; push_error("different seeds produced the same marathon")
	var p1 := _partial(SEED_A, 10); var p2 := _partial(SEED_A, 10)
	if p1 != p2: ok = false; push_error("partial run not deterministic")
	if not a1.over: ok = false; push_error("marathon did not end")
	# the filtering solver should crack the large majority of a small-dictionary marathon
	if int(a1.solved) < WordEngine.ROUNDS - 1: ok = false; push_error("solver too weak (%d/%d solved)" % [int(a1.solved), WordEngine.ROUNDS])
	if int(a1.score) <= 0: ok = false; push_error("no score")
	print("DEBUG full_chk=%d score=%d solved=%d/%d best_streak=%d" % [
		int(a1.chk), int(a1.score), int(a1.solved), WordEngine.ROUNDS, int(a1.best)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
