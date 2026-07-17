class_name WordEngine
extends RefCounted
## Pure, seedable WORD-PUZZLE engine (Wordle-lineage letter-deduction) run as a DETERMINISTIC sim.
## Each ROUND hides a seeded target word; you GUESS words and each guess is scored per-letter —
## HIT (right letter, right spot) / PRESENT (right letter, wrong spot) / ABSENT — using the exact
## Wordle duplicate-letter rule. Solve inside MAX_GUESSES to bank streak + score; run a whole
## MARATHON of rounds for a run. Node-free + Time-free: one seeded RNG picks the target sequence,
## so a whole marathon replays BYTE-IDENTICALLY from a seed (FNV-1a checksum over the state). The
## scene (word_view.gd) + GameManager wrap this; all rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Rules
# --------------------------------------------------------------------------- #

const WORD_LEN := 5
const MAX_GUESSES := 6
const ROUNDS := 8                   ## a marathon of this many words == one run

# per-letter scores
const ABSENT := 0
const PRESENT := 1
const HIT := 2

## Embedded answer + guess list (generic common words; authors swap in a full dictionary).
const WORDS := [
	"CRANE", "SLATE", "TRACE", "ROAST", "PLANT", "BRAVE", "CHARM", "DRINK", "FLAME", "GRACE",
	"HOUSE", "IVORY", "JOKER", "KNEEL", "LEMON", "MONEY", "NURSE", "OCEAN", "PRIDE", "QUILT",
	"RIVER", "STONE", "TIGER", "ULTRA", "VOICE", "WHALE", "YOUTH", "ZEBRA", "APPLE", "BEACH",
	"CLOUD", "DANCE", "EAGLE", "FROST", "GLIDE", "HONEY", "INLET", "JELLY", "KOALA", "LIGHT",
	"MAPLE", "NIGHT", "OLIVE", "PEARL", "QUEEN", "ROBIN", "SUGAR", "TOWER", "UNITY", "VILLA",
	"WATER", "XENON", "YACHT", "ANGEL", "BLADE", "CABIN", "DELTA", "EMBER", "FABLE", "GHOST",
	"HEART", "IMAGE", "JUICE", "KARMA", "LUNAR", "MARCH", "NOBLE", "ORBIT", "PIANO", "QUART",
	"RADAR", "SHINE", "THORN", "URBAN", "VAULT", "WOVEN", "AMBER", "BRICK", "CHESS", "DWELL",
	"ELDER", "FJORD", "GRAPE", "HUMOR", "INDEX", "JOUST", "KRAFT", "LATCH", "MIRTH", "NYLON",
	"ONION", "PLUMB", "QUACK", "RUSTY", "SWORD", "TULIP", "UNZIP", "VIXEN", "WRING", "YEAST",
	"ABYSS", "BLINK", "CRISP", "DROWN", "EPOXY", "FLINT", "GRIND", "HATCH", "IGLOO", "JUMPY",
	"KNACK", "LYMPH", "MOTTO", "NOMAD", "PROXY", "QUELL", "RHYME", "SPINY", "TWIRL", "USHER"]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var round_idx := 0
var target := ""
var guesses: Array = []             ## Array of String for the CURRENT round
var feedbacks: Array = []           ## Array of Array[int] (WORD_LEN each) for the current round
var round_solved: Array = []        ## bool per finished round
var score := 0
var streak := 0
var best_streak := 0
var game_over := false
var _used: Dictionary = {}          ## target indices already used this marathon
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	round_idx = 0
	round_solved = []
	score = 0
	streak = 0
	best_streak = 0
	game_over = false
	_used = {}
	log_lines = []
	_start_round()

func _pick_target() -> String:
	# a distinct target per round (no repeats within a marathon)
	var idx := rng.randi_range(0, WORDS.size() - 1)
	var guard := 0
	while _used.has(idx) and guard < WORDS.size() * 4:
		idx = rng.randi_range(0, WORDS.size() - 1)
		guard += 1
	_used[idx] = true
	return str(WORDS[idx])

func _start_round() -> void:
	target = _pick_target()
	guesses = []
	feedbacks = []

# --------------------------------------------------------------------------- #
# Scoring (exact Wordle duplicate-letter handling)
# --------------------------------------------------------------------------- #

## Score `guess` against `answer`: HIT for right-letter-right-spot, then PRESENT for the remaining
## letters limited by their leftover count in the answer, else ABSENT.
func score_word(guess: String, answer: String) -> Array:
	var out: Array = []
	out.resize(WORD_LEN)
	var counts: Dictionary = {}
	for i in range(WORD_LEN):
		var a := answer[i]
		counts[a] = int(counts.get(a, 0)) + 1
	# first pass: hits consume a count
	for i in range(WORD_LEN):
		if guess[i] == answer[i]:
			out[i] = HIT
			counts[guess[i]] = int(counts[guess[i]]) - 1
		else:
			out[i] = ABSENT
	# second pass: presents from leftover counts
	for i in range(WORD_LEN):
		if out[i] == HIT:
			continue
		var g := guess[i]
		if int(counts.get(g, 0)) > 0:
			out[i] = PRESENT
			counts[g] = int(counts[g]) - 1
	return out

