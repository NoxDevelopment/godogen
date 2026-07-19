class_name WarrenEngine
extends RefCounted
## res://scripts/warren_engine.gd
## THE PURE ENGINE — a deterministic, seedable ANIMAL-SOCIETY survival + migration
## RPG in the WATERSHIP DOWN / SECRET OF NIMH / AMERICAN TAIL lineage. You lead a
## small BAND of NAMED animals (rabbits / mice), each with a distinct SOCIAL ROLE,
## across a dangerous seeded landscape of STOPS to found and grow a THRIVING WARREN
## — surviving predators, seasons, hunger, and the band's own MORALE.
##
## Everything — the band, roles + abilities, the day/tick survival economy, seasons,
## predators + hazards, the social morale/cohesion layer, the migration quest, and
## win/loss — is a pure function of (state, day, seeded RNG). No Godot node / scene
## dependency lives in here: the whole game replays BYTE-IDENTICALLY from a seed and
## is fully headless-testable. GameManager owns one instance; warren.gd only reads
## state and forwards a decision.
##
## THE ARC (why it is a real RPG, not an abstraction):
##   * THE BAND — a colony of NAMED animals. Each has a SOCIAL ROLE (Chief / Scout /
##     Seer / Forager / Fighter / Storyteller / Kit), a SEX, an AGE (days), traits
##     (courage / wisdom / speed) + HEALTH (hp), NEEDS (hunger / fatigue), a BOND to
##     the band, and roles confer REAL abilities:
##       - FORAGER gathers measurably more food,
##       - SCOUT lowers the ambush rate (spots predators earlier),
##       - SEER gives an early-warning (better escape → less damage in a raid),
##       - FIGHTER raises the band's defence,
##       - STORYTELLER lifts MORALE on rest,
##       - CHIEF (leader) steadies morale + reduces dissent,
##       - KIT (young) cannot yet work but is the warren's future (matures into an
##         adult role).
##   * SURVIVAL SIM — SEASONS cycle over a year and modulate food + danger (lean,
##     dangerous WINTER; rich, calm SUMMER). Each day the band takes ONE decision;
##     the day then RESOLVES: everyone eats (starvation harms/kills), fatigue +
##     illness accrue, a hazard may strike, morale drifts, and — once settled — a
##     breeding pair REPRODUCES up to a population cap.
##   * PREDATORS + HAZARDS — >=3 threats (Fox / Hawk / Cat / the "Man" & his road/
##     machines) hunt on a deterministic model. A Scout/Seer warning + the band's
##     fighters/speed decide escape vs loss; a raid can KILL a named member.
##   * SOCIAL LAYER — MORALE/cohesion is driven by leadership, storytelling, losses,
##     and success; low morale → dissent → a member may DESERT (the band splinters).
##   * MIGRATION QUEST — the band travels a seeded chain of STOPS toward the goal:
##     found a NEW WARREN at a safe, food-rich site. Each leg costs days + risks a
##     predator encounter. You must ARRIVE with a viable founding group (enough
##     survivors + a breeding pair) and then GROW the warren to a target size.
##   * WIN = found the new warren AND grow it to TARGET_POP (a thriving society).
##     LOSS = the band is wiped out, falls below a viable founding size, or fails to
##     reach the site before the deadline. Both are genuinely reachable by a
##     deterministic auto-play policy; MAX_DAYS guarantees termination.
##
## DAY DISCIPLINE (deterministic AND terminating):
##   take_action() applies ONE decision then advances the day via _end_day() (a
##   MOVE_ON runs one _end_day per travel-day of the leg). _end_day() is a fixed
##   pipeline — eat → fatigue/illness → hazard → morale → reproduction → aging →
##   desertion → compact the fallen → judge — with no unbounded rescans, so every
##   run terminates under MAX_DAYS and every stochastic choice draws from the SEEDED
##   RNG whose state is saved. checksum() proves the whole state is byte-identical.

# =====================================================================
#  Social roles
# =====================================================================
const CHIEF := 0        ## leader — steadies morale, reduces dissent
const SCOUT := 1        ## reveals the road ahead, lowers the ambush rate
const SEER := 2         ## lookout — early-warning improves escape in a raid
const FORAGER := 3      ## gathers measurably more food
const FIGHTER := 4      ## protector — raises the band's defence
const STORYTELLER := 5  ## lifts MORALE on rest
const KIT := 6          ## young — cannot work yet, matures into an adult role
const ROLE_COUNT := 7
const ROLE_NAME: PackedStringArray = [
	"Chief", "Scout", "Seer", "Forager", "Fighter", "Storyteller", "Kit",
]
## Adult roles a maturing kit / a reassignment may take (never Kit).
const ADULT_ROLES: Array[int] = [CHIEF, SCOUT, SEER, FORAGER, FIGHTER, STORYTELLER]

# =====================================================================
#  Sex
# =====================================================================
const FEMALE := 0
const MALE := 1

# =====================================================================
#  Predators / hazards (>=3 threats)
# =====================================================================
const FOX := 0
const HAWK := 1
const CAT := 2
const MAN := 3          ## the "Man" — road, machines, snares; the deadliest threat
const PRED_COUNT := 4
const PRED_NAME: PackedStringArray = ["Fox", "Hawk", "Cat", "Man"]
## Raw attack power per predator (scaled by season + stop danger at resolution).
const PRED_ATTACK: PackedFloat32Array = [3.2, 2.7, 3.6, 5.2]

# =====================================================================
#  Seasons
# =====================================================================
const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3
const SEASON_NAME: PackedStringArray = ["Spring", "Summer", "Autumn", "Winter"]
const DAYS_PER_SEASON := 12
const SEASON_COUNT := 4
const DAYS_PER_YEAR := DAYS_PER_SEASON * SEASON_COUNT   ## 48
## Season food multiplier (lean winter, rich summer).
const SEASON_FOOD: PackedFloat32Array = [1.0, 1.25, 0.85, 0.45]
## Season danger multiplier (calm summer, harsh winter).
const SEASON_DANGER: PackedFloat32Array = [1.0, 0.85, 1.15, 1.45]

# =====================================================================
#  Player decisions (one per day; ASSIGN is a free management action)
# =====================================================================
const ACT_FORAGE := 0    ## gather food (role-weighted)
const ACT_SCOUT := 1     ## scout the next leg — lowers its ambush rate
const ACT_REST := 2      ## recover fatigue/hp; a Storyteller lifts morale
const ACT_MOVE_ON := 3   ## advance one leg toward the goal (costs leg-days + risk)
const ACT_SHELTER := 4   ## dig in / burrow — deepens safety for the coming day
const ACT_ASSIGN := 5    ## reassign a member's role (free; no day passes)
const ACTION_COUNT := 6
const ACTION_NAME: PackedStringArray = [
	"Forage", "Scout", "Rest", "Move On", "Shelter", "Assign Role",
]

# =====================================================================
#  Tuning (auditable constants)
# =====================================================================
# Time / termination.
const MAX_DAYS := 400        ## hard cap — a run always ends by here (loss if unresolved)
const DEADLINE_DAYS := 220   ## must REACH the new-warren site before this day

