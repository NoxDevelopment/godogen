class_name IdleEngine
extends RefCounted
## Pure, seedable INCREMENTAL / IDLE-CLICKER engine (Cookie Clicker lineage) run as a
## DETERMINISTIC FIXED-TIMESTEP sim at 60 ticks/sec: tap to earn, spend the currency on
## GENERATORS (each with a x1.15 escalating cost + passive output) and one-off UPGRADES
## (building + click multipliers), and chase seeded GOLDEN bonuses (lump payouts + timed
## frenzies) — with a prestige-style ascension goal. Node-free + Time-free: the ONLY
## randomness is the seeded golden-bonus schedule, so a whole run replays BYTE-IDENTICALLY
## from a seed (FNV-1a checksum over string-formatted floats, overflow-proof) and drives
## headlessly. The scene (idle_view.gd) + GameManager wrap this; all rules live here (ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const TICKS_PER_SEC := 60.0
const ASCEND_GOAL := 1.0e6          ## total earned to unlock ascension (the first-prestige milestone)

# generators: {name, base_cost, cost_growth, base_cps}
const GENERATORS := [
	{"name": "Clicker", "cost": 15.0, "growth": 1.15, "cps": 0.1},
	{"name": "Helper", "cost": 100.0, "growth": 1.15, "cps": 1.0},
	{"name": "Farm", "cost": 1100.0, "growth": 1.15, "cps": 8.0},
	{"name": "Mine", "cost": 12000.0, "growth": 1.15, "cps": 47.0},
	{"name": "Factory", "cost": 130000.0, "growth": 1.15, "cps": 260.0},
	{"name": "Bank", "cost": 1400000.0, "growth": 1.15, "cps": 1400.0},
	{"name": "Lab", "cost": 20000000.0, "growth": 1.15, "cps": 7800.0},
]

# one-off upgrades: {id, kind: "click"/"gen", target(gen idx for gen), mult, cost, req}
const UPGRADES := [
	{"id": "u_click1", "kind": "click", "target": -1, "mult": 2.0, "cost": 100.0, "req": 0},
	{"id": "u_click2", "kind": "click", "target": -1, "mult": 2.0, "cost": 5000.0, "req": 0},
	{"id": "u_gen0", "kind": "gen", "target": 0, "mult": 2.0, "cost": 200.0, "req": 5},
	{"id": "u_gen1", "kind": "gen", "target": 1, "mult": 2.0, "cost": 2000.0, "req": 5},
	{"id": "u_gen2", "kind": "gen", "target": 2, "mult": 2.0, "cost": 22000.0, "req": 5},
	{"id": "u_gen3", "kind": "gen", "target": 3, "mult": 2.0, "cost": 240000.0, "req": 5},
	{"id": "u_gen4", "kind": "gen", "target": 4, "mult": 2.0, "cost": 2600000.0, "req": 5},
	{"id": "u_all", "kind": "gen", "target": -2, "mult": 2.0, "cost": 10000000.0, "req": 0},
]

const BASE_CLICK := 1.0
const GOLDEN_MIN := 900             ## min ticks between golden spawns (15s)
const GOLDEN_MAX := 2400            ## max ticks (40s)
const GOLDEN_WINDOW := 300          ## ticks it stays tappable (5s)
const FRENZY_TICKS := 420           ## 7s frenzy
const FRENZY_MULT := 7.0
const GOLDEN_LUMP_SECS := 90.0      ## lump = this many seconds of current cps

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var cookies := 0.0
var total_earned := 0.0
var counts: Array = []              ## per-generator owned count
var bought: Dictionary = {}         ## upgrade id → true
var gen_mult: Array = []            ## per-generator multiplier
var click_mult := 1.0
var frenzy := 0                     ## remaining frenzy ticks
var golden_timer := 0               ## ticks until next golden spawn
var golden_active := 0              ## remaining tappable ticks (0 = none)
var golden_kind := ""               ## "lump" | "frenzy"
var ascended := false
var frame := 0
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	cookies = 0.0
	total_earned = 0.0
	counts = []
	gen_mult = []
	for i in range(GENERATORS.size()):
		counts.append(0)
		gen_mult.append(1.0)
	bought = {}
	click_mult = 1.0
	frenzy = 0
	golden_active = 0
	golden_kind = ""
	ascended = false
	frame = 0
	log_lines = []
	golden_timer = rng.randi_range(GOLDEN_MIN, GOLDEN_MAX)

# --------------------------------------------------------------------------- #
# Derived rates
# --------------------------------------------------------------------------- #

func click_power() -> float:
	var p := BASE_CLICK * click_mult
	if frenzy > 0:
		p *= FRENZY_MULT
	return p

func cps() -> float:
	var total := 0.0
	for i in range(GENERATORS.size()):
		total += float(counts[i]) * float(GENERATORS[i].cps) * float(gen_mult[i])
	if frenzy > 0:
		total *= FRENZY_MULT
	return total

func gen_cost(i: int) -> float:
	var g: Dictionary = GENERATORS[i]
	return float(g.cost) * pow(float(g.growth), float(counts[i]))

func upgrade_available(u: Dictionary) -> bool:
	if bought.has(str(u.id)):
		return false
	if str(u.kind) == "gen" and int(u.target) >= 0 and int(counts[int(u.target)]) < int(u.req):
		return false
	return true

# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #

func do_click() -> void:
	var p := click_power()
	cookies += p
	total_earned += p

func buy_gen(i: int) -> bool:
	if i < 0 or i >= GENERATORS.size():
		return false
	var c := gen_cost(i)
	if cookies < c:
		return false
	cookies -= c
	counts[i] = int(counts[i]) + 1
	return true

