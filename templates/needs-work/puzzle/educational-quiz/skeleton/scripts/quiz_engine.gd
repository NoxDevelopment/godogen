class_name QuizEngine
extends RefCounted
## Pure, seedable EDUCATIONAL-QUIZ engine (learning-game lineage): a timed, ADAPTIVE
## multiple-choice quiz that generates arithmetic questions on the fly + draws from a trivia
## bank, scales difficulty to the player's streak, scores with time + streak bonuses, and
## produces a per-CATEGORY report card + a letter grade. Node-free + Time-free: one seeded
## RNG generates the questions + shuffles the choices, so a whole quiz replays BYTE-IDENTICALLY
## from a seed (FNV-1a checksum) and drives headlessly. The scene (quiz_view.gd) + GameManager
## wrap this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const N_QUESTIONS := 20
const N_CHOICES := 4
const TIME_LIMIT := 900            ## ticks per question (15s at 60fps)
const BASE_POINTS := 100
const STREAK_STEP := 25            ## +points per current streak
const TIME_BONUS_MAX := 50         ## up to +50 for answering fast
const PASS_ACCURACY := 70.0
const MIN_DIFF := 1
const MAX_DIFF := 5

# a small factual trivia bank (generic, non-trademark), tagged by difficulty tier
const TRIVIA := [
	{"q": "Which planet is closest to the Sun?", "a": ["Mercury", "Venus", "Earth", "Mars"], "c": 0, "cat": "science", "diff": 1},
	{"q": "How many continents are there?", "a": ["5", "6", "7", "8"], "c": 2, "cat": "geography", "diff": 1},
	{"q": "What gas do plants absorb?", "a": ["Oxygen", "Nitrogen", "Carbon dioxide", "Helium"], "c": 2, "cat": "science", "diff": 2},
	{"q": "What is the largest ocean?", "a": ["Atlantic", "Indian", "Arctic", "Pacific"], "c": 3, "cat": "geography", "diff": 2},
	{"q": "How many sides does a hexagon have?", "a": ["5", "6", "7", "8"], "c": 1, "cat": "math", "diff": 2},
	{"q": "Water freezes at what Celsius temperature?", "a": ["0", "32", "100", "-10"], "c": 0, "cat": "science", "diff": 2},
	{"q": "Which is a prime number?", "a": ["9", "15", "17", "21"], "c": 2, "cat": "math", "diff": 3},
	{"q": "What is the capital of Japan?", "a": ["Seoul", "Beijing", "Tokyo", "Bangkok"], "c": 2, "cat": "geography", "diff": 3},
	{"q": "The powerhouse of the cell is the...", "a": ["Nucleus", "Mitochondria", "Ribosome", "Membrane"], "c": 1, "cat": "science", "diff": 3},
	{"q": "What is 15% of 200?", "a": ["25", "30", "35", "40"], "c": 1, "cat": "math", "diff": 4},
	{"q": "Speed of light is about ___ km/s.", "a": ["3,000", "30,000", "300,000", "3,000,000"], "c": 2, "cat": "science", "diff": 4},
	{"q": "Which is NOT a noble gas?", "a": ["Neon", "Argon", "Oxygen", "Krypton"], "c": 2, "cat": "science", "diff": 5},
]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var idx := 0
var question := {}                 ## {prompt, choices[], correct, cat, diff}
var difficulty := 2
var score := 0
var streak := 0
var max_streak := 0
var correct := 0
var wrong := 0
var time_left := 0
var cat_correct := {}              ## category → correct count
var cat_total := {}
var done := false
var last_result := ""              ## "" | "right" | "wrong" | "timeout"
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	idx = 0
	difficulty = 2
	score = 0
	streak = 0
	max_streak = 0
	correct = 0
	wrong = 0
	cat_correct = {}
	cat_total = {}
	done = false
	last_result = ""
	log_lines = []
	_next_question()

