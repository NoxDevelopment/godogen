extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the hidden-object engine. Proves the same seed
## reproduces a BYTE-IDENTICAL game (identical FNV-1a checksum + the same object placements)
## mid-game and at the end; different seeds lay out a different scene; and the solver seat
## finds every item across all rounds to a WIN (using a hint each round) — proving placement,
## click hit-testing, the find list, scoring, and round progression all work. Prints
## `DEBUG full_chk=<n>` so the harness can confirm the checksum matches across two SEPARATE
## PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 3838


func _run(seed_value: int) -> Dictionary:
	var e := HiddenEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("solver")
	return {"chk": e.checksum(), "score": e.score, "won": e.won, "round": e.round_no,
		"misclicks": e.misclicks, "over": e.game_over}


func _partial(seed_value: int, steps: int) -> int:
	var e := HiddenEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
		if e.game_over:
			break
		e.auto_step("solver")
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
		push_error("different seeds produced the same scene layout")

	var p1 := _partial(SEED_A, 6)
	var p2 := _partial(SEED_A, 6)
	if p1 != p2:
		ok = false
		push_error("partial game not deterministic")

	# playability: the solver found every item across all rounds to a win, scoring positive,
	# with no misclicks (it clicks exact object positions)
	if not a1.over:
		ok = false
		push_error("game did not end")
	if not a1.won:
		ok = false
		push_error("solver did not clear all rounds (round=%d)" % int(a1.round))
	if int(a1.score) <= 0:
		ok = false
		push_error("no score accrued")
	if int(a1.misclicks) != 0:
		ok = false
		push_error("solver misclicked (%d) — hit-testing may be off" % int(a1.misclicks))

	print("DEBUG full_chk=%d won=%s round=%d score=%d misclicks=%d" % [
		int(a1.chk), str(a1.won), int(a1.round), int(a1.score), int(a1.misclicks)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
