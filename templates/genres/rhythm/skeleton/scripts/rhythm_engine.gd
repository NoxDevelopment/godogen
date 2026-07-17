class_name RhythmEngine
extends RefCounted
## Pure, seedable RHYTHM-GAME engine (Guitar Hero / DDR / osu!-mania lineage) run as a
## DETERMINISTIC FIXED-TIMESTEP sim at 60 ticks/sec: a seeded NOTE CHART scrolls down four
## lanes toward a hit line, and the player taps each lane in time. Judgment is by TIMING
## WINDOW (Perfect / Good / Miss) with combo + multiplier scoring, accuracy, and a letter
## grade. Node-free + Time-free: the RNG only builds the chart, and play is otherwise a pure
## function of the input stream, so a whole song replays BYTE-IDENTICALLY from a seed
## (FNV-1a checksum) and drives headlessly. The scene (rhythm_view.gd) + GameManager wrap
## this; all rules + state live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const LANES := 4
const BPM := 132
const BEAT_TICKS := 27              ## 60fps * 60 / BPM ≈ 27.3 → 27 ticks/beat
const START_OFFSET := 60            ## lead-in ticks before the first note
const END_BUFFER := 90
const N_BEATS := 72                 ## chart length in note-events

const PERFECT_W := 2                ## ± ticks for a Perfect
const GOOD_W := 5                   ## ± ticks for a Good (beyond → Miss when it passes)
const SCROLL_TICKS := 48            ## how long a note is visible above the line before its time

const SCORE_PERFECT := 100
const SCORE_GOOD := 50
const MAX_MULT := 4

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var notes: Array = []               ## {time, lane, hit, judged}
var playhead := 0
var song_end := 0
var score := 0
var combo := 0
var max_combo := 0
var counts := {"perfect": 0, "good": 0, "miss": 0}
var last_judge := ""
var last_judge_tick := -999
var game_over := false
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	notes = []
	playhead = 0
	score = 0
	combo = 0
	max_combo = 0
	counts = {"perfect": 0, "good": 0, "miss": 0}
	last_judge = ""
	last_judge_tick = -999
	game_over = false
	log_lines = []
	_gen_chart()

func _gen_chart() -> void:
	var t := START_OFFSET
	var prev_lane := -1
	for i in range(N_BEATS):
		var lane := rng.randi_range(0, LANES - 1)
		if lane == prev_lane and rng.randf() < 0.5:
			lane = (lane + 1) % LANES         # avoid too many repeats on one lane
		prev_lane = lane
		notes.append({"time": t, "lane": lane, "hit": false, "judged": ""})
		# occasional chord: a second simultaneous note in a different lane
		if rng.randf() < 0.18:
			var lane2 := (lane + 1 + rng.randi_range(0, LANES - 2)) % LANES
			notes.append({"time": t, "lane": lane2, "hit": false, "judged": ""})
		# syncopation: mostly on-beat, sometimes a half-beat gap
		var step := BEAT_TICKS if rng.randf() < 0.72 else BEAT_TICKS / 2
		t += step
	song_end = t + END_BUFFER

func total_notes() -> int:
	return notes.size()

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

## input = {lanes: [bool, bool, bool, bool]} — which lanes were TAPPED this tick (edge).
func tick(input: Dictionary) -> void:
	if game_over:
		return
	var lanes: Array = input.get("lanes", [])
	for l in range(LANES):
		if l < lanes.size() and bool(lanes[l]):
			_judge_press(l)
	# notes that scrolled past the window unhit → Miss
	for n in notes:
		if not bool(n.hit) and str(n.judged) == "" and int(n.time) < playhead - GOOD_W:
			n.judged = "miss"
			counts.miss = int(counts.miss) + 1
			combo = 0
			last_judge = "MISS"
			last_judge_tick = playhead
	playhead += 1
	if playhead > song_end:
		_finish()