func is_valid_guess(word: String) -> bool:
	return word.length() == WORD_LEN and WORDS.has(word.to_upper())

# --------------------------------------------------------------------------- #
# Play
# --------------------------------------------------------------------------- #

func submit(word: String) -> bool:
	if game_over:
		return false
	var g := word.to_upper()
	if not is_valid_guess(g):
		return false
	guesses.append(g)
	var fb := score_word(g, target)
	feedbacks.append(fb)
	if g == target:
		_end_round(true)
	elif guesses.size() >= MAX_GUESSES:
		_end_round(false)
	return true

func _end_round(solved: bool) -> void:
	round_solved.append(solved)
	if solved:
		# fewer guesses == more points; a solved round extends the streak
		score += (MAX_GUESSES - guesses.size() + 1) * 10 + streak * 2
		streak += 1
		best_streak = maxi(best_streak, streak)
		_log("Round %d solved '%s' in %d — score %d, streak %d" % [round_idx + 1, target, guesses.size(), score, streak])
	else:
		streak = 0
		_log("Round %d failed '%s' — streak reset" % [round_idx + 1, target])
	round_idx += 1
	if round_idx >= ROUNDS:
		game_over = true
	else:
		_start_round()

func rounds_solved() -> int:
	var n := 0
	for s in round_solved:
		if bool(s):
			n += 1
	return n

# --------------------------------------------------------------------------- #
# Deterministic solver auto-seat (probe / demo)
# --------------------------------------------------------------------------- #

## Words still consistent with EVERY (guess, feedback) so far this round.
func candidates() -> Array:
	var out: Array = []
	for w in WORDS:
		var word := str(w)
		var ok := true
		for i in range(guesses.size()):
			if score_word(str(guesses[i]), word) != feedbacks[i]:
				ok = false
				break
		if ok:
			out.append(word)
	return out

## Pick the next guess: greedily maximise positional letter frequency across the remaining
## candidates (with a distinct-letter bonus) — a strong, fully deterministic Wordle solver.
func ai_guess() -> String:
	var cands := candidates()
	if cands.is_empty():
		return str(WORDS[0])          # unreachable when target is in WORDS, but stay safe
	if cands.size() == 1:
		return str(cands[0])
	# positional frequency table over the candidate set
	var freq: Array = []
	for _p in range(WORD_LEN):
		freq.append({})
	for w in cands:
		var word := str(w)
		for p in range(WORD_LEN):
			var c := word[p]
			freq[p][c] = int(freq[p].get(c, 0)) + 1
	var best := str(cands[0])
	var best_score := -1
	for w in cands:
		var word := str(w)
		var sc := 0
		var seen: Dictionary = {}
		for p in range(WORD_LEN):
			var c := word[p]
			sc += int(freq[p].get(c, 0))
			if not seen.has(c):
				seen[c] = true
				sc += 3               # reward distinct letters (more information)
		if sc > best_score:
			best_score = sc
			best = word
	return best

func auto_step() -> void:
	if game_over:
		return
	submit(ai_guess())

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < ROUNDS * MAX_GUESSES + 5:
		auto_step()
		guard += 1
	if not game_over:
		game_over = true

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 20:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%s|%d" % [round_idx, score, streak, best_streak, rounds_solved(),
		target, int(game_over)]
	for i in range(guesses.size()):
		s += "|%s:" % str(guesses[i])
		for v in feedbacks[i]:
			s += str(int(v))
	for sv in round_solved:
		s += "|%d" % int(bool(sv))
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	var fb: Array = []
	for f in feedbacks:
		fb.append((f as Array).duplicate())
	var used_keys: Array = []
	for k in _used:
		used_keys.append(int(k))
	return {"version": 1, "round_idx": round_idx, "target": target, "guesses": guesses.duplicate(),
		"feedbacks": fb, "round_solved": round_solved.duplicate(), "score": score, "streak": streak,
		"best_streak": best_streak, "game_over": game_over, "used": used_keys,
		"seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	round_idx = int(d.get("round_idx", 0))
	target = str(d.get("target", ""))
	guesses = (d.get("guesses", []) as Array).duplicate()
	feedbacks = []
	for f in (d.get("feedbacks", []) as Array):
		feedbacks.append((f as Array).duplicate())
	round_solved = (d.get("round_solved", []) as Array).duplicate()
	score = int(d.get("score", 0))
	streak = int(d.get("streak", 0))
	best_streak = int(d.get("best_streak", 0))
	game_over = bool(d.get("game_over", false))
	_used = {}
	for k in (d.get("used", []) as Array):
		_used[int(k)] = true
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
