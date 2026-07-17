class_name VenueMgmtEngine
extends RefCounted
## Pure, seedable ADULT-MANAGEMENT engine (a mature-themed VENUE / AGENCY MANAGEMENT TYCOON) run as
## a DETERMINISTIC sim. This template ships the MANAGEMENT SYSTEMS ONLY — a staff roster, room
## upgrades, a seeded daily client flow, a skill-matching shift-assignment algorithm, and a
## cash/reputation economy — plus a `mature_content` GATING FLAG (OFF by default) that only calls
## EMPTY author hooks. It ships NO explicit content; an author who adds mature content owns their
## own assets, an age-verification gate, and platform compliance. Node-free + Time-free: one seeded
## RNG drives the client flow, so a whole run replays BYTE-IDENTICALLY from a seed (FNV-1a
## checksum). The scene (venue_view.gd) + GameManager wrap this; all rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Economy / rules
# --------------------------------------------------------------------------- #

const DAY_CAP := 30
const CASH_GOAL := 12000.0
const REP_GOAL := 75.0
const START_CASH := 700.0
const MAX_STAFF := 6
const MAX_ROOM_LVL := 4
const HIRE_COST := 400.0
const UPGRADE_COST := 500.0
const MARKETING_COST := 250.0
const STAMINA_WORK_MIN := 18
const STAMINA_WORK_MAX := 28
const REST_STAMINA := 42
const REST_MOOD := 9
const WORK_STAMINA_FLOOR := 25       ## staff below this can't take a client this shift

const FIRST_NAMES := ["Ava", "Lena", "Mika", "Rho", "Sol", "Nix", "Vera", "Cleo", "Juno", "Remy",
	"Kai", "Zara", "Ines", "Bex", "Ode", "Wren"]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var day := 1
var cash := START_CASH
var reputation := 30.0
var marketing := 0.0                 ## decays each day; boosts client count
var staff: Array = []                ## {name, skill, stamina, mood, popularity, wage}
var rooms: Array = []                ## {level} — index is a station
var last_clients: Array = []         ## last shift's generated clients (for the view)
var last_served := 0
var last_income := 0.0
var day_log: Array = []
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
	cash = START_CASH
	reputation = 30.0
	marketing = 0.0
	staff = []
	rooms = [{"level": 1}, {"level": 1}]
	last_clients = []
	last_served = 0
	last_income = 0.0
	day_log = []
	game_over = false
	won = false
	mature_content = false
	log_lines = []
	# start with two hires
	_hire_internal()
	_hire_internal()

func _new_staff() -> Dictionary:
	var nm: String = str(FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)])
	var skill := rng.randi_range(4, 8)
	return {"name": nm, "skill": skill, "stamina": 100.0, "mood": 80.0,
		"popularity": float(rng.randi_range(20, 45)), "wage": 40.0 + skill * 10.0}

func _hire_internal() -> bool:
	if staff.size() >= MAX_STAFF:
		return false
	staff.append(_new_staff())
	return true

# --------------------------------------------------------------------------- #
# Management actions (player OR ai; each returns true if applied)
# --------------------------------------------------------------------------- #

func hire() -> bool:
	if game_over or staff.size() >= MAX_STAFF or cash < HIRE_COST:
		return false
	cash -= HIRE_COST
	_hire_internal()
	_log("Hired %s" % str(staff[staff.size() - 1].name))
	return true

func add_room() -> bool:
	# open a new station (bounded) — raises capacity to serve more clients per shift
	if game_over or rooms.size() >= 4 or cash < UPGRADE_COST:
		return false
	cash -= UPGRADE_COST
	rooms.append({"level": 1})
	_log("Opened station %d" % rooms.size())
	return true

func upgrade_room(idx: int) -> bool:
	if game_over or idx < 0 or idx >= rooms.size() or cash < UPGRADE_COST:
		return false
	if int(rooms[idx].level) >= MAX_ROOM_LVL:
		return false
	cash -= UPGRADE_COST
	rooms[idx].level = int(rooms[idx].level) + 1
	_log("Upgraded station %d to L%d" % [idx + 1, int(rooms[idx].level)])
	return true