# Food economy.
const START_FOOD := 26
const FOOD_PER_ADULT := 2    ## food an adult eats per day
const FOOD_PER_KIT := 1      ## a kit eats less
const BASE_FORAGE := 20.0    ## base forage yield before role / season / site scaling
const FORAGER_BONUS := 0.5   ## extra forage weight a FORAGER contributes
const ADULT_FORAGE := 0.16   ## base forage weight any able adult contributes
const HUNGER_MAX := 100
const HUNGER_RISE := 30      ## hunger gained on an unfed day
const HUNGER_RECOVER := 24   ## hunger shed on a fed day
const STARVE_HP := 5         ## hp lost per day at max hunger

# Health / rest.
const HP_MAX := 20
const REST_HP := 3
const SHELTER_HP := 1
const ILL_HP := 3            ## hp lost to a bout of illness

# Fatigue.
const FATIGUE_MAX := 100
const TRAVEL_FATIGUE := 24   ## fatigue gained on a travel day
const CAMP_FATIGUE_DROP := 16 ## fatigue shed on a camp (non-travel) day
const REST_FATIGUE_DROP := 42 ## fatigue shed by a REST decision
const ILL_FATIGUE := 68      ## above this, illness becomes likely

# Morale / cohesion (the Watership heart).
const MORALE_MAX := 100.0
const MORALE_START := 62.0
const MORALE_EQ := 46.0        ## the level morale drifts toward absent inputs
const REST_MORALE := 5.0       ## morale a plain rest restores
const STORYTELLER_MORALE := 9.0 ## extra morale a Storyteller's tale gives on rest
const CHIEF_MORALE_REGEN := 3.0 ## daily morale nudge a living Chief provides
const FORAGE_MORALE := 3.0     ## a good haul cheers the band
const ARRIVE_MORALE := 16.0    ## reaching the promised site
const DEATH_MORALE := 17.0     ## grief per lost member
const DESERT_MORALE_FLOOR := 30.0 ## below this, dissent/desertion can occur

# Bond (per-member attachment; drives desertion + cohesion).
const BOND_START := 0.62
const BOND_GAIN := 0.03
const BOND_LOSS := 0.14
const BOND_DESERT := 0.34      ## a member this loosely bound may leave when morale is low

# Encounter / combat.
const FIGHTER_DEFENSE := 0.65  ## defence a FIGHTER adds on top of its base contribution
const SEER_DEFENSE_MULT := 1.4 ## early-warning multiplies band defence (better escape)
const SCOUT_CHANCE_MULT := 0.5 ## a SCOUT in the band halves the encounter chance
const SCOUTED_CHANCE_MULT := 0.5 ## a scouted leg halves the encounter chance again
const BASE_ENCOUNTER_TRAVEL := 0.5 ## base per-day encounter chance while travelling
const BASE_ENCOUNTER_CAMP := 0.12  ## base per-day encounter chance while camped
const SHELTER_CHANCE_MULT := 0.35  ## sheltering strongly cuts the next day's danger
const REPEL_MORALE := 5.0      ## morale for driving a predator off

# Migration / warren.
const DEFAULT_STOPS := 7       ## stops in the journey (start … goal), inclusive
const GOAL_DANGER := 0.1
const GOAL_FOOD := 1.0
const TARGET_POP := 12         ## grow the new warren to this to WIN
const VIABLE_FOUNDING := 3     ## below this many survivors → the founding fails (LOSS)
const POP_CAP := 16            ## hard population cap (bounds reproduction)
const REPRO_INTERVAL := 4      ## a settled breeding pair births at most every N days
const REPRO_FOOD_SURPLUS := 12 ## food stock must exceed this to breed
const REPRO_COST := 4          ## food a birth consumes
const KIT_MATURE_DAYS := 20    ## age (days) at which a kit becomes an adult

# =====================================================================
#  Phase
# =====================================================================
const PH_MIGRATION := 0   ## travelling toward the new-warren site
const PH_GROWTH := 1      ## arrived + founded; growing to the target
const PH_OVER := 2        ## game decided
const PHASE_NAME: PackedStringArray = ["Migration", "Growth", "Over"]

# =====================================================================
#  Name pools (deterministic — assigned in order, never from RNG)
# =====================================================================
const NAME_POOL: PackedStringArray = [
	"Hazel", "Fiver", "Bigwig", "Blackberry", "Dandelion", "Pipkin", "Holly",
	"Clover", "Bluebell", "Acorn", "Sorrel", "Nettle", "Bramble", "Thistle",
	"Willow", "Moss", "Fern", "Rowan", "Speedwell", "Hawkbit", "Cowslip",
	"Strawberry", "Campion", "Vervain", "Silver", "Buckthorn", "Laurel", "Ash",
]
const STOP_POOL: PackedStringArray = [
	"The Long Field", "Nuthanger Farm", "The Iron Road", "The Bourne Brook",
	"The Beech Hanger", "Caesar's Belt", "The Enborne Bank", "Cowslip's Snare",
	"The Common", "The Hollow Oak",
]

# =====================================================================
#  Live state — the band (parallel arrays; the fallen are compacted out)
# =====================================================================
var _mname: Array[String] = []
var _mrole := PackedInt32Array()
var _msex := PackedInt32Array()
var _mage := PackedInt32Array()        ## age in days
var _mcourage := PackedFloat32Array()  ## 0..1
var _mwisdom := PackedFloat32Array()   ## 0..1
var _mspeed := PackedFloat32Array()    ## 0..1
var _mhp := PackedInt32Array()
var _mhunger := PackedInt32Array()     ## 0 sated .. HUNGER_MAX starving
var _mfatigue := PackedInt32Array()
var _mbond := PackedFloat32Array()     ## attachment to the band

var _next_name := 0                    ## cursor into NAME_POOL (then #-suffixed)

# =====================================================================
#  Live state — the world
# =====================================================================
var day := 0
var phase := PH_MIGRATION
var arrived := false
var morale := MORALE_START
var food_stock := 0
var burrow_depth := 0.0                ## sheltering deepens this; cut by moving on

var journey_index := 0                 ## which stop the band is at
var goal_index := 0                    ## index of the goal stop
var _target := TARGET_POP              ## effective grow-to-win population (config override)
var _stops: Array = []                 ## each: {name, danger, food, legdays, goal, road}
var _scouted := false                  ## the NEXT leg has been scouted (one-shot)

# Cumulative counters (proof of the sim's history).
var births := 0
var deaths_starvation := 0
var deaths_illness := 0
var deaths_predator := 0
var deserters := 0
var matured := 0
var encounters := 0
var repelled := 0
var last_repro_day := -100

var game_over := false
var outcome := ""                      ## "" | "win" | "loss"
var loss_reason := ""
var illegal_attempts := 0
var action_count := 0
var log_lines: Array[String] = []

var _rng := RandomNumberGenerator.new()
var _seed := 0
var _config: Dictionary = {}


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh run. seed_value == 0 → randomised; any other value replays byte-
## identically. `config` may override: "stops" (int), "target" (int), "danger"
## (float multiplier on every stop's danger), "start_food" (int) — these are the
## difficulty levers that make BOTH a win and a loss genuinely reachable without
## ever hardcoding the outcome.
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	_seed = seed_value
	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value
	_config = config.duplicate(true)

	day = 0
	phase = PH_MIGRATION
	arrived = false
	morale = MORALE_START
	food_stock = int(_config.get("start_food", START_FOOD))
	burrow_depth = 0.0
	journey_index = 0
	_target = clampi(int(_config.get("target", TARGET_POP)), VIABLE_FOUNDING, POP_CAP)
	_scouted = false
	births = 0
	deaths_starvation = 0
	deaths_illness = 0
	deaths_predator = 0
	deserters = 0
	matured = 0
	encounters = 0
	repelled = 0
	last_repro_day = -100
	game_over = false
	outcome = ""
	loss_reason = ""
	illegal_attempts = 0
	action_count = 0
	log_lines = []
	_next_name = 0

	_clear_band()
	_generate_journey()
	_found_band()

	_log("The band flees the old warren — %d souls set out for a new home under %s skies (seed %d)." % [
		alive_count(), SEASON_NAME[season()], _seed])


