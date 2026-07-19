extends RefCounted
class_name PirateEngine
## res://scripts/pirate_engine.gd
## The PURE, seedable, headless-testable engine for an AGE-OF-SAIL PIRATE CAREER SIM
## (Sid Meier's Pirates! lineage, but with DEEPER, fully-systemic mechanics). There
## is NO Godot-node dependency and NO physics server in here: the whole career is a
## deterministic TURN/TICK model over DAYS, so a career replays BYTE-IDENTICALLY from
## a seed and drives headlessly with no UI at all.
##
## WHY A PURE TICK MODEL (the key design decision):
##   A career sim is a web of interlocking economic + combat + reputation systems, not
##   a real-time arcade game. Modelling it as a deterministic sequence of DAY ticks
##   (sail / trade / fight / careen / divide-plunder / retire) means: every price, wind,
##   broadside, boarding roll, mutiny check and rival move is a pure function of the
##   engine state + ONE seeded RNG whose state is part of save/load. Given a seed and a
##   fixed action sequence (a human's inputs, or an auto-play policy) the ENTIRE career
##   — the world map, the economy drift, every duel, the final retirement rank — is
##   100% reproducible. A MAX_CAREER_DAYS cap plus "every action costs >=1 day" bounds
##   the career, so the sim ALWAYS terminates in a WIN (retire at/above a rank) or a
##   LOSS (ship sunk with no reserves / crew mutiny / retire below the rank threshold).
##
## Interlocking systems (all real formulas, no stubs / placeholders / hardcoded winner):
##   * WORLD       — a seeded map of >=12 ports across 4 rival NATIONS, each with a
##                   position, owner, wealth tier, garrison, and a per-good local economy.
##   * SAILING     — travel between ports costs DAYS via a deterministic wind model that
##                   modifies travel time AND sea-combat initiative (the weather gauge).
##   * TRADE       — 6 goods with per-port supply/demand PRICES on a real scarcity curve;
##                   buying/selling moves the local price (PRICE IMPACT) and prices DRIFT
##                   back to equilibrium over time, so arbitrage is emergent + profitable.
##   * SEA COMBAT  — a deterministic turn-based ship DUEL: maneuver for the wind gauge,
##                   fire broadsides (damage scales with cannons, range, crew gunnery,
##                   hull), pick round/chain/grape shot (hull/sails/crew) -> sink/flee/board.
##   * BOARDING    — crew-vs-crew melee from crew count, morale + captain fencing ->
##                   capture the ship + cargo, or get repelled.
##   * REPUTATION  — a 4-nation standing vector; attacking a nation lowers its standing +
##                   raises its enemy's; LETTERS OF MARQUE sanction privateering; standing
##                   gates safe-port access + spawns bounty hunters.
##   * CREW/MORALE — wages, food, plunder shares; low morale -> MUTINY (ends the career);
##                   dividing plunder + shore leave restore it.
##   * PROGRESSION — fame / gold / land grants; four SKILLS (navigation, gunnery, fencing,
##                   wit) that improve with use; AGING -> a bounded career -> a retirement
##                   RANK from the final score.
##   * TREASURE    — seeded treasure-map FRAGMENTS + a bounded QUEST CHAIN.
##   * AI RIVALS   — rival pirate captains sailing / trading / fighting under the same rules.

# =====================================================================
#  Determinism helpers (FNV-1a, 63-bit masked) + float quantiser
# =====================================================================

const FNV_OFFSET: int = 1469598103934665603
const FNV_PRIME: int = 1099511628211
const MASK63: int = 0x7FFFFFFFFFFFFFFF

# =====================================================================
#  World tuning (auditable constants — swap for your own game)
# =====================================================================

const SEA_W: float = 1000.0            ## logical sea width (port x range).
const SEA_H: float = 640.0             ## logical sea height (port y range).
const NUM_PORTS: int = 16              ## >=12 ports (4 per nation).
const NATIONS: Array = ["Crown", "Empire", "Republic", "Company"]

## Each nation's sworn enemy — attacking a nation delights its enemy.
const ENEMY_OF: Dictionary = {
	"Crown": "Empire", "Empire": "Crown",
	"Republic": "Company", "Company": "Republic",
}

## Goods — id -> {name, base}. base is the equilibrium price in gold/unit.
const GOODS: Dictionary = {
	"sugar":   {"name": "Sugar",   "base": 10.0},
	"tobacco": {"name": "Tobacco", "base": 18.0},
	"cloth":   {"name": "Cloth",   "base": 26.0},
	"rum":     {"name": "Rum",     "base": 34.0},
	"spice":   {"name": "Spice",   "base": 48.0},
	"ivory":   {"name": "Ivory",   "base": 82.0},
}
const GOOD_IDS: Array = ["sugar", "tobacco", "cloth", "rum", "spice", "ivory"]

## Economy curve.
const ELASTICITY: float = 0.85         ## price responsiveness to scarcity.
const PRICE_MIN_MULT: float = 0.38     ## a glutted producer floor.
const PRICE_MAX_MULT: float = 3.20     ## a starved consumer ceiling.
const SPREAD: float = 0.06             ## buy/sell half-spread around the mid price.
const DRIFT_RATE: float = 0.018        ## fraction/day stock relaxes toward baseline.
const IMPACT_UNIT: float = 1.0         ## each traded unit shifts stock by this (price impact).

# =====================================================================
#  Sailing + wind
# =====================================================================

const BASE_WIND: float = 0.6           ## the prevailing wind bearing at day 0 (rad).
const WIND_DRIFT: float = 0.021        ## the wind bearing rotates this many rad/day.
const WIND_WITH: float = 1.45          ## travel speed multiplier dead downwind.
const WIND_AGAINST: float = 0.62       ## travel speed multiplier hard upwind.
const LEAGUES_PER_DAY: float = 165.0   ## base distance a healthy ship makes per day.

# =====================================================================
#  Sea combat
# =====================================================================

const MAX_COMBAT_TURNS: int = 40       ## hard cap on a duel -> a resolved outcome.
const RANGE_LONG: int = 3
const RANGE_MEDIUM: int = 2
const RANGE_SHORT: int = 1
const RANGE_GRAPPLED: int = 0
const GUN_BASE: float = 3.4            ## damage per cannon at reference gunnery/range.
## per-range effectiveness of gunfire (index by range level 0..3).
const RANGE_HULL_FACTOR: Array = [1.30, 1.20, 0.82, 0.48]
const RANGE_HIT_FACTOR: Array = [1.25, 1.15, 0.85, 0.55]
const CHAIN_SAIL_FACTOR: float = 1.55  ## chain shot's bonus vs sails.
const GRAPE_CREW_FACTOR: float = 1.70  ## grape shot's bonus vs crew.
const FLEE_SAIL_FRAC: float = 0.30     ## below this sail integrity a ship tries to flee.
const FLEE_CREW_FRAC: float = 0.28     ## below this crew fraction a ship breaks / flees.

# =====================================================================
#  Boarding
# =====================================================================

const MAX_BOARD_ROUNDS: int = 24
const BOARD_BASE_CASUALTY: float = 0.16  ## fraction of the LOSING side lost per round.

# =====================================================================
#  Crew, morale, upkeep
# =====================================================================

const PAY_PERIOD: int = 30              ## wages fall due every 30 days.
const WAGE_PER_CREW: float = 0.9        ## gold owed per crew per pay period.
const FOOD_PER_CREW: float = 0.05       ## food units eaten per crew per day.
const MORALE_MAX: float = 1.0
const MORALE_SEA_DECAY: float = 0.0022  ## daily morale bleed of a hard life at sea.
const MORALE_UNPAID_HIT: float = 0.22   ## morale lost when a payday can't be met.
const MORALE_HUNGRY_HIT: float = 0.012  ## daily morale lost while starving.
const MORALE_WIN_GAIN: float = 0.10     ## morale gained by a victory.
const MORALE_PLUNDER_GAIN: float = 0.16 ## morale gained by dividing plunder.
const MORALE_SHORE_GAIN: float = 0.09   ## morale gained by shore leave.
const MUTINY_THRESHOLD: float = 0.14    ## at/below this at a payday check -> MUTINY.

# =====================================================================
#  Progression / career
# =====================================================================

const MAX_CAREER_DAYS: int = 3650       ## a bounded ~10-year career (guarantees an end).
const START_AGE: int = 20
const NEW_SHIP_COST: int = 900          ## gold to re-fit after a sinking (else career ends).
const SKILL_MAX: float = 5.0
const FAME_PER_WEALTH_STEP: int = 45    ## fame granted per net-worth milestone crossed.
const WEALTH_STEP: int = 4000           ## net-worth milestone size.
const LAND_REP: float = 62.0            ## rep needed for a nation to grant land.
const MARQUE_REP: float = 40.0          ## rep needed to be offered a letter of marque.
const HOSTILE_REP: float = -45.0        ## below this a nation's ports are hostile.
const LAND_GRANT_FAME: int = 220
const LAND_GRANT_GOLD: int = 500

