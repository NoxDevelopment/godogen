class_name LifeEngine
extends RefCounted
## Pure, seedable LIFE-SIM engine (The Sims-lite) run as a DETERMINISTIC FIXED-TIMESTEP sim:
## a character with six decaying NEEDS (hunger/energy/hygiene/fun/social/bladder) does timed
## ACTIONS to meet them, holds a JOB (earning money on a daily schedule, paid by mood), builds
## RELATIONSHIPS with NPCs, and works toward an ASPIRATION goal — over a day/clock cycle with
## seeded daily EVENTS. Node-free + Time-free: one seeded RNG only drives the daily events +
## start jitter, so a whole life replays BYTE-IDENTICALLY from a seed (FNV-1a checksum over
## quantized needs). The scene (life_view.gd) + GameManager wrap this; all rules live here (ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const DAY_TICKS := 240              ## ticks/day → 10 ticks per game-hour
const TPH := 10                     ## ticks per hour
const WORK_START_H := 9
const WORK_END_H := 17
const WORK_DUR := 45                ## a work shift ~4.5h
const WAGE := 210                   ## base pay per shift, scaled by mood
const NEEDS := ["hunger", "energy", "hygiene", "fun", "social", "bladder"]
# decay is tuned so a need drains ~1-2 refills per 240-tick day (leaving time to work + socialize)
const DECAY := {"hunger": 0.34, "energy": 0.26, "hygiene": 0.20, "fun": 0.28, "social": 0.20, "bladder": 0.40}

# actions: {need, restore, dur}. "work"/"idle" are handled specially.
const ACTIONS := {
	"toilet": {"need": "bladder", "restore": 100.0, "dur": 2},
	"eat": {"need": "hunger", "restore": 70.0, "dur": 6},
	"shower": {"need": "hygiene", "restore": 85.0, "dur": 4},
	"sleep": {"need": "energy", "restore": 100.0, "dur": 60},
	"relax": {"need": "fun", "restore": 55.0, "dur": 10},
	"socialize": {"need": "social", "restore": 55.0, "dur": 10},
}
const NPCS := ["Sam", "Robin", "Alex"]
const ASPIRE_MONEY := 2000
const ASPIRE_FRIEND := 80

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var needs := {}                     ## need → 0..100
var money := 0
var day := 1
var tick_of_day := 0
var frame := 0
var action := ""                    ## current action ("" = idle)
var action_left := 0
var worked_today := false
var rel := {}                       ## npc → 0..100
var mood := 100.0
var aspiration := false
var collapses := 0                  ## times energy hit 0 (forced sleep)
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	needs = {}
	for n in NEEDS:
		needs[n] = 70.0 + float(rng.randi_range(-10, 15))
	money = 0
	day = 1
	tick_of_day = 0
	frame = 0
	action = ""
	action_left = 0
	worked_today = false
	rel = {}
	for npc in NPCS:
		rel[npc] = float(rng.randi_range(0, 15))
	aspiration = false
	collapses = 0
	log_lines = []
	_recompute_mood()

func hour() -> int:
	return int(tick_of_day / TPH)

func is_work_time() -> bool:
	var h := hour()
	return h >= WORK_START_H and h < WORK_END_H

func _recompute_mood() -> void:
	var s := 0.0
	for n in NEEDS:
		s += float(needs[n])
	mood = s / float(NEEDS.size())

func best_friend() -> float:
	var m := 0.0
	for npc in NPCS:
		m = max(m, float(rel[npc]))
	return m

# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #

func start_action(kind: String) -> bool:
	if action != "":
		return false
	if kind == "work":
		if not is_work_time() or worked_today:
			return false
		action = "work"
		action_left = WORK_DUR
		return true
	if kind in ACTIONS:
		action = kind
		action_left = int(ACTIONS[kind].dur)
		return true
	return false

func _finish_action() -> void:
	var k := action
	if k == "work":
		var pay: int = int(float(WAGE) * clampf(mood / 100.0, 0.3, 1.2))
		money += pay
		worked_today = true
		needs.energy = maxf(0.0, float(needs.energy) - 25.0)
		needs.hygiene = maxf(0.0, float(needs.hygiene) - 20.0)
		needs.bladder = maxf(0.0, float(needs.bladder) - 25.0)
		needs.fun = maxf(0.0, float(needs.fun) - 15.0)
		_log("Worked a shift (+$%d, mood %.0f)" % [pay, mood])
	elif k in ACTIONS:
		var need: String = str(ACTIONS[k].need)
		needs[need] = minf(100.0, float(needs[need]) + float(ACTIONS[k].restore))
		if k == "socialize":
			var npc := _deepen_friend()
			rel[npc] = minf(100.0, float(rel[npc]) + 12.0)
			_log("Hung out with %s (rel %.0f)" % [npc, float(rel[npc])])
	action = ""
	action_left = 0