func _clear_band() -> void:
	_mname = []
	_mrole = PackedInt32Array()
	_msex = PackedInt32Array()
	_mage = PackedInt32Array()
	_mcourage = PackedFloat32Array()
	_mwisdom = PackedFloat32Array()
	_mspeed = PackedFloat32Array()
	_mhp = PackedInt32Array()
	_mhunger = PackedInt32Array()
	_mfatigue = PackedInt32Array()
	_mbond = PackedFloat32Array()


## The seeded chain of stops: a start warren, several increasingly exposed legs
## (some crossing the Man's road), and a safe, food-rich GOAL — the promised down.
func _generate_journey() -> void:
	_stops = []
	var count: int = maxi(4, int(_config.get("stops", DEFAULT_STOPS)))
	var danger_mult: float = float(_config.get("danger", 1.0))
	# The start warren (the place being fled): modestly safe, ordinary food.
	_stops.append({
		"name": "Sandleford Warren", "danger": 0.15 * danger_mult,
		"food": 0.5, "legdays": 0, "goal": false, "road": false,
	})
	# Intermediate legs: danger rises toward the middle, food varies with the seed.
	for i in range(1, count - 1):
		var t: float = float(i) / float(count - 1)
		var ramp: float = 0.22 + 0.5 * t          ## danger baseline climbs with the trek
		var jitter: float = _rng.randf() * 0.22 - 0.06
		var danger: float = clampf((ramp + jitter) * danger_mult, 0.1, 0.95)
		var food: float = clampf(0.35 + _rng.randf() * 0.45, 0.2, 0.95)
		var road: bool = danger > 0.6                ## a high-danger leg is the Man's road
		var legdays: int = 1 + (_rng.randi() % 3)    ## a leg costs 1..3 travel days
		var nm: String = STOP_POOL[(_next_stop_name(i))]
		_stops.append({
			"name": nm, "danger": danger, "food": food,
			"legdays": legdays, "goal": false, "road": road,
		})
	# The goal: Watership Down — safe and rich, where the warren is founded + grown.
	_stops.append({
		"name": "Watership Down", "danger": GOAL_DANGER * danger_mult,
		"food": GOAL_FOOD, "legdays": 1 + (_rng.randi() % 2),
		"goal": true, "road": false,
	})
	goal_index = _stops.size() - 1


func _next_stop_name(i: int) -> int:
	return (i - 1) % STOP_POOL.size()


## The founding band: six named adults filling every working role (mixed sexes so a
## breeding pair exists) plus one kit — the warren's future.
func _found_band() -> void:
	_add_member(_take_name(), CHIEF, FEMALE, 240)
	_add_member(_take_name(), SCOUT, MALE, 190)
	_add_member(_take_name(), SEER, FEMALE, 170)
	_add_member(_take_name(), FORAGER, MALE, 205)
	_add_member(_take_name(), FIGHTER, MALE, 175)
	_add_member(_take_name(), STORYTELLER, FEMALE, 260)
	# A founding kit, already part-grown (matures a handful of days into the trek).
	var kit_idx: int = _add_member(_take_name(), KIT, _rng.randi() & 1, KIT_MATURE_DAYS - 8)


func _take_name() -> String:
	if _next_name < NAME_POOL.size():
		var nm: String = NAME_POOL[_next_name]
		_next_name += 1
		return nm
	var idx: int = _next_name
	_next_name += 1
	return "%s-%d" % [NAME_POOL[idx % NAME_POOL.size()], idx / NAME_POOL.size() + 1]


## Add a member with seeded traits (courage/wisdom/speed) tuned lightly by role, and
## full needs. Returns the new member index.
func _add_member(nm: String, role: int, sex: int, age: int) -> int:
	var courage: float = _trait_for(role, "courage")
	var wisdom: float = _trait_for(role, "wisdom")
	var speed: float = _trait_for(role, "speed")
	_mname.append(nm)
	_mrole.append(role)
	_msex.append(sex)
	_mage.append(age)
	_mcourage.append(courage)
	_mwisdom.append(wisdom)
	_mspeed.append(speed)
	_mhp.append(HP_MAX)
	_mhunger.append(0)
	_mfatigue.append(0)
	_mbond.append(BOND_START)
	return _mname.size() - 1


## Seeded trait in 0..1 with a small role-appropriate lean (a Fighter is braver, a
## Seer/Chief wiser, a Scout faster) — never a hard default; the seed dominates.
func _trait_for(role: int, which: String) -> float:
	var base: float = 0.35 + _rng.randf() * 0.4
	var lean: float = 0.0
	match which:
		"courage":
			if role == FIGHTER:
				lean = 0.18
			elif role == CHIEF:
				lean = 0.1
			elif role == KIT:
				lean = -0.2
		"wisdom":
			if role == SEER or role == CHIEF:
				lean = 0.16
			elif role == STORYTELLER:
				lean = 0.12
			elif role == KIT:
				lean = -0.15
		"speed":
			if role == SCOUT:
				lean = 0.18
			elif role == FORAGER:
				lean = 0.08
			elif role == KIT:
				lean = -0.1
	return clampf(base + lean, 0.05, 1.0)


# =====================================================================
#  Band queries
# =====================================================================

func member_count() -> int:
	return _mname.size()


func alive_count() -> int:
	return _mname.size()  ## the fallen are compacted out each day; all listed are alive


## Adults (any non-Kit role) currently in the band.
func adult_count() -> int:
	var c: int = 0
	for i in _mrole.size():
		if _mrole[i] != KIT:
			c += 1
	return c


func kit_count() -> int:
	return _mname.size() - adult_count()


func role_pop(role: int) -> int:
	var c: int = 0
	for i in _mrole.size():
		if _mrole[i] == role:
			c += 1
	return c


func has_role(role: int) -> bool:
	return _mrole.find(role) != -1


func is_alive(i: int) -> bool:
	return i >= 0 and i < _mname.size()


## Read-only member snapshot for the view / tests.
func member_info(i: int) -> Dictionary:
	return {
		"name": _mname[i], "role": _mrole[i], "role_name": ROLE_NAME[_mrole[i]],
		"sex": _msex[i], "age": _mage[i], "hp": _mhp[i], "hunger": _mhunger[i],
		"fatigue": _mfatigue[i], "bond": _mbond[i],
		"courage": _mcourage[i], "wisdom": _mwisdom[i], "speed": _mspeed[i],
		"adult": _mrole[i] != KIT,
	}


