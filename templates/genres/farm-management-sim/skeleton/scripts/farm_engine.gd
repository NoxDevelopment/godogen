extends RefCounted
class_name FarmEngine
## res://scripts/farm_engine.gd
## THE PURE ENGINE — a deterministic, seedable FARM-OPERATION management sim (a deeper
## redo of Maxis's SIMFARM). You run a whole farm BUSINESS from a top-down desk, not a
## single hoe-and-watering-can plot: a GRID OF NINE FIELDS each with its own SOIL QUALITY
## and NITROGEN level; SIX CROPS (corn / wheat / soybeans / cotton / hay / vegetables)
## each with a growth duration, water need, plantable seasons, a nitrogen DRAW (or, for
## the soybean legume, a nitrogen FIX), a seed cost and a yield curve; deterministic
## WEATHER + four SEASONS (rain / drought / frost / heat / pests) that modulate growth and
## can damage a crop, with IRRIGATION to buy your way out of a drought; THREE LIVESTOCK
## herds (cattle / pigs / chickens) that eat feed, produce milk / eggs / meat, breed and
## die; a COMMODITY MARKET whose per-commodity prices drift over time on a deterministic
## multi-frequency wave (so WHEN you sell matters); MACHINERY (tractors / harvesters) that
## raise field throughput and harvest efficiency at a purchase + maintenance + depreciation
## cost; and a cash-flow ECONOMY with strict INTEGER MONEY CONSERVATION.
##
## THE THREE THINGS THAT MAKE THIS DISTINCT FROM ITS SIBLINGS (dept-store-sim / mall-tycoon):
##
##  1) SOIL + CROP ROTATION as a real per-field NITROGEN BALANCE. A field's yield is a
##     function of its soil nitrogen at harvest; harvesting a heavy-feeder crop DRAWS
##     nitrogen down, so replanting the same nutrient-draining crop (a MONOCULTURE)
##     measurably DEPLETES the field and its yields DECLINE. Rotating in a nitrogen-FIXING
##     legume (soybeans), applying FERTILIZER, or letting a field recover REPLENISHES the
##     nitrogen and yields hold or recover. This is not a cosmetic stat — a probe proves a
##     monoculture field's yield falls below a rotated/fertilized field's under identical
##     weather.
##
##  2) DETERMINISTIC WEATHER as a PURE HASH of (seed, day) — independent of the RNG stream
##     the livestock draw from. weather_for_day(d) is a pure function, so a season's
##     drought / frost / heat / pest events are reproducible and TESTABLE, and IRRIGATION
##     provably lifts a drought-struck field's yield.
##
##  3) A COMMODITY MARKET as a real COMPUTED price curve (not a table): each commodity's
##     price is base × a sum of sine waves with seed-derived phases, so a commodity's
##     price genuinely VARIES over the year and sell-timing changes revenue.
##
## Everything — weather, crop growth, livestock feeding/breeding/mortality, market prices,
## the auto-play heuristic, win/loss — is a pure function of (state, day, seeded RNG). The
## same seed + the same scripted actions always yield a BYTE-IDENTICAL farm after N days.
## No Godot node dependency: this class is fully headless-testable. GameManager owns one
## instance and adds the autoload ABI + save; farm.gd only reads state + forwards actions.
##
## MONEY DISCIPLINE (why conservation holds): every mutation of `cash` goes through
## _apply_cash(delta, category) which also folds delta into _cat_totals. The invariant
## cash == _start_cash + sum(_cat_totals.values()) holds at all times — no code path may
## touch `cash` directly. All money is INTEGER dollars, so replays and save round-trips are
## exact; nitrogen / soil / health / market multipliers are floats (they never touch cash).

# =====================================================================
#  Determinism helpers (FNV-1a, 63-bit masked)
# =====================================================================
const FNV_OFFSET: int = 1469598103934665603
const FNV_PRIME: int = 1099511628211
const MASK63: int = 0x7FFFFFFFFFFFFFFF

# =====================================================================
#  Outcome
# =====================================================================
const ONGOING: int = 0
const WON: int = 1
const LOST: int = 2

# =====================================================================
#  Calendar
# =====================================================================
const MONTH_DAYS: int = 30
const SEASON_DAYS: int = 90
const YEAR_DAYS: int = 360   ## twelve 30-day months == four 90-day seasons — clean wrap.
const S_SPRING: int = 0
const S_SUMMER: int = 1
const S_FALL: int = 2
const S_WINTER: int = 3
const SEASON_NAME: PackedStringArray = ["Spring", "Summer", "Fall", "Winter"]

# =====================================================================
#  Fields (a 3x3 grid == 9 fields)
# =====================================================================
const FIELD_COLS: int = 3
const FIELD_ROWS: int = 3
const FIELD_COUNT: int = 9
const NITROGEN_START: float = 60.0
const NITROGEN_OPTIMAL: float = 60.0   ## nitrogen at/above this == full nutrient factor.
const NITROGEN_MAX: float = 120.0
const NUTRIENT_FLOOR: float = 0.25     ## a fully depleted field still yields this fraction.
## Per-field base soil quality (fertility multiplier). A fixed spread across the grid so
## some fields are naturally better; setup adds a small seeded jitter.
const FIELD_SOIL_BASE: PackedFloat32Array = [
	0.95, 0.85, 0.75,
	0.80, 1.00, 0.70,
	0.72, 0.88, 0.92,
]
const LAND_VALUE_EACH: int = 8000   ## fixed land asset per field (net-worth component).

# =====================================================================
#  Crops (6). Reference data as hardcoded constants — index i == crop id.
# =====================================================================
const CROP_NAME: PackedStringArray = ["Corn", "Wheat", "Soybeans", "Cotton", "Hay", "Vegetables"]
const CR_CORN: int = 0
const CR_WHEAT: int = 1
const CR_SOY: int = 2
const CR_COTTON: int = 3
const CR_HAY: int = 4
const CR_VEG: int = 5
const CROP_COUNT: int = 6

const CROP_DURATION: PackedInt32Array = [90, 100, 80, 110, 60, 70]   ## days seed→harvest.
const CROP_WATER_NEED: PackedFloat32Array = [0.90, 0.60, 0.60, 0.80, 0.40, 1.00]
## Nitrogen change AT HARVEST: positive == drawn down (heavy feeder), negative == FIXED
## (the soybean legume enriches the soil). Corn / cotton / vegetables are heavy feeders.
const CROP_NUTRIENT_DRAW: PackedFloat32Array = [26.0, 16.0, -30.0, 24.0, 8.0, 20.0]
const CROP_SEED_COST: PackedInt32Array = [400, 300, 350, 500, 150, 450]   ## per field planting.
const CROP_BASE_YIELD: PackedInt32Array = [520, 430, 360, 300, 700, 460]  ## units at ideal.
## Which market commodity a crop sells as (hay is special — it stocks FEED, never sold).
const CROP_COMMODITY: PackedInt32Array = [0, 0, 0, 1, 6, 2]   ## GRAIN,GRAIN,GRAIN,FIBER,FEED,PRODUCE
## Growth-suitability wrapped-Gaussian centre (day-of-year) + width — how well the crop
## grows through the calendar (folded into daily condition, NOT the plant-season gate).
const CROP_SUIT_CENTER: PackedFloat32Array = [140.0, 95.0, 150.0, 165.0, 120.0, 90.0]
const CROP_SUIT_WIDTH: PackedFloat32Array = [70.0, 95.0, 70.0, 60.0, 100.0, 60.0]
const SUIT_FLOOR: float = 0.35
## Plantable-season bitmask (bit s set == crop may be planted in season s). The plant-time
## legality gate; growth suitability above is a separate continuous quality term.
const CROP_PLANT_SEASONS: PackedInt32Array = [
	1,                          # Corn: spring
	(1 << 0) | (1 << 2),        # Wheat: spring + fall
	(1 << 0) | (1 << 1),        # Soybeans: spring + summer
	1,                          # Cotton: spring
	(1 << 0) | (1 << 1),        # Hay: spring + summer
	(1 << 0) | (1 << 1),        # Vegetables: spring + summer
]
## Frost sensitivity: warm-season crops are damaged by a frost event; wheat/hay shrug it off.
const CROP_FROST_SENSITIVE: PackedInt32Array = [1, 0, 1, 1, 0, 1]

