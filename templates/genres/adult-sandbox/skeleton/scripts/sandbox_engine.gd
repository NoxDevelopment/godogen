class_name SandboxEngine
extends RefCounted
## Pure, seedable ADULT-SANDBOX engine (a mature-themed open LIFE / RELATIONSHIP SANDBOX) run as a
## DETERMINISTIC sim. This template ships the SANDBOX SYSTEMS ONLY — an open map of locations, a
## time-of-day / day-of-week clock, player needs (energy / money / fitness / mood), NPCs on seeded
## weekly SCHEDULES, and multi-NPC RELATIONSHIPS with stages — PLUS a `mature_content` GATING FLAG
## (OFF by default) that only calls EMPTY author hooks. It ships NO explicit content; an author who
## adds mature content owns their own assets, an age-verification gate, and platform compliance.
## Node-free + Time-free: one seeded RNG lays out the NPC schedules, so a whole run replays
## BYTE-IDENTICALLY from a seed (FNV-1a checksum). The scene (sandbox_view.gd) + GameManager wrap
## this; all rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# World / rules
# --------------------------------------------------------------------------- #

const LOCATIONS := ["home", "work", "gym", "bar", "park", "cafe", "shop"]
const HOME := 0
const WORK := 1
const GYM := 2
const SHOP := 6
const BLOCKS := 6                    ## time blocks per day (morning..late)
const DAYS := 21                     ## the sandbox runs this many days
const PUBLIC_FIRST := 1              ## NPCs roam LOCATIONS[1..end] (never the player's home)
const NPC_NAMES := ["Aria", "Bess", "Cleo", "Dana"]
# relationship stage thresholds
const STAGE_NAMES := ["Stranger", "Acquaintance", "Friend", "Close", "Partner"]
const STAGE_THRESH := [0, 20, 45, 70, 90]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var day := 1
var block := 0
var location := HOME
var energy := 100.0
var money := 100
var fitness := 10.0
var mood := 70.0
var gifts := 0
var npcs: Array = []                 ## {name, affinity, rel}
var schedule: Array = []             ## [npc][dayOfWeek][block] -> location index
var _trained_today := false
var game_over := false
var won := false
var mature_content := false          ## GATE — OFF by default; only unlocks empty hooks
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	day = 1
	block = 0
	location = HOME
	energy = 100.0
	money = 100
	fitness = 10.0
	mood = 70.0
	gifts = 0
	_trained_today = false
	game_over = false
	won = false
	mature_content = false
	log_lines = []
	npcs = []
	for nm in NPC_NAMES:
		npcs.append({"name": str(nm), "affinity": 0.85 + rng.randf() * 0.4, "rel": 0.0})
	# seeded weekly schedules — each NPC roams the PUBLIC locations across 7 days x BLOCKS
	schedule = []
	for _i in range(npcs.size()):
		var week: Array = []
		for _dow in range(7):
			var row: Array = []
			for _b in range(BLOCKS):
				row.append(rng.randi_range(PUBLIC_FIRST, LOCATIONS.size() - 1))
			week.append(row)
		schedule.append(week)

func dow() -> int:
	return (day - 1) % 7

func npc_location(i: int, d: int, b: int) -> int:
	return int(schedule[i][(d - 1) % 7][b])

func npc_here(i: int) -> bool:
	return npc_location(i, day, block) == location

func present_npcs() -> Array:
	var out: Array = []
	for i in range(npcs.size()):
		if npc_here(i):
			out.append(i)
	return out

func stage_idx(rel: float) -> int:
	var s := 0
	for i in range(STAGE_THRESH.size()):
		if rel >= float(STAGE_THRESH[i]):
			s = i
	return s

func stage_name(rel: float) -> String:
	return STAGE_NAMES[stage_idx(rel)]

func progress() -> int:
	var p := 0
	for n in npcs:
		p += stage_idx(float(n.rel)) * 10
	return p + int(fitness) + money / 10

func max_rel() -> float:
	var m := 0.0
	for n in npcs:
		m = maxf(m, float(n.rel))
	return m

# --------------------------------------------------------------------------- #
# Actions — travel is FREE (repositioning), actions advance a time block
# --------------------------------------------------------------------------- #

func travel(loc: int) -> void:
	if game_over or loc < 0 or loc >= LOCATIONS.size():
		return
	location = loc

func _advance_block() -> void:
	block += 1
	if block >= BLOCKS:
		# out of time — a forced late night home (a small mood hit), then a new day
		mood = maxf(0.0, mood - 4.0)
		_new_day()

func _new_day() -> void:
	day += 1
	block = 0
	_trained_today = false
	if day > DAYS:
		_finish()

func sleep() -> void:
	if game_over:
		return
	if location != HOME:
		location = HOME       # travel home is free; sleeping is at home
	energy = 100.0
	mood = minf(100.0, mood + 6.0)
	_new_day()

func work() -> bool:
	if game_over or location != WORK or energy < 20.0:
		return false
	money += 40
	energy = maxf(0.0, energy - 25.0)
	mood = maxf(0.0, mood - 4.0)
	_advance_block()
	return true