## True iff a viable breeding pair exists: a healthy adult female AND a healthy
## adult male (both non-kit, alive) — the demographic floor for reproduction.
func has_breeding_pair() -> bool:
	var f: bool = false
	var m: bool = false
	for i in _mrole.size():
		if _mrole[i] == KIT or _mhp[i] <= 0:
			continue
		if _msex[i] == FEMALE:
			f = true
		else:
			m = true
	return f and m


## Band-average bond — the cohesion readout the social layer exposes.
func cohesion() -> float:
	if _mbond.is_empty():
		return 0.0
	var s: float = 0.0
	for v in _mbond:
		s += v
	return s / float(_mbond.size())


# =====================================================================
#  World queries
# =====================================================================

func season() -> int:
	return int(day / DAYS_PER_SEASON) % SEASON_COUNT


func season_name() -> String:
	return SEASON_NAME[season()]


func year() -> int:
	return int(day / DAYS_PER_YEAR)


func season_food_mult() -> float:
	return SEASON_FOOD[season()]


func season_danger_mult() -> float:
	return SEASON_DANGER[season()]


func stop_count() -> int:
	return _stops.size()


func stop_info(i: int) -> Dictionary:
	var s: Dictionary = _stops[i]
	return {
		"name": String(s["name"]), "danger": float(s["danger"]),
		"food": float(s["food"]), "legdays": int(s["legdays"]),
		"goal": bool(s["goal"]), "road": bool(s["road"]),
	}


func current_stop() -> Dictionary:
	return stop_info(journey_index)


func next_stop_index() -> int:
	return mini(journey_index + 1, goal_index)


func current_stop_name() -> String:
	return String(_stops[journey_index]["name"])


func scouted() -> bool:
	return _scouted


func phase_name() -> String:
	return PHASE_NAME[phase]


func target_pop() -> int:
	return _target


func rng_state() -> int:
	return int(_rng.state)


# =====================================================================
#  Forage model (deterministic — the FORAGER advantage is measurable)
# =====================================================================

## The food a FORAGE decision would yield RIGHT NOW: base × season × the current
## site's richness × (1 + the band's forage weight), where every able adult adds a
## wisdom-scaled weight and a FORAGER adds FORAGER_BONUS on top. Pure (no RNG), so a
## band with a Forager ALWAYS out-gathers the same band without one.
func forage_yield_preview() -> int:
	var weight: float = 0.0
	for i in _mrole.size():
		if _mrole[i] == KIT:
			continue                       ## kits cannot forage
		if _mhp[i] <= 0:
			continue
		var able: float = 0.55 + 0.45 * _mwisdom[i]
		able *= 1.0 - 0.35 * (float(_mfatigue[i]) / float(FATIGUE_MAX))  ## tired = less
		weight += ADULT_FORAGE * able
		if _mrole[i] == FORAGER:
			weight += FORAGER_BONUS * able
	var site: float = float(_stops[journey_index]["food"])
	var raw: float = BASE_FORAGE * season_food_mult() * site * (1.0 + weight)
	return int(round(raw))


# =====================================================================
#  Legality + enumeration of decisions
# =====================================================================

## Is `action` legal right now? Rejects everything once the game is over, an empty
## band, forage/scout/rest/shelter with no one to do it, moving on with no survivors
## or already at the goal, and an ASSIGN to a dead/invalid member, to Kit, of a kit,
## or an out-of-range role.
func is_legal_action(action: int, arg0: int = -1, arg1: int = -1) -> bool:
	if game_over:
		return false
	if action < 0 or action >= ACTION_COUNT:
		return false
	if alive_count() <= 0:
		return false
	match action:
		ACT_FORAGE, ACT_SCOUT, ACT_REST, ACT_SHELTER:
			return alive_count() > 0
		ACT_MOVE_ON:
			# Need survivors and somewhere still to go.
			return alive_count() > 0 and journey_index < goal_index
		ACT_ASSIGN:
			if arg0 < 0 or arg0 >= _mname.size():
				return false                  ## no such member (e.g. one who fell)
			if _mrole[arg0] == KIT:
				return false                  ## a kit is too young to hold a role
			if arg1 < 0 or arg1 >= ROLE_COUNT or arg1 == KIT:
				return false                  ## cannot assign the Kit role
			return true
		_:
			return false


## Every legal decision right now, in a fixed deterministic order. ASSIGN options
## are enumerated per (adult member → each adult role != its current one).
func legal_actions() -> Array:
	var out: Array = []
	if game_over:
		return out
	for a in [ACT_FORAGE, ACT_SCOUT, ACT_REST, ACT_MOVE_ON, ACT_SHELTER]:
		if is_legal_action(a):
			out.append({"action": a})
	for i in _mname.size():
		if _mrole[i] == KIT:
			continue
		for r in ADULT_ROLES:
			if r == _mrole[i]:
				continue
			if is_legal_action(ACT_ASSIGN, i, r):
				out.append({"action": ACT_ASSIGN, "member": i, "role": r})
	return out


# =====================================================================
#  Apply one decision
# =====================================================================

## Take ONE decision. Rejects an illegal one (state unchanged, counted). ASSIGN is a
## free management action (no day passes). Every other decision resolves then ADVANCES
## the day (MOVE_ON runs one day per travel-day of the leg).
func take_action(action: int, arg0: int = -1, arg1: int = -1) -> bool:
	if not is_legal_action(action, arg0, arg1):
		illegal_attempts += 1
		return false
	action_count += 1
	match action:
		ACT_FORAGE:
			_do_forage()
			_end_day(false)
		ACT_SCOUT:
			_do_scout()
			_end_day(false)
		ACT_REST:
			_do_rest()
			_end_day(false)
		ACT_SHELTER:
			_do_shelter()
			_end_day(false)
		ACT_MOVE_ON:
			_do_move_on()
		ACT_ASSIGN:
			_do_assign(arg0, arg1)
	return true


func _do_forage() -> void:
	var gained: int = forage_yield_preview()
	food_stock += gained
	if gained >= int(round(BASE_FORAGE * season_food_mult())):
		morale = minf(MORALE_MAX, morale + FORAGE_MORALE)
		_bond_all(BOND_GAIN)
	_log("The band forages %s — %d food gathered (stock %d)." % [
		current_stop_name(), gained, food_stock])


func _do_scout() -> void:
	_scouted = true
	var nxt: Dictionary = stop_info(next_stop_index())
	_log("The scout reads the road to %s (danger %d%%) — the band will not be caught unawares." % [
		String(nxt["name"]), int(round(float(nxt["danger"]) * 100.0))])


func _do_rest() -> void:
	for i in _mfatigue.size():
		_mfatigue[i] = maxi(0, _mfatigue[i] - REST_FATIGUE_DROP)
		_mhp[i] = mini(HP_MAX, _mhp[i] + REST_HP)
	var gain: float = rest_morale_gain()
	if has_role(STORYTELLER):
		_log("The Storyteller spins a tale of El-ahrairah; the band rests (+%d morale)." % int(round(gain)))
	else:
		_log("The band rests and licks its wounds (+%d morale)." % int(round(gain)))
	morale = minf(MORALE_MAX, morale + gain)
	_bond_all(BOND_GAIN)


## The morale a REST decision restores right now (pure) — REST_MORALE, plus the
## STORYTELLER's bonus when one is in the band. The society probe compares this with
## vs without a Storyteller to prove the ability is real.
func rest_morale_gain() -> float:
	var gain: float = REST_MORALE
	if has_role(STORYTELLER):
		gain += STORYTELLER_MORALE
	return gain