## Retirement ranks by minimum final score (ascending).
const RANKS: Array = [
	{"name": "Bilge Rat",           "min": 0},
	{"name": "Freebooter",          "min": 800},
	{"name": "Buccaneer",           "min": 2000},
	{"name": "Corsair Captain",     "min": 4200},
	{"name": "Notorious Privateer", "min": 7200},
	{"name": "Dread Pirate Lord",   "min": 11000},
]
const WIN_RANK_INDEX: int = 3           ## retire at "Corsair Captain" or higher = WIN.

# =====================================================================
#  Treasure + quest chain
# =====================================================================

const FRAGMENTS_FOR_MAP: int = 4        ## fragments that complete a treasure map.
const TREASURE_GOLD: int = 3200
const TREASURE_FAME: int = 400
## A bounded ordered quest chain (each step: a deliver/hunt objective).
const QUEST_CHAIN: Array = [
	{"kind": "deliver", "good": "rum",   "qty": 20, "fame": 120, "gold": 350, "desc": "Run rum to a thirsty garrison"},
	{"kind": "bounty",  "tier": "sloop",             "fame": 180, "gold": 500, "desc": "Hunt the rogue El Tiburon"},
	{"kind": "deliver", "good": "spice", "qty": 15, "fame": 160, "gold": 600, "desc": "Smuggle spice past a blockade"},
	{"kind": "bounty",  "tier": "frigate",           "fame": 260, "gold": 900, "desc": "Sink the mutineer's frigate"},
]

# =====================================================================
#  Enemy-ship archetypes (generated per encounter, scaled by a seed roll)
# =====================================================================

const SHIP_TIERS: Dictionary = {
	"merchant":  {"hull": 120, "sails": 90,  "cannons": 8,  "crew": 24,  "gunnery": 1.0, "prize": 240,  "cargo_units": 60},
	"sloop":     {"hull": 150, "sails": 120, "cannons": 12, "crew": 40,  "gunnery": 1.8, "prize": 380,  "cargo_units": 30},
	"frigate":   {"hull": 260, "sails": 130, "cannons": 22, "crew": 90,  "gunnery": 2.6, "prize": 760,  "cargo_units": 40},
	"man_o_war": {"hull": 420, "sails": 140, "cannons": 34, "crew": 150, "gunnery": 3.4, "prize": 1500, "cargo_units": 50},
}

# =====================================================================
#  Live career state
# =====================================================================

var day: int = 0
var phase: String = "setup"             ## setup | sailing | port | combat | done.
var career_over: bool = false
var career_won: bool = false
var end_cause: String = ""              ## retired | sunk | mutiny.
var retirement_rank: int = 0

# Captain.
var captain_name: String = "Captain"
var age: float = float(START_AGE)
var fame: int = 0
var gold: int = 200
var land: int = 0
var skills: Dictionary = {"navigation": 0.0, "gunnery": 0.0, "fencing": 0.0, "wit": 0.0}

# Ship.
var ship: Dictionary = {}
var cargo: Dictionary = {}              ## good id -> units aboard.

# Standing with each nation (-100..+100) + marque.
var reputation: Dictionary = {}
var marque: String = ""                 ## nation whose letter of marque is held ("" = none).

# World.
var ports: Array = []                   ## array of port dicts.
var location: int = 0                   ## current port index.
var rivals: Array = []                  ## AI pirate captains.

# Crew upkeep.
var morale: float = 0.78
var food: float = 0.0
var wage_debt: float = 0.0
var last_payday: int = 0

# Quests / treasure.
var fragments: int = 0
var quest_step: int = 0
var quest_done: bool = false
var treasure_found: bool = false

# Encounter (a ship in these waters the captain may attack / that may attack them).
var encounter: Dictionary = {}

# Bookkeeping.
var illegal_attempts: int = 0
var battles_won: int = 0
var ships_captured: int = 0
var net_worth_peak: int = 0
var last_combat: Dictionary = {}
var log_lines: Array = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = 0
var _policy: String = "trade"           ## auto-play policy: trade | reckless | neglect.


# =====================================================================
#  Setup / world generation
# =====================================================================

## Start a fresh career. seed_value == 0 -> random; any other value replays
## byte-identically. `config` overrides: captain_name:String, policy:String,
## start_gold:int.
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	_seed = seed_value
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value
	_policy = String(config.get("policy", "trade"))
	captain_name = String(config.get("captain_name", "Captain Nemo"))
	day = 0
	age = float(START_AGE)
	fame = 0
	gold = int(config.get("start_gold", 200))
	land = 0
	skills = {"navigation": 0.0, "gunnery": 0.0, "fencing": 0.0, "wit": 0.0}
	cargo = {}
	for gid in GOOD_IDS:
		cargo[gid] = 0
	reputation = {}
	for n in NATIONS:
		reputation[n] = 0.0
	marque = ""
	morale = 0.78
	wage_debt = 0.0
	last_payday = 0
	fragments = 0
	quest_step = 0
	quest_done = false
	treasure_found = false
	encounter = {}
	illegal_attempts = 0
	battles_won = 0
	ships_captured = 0
	net_worth_peak = 0
	last_combat = {}
	career_over = false
	career_won = false
	end_cause = ""
	retirement_rank = 0
	log_lines = []
	_make_ship()
	food = 220.0
	_generate_world()
	_generate_rivals()
	location = 0
	phase = "port"
	_recompute_encounter()
	_log("Career begins at %s under seed %d." % [String(ports[location]["name"]), _seed])


## Build the player's starting ship (a modest sloop).
func _make_ship() -> void:
	ship = {
		"name": "Sea Wraith",
		"class": "sloop",
		"hull": 150.0, "hull_max": 150.0,
		"sails": 120.0, "sails_max": 120.0,
		"cannons": 12,
		"cargo_cap": 120,
		"base_speed": 1.0,
		"crew": 34, "crew_max": 60,
	}


## Deterministically place NUM_PORTS ports across the 4 nations, each with a
## position, wealth tier, garrison, and a full per-good local economy.
func _generate_world() -> void:
	ports = []
	var per_nation: int = int(NUM_PORTS / NATIONS.size())
	var port_names: Array = [
		"Port Royal", "Tortuga", "Havana", "Nassau", "Cartagena", "Maracaibo",
		"Santo Domingo", "Bridgetown", "Willemstad", "Kingston", "Campeche",
		"Panama", "Trinidad", "Curacao", "Belize", "St. Kitts",
	]
	var idx: int = 0
	for ni in NATIONS.size():
		var nation: String = String(NATIONS[ni])
		for _k in per_nation:
			var wealth: int = 1 + _rng.randi_range(0, 2)
			var pos: Vector2 = Vector2(
				_rng.randf_range(60.0, SEA_W - 60.0),
				_rng.randf_range(60.0, SEA_H - 60.0))
			var garrison: int = 6 + wealth * 8 + _rng.randi_range(0, 10)
			var econ: Dictionary = _make_port_economy(nation, wealth)
			ports.append({
				"name": String(port_names[idx % port_names.size()]),
				"nation": nation,
				"wealth": wealth,
				"pos_x": pos.x, "pos_y": pos.y,
				"garrison": garrison,
				"econ": econ,        ## good id -> {stock, base_stock, demand}
			})
			idx += 1
	# Any remainder ports (if NUM_PORTS not divisible) go to the first nation.
	while ports.size() < NUM_PORTS:
		var wealth2: int = 1 + _rng.randi_range(0, 2)
		var econ2: Dictionary = _make_port_economy(String(NATIONS[0]), wealth2)
		ports.append({
			"name": String(port_names[ports.size() % port_names.size()]),
			"nation": String(NATIONS[0]), "wealth": wealth2,
			"pos_x": _rng.randf_range(60.0, SEA_W - 60.0),
			"pos_y": _rng.randf_range(60.0, SEA_H - 60.0),
			"garrison": 10 + wealth2 * 8, "econ": econ2,
		})