func _next_question() -> void:
	if idx >= N_QUESTIONS:
		done = true
		question = {}
		_log("Quiz complete: %d/%d, grade %s" % [correct, N_QUESTIONS, grade()])
		return
	question = _make_question(difficulty)
	time_left = TIME_LIMIT
	last_result = ""

# --------------------------------------------------------------------------- #
# Question generation (seeded)
# --------------------------------------------------------------------------- #

func _make_question(diff: int) -> Dictionary:
	# 55% generated arithmetic, else a trivia question near this difficulty
	if rng.randf() < 0.55:
		return _make_arithmetic(diff)
	return _make_trivia(diff)

func _make_arithmetic(diff: int) -> Dictionary:
	var mag: int = int(pow(10.0, float(clampi(diff, 1, 4))))     # 10,100,1000,10000
	var a := rng.randi_range(2, mag)
	var b := rng.randi_range(2, max(2, mag / 2))
	var op := "+"
	var ans := 0
	var roll := rng.randi_range(0, 2 if diff >= 3 else 1)
	if roll == 0:
		op = "+"
		ans = a + b
	elif roll == 1:
		op = "-"
		if b > a:
			var t := a
			a = b
			b = t
		ans = a - b
	else:
		op = "×"
		a = rng.randi_range(2, 12 + diff * 3)
		b = rng.randi_range(2, 12 + diff * 3)
		ans = a * b
	return _wrap_numeric("%d %s %d = ?" % [a, op, b], ans, "math", diff)

func _wrap_numeric(prompt: String, ans: int, cat: String, diff: int) -> Dictionary:
	# build 3 unique distractors near the answer, then place the correct one at a seeded slot
	var opts := [ans]
	var guard := 0
	while opts.size() < N_CHOICES and guard < 50:
		guard += 1
		var off := rng.randi_range(1, 5 + diff * 2) * (1 if rng.randf() < 0.5 else -1)
		var d := ans + off
		if d != ans and not (d in opts):
			opts.append(d)
	while opts.size() < N_CHOICES:
		opts.append(ans + opts.size())        # safety fill
	var correct_slot := rng.randi_range(0, N_CHOICES - 1)
	var choices := []
	var oi := 1
	for s in range(N_CHOICES):
		if s == correct_slot:
			choices.append(str(ans))
		else:
			choices.append(str(opts[oi]))
			oi += 1
	return {"prompt": prompt, "choices": choices, "correct": correct_slot, "cat": cat, "diff": diff}

func _make_trivia(diff: int) -> Dictionary:
	# pick a trivia entry near the difficulty, then shuffle its choices (seeded)
	var pool := []
	for t in TRIVIA:
		if abs(int(t.diff) - diff) <= 1:
			pool.append(t)
	if pool.is_empty():
		pool = TRIVIA
	var base: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	# shuffle choice order, tracking where the correct answer lands
	var order := []
	for i in range(base.a.size()):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var choices := []
	var correct_slot := 0
	for s in range(order.size()):
		choices.append(str(base.a[order[s]]))
		if int(order[s]) == int(base.c):
			correct_slot = s
	return {"prompt": str(base.q), "choices": choices, "correct": correct_slot, "cat": str(base.cat), "diff": int(base.diff)}

# --------------------------------------------------------------------------- #
# Answering + scoring
# --------------------------------------------------------------------------- #

func answer(choice: int) -> void:
	if done or question.is_empty():
		return
	var cat := str(question.cat)
	cat_total[cat] = int(cat_total.get(cat, 0)) + 1
	if choice == int(question.correct):
		correct += 1
		streak += 1
		max_streak = max(max_streak, streak)
		cat_correct[cat] = int(cat_correct.get(cat, 0)) + 1
		var time_bonus: int = int(TIME_BONUS_MAX * float(time_left) / float(TIME_LIMIT))
		var pts: int = BASE_POINTS + int(question.diff) * 20 + (streak - 1) * STREAK_STEP + time_bonus
		score += pts
		last_result = "right"
		_log("Q%d right (+%d, streak %d)" % [idx + 1, pts, streak])
		difficulty = clampi(difficulty + (1 if streak % 2 == 0 else 0), MIN_DIFF, MAX_DIFF)
	else:
		wrong += 1
		streak = 0
		last_result = "wrong"
		_log("Q%d wrong" % [idx + 1])
		difficulty = clampi(difficulty - 1, MIN_DIFF, MAX_DIFF)
	idx += 1
	_advance_after_result()