func _do_shelter() -> void:
	burrow_depth = minf(1.0, burrow_depth + 0.6)
	for i in _mhp.size():
		_mhp[i] = mini(HP_MAX, _mhp[i] + SHELTER_HP)
	_log("The band digs a deep scrape and lies low (safety deepened).")


func _do_move_on() -> void:
	var target: int = next_stop_index()
	var legdays: int = maxi(1, int(_stops[target]["legdays"]))
	_log("The band breaks cover and runs for %s — %d day(s) on open ground." % [
		String(_stops[target]["name"]), legdays])
	burrow_depth = 0.0
	for _d in legdays:
		if game_over:
			return
		_end_day(true)
	if game_over:
		return
	journey_index = target
	_scouted = false
	if journey_index == goal_index and not arrived:
		_arrive()


func _do_assign(member: int, role: int) -> void:
	var old: int = _mrole[member]
	_mrole[member] = role
	_log("%s takes up the role of %s (was %s)." % [
		_mname[member], ROLE_NAME[role], ROLE_NAME[old]])


func _arrive() -> void:
	arrived = true
	phase = PH_GROWTH
	morale = minf(MORALE_MAX, morale + ARRIVE_MORALE)
	_bond_all(BOND_GAIN * 3.0)
	_log("They crest the down and look upon %s — the new warren is FOUNDED with %d souls. Now it must GROW." % [
		current_stop_name(), alive_count()])


# =====================================================================
#  End of day — the deterministic survival pipeline
# =====================================================================

## Resolve one day. `travelling` is true for each travel-day of a MOVE_ON leg (more
## fatigue + a far higher hazard chance), false for a camped day (forage/scout/rest/
## shelter). Fixed order: eat → fatigue/illness → hazard → morale drift → reproduce
## → age/mature → desertion → judge. The fallen (starved / slain / deserted) are
## removed from the parallel arrays IN PLACE the moment they leave, so alive_count()
## always equals member_count() — no separate compaction step is needed.
func _end_day(travelling: bool) -> void:
	if game_over:
		return
	_feed()
	_fatigue_and_illness(travelling)
	_hazard(travelling)
	_morale_drift()
	if phase == PH_GROWTH:
		_reproduce()
	_age_and_mature()
	_desertion()
	day += 1
	_judge()


## Everyone eats. A full larder sheds hunger; an empty one starves the band, and a
## member already at max hunger loses hp (and can die).
func _feed() -> void:
	var needed: int = 0
	for i in _mrole.size():
		needed += FOOD_PER_KIT if _mrole[i] == KIT else FOOD_PER_ADULT
	if food_stock >= needed:
		food_stock -= needed
		for i in _mhunger.size():
			_mhunger[i] = maxi(0, _mhunger[i] - HUNGER_RECOVER)
	else:
		# Partial feeding: spend what we have, the rest go hungry. Collect the fallen
		# and remove them AFTER the pass (removing mid-loop would shift indices).
		food_stock = 0
		var fallen: Array[int] = []
		for i in _mhunger.size():
			_mhunger[i] = mini(HUNGER_MAX, _mhunger[i] + HUNGER_RISE)
			if _mhunger[i] >= HUNGER_MAX:
				_mhp[i] -= STARVE_HP
				if _mhp[i] <= 0:
					fallen.append(i)
		for k in range(fallen.size() - 1, -1, -1):
			var idx: int = fallen[k]
			_log("%s starves on the road." % _mname[idx])
			_remove(idx)
			deaths_starvation += 1


func _fatigue_and_illness(travelling: bool) -> void:
	for i in _mfatigue.size():
		if i >= _mname.size():
			break
		if travelling:
			_mfatigue[i] = mini(FATIGUE_MAX, _mfatigue[i] + TRAVEL_FATIGUE)
		else:
			_mfatigue[i] = maxi(0, _mfatigue[i] - CAMP_FATIGUE_DROP)
	# Illness: a tired member in a harsh season may sicken (seeded).
	var winter_bonus: float = 0.12 if season() == WINTER else 0.0
	var i2: int = 0
	while i2 < _mname.size():
		var risk: float = 0.0
		if _mfatigue[i2] >= ILL_FATIGUE:
			risk += 0.10
		if _mhunger[i2] >= HUNGER_MAX / 2:
			risk += 0.08
		risk += winter_bonus
		if risk > 0.0 and _rng.randf() < risk:
			_mhp[i2] -= ILL_HP
			if _mhp[i2] <= 0:
				_kill(i2, "illness")
				deaths_illness += 1
				continue                      ## _kill compacts i2 out; re-test this slot
			else:
				_log("%s falls ill in the %s cold (hp %d)." % [
					_mname[i2], SEASON_NAME[season()], _mhp[i2]])
		i2 += 1


## Roll the day's hazard. The encounter CHANCE is the lever a Scout / scouted leg /
## shelter turn down; if one fires, _resolve_encounter decides escape vs loss.
func _hazard(travelling: bool) -> void:
	if _mname.is_empty():
		return
	var chance: float = encounter_chance_preview(travelling)
	if _rng.randf() < chance:
		var stop: Dictionary = _stops[journey_index]
		var pred: int = _pick_predator(travelling, bool(stop["road"]))
		_resolve_encounter(pred)


## The probability a predator strikes on the coming day (pure, no RNG) — the SCOUT
## in the band, a scouted leg, and a deepened burrow each MEASURABLY turn it down,
## and a harsher season turns it up. The society + predator probes compare this to
## prove the Scout's ability is real.
func encounter_chance_preview(travelling: bool) -> float:
	var stop: Dictionary = _stops[journey_index]
	var base: float = BASE_ENCOUNTER_TRAVEL if travelling else BASE_ENCOUNTER_CAMP
	var chance: float = base * (0.5 + float(stop["danger"])) * season_danger_mult()
	if has_role(SCOUT):
		chance *= SCOUT_CHANCE_MULT
	if _scouted:
		chance *= SCOUTED_CHANCE_MULT
	if not travelling:
		chance *= 1.0 - SHELTER_CHANCE_MULT * burrow_depth
	return clampf(chance, 0.0, 0.95)


## Choose which threat strikes. The Man haunts the road / higher-danger travel; Fox
## and Cat prowl the ground; the Hawk stoops from open sky.
func _pick_predator(travelling: bool, road: bool) -> int:
	var weights: PackedFloat32Array = PackedFloat32Array([3.0, 2.0, 2.0, 0.4])  ## fox/hawk/cat/man
	if road:
		weights[MAN] = 3.5
	if travelling:
		weights[HAWK] += 1.0                  ## open ground → the hawk sees you
		weights[MAN] += 0.6
	if season() == WINTER:
		weights[FOX] += 1.0                   ## a hungry winter fox ranges wider
	var total: float = 0.0
	for w in weights:
		total += w
	var r: float = _rng.randf() * total
	var acc: float = 0.0
	for p in PRED_COUNT:
		acc += weights[p]
		if r < acc:
			return p
	return FOX