# =====================================================================
#  Commodity market (7). Reference data as constants — index c == commodity id.
# =====================================================================
const COMMODITY_NAME: PackedStringArray = ["Grain", "Fiber", "Produce", "Milk", "Eggs", "Meat", "Feed"]
const C_GRAIN: int = 0
const C_FIBER: int = 1
const C_PRODUCE: int = 2
const C_MILK: int = 3
const C_EGGS: int = 4
const C_MEAT: int = 5
const C_FEED: int = 6
const COMMODITY_COUNT: int = 7
const COMMODITY_BASE_PRICE: PackedInt32Array = [13, 22, 17, 9, 4, 14, 3]
## Which ledger category a commodity's SALE books under (crop products vs animal products).
const COMMODITY_IS_LIVESTOCK: PackedInt32Array = [0, 0, 0, 1, 1, 1, 0]
## Multi-frequency price-wave parameters shared across commodities: [period_days, amplitude].
## Phases are derived per-commodity from the seed so each commodity peaks on its own schedule.
const PRICE_WAVES: Array = [
	[90.0, 0.24],
	[45.0, 0.12],
	[180.0, 0.18],
]
const PRICE_FLOOR_FRAC: float = 0.35   ## price never drops below this fraction of base.

# =====================================================================
#  Livestock (3). Reference data as constants — index a == animal id.
# =====================================================================
const ANIMAL_NAME: PackedStringArray = ["Cattle", "Pigs", "Chickens"]
const A_CATTLE: int = 0
const A_PIGS: int = 1
const A_CHICKENS: int = 2
const ANIMAL_COUNT: int = 3
const ANIMAL_FEED_PER_DAY: PackedInt32Array = [3, 2, 1]      ## feed units per head per day.
const ANIMAL_PRODUCT: PackedInt32Array = [3, 5, 4]           ## MILK, MEAT, EGGS commodity.
const ANIMAL_PRODUCT_PER_DAY: PackedInt32Array = [2, 1, 1]   ## product units per fed head per day.
const ANIMAL_BUY_COST: PackedInt32Array = [1200, 400, 40]    ## $ per head to purchase.
const ANIMAL_SELL_VALUE: PackedInt32Array = [700, 260, 22]   ## $ per head when sold/culled.
const ANIMAL_CAP: PackedInt32Array = [40, 60, 200]           ## herd cap per type.
const ANIMAL_BREED_PERIOD: PackedInt32Array = [40, 28, 14]   ## days between breeding events.
const ANIMAL_MORTALITY_BP: PackedInt32Array = [4, 6, 10]     ## base daily mortality, basis points.
const ANIMAL_ASSET_VALUE: PackedInt32Array = [700, 260, 22]  ## net-worth value per head.

# =====================================================================
#  Machinery (2). Reference data as constants — index m == machine type.
# =====================================================================
const MACHINE_NAME: PackedStringArray = ["Tractor", "Harvester"]
const M_TRACTOR: int = 0
const M_HARVESTER: int = 1
const MACHINE_TYPE_COUNT: int = 2
const MACHINE_COST: PackedInt32Array = [15000, 22000]
const MACHINE_MAINT: PackedInt32Array = [14, 20]            ## $ per day per machine.
const MACHINE_DEP_BP: PackedInt32Array = [12, 10]           ## daily depreciation, basis points of cost.
const MACHINE_SALVAGE_FRAC: float = 0.25                    ## value floors at this fraction of cost.
const WORK_PER_TRACTOR: int = 3                             ## extra fields worked/day per tractor.
const WORK_PER_HARVESTER: int = 1
const HARVEST_EFF_PER_HARVESTER: float = 0.10              ## harvest-efficiency lift per harvester.

# =====================================================================
#  Weather
# =====================================================================
const W_NORMAL: int = 0
const W_RAIN: int = 1
const W_DROUGHT: int = 2
const W_FROST: int = 3
const W_HEAT: int = 4
const W_PESTS: int = 5
const WEATHER_NAME: PackedStringArray = ["Clear", "Rain", "Drought", "Frost", "Heat", "Pests"]
const BASE_MOISTURE: float = 0.85
const IRRIGATION_WATER: float = 0.65
const BASE_HARVEST_EFF: float = 0.80

# =====================================================================
#  Default tuning (auditable; overridable via a config dict in setup)
# =====================================================================
const DEFAULTS: Dictionary = {
	"policy": "balanced",           ## auto-play flavour: "balanced" | "aggressive"
	"start_cash": 34000,
	"initial_debt": 0,
	"growth_goal": 55000,           ## WIN = starting net worth + this
	"max_years": 4,                 ## hard cap in YEARS — guarantees termination
	"overhead": 45,                 ## $ per day property tax / mortgage overhead
	"base_wage": 60,                ## $ per day base hired-hand labour bill
	"wage_per_field": 8,            ## added labour $ per planted field per day
	"labor_saving_per_machine": 14, ## each machine trims the daily labour bill by this
	"min_wage": 30,                 ## labour bill never falls below this
	"base_work": 4,                 ## fields plantable/harvestable per day by hand
	"fertilizer_cost": 620,         ## $ to fertilize one field
	"fertilizer_amount": 34.0,      ## nitrogen added by one fertilizer application
	"irrigation_cost": 22,          ## $ per day per irrigated planted field
	"feed_buy_batch": 200,          ## default feed units bought per buy_feed()
	"interest_bp": 90,              ## monthly loan interest, basis points
	"max_debt": 45000,
	"bankruptcy_floor": -9000,      ## cash below this…
	"bankruptcy_patience": 45,      ## …for this many consecutive days => LOSE
	"weather_override": -1,         ## -1 == computed weather; >=0 forces a weather type
	"stock_asset_frac_num": 1,      ## harvested-stock net-worth value == base price * num/den
	"stock_asset_frac_den": 1,
}

# =====================================================================
#  Tuning (resolved from DEFAULTS + config in setup)
# =====================================================================
var _policy: String = "balanced"
var growth_goal: int = 55000
var max_days: int = 1440
var overhead: int = 90
var base_wage: int = 130
var wage_per_field: int = 12
var labor_saving_per_machine: int = 22
var min_wage: int = 40
var base_work: int = 4
var fertilizer_cost: int = 620
var fertilizer_amount: float = 34.0
var irrigation_cost: int = 22
var feed_buy_batch: int = 200
var interest_bp: int = 90
var max_debt: int = 45000
var bankruptcy_floor: int = -9000
var bankruptcy_patience: int = 45
var weather_override: int = -1
var stock_asset_frac_num: int = 1
var stock_asset_frac_den: int = 1

