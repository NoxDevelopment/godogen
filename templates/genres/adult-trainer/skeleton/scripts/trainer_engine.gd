class_name TrainerEngine
extends RefCounted
## Pure, seedable ADULT-TRAINER engine (a mature-themed RAISE / TRAINER sim, Princess-Maker lineage)
## run as a DETERMINISTIC sim. This template ships the RAISER SYSTEMS ONLY — a companion with stat
## tracks, a weekly schedule of training activities with stamina/mood/money trade-offs, seeded
## events, an affection relationship meter, and stat-gated ENDINGS — plus a `mature_content` GATING
## FLAG (OFF by default) that only calls EMPTY author hooks. It ships NO explicit content; an author
## who adds mature content owns their own assets, an age-verification gate, and platform compliance.
## Node-free + Time-free: one seeded RNG drives the events, so a whole raise replays BYTE-IDENTICALLY
## from a seed (FNV-1a checksum). The scene (trainer_view.gd) + GameManager wrap this (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Rules
# --------------------------------------------------------------------------- #

const WEEKS := 24
const STAT_CAP := 100
const START_MONEY := 120
const TRACKS := ["discipline", "grace", "wit", "fitness", "artistry"]
# target for the built-in demo AI + the "win" definition (a Devoted Scholar path)
const TARGET_TRACK := "wit"
const TARGET_STAT := 60
const TARGET_AFFECTION := 60

# activity table: gains{track:amount}, money, stamina, mood, affection
const ACTIVITIES := {
	"study":      {"gain": {"wit": 8},        "money": -30, "stamina": -20, "mood": -3, "affection": -1},
	"etiquette":  {"gain": {"grace": 8},      "money": -30, "stamina": -18, "mood": -2, "affection": -1},
	"combat":     {"gain": {"fitness": 9},    "money": -25, "stamina": -28, "mood": -5, "affection": -2},
	"art":        {"gain": {"artistry": 8},   "money": -35, "stamina": -16, "mood": -1, "affection": 0},
	"drill":      {"gain": {"discipline": 8}, "money": -20, "stamina": -22, "mood": -6, "affection": -3},
	"work":       {"gain": {},                "money": 80,  "stamina": -20, "mood": -3, "affection": -1},
	"rest":       {"gain": {},                "money": 0,   "stamina": 45,  "mood": 10, "affection": 2},
	"outing":     {"gain": {},                "money": -40, "stamina": -8,  "mood": 12, "affection": 8},
}

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var week := 1
var money := START_MONEY
var stamina := 100.0
var mood := 70.0
var affection := 30.0
var stats: Dictionary = {}            ## track -> value
var last_activity := ""
var last_note := ""
var ending := ""
var game_over := false
var won := false
var mature_content := false           ## GATE — OFF by default; only unlocks empty hooks
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	week = 1
	money = START_MONEY
	stamina = 100.0
	mood = 70.0
	affection = 30.0
	stats = {}
	for t in TRACKS:
		stats[t] = 8 + rng.randi_range(0, 4)
	last_activity = ""
	last_note = ""
	ending = ""
	game_over = false
	won = false
	mature_content = false
	log_lines = []

func stat(track: String) -> int:
	return int(stats.get(track, 0))

func stat_total() -> int:
	var n := 0
	for t in TRACKS:
		n += int(stats[t])
	return n

func top_track() -> String:
	var best := TRACKS[0]
	for t in TRACKS:
		if int(stats[t]) > int(stats[best]):
			best = t
	return best

func can_afford(id: String) -> bool:
	return money + int(ACTIVITIES[id].money) >= 0

# --------------------------------------------------------------------------- #
# The weekly turn
# --------------------------------------------------------------------------- #

## Run one week's chosen activity. Returns true if it was applied.
func do_activity(id: String) -> bool:
	if game_over or not ACTIVITIES.has(id) or not can_afford(id):
		return false
	var a: Dictionary = ACTIVITIES[id]
	var cost_stamina := -int(a.stamina) if int(a.stamina) < 0 else 0
	# overtraining: not enough stamina for a draining activity → halved gains + extra mood hit
	var overtrained := cost_stamina > 0 and stamina < float(cost_stamina)
	var scale := 0.5 if overtrained else 1.0
	# apply resource deltas
	money += int(a.money)
	stamina = clampf(stamina + float(a.stamina), 0.0, 100.0)
	mood = clampf(mood + float(a.mood) - (6.0 if overtrained else 0.0), 0.0, 100.0)
	affection = clampf(affection + float(a.affection), 0.0, 100.0)
	# apply stat gains, scaled by mood (a happy trainee learns better) and overtraining
	var mood_mult := 0.8 + mood / 250.0
	for track in (a.gain as Dictionary):
		var g := int(round(float(a.gain[track]) * scale * mood_mult))
		stats[track] = mini(STAT_CAP, int(stats[track]) + g)
	last_activity = id
	last_note = ("(overtrained — reduced gains)" if overtrained else "")
	# seeded weekly event
	_weekly_event()
	# GATED, EMPTY hook when affection crosses a high milestone — no content ships
	if mature_content and affection >= 80.0:
		_mature_hook("affection_milestone", {"week": week, "affection": affection})
	_log("Week %d: %s  money %d stamina %.0f mood %.0f aff %.0f %s" % [week, id, money, stamina, mood, affection, last_note])
	week += 1
	if week > WEEKS:
		_finish()
	return true