## Resolve a predator raid. Band defence = each member's courage/speed/health plus a
## FIGHTER bonus; a SEER's early-warning multiplies it (a cleaner escape). If defence
## meets the threat the band drives the predator off (a scratch at worst); otherwise
## the most-exposed member (a kit, else the frailest) is taken — real, named stakes —
## and morale plunges.
func _resolve_encounter(pred: int) -> void:
	encounters += 1
	var defense: float = 0.0
	for i in _mname.size():
		var contrib: float = _mcourage[i] * 0.5 + _mspeed[i] * 0.3 + (float(_mhp[i]) / float(HP_MAX)) * 0.2
		if _mrole[i] == FIGHTER:
			contrib += FIGHTER_DEFENSE
		defense += contrib
	if has_role(SEER):
		defense *= SEER_DEFENSE_MULT
	var stop: Dictionary = _stops[journey_index]
	var threat: float = PRED_ATTACK[pred] * season_danger_mult() * (0.6 + float(stop["danger"]))
	var margin: float = defense - threat
	if margin >= 0.0:
		repelled += 1
		morale = minf(MORALE_MAX, morale + REPEL_MORALE)
		# A skirmish still costs a fighter a scratch.
		var fi: int = _first_role(FIGHTER)
		if fi < 0:
			fi = _weakest_member()
		if fi >= 0:
			_mhp[fi] = maxi(1, _mhp[fi] - (1 + _rng.randi() % 2))
		_bond_all(BOND_GAIN)
		_log("A %s attacks near %s — the band stands firm and drives it off." % [
			PRED_NAME[pred], current_stop_name()])
	else:
		var casualties: int = 1
		if margin < -3.0:
			casualties = 2
		casualties = clampi(casualties, 1, _mname.size())  ## a rout can wipe the band
		_log("A %s falls upon the band on the open ground of %s!" % [
			PRED_NAME[pred], current_stop_name()])
		for _c in casualties:
			if _mname.is_empty():
				break
			var victim: int = _most_exposed()
			if victim < 0:
				break
			var vname: String = _mname[victim]
			_kill(victim, "taken by a %s" % PRED_NAME[pred])
			deaths_predator += 1
			morale = maxf(0.0, morale - DEATH_MORALE)
			_bond_all(-BOND_LOSS)
			_log("%s is lost to the %s. The band mourns." % [vname, PRED_NAME[pred]])


## The member most likely to be caught: a kit first (slow, small), else the frailest
## (lowest hp + courage). Deterministic scan.
func _most_exposed() -> int:
	var best: int = -1
	var best_score: float = 1e20
	for i in _mname.size():
		var score: float = float(_mhp[i]) + _mcourage[i] * 10.0 + _mspeed[i] * 6.0
		if _mrole[i] == KIT:
			score -= 100.0                    ## kits are the most exposed
		if score < best_score:
			best_score = score
			best = i
	return best


func _weakest_member() -> int:
	var best: int = -1
	var best_hp: int = 1 << 30
	for i in _mhp.size():
		if _mhp[i] < best_hp:
			best_hp = _mhp[i]
			best = i
	return best


func _first_role(role: int) -> int:
	for i in _mrole.size():
		if _mrole[i] == role:
			return i
	return -1


## Morale drifts toward its equilibrium, nudged up by a living Chief's leadership and
## by high cohesion, down by grief already applied. Bounded 0..MORALE_MAX.
func _morale_drift() -> void:
	var eq: float = MORALE_EQ
	if has_role(CHIEF):
		eq += 8.0
	eq += (cohesion() - 0.5) * 20.0
	if morale < eq:
		morale = minf(eq, morale + CHIEF_MORALE_REGEN)
	else:
		morale = maxf(eq, morale - 1.0)
	morale = clampf(morale, 0.0, MORALE_MAX)


## Once settled, a healthy breeding pair with a food surplus births a kit — up to the
## population cap, at most once every REPRO_INTERVAL days. This is how the warren GROWS.
func _reproduce() -> void:
	if not arrived:
		return
	if _mname.size() >= POP_CAP:
		return
	if food_stock <= REPRO_FOOD_SURPLUS:
		return
	if not has_breeding_pair():
		return
	if day - last_repro_day < REPRO_INTERVAL:
		return
	if morale < 30.0:
		return                                ## a fearful band does not raise young
	last_repro_day = day
	food_stock -= REPRO_COST
	births += 1
	var sex: int = _rng.randi() & 1
	var idx: int = _add_member(_take_name(), KIT, sex, 0)
	morale = minf(MORALE_MAX, morale + 4.0)
	_bond_all(BOND_GAIN)
	_log("A kit is born in the new warren — %s (pop %d)." % [_mname[idx], _mname.size()])


## Age everyone a day; a kit that reaches maturity takes up an adult role (Forager /
## Fighter, alternating) — the warren's future joining the work.
func _age_and_mature() -> void:
	for i in _mage.size():
		if i >= _mname.size():
			break
		_mage[i] += 1
		if _mrole[i] == KIT and _mage[i] >= KIT_MATURE_DAYS:
			var role: int = FORAGER if (matured % 2 == 0) else FIGHTER
			_mrole[i] = role
			matured += 1
			_log("%s comes of age and becomes a %s." % [_mname[i], ROLE_NAME[role]])


## Dissent: when morale is below the floor, a loosely-bonded member may DESERT and
## splinter off (the band shrinks). The Chief's presence steadies the waverers.
func _desertion() -> void:
	if morale >= DESERT_MORALE_FLOOR:
		return
	if _mname.size() <= 1:
		return                                ## the last one standing does not desert
	var steady: float = 0.12 if has_role(CHIEF) else 0.0
	var i: int = 0
	while i < _mname.size():
		if _mrole[i] == KIT:
			i += 1
			continue                          ## kits do not leave on their own
		var leave_chance: float = (BOND_DESERT - _mbond[i]) * 1.2 + (DESERT_MORALE_FLOOR - morale) / 220.0
		leave_chance -= steady
		if leave_chance > 0.0 and _rng.randf() < clampf(leave_chance, 0.0, 0.6):
			if _mname.size() <= 1:
				break
			var lname: String = _mname[i]
			_remove(i)
			deserters += 1
			morale = maxf(0.0, morale - 4.0)
			_log("Morale breaks — %s loses faith and splinters from the band." % lname)
			continue                          ## _remove shifts arrays; re-test slot i
		i += 1


# =====================================================================
#  Member removal (death / desertion) + compaction
# =====================================================================

## Mark a member dead: log then remove. (Deaths + desertions both remove; the fallen
## are never left in the arrays, so alive_count() == member_count() always.)
func _kill(i: int, cause: String) -> void:
	if i < 0 or i >= _mname.size():
		return
	_remove(i)


func _remove(i: int) -> void:
	if i < 0 or i >= _mname.size():
		return
	_mname.remove_at(i)
	_mrole.remove_at(i)
	_msex.remove_at(i)
	_mage.remove_at(i)
	_mcourage.remove_at(i)
	_mwisdom.remove_at(i)
	_mspeed.remove_at(i)
	_mhp.remove_at(i)
	_mhunger.remove_at(i)
	_mfatigue.remove_at(i)
	_mbond.remove_at(i)


func _bond_all(delta: float) -> void:
	for i in _mbond.size():
		_mbond[i] = clampf(_mbond[i] + delta, 0.0, 1.0)


# =====================================================================
#  Judge — win / loss (both reachable; MAX_DAYS guarantees termination)
# =====================================================================