# =====================================================================
#  State
# =====================================================================
var day: int = 0
var outcome: int = ONGOING
var cash: int = 0
var debt: int = 0
var bankruptcy_days: int = 0
var win_target: int = 0
var illegal_attempts: int = 0
var work_used: int = 0                 ## fields worked so far TODAY (reset each tick).

# Per-day telemetry (info + probes; folded into no ledger).
var last_income: int = 0
var last_weather: int = W_NORMAL
var last_harvest_units: int = 0
var last_harvest_field: int = -1
var last_livestock_product: int = 0
var last_livestock_deaths: int = 0
var last_livestock_births: int = 0
var last_feed_consumed: int = 0
var total_harvests: int = 0

var _seed: int = 0
var _start_cash: int = 0

# Per-field state.
var _soil: PackedFloat32Array = PackedFloat32Array()        ## soil-quality multiplier per field.
var _nitrogen: PackedFloat32Array = PackedFloat32Array()    ## soil nitrogen (0..NITROGEN_MAX).
var _crop: PackedInt32Array = PackedInt32Array()            ## crop id growing, or -1 fallow.
var _growth: PackedInt32Array = PackedInt32Array()          ## days grown (capped at duration).
var _health_sum: PackedFloat32Array = PackedFloat32Array()  ## accumulated daily condition.
var _irrigated: PackedInt32Array = PackedInt32Array()       ## 1 == field irrigation active.
var _last_crop: PackedInt32Array = PackedInt32Array()       ## last crop harvested here (rotation memory).

# Livestock.
var _herd: PackedInt32Array = PackedInt32Array()            ## head count per animal type.
var _feed_stock: int = 0                                    ## feed units on hand (hay + bought).

# Harvested / produced goods, per commodity.
var _product_stock: PackedInt32Array = PackedInt32Array()

# Machinery — parallel arrays, order-stable (index == machine instance).
var _mach_type: PackedInt32Array = PackedInt32Array()
var _mach_value: PackedInt32Array = PackedInt32Array()

# Money ledger — every cash delta folded by category.
var _cat_totals: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Every ledger category the engine may ever book to (for the "no undefined flow" probe).
const LEDGER_CATEGORIES: PackedStringArray = [
	"seed_capital", "crop_sales", "livestock_sales", "seed_purchase", "feed_purchase",
	"fertilizer", "irrigation", "machinery_purchase", "maintenance", "wages", "overhead",
	"livestock_purchase", "livestock_salvage", "interest", "loan_draw", "loan_repay",
]


# =====================================================================
#  Lifecycle
# =====================================================================

## Build a fresh farm. seed == 0 → randomised; any other value is deterministic.
## `config` overrides any DEFAULTS key (used to make win-friendly / harsh runs, or to
## force a weather type / disable weather variance for a controlled probe).
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	var cfg: Dictionary = DEFAULTS.duplicate(true)
	for k in config.keys():
		cfg[k] = config[k]

	_policy = String(cfg["policy"])
	growth_goal = int(cfg["growth_goal"])
	var years: int = maxi(1, int(cfg["max_years"]))
	max_days = years * YEAR_DAYS
	overhead = int(cfg["overhead"])
	base_wage = int(cfg["base_wage"])
	wage_per_field = int(cfg["wage_per_field"])
	labor_saving_per_machine = int(cfg["labor_saving_per_machine"])
	min_wage = int(cfg["min_wage"])
	base_work = maxi(1, int(cfg["base_work"]))
	fertilizer_cost = int(cfg["fertilizer_cost"])
	fertilizer_amount = float(cfg["fertilizer_amount"])
	irrigation_cost = int(cfg["irrigation_cost"])
	feed_buy_batch = maxi(1, int(cfg["feed_buy_batch"]))
	interest_bp = int(cfg["interest_bp"])
	max_debt = int(cfg["max_debt"])
	bankruptcy_floor = int(cfg["bankruptcy_floor"])
	bankruptcy_patience = maxi(1, int(cfg["bankruptcy_patience"]))
	weather_override = int(cfg["weather_override"])
	stock_asset_frac_num = int(cfg["stock_asset_frac_num"])
	stock_asset_frac_den = maxi(1, int(cfg["stock_asset_frac_den"]))

	day = 0
	outcome = ONGOING
	bankruptcy_days = 0
	illegal_attempts = 0
	work_used = 0
	last_income = 0
	last_weather = W_NORMAL
	last_harvest_units = 0
	last_harvest_field = -1
	last_livestock_product = 0
	last_livestock_deaths = 0
	last_livestock_births = 0
	last_feed_consumed = 0
	total_harvests = 0

	_seed = seed_value
	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

	# Per-field state — soil quality gets a small deterministic jitter from the seed.
	_soil = PackedFloat32Array()
	_nitrogen = PackedFloat32Array()
	_crop = PackedInt32Array()
	_growth = PackedInt32Array()
	_health_sum = PackedFloat32Array()
	_irrigated = PackedInt32Array()
	_last_crop = PackedInt32Array()
	_soil.resize(FIELD_COUNT)
	_nitrogen.resize(FIELD_COUNT)
	_crop.resize(FIELD_COUNT)
	_growth.resize(FIELD_COUNT)
	_health_sum.resize(FIELD_COUNT)
	_irrigated.resize(FIELD_COUNT)
	_last_crop.resize(FIELD_COUNT)
	for f in FIELD_COUNT:
		var jitter: float = (float(_hash2(_seed, 7000 + f) % 1000) / 1000.0 - 0.5) * 0.10
		_soil[f] = clampf(FIELD_SOIL_BASE[f] + jitter, 0.50, 1.10)
		_nitrogen[f] = NITROGEN_START
		_crop[f] = -1
		_growth[f] = 0
		_health_sum[f] = 0.0
		_irrigated[f] = 0
		_last_crop[f] = -1

	# Livestock + feed.
	_herd = PackedInt32Array()
	_herd.resize(ANIMAL_COUNT)
	for a in ANIMAL_COUNT:
		_herd[a] = 0
	_feed_stock = 0

	# Harvested goods.
	_product_stock = PackedInt32Array()
	_product_stock.resize(COMMODITY_COUNT)
	for c in COMMODITY_COUNT:
		_product_stock[c] = 0

	# Machinery.
	_mach_type = PackedInt32Array()
	_mach_value = PackedInt32Array()

	# Money ledger + starting position.
	_cat_totals = {}
	cash = 0
	_start_cash = 0
	debt = 0
	_apply_cash(int(cfg["start_cash"]), "seed_capital")
	_start_cash = cash   # baseline for the conservation invariant
	var start_debt: int = int(cfg["initial_debt"])
	if start_debt > 0:
		debt = start_debt

	win_target = net_worth() + growth_goal


# =====================================================================
#  Money ledger (the ONLY way cash may change)
# =====================================================================

func _apply_cash(delta: int, category: String) -> void:
	cash += delta
	_cat_totals[category] = int(_cat_totals.get(category, 0)) + delta


func category_total(category: String) -> int:
	return int(_cat_totals.get(category, 0))


## Every ledger category that has seen a flow — lets tests confirm money only ever moves
## through DEFINED, named flows (no undefined path minted cash).
func category_keys() -> Array:
	return _cat_totals.keys()


## The conservation invariant: cash equals the sum of every recorded ledger delta (starting
## cash is itself a ledger entry, "seed_capital"). True by construction — the probe
## recomputes it to prove no path bypasses the ledger.
func conservation_ok() -> bool:
	var s: int = 0
	for k in _cat_totals.keys():
		s += int(_cat_totals[k])
	return cash == s