func buy_upgrade(uid: String) -> bool:
	for u in UPGRADES:
		if str(u.id) != uid:
			continue
		if not upgrade_available(u) or cookies < float(u.cost):
			return false
		cookies -= float(u.cost)
		bought[uid] = true
		_apply_upgrade(u)
		_log("Bought upgrade %s" % uid)
		return true
	return false

func _apply_upgrade(u: Dictionary) -> void:
	if str(u.kind) == "click":
		click_mult *= float(u.mult)
	elif str(u.kind) == "gen":
		if int(u.target) == -2:
			for i in range(gen_mult.size()):
				gen_mult[i] = float(gen_mult[i]) * float(u.mult)
		else:
			var t := int(u.target)
			gen_mult[t] = float(gen_mult[t]) * float(u.mult)

func tap_golden() -> bool:
	if golden_active <= 0:
		return false
	golden_active = 0
	if golden_kind == "frenzy":
		frenzy = FRENZY_TICKS
		_log("Golden: FRENZY! x%d for %ds" % [int(FRENZY_MULT), int(FRENZY_TICKS / TICKS_PER_SEC)])
	else:
		var lump := cps() * GOLDEN_LUMP_SECS
		if lump < click_power() * 50.0:
			lump = click_power() * 50.0        # early-game floor so it's worth tapping
		cookies += lump
		total_earned += lump
		_log("Golden: LUMP +%.0f" % lump)
	return true

# --------------------------------------------------------------------------- #
# Simulation tick
# --------------------------------------------------------------------------- #

## input = {click:bool, buy_gen:int(-1 none), buy_up:String(""), tap:bool}
func tick(input: Dictionary) -> void:
	if bool(input.get("click", false)):
		do_click()
	# passive income
	var produced := cps() / TICKS_PER_SEC
	cookies += produced
	total_earned += produced
	# purchases
	var bg: int = int(input.get("buy_gen", -1))
	if bg >= 0:
		buy_gen(bg)
	var bu: String = str(input.get("buy_up", ""))
	if bu != "":
		buy_upgrade(bu)
	if bool(input.get("tap", false)):
		tap_golden()
	# frenzy countdown
	if frenzy > 0:
		frenzy -= 1
	# golden lifecycle
	if golden_active > 0:
		golden_active -= 1
	else:
		golden_timer -= 1
		if golden_timer <= 0:
			golden_active = GOLDEN_WINDOW
			golden_kind = "frenzy" if rng.randf() < 0.4 else "lump"
			golden_timer = rng.randi_range(GOLDEN_MIN, GOLDEN_MAX)
	if not ascended and total_earned >= ASCEND_GOAL:
		ascended = true
		_log("Ascension unlocked! (total %.0f)" % total_earned)
	frame += 1

# --------------------------------------------------------------------------- #
# Heuristic auto-play seat — click, grab goldens, buy the best value. Deterministic.
# --------------------------------------------------------------------------- #

func ai_input() -> Dictionary:
	var inp := {"click": true, "buy_gen": -1, "buy_up": "", "tap": golden_active > 0}
	# buy the cheapest available upgrade we can afford (upgrades are high-value)
	for u in UPGRADES:
		if upgrade_available(u) and cookies >= float(u.cost):
			inp.buy_up = str(u.id)
			return inp
	# else buy the generator with the best cps-per-cost we can afford
	var best := -1
	var best_ratio := 0.0
	for i in range(GENERATORS.size()):
		var c := gen_cost(i)
		if cookies >= c and c > 0.0:
			var ratio := float(GENERATORS[i].cps) * float(gen_mult[i]) / c
			if ratio > best_ratio:
				best_ratio = ratio
				best = i
	inp.buy_gen = best
	return inp

func auto_step(_policy: String = "greedy") -> void:
	tick(ai_input())

func auto_play_ticks(n: int) -> void:
	for _i in range(n):
		auto_step("greedy")

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append("[%.1fs] %s" % [float(frame) / TICKS_PER_SEC, s])
	if log_lines.size() > 30:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over string-formatted state — overflow-proof) + ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%.4f|%.4f|%.4f|%d|%d|%d|%s" % [frame, cookies, total_earned, click_mult,
		frenzy, golden_active, int(ascended), golden_kind]
	for i in range(counts.size()):
		s += "|G%d,%.4f" % [int(counts[i]), float(gen_mult[i])]
	s += "|U%d" % bought.size()
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "cookies": cookies, "total_earned": total_earned, "counts": counts.duplicate(),
		"bought": bought.duplicate(), "gen_mult": gen_mult.duplicate(), "click_mult": click_mult,
		"frenzy": frenzy, "golden_timer": golden_timer, "golden_active": golden_active,
		"golden_kind": golden_kind, "ascended": ascended, "frame": frame,
		"seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	cookies = float(d.get("cookies", 0.0))
	total_earned = float(d.get("total_earned", 0.0))
	counts = (d.get("counts", []) as Array).duplicate()
	bought = (d.get("bought", {}) as Dictionary).duplicate()
	gen_mult = (d.get("gen_mult", []) as Array).duplicate()
	click_mult = float(d.get("click_mult", 1.0))
	frenzy = int(d.get("frenzy", 0))
	golden_timer = int(d.get("golden_timer", 0))
	golden_active = int(d.get("golden_active", 0))
	golden_kind = str(d.get("golden_kind", ""))
	ascended = bool(d.get("ascended", false))
	frame = int(d.get("frame", 0))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