func _advance_after_result() -> void:
	_next_question()

## Fixed-timestep countdown for the interactive view — a timeout counts as wrong.
func tick() -> void:
	if done or question.is_empty():
		return
	time_left -= 1
	if time_left <= 0:
		wrong += 1
		streak = 0
		last_result = "timeout"
		var cat := str(question.cat)
		cat_total[cat] = int(cat_total.get(cat, 0)) + 1
		_log("Q%d timed out" % [idx + 1])
		difficulty = clampi(difficulty - 1, MIN_DIFF, MAX_DIFF)
		idx += 1
		_next_question()

# --------------------------------------------------------------------------- #
# Results
# --------------------------------------------------------------------------- #

func accuracy() -> float:
	var answered := correct + wrong
	if answered <= 0:
		return 0.0
	return float(correct) / float(answered) * 100.0

func passed() -> bool:
	return accuracy() >= PASS_ACCURACY

func grade() -> String:
	var a := accuracy()
	if a >= 90.0:
		return "A"
	if a >= 80.0:
		return "B"
	if a >= 70.0:
		return "C"
	if a >= 60.0:
		return "D"
	return "F"

func report_card() -> Array:
	var out: Array = []
	for cat in cat_total.keys():
		out.append({"cat": cat, "correct": int(cat_correct.get(cat, 0)), "total": int(cat_total[cat])})
	out.sort_custom(func(x, y): return str(x.cat) < str(y.cat))
	return out

# --------------------------------------------------------------------------- #
# Auto-play seat (probe / demo). policy: "perfect" | "guess"
# --------------------------------------------------------------------------- #

func seat_choice(policy: String) -> int:
	if question.is_empty():
		return 0
	if policy == "perfect":
		return int(question.correct)
	# "guess": a fixed pattern independent of the answer key (no RNG, so it doesn't perturb
	# question generation) — lands on the correct slot only occasionally, like a guesser
	return (idx * 3 + int(question.diff)) % N_CHOICES

func auto_step(policy: String = "perfect") -> void:
	if done:
		return
	answer(seat_choice(policy))

func auto_play_to_end(policy: String = "perfect") -> void:
	var guard := 0
	while not done and guard < N_QUESTIONS + 4:
		auto_step(policy)
		guard += 1

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 40:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d|%d|%s" % [idx, difficulty, score, streak, max_streak, correct, wrong, last_result]
	var qp: String = str(question.get("prompt", "")) if not question.is_empty() else ""
	s += "|Q%s,%d" % [qp, int(question.get("correct", -1))]
	for cat in report_card():
		s += "|C%s,%d,%d" % [str(cat.cat), int(cat.correct), int(cat.total)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "idx": idx, "difficulty": difficulty, "score": score, "streak": streak,
		"max_streak": max_streak, "correct": correct, "wrong": wrong, "time_left": time_left,
		"cat_correct": cat_correct.duplicate(), "cat_total": cat_total.duplicate(),
		"done": done, "last_result": last_result, "question": question.duplicate(true),
		"seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	idx = int(d.get("idx", 0))
	difficulty = int(d.get("difficulty", 2))
	score = int(d.get("score", 0))
	streak = int(d.get("streak", 0))
	max_streak = int(d.get("max_streak", 0))
	correct = int(d.get("correct", 0))
	wrong = int(d.get("wrong", 0))
	time_left = int(d.get("time_left", 0))
	cat_correct = (d.get("cat_correct", {}) as Dictionary).duplicate()
	cat_total = (d.get("cat_total", {}) as Dictionary).duplicate()
	done = bool(d.get("done", false))
	last_result = str(d.get("last_result", ""))
	question = (d.get("question", {}) as Dictionary).duplicate(true)
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