# =====================================================================
#  Determinism hash helper (pure — does NOT consume the RNG stream)
# =====================================================================

func _hash2(a: int, b: int) -> int:
	var h: int = FNV_OFFSET
	h = (h ^ (a & MASK63)) * FNV_PRIME
	h &= MASK63
	h = (h ^ (b & MASK63)) * FNV_PRIME
	h &= MASK63
	return h


# =====================================================================
#  Calendar helpers
# =====================================================================

func season_of(at_day: int) -> int:
	return (((at_day % YEAR_DAYS) + YEAR_DAYS) % YEAR_DAYS) / SEASON_DAYS

func day_of_year(at_day: int) -> int:
	return ((at_day % YEAR_DAYS) + YEAR_DAYS) % YEAR_DAYS

func year_of(at_day: int) -> int:
	return at_day / YEAR_DAYS + 1

## Shortest distance between two days on the 360-day ring.
func _ring_dist(a: float, b: float) -> float:
	var raw: float = absf(a - b)
	return minf(raw, float(YEAR_DAYS) - raw)


# =====================================================================
#  Weather — a PURE HASH of (seed, day); NOT gated by the RNG stream
# =====================================================================

## The weather for a given day — a deterministic function of (seed, day). Season shapes the
## odds: drought/heat cluster in summer, frost in winter/late-spring, rain in spring, pests
## in summer/fall. If weather_override >= 0 that type is forced (used by controlled probes).
func weather_for_day(at_day: int) -> int:
	if weather_override >= 0:
		return weather_override
	var s: int = season_of(at_day)
	var r: float = float(_hash2(_seed, 30000 + at_day) % 100000) / 100000.0
	# Cumulative thresholds [rain, drought, frost, heat, pests]; remainder is clear weather.
	var rain: float = 0.14
	var drought: float = 0.0
	var frost: float = 0.0
	var heat: float = 0.0
	var pests: float = 0.06
	match s:
		S_SPRING:
			rain = 0.22
			frost = 0.08
			pests = 0.05
		S_SUMMER:
			rain = 0.12
			drought = 0.16
			heat = 0.14
			pests = 0.09
		S_FALL:
			rain = 0.14
			pests = 0.12
			frost = 0.04
		S_WINTER:
			rain = 0.10
			frost = 0.18
			heat = 0.0
	var t_rain: float = rain
	var t_drought: float = t_rain + drought
	var t_frost: float = t_drought + frost
	var t_heat: float = t_frost + heat
	var t_pests: float = t_heat + pests
	if r < t_rain:
		return W_RAIN
	if r < t_drought:
		return W_DROUGHT
	if r < t_frost:
		return W_FROST
	if r < t_heat:
		return W_HEAT
	if r < t_pests:
		return W_PESTS
	return W_NORMAL


# =====================================================================
#  Crop suitability + the daily growth condition
# =====================================================================

## A crop's growth-suitability multiplier on a given day (a wrapped Gaussian, floored).
func crop_suitability(crop: int, at_day: int) -> float:
	if crop < 0 or crop >= CROP_COUNT:
		return 0.0
	var doy: float = float(day_of_year(at_day))
	var dist: float = _ring_dist(doy, CROP_SUIT_CENTER[crop])
	var w: float = CROP_SUIT_WIDTH[crop]
	return SUIT_FLOOR + (1.0 - SUIT_FLOOR) * exp(-(dist * dist) / (2.0 * w * w))


## The growth condition for a crop on a field on a given day under a given weather: the
## product of a WATER factor (weather + irrigation vs the crop's need), the crop's seasonal
## SUITABILITY, and a HAZARD factor (frost / pest / heat damage). Range ~0..1.2.
func growth_condition(crop: int, at_day: int, irrigated: bool, weather: int) -> float:
	if crop < 0 or crop >= CROP_COUNT:
		return 0.0
	var water: float = BASE_MOISTURE
	match weather:
		W_RAIN:
			water += 0.45
		W_DROUGHT:
			water -= 0.42
		W_HEAT:
			water -= 0.22
	if irrigated:
		water += IRRIGATION_WATER
	var need: float = CROP_WATER_NEED[crop]
	var water_factor: float = 1.0
	if need > 0.0:
		water_factor = clampf(water / need, 0.30, 1.0)
	var suit: float = crop_suitability(crop, at_day)
	var hazard: float = 1.0
	if weather == W_FROST and CROP_FROST_SENSITIVE[crop] == 1:
		hazard *= 0.55
	if weather == W_PESTS:
		hazard *= 0.75
	if weather == W_HEAT and crop == CR_WHEAT:
		hazard *= 0.85
	return clampf(water_factor * suit * hazard, 0.0, 1.2)


## The nutrient factor a field's nitrogen buys a crop's yield (0.25..1.0).
func nutrient_factor(nitrogen: float) -> float:
	return clampf(nitrogen / NITROGEN_OPTIMAL, NUTRIENT_FLOOR, 1.0)


# =====================================================================
#  Machinery-derived capabilities
# =====================================================================

func machine_count(mtype: int) -> int:
	var c: int = 0
	for i in _mach_type.size():
		if _mach_type[i] == mtype:
			c += 1
	return c

func tractor_count() -> int:
	return machine_count(M_TRACTOR)

func harvester_count() -> int:
	return machine_count(M_HARVESTER)

## Fields that can be planted/harvested per day (hand labour + machinery throughput).
func work_capacity() -> int:
	return base_work + tractor_count() * WORK_PER_TRACTOR + harvester_count() * WORK_PER_HARVESTER

func work_remaining() -> int:
	return maxi(0, work_capacity() - work_used)

## Harvest efficiency — the fraction of a crop actually brought in (harvesters cut losses).
func harvest_efficiency() -> float:
	return clampf(BASE_HARVEST_EFF + float(harvester_count()) * HARVEST_EFF_PER_HARVESTER, 0.0, 1.0)

func machinery_value() -> int:
	var v: int = 0
	for i in _mach_value.size():
		v += _mach_value[i]
	return v


# =====================================================================
#  Commodity market — a real COMPUTED multi-frequency price curve
# =====================================================================

## A commodity's market price on a given day: base × (1 + Σ amp·sin(2π·day/period + phase)),
## with a seed-derived phase per commodity+wave and a floor. Pure — sell-timing matters.
func market_price(commodity: int, at_day: int) -> int:
	if commodity < 0 or commodity >= COMMODITY_COUNT:
		return 0
	var base: float = float(COMMODITY_BASE_PRICE[commodity])
	var m: float = 1.0
	var doy: float = float(day_of_year(at_day))
	for wi in PRICE_WAVES.size():
		var period: float = float(PRICE_WAVES[wi][0])
		var amp: float = float(PRICE_WAVES[wi][1])
		var phase: float = float(_hash2(_seed, 40000 + commodity * 16 + wi) % 62832) / 10000.0
		m += amp * sin(TAU * doy / period + phase)
	var price: float = base * m
	var floor_price: float = base * PRICE_FLOOR_FRAC
	return maxi(1, int(round(maxf(price, floor_price))))

## The average price of a commodity across one full year (a deterministic reference used by
## auto-play to decide when the market is "high").
func average_price(commodity: int) -> int:
	var s: int = 0
	for d in YEAR_DAYS:
		s += market_price(commodity, d)
	return maxi(1, s / YEAR_DAYS)