func _judge() -> void:
	if game_over:
		return
	if alive_count() == 0:
		_end_game("loss", "the band was wiped out")
		return
	if alive_count() < VIABLE_FOUNDING:
		_end_game("loss", "the band fell below a viable founding size")
		return
	if arrived and alive_count() >= _target:
		_end_game("win", "the new warren thrives")
		return
	if not arrived and day > DEADLINE_DAYS:
		_end_game("loss", "the band failed to reach the new site before the deadline")
		return
	if day >= MAX_DAYS:
		_end_game("loss", "the years ran out before the warren could thrive")


func _end_game(result: String, reason: String) -> void:
	if game_over:
		return
	game_over = true
	phase = PH_OVER
	outcome = result
	loss_reason = reason
	if result == "win":
		_log("A THRIVING WARREN — %d souls under the down after %d days. The band's long road is won." % [
			alive_count(), day])
	else:
		_log("THE ROAD ENDS — %s (day %d)." % [reason, day])


func is_win() -> bool:
	return game_over and outcome == "win"


func is_loss() -> bool:
	return game_over and outcome == "loss"


# =====================================================================
#  Auto-play policies (deterministic; drive BOTH outcomes for the probes)
# =====================================================================

## Choose the next decision under a named policy. "balanced" plays to survive + thrive
## (forage when lean, rest when weary / low morale, scout a dangerous leg, then move
## on; in growth it keeps a surplus so the pair breeds). "reckless" charges on with no
## scouting or foraging and gets the band killed. Returns {action, member?, role?}.
func policy_choice(policy: String) -> Dictionary:
	if game_over:
		return {}
	match policy:
		"reckless":
			return _policy_reckless()
		_:
			return _policy_balanced()


func _policy_reckless() -> Dictionary:
	# Charge for the goal every day; never forage, scout, or rest. In growth (if it
	# ever gets there) it simply waits — but it almost never survives the trek.
	if is_legal_action(ACT_MOVE_ON):
		return {"action": ACT_MOVE_ON}
	if is_legal_action(ACT_REST):
		return {"action": ACT_REST}
	return _first_legal()


func _policy_balanced() -> Dictionary:
	var days_buffer: int = _days_of_food()
	# In the growth phase: keep a surplus so the breeding pair keeps birthing.
	if arrived:
		if food_stock <= REPRO_FOOD_SURPLUS + 6:
			if is_legal_action(ACT_FORAGE):
				return {"action": ACT_FORAGE}
		if morale < 40.0 and is_legal_action(ACT_REST):
			return {"action": ACT_REST}
		# Otherwise pass days (rest) so the warren grows.
		if is_legal_action(ACT_REST):
			return {"action": ACT_REST}
		return _first_legal()
	# Migration phase.
	if days_buffer < 4 and is_legal_action(ACT_FORAGE):
		return {"action": ACT_FORAGE}
	if morale < 42.0 and is_legal_action(ACT_REST):
		return {"action": ACT_REST}
	if _avg_fatigue() > 60.0 and is_legal_action(ACT_REST):
		return {"action": ACT_REST}
	var nxt: Dictionary = stop_info(next_stop_index())
	if float(nxt["danger"]) > 0.5 and not _scouted and is_legal_action(ACT_SCOUT):
		return {"action": ACT_SCOUT}
	if float(nxt["danger"]) > 0.7 and burrow_depth < 0.3 and is_legal_action(ACT_SHELTER):
		return {"action": ACT_SHELTER}
	if is_legal_action(ACT_MOVE_ON):
		return {"action": ACT_MOVE_ON}
	if is_legal_action(ACT_FORAGE):
		return {"action": ACT_FORAGE}
	return _first_legal()


func _first_legal() -> Dictionary:
	var opts: Array = legal_actions()
	return opts[0] if not opts.is_empty() else {}


## Days of food the band currently holds at the present consumption rate.
func _days_of_food() -> int:
	var needed: int = 0
	for i in _mrole.size():
		needed += FOOD_PER_KIT if _mrole[i] == KIT else FOOD_PER_ADULT
	if needed <= 0:
		return 999
	return int(food_stock / needed)


func _avg_fatigue() -> float:
	if _mfatigue.is_empty():
		return 0.0
	var s: int = 0
	for v in _mfatigue:
		s += v
	return float(s) / float(_mfatigue.size())


## Take ONE decision under `policy`. Returns the decision taken (or {} at game over).
func auto_step(policy: String = "balanced") -> Dictionary:
	if game_over:
		return {}
	var choice: Dictionary = policy_choice(policy)
	if choice.is_empty():
		return {}
	var member: int = int(choice.get("member", -1))
	var role: int = int(choice.get("role", -1))
	take_action(int(choice["action"]), member, role)
	return choice


## Play a whole run to its end under `policy`. Terminates: every non-assign decision
## advances >=1 day and the judge ends by MAX_DAYS; the loop guard is a final backstop.
func auto_play_to_end(policy: String = "balanced") -> void:
	var guard: int = 0
	while not game_over and guard < MAX_DAYS * 8 + 64:
		guard += 1
		var before_day: int = day
		var acted: Dictionary = auto_step(policy)
		if acted.is_empty():
			break
		# Safety: if a policy somehow only ever picks ASSIGN (no day passes), break to
		# guarantee termination (real policies always advance the day).
		if day == before_day and int(acted.get("action", -1)) != ACT_ASSIGN:
			break


# =====================================================================
#  Test hooks (deterministic; used by the survival / predator probes)
# =====================================================================

## Force-resolve one predator raid of `pred` type against the current band and report
## how many members were lost — the predator probe's honest stakes lever.
func force_encounter(pred: int) -> int:
	var before: int = _mname.size()
	_resolve_encounter(clampi(pred, 0, PRED_COUNT - 1))
	return before - _mname.size()


## Directly set a member's hp (test setup only).
func debug_set_hp(i: int, hp: int) -> void:
	if i >= 0 and i < _mhp.size():
		_mhp[i] = clampi(hp, 0, HP_MAX)


## Directly bank food (test setup only).
func debug_add_food(amount: int) -> void:
	food_stock = maxi(0, food_stock + amount)


## Force the band into the settled growth phase at the goal (test setup only).
func debug_force_arrived() -> void:
	journey_index = goal_index
	if not arrived:
		_arrive()


# =====================================================================
#  Logging
# =====================================================================

func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 400:
		log_lines.remove_at(0)


func recent_log(n: int = 12) -> Array[String]:
	var out: Array[String] = []
	var start: int = maxi(0, log_lines.size() - n)
	for i in range(start, log_lines.size()):
		out.append(log_lines[i])
	return out


# =====================================================================
#  Determinism helper — FNV-1a checksum over the ENTIRE state
# =====================================================================