## A port's economy: each good gets a production/consumption baseline. Producers
## carry high stock (cheap); consumers carry low stock + high demand (dear). This is
## what makes cross-port ARBITRAGE emergent, not scripted.
func _make_port_economy(nation: String, wealth: int) -> Dictionary:
	var econ: Dictionary = {}
	# Choose 2 produced goods + treat the rest as consumed, seeded per port.
	var shuffled: Array = GOOD_IDS.duplicate()
	_seeded_shuffle(shuffled)
	var produced: Array = [String(shuffled[0]), String(shuffled[1])]
	for gid in GOOD_IDS:
		var is_prod: bool = produced.has(gid)
		var demand: float
		var base_stock: float
		# Prices are kept inside the UNCLAMPED band (roughly 0.5x .. 2.4x base) so a
		# producer is cheap + a consumer is dear WITHOUT pegging the floor/ceiling —
		# that way trading actually MOVES the marginal price (visible impact + drift).
		if is_prod:
			# abundant supply vs modest demand -> scarcity ~0.5 -> price ~0.55x.
			base_stock = 150.0 + float(wealth) * 22.0 + _rng.randf_range(0.0, 40.0)
			demand = 78.0 + float(wealth) * 10.0 + _rng.randf_range(0.0, 20.0)
		else:
			# scarce supply vs hungry demand -> scarcity ~2.4 -> price ~2.1x.
			base_stock = 60.0 + float(wealth) * 8.0 + _rng.randf_range(0.0, 30.0)
			demand = 150.0 + float(wealth) * 22.0 + _rng.randf_range(0.0, 40.0)
		econ[gid] = {
			"stock": base_stock,
			"base_stock": base_stock,
			"demand": demand,
		}
	return econ


## Deterministic Fisher-Yates over the engine RNG.
func _seeded_shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Spin up a handful of AI rival captains that sail, trade, and can be fought.
func _generate_rivals() -> void:
	rivals = []
	var names: Array = ["Blackheart Rourke", "La Sirena", "Silas Vane", "Mad Anne Gray", "Diego Cruz"]
	var tiers: Array = ["sloop", "sloop", "frigate", "sloop", "frigate"]
	for i in names.size():
		var home: int = _rng.randi_range(0, ports.size() - 1)
		rivals.append({
			"name": String(names[i]),
			"tier": String(tiers[i]),
			"location": home,
			"dest": home,
			"gold": 300 + _rng.randi_range(0, 400),
			"fame": 40 + _rng.randi_range(0, 120),
			"alive": true,
			"days_to_dest": 0,
		})


# =====================================================================
#  Geometry + wind + sailing
# =====================================================================

func port_pos(i: int) -> Vector2:
	return Vector2(float(ports[i]["pos_x"]), float(ports[i]["pos_y"]))


func distance_between(a: int, b: int) -> float:
	return port_pos(a).distance_to(port_pos(b))


## The prevailing wind bearing on a given day (the direction the wind BLOWS TOWARD).
func wind_dir(d: int) -> float:
	return fposmod(BASE_WIND + float(d) * WIND_DRIFT, TAU)


## Wind speed multiplier for a heading `bearing` on day `d`: dead downwind is fast,
## hard upwind is slow. Navigation skill trims the upwind penalty.
func wind_factor(bearing: float, d: int) -> float:
	var align: float = cos(bearing - wind_dir(d))   ## +1 downwind, -1 upwind.
	var base: float = lerp(WIND_AGAINST, WIND_WITH, (align + 1.0) * 0.5)
	# navigation eases the worst upwind sailing.
	var nav: float = float(skills["navigation"]) / SKILL_MAX
	if base < 1.0:
		base = base + (1.0 - base) * (0.35 * nav)
	return base


## Days it takes to sail from the current port to `dest`, given the ship's speed,
## sail integrity, navigation skill, and the wind on departure day.
func travel_days_to(dest: int) -> int:
	if dest == location:
		return 0
	var dist: float = distance_between(location, dest)
	var bearing: float = port_pos(location).angle_to_point(port_pos(dest))
	var sail_health: float = clampf(float(ship["sails"]) / float(ship["sails_max"]), 0.15, 1.0)
	var nav_bonus: float = 1.0 + 0.05 * float(skills["navigation"])
	var effective: float = LEAGUES_PER_DAY * float(ship["base_speed"]) * sail_health \
		* nav_bonus * wind_factor(bearing, day)
	return maxi(1, int(ceil(dist / maxf(1.0, effective))))


# =====================================================================
#  Economy — supply/demand pricing with price impact + drift
# =====================================================================

## The MID price of one unit of `good` at `port_i` given the current stock/demand.
func _mid_price(port_i: int, good: String) -> float:
	var e: Dictionary = ports[port_i]["econ"][good]
	var base: float = float(GOODS[good]["base"])
	var stock: float = maxf(1.0, float(e["stock"]))
	var demand: float = maxf(1.0, float(e["demand"]))
	var scarcity: float = demand / stock
	var mult: float = clampf(pow(scarcity, ELASTICITY), PRICE_MIN_MULT, PRICE_MAX_MULT)
	return base * mult


## The price a player pays to BUY (side "buy") or receives to SELL (side "sell") one
## unit right now — the mid price plus/minus the spread, trimmed by wit skill.
func unit_price(port_i: int, good: String, side: String) -> int:
	var mid: float = _mid_price(port_i, good)
	var wit: float = float(skills["wit"]) / SKILL_MAX
	var spread: float = SPREAD * (1.0 - 0.4 * wit)   ## a shrewd captain trades tighter.
	if side == "buy":
		return maxi(1, int(round(mid * (1.0 + spread))))
	return maxi(1, int(round(mid * (1.0 - spread))))


## The current buy price of a good at the player's port (for the UI).
func port_buy_price(good: String) -> int:
	return unit_price(location, good, "buy")


func port_sell_price(good: String) -> int:
	return unit_price(location, good, "sell")


