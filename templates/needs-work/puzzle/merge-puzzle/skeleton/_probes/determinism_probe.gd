extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the merge-puzzle (2048) engine. Proves the same seed
## reproduces a BYTE-IDENTICAL game (identical FNV-1a checksum) mid-game and at the end; different
## seeds spawn a different board; and the corner-heuristic seat plays a REAL long game — merging
## up to a high tile with a positive score — to a genuine game over. Prints `DEBUG full_chk=<n>`
## so the harness can confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 2468


func _run(seed_value: int) -> Dictionary:
	var e := MergeEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end()
	return {"chk": e.checksum(), "score": e.score, "moves": e.moves, "best": e.best_tile,
		"won": e.won, "over": e.game_over}


func _partial(seed_value: int, steps: int) -> int:
	var e := MergeEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
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
		push_error("different seeds produced the same board")

	var p1 := _partial(SEED_A, 30)
	var p2 := _partial(SEED_A, 30)
	if p1 != p2:
		ok = false
		push_error("partial game not deterministic")

	# playability: the seat played a real game — many merges, a high tile, a positive score
	if not a1.over:
		ok = false
		push_error("game did not end")
	if int(a1.moves) < 60:
		ok = false
		push_error("game ended too quickly (%d moves) — slide/merge may be broken" % int(a1.moves))
	if int(a1.best) < 128:
		ok = false
		push_error("did not merge to a high tile (best %d) — merging may be broken" % int(a1.best))
	if int(a1.score) <= 0:
		ok = false
		push_error("no score accrued")

	print("DEBUG full_chk=%d moves=%d best_tile=%d score=%d won=%s" % [
		int(a1.chk), int(a1.moves), int(a1.best), int(a1.score), str(a1.won)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