func run_marketing() -> bool:
	if game_over or cash < MARKETING_COST:
		return false
	cash -= MARKETING_COST
	marketing += 6.0
	_log("Marketing campaign (+client flow)")
	return true

# --------------------------------------------------------------------------- #
# The daily shift (a pure assignment algorithm) + close-of-day economy
# --------------------------------------------------------------------------- #

func _room_bonus(level: int) -> float:
	return 1.0 + 0.18 * (level - 1)

## capacity = how many clients the venue can physically serve this shift
func _capacity() -> int:
	var cap := 0
	for r in rooms:
		cap += 1 + int(r.level) / 2
	return cap

func _gen_clients() -> Array:
	var count := 3 + int(reputation / 12.0) + int(marketing / 3.0)
	count = clampi(count, 3, 12)
	var out: Array = []
	for _i in range(count):
		var tier := 1
		var roll := rng.randf() * 100.0
		var rep_pull := reputation
		if roll < rep_pull * 0.55: tier = 3
		elif roll < rep_pull * 0.9: tier = 2
		if rng.randf() < reputation / 240.0: tier += 1     # occasional premium client
		tier = clampi(tier, 1, 5)
		out.append({"tier": tier, "budget": 85.0 * tier + rng.randf() * 55.0,
			"demand": 1 + tier / 2 + rng.randi_range(0, 1), "patience": rng.randi_range(1, 3)})
	return out

## Assign rested staff to the highest-budget clients (greedy best-fit). Pure + deterministic.
func run_shift() -> void:
	if game_over:
		return
	var clients := _gen_clients()
	last_clients = clients.duplicate(true)
	# clients by budget desc
	var order: Array = []
	for i in range(clients.size()):
		order.append(i)
	order.sort_custom(func(a, b): return float(clients[a].budget) > float(clients[b].budget))
	# available staff by skill desc
	var avail: Array = []
	for s in staff:
		if float(s.stamina) >= WORK_STAMINA_FLOOR:
			avail.append(s)
	avail.sort_custom(func(a, b): return int(a.skill) > int(b.skill))
	# best rooms by bonus desc, each usable up to its slot capacity
	var room_slots: Array = []
	for r in rooms:
		var slots := 1 + int(r.level) / 2
		for _k in range(slots):
			room_slots.append(_room_bonus(int(r.level)))
	room_slots.sort_custom(func(a, b): return float(a) > float(b))
	var cap: int = min(min(avail.size(), room_slots.size()), _capacity())
	var served := 0
	var income := 0.0
	var ai := 0
	for oi in range(order.size()):
		if ai >= cap:
			break
		var c = clients[order[oi]]
		var worker = avail[ai]
		var rbonus: float = float(room_slots[ai])
		var effective := float(worker.skill) + (rbonus - 1.0) * 4.0
		if effective >= float(c.demand):
			var gain: float = float(c.budget) * (1.05 + 0.08 * float(worker.skill)) * (1.0 + float(worker.popularity) / 200.0) * rbonus
			income += gain
			reputation = minf(100.0, reputation + 2.0)
			worker.popularity = minf(100.0, float(worker.popularity) + 2.0)
			worker.mood = maxf(0.0, float(worker.mood) - 3.0)
			# GATED, EMPTY hook at premium service — no content ships in the template
			if mature_content and int(c.tier) >= 4:
				_mature_hook("premium_service", {"tier": int(c.tier), "worker": str(worker.name)})
		else:
			income += float(c.budget) * 0.35
			reputation = maxf(0.0, reputation - 1.0)
			worker.mood = maxf(0.0, float(worker.mood) - 5.0)
		worker.stamina = maxf(0.0, float(worker.stamina) - rng.randi_range(STAMINA_WORK_MIN, STAMINA_WORK_MAX))
		served += 1
		ai += 1
	# unserved clients sour reputation a little
	var unserved: int = order.size() - served
	if unserved > 0:
		reputation = maxf(0.0, reputation - minf(2.0, float(unserved) * 0.35))
	cash += income
	last_served = served
	last_income = income
	_close_day(income)