# =====================================================================
#  Derived queries
# =====================================================================

func field_count() -> int:
	return FIELD_COUNT

func crop_count() -> int:
	return CROP_COUNT

func field_crop(field: int) -> int:
	return _crop[field]

func field_growth(field: int) -> int:
	return _growth[field]

func field_nitrogen(field: int) -> float:
	return _nitrogen[field]

func field_soil(field: int) -> float:
	return _soil[field]

func field_irrigated(field: int) -> bool:
	return _irrigated[field] == 1

func field_last_crop(field: int) -> int:
	return _last_crop[field]

func field_is_fallow(field: int) -> bool:
	return _crop[field] < 0

func field_is_mature(field: int) -> bool:
	return _crop[field] >= 0 and _growth[field] >= CROP_DURATION[_crop[field]]

## Progress of a field's crop toward maturity, 0..1.
func field_progress(field: int) -> float:
	if _crop[field] < 0:
		return 0.0
	return clampf(float(_growth[field]) / float(CROP_DURATION[_crop[field]]), 0.0, 1.0)

## The yield a field's crop would produce if harvested right now (units) — the same formula
## harvest() commits. Uses nitrogen BEFORE the harvest draw, accumulated health, soil, and
## current harvest efficiency.
func projected_yield(field: int) -> int:
	var crop: int = _crop[field]
	if crop < 0:
		return 0
	var dur: int = CROP_DURATION[crop]
	var avg_health: float = 0.0
	if dur > 0:
		avg_health = _health_sum[field] / float(dur)
	var units: float = float(CROP_BASE_YIELD[crop]) * _soil[field] * nutrient_factor(_nitrogen[field]) \
		* avg_health * harvest_efficiency()
	return maxi(0, int(round(units)))

func herd(animal: int) -> int:
	return _herd[animal]

func total_herd() -> int:
	var c: int = 0
	for a in ANIMAL_COUNT:
		c += _herd[a]
	return c

func feed_stock() -> int:
	return _feed_stock

func product_stock(commodity: int) -> int:
	return _product_stock[commodity]

func daily_feed_need() -> int:
	var n: int = 0
	for a in ANIMAL_COUNT:
		n += _herd[a] * ANIMAL_FEED_PER_DAY[a]
	return n

## Net-worth value of one unit of a commodity's harvested stock (base price, depreciated).
func stock_unit_value(commodity: int) -> int:
	return COMMODITY_BASE_PRICE[commodity] * stock_asset_frac_num / stock_asset_frac_den

func land_value() -> int:
	return FIELD_COUNT * LAND_VALUE_EACH

## Value of everything not cash: land + machinery + herds + feed + harvested stock.
func stock_value() -> int:
	var v: int = 0
	for c in COMMODITY_COUNT:
		v += _product_stock[c] * stock_unit_value(c)
	v += _feed_stock * stock_unit_value(C_FEED)
	for a in ANIMAL_COUNT:
		v += _herd[a] * ANIMAL_ASSET_VALUE[a]
	return v

func net_worth() -> int:
	return cash + land_value() + machinery_value() + stock_value() - debt


# =====================================================================
#  Legality — actions are is_legal-gated; illegal ones never mutate state
# =====================================================================

func _valid_field(field: int) -> bool:
	return field >= 0 and field < FIELD_COUNT

func _valid_crop(crop: int) -> bool:
	return crop >= 0 and crop < CROP_COUNT

func crop_in_season(crop: int, at_day: int) -> bool:
	if not _valid_crop(crop):
		return false
	return (CROP_PLANT_SEASONS[crop] & (1 << season_of(at_day))) != 0

func can_plant(field: int, crop: int, override_season: bool = false) -> bool:
	if outcome != ONGOING or not _valid_field(field) or not _valid_crop(crop):
		return false
	if _crop[field] >= 0:
		return false                       # field already planted.
	if work_remaining() <= 0:
		return false                       # no labour/throughput left today.
	if not override_season and not crop_in_season(crop, day):
		return false
	return cash >= CROP_SEED_COST[crop]

func can_harvest(field: int) -> bool:
	if outcome != ONGOING or not _valid_field(field):
		return false
	if not field_is_mature(field):
		return false
	return work_remaining() > 0

func can_fertilize(field: int) -> bool:
	if outcome != ONGOING or not _valid_field(field):
		return false
	return cash >= fertilizer_cost and _nitrogen[field] < NITROGEN_MAX

func can_set_irrigation(field: int, _on: bool) -> bool:
	return outcome == ONGOING and _valid_field(field)

func can_buy_livestock(animal: int, count: int) -> bool:
	if outcome != ONGOING or animal < 0 or animal >= ANIMAL_COUNT or count <= 0:
		return false
	if _herd[animal] + count > ANIMAL_CAP[animal]:
		return false
	return cash >= count * ANIMAL_BUY_COST[animal]

func can_sell_livestock(animal: int, count: int) -> bool:
	if outcome != ONGOING or animal < 0 or animal >= ANIMAL_COUNT or count <= 0:
		return false
	return _herd[animal] >= count

func can_buy_feed(units: int) -> bool:
	if outcome != ONGOING or units <= 0:
		return false
	return cash >= units * market_price(C_FEED, day)

func can_sell_commodity(commodity: int, units: int) -> bool:
	if outcome != ONGOING or commodity < 0 or commodity >= COMMODITY_COUNT or units <= 0:
		return false
	if commodity == C_FEED:
		return false                       # feed is an input, not a sale product.
	return _product_stock[commodity] >= units

func can_buy_machinery(mtype: int) -> bool:
	if outcome != ONGOING or mtype < 0 or mtype >= MACHINE_TYPE_COUNT:
		return false
	return cash >= MACHINE_COST[mtype]

func can_take_loan(amount: int) -> bool:
	return outcome == ONGOING and amount > 0 and debt + amount <= max_debt

func can_repay_loan(amount: int) -> bool:
	return outcome == ONGOING and amount > 0 and debt > 0 and cash >= amount


# =====================================================================
#  Actions (each returns true on success; false leaves state untouched)
# =====================================================================

## Plant `crop` in a fallow field. Charges the seed cost, consumes a unit of the day's work
## capacity, and begins growth. `override_season` bypasses the plant-season gate (used by
## controlled probes to isolate the nutrient/weather effect).
func plant(field: int, crop: int, override_season: bool = false) -> bool:
	if not can_plant(field, crop, override_season):
		illegal_attempts += 1
		return false
	_apply_cash(-CROP_SEED_COST[crop], "seed_purchase")
	_crop[field] = crop
	_growth[field] = 0
	_health_sum[field] = 0.0
	work_used += 1
	return true


## Harvest a mature field: bring in the yield (crops → the commodity stock, hay → feed
## stock), apply the crop's nitrogen DRAW/FIX to the field, remember the crop for rotation,
## consume a unit of work, and leave the field fallow.
func harvest(field: int) -> bool:
	if not can_harvest(field):
		illegal_attempts += 1
		return false
	var crop: int = _crop[field]
	var units: int = projected_yield(field)
	var commodity: int = CROP_COMMODITY[crop]
	if crop == CR_HAY:
		_feed_stock += units                # hay feeds the herd, it is not sold.
	else:
		_product_stock[commodity] += units
	# Apply the nitrogen balance: heavy feeders draw down, the legume fixes.
	_nitrogen[field] = clampf(_nitrogen[field] - CROP_NUTRIENT_DRAW[crop], 0.0, NITROGEN_MAX)
	_last_crop[field] = crop
	_crop[field] = -1
	_growth[field] = 0
	_health_sum[field] = 0.0
	work_used += 1
	total_harvests += 1
	last_harvest_units = units
	last_harvest_field = field
	return true


