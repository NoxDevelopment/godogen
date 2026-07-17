extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the educational-quiz engine. Proves the same seed
## reproduces a BYTE-IDENTICAL quiz (identical FNV-1a checksum + the same generated questions)
## mid-quiz and at the end; different seeds produce different quizzes; the PERFECT seat aces
## every question (grade A) while a GUESS seat scores strictly lower (so the scoring/grading is
## real); and a per-category report card is produced. Prints `DEBUG full_chk=<n>` so the
## harness can confirm the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 2929


func _run(seed_value: int, policy: String) -> Dictionary:
	var e := QuizEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end(policy)
	return {"chk": e.checksum(), "score": e.score, "grade": e.grade(), "correct": e.correct,
		"wrong": e.wrong, "max_streak": e.max_streak, "cats": e.report_card().size(), "done": e.done}


func _partial(seed_value: int, steps: int) -> int:
	var e := QuizEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
		if e.done:
			break
		e.auto_step("perfect")
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _run(SEED_A, "perfect")
	var a2 := _run(SEED_A, "perfect")
	if int(a1.chk) != int(a2.chk):
		ok = false
		push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])

	var b1 := _run(SEED_B, "perfect")
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds produced the same quiz")

	var p1 := _partial(SEED_A, 8)
	var p2 := _partial(SEED_A, 8)
	if p1 != p2:
		ok = false
		push_error("partial quiz not deterministic")

	# playability: perfect aces it (grade A), the report card is populated, and a guess seat
	# scores strictly worse — proving the scoring + grading actually respond to answers
	if not a1.done:
		ok = false
		push_error("quiz did not finish")
	if int(a1.correct) != QuizEngine.N_QUESTIONS:
		ok = false
		push_error("perfect seat did not ace the quiz (%d/%d)" % [int(a1.correct), QuizEngine.N_QUESTIONS])
	if str(a1.grade) != "A":
		ok = false
		push_error("perfect run not graded A (got %s)" % str(a1.grade))
	if int(a1.cats) < 2:
		ok = false
		push_error("report card has too few categories (%d)" % int(a1.cats))
	var guess := _run(SEED_A, "guess")
	if int(guess.score) >= int(a1.score) or int(guess.correct) >= int(a1.correct):
		ok = false
		push_error("guess seat did not score worse (guess %d/%d vs perfect %d/%d)" % [
			int(guess.correct), int(guess.score), int(a1.correct), int(a1.score)])

	print("DEBUG full_chk=%d correct=%d/%d score=%d grade=%s streak=%d cats=%d  guess_correct=%d guess_score=%d" % [
		int(a1.chk), int(a1.correct), QuizEngine.N_QUESTIONS, int(a1.score), str(a1.grade),
		int(a1.max_streak), int(a1.cats), int(guess.correct), int(guess.score)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