func _close_day(income: float) -> void:
	var wages := 0.0
	for s in staff:
		wages += float(s.wage)
	var upkeep := 65.0 * float(rooms.size()) + 8.0 * float(day)   ## rising overhead pressures the late game
	cash -= wages + upkeep
	marketing = maxf(0.0, marketing - 2.0)
	# rest recovers staff
	for s in staff:
		s.stamina = minf(100.0, float(s.stamina) + REST_STAMINA)
		s.mood = minf(100.0, float(s.mood) + REST_MOOD)
	day_log.append({"day": day, "income": income, "wages": wages, "cash": cash, "rep": reputation, "served": last_served})
	_log("Day %d: served %d, income %.0f, wages %.0f, cash %.0f, rep %.0f" % [day, last_served, income, wages, cash, reputation])
	if cash < 0.0:
		game_over = true
		won = false
		_log("BANKRUPT on day %d" % day)
		return
	if cash >= CASH_GOAL and reputation >= REP_GOAL:
		game_over = true
		won = true
		_log("GOAL MET on day %d (cash %.0f, rep %.0f)" % [day, cash, reputation])
		return
	day += 1
	if day > DAY_CAP:
		game_over = true
		won = cash >= CASH_GOAL and reputation >= REP_GOAL

## INTENTIONALLY EMPTY. Author hook for gated mature milestones. Left empty on purpose — the
## template ships the management SYSTEMS + this gate, and NO explicit content. Wire your OWN
## age-verified, platform-compliant content here if you choose to.
func _mature_hook(_event: String, _ctx: Dictionary) -> void:
	pass

# --------------------------------------------------------------------------- #
# Deterministic manager auto-seat (probe / demo)
# --------------------------------------------------------------------------- #

func _busiest_room() -> int:
	var best := 0
	var bl := 99
	for i in range(rooms.size()):
		if int(rooms[i].level) < bl:
			bl = int(rooms[i].level)
			best = i
	return best

## One AI turn: make sensible management moves, then run the shift.
func ai_day() -> void:
	if game_over:
		return
	# open a station early if capacity-bound and flush
	if rooms.size() < 3 and staff.size() >= rooms.size() * 2 and cash > UPGRADE_COST * 2.0:
		add_room()
	# hire toward a full roster while affordable
	if staff.size() < MAX_STAFF and cash > HIRE_COST * 2.2:
		hire()
	# upgrade the weakest room when there's a cash buffer
	if cash > UPGRADE_COST * 2.5:
		upgrade_room(_busiest_room())
	# marketing when reputation is lagging the goal and there's spare cash
	if reputation < REP_GOAL - 10.0 and cash > MARKETING_COST * 2.0:
		run_marketing()
	run_shift()

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < DAY_CAP + 5:
		ai_day()
		guard += 1
	if not game_over:
		game_over = true

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
	var s := "%d|%d|%d|%d|%d|%d|%d" % [day, _q(cash), _q(reputation), _q(marketing),
		int(game_over), int(won), int(mature_content)]
	for st in staff:
		s += "|S%s,%d,%d,%d,%d" % [str(st.name), int(st.skill), _q(float(st.stamina)), _q(float(st.mood)), _q(float(st.popularity))]
	for r in rooms:
		s += "|R%d" % int(r.level)
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {"version": 1, "day": day, "cash": cash, "reputation": reputation, "marketing": marketing,
		"staff": staff.duplicate(true), "rooms": rooms.duplicate(true), "game_over": game_over,
		"won": won, "mature_content": mature_content, "seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	cash = float(d.get("cash", START_CASH))
	reputation = float(d.get("reputation", 30.0))
	marketing = float(d.get("marketing", 0.0))
	staff = (d.get("staff", []) as Array).duplicate(true)
	rooms = (d.get("rooms", []) as Array).duplicate(true)
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	mature_content = bool(d.get("mature_content", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
