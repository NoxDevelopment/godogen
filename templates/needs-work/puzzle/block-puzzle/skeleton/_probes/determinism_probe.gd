extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the falling-block engine. Proves the same seed
## reproduces a BYTE-IDENTICAL game (identical FNV-1a checksum) mid-game and at the end;
## different seeds diverge (seeded 7-bag); and the placement AI plays a REAL game — it clears
## a lot of lines and scores — proving collision, rotation, line-clears and scoring all work.
## Prints `DEBUG full_chk=<n>` so the harness can confirm the checksum matches across two
## SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 7373


func _full(seed_value: int) -> Dictionary:
	var e := BlockEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("ai")
	return {"chk": e.checksum(), "score": e.score, "lines": e.lines, "level": e.level,
		"pieces": e.pieces, "over": e.game_over}


func _partial(seed_value: int, steps: int) -> int:
	var e := BlockEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
		if e.game_over:
			break
		e.auto_step("ai")
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _full(SEED_A)
	var a2 := _full(SEED_A)
	if int(a1.chk) != int(a2.chk):
		ok = false
		push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])

	var b1 := _full(SEED_B)
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds produced the same game (7-bag not seeded?)")

	var p1 := _partial(SEED_A, 40)
	var p2 := _partial(SEED_A, 40)
	if p1 != p2:
		ok = false
		push_error("partial game not deterministic")

	# playability: the AI cleared real lines and scored
	if int(a1.lines) < 20:
		ok = false
		push_error("too few lines cleared (%d) — collision/clear/AI may be broken" % int(a1.lines))
	if int(a1.score) <= 0:
		ok = false
		push_error("no score accrued")
	if int(a1.pieces) < 50:
		ok = false
		push_error("game ended almost immediately (%d pieces)" % int(a1.pieces))

	print("DEBUG full_chk=%d pieces=%d lines=%d score=%d level=%d over=%s" % [
		int(a1.chk), int(a1.pieces), int(a1.lines), int(a1.score), int(a1.level), str(a1.over)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