func _weekly_event() -> void:
	# ~28% chance of a small seeded event that nudges a resource or a stat
	if rng.randf() > 0.28:
		return
	var kind := rng.randi_range(0, 3)
	match kind:
		0:
			var bonus := rng.randi_range(2, 5)
			var t: String = TRACKS[rng.randi_range(0, TRACKS.size() - 1)]
			stats[t] = mini(STAT_CAP, int(stats[t]) + bonus)
			last_note += " [inspired: +%d %s]" % [bonus, t]
		1:
			mood = clampf(mood - rng.randi_range(4, 9), 0.0, 100.0)
			last_note += " [a bad week: mood down]"
		2:
			affection = clampf(affection + rng.randi_range(3, 7), 0.0, 100.0)
			last_note += " [a fond moment: affection up]"
		3:
			money += rng.randi_range(20, 50)
			last_note += " [a small windfall]"

func _finish() -> void:
	game_over = true
	ending = _resolve_ending()
	won = ending != "Burnout" and stat(TARGET_TRACK) >= TARGET_STAT and affection >= float(TARGET_AFFECTION)
	_log("Ending: %s (won=%s)  total %d, %s %d, affection %.0f" % [ending, str(won), stat_total(), TARGET_TRACK, stat(TARGET_TRACK), affection])

func _resolve_ending() -> String:
	if mood < 25.0 or affection < 20.0:
		return "Burnout"
	var top := top_track()
	var tv := stat(top)
	if affection >= 80.0 and tv >= 70:
		return "Devoted %s" % top.capitalize()
	if tv >= 60:
		return "%s Prodigy" % top.capitalize()
	if affection >= 60.0:
		return "Beloved Companion"
	return "Well-Rounded"

## INTENTIONALLY EMPTY. Author hook for gated mature milestones. Left empty on purpose — the
## template ships the raiser SYSTEMS + this gate, and NO explicit content. Wire your OWN
## age-verified, platform-compliant content here if you choose to.
func _mature_hook(_event: String, _ctx: Dictionary) -> void:
	pass

# --------------------------------------------------------------------------- #
# Deterministic trainer auto-seat (probe / demo) — raises toward the TARGET path
# --------------------------------------------------------------------------- #

## Pick the week's activity: keep resources above floors, then push the target stat + affection.
func ai_choice() -> String:
	if money < 40:
		return "work"
	if stamina < 25.0:
		return "rest"
	if (affection < 45.0 or mood < 45.0) and can_afford("outing"):
		return "outing"
	if stat(TARGET_TRACK) < TARGET_STAT and can_afford("study"):
		return "study"
	if affection < float(TARGET_AFFECTION) and can_afford("outing"):
		return "outing"
	if stamina < 50.0:
		return "rest"
	# target met — round out the top track a little, else rest
	if can_afford("study"):
		return "study"
	return "rest"

func auto_step() -> void:
	if game_over:
		return
	do_activity(ai_choice())

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < WEEKS + 4:
		auto_step()
		guard += 1
	if not game_over:
		_finish()

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 24:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func _q(v: float) -> int:
	return int(round(v))

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d|%d|%s" % [week, money, _q(stamina), _q(mood), _q(affection),
		int(game_over), int(won), ending]
	for t in TRACKS:
		s += "|%s%d" % [t, int(stats[t])]
	s += "|M%d" % int(mature_content)
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {"version": 1, "week": week, "money": money, "stamina": stamina, "mood": mood,
		"affection": affection, "stats": stats.duplicate(), "ending": ending, "game_over": game_over,
		"won": won, "mature_content": mature_content, "seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	week = int(d.get("week", 1))
	money = int(d.get("money", START_MONEY))
	stamina = float(d.get("stamina", 100.0))
	mood = float(d.get("mood", 70.0))
	affection = float(d.get("affection", 30.0))
	stats = (d.get("stats", {}) as Dictionary).duplicate()
	ending = str(d.get("ending", ""))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	mature_content = bool(d.get("mature_content", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