## The friend to invest in: the highest relationship not yet maxed (build a best friend).
func _deepen_friend() -> String:
	var pick := NPCS[0]
	var best := -1.0
	for npc in NPCS:
		var v: float = float(rel[npc])
		if v < 100.0 and v > best:
			best = v
			pick = npc
	return pick

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

## input = {action: String} — start an action when idle (ignored while busy). "" = let be.
func tick(input: Dictionary) -> void:
	# idle → accept an action choice
	if action == "" and str(input.get("action", "")) != "":
		start_action(str(input.action))
	# progress current action
	if action != "":
		action_left -= 1
		if action_left <= 0:
			_finish_action()
	# needs decay (sleep pauses most decay; being at work is covered by the shift drain)
	for n in NEEDS:
		var d: float = float(DECAY[n])
		if action == "sleep" and n != "hunger":
			d *= 0.15
		needs[n] = maxf(0.0, float(needs[n]) - d)
	# exhaustion: energy at 0 forces a collapse-sleep
	if float(needs.energy) <= 0.0 and action != "sleep":
		collapses += 1
		action = "sleep"
		action_left = 40
		_log("Collapsed from exhaustion!")
	_recompute_mood()
	# aspiration check
	if not aspiration and money >= ASPIRE_MONEY and best_friend() >= float(ASPIRE_FRIEND):
		aspiration = true
		_log("LIFE GOAL achieved on day %d!" % day)
	# clock
	tick_of_day += 1
	frame += 1
	if tick_of_day >= DAY_TICKS:
		_new_day()

func _new_day() -> void:
	tick_of_day = 0
	day += 1
	worked_today = false
	# a seeded daily event
	var roll := rng.randf()
	if roll < 0.18:
		money = max(0, money - 60)
		_log("Day %d: a bill arrived (-$60)" % day)
	elif roll < 0.34:
		var npc: String = NPCS[rng.randi_range(0, NPCS.size() - 1)]
		rel[npc] = minf(100.0, float(rel[npc]) + 10.0)
		_log("Day %d: a nice chat with %s (+rel)" % [day, npc])
	elif roll < 0.44:
		needs.fun = minf(100.0, float(needs.fun) + 20.0)
		_log("Day %d: woke up inspired (+fun)" % day)

# --------------------------------------------------------------------------- #
# Heuristic auto-play seat (probe / demo) — a well-adjusted daily routine
# --------------------------------------------------------------------------- #

func ai_choice() -> String:
	if action != "":
		return ""
	# urgent needs first
	if float(needs.bladder) < 30.0:
		return "toilet"
	if float(needs.hunger) < 30.0:
		return "eat"
	if float(needs.energy) < 25.0:
		return "sleep"
	if float(needs.hygiene) < 30.0:
		return "shower"
	# go to work on schedule if rested enough
	if is_work_time() and not worked_today and float(needs.energy) > 30.0 and float(needs.bladder) > 25.0:
		return "work"
	# top up social + fun in free time
	if float(needs.social) < 45.0:
		return "socialize"
	if float(needs.fun) < 45.0:
		return "relax"
	# nighttime → sleep to pass the hours; else keep topped up
	if hour() >= 22 or hour() < 6:
		if float(needs.energy) < 90.0:
			return "sleep"
	if float(needs.energy) < 55.0:
		return "sleep"
	return ""

func auto_step() -> void:
	tick({"action": ai_choice()})

func auto_play_days(n: int) -> void:
	var target_frame := frame + n * DAY_TICKS
	var guard := 0
	while frame < target_frame and guard < n * DAY_TICKS + 10:
		auto_step()
		guard += 1

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[D%d %02d:00] %s" % [day, hour(), s])
	if log_lines.size() > 40:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func _q(v: float) -> int:
	return int(round(v))

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%s|%d|%d|%d" % [frame, day, tick_of_day, money, action, action_left,
		int(aspiration), collapses]
	for n in NEEDS:
		s += "|N%s%d" % [n, _q(needs[n])]
	for npc in NPCS:
		s += "|R%s%d" % [npc, _q(rel[npc])]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "needs": needs.duplicate(), "money": money, "day": day,
		"tick_of_day": tick_of_day, "frame": frame, "action": action, "action_left": action_left,
		"worked_today": worked_today, "rel": rel.duplicate(), "aspiration": aspiration,
		"collapses": collapses, "seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	needs = (d.get("needs", {}) as Dictionary).duplicate()
	money = int(d.get("money", 0))
	day = int(d.get("day", 1))
	tick_of_day = int(d.get("tick_of_day", 0))
	frame = int(d.get("frame", 0))
	action = str(d.get("action", ""))
	action_left = int(d.get("action_left", 0))
	worked_today = bool(d.get("worked_today", false))
	rel = (d.get("rel", {}) as Dictionary).duplicate()
	aspiration = bool(d.get("aspiration", false))
	collapses = int(d.get("collapses", 0))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
	_recompute_mood()