## Apply fertilizer to a field: pay the cost and raise its nitrogen (capped).
func fertilize(field: int) -> bool:
	if not can_fertilize(field):
		illegal_attempts += 1
		return false
	_apply_cash(-fertilizer_cost, "fertilizer")
	_nitrogen[field] = clampf(_nitrogen[field] + fertilizer_amount, 0.0, NITROGEN_MAX)
	return true


## Toggle a field's irrigation. While active and the field is planted, a daily irrigation
## cost is charged in the tick, and the field's crop gets extra water (mitigating drought).
func set_irrigation(field: int, on: bool) -> bool:
	if not can_set_irrigation(field, on):
		illegal_attempts += 1
		return false
	_irrigated[field] = 1 if on else 0
	return true


func buy_livestock(animal: int, count: int) -> bool:
	if not can_buy_livestock(animal, count):
		illegal_attempts += 1
		return false
	_apply_cash(-count * ANIMAL_BUY_COST[animal], "livestock_purchase")
	_herd[animal] += count
	return true


## Sell (cull) livestock for their salvage value.
func sell_livestock(animal: int, count: int) -> bool:
	if not can_sell_livestock(animal, count):
		illegal_attempts += 1
		return false
	_herd[animal] -= count
	_apply_cash(count * ANIMAL_SELL_VALUE[animal], "livestock_salvage")
	return true


func buy_feed(units: int) -> bool:
	if not can_buy_feed(units):
		illegal_attempts += 1
		return false
	_apply_cash(-units * market_price(C_FEED, day), "feed_purchase")
	_feed_stock += units
	return true


## Sell harvested crop / livestock product at the CURRENT market price — sell-timing matters.
func sell_commodity(commodity: int, units: int) -> bool:
	if not can_sell_commodity(commodity, units):
		illegal_attempts += 1
		return false
	var price: int = market_price(commodity, day)
	_product_stock[commodity] -= units
	var category: String = "livestock_sales" if COMMODITY_IS_LIVESTOCK[commodity] == 1 else "crop_sales"
	_apply_cash(units * price, category)
	return true


func buy_machinery(mtype: int) -> bool:
	if not can_buy_machinery(mtype):
		illegal_attempts += 1
		return false
	_apply_cash(-MACHINE_COST[mtype], "machinery_purchase")
	_mach_type.append(mtype)
	_mach_value.append(MACHINE_COST[mtype])
	return true


func take_loan(amount: int) -> bool:
	if not can_take_loan(amount):
		illegal_attempts += 1
		return false
	_apply_cash(amount, "loan_draw")
	debt += amount
	return true


func repay_loan(amount: int) -> bool:
	if not can_repay_loan(amount):
		illegal_attempts += 1
		return false
	var pay: int = mini(amount, debt)
	_apply_cash(-pay, "loan_repay")
	debt -= pay
	return true


# =====================================================================
#  The daily tick — weather, crops, livestock, machinery, bills, time
# =====================================================================

## Advance the farm one day. Returns the player's signed cash delta for the day (bills, and
## any livestock salvage from mortality book only to net worth via herd loss, not cash).
func tick_day() -> int:
	if outcome != ONGOING:
		return 0
	var cash_before: int = cash

	last_weather = weather_for_day(day)
	_advance_crops(last_weather)     # growth + accumulated condition per planted field
	_run_livestock()                 # feed, produce, breed, mortality
	_depreciate_machinery()          # net-worth depreciation (no cash flow)
	_pay_daily_bills()               # overhead + wages + maintenance + irrigation

	day += 1
	work_used = 0                    # a fresh day of labour/throughput capacity
	if day % MONTH_DAYS == 0:
		_close_month()               # loan interest

	_judge()

	last_income = cash - cash_before
	return last_income


## Grow every planted, immature field one day under today's weather, accumulating its daily
## growth condition into the field's health (which sets the eventual yield).
func _advance_crops(weather: int) -> void:
	for f in FIELD_COUNT:
		var crop: int = _crop[f]
		if crop < 0:
			continue
		if _growth[f] >= CROP_DURATION[crop]:
			continue                 # already mature — waits for harvest, no further health.
		var cond: float = growth_condition(crop, day, _irrigated[f] == 1, weather)
		_health_sum[f] += cond
		_growth[f] += 1


## Feed the herds from the feed stock, produce milk/eggs/meat for fed animals, then breed
## (well-fed, under cap, on the animal's breed cycle) and apply mortality (seeded, higher
## when underfed). Products accumulate into commodity stock for later sale.
func _run_livestock() -> void:
	last_livestock_product = 0
	last_livestock_deaths = 0
	last_livestock_births = 0
	last_feed_consumed = 0
	var need: int = daily_feed_need()
	if need <= 0:
		return
	var consumed: int = mini(need, _feed_stock)
	_feed_stock -= consumed
	last_feed_consumed = consumed
	var fed_ratio: float = float(consumed) / float(need)

	for a in ANIMAL_COUNT:
		var head: int = _herd[a]
		if head <= 0:
			continue
		# Production scales with how well the herd was fed.
		var produced: int = int(floor(float(head) * float(ANIMAL_PRODUCT_PER_DAY[a]) * fed_ratio))
		if produced > 0:
			_product_stock[ANIMAL_PRODUCT[a]] += produced
			last_livestock_product += produced
		# Mortality: base rate plus a hunger penalty, resolved with the seeded RNG.
		var mort: float = float(ANIMAL_MORTALITY_BP[a]) / 10000.0 + (1.0 - fed_ratio) * 0.05
		var expected: float = float(head) * mort
		var deaths: int = int(floor(expected))
		if _rng.randf() < (expected - float(deaths)):
			deaths += 1
		deaths = mini(deaths, head)
		if deaths > 0:
			_herd[a] -= deaths
			head -= deaths
			last_livestock_deaths += deaths
		# Breeding: only a well-fed herd of at least a pair, on its breeding cycle, under cap.
		if fed_ratio >= 0.999 and head >= 2 and (day % ANIMAL_BREED_PERIOD[a]) == 0:
			var births: int = maxi(1, head / 8)
			births = mini(births, ANIMAL_CAP[a] - _herd[a])
			if births > 0:
				_herd[a] += births
				last_livestock_births += births


## Depreciate each machine one day toward its salvage floor (a net-worth effect only — the
## cash cost of a machine was booked at purchase; maintenance is the ongoing cash cost).
func _depreciate_machinery() -> void:
	for i in _mach_value.size():
		var mtype: int = _mach_type[i]
		var floor_v: int = int(float(MACHINE_COST[mtype]) * MACHINE_SALVAGE_FRAC)
		var dep: int = int(float(MACHINE_COST[mtype]) * float(MACHINE_DEP_BP[mtype]) / 10000.0)
		_mach_value[i] = maxi(floor_v, _mach_value[i] - dep)