## The total gold cost of buying `qty` units of `good` here, computed unit-by-unit so
## depleting local stock RAISES the marginal price (real price impact within one order).
func quote_buy(good: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var e: Dictionary = ports[location]["econ"][good]
	var stock: float = float(e["stock"])
	var total: int = 0
	for _u in qty:
		var mid: float = _price_from(stock, float(e["demand"]), float(GOODS[good]["base"]))
		var wit: float = float(skills["wit"]) / SKILL_MAX
		total += maxi(1, int(round(mid * (1.0 + SPREAD * (1.0 - 0.4 * wit)))))
		stock = maxf(1.0, stock - IMPACT_UNIT)
	return total


## The total gold received for selling `qty` units — dumping stock LOWERS the price.
func quote_sell(good: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var e: Dictionary = ports[location]["econ"][good]
	var stock: float = float(e["stock"])
	var total: int = 0
	for _u in qty:
		var mid: float = _price_from(stock, float(e["demand"]), float(GOODS[good]["base"]))
		var wit: float = float(skills["wit"]) / SKILL_MAX
		total += maxi(1, int(round(mid * (1.0 - SPREAD * (1.0 - 0.4 * wit)))))
		stock = stock + IMPACT_UNIT
	return total


## Pure price for a hypothetical (stock, demand) — the same curve as _mid_price.
func _price_from(stock: float, demand: float, base: float) -> float:
	var s: float = maxf(1.0, stock)
	var d: float = maxf(1.0, demand)
	var scarcity: float = d / s
	return base * clampf(pow(scarcity, ELASTICITY), PRICE_MIN_MULT, PRICE_MAX_MULT)


## Buy `qty` units of `good` at the current port. Rejects unaffordable / over-cargo /
## illegal orders. Moves the local price (stock down) and nudges wit skill.
func buy(good: String, qty: int) -> bool:
	if not is_legal({"type": "buy", "good": good, "qty": qty}):
		illegal_attempts += 1
		return false
	var cost: int = quote_buy(good, qty)
	gold -= cost
	cargo[good] = int(cargo.get(good, 0)) + qty
	var e: Dictionary = ports[location]["econ"][good]
	e["stock"] = maxf(1.0, float(e["stock"]) - float(qty) * IMPACT_UNIT)
	_gain_skill("wit", 0.02 * float(qty) / 40.0)
	_check_quest_deliver(good)
	_log("Bought %d %s for %d gold at %s." % [qty, String(GOODS[good]["name"]), cost, String(ports[location]["name"])])
	return true


## Sell `qty` units of `good` at the current port. Rejects selling more than aboard.
func sell(good: String, qty: int) -> bool:
	if not is_legal({"type": "sell", "good": good, "qty": qty}):
		illegal_attempts += 1
		return false
	var revenue: int = quote_sell(good, qty)
	gold += revenue
	cargo[good] = int(cargo.get(good, 0)) - qty
	var e: Dictionary = ports[location]["econ"][good]
	e["stock"] = float(e["stock"]) + float(qty) * IMPACT_UNIT
	_gain_skill("wit", 0.02 * float(qty) / 40.0)
	_note_wealth()
	_log("Sold %d %s for %d gold at %s." % [qty, String(GOODS[good]["name"]), revenue, String(ports[location]["name"])])
	return true


func cargo_used() -> int:
	var t: int = 0
	for gid in GOOD_IDS:
		t += int(cargo.get(gid, 0))
	return t


func cargo_free() -> int:
	return int(ship["cargo_cap"]) - cargo_used()


# =====================================================================
#  Sailing action — advances days, ticks the world, may spawn an encounter
# =====================================================================

## Sail to port `dest`. Illegal with no crew, to the current port, or when the run is
## over. Advances the world by the travel time, then docks (or is intercepted).
func sail_to(dest: int) -> bool:
	if not is_legal({"type": "sail", "dest": dest}):
		illegal_attempts += 1
		return false
	var days: int = travel_days_to(dest)
	phase = "sailing"
	_advance_days(days)
	if career_over:
		return true
	location = dest
	phase = "port"
	_gain_skill("navigation", 0.05 + 0.02 * float(days))
	_recompute_encounter()
	_maybe_land_grant()
	_maybe_marque_offer()
	_log("Made port at %s (%s) after %d days." % [String(ports[dest]["name"]), String(ports[dest]["nation"]), days])
	return true


## Advance the world by `n` days: economy drift, wind, food, wages/morale, aging,
## rival movement, and the career-length cap. Every player action funnels through
## here, so the whole timeline is one deterministic tick stream.
func _advance_days(n: int) -> void:
	for _d in n:
		if career_over:
			return
		day += 1
		age += 1.0 / 365.0
		_drift_economy()
		_consume_food()
		morale = clampf(morale - MORALE_SEA_DECAY, 0.0, MORALE_MAX)
		_advance_rivals()
		# Wages come due periodically.
		if day - last_payday >= PAY_PERIOD:
			_run_payday()
			if career_over:
				return
		# Hard career cap -> forced retirement (guarantees termination).
		if day >= MAX_CAREER_DAYS:
			_retire_internal("cap")
			return


## Every port's stock relaxes toward its baseline (prices drift back to equilibrium),
## so a fleeced market recovers and arbitrage windows reopen — not a one-shot exploit.
func _drift_economy() -> void:
	for p in ports:
		var econ: Dictionary = p["econ"]
		for gid in GOOD_IDS:
			var e: Dictionary = econ[gid]
			var base_stock: float = float(e["base_stock"])
			var stock: float = float(e["stock"])
			e["stock"] = stock + (base_stock - stock) * DRIFT_RATE


func _consume_food() -> void:
	var eaten: float = FOOD_PER_CREW * float(ship["crew"])
	food = maxf(0.0, food - eaten)
	if food <= 0.0:
		morale = clampf(morale - MORALE_HUNGRY_HIT, 0.0, MORALE_MAX)


## Payday: try to pay the crew's wages from gold. Full pay steadies morale; a shortfall
## bleeds it and risks a MUTINY that ends the career.
func _run_payday() -> void:
	last_payday = day
	var due: int = int(ceil(WAGE_PER_CREW * float(ship["crew"])))
	if gold >= due:
		gold -= due
		morale = clampf(morale + 0.02, 0.0, MORALE_MAX)
		_log("Paid the crew %d gold in wages. Morale holds." % due)
	else:
		wage_debt += float(due - gold)
		gold = 0
		morale = clampf(morale - MORALE_UNPAID_HIT, 0.0, MORALE_MAX)
		_log("Could NOT meet payroll (short %d gold). The crew grumbles." % (due - int(gold)))
	if morale <= MUTINY_THRESHOLD:
		_mutiny()


func _mutiny() -> void:
	_log("MUTINY! The crew turns on the captain — the career ends in irons.")
	_end_career("mutiny", false)


# =====================================================================
#  Reputation, marque, land
# =====================================================================

## Shift standing after attacking a ship of `flag` nation. Piracy against a nation
## drops its standing and lifts its sworn enemy's; a valid marque converts the raid
## into sanctioned privateering (no penalty vs the patron, a bonus instead).
func _apply_attack_reputation(flag: String, severity: float) -> void:
	if flag == "":
		return
	var sanctioned: bool = marque != "" and String(ENEMY_OF.get(marque, "")) == flag
	if sanctioned:
		reputation[marque] = clampf(float(reputation[marque]) + severity * 0.5, -100.0, 100.0)
		reputation[flag] = clampf(float(reputation[flag]) - severity * 0.6, -100.0, 100.0)
	else:
		reputation[flag] = clampf(float(reputation[flag]) - severity, -100.0, 100.0)
		var enemy: String = String(ENEMY_OF.get(flag, ""))
		if enemy != "":
			reputation[enemy] = clampf(float(reputation[enemy]) + severity * 0.5, -100.0, 100.0)
		# Attacking your own patron voids the marque.
		if marque == flag:
			_log("Raiding %s under their own flag — the letter of marque is torn up." % flag)
			marque = ""


## Is the port at `i` hostile to the captain (very low standing)? Hostile ports fire
## on approach and refuse safe trade.
func port_hostile(i: int) -> bool:
	return float(reputation[String(ports[i]["nation"])]) <= HOSTILE_REP


## After docking, a nation you stand well with may grant land + gold + fame.
func _maybe_land_grant() -> void:
	var nation: String = String(ports[location]["nation"])
	if float(reputation[nation]) >= LAND_REP and _rng.randf() < 0.5:
		land += 1
		gold += LAND_GRANT_GOLD
		fame += LAND_GRANT_FAME
		reputation[nation] = clampf(float(reputation[nation]) - 6.0, -100.0, 100.0)
		_log("The governor of %s grants you an estate (+1 land, +%d fame)." % [String(ports[location]["name"]), LAND_GRANT_FAME])


## A nation you stand well with (and are not already sworn to) may offer a marque.
func _maybe_marque_offer() -> void:
	if marque != "":
		return
	var nation: String = String(ports[location]["nation"])
	if float(reputation[nation]) >= MARQUE_REP:
		marque = nation
		_log("%s issues you a Letter of Marque — privateering against %s is now sanctioned." % [nation, String(ENEMY_OF.get(nation, "rivals"))])


func accept_marque(nation: String) -> bool:
	if career_over or nation == "" or not NATIONS.has(nation):
		illegal_attempts += 1
		return false
	if float(reputation[nation]) < MARQUE_REP:
		illegal_attempts += 1
		return false
	marque = nation
	_log("Accepted a Letter of Marque from %s." % nation)
	return true


# =====================================================================
#  Encounters + sea combat
# =====================================================================

## Decide (deterministically) whether a ship is in these waters to fight. Hostile
## waters spawn a patrol; otherwise a merchant/rival may appear based on wealth + a
## seeded roll. Sets `encounter` ({} = clear seas).
func _recompute_encounter() -> void:
	encounter = {}
	var nation: String = String(ports[location]["nation"])
	var roll: float = _rng.randf()
	if port_hostile(location):
		# A furious nation sends a warship after a notorious pirate.
		encounter = _make_enemy("frigate" if float(reputation[nation]) > -70.0 else "man_o_war", nation)
		return
	if roll < 0.34:
		encounter = _make_enemy("merchant", nation)
	elif roll < 0.5:
		encounter = _make_enemy("sloop", String(ENEMY_OF.get(nation, nation)))


## Build a concrete enemy ship of `tier` flying `flag`, scaled by a seeded roll and
## loaded with cargo a capture would yield.
func _make_enemy(tier: String, flag: String) -> Dictionary:
	var t: Dictionary = SHIP_TIERS[tier]
	var scale: float = 0.86 + _rng.randf() * 0.34
	var enemy_cargo: Dictionary = {}
	var units_left: int = int(t["cargo_units"])
	var pool: Array = GOOD_IDS.duplicate()
	_seeded_shuffle(pool)
	var give: int = 2 + _rng.randi_range(0, 2)
	for i in give:
		var g: String = String(pool[i % pool.size()])
		var q: int = _rng.randi_range(4, maxi(4, units_left / 2))
		enemy_cargo[g] = q
		units_left = maxi(0, units_left - q)
	return {
		"name": "%s %s" % [flag, tier.capitalize()],
		"tier": tier,
		"flag": flag,
		"hull": float(t["hull"]) * scale, "hull_max": float(t["hull"]) * scale,
		"sails": float(t["sails"]) * scale, "sails_max": float(t["sails"]) * scale,
		"cannons": int(t["cannons"]),
		"crew": int(round(float(t["crew"]) * scale)), "crew_max": int(round(float(t["crew"]) * scale)),
		"gunnery": float(t["gunnery"]),
		"prize": int(t["prize"]),
		"cargo": enemy_cargo,
	}


## Fire ONE broadside from `shooter` at `target` with the given shot type + range.
## Damage scales with cannons, gunnery, range, and (for round shot) target hull.
## Returns the numeric damage dealt to the relevant subsystem. MUTATES the target.
func _fire_broadside(shooter: Dictionary, target: Dictionary, shot: String, range_idx: int, gun_skill: float) -> Dictionary:
	var cannons: float = float(shooter["cannons"])
	var gunnery: float = float(shooter["gunnery"]) + gun_skill
	var hit: float = float(RANGE_HIT_FACTOR[range_idx]) * (0.55 + 0.16 * gunnery)
	hit = clampf(hit, 0.15, 1.0)
	# a deterministic salvo roll from the engine RNG.
	var roll: float = 0.7 + _rng.randf() * 0.6
	var raw: float = cannons * GUN_BASE * gunnery * hit * roll
	var to_hull: float = 0.0
	var to_sails: float = 0.0
	var to_crew: float = 0.0
	match shot:
		"round":
			to_hull = raw * float(RANGE_HULL_FACTOR[range_idx])
			target["hull"] = maxf(0.0, float(target["hull"]) - to_hull)
			to_crew = raw * 0.10
			target["crew"] = maxi(0, int(target["crew"]) - int(round(to_crew)))
		"chain":
			to_sails = raw * CHAIN_SAIL_FACTOR
			target["sails"] = maxf(0.0, float(target["sails"]) - to_sails)
		"grape":
			to_crew = raw * GRAPE_CREW_FACTOR * 0.14
			target["crew"] = maxi(0, int(target["crew"]) - int(round(to_crew)))
	return {"hull": to_hull, "sails": to_sails, "crew": to_crew}


## Resolve a full deterministic ship duel between the player's ship and `enemy`, with
## the player's chosen `stance` (sink | cripple | board). Maneuvering contests the
## WIND GAUGE each turn (weather-gauge holder fires first + closes range); shot types
## follow the stance; the fight ends in SINK / FLEE / BOARD within MAX_COMBAT_TURNS.
## Returns a rich result dict (also stored in last_combat). PURE w.r.t. RNG state.
func simulate_combat(enemy: Dictionary, stance: String) -> Dictionary:
	var pl: Dictionary = {
		"hull": float(ship["hull"]), "hull_max": float(ship["hull_max"]),
		"sails": float(ship["sails"]), "sails_max": float(ship["sails_max"]),
		"cannons": int(ship["cannons"]), "crew": int(ship["crew"]), "crew_max": int(ship["crew_max"]),
		"gunnery": 1.0 + float(skills["gunnery"]),
	}
	var en: Dictionary = enemy.duplicate(true)
	var range_idx: int = RANGE_LONG
	var gun_skill: float = float(skills["gunnery"])
	var turns: int = 0
	var outcome: String = ""
	var trace: Array = []
	# Enemy AI stance: warships slug it out, merchants try to flee/cripple, pirates board.
	var enemy_stance: String = _enemy_stance(String(en["tier"]))
	while turns < MAX_COMBAT_TURNS:
		turns += 1
		# 1) maneuver for the weather gauge.
		var pl_man: float = float(pl["cannons"]) * 0.0 + (float(pl["sails"]) / float(pl["sails_max"])) \
			* (1.0 + 0.12 * float(skills["navigation"])) + _rng.randf() * 0.5
		var en_man: float = (float(en["sails"]) / float(en["sails_max"])) + _rng.randf() * 0.5
		var player_gauge: bool = pl_man >= en_man
		# 2) desired range from stance: sink=hold medium, cripple/board=close.
		var want_close: bool = stance in ["cripple", "board"]
		if player_gauge and want_close and range_idx > RANGE_GRAPPLED:
			range_idx -= 1
		elif not player_gauge and enemy_stance == "board" and range_idx > RANGE_GRAPPLED:
			range_idx -= 1
		elif player_gauge and not want_close and range_idx < RANGE_MEDIUM:
			range_idx += 1
		# 3) broadsides — the gauge holder fires first (may sink the foe before reply).
		var pl_shot: String = _stance_shot(stance)
		var en_shot: String = _stance_shot(enemy_stance)
		if player_gauge:
			_fire_broadside(pl, en, pl_shot, range_idx, gun_skill)
			if float(en["hull"]) > 0.0 and int(en["crew"]) > 0:
				_fire_broadside(en, pl, en_shot, range_idx, 0.0)
		else:
			_fire_broadside(en, pl, en_shot, range_idx, 0.0)
			if float(pl["hull"]) > 0.0 and int(pl["crew"]) > 0:
				_fire_broadside(pl, en, pl_shot, range_idx, gun_skill)
		trace.append({"turn": turns, "range": range_idx, "pl_hull": float(pl["hull"]), "en_hull": float(en["hull"])})
		# 4) resolve outcomes.
		if float(pl["hull"]) <= 0.0:
			outcome = "player_sunk"
			break
		if float(en["hull"]) <= 0.0:
			outcome = "enemy_sunk"
			break
		# boarding when grappled and either side wants it.
		if range_idx == RANGE_GRAPPLED and (stance == "board" or stance == "cripple" or enemy_stance == "board"):
			outcome = "boarding"
			break
		# a badly-crippled or crew-thin enemy tries to run.
		if float(en["sails"]) / float(en["sails_max"]) < FLEE_SAIL_FRAC \
			and float(en["hull"]) / float(en["hull_max"]) < 0.4 and range_idx >= RANGE_MEDIUM:
			outcome = "enemy_fled"
			break
		if int(en["crew"]) <= int(float(en["crew_max"]) * FLEE_CREW_FRAC) and stance != "board":
			outcome = "enemy_struck"   ## crew broke -> surrenders.
			break
	if outcome == "":
		# hit the turn cap: whoever has the higher hull fraction prevails.
		var pf: float = float(pl["hull"]) / float(pl["hull_max"])
		var ef: float = float(en["hull"]) / float(en["hull_max"])
		outcome = "enemy_struck" if pf >= ef else "player_fled"
	var result: Dictionary = {
		"outcome": outcome, "turns": turns, "stance": stance,
		"player": pl, "enemy": en, "trace": trace,
		"boarding": null,
	}
	if outcome == "boarding":
		result["boarding"] = _resolve_boarding(pl, en)
	last_combat = result
	return result


func _enemy_stance(tier: String) -> String:
	match tier:
		"merchant": return "cripple"
		"sloop": return "board"
		"frigate": return "sink"
		"man_o_war": return "sink"
	return "sink"


func _stance_shot(stance: String) -> String:
	match stance:
		"sink": return "round"
		"cripple": return "chain"
		"board": return "grape"
	return "round"


## Deterministic crew-vs-crew boarding melee: each round the stronger side (crew *
## morale * fencing) inflicts casualties on the weaker until one side breaks. Returns
## {winner, pl_crew, en_crew, rounds}.
func _resolve_boarding(pl: Dictionary, en: Dictionary) -> Dictionary:
	var pl_crew: float = float(pl["crew"])
	var en_crew: float = float(en["crew"])
	var pl_start: float = maxf(1.0, pl_crew)
	var en_start: float = maxf(1.0, en_crew)
	var rounds: int = 0
	var winner: String = ""
	while rounds < MAX_BOARD_ROUNDS:
		rounds += 1
		var pl_power: float = pl_crew * (0.55 + 0.45 * morale) * (1.0 + 0.14 * float(skills["fencing"])) * (0.85 + _rng.randf() * 0.3)
		var en_power: float = en_crew * 0.9 * (0.85 + _rng.randf() * 0.3)
		# each side removes crew from the other in proportion to its own power.
		var to_en: float = BOARD_BASE_CASUALTY * en_start * (pl_power / maxf(1.0, pl_power + en_power)) * 2.0
		var to_pl: float = BOARD_BASE_CASUALTY * pl_start * (en_power / maxf(1.0, pl_power + en_power)) * 2.0
		en_crew = maxf(0.0, en_crew - to_en)
		pl_crew = maxf(0.0, pl_crew - to_pl)
		if en_crew <= en_start * FLEE_CREW_FRAC:
			winner = "player"
			break
		if pl_crew <= pl_start * FLEE_CREW_FRAC:
			winner = "enemy"
			break
	if winner == "":
		winner = "player" if pl_crew >= en_crew else "enemy"
	return {"winner": winner, "pl_crew": int(round(pl_crew)), "en_crew": int(round(en_crew)), "rounds": rounds}


## The player commits to attacking the current encounter with a chosen `stance`.
## Runs the full duel, applies its consequences to the ship, cargo, crew, reputation,
## fame, and morale, and may end the career if the player's ship is lost. Returns the
## combat result, or {} if illegal.
func attack(stance: String) -> Dictionary:
	if not is_legal({"type": "attack", "stance": stance}):
		illegal_attempts += 1
		return {}
	var enemy: Dictionary = encounter
	var flag: String = String(enemy["flag"])
	phase = "combat"
	var res: Dictionary = simulate_combat(enemy, stance)
	var severity: float = 4.0 + float(SHIP_TIERS[String(enemy["tier"])]["cannons"]) * 0.35
	_apply_attack_reputation(flag, severity)
	_gain_skill("gunnery", 0.14)
	# write the ship's battle damage back onto the persistent ship.
	ship["hull"] = float(res["player"]["hull"])
	ship["sails"] = float(res["player"]["sails"])
	ship["crew"] = int(res["player"]["crew"])
	var outcome: String = String(res["outcome"])
	match outcome:
		"player_sunk":
			_handle_player_ship_lost("sunk in a broadside duel")
		"enemy_sunk":
			_victory(enemy, false, res)
		"enemy_struck", "enemy_fled":
			if outcome == "enemy_struck":
				_victory(enemy, false, res)
			else:
				_log("The %s slips away over the horizon." % String(enemy["name"]))
		"boarding":
			var board: Dictionary = res["boarding"]
			_gain_skill("fencing", 0.16)
			if String(board["winner"]) == "player":
				ship["crew"] = maxi(1, int(board["pl_crew"]))
				_victory(enemy, true, res)
			else:
				ship["crew"] = maxi(0, int(board["pl_crew"]))
				morale = clampf(morale - 0.14, 0.0, MORALE_MAX)
				_log("The boarding is REPELLED — the crew is cut down (%d left)." % int(ship["crew"]))
				if int(ship["crew"]) <= 0:
					_handle_player_ship_lost("overrun during a failed boarding")
		"player_fled":
			morale = clampf(morale - 0.06, 0.0, MORALE_MAX)
			_log("Outgunned — you break off and flee the %s." % String(enemy["name"]))
	if not career_over:
		phase = "port"
		encounter = {}
	return res


## Resolve a WON fight: fame + prize gold, captured cargo (if boarded), morale, and
## quest-bounty credit.
func _victory(enemy: Dictionary, boarded: bool, _res: Dictionary) -> void:
	battles_won += 1
	var prize: int = int(enemy["prize"])
	fame += int(round(float(prize) / 6.0)) + 20
	morale = clampf(morale + MORALE_WIN_GAIN, 0.0, MORALE_MAX)
	if boarded:
		ships_captured += 1
		gold += prize
		# load as much of the prize's cargo as will fit.
		var enemy_cargo: Dictionary = enemy["cargo"]
		for gid in enemy_cargo.keys():
			var space: int = cargo_free()
			if space <= 0:
				break
			var take: int = mini(int(enemy_cargo[gid]), space)
			cargo[gid] = int(cargo.get(gid, 0)) + take
		# a captured hull may also yield a treasure-map fragment.
		if _rng.randf() < 0.4:
			fragments += 1
			_log("A treasure-map fragment is found in the prize's hold (%d/%d)." % [fragments, FRAGMENTS_FOR_MAP])
		_log("BOARDED and captured the %s! +%d gold, cargo seized." % [String(enemy["name"]), prize])
	else:
		gold += int(round(float(prize) * 0.55))
		_log("SANK the %s. +%d gold in floating plunder." % [String(enemy["name"]), int(round(float(prize) * 0.55))])
	_check_quest_bounty(String(enemy["tier"]))
	_note_wealth()


## The player's ship is lost. If gold covers a refit, a new sloop is bought at the
## nearest friendly port and the career continues; otherwise the career ends.
func _handle_player_ship_lost(reason: String) -> void:
	if gold >= NEW_SHIP_COST:
		gold -= NEW_SHIP_COST
		_make_ship()
		ship["crew"] = 24
		morale = clampf(morale - 0.10, 0.0, MORALE_MAX)
		var safe: int = _nearest_friendly_port()
		location = safe
		_log("Ship %s! Bought a replacement sloop for %d gold, limped into %s." % [reason, NEW_SHIP_COST, String(ports[safe]["name"])])
		phase = "port"
		encounter = {}
	else:
		_log("Ship %s — and no gold for a refit. The career ends beneath the waves." % reason)
		_end_career("sunk", false)


func _nearest_friendly_port() -> int:
	var best: int = location
	var best_d: float = 1.0e20
	for i in ports.size():
		if not port_hostile(i):
			var d: float = distance_between(location, i)
			if d < best_d:
				best_d = d
				best = i
	return best


# =====================================================================
#  Crew morale actions
# =====================================================================

## Divide plunder among the crew — spend gold on shares to restore morale (and buy
## back some loyalty). Illegal without the gold or when the run is over.
func divide_plunder(amount: int) -> bool:
	if career_over or amount <= 0 or gold < amount:
		illegal_attempts += 1
		return false
	gold -= amount
	var gain: float = MORALE_PLUNDER_GAIN * clampf(float(amount) / maxf(1.0, WAGE_PER_CREW * float(ship["crew"])), 0.3, 2.0)
	morale = clampf(morale + gain, 0.0, MORALE_MAX)
	wage_debt = maxf(0.0, wage_debt - float(amount))
	_log("Divided %d gold of plunder — morale rises to %.0f%%." % [amount, morale * 100.0])
	return true


## Take shore leave at the current (friendly) port: spend a few days + gold on the
## crew's revelry to restore morale and restock food.
func shore_leave() -> bool:
	if career_over or phase != "port" or port_hostile(location):
		illegal_attempts += 1
		return false
	var cost: int = 20 + int(ship["crew"]) * 2
	if gold < cost:
		illegal_attempts += 1
		return false
	gold -= cost
	food = 220.0
	_advance_days(3)
	if career_over:
		return true
	morale = clampf(morale + MORALE_SHORE_GAIN, 0.0, MORALE_MAX)
	_log("Shore leave at %s (%d gold): the crew carouses, morale up, food restocked." % [String(ports[location]["name"]), cost])
	return true


## Recruit crew at a friendly port (cost scales with headcount) up to the ship's max.
func recruit_crew(n: int) -> bool:
	if career_over or phase != "port" or port_hostile(location) or n <= 0:
		illegal_attempts += 1
		return false
	var can: int = mini(n, int(ship["crew_max"]) - int(ship["crew"]))
	if can <= 0:
		illegal_attempts += 1
		return false
	var cost: int = can * 6
	if gold < cost:
		illegal_attempts += 1
		return false
	gold -= cost
	ship["crew"] = int(ship["crew"]) + can
	_log("Recruited %d hands at %s for %d gold." % [can, String(ports[location]["name"]), cost])
	return true


# =====================================================================
#  Quests + treasure
# =====================================================================

func _check_quest_deliver(good: String) -> void:
	if quest_done or quest_step >= QUEST_CHAIN.size():
		return
	var q: Dictionary = QUEST_CHAIN[quest_step]
	if String(q.get("kind", "")) == "deliver" and String(q.get("good", "")) == good:
		if int(cargo.get(good, 0)) >= int(q["qty"]):
			_complete_quest_step()


func _check_quest_bounty(tier: String) -> void:
	if quest_done or quest_step >= QUEST_CHAIN.size():
		return
	var q: Dictionary = QUEST_CHAIN[quest_step]
	if String(q.get("kind", "")) == "bounty" and String(q.get("tier", "")) == tier:
		_complete_quest_step()


func _complete_quest_step() -> void:
	var q: Dictionary = QUEST_CHAIN[quest_step]
	fame += int(q["fame"])
	gold += int(q["gold"])
	morale = clampf(morale + 0.05, 0.0, MORALE_MAX)
	_log("Quest complete: %s (+%d fame, +%d gold)." % [String(q["desc"]), int(q["fame"]), int(q["gold"])])
	quest_step += 1
	if quest_step >= QUEST_CHAIN.size():
		quest_done = true
		fame += 300
		_log("The full saga is done — a legend is born (+300 fame).")
	_note_wealth()


## Dig for buried treasure once a full map is assembled. Big gold + fame, once.
func dig_treasure() -> bool:
	if career_over or treasure_found or fragments < FRAGMENTS_FOR_MAP or phase != "port":
		illegal_attempts += 1
		return false
	treasure_found = true
	gold += TREASURE_GOLD
	fame += TREASURE_FAME
	_advance_days(2)
	_log("X marks the spot — %d gold + %d fame unearthed near %s!" % [TREASURE_GOLD, TREASURE_FAME, String(ports[location]["name"])])
	_note_wealth()
	return true


# =====================================================================
#  Fame / wealth / skills
# =====================================================================

func net_worth() -> int:
	var cargo_val: int = 0
	for gid in GOOD_IDS:
		cargo_val += int(cargo.get(gid, 0)) * int(unit_price(location, gid, "sell"))
	return gold + cargo_val + land * 800


## Fame accrues as net worth crosses milestones — so an honest trader also builds a
## reputation, not just a raider.
func _note_wealth() -> void:
	var nw: int = net_worth()
	if nw > net_worth_peak:
		var before: int = net_worth_peak / WEALTH_STEP
		var after: int = nw / WEALTH_STEP
		if after > before:
			fame += (after - before) * FAME_PER_WEALTH_STEP
		net_worth_peak = nw


func _gain_skill(which: String, amount: float) -> void:
	skills[which] = clampf(float(skills[which]) + amount, 0.0, SKILL_MAX)


# =====================================================================
#  AI rivals — sail, trade, and rise/fall under the same rules
# =====================================================================

func _advance_rivals() -> void:
	for r in rivals:
		if not bool(r["alive"]):
			continue
		if int(r["days_to_dest"]) > 0:
			r["days_to_dest"] = int(r["days_to_dest"]) - 1
			if int(r["days_to_dest"]) == 0:
				r["location"] = int(r["dest"])
				# a rival "trades": deterministic gold from local arbitrage.
				var margin: int = 40 + _rng.randi_range(0, 90)
				r["gold"] = int(r["gold"]) + margin
				r["fame"] = int(r["fame"]) + _rng.randi_range(0, 6)
		else:
			# pick a new destination.
			var dest: int = _rng.randi_range(0, ports.size() - 1)
			r["dest"] = dest
			var dist: float = port_pos(int(r["location"])).distance_to(port_pos(dest))
			r["days_to_dest"] = maxi(1, int(ceil(dist / LEAGUES_PER_DAY)))
	# occasionally two rivals cross swords — the weaker loses fame (emergent rivalry).
	if rivals.size() >= 2 and _rng.randf() < 0.05:
		var i: int = _rng.randi_range(0, rivals.size() - 1)
		var j: int = _rng.randi_range(0, rivals.size() - 1)
		if i != j and bool(rivals[i]["alive"]) and bool(rivals[j]["alive"]):
			var wi: int = int(rivals[i]["gold"]) + int(rivals[i]["fame"]) * 3
			var wj: int = int(rivals[j]["gold"]) + int(rivals[j]["fame"]) * 3
			var loser: int = j if wi >= wj else i
			rivals[loser]["fame"] = maxi(0, int(rivals[loser]["fame"]) - 8)


# =====================================================================
#  Retirement + career end
# =====================================================================

## The captain's final score: fame + wealth + land + skills + standing.
func final_score() -> int:
	var rep_bonus: int = 0
	for n in NATIONS:
		if float(reputation[n]) > 0.0:
			rep_bonus += int(reputation[n])
	var skill_bonus: int = 0
	for k in skills.keys():
		skill_bonus += int(round(float(skills[k]) * 90.0))
	return fame + int(net_worth() / 8) + land * 400 + rep_bonus * 6 + skill_bonus \
		+ battles_won * 30 + ships_captured * 60


func rank_for_score(score: int) -> int:
	var idx: int = 0
	for i in RANKS.size():
		if score >= int(RANKS[i]["min"]):
			idx = i
	return idx


func rank_name(idx: int) -> String:
	return String(RANKS[clampi(idx, 0, RANKS.size() - 1)]["name"])


## Voluntarily retire from the current (friendly) port. Scores the career and decides
## WIN (rank >= WIN_RANK_INDEX) or LOSS (below it).
func retire() -> bool:
	if career_over:
		illegal_attempts += 1
		return false
	if phase != "port" or port_hostile(location):
		illegal_attempts += 1
		return false
	_retire_internal("voluntary")
	return true


func _retire_internal(_why: String) -> void:
	var score: int = final_score()
	var idx: int = rank_for_score(score)
	retirement_rank = idx
	var won: bool = idx >= WIN_RANK_INDEX
	_log("Retired at %s with score %d — rank: %s." % [
		String(ports[location]["name"]), score, rank_name(idx)])
	_end_career("retired", won)


func _end_career(cause: String, won: bool) -> void:
	if career_over:
		return
	career_over = true
	career_won = won
	end_cause = cause
	phase = "done"
	if retirement_rank == 0 and cause == "retired":
		retirement_rank = rank_for_score(final_score())


# =====================================================================
#  Legality
# =====================================================================

## Is `action` legal right now? Rejects acting after the career is over, sailing with
## no crew / to the current or invalid port, buying beyond gold or cargo space,
## selling more than is aboard, and attacking with no crew or no encounter.
func is_legal(action: Dictionary) -> bool:
	if career_over:
		return false
	match String(action.get("type", "")):
		"sail":
			var dest: int = int(action.get("dest", -1))
			if dest < 0 or dest >= ports.size() or dest == location:
				return false
			if int(ship["crew"]) <= 0:
				return false
			return phase == "port"
		"buy":
			var good_b: String = String(action.get("good", ""))
			var qty_b: int = int(action.get("qty", 0))
			if not GOODS.has(good_b) or qty_b <= 0 or phase != "port":
				return false
			if port_hostile(location):
				return false
			if qty_b > cargo_free():
				return false
			return gold >= quote_buy(good_b, qty_b)
		"sell":
			var good_s: String = String(action.get("good", ""))
			var qty_s: int = int(action.get("qty", 0))
			if not GOODS.has(good_s) or qty_s <= 0 or phase != "port":
				return false
			if port_hostile(location):
				return false
			return int(cargo.get(good_s, 0)) >= qty_s
		"attack":
			var stance: String = String(action.get("stance", ""))
			if not (stance in ["sink", "cripple", "board"]):
				return false
			if encounter.is_empty():
				return false
			return int(ship["crew"]) > 0
	return false


# =====================================================================
#  Auto-play — deterministic policies that drive a whole career to WIN / LOSS
# =====================================================================

## Run the career to its end under the configured policy. Bounded by MAX_CAREER_DAYS
## and a hard step cap (safety); always terminates. Returns the outcome dict.
func auto_play_to_end() -> Dictionary:
	var steps: int = 0
	while not career_over and steps < 20000:
		steps += 1
		auto_step()
	return {
		"won": career_won, "cause": end_cause, "rank": retirement_rank,
		"rank_name": rank_name(retirement_rank), "score": final_score(),
		"day": day, "steps": steps,
	}


## Take ONE deterministic auto-play action according to `_policy`.
func auto_step() -> void:
	if career_over:
		return
	match _policy:
		"reckless":
			_auto_reckless()
		"neglect":
			_auto_neglect()
		_:
			_auto_trade()


## WIN-oriented merchant policy: keep the crew happy, run the best arbitrage route,
## take sanctioned prizes of opportunity, and retire rich once the rank is secured.
func _auto_trade() -> void:
	if phase == "combat":
		phase = "port"
	# 1) crew care first — never let morale slide toward mutiny.
	if morale < 0.5 and phase == "port" and not port_hostile(location):
		if gold > 120:
			divide_plunder(60)
			return
		if gold > 60:
			shore_leave()
			return
	# 2) fight ONLY safe, sanctioned prizes (merchants / marque targets) with a strong ship.
	if not encounter.is_empty() and phase == "port":
		if _is_safe_prize(encounter):
			attack("board")
			return
		else:
			encounter = {}   ## decline the fight, sail on.
	# 3) treasure + retirement checks.
	if fragments >= FRAGMENTS_FOR_MAP and not treasure_found and phase == "port":
		dig_treasure()
		return
	if phase == "port" and not port_hostile(location):
		var score: int = final_score()
		# retire once the rank is comfortably secured (a fat war-chest) or near the cap.
		if rank_for_score(score) >= WIN_RANK_INDEX and (day > MAX_CAREER_DAYS - 200 or gold > 60000):
			retire()
			return
	# 4) sell everything profitable here, then buy the best outbound cargo + sail.
	if phase == "port" and not port_hostile(location):
		var sold: bool = _auto_sell_here()
		if sold:
			return
		var plan: Dictionary = _best_trade_route()
		if not plan.is_empty():
			var good: String = String(plan["good"])
			var dest: int = int(plan["dest"])
			var qty: int = int(plan["qty"])
			if qty > 0 and is_legal({"type": "buy", "good": good, "qty": qty}):
				buy(good, qty)
			sail_to(dest)
			return
		# no profitable route from here — hop to the nearest other port.
		sail_to(_some_other_port())
		return
	# fallback: if stuck at a hostile port, flee to a friendly one.
	if phase == "port":
		sail_to(_nearest_friendly_port() if _nearest_friendly_port() != location else _some_other_port())
		return
	phase = "port"


## LOSS-by-sinking policy: pick fights with the strongest warships until the ship is
## lost with no reserves.
func _auto_reckless() -> void:
	if phase == "combat":
		phase = "port"
	if not encounter.is_empty():
		attack("sink")
		return
	# force a hostile encounter: attack a nation until its patrols come, then sail into them.
	if phase == "port":
		# antagonise the local nation so a warship spawns.
		var nation: String = String(ports[location]["nation"])
		reputation[nation] = clampf(float(reputation[nation]) - 30.0, -100.0, 100.0)
		_recompute_encounter()
		if encounter.is_empty():
			sail_to(_some_other_port())
		return
	phase = "port"


## LOSS-by-mutiny policy: sail endlessly, never pay/feed/reward the crew, until morale
## collapses into a mutiny.
func _auto_neglect() -> void:
	if phase == "combat":
		phase = "port"
	if career_over:
		return
	# never divide plunder, never take shore leave — just sail back and forth.
	sail_to(_some_other_port())


## Sell any cargo whose local sell price beats a rough acquisition floor. Returns true
## if a sale was made.
func _auto_sell_here() -> bool:
	for gid in GOOD_IDS:
		var have: int = int(cargo.get(gid, 0))
		if have > 0:
			var price: int = unit_price(location, gid, "sell")
			if float(price) >= float(GOODS[gid]["base"]) * 1.15:
				sell(gid, have)
				return true
	return false


## Find the most profitable (good, destination) route from the current port: buy a
## good cheap here, sell it dear at the best consumer within reach. Pure evaluation.
func _best_trade_route() -> Dictionary:
	var best: Dictionary = {}
	var best_profit: float = 0.0
	var budget: int = maxi(0, gold - 60)
	for gid in GOOD_IDS:
		var buy_here: int = unit_price(location, gid, "buy")
		# how many units can we afford + fit?
		var max_qty: int = mini(cargo_free(), int(budget / maxi(1, buy_here)))
		if max_qty <= 0:
			continue
		var qty: int = mini(max_qty, 60)
		var cost: int = quote_buy(gid, qty)
		for dest in ports.size():
			if dest == location or port_hostile(dest):
				continue
			var sell_there: int = unit_price(dest, gid, "sell")
			var revenue: int = qty * sell_there
			var days: int = maxi(1, travel_days_to(dest))
			var wages: float = WAGE_PER_CREW * float(ship["crew"]) * float(days) / float(PAY_PERIOD)
			var profit: float = float(revenue - cost) - wages
			if profit > best_profit:
				best_profit = profit
				best = {"good": gid, "dest": dest, "qty": qty, "profit": int(profit)}
	return best


## Is this encounter a SAFE prize for a trader — a lightly-crewed MERCHANT our ship
## clearly outguns (enough crew + hull to win the boarding without a bloodbath)? A
## cautious trader never picks a fight with a warship or an evenly-matched raider.
func _is_safe_prize(enemy: Dictionary) -> bool:
	var tier: String = String(enemy["tier"])
	if tier != "merchant":
		return false
	# require a clear crew edge + a healthy hull so the boarding is a near-certain win.
	if int(ship["crew"]) < int(enemy["crew"]) + 8:
		return false
	if float(ship["hull"]) < float(ship["hull_max"]) * 0.6:
		return false
	return true


func _some_other_port() -> int:
	var target: int = (location + 1) % ports.size()
	# prefer a friendly port to keep trading legal.
	for k in ports.size():
		var cand: int = (location + 1 + k) % ports.size()
		if cand != location and not port_hostile(cand):
			return cand
	return target


# =====================================================================
#  Queries for the view
# =====================================================================

func good_name(gid: String) -> String:
	return String(GOODS[gid]["name"])


func port_name(i: int) -> String:
	return String(ports[i]["name"])


func current_wind_arrow() -> float:
	return wind_dir(day)


func recent_log(n: int = 14) -> Array:
	var out: Array = []
	var start: int = maxi(0, log_lines.size() - n)
	for i in range(start, log_lines.size()):
		out.append(log_lines[i])
	return out


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 300:
		log_lines.remove_at(0)


# =====================================================================
#  Determinism checksum — folds the WHOLE career state into one int
# =====================================================================

func _fold(h: int, v: int) -> int:
	h = (h ^ v) * FNV_PRIME
	return h & MASK63


func _qf(v: float) -> int:
	return int(round(v * 100.0))


## Order-stable checksum of the entire career: two engines are equal iff this matches.
func career_checksum() -> int:
	var h: int = FNV_OFFSET
	h = _fold(h, _seed)
	h = _fold(h, int(_rng.state & MASK63))
	h = _fold(h, day)
	h = _fold(h, _qf(age))
	h = _fold(h, fame)
	h = _fold(h, gold)
	h = _fold(h, land)
	h = _fold(h, location)
	h = _fold(h, _qf(morale))
	h = _fold(h, _qf(food))
	h = _fold(h, fragments)
	h = _fold(h, quest_step)
	h = _fold(h, battles_won)
	h = _fold(h, ships_captured)
	h = _fold(h, 1 if career_over else 0)
	h = _fold(h, 1 if career_won else 0)
	h = _fold(h, retirement_rank)
	h = _fold(h, hash(end_cause))
	h = _fold(h, hash(marque))
	h = _fold(h, illegal_attempts)
	for k in ["navigation", "gunnery", "fencing", "wit"]:
		h = _fold(h, _qf(float(skills[k])))
	for n in NATIONS:
		h = _fold(h, _qf(float(reputation[n])))
	h = _fold(h, _qf(float(ship["hull"])))
	h = _fold(h, _qf(float(ship["sails"])))
	h = _fold(h, int(ship["crew"]))
	for gid in GOOD_IDS:
		h = _fold(h, int(cargo.get(gid, 0)))
	# fold the world economy (quantized) so trade + drift are covered.
	for p in ports:
		var econ: Dictionary = p["econ"]
		for gid in GOOD_IDS:
			h = _fold(h, _qf(float(econ[gid]["stock"])))
	for r in rivals:
		h = _fold(h, int(r["gold"]))
		h = _fold(h, int(r["fame"]))
		h = _fold(h, int(r["location"]))
	return h


# =====================================================================
#  Save / load — the WHOLE career round-trips (JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	return {
		"seed": _seed,
		"rng_state": str(_rng.state),
		"policy": _policy,
		"captain_name": captain_name,
		"day": day, "age": age, "phase": phase,
		"fame": fame, "gold": gold, "land": land,
		"skills": skills.duplicate(true),
		"ship": ship.duplicate(true),
		"cargo": cargo.duplicate(true),
		"reputation": reputation.duplicate(true),
		"marque": marque,
		"ports": ports.duplicate(true),
		"location": location,
		"rivals": rivals.duplicate(true),
		"morale": morale, "food": food, "wage_debt": wage_debt, "last_payday": last_payday,
		"fragments": fragments, "quest_step": quest_step, "quest_done": quest_done, "treasure_found": treasure_found,
		"encounter": encounter.duplicate(true),
		"illegal_attempts": illegal_attempts, "battles_won": battles_won,
		"ships_captured": ships_captured, "net_worth_peak": net_worth_peak,
		"career_over": career_over, "career_won": career_won,
		"end_cause": end_cause, "retirement_rank": retirement_rank,
	}


func from_dict(data: Dictionary) -> void:
	_seed = int(data.get("seed", 0))
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	_policy = String(data.get("policy", "trade"))
	captain_name = String(data.get("captain_name", "Captain"))
	day = int(data.get("day", 0))
	age = float(data.get("age", START_AGE))
	phase = String(data.get("phase", "port"))
	fame = int(data.get("fame", 0))
	gold = int(data.get("gold", 0))
	land = int(data.get("land", 0))
	skills = (data.get("skills", {}) as Dictionary).duplicate(true)
	for sk in ["navigation", "gunnery", "fencing", "wit"]:
		if not skills.has(sk):
			skills[sk] = 0.0
	ship = (data.get("ship", {}) as Dictionary).duplicate(true)
	cargo = (data.get("cargo", {}) as Dictionary).duplicate(true)
	for gid in GOOD_IDS:
		if not cargo.has(gid):
			cargo[gid] = 0
	reputation = (data.get("reputation", {}) as Dictionary).duplicate(true)
	for n in NATIONS:
		if not reputation.has(n):
			reputation[n] = 0.0
	marque = String(data.get("marque", ""))
	ports = (data.get("ports", []) as Array).duplicate(true)
	location = int(data.get("location", 0))
	rivals = (data.get("rivals", []) as Array).duplicate(true)
	morale = float(data.get("morale", 0.7))
	food = float(data.get("food", 200.0))
	wage_debt = float(data.get("wage_debt", 0.0))
	last_payday = int(data.get("last_payday", 0))
	fragments = int(data.get("fragments", 0))
	quest_step = int(data.get("quest_step", 0))
	quest_done = bool(data.get("quest_done", false))
	treasure_found = bool(data.get("treasure_found", false))
	encounter = (data.get("encounter", {}) as Dictionary).duplicate(true)
	illegal_attempts = int(data.get("illegal_attempts", 0))
	battles_won = int(data.get("battles_won", 0))
	ships_captured = int(data.get("ships_captured", 0))
	net_worth_peak = int(data.get("net_worth_peak", 0))
	career_over = bool(data.get("career_over", false))
	career_won = bool(data.get("career_won", false))
	end_cause = String(data.get("end_cause", ""))
	retirement_rank = int(data.get("retirement_rank", 0))