func train() -> bool:
	if game_over or location != GYM or energy < 18.0:
		return false
	fitness = minf(100.0, fitness + 6.0)
	energy = maxf(0.0, energy - 18.0)
	mood = maxf(0.0, mood - 2.0)
	_trained_today = true
	_advance_block()
	return true

func buy_gift() -> bool:
	if game_over or location != SHOP or money < 30:
		return false
	money -= 30
	gifts += 1
	_advance_block()
	return true

func relax() -> bool:
	# a self-care action at a leisure spot (bar/park/cafe)
	if game_over or location == HOME or location == WORK:
		return false
	mood = minf(100.0, mood + 10.0)
	energy = maxf(0.0, energy - 6.0)
	_advance_block()
	return true

func socialize(i: int) -> bool:
	if game_over or i < 0 or i >= npcs.size() or not npc_here(i) or energy < 10.0:
		return false
	var gain := 6.0 * (0.7 + mood / 200.0) * float(npcs[i].affinity)
	_apply_rel(i, gain)
	energy = maxf(0.0, energy - 12.0)
	mood = minf(100.0, mood + 3.0)
	_advance_block()
	return true

func gift(i: int) -> bool:
	if game_over or i < 0 or i >= npcs.size() or not npc_here(i) or gifts <= 0:
		return false
	gifts -= 1
	_apply_rel(i, 15.0)
	_advance_block()
	return true

func wait() -> void:
	if game_over:
		return
	energy = maxf(0.0, energy - 2.0)
	_advance_block()

func _apply_rel(i: int, amount: float) -> void:
	var before := stage_idx(float(npcs[i].rel))
	npcs[i].rel = clampf(float(npcs[i].rel) + amount, 0.0, 100.0)
	var after := stage_idx(float(npcs[i].rel))
	if after > before:
		_log("%s is now your %s" % [str(npcs[i].name), stage_name(float(npcs[i].rel))])
		# GATED, EMPTY hook when a relationship reaches the top (Partner) stage — no content ships
		if after >= 4 and mature_content:
			_mature_hook("partner_stage", {"npc": str(npcs[i].name)})

func _finish() -> void:
	game_over = true
	won = max_rel() >= float(STAGE_THRESH[3])     # at least one "Close" relationship
	_log("Sandbox over: progress %d, best relationship %s" % [progress(), stage_name(max_rel())])

## INTENTIONALLY EMPTY. Author hook for gated mature milestones. Left empty on purpose — the
## template ships the sandbox SYSTEMS + this gate, and NO explicit content. Wire your OWN
## age-verified, platform-compliant content here if you choose to.
func _mature_hook(_event: String, _ctx: Dictionary) -> void:
	pass

# --------------------------------------------------------------------------- #
# Deterministic resident auto-seat (probe / demo)
# --------------------------------------------------------------------------- #

## The not-yet-Partner NPC with the highest relationship (push one toward the top).
func _best_target() -> int:
	var best := -1
	var bv := -1.0
	for i in range(npcs.size()):
		if float(npcs[i].rel) >= 90.0:
			continue
		if float(npcs[i].rel) > bv:
			bv = float(npcs[i].rel)
			best = i
	return best if best >= 0 else 0

func ai_step() -> void:
	if game_over:
		return
	# 1) survival: sleep when exhausted
	if energy < 25.0:
		sleep()
		return
	# 2) earn when broke
	if money < 40:
		travel(WORK)
		work()
		return
	# 3) once a day, keep fit
	if not _trained_today and energy > 55.0 and money > 55:
		travel(GYM)
		train()
		return
	# 4) stock a gift when flush
	if gifts < 1 and money > 110:
		travel(SHOP)
		buy_gift()
		return
	# 5) advance the best relationship: go to where they are now, gift or socialize
	var t := _best_target()
	travel(npc_location(t, day, block))
	if npc_here(t):
		if gifts > 0 and float(npcs[t].rel) < 85.0:
			gift(t)
		else:
			socialize(t)
		return
	# (unreachable when travelling to their exact slot, but stay safe)
	wait()

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < DAYS * BLOCKS * 4 + 10:
		ai_step()
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
	var s := "%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [day, block, location, _q(energy), money, _q(fitness),
		_q(mood), gifts, int(game_over), int(won)]
	for n in npcs:
		s += "|%s%d" % [str(n.name), _q(float(n.rel))]
	s += "|M%d" % int(mature_content)
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {"version": 1, "day": day, "block": block, "location": location, "energy": energy,
		"money": money, "fitness": fitness, "mood": mood, "gifts": gifts, "npcs": npcs.duplicate(true),
		"schedule": schedule.duplicate(true), "trained_today": _trained_today, "game_over": game_over,
		"won": won, "mature_content": mature_content, "seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	block = int(d.get("block", 0))
	location = int(d.get("location", HOME))
	energy = float(d.get("energy", 100.0))
	money = int(d.get("money", 100))
	fitness = float(d.get("fitness", 10.0))
	mood = float(d.get("mood", 70.0))
	gifts = int(d.get("gifts", 0))
	npcs = (d.get("npcs", []) as Array).duplicate(true)
	schedule = (d.get("schedule", []) as Array).duplicate(true)
	_trained_today = bool(d.get("trained_today", false))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	mature_content = bool(d.get("mature_content", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