func _pay_daily_bills() -> void:
	if overhead > 0:
		_apply_cash(-overhead, "overhead")
	# Labour: a base bill plus a per-planted-field charge, trimmed by machinery, floored.
	var planted: int = 0
	for f in FIELD_COUNT:
		if _crop[f] >= 0:
			planted += 1
	var machines: int = _mach_type.size()
	var wage_bill: int = base_wage + planted * wage_per_field - machines * labor_saving_per_machine
	wage_bill = maxi(min_wage, wage_bill)
	_apply_cash(-wage_bill, "wages")
	# Machinery maintenance.
	var maint: int = 0
	for i in _mach_type.size():
		maint += MACHINE_MAINT[_mach_type[i]]
	if maint > 0:
		_apply_cash(-maint, "maintenance")
	# Irrigation: charged per planted, irrigated field.
	var irr: int = 0
	for f in FIELD_COUNT:
		if _irrigated[f] == 1 and _crop[f] >= 0:
			irr += 1
	if irr > 0 and irrigation_cost > 0:
		_apply_cash(-irr * irrigation_cost, "irrigation")


func _close_month() -> void:
	if debt > 0:
		var interest: int = int(float(debt) * float(interest_bp) / 10000.0)
		if interest > 0:
			_apply_cash(-interest, "interest")


func _judge() -> void:
	if outcome != ONGOING:
		return
	# Bankruptcy watch.
	if cash < bankruptcy_floor:
		bankruptcy_days += 1
	else:
		bankruptcy_days = 0
	if bankruptcy_days >= bankruptcy_patience:
		outcome = LOST
		return
	# Victory: net-worth goal reached.
	if net_worth() >= win_target:
		outcome = WON
		return
	# Hard cap: judged by net worth at the deadline.
	if day >= max_days:
		outcome = WON if net_worth() >= win_target else LOST


# =====================================================================
#  Auto-play heuristic (deterministic) — for the full-run probe / demo
# =====================================================================

## Take one day's worth of prudent decisions, then advance the day. Harvests mature fields,
## sells stock when the market is strong (or to stay liquid), fertilizes depleted fields,
## rotation-plants the best in-season crop into fallow fields, keeps the herds fed, buys
## livestock + machinery when flush, irrigates under drought, and borrows to stay solvent.
## Pure & deterministic given the seed. Returns the day's cash delta.
func auto_play_step() -> int:
	if outcome != ONGOING:
		return 0
	var aggressive: bool = _policy == "aggressive"

	# 1) HARVEST every mature field (bounded by the day's work capacity).
	for f in FIELD_COUNT:
		if work_remaining() <= 0:
			break
		if field_is_mature(f):
			harvest(f)

	# 2) SELL harvested stock: dump when the price beats its yearly average, or whenever
	#    cash is tight, so profit is realized above the booked stock value.
	for c in COMMODITY_COUNT:
		if c == C_FEED:
			continue
		var units: int = _product_stock[c]
		if units <= 0:
			continue
		var price: int = market_price(c, day)
		var avg: int = average_price(c)
		if price >= avg or cash < 3000:
			sell_commodity(c, units)

	# 3) IRRIGATE planted fields under a drought; drop irrigation otherwise (save the cost).
	var drought_today: bool = weather_for_day(day) == W_DROUGHT
	for f in FIELD_COUNT:
		if _crop[f] >= 0 and drought_today and not field_irrigated(f):
			set_irrigation(f, true)
		elif field_irrigated(f) and not drought_today:
			set_irrigation(f, false)

	# 4) FERTILIZE a fallow, depleted field before replanting (keeps yields up).
	for f in FIELD_COUNT:
		if _crop[f] < 0 and _nitrogen[f] < 25.0 and cash > fertilizer_cost + 4000:
			if can_fertilize(f):
				fertilize(f)

	# 5) PLANT fallow fields with the best in-season crop, avoiding an immediate repeat of
	#    the last crop (rotation) and preferring the nitrogen-fixing legume on a poor field.
	for f in FIELD_COUNT:
		if work_remaining() <= 0:
			break
		if _crop[f] >= 0:
			continue
		var pick: int = _auto_pick_crop(f)
		if pick < 0:
			continue
		var buffer: int = 2500 if aggressive else 4000
		if cash - CROP_SEED_COST[pick] > buffer and can_plant(f, pick):
			plant(f, pick)

	# 6) FEED the herds: keep enough feed on hand for a few days.
	var need: int = daily_feed_need()
	if need > 0 and _feed_stock < need * 3:
		var want: int = need * 6
		var batch: int = want - _feed_stock
		var feed_cost: int = batch * market_price(C_FEED, day)
		if cash - feed_cost > 2000 and can_buy_feed(batch):
			buy_feed(batch)

	# 7) BUY LIVESTOCK early for passive income when flush and the herd is small.
	if _herd[A_CHICKENS] < 30 and cash > 4000 and can_buy_livestock(A_CHICKENS, 20):
		buy_livestock(A_CHICKENS, 20)
	if _herd[A_CATTLE] < 6 and cash > 12000 and can_buy_livestock(A_CATTLE, 3):
		buy_livestock(A_CATTLE, 3)
	if aggressive and _herd[A_PIGS] < 10 and cash > 8000 and can_buy_livestock(A_PIGS, 6):
		buy_livestock(A_PIGS, 6)

	# 8) BUY MACHINERY when cash is deep — raises throughput + harvest efficiency.
	if tractor_count() < 1 and cash > MACHINE_COST[M_TRACTOR] + 14000 and can_buy_machinery(M_TRACTOR):
		buy_machinery(M_TRACTOR)
	elif harvester_count() < 1 and tractor_count() >= 1 and cash > MACHINE_COST[M_HARVESTER] + 18000 \
			and can_buy_machinery(M_HARVESTER):
		buy_machinery(M_HARVESTER)

	# 9) LOAN to stay liquid while still solvent.
	if cash < 1500 and net_worth() > land_value() + 12000 and debt + 6000 <= max_debt \
			and can_take_loan(6000):
		take_loan(6000)

	return tick_day()


## Choose the crop to plant into a fallow field under auto-play: among crops in season, skip
## the one just harvested here (rotation); if the field is nitrogen-poor, force the legume
## (soybeans) to rebuild it; otherwise take the crop with the highest expected gross value
## at the current market (base yield × price − seed cost), scaled by this field's soil.
func _auto_pick_crop(field: int) -> int:
	# Rebuild depleted soil with the legume if it is plantable now.
	if _nitrogen[field] < 30.0 and crop_in_season(CR_SOY, day) and _last_crop[field] != CR_SOY:
		return CR_SOY
	var best: int = -1
	var best_score: float = -1.0e18
	for crop in CROP_COUNT:
		if not crop_in_season(crop, day):
			continue
		if crop == _last_crop[field]:
			continue                        # rotate — avoid an immediate monoculture repeat.
		var commodity: int = CROP_COMMODITY[crop]
		var price: float = float(market_price(commodity, day)) if crop != CR_HAY else float(COMMODITY_BASE_PRICE[C_FEED])
		var expected: float = float(CROP_BASE_YIELD[crop]) * _soil[field] * nutrient_factor(_nitrogen[field]) \
			* crop_suitability(crop, day) * price - float(CROP_SEED_COST[crop])
		# A legume that also rebuilds nitrogen gets a small rotation bonus.
		if crop == CR_SOY:
			expected += 300.0
		if expected > best_score:
			best_score = expected
			best = crop
	# Fall back to any in-season crop (even a repeat) if rotation left nothing.
	if best < 0:
		for crop in CROP_COUNT:
			if crop_in_season(crop, day):
				return crop
	return best