## FNV-1a-style checksum over the whole run (band arrays, world, journey, morale,
## counters, day, phase, RNG). Two engines are byte-identical iff their checksums
## match — the determinism probe compares this within and ACROSS processes.
func checksum() -> int:
	var h: int = 1469598103934665603
	for nm in _mname:
		h = _mix_str(h, nm)
	h = _mix_ints(h, _mrole)
	h = _mix_ints(h, _msex)
	h = _mix_ints(h, _mage)
	h = _mix_bytes(h, _mcourage.to_byte_array())
	h = _mix_bytes(h, _mwisdom.to_byte_array())
	h = _mix_bytes(h, _mspeed.to_byte_array())
	h = _mix_ints(h, _mhp)
	h = _mix_ints(h, _mhunger)
	h = _mix_ints(h, _mfatigue)
	h = _mix_bytes(h, _mbond.to_byte_array())
	h = _mix_int(h, day)
	h = _mix_int(h, phase)
	h = _mix_int(h, 1 if arrived else 0)
	h = _mix_int(h, int(round(morale * 1000.0)))
	h = _mix_int(h, food_stock)
	h = _mix_int(h, int(round(burrow_depth * 1000.0)))
	h = _mix_int(h, journey_index)
	h = _mix_int(h, goal_index)
	h = _mix_int(h, 1 if _scouted else 0)
	h = _mix_int(h, births)
	h = _mix_int(h, deaths_starvation)
	h = _mix_int(h, deaths_illness)
	h = _mix_int(h, deaths_predator)
	h = _mix_int(h, deserters)
	h = _mix_int(h, matured)
	h = _mix_int(h, encounters)
	h = _mix_int(h, repelled)
	h = _mix_int(h, last_repro_day)
	h = _mix_int(h, action_count)
	h = _mix_int(h, illegal_attempts)
	# The journey terrain (danger/food are seed-derived floats).
	for s in _stops:
		h = _mix_int(h, int(round(float(s["danger"]) * 100000.0)))
		h = _mix_int(h, int(round(float(s["food"]) * 100000.0)))
		h = _mix_int(h, int(s["legdays"]))
	h = _mix_int(h, 1 if game_over else 0)
	h = _mix_str(h, outcome)
	return h & 0x7FFFFFFFFFFFFFFF


func _mix_int(h: int, v: int) -> int:
	h = (h ^ (v & 0xFFFFFFFF)) * 1099511628211
	return h & 0x7FFFFFFFFFFFFFFF


func _mix_ints(h: int, arr: PackedInt32Array) -> int:
	for i in arr.size():
		h = _mix_int(h, arr[i])
	return h


func _mix_bytes(h: int, arr: PackedByteArray) -> int:
	for i in arr.size():
		h = (h ^ int(arr[i])) * 1099511628211
		h = h & 0x7FFFFFFFFFFFFFFF
	return h


func _mix_str(h: int, s: String) -> int:
	for i in s.length():
		h = (h ^ (s.unicode_at(i) & 0xFFFFFFFF)) * 1099511628211
		h = h & 0x7FFFFFFFFFFFFFFF
	return h


# =====================================================================
#  Save / load — the FULL state round-trips (deep, JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	var stops_out: Array = []
	for s in _stops:
		stops_out.append({
			"name": String(s["name"]), "danger": float(s["danger"]),
			"food": float(s["food"]), "legdays": int(s["legdays"]),
			"goal": bool(s["goal"]), "road": bool(s["road"]),
		})
	return {
		"seed": _seed,
		"config": _config.duplicate(true),
		"rng_state": str(_rng.state),
		"mname": _mname.duplicate(),
		"mrole": Marshalls.raw_to_base64(_mrole.to_byte_array()),
		"msex": Marshalls.raw_to_base64(_msex.to_byte_array()),
		"mage": Marshalls.raw_to_base64(_mage.to_byte_array()),
		"mcourage": Marshalls.raw_to_base64(_mcourage.to_byte_array()),
		"mwisdom": Marshalls.raw_to_base64(_mwisdom.to_byte_array()),
		"mspeed": Marshalls.raw_to_base64(_mspeed.to_byte_array()),
		"mhp": Marshalls.raw_to_base64(_mhp.to_byte_array()),
		"mhunger": Marshalls.raw_to_base64(_mhunger.to_byte_array()),
		"mfatigue": Marshalls.raw_to_base64(_mfatigue.to_byte_array()),
		"mbond": Marshalls.raw_to_base64(_mbond.to_byte_array()),
		"next_name": _next_name,
		"day": day,
		"phase": phase,
		"arrived": arrived,
		"morale": morale,
		"food_stock": food_stock,
		"burrow_depth": burrow_depth,
		"journey_index": journey_index,
		"goal_index": goal_index,
		"target": _target,
		"stops": stops_out,
		"scouted": _scouted,
		"births": births,
		"deaths_starvation": deaths_starvation,
		"deaths_illness": deaths_illness,
		"deaths_predator": deaths_predator,
		"deserters": deserters,
		"matured": matured,
		"encounters": encounters,
		"repelled": repelled,
		"last_repro_day": last_repro_day,
		"game_over": game_over,
		"outcome": outcome,
		"loss_reason": loss_reason,
		"illegal_attempts": illegal_attempts,
		"action_count": action_count,
		"log_lines": log_lines.duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	_seed = int(data.get("seed", 0))
	_config = (data.get("config", {}) as Dictionary).duplicate(true)
	_rng = RandomNumberGenerator.new()
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	_mname = []
	for v in data.get("mname", []):
		_mname.append(String(v))
	_mrole = _ints(data.get("mrole", ""))
	_msex = _ints(data.get("msex", ""))
	_mage = _ints(data.get("mage", ""))
	_mcourage = _floats(data.get("mcourage", ""))
	_mwisdom = _floats(data.get("mwisdom", ""))
	_mspeed = _floats(data.get("mspeed", ""))
	_mhp = _ints(data.get("mhp", ""))
	_mhunger = _ints(data.get("mhunger", ""))
	_mfatigue = _ints(data.get("mfatigue", ""))
	_mbond = _floats(data.get("mbond", ""))
	_next_name = int(data.get("next_name", _mname.size()))
	day = int(data.get("day", 0))
	phase = int(data.get("phase", PH_MIGRATION))
	arrived = bool(data.get("arrived", false))
	morale = float(data.get("morale", MORALE_START))
	food_stock = int(data.get("food_stock", 0))
	burrow_depth = float(data.get("burrow_depth", 0.0))
	journey_index = int(data.get("journey_index", 0))
	goal_index = int(data.get("goal_index", 0))
	_target = int(data.get("target", TARGET_POP))
	_stops = []
	for v in data.get("stops", []):
		var s: Dictionary = v
		_stops.append({
			"name": String(s["name"]), "danger": float(s["danger"]),
			"food": float(s["food"]), "legdays": int(s["legdays"]),
			"goal": bool(s["goal"]), "road": bool(s.get("road", false)),
		})
	_scouted = bool(data.get("scouted", false))
	births = int(data.get("births", 0))
	deaths_starvation = int(data.get("deaths_starvation", 0))
	deaths_illness = int(data.get("deaths_illness", 0))
	deaths_predator = int(data.get("deaths_predator", 0))
	deserters = int(data.get("deserters", 0))
	matured = int(data.get("matured", 0))
	encounters = int(data.get("encounters", 0))
	repelled = int(data.get("repelled", 0))
	last_repro_day = int(data.get("last_repro_day", -100))
	game_over = bool(data.get("game_over", false))
	outcome = String(data.get("outcome", ""))
	loss_reason = String(data.get("loss_reason", ""))
	illegal_attempts = int(data.get("illegal_attempts", 0))
	action_count = int(data.get("action_count", 0))
	log_lines = []
	for v in data.get("log_lines", []):
		log_lines.append(String(v))


func _ints(v: Variant) -> PackedInt32Array:
	return Marshalls.base64_to_raw(String(v)).to_int32_array()


func _floats(v: Variant) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(String(v)).to_float32_array()