func _judge_press(lane: int) -> void:
	# nearest un-judged note in this lane within the Good window
	var best: Dictionary = {}
	var bestd := GOOD_W + 1
	for n in notes:
		if int(n.lane) != lane or bool(n.hit) or str(n.judged) != "":
			continue
		var dt: int = abs(int(n.time) - playhead)
		if dt <= GOOD_W and dt < bestd:
			bestd = dt
			best = n
	if best.is_empty():
		return                                # stray tap — no penalty (lenient)
	best.hit = true
	var pts := 0
	if bestd <= PERFECT_W:
		best.judged = "perfect"
		counts.perfect = int(counts.perfect) + 1
		pts = SCORE_PERFECT
		last_judge = "PERFECT"
	else:
		best.judged = "good"
		counts.good = int(counts.good) + 1
		pts = SCORE_GOOD
		last_judge = "GOOD"
	combo += 1
	max_combo = max(max_combo, combo)
	score += pts * mult()
	last_judge_tick = playhead

func mult() -> int:
	return clampi(1 + combo / 8, 1, MAX_MULT)

func accuracy() -> float:
	var tot := total_notes()
	if tot <= 0:
		return 0.0
	return float(int(counts.perfect) * 100 + int(counts.good) * 50) / float(tot * 100) * 100.0

func grade() -> String:
	var a := accuracy()
	if a >= 95.0:
		return "S"
	if a >= 90.0:
		return "A"
	if a >= 80.0:
		return "B"
	if a >= 70.0:
		return "C"
	return "D"

func _finish() -> void:
	game_over = true
	_log("Song complete — %s  score %d  combo %d  acc %.1f%%" % [grade(), score, max_combo, accuracy()])

## Notes currently on screen (within the scroll window above/around the line) for the view.
func visible_notes() -> Array:
	var out: Array = []
	for n in notes:
		if str(n.judged) != "":
			continue
		var d: int = int(n.time) - playhead
		if d <= SCROLL_TICKS and d >= -GOOD_W:
			out.append(n)
	return out

# --------------------------------------------------------------------------- #
# Deterministic auto-play seat (probe / attract) — a policy taps each note on time
# --------------------------------------------------------------------------- #

## Returns the input for this tick under a policy:
##   "perfect" — tap each note exactly on its time (dt=0, full combo of Perfects)
##   "late<N>" — tap N ticks late (drives Good/Miss so the judgment tiers are exercised)
func seat_input(policy: String = "perfect") -> Dictionary:
	var offset := 0
	if policy.begins_with("late"):
		offset = int(policy.substr(4))
	var lanes := [false, false, false, false]
	for n in notes:
		if bool(n.hit) or str(n.judged) != "":
			continue
		if int(n.time) == playhead - offset:
			lanes[int(n.lane)] = true
	return {"lanes": lanes}

func auto_step(policy: String = "perfect") -> void:
	if game_over:
		return
	tick(seat_input(policy))

func auto_play_to_end(policy: String = "perfect") -> void:
	var guard := 0
	while not game_over and guard < song_end + 200:
		auto_step(policy)
		guard += 1
	if not game_over:
		_finish()

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 30:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d,%d,%d" % [playhead, int(game_over), score, combo, max_combo,
		int(counts.perfect), int(counts.good), int(counts.miss)]
	for n in notes:
		s += "|N%d,%d,%d,%s" % [int(n.time), int(n.lane), int(n.hit), str(n.judged)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "playhead": playhead, "song_end": song_end, "score": score,
		"combo": combo, "max_combo": max_combo, "counts": counts.duplicate(),
		"game_over": game_over, "seed": int(rng.seed), "rng_state": int(rng.state),
		"notes": notes.duplicate(true),
	}

func load_data(d: Dictionary) -> void:
	playhead = int(d.get("playhead", 0))
	song_end = int(d.get("song_end", 0))
	score = int(d.get("score", 0))
	combo = int(d.get("combo", 0))
	max_combo = int(d.get("max_combo", 0))
	counts = (d.get("counts", {"perfect": 0, "good": 0, "miss": 0}) as Dictionary).duplicate()
	game_over = bool(d.get("game_over", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	notes = (d.get("notes", []) as Array).duplicate(true)