## Run the whole game to a terminal outcome under auto-play (bounded by max_days so it
## always terminates). Returns the final outcome.
func auto_play_to_end() -> int:
	var guard: int = 0
	var hard_cap: int = max_days + 8
	while outcome == ONGOING and guard < hard_cap:
		auto_play_step()
		guard += 1
	return outcome


# =====================================================================
#  Determinism checksum — folds the WHOLE farm state into one int
# =====================================================================

func _fold(h: int, v: int) -> int:
	h = (h ^ v) * FNV_PRIME
	return h & MASK63

func _qf(v: float) -> int:
	return int(round(v * 100.0))

## Order-stable checksum of the entire farm: two engines are equal iff this matches.
func state_checksum() -> int:
	var h: int = FNV_OFFSET
	h = _fold(h, _seed)
	h = _fold(h, int(_rng.state & MASK63))
	h = _fold(h, day)
	h = _fold(h, outcome)
	h = _fold(h, cash)
	h = _fold(h, debt)
	h = _fold(h, bankruptcy_days)
	h = _fold(h, win_target)
	h = _fold(h, illegal_attempts)
	h = _fold(h, work_used)
	h = _fold(h, total_harvests)
	h = _fold(h, _feed_stock)
	for f in FIELD_COUNT:
		h = _fold(h, _crop[f])
		h = _fold(h, _growth[f])
		h = _fold(h, _irrigated[f])
		h = _fold(h, _last_crop[f])
		h = _fold(h, _qf(_nitrogen[f]))
		h = _fold(h, _qf(_soil[f]))
		h = _fold(h, _qf(_health_sum[f]))
	for a in ANIMAL_COUNT:
		h = _fold(h, _herd[a])
	for c in COMMODITY_COUNT:
		h = _fold(h, _product_stock[c])
	for i in _mach_type.size():
		h = _fold(h, _mach_type[i])
		h = _fold(h, _mach_value[i])
	for cat in LEDGER_CATEGORIES:
		h = _fold(h, category_total(cat))
	return h


# =====================================================================
#  Persistence — full state incl. RNG (byte-identical round-trip)
# =====================================================================

func save_data() -> Dictionary:
	return {
		"seed": _seed,
		"policy": _policy,
		"day": day,
		"outcome": outcome,
		"cash": cash,
		"debt": debt,
		"bankruptcy_days": bankruptcy_days,
		"win_target": win_target,
		"illegal_attempts": illegal_attempts,
		"work_used": work_used,
		"total_harvests": total_harvests,
		"last_income": last_income,
		"last_weather": last_weather,
		"last_harvest_units": last_harvest_units,
		"last_harvest_field": last_harvest_field,
		"last_livestock_product": last_livestock_product,
		"last_livestock_deaths": last_livestock_deaths,
		"last_livestock_births": last_livestock_births,
		"last_feed_consumed": last_feed_consumed,
		"start_cash": _start_cash,
		"growth_goal": growth_goal,
		"max_days": max_days,
		"overhead": overhead,
		"base_wage": base_wage,
		"wage_per_field": wage_per_field,
		"labor_saving_per_machine": labor_saving_per_machine,
		"min_wage": min_wage,
		"base_work": base_work,
		"fertilizer_cost": fertilizer_cost,
		"fertilizer_amount": fertilizer_amount,
		"irrigation_cost": irrigation_cost,
		"feed_buy_batch": feed_buy_batch,
		"interest_bp": interest_bp,
		"max_debt": max_debt,
		"bankruptcy_floor": bankruptcy_floor,
		"bankruptcy_patience": bankruptcy_patience,
		"weather_override": weather_override,
		"stock_asset_frac_num": stock_asset_frac_num,
		"stock_asset_frac_den": stock_asset_frac_den,
		"feed_stock": _feed_stock,
		"soil": _soil.duplicate(),
		"nitrogen": _nitrogen.duplicate(),
		"crop": _crop.duplicate(),
		"growth": _growth.duplicate(),
		"health_sum": _health_sum.duplicate(),
		"irrigated": _irrigated.duplicate(),
		"last_crop": _last_crop.duplicate(),
		"herd": _herd.duplicate(),
		"product_stock": _product_stock.duplicate(),
		"mach_type": _mach_type.duplicate(),
		"mach_value": _mach_value.duplicate(),
		"cat_totals": _cat_totals.duplicate(true),
		"rng_seed": _rng.seed,
		"rng_state": _rng.state,
	}


func load_data(data: Dictionary) -> void:
	_seed = int(data["seed"])
	_policy = String(data["policy"])
	day = int(data["day"])
	outcome = int(data["outcome"])
	cash = int(data["cash"])
	debt = int(data["debt"])
	bankruptcy_days = int(data["bankruptcy_days"])
	win_target = int(data["win_target"])
	illegal_attempts = int(data["illegal_attempts"])
	work_used = int(data["work_used"])
	total_harvests = int(data["total_harvests"])
	last_income = int(data["last_income"])
	last_weather = int(data["last_weather"])
	last_harvest_units = int(data["last_harvest_units"])
	last_harvest_field = int(data["last_harvest_field"])
	last_livestock_product = int(data["last_livestock_product"])
	last_livestock_deaths = int(data["last_livestock_deaths"])
	last_livestock_births = int(data["last_livestock_births"])
	last_feed_consumed = int(data["last_feed_consumed"])
	_start_cash = int(data["start_cash"])
	growth_goal = int(data["growth_goal"])
	max_days = int(data["max_days"])
	overhead = int(data["overhead"])
	base_wage = int(data["base_wage"])
	wage_per_field = int(data["wage_per_field"])
	labor_saving_per_machine = int(data["labor_saving_per_machine"])
	min_wage = int(data["min_wage"])
	base_work = int(data["base_work"])
	fertilizer_cost = int(data["fertilizer_cost"])
	fertilizer_amount = float(data["fertilizer_amount"])
	irrigation_cost = int(data["irrigation_cost"])
	feed_buy_batch = int(data["feed_buy_batch"])
	interest_bp = int(data["interest_bp"])
	max_debt = int(data["max_debt"])
	bankruptcy_floor = int(data["bankruptcy_floor"])
	bankruptcy_patience = int(data["bankruptcy_patience"])
	weather_override = int(data["weather_override"])
	stock_asset_frac_num = int(data["stock_asset_frac_num"])
	stock_asset_frac_den = int(data["stock_asset_frac_den"])
	_feed_stock = int(data["feed_stock"])
	_soil = (data["soil"] as PackedFloat32Array).duplicate()
	_nitrogen = (data["nitrogen"] as PackedFloat32Array).duplicate()
	_crop = (data["crop"] as PackedInt32Array).duplicate()
	_growth = (data["growth"] as PackedInt32Array).duplicate()
	_health_sum = (data["health_sum"] as PackedFloat32Array).duplicate()
	_irrigated = (data["irrigated"] as PackedInt32Array).duplicate()
	_last_crop = (data["last_crop"] as PackedInt32Array).duplicate()
	_herd = (data["herd"] as PackedInt32Array).duplicate()
	_product_stock = (data["product_stock"] as PackedInt32Array).duplicate()
	_mach_type = (data["mach_type"] as PackedInt32Array).duplicate()
	_mach_value = (data["mach_value"] as PackedInt32Array).duplicate()
	_cat_totals = (data["cat_totals"] as Dictionary).duplicate(true)
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(data["rng_seed"])
	_rng.state = int(data["rng_state"])


## A canonical, order-stable serialization for byte-identical comparison in tests.
func snapshot_string() -> String:
	return JSON.stringify(save_data())
