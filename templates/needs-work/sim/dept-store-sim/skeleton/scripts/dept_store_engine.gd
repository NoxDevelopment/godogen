extends RefCounted
class_name DeptStoreEngine
## res://scripts/dept_store_engine.gd
## THE PURE ENGINE — a deterministic, seedable 80s BIG-BOX DEPARTMENT-STORE
## management sim (a Kmart / Sears-of-the-catalog-era in the mall-tycoon /
## video-store-sim retail-tycoon lineage). You OWN the store: EIGHT DEPARTMENTS
## (Apparel, Electronics, Toys, Appliances, Home & Garden, Automotive, Jewelry,
## Sporting Goods), each with several PRODUCT LINES you buy INVENTORY of, its own
## STAFFING and FLOOR-SPACE allocation, and its own SEASONAL demand profile. Grow CASH
## and NET WORTH by stocking the right depth in each department AHEAD of its season and
## clearing the leftovers before the next one.
##
## THE TWO THINGS THAT MAKE THIS DISTINCT FROM ITS SIBLINGS:
##
##  1) SEASONAL DEMAND (a real curve, not a table). Each department's demand is a pure
##     function of the day-of-year: a sum of Gaussian season bumps
##       season(dept, day) = 1 + Σ_k amp_k · e^(−dist(doy, center_k)^2 / (2·width_k^2))
##     where dist() wraps around the 360-day year. Toys & Electronics SPIKE in the
##     Christmas window; Home & Garden peaks in spring; Jewelry at Valentine's and
##     Christmas; Automotive & Sporting Goods in summer. Stock a department for its
##     season, or eat stockouts (lost sales) at the peak and aging leftovers after.
##
##  2) THE MAIL-ORDER CATALOGUE (the Sears book) — a SECOND demand channel. PUBLISH a
##     seasonal catalogue (an up-front PRINT cost) and for its run you open a mail-order
##     stream that reaches buyers the physical floor never sees (rural / remote — NOT
##     gated by store foot traffic or floor staff), drawing from the SAME shared
##     inventory. Catalogue orders SHIP after a LEAD TIME (cash lands later) and cost a
##     per-order FULFILLMENT fee. The trade-off — print + fulfillment vs incremental
##     reach — is real: a well-stocked store with little floor traffic still moves units
##     through the book.
##
## Plus MARKDOWNS / CLEARANCE: unsold seasonal stock AGES; a per-line MARKDOWN cuts the
## shelf price (recovering cash but slashing margin) AND lifts that line's demand pull,
## clearing aging inventory before it dead-weights the floor.
##
## Everything — foot traffic, which department each customer visits, catalogue orders,
## returns of cash on shipment, reputation drift, the auto-play heuristic, win/loss — is
## a pure function of (state, day, seeded RNG). The same seed + the same scripted
## actions always yield a BYTE-IDENTICAL store after N days. No Godot node dependency:
## this class is fully headless-testable. GameManager owns one instance and adds the
## autoload ABI + save; store_floor.gd only reads state + forwards a player's action.
##
## MONEY DISCIPLINE (why conservation holds): every mutation of `cash` goes through
## _apply_cash(delta, category) which also folds delta into _cat_totals. The invariant
## cash == _start_cash + sum(_cat_totals.values()) holds at all times — no code path may
## touch `cash` directly. All money is INTEGER dollars, so replays and save round-trips
## are exact; reputation / demand / age are floats (they never touch the cash ledger).
##
## INVENTORY DISCIPLINE (why the unit invariant holds): every unit is accounted for. For
## each product line, _purchased == _on_hand + in_transit + _consumed at ALL times —
## restock adds to purchased+on_hand, an in-store sale moves on_hand→consumed, a
## catalogue order moves on_hand→in-transit (a pending shipment), and a shipment moves
## in-transit→consumed. Liquidation moves on_hand→consumed. No unit is ever minted or
## lost outside these named transitions.

# =====================================================================
#  Determinism helpers (FNV-1a, 63-bit masked) + float quantiser
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
const YEAR_DAYS: int = 360   ## twelve 30-day months — a clean seasonal wrap.

# =====================================================================
#  Departments (8 — a big-box multi-department retailer)
# =====================================================================
const DEPT_NAME: PackedStringArray = [
	"Apparel", "Electronics", "Toys", "Appliances",
	"Home & Garden", "Automotive", "Jewelry", "Sporting Goods",
]
const D_APPAREL: int = 0
const D_ELECTRONICS: int = 1
const D_TOYS: int = 2
const D_APPLIANCES: int = 3
const D_HOMEGARDEN: int = 4
const D_AUTOMOTIVE: int = 5
const D_JEWELRY: int = 6
const D_SPORTING: int = 7
const DEPT_COUNT: int = 8

## Seasonal demand curve PARAMETERS per department — a list of Gaussian bumps
## [center_day_of_year, width_days, amplitude]. season(dept, day) is COMPUTED from these
## via a wrapped-Gaussian formula (see season_mult); this is NOT a per-day lookup table.
## Day 0 == Jan 1, so day-of-year 44 ≈ Valentine's, 135 ≈ spring, 225 ≈ back-to-school,
## 345 ≈ mid-December.
const SEASON_BUMPS: Array = [
	[[225.0, 25.0, 0.6], [345.0, 20.0, 0.5]],                    # Apparel: back-to-school + Christmas
	[[340.0, 22.0, 1.2], [225.0, 20.0, 0.4]],                    # Electronics: Christmas + back-to-school
	[[345.0, 18.0, 1.6], [180.0, 30.0, 0.2]],                    # Toys: huge Christmas + small summer
	[[120.0, 35.0, 0.4], [330.0, 18.0, 0.5]],                    # Appliances: spring + Black-Friday
	[[135.0, 45.0, 1.1], [270.0, 30.0, 0.3]],                    # Home & Garden: spring/summer + fall
	[[180.0, 45.0, 0.6], [20.0, 30.0, 0.4]],                     # Automotive: summer road-trip + winter batteries
	[[44.0, 12.0, 1.0], [130.0, 12.0, 0.5], [348.0, 15.0, 1.3]], # Jewelry: Valentine + Mother's Day + Christmas
	[[165.0, 50.0, 0.7], [345.0, 18.0, 0.5]],                    # Sporting Goods: summer + Christmas
]

## The catalogue's own seasonal effectiveness (the spring "big book" + the Christmas
## "wish book") — same wrapped-Gaussian form, used to modulate mail-order demand.
const CATALOGUE_BUMPS: Array = [
	[135.0, 40.0, 0.8],   # spring big book
	[340.0, 25.0, 1.4],   # Christmas wish book
]

# =====================================================================
#  Product lines (32 — four per department). Each: name, department, per-unit COST,
#  base SHELF PRICE (> cost => margin), and a baseline DEMAND weight. Reference data as
#  hardcoded constants, never a DB table. Index i == line id.
# =====================================================================
const LINE_NAME: PackedStringArray = [
	"Menswear", "Womenswear", "Childrenswear", "Footwear",
	"Televisions", "Stereo Systems", "Home Computers", "Cameras",
	"Action Figures", "Board Games", "Dolls", "Bicycles",
	"Refrigerators", "Washers", "Ranges", "Vacuums",
	"Furniture", "Bedding", "Lawn Mowers", "Garden Tools",
	"Tires", "Batteries", "Car Stereos", "Auto Tools",
	"Watches", "Diamond Rings", "Necklaces", "Earrings",
	"Exercise Equipment", "Fishing Gear", "Camping Gear", "Team Sports",
]
const LINE_DEPT: PackedInt32Array = [
	D_APPAREL, D_APPAREL, D_APPAREL, D_APPAREL,
	D_ELECTRONICS, D_ELECTRONICS, D_ELECTRONICS, D_ELECTRONICS,
	D_TOYS, D_TOYS, D_TOYS, D_TOYS,
	D_APPLIANCES, D_APPLIANCES, D_APPLIANCES, D_APPLIANCES,
	D_HOMEGARDEN, D_HOMEGARDEN, D_HOMEGARDEN, D_HOMEGARDEN,
	D_AUTOMOTIVE, D_AUTOMOTIVE, D_AUTOMOTIVE, D_AUTOMOTIVE,
	D_JEWELRY, D_JEWELRY, D_JEWELRY, D_JEWELRY,
	D_SPORTING, D_SPORTING, D_SPORTING, D_SPORTING,
]
const LINE_COST: PackedInt32Array = [
	22, 24, 14, 28,
	240, 160, 300, 90,
	5, 8, 9, 60,
	320, 260, 240, 55,
	120, 30, 110, 12,
	35, 28, 70, 18,
	45, 200, 60, 30,
	85, 25, 40, 15,
]
const LINE_PRICE: PackedInt32Array = [
	40, 46, 26, 52,
	360, 250, 440, 150,
	11, 17, 19, 105,
	460, 380, 350, 95,
	200, 55, 185, 24,
	62, 50, 120, 34,
	110, 480, 150, 78,
	145, 46, 72, 29,
]
const LINE_BASE_DEMAND: PackedFloat32Array = [
	2.4, 2.8, 2.0, 2.2,
	1.6, 1.5, 1.2, 1.4,
	2.6, 2.2, 2.3, 1.3,
	1.0, 1.1, 0.9, 1.6,
	1.4, 1.9, 1.2, 2.0,
	1.8, 1.7, 1.3, 1.9,
	1.7, 0.9, 1.5, 1.8,
	1.3, 1.6, 1.5, 1.9,
]
const LINE_COUNT: int = 32

# =====================================================================
#  Default tuning (auditable; overridable via a config dict in setup)
# =====================================================================
const DEFAULTS: Dictionary = {
	"policy": "balanced",           ## auto-play flavour: "balanced" | "aggressive"
	"start_cash": 40000,
	"initial_debt": 0,
	"base_traffic": 28,             ## baseline daily walk-ins before modifiers
	"growth_goal": 120000,          ## WIN = starting net worth + this
	"max_days": 720,                ## hard cap — guarantees termination (two seasonal years)
	"overhead": 1500,               ## $ per day store rent + utilities + insurance
	"wage": 26,                     ## $ per day per staff member
	"throughput_per_staff": 40,     ## customers one staff member serves per day (per dept)
	"max_staff_total": 18,          ## total headcount across all departments
	"start_staff_each": 1,          ## staff per department at open
	"floor_total": 80,              ## total floor-space units to allocate across departments
	"start_space_each": 10,         ## floor-space per department at open (8*10 == 80)
	"marketing_cost": 2500,
	"marketing_days": 14,
	"marketing_mult": 1.5,
	"catalogue_cost": 3000,         ## up-front print cost to PUBLISH a catalogue
	"catalogue_days": 90,           ## how long a published catalogue keeps drawing orders
	"catalogue_reach": 1.0,         ## reach multiplier on mail-order demand
	"base_catalogue_demand": 18,    ## baseline daily mail-order buyers while active
	"catalogue_lead_time": 5,       ## days from order to SHIPMENT (revenue lands then)
	"catalogue_fulfill_cost": 2,    ## $ per shipped order (pick/pack/postage)
	"catalogue_capacity": 32,       ## max mail-order units the warehouse ships/day
	"markdown_elasticity": 1.4,     ## how strongly a markdown lifts a line's demand pull
	"max_markdown_bp": 6000,        ## deepest markdown, basis points (60%)
	"markdown_age_threshold": 40,   ## age (days) at which auto-play marks a line down
	"restock_coverage": 6.0,        ## auto-play target ≈ current demand * this
	"interest_bp": 100,             ## monthly loan interest, basis points (1.00%)
	"max_debt": 40000,
	"bankruptcy_floor": -8000,      ## cash below this…
	"bankruptcy_patience": 45,      ## …for this many consecutive days => LOSE
	"rep_start": 45.0,
	"rep_drift": 0.10,              ## fraction of the gap to target closed per day
	"service_k": 0.010,             ## each staff member lifts foot traffic by this fraction
	"salvage_frac_num": 1,          ## liquidation recovers cost * num/den in cash
	"salvage_frac_den": 2,
	"asset_frac_num": 1,            ## inventory asset value == cost * num/den (depreciated)
	"asset_frac_den": 2,
}

# =====================================================================
#  Tuning (resolved from DEFAULTS + config in setup)
# =====================================================================
var _policy: String = "balanced"
var base_traffic: int = 150
var growth_goal: int = 60000
var max_days: int = 720
var overhead: int = 300
var wage: int = 22
var throughput_per_staff: int = 40
var max_staff_total: int = 24
var floor_total: int = 80
var marketing_cost: int = 2500
var marketing_span: int = 14
var marketing_mult: float = 1.5
var catalogue_cost: int = 3000
var catalogue_span: int = 90
var catalogue_reach: float = 1.0
var base_catalogue_demand: int = 55
var catalogue_lead_time: int = 5
var catalogue_fulfill_cost: int = 2
var catalogue_capacity: int = 90
var markdown_elasticity: float = 1.4
var max_markdown_bp: int = 6000
var markdown_age_threshold: int = 40
var restock_coverage: float = 6.0
var interest_bp: int = 100
var max_debt: int = 40000
var bankruptcy_floor: int = -8000
var bankruptcy_patience: int = 45
var rep_drift: float = 0.10
var service_k: float = 0.010
var salvage_frac_num: int = 1
var salvage_frac_den: int = 2
var asset_frac_num: int = 1
var asset_frac_den: int = 2

# =====================================================================
#  State
# =====================================================================
var day: int = 0
var outcome: int = ONGOING
var cash: int = 0
var debt: int = 0
var reputation: float = 45.0
var marketing_left: int = 0
var catalogue_left: int = 0
var catalogues_published: int = 0
var bankruptcy_days: int = 0
var win_target: int = 0
var illegal_attempts: int = 0

# Most-recent-day telemetry (info + probes; folded into no ledger).
var last_traffic: int = 0
var last_instore_sales: int = 0
var last_stockouts: int = 0
var last_turned_away: int = 0
var last_catalogue_orders: int = 0
var last_catalogue_shipped: int = 0
var last_catalogue_stockouts: int = 0
var last_instore_revenue: int = 0
var last_catalogue_revenue: int = 0
var last_income: int = 0

var _seed: int = 0
var _start_cash: int = 0

# Per-department levers.
var _staff: PackedInt32Array = PackedInt32Array()    ## staff assigned to each department
var _space: PackedInt32Array = PackedInt32Array()    ## floor-space units per department

# Per-line inventory + aging + markdown.
var _on_hand: PackedInt32Array = PackedInt32Array()  ## units on hand (shelf + backroom)
var _purchased: PackedInt32Array = PackedInt32Array()## cumulative units ever bought
var _consumed: PackedInt32Array = PackedInt32Array() ## cumulative units sold/shipped/liquidated
var _markdown: PackedInt32Array = PackedInt32Array() ## discount basis points per line
var _age: PackedFloat32Array = PackedFloat32Array()  ## average age (days) of on-hand stock
var _day_sales: PackedInt32Array = PackedInt32Array()      ## in-store units sold today, per line
var _day_stockouts: PackedInt32Array = PackedInt32Array()  ## in-store stockouts today, per line

# Catalogue shipment queue (in-transit orders) — parallel arrays, order-stable.
var _ship_line: PackedInt32Array = PackedInt32Array()
var _ship_day: PackedInt32Array = PackedInt32Array()   ## day the order ships (revenue lands)
var _ship_rev: PackedInt32Array = PackedInt32Array()   ## locked-in revenue for the order

# Money ledger — every cash delta folded by category.
var _cat_totals: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# =====================================================================
#  Lifecycle
# =====================================================================

## Build a fresh store. seed == 0 → randomised; any other value is deterministic.
## `config` overrides any DEFAULTS key (used to make win-friendly / harsh runs).
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	var cfg: Dictionary = DEFAULTS.duplicate(true)
	for k in config.keys():
		cfg[k] = config[k]

	_policy = String(cfg["policy"])
	base_traffic = maxi(0, int(cfg["base_traffic"]))
	growth_goal = int(cfg["growth_goal"])
	max_days = maxi(1, int(cfg["max_days"]))
	overhead = int(cfg["overhead"])
	wage = int(cfg["wage"])
	throughput_per_staff = maxi(1, int(cfg["throughput_per_staff"]))
	max_staff_total = maxi(0, int(cfg["max_staff_total"]))
	floor_total = maxi(DEPT_COUNT, int(cfg["floor_total"]))
	marketing_cost = int(cfg["marketing_cost"])
	marketing_span = maxi(1, int(cfg["marketing_days"]))
	marketing_mult = float(cfg["marketing_mult"])
	catalogue_cost = int(cfg["catalogue_cost"])
	catalogue_span = maxi(1, int(cfg["catalogue_days"]))
	catalogue_reach = float(cfg["catalogue_reach"])
	base_catalogue_demand = maxi(0, int(cfg["base_catalogue_demand"]))
	catalogue_lead_time = maxi(1, int(cfg["catalogue_lead_time"]))
	catalogue_fulfill_cost = int(cfg["catalogue_fulfill_cost"])
	catalogue_capacity = maxi(0, int(cfg["catalogue_capacity"]))
	markdown_elasticity = float(cfg["markdown_elasticity"])
	max_markdown_bp = clampi(int(cfg["max_markdown_bp"]), 0, 9000)
	markdown_age_threshold = maxi(1, int(cfg["markdown_age_threshold"]))
	restock_coverage = float(cfg["restock_coverage"])
	interest_bp = int(cfg["interest_bp"])
	max_debt = int(cfg["max_debt"])
	bankruptcy_floor = int(cfg["bankruptcy_floor"])
	bankruptcy_patience = maxi(1, int(cfg["bankruptcy_patience"]))
	rep_drift = float(cfg["rep_drift"])
	service_k = float(cfg["service_k"])
	salvage_frac_num = int(cfg["salvage_frac_num"])
	salvage_frac_den = maxi(1, int(cfg["salvage_frac_den"]))
	asset_frac_num = int(cfg["asset_frac_num"])
	asset_frac_den = maxi(1, int(cfg["asset_frac_den"]))

	day = 0
	outcome = ONGOING
	reputation = float(cfg["rep_start"])
	marketing_left = 0
	catalogue_left = 0
	catalogues_published = 0
	bankruptcy_days = 0
	illegal_attempts = 0
	last_traffic = 0
	last_instore_sales = 0
	last_stockouts = 0
	last_turned_away = 0
	last_catalogue_orders = 0
	last_catalogue_shipped = 0
	last_catalogue_stockouts = 0
	last_instore_revenue = 0
	last_catalogue_revenue = 0
	last_income = 0

	_seed = seed_value
	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

	# Per-department levers.
	var start_staff_each: int = int(cfg["start_staff_each"])
	var start_space_each: int = int(cfg["start_space_each"])
	_staff = PackedInt32Array()
	_space = PackedInt32Array()
	_staff.resize(DEPT_COUNT)
	_space.resize(DEPT_COUNT)
	for d in DEPT_COUNT:
		_staff[d] = start_staff_each
		_space[d] = start_space_each
	# Clamp the opening staff/space to their global budgets deterministically.
	while _total_staff() > max_staff_total:
		var hi_s: int = _highest_staff_dept()
		if _staff[hi_s] <= 0:
			break
		_staff[hi_s] -= 1
	while _total_space() > floor_total:
		var hi_p: int = _highest_space_dept()
		if _space[hi_p] <= 0:
			break
		_space[hi_p] -= 1

	# Per-line inventory + aging + markdown + day telemetry.
	_on_hand = PackedInt32Array()
	_purchased = PackedInt32Array()
	_consumed = PackedInt32Array()
	_markdown = PackedInt32Array()
	_age = PackedFloat32Array()
	_day_sales = PackedInt32Array()
	_day_stockouts = PackedInt32Array()
	_on_hand.resize(LINE_COUNT)
	_purchased.resize(LINE_COUNT)
	_consumed.resize(LINE_COUNT)
	_markdown.resize(LINE_COUNT)
	_age.resize(LINE_COUNT)
	_day_sales.resize(LINE_COUNT)
	_day_stockouts.resize(LINE_COUNT)
	for i in LINE_COUNT:
		_on_hand[i] = 0
		_purchased[i] = 0
		_consumed[i] = 0
		_markdown[i] = 0
		_age[i] = 0.0
		_day_sales[i] = 0
		_day_stockouts[i] = 0

	_ship_line = PackedInt32Array()
	_ship_day = PackedInt32Array()
	_ship_rev = PackedInt32Array()

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


## Every ledger category that has seen a flow — lets tests confirm money only ever
## moves through DEFINED, named flows (no undefined path minted cash).
func category_keys() -> Array:
	return _cat_totals.keys()


## The conservation invariant: cash equals the sum of every recorded ledger delta
## (starting cash is itself a ledger entry, "seed_capital"). True by construction — the
## probe recomputes it to prove no path bypasses the ledger.
func conservation_ok() -> bool:
	var s: int = 0
	for k in _cat_totals.keys():
		s += int(_cat_totals[k])
	return cash == s


# =====================================================================
#  Seasonal demand — the wrapped-Gaussian season curve (a real formula)
# =====================================================================

## Shortest distance between two days on the 360-day ring.
func _ring_dist(a: float, b: float) -> float:
	var raw: float = absf(a - b)
	return minf(raw, float(YEAR_DAYS) - raw)


## A department's seasonal demand multiplier on a given day. Base 1.0 plus a sum of
## Gaussian bumps parameterised in SEASON_BUMPS — COMPUTED, not looked up. Always >= 1.
func season_mult(dept: int, at_day: int) -> float:
	if dept < 0 or dept >= DEPT_COUNT:
		return 1.0
	var doy: float = float(((at_day % YEAR_DAYS) + YEAR_DAYS) % YEAR_DAYS)
	var m: float = 1.0
	var bumps: Array = SEASON_BUMPS[dept]
	for b in bumps:
		var center: float = float(b[0])
		var width: float = float(b[1])
		var amp: float = float(b[2])
		var dist: float = _ring_dist(doy, center)
		m += amp * exp(-(dist * dist) / (2.0 * width * width))
	return m


## The catalogue's own seasonal effectiveness on a given day (spring + Christmas books).
func catalogue_season(at_day: int) -> float:
	var doy: float = float(((at_day % YEAR_DAYS) + YEAR_DAYS) % YEAR_DAYS)
	var m: float = 1.0
	for b in CATALOGUE_BUMPS:
		var center: float = float(b[0])
		var width: float = float(b[1])
		var amp: float = float(b[2])
		var dist: float = _ring_dist(doy, center)
		m += amp * exp(-(dist * dist) / (2.0 * width * width))
	return m


## The overall shopping-season multiplier (mean of the departments) — drives foot traffic.
func season_total(at_day: int) -> float:
	var s: float = 0.0
	for d in DEPT_COUNT:
		s += season_mult(d, at_day)
	return s / float(DEPT_COUNT)


## A line's markdown pull multiplier (>= 1): a deeper markdown attracts more buyers.
func markdown_boost(line: int) -> float:
	return 1.0 + markdown_elasticity * (float(_markdown[line]) / 10000.0)


## A product line's demand weight on a given day: baseline * its department's season *
## its markdown pull. The single formula that drives BOTH the floor and the catalogue.
func demand(line: int, at_day: int) -> float:
	if line < 0 or line >= LINE_COUNT:
		return 0.0
	return LINE_BASE_DEMAND[line] * season_mult(LINE_DEPT[line], at_day) * markdown_boost(line)


## A department's total demand weight (sum over its lines) on a given day.
func dept_demand(dept: int, at_day: int) -> float:
	var s: float = 0.0
	for i in LINE_COUNT:
		if LINE_DEPT[i] == dept:
			s += demand(i, at_day)
	return s


# =====================================================================
#  Pricing + derived queries
# =====================================================================

## The current shelf price of a line after its markdown (integer dollars).
func effective_price(line: int) -> int:
	return LINE_PRICE[line] * (10000 - _markdown[line]) / 10000


## Per-unit margin at the current (marked-down) price — can go negative on deep clearance.
func unit_margin(line: int) -> int:
	return effective_price(line) - LINE_COST[line]


func line_count() -> int:
	return LINE_COUNT

func dept_count() -> int:
	return DEPT_COUNT

func line_on_hand(line: int) -> int:
	return _on_hand[line]

func line_in_transit(line: int) -> int:
	var c: int = 0
	for i in _ship_line.size():
		if _ship_line[i] == line:
			c += 1
	return c

func line_purchased(line: int) -> int:
	return _purchased[line]

func line_consumed(line: int) -> int:
	return _consumed[line]

func line_markdown_bp(line: int) -> int:
	return _markdown[line]

func line_age(line: int) -> float:
	return _age[line]

func line_day_sales(line: int) -> int:
	return _day_sales[line]

func line_day_stockouts(line: int) -> int:
	return _day_stockouts[line]

func dept_staff(dept: int) -> int:
	return _staff[dept]

func dept_space(dept: int) -> int:
	return _space[dept]

func dept_on_hand(dept: int) -> int:
	var c: int = 0
	for i in LINE_COUNT:
		if LINE_DEPT[i] == dept:
			c += _on_hand[i]
	return c

func dept_day_sales(dept: int) -> int:
	var c: int = 0
	for i in LINE_COUNT:
		if LINE_DEPT[i] == dept:
			c += _day_sales[i]
	return c

func _total_staff() -> int:
	var c: int = 0
	for d in DEPT_COUNT:
		c += _staff[d]
	return c

func _total_space() -> int:
	var c: int = 0
	for d in DEPT_COUNT:
		c += _space[d]
	return c

func total_staff() -> int:
	return _total_staff()

func total_space() -> int:
	return _total_space()

func active_shipments() -> int:
	return _ship_line.size()

func total_on_hand() -> int:
	var c: int = 0
	for i in _on_hand.size():
		c += _on_hand[i]
	return c

func total_in_transit() -> int:
	return _ship_line.size()

func _highest_staff_dept() -> int:
	var best: int = 0
	for d in range(1, DEPT_COUNT):
		if _staff[d] > _staff[best]:
			best = d
	return best

func _highest_space_dept() -> int:
	var best: int = 0
	for d in range(1, DEPT_COUNT):
		if _space[d] > _space[best]:
			best = d
	return best

## Depreciated asset value of one unit of a line.
func unit_asset_value(line: int) -> int:
	return LINE_COST[line] * asset_frac_num / asset_frac_den

## Cash recovered per unit when liquidating a line to a jobber.
func unit_salvage_value(line: int) -> int:
	return LINE_COST[line] * salvage_frac_num / salvage_frac_den

## Total inventory asset value: every unit not yet consumed (on hand + in transit),
## valued at its depreciated cost.
func inventory_value() -> int:
	var v: int = 0
	for i in LINE_COUNT:
		v += _on_hand[i] * unit_asset_value(i)
	for i in _ship_line.size():
		v += unit_asset_value(_ship_line[i])
	return v

func net_worth() -> int:
	return cash + inventory_value() - debt

## Fill rate over the most recent day (in-store): sales / (sales + stockouts).
func fill_rate() -> float:
	var seen: int = last_instore_sales + last_stockouts
	if seen <= 0:
		return 1.0
	return float(last_instore_sales) / float(seen)


# =====================================================================
#  Legality — actions are is_legal-gated; illegal ones never mutate state
# =====================================================================

func _valid_line(line: int) -> bool:
	return line >= 0 and line < LINE_COUNT

func _valid_dept(dept: int) -> bool:
	return dept >= 0 and dept < DEPT_COUNT

func can_restock(line: int, qty: int) -> bool:
	if outcome != ONGOING or not _valid_line(line):
		return false
	if qty <= 0:
		return false
	return cash >= qty * LINE_COST[line]

func can_liquidate(line: int, qty: int) -> bool:
	return outcome == ONGOING and _valid_line(line) and qty > 0 and _on_hand[line] >= qty

func can_set_markdown(line: int, bp: int) -> bool:
	return outcome == ONGOING and _valid_line(line) and bp >= 0 and bp <= max_markdown_bp

func can_set_dept_staff(dept: int, count: int) -> bool:
	if outcome != ONGOING or not _valid_dept(dept) or count < 0:
		return false
	return _total_staff() - _staff[dept] + count <= max_staff_total

func can_set_dept_space(dept: int, units: int) -> bool:
	if outcome != ONGOING or not _valid_dept(dept) or units < 0:
		return false
	return _total_space() - _space[dept] + units <= floor_total

func can_publish_catalogue() -> bool:
	return outcome == ONGOING and catalogue_left == 0 and cash >= catalogue_cost

func can_run_marketing() -> bool:
	return outcome == ONGOING and cash >= marketing_cost

func can_take_loan(amount: int) -> bool:
	return outcome == ONGOING and amount > 0 and debt + amount <= max_debt

func can_repay_loan(amount: int) -> bool:
	return outcome == ONGOING and amount > 0 and debt > 0 and cash >= amount


# =====================================================================
#  Actions (each returns true on success; false leaves state untouched)
# =====================================================================

## Buy `qty` units of a product line into on-hand stock. Cash → depreciated inventory
## asset (net worth dips by the depreciation only). Fresh units pull the line's average
## age down toward zero (weighted by quantity).
func restock(line: int, qty: int) -> bool:
	if not can_restock(line, qty):
		illegal_attempts += 1
		return false
	var cost: int = qty * LINE_COST[line]
	_apply_cash(-cost, "restock")
	var prior: int = _on_hand[line]
	var blended: float = 0.0
	if prior + qty > 0:
		blended = (_age[line] * float(prior)) / float(prior + qty)
	_age[line] = blended
	_on_hand[line] += qty
	_purchased[line] += qty
	return true


## Liquidate `qty` on-hand units of a line to a jobber, recovering their salvage value.
## Units leave stock (consumed) — a last resort to raise cash on dead inventory.
func liquidate(line: int, qty: int) -> bool:
	if not can_liquidate(line, qty):
		illegal_attempts += 1
		return false
	_on_hand[line] -= qty
	_consumed[line] += qty
	_apply_cash(qty * unit_salvage_value(line), "liquidation")
	return true


## Set a line's markdown (basis points off the shelf price). Cuts margin, lifts demand.
func set_markdown(line: int, bp: int) -> bool:
	if not can_set_markdown(line, bp):
		illegal_attempts += 1
		return false
	_markdown[line] = bp
	return true


func set_dept_staff(dept: int, count: int) -> bool:
	if not can_set_dept_staff(dept, count):
		illegal_attempts += 1
		return false
	_staff[dept] = count
	return true


func hire_staff(dept: int, count: int) -> bool:
	return set_dept_staff(dept, _staff[dept] + count)


func set_dept_space(dept: int, units: int) -> bool:
	if not can_set_dept_space(dept, units):
		illegal_attempts += 1
		return false
	_space[dept] = units
	return true


## PUBLISH a seasonal catalogue: pay the print cost up front and open the mail-order
## channel for `catalogue_span` days.
func publish_catalogue() -> bool:
	if not can_publish_catalogue():
		illegal_attempts += 1
		return false
	_apply_cash(-catalogue_cost, "catalogue_print")
	catalogue_left = catalogue_span
	catalogues_published += 1
	return true


func run_marketing() -> bool:
	if not can_run_marketing():
		illegal_attempts += 1
		return false
	_apply_cash(-marketing_cost, "marketing")
	marketing_left = marketing_span
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
#  The daily tick — shipments, floor economy, catalogue, bills, time
# =====================================================================

## Advance the store one day. Returns the player's signed cash delta for the day.
func tick_day() -> int:
	if outcome != ONGOING:
		return 0
	var cash_before: int = cash

	_process_shipments()            # catalogue orders that ship today (revenue + fulfillment)
	var traffic: int = _generate_traffic()
	last_traffic = traffic
	_serve_instore(traffic)         # floor sales (income), stockouts, staff throughput gating
	_generate_catalogue()           # mail-order orders (reserve stock into transit)
	_pay_daily_bills()              # overhead + wages
	if marketing_left > 0:
		marketing_left -= 1
	if catalogue_left > 0:
		catalogue_left -= 1
	_age_inventory()                # aging of standing stock
	_drift_reputation()

	day += 1
	if day % MONTH_DAYS == 0:
		_close_month()              # loan interest

	_judge()

	last_income = cash - cash_before
	return last_income


## Ship every catalogue order scheduled to arrive today (stable order): collect the
## locked-in revenue, pay the per-order fulfillment fee, and consume the unit.
func _process_shipments() -> void:
	last_catalogue_shipped = 0
	last_catalogue_revenue = 0
	if _ship_line.is_empty():
		return
	var keep_line: PackedInt32Array = PackedInt32Array()
	var keep_day: PackedInt32Array = PackedInt32Array()
	var keep_rev: PackedInt32Array = PackedInt32Array()
	for i in _ship_line.size():
		if _ship_day[i] != day:
			keep_line.append(_ship_line[i])
			keep_day.append(_ship_day[i])
			keep_rev.append(_ship_rev[i])
			continue
		var ln: int = _ship_line[i]
		var rev: int = _ship_rev[i]
		_apply_cash(rev, "catalogue_revenue")
		if catalogue_fulfill_cost > 0:
			_apply_cash(-catalogue_fulfill_cost, "catalogue_fulfill")
		_consumed[ln] += 1          # the in-transit unit is delivered (leaves the store)
		last_catalogue_shipped += 1
		last_catalogue_revenue += rev
	_ship_line = keep_line
	_ship_day = keep_day
	_ship_rev = keep_rev


## Seeded foot traffic: base × reputation × marketing × overall season × staff presence.
func _generate_traffic() -> int:
	var rep_factor: float = 0.4 + reputation / 100.0
	var marketing_factor: float = marketing_mult if marketing_left > 0 else 1.0
	var season_factor: float = season_total(day)
	var service_factor: float = 1.0 + service_k * float(_total_staff())
	var noise: float = _rng.randf_range(0.9, 1.1)
	var t: float = float(base_traffic) * rep_factor * marketing_factor * season_factor * service_factor * noise
	return maxi(0, int(t))


## Serve the day's floor customers. Each customer visits a DEPARTMENT (weighted by that
## department's product-line demand × its floor space) and wants a specific line within
## it. Per-department STAFF THROUGHPUT caps how many that department can serve (the rest
## are TURNED AWAY). A served customer BUYS if the line has stock (→ revenue, on_hand
## consumed) — otherwise it's a STOCKOUT (lost sale + goodwill hit).
func _serve_instore(traffic: int) -> void:
	for i in LINE_COUNT:
		_day_sales[i] = 0
		_day_stockouts[i] = 0
	last_instore_sales = 0
	last_stockouts = 0
	last_turned_away = 0
	last_instore_revenue = 0
	if traffic <= 0:
		return

	# Remaining per-department serving capacity for the day.
	var cap: PackedInt32Array = PackedInt32Array()
	cap.resize(DEPT_COUNT)
	for d in DEPT_COUNT:
		cap[d] = _staff[d] * throughput_per_staff

	# Per-line pull weight = demand × its department's floor space (visibility).
	var weight: PackedFloat32Array = PackedFloat32Array()
	weight.resize(LINE_COUNT)
	var total_w: float = 0.0
	for i in LINE_COUNT:
		var w: float = demand(i, day) * float(maxi(0, _space[LINE_DEPT[i]]))
		weight[i] = w
		total_w += w
	if total_w <= 0.0:
		return

	for _c in traffic:
		var line: int = _weighted_pick(weight, total_w)
		if line < 0:
			continue
		var dept: int = LINE_DEPT[line]
		if cap[dept] <= 0:
			last_turned_away += 1
			continue
		cap[dept] -= 1
		if _on_hand[line] > 0:
			_on_hand[line] -= 1
			_consumed[line] += 1
			var price: int = effective_price(line)
			_apply_cash(price, "instore_revenue")
			last_instore_revenue += price
			_day_sales[line] += 1
			last_instore_sales += 1
		else:
			_day_stockouts[line] += 1
			last_stockouts += 1


## Mail-order: while a catalogue is active, a SECOND stream of buyers orders from the
## book. This demand is NOT gated by store foot traffic or floor staff — it reaches
## buyers the physical store never sees — only by the warehouse's daily capacity and by
## available inventory. Each order RESERVES a unit into transit (ships after the lead
## time); if the line is out of stock it's a catalogue stockout (lost, goodwill hit).
func _generate_catalogue() -> void:
	last_catalogue_orders = 0
	last_catalogue_stockouts = 0
	if catalogue_left <= 0:
		return

	var rep_factor: float = 0.4 + reputation / 100.0
	var cseason: float = catalogue_season(day)
	var noise: float = _rng.randf_range(0.9, 1.1)
	var raw: float = float(base_catalogue_demand) * cseason * catalogue_reach * rep_factor * noise
	var orders: int = mini(maxi(0, int(raw)), catalogue_capacity)
	if orders <= 0:
		return

	# Catalogue buyers want lines by their pure demand (no floor-space visibility term).
	var weight: PackedFloat32Array = PackedFloat32Array()
	weight.resize(LINE_COUNT)
	var total_w: float = 0.0
	for i in LINE_COUNT:
		var w: float = demand(i, day)
		weight[i] = w
		total_w += w
	if total_w <= 0.0:
		return

	for _o in orders:
		var line: int = _weighted_pick(weight, total_w)
		if line < 0:
			continue
		if _on_hand[line] > 0:
			_on_hand[line] -= 1                 # reserved out of on-hand into transit
			_ship_line.append(line)
			_ship_day.append(day + catalogue_lead_time)
			_ship_rev.append(effective_price(line))
			last_catalogue_orders += 1
		else:
			last_catalogue_stockouts += 1


## Weighted index draw over the pull weights using the seeded RNG.
func _weighted_pick(weight: PackedFloat32Array, total_w: float) -> int:
	var r: float = _rng.randf() * total_w
	var acc: float = 0.0
	for i in LINE_COUNT:
		acc += weight[i]
		if r < acc:
			return i
	for i in range(LINE_COUNT - 1, -1, -1):
		if weight[i] > 0.0:
			return i
	return -1


func _pay_daily_bills() -> void:
	if overhead > 0:
		_apply_cash(-overhead, "overhead")
	var wages: int = _total_staff() * wage
	if wages > 0:
		_apply_cash(-wages, "wages")


## Age standing stock: every line with units on hand gets one day older. (Fresh restock
## resets the blended age toward 0; markdowns clear old stock before it dead-weights.)
func _age_inventory() -> void:
	for i in LINE_COUNT:
		if _on_hand[i] > 0:
			_age[i] += 1.0
		else:
			_age[i] = 0.0


func _drift_reputation() -> void:
	var target: float = _target_reputation()
	reputation = clampf(reputation + (target - reputation) * rep_drift, 0.0, 100.0)


## Reputation the store trends toward: driven by in-stock rate (fill rate) and by
## SERVICE (the fraction of visitors actually served rather than turned away for lack of
## staff), with a value bump for active markdowns (fair pricing) and a drag for stockouts.
func _target_reputation() -> float:
	var t: float = 20.0
	t += 40.0 * fill_rate()
	var seen: int = last_instore_sales + last_stockouts + last_turned_away
	var service_ratio: float = 1.0
	if seen > 0:
		service_ratio = float(last_instore_sales + last_stockouts) / float(seen)
	t += 22.0 * service_ratio
	t += minf(8.0, 0.4 * float(_markdown_lines()))
	if last_stockouts > 0:
		t -= 6.0
	return clampf(t, 0.0, 100.0)


## How many lines currently carry an active markdown (a small "value" reputation input).
func _markdown_lines() -> int:
	var c: int = 0
	for i in LINE_COUNT:
		if _markdown[i] > 0:
			c += 1
	return c


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

## Take one day's worth of prudent decisions, then advance the day. Allocates staff and
## floor space toward the departments whose SEASON is peaking, stocks each line ahead of
## its demand, marks down aging stock to clear it, publishes a catalogue when the book's
## season is strong, runs marketing when reputation sags, and borrows to stay liquid.
## Pure & deterministic given the seed. Returns the day's cash delta.
func auto_play_step() -> int:
	if outcome != ONGOING:
		return 0
	var aggressive: bool = _policy == "aggressive"

	# 1) Allocate STAFF toward the departments with the strongest current demand.
	_allocate_by_weight(true, int(float(max_staff_total) * (0.85 if aggressive else 0.65)))
	# 2) Allocate FLOOR SPACE the same way (uses the whole floor).
	_allocate_by_weight(false, floor_total)

	# 3) MARKDOWNS: clear lines whose stock has aged past the threshold and isn't moving;
	#    lift the markdown once a line turns fresh again.
	for i in LINE_COUNT:
		if _on_hand[i] > 0 and _age[i] >= float(markdown_age_threshold) and _day_sales[i] <= 0:
			if _markdown[i] < 4000:
				set_markdown(i, 4000)
		elif _age[i] <= 3.0 and _markdown[i] > 0:
			set_markdown(i, 0)

	# 4) Publish a CATALOGUE when the book's season is strong and cash is comfortable.
	if catalogue_left == 0 and catalogue_season(day) >= 1.35 and cash > catalogue_cost + 6000 and can_publish_catalogue():
		publish_catalogue()

	# 5) MARKETING push when reputation sags and cash is comfortable.
	if marketing_left == 0 and reputation < 55.0 and cash > marketing_cost + 8000 and can_run_marketing():
		run_marketing()

	# 6) RESTOCK every line toward a target sized to its current demand.
	var buffer: int = 4000 if aggressive else 7000
	for i in LINE_COUNT:
		var want: int = _auto_target_units(i)
		if _on_hand[i] >= want:
			continue
		var need: int = want - _on_hand[i]
		var cost: int = need * LINE_COST[i]
		if cash - cost > buffer and can_restock(i, need):
			restock(i, need)

	# 7) Draw a loan to stay liquid while still solvent.
	if cash < 2000 and net_worth() > 12000 and debt + 6000 <= max_debt and can_take_loan(6000):
		take_loan(6000)

	return tick_day()


## Deterministic per-line target on-hand under auto-play: proportional to CURRENT demand
## (so a line in season is stocked deep), scaled down for expensive lines whose capital
## turns slowly, and capped.
func _auto_target_units(line: int) -> int:
	var d: float = demand(line, day)
	var per: float = restock_coverage * (1.15 if _policy == "aggressive" else 1.0)
	var price_scale: float = clampf(120.0 / float(maxi(1, LINE_COST[line])), 0.25, 1.0)
	var target: int = int(round(d * per * price_scale))
	return clampi(target, 0, 60)


## Allocate a budget across departments in proportion to their current demand weight.
## `is_staff` picks the staff pool + setter; otherwise the floor-space pool + setter.
## Deterministic: largest-remainder rounding, applied in department order.
func _allocate_by_weight(is_staff: bool, budget: int) -> void:
	if budget <= 0:
		return
	var w: PackedFloat32Array = PackedFloat32Array()
	w.resize(DEPT_COUNT)
	var wsum: float = 0.0
	for d in DEPT_COUNT:
		var wd: float = dept_demand(d, day)
		w[d] = wd
		wsum += wd
	if wsum <= 0.0:
		return
	# Floor allocation, then hand out the remainder to the largest fractional parts.
	var alloc: PackedInt32Array = PackedInt32Array()
	alloc.resize(DEPT_COUNT)
	var frac: PackedFloat32Array = PackedFloat32Array()
	frac.resize(DEPT_COUNT)
	var used: int = 0
	for d in DEPT_COUNT:
		var exact: float = float(budget) * w[d] / wsum
		var base: int = int(floor(exact))
		alloc[d] = base
		frac[d] = exact - float(base)
		used += base
	var remainder: int = budget - used
	while remainder > 0:
		var best: int = -1
		var best_frac: float = -1.0
		for d in DEPT_COUNT:
			if frac[d] > best_frac:
				best_frac = frac[d]
				best = d
		if best < 0:
			break
		alloc[best] += 1
		frac[best] = -1.0
		remainder -= 1
	# Staff wants at least 1 per department; space may be 0 for a dead department.
	if is_staff:
		for d in DEPT_COUNT:
			set_dept_staff(d, maxi(1, alloc[d]))
	else:
		for d in DEPT_COUNT:
			set_dept_space(d, alloc[d])


## Run the whole game to a terminal outcome under the auto-play policy (bounded by
## max_days, so it always terminates). Returns the final outcome.
func auto_play_to_end() -> int:
	var guard: int = 0
	var hard_cap: int = max_days + 8
	while outcome == ONGOING and guard < hard_cap:
		auto_play_step()
		guard += 1
	return outcome


# =====================================================================
#  Determinism checksum — folds the WHOLE store state into one int
# =====================================================================

func _fold(h: int, v: int) -> int:
	h = (h ^ v) * FNV_PRIME
	return h & MASK63

func _qf(v: float) -> int:
	return int(round(v * 100.0))

## Order-stable checksum of the entire store: two engines are equal iff this matches.
func state_checksum() -> int:
	var h: int = FNV_OFFSET
	h = _fold(h, _seed)
	h = _fold(h, int(_rng.state & MASK63))
	h = _fold(h, day)
	h = _fold(h, outcome)
	h = _fold(h, cash)
	h = _fold(h, debt)
	h = _fold(h, _qf(reputation))
	h = _fold(h, marketing_left)
	h = _fold(h, catalogue_left)
	h = _fold(h, catalogues_published)
	h = _fold(h, bankruptcy_days)
	h = _fold(h, win_target)
	h = _fold(h, illegal_attempts)
	h = _fold(h, last_income)
	for d in DEPT_COUNT:
		h = _fold(h, _staff[d])
		h = _fold(h, _space[d])
	for i in LINE_COUNT:
		h = _fold(h, _on_hand[i])
		h = _fold(h, _purchased[i])
		h = _fold(h, _consumed[i])
		h = _fold(h, _markdown[i])
		h = _fold(h, _qf(_age[i]))
	for i in _ship_line.size():
		h = _fold(h, _ship_line[i])
		h = _fold(h, _ship_day[i])
		h = _fold(h, _ship_rev[i])
	for cat in ["seed_capital", "instore_revenue", "catalogue_revenue", "restock",
			"wages", "overhead", "marketing", "catalogue_print", "catalogue_fulfill",
			"interest", "loan_draw", "loan_repay", "liquidation"]:
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
		"reputation": reputation,
		"marketing_left": marketing_left,
		"catalogue_left": catalogue_left,
		"catalogues_published": catalogues_published,
		"bankruptcy_days": bankruptcy_days,
		"win_target": win_target,
		"illegal_attempts": illegal_attempts,
		"last_traffic": last_traffic,
		"last_instore_sales": last_instore_sales,
		"last_stockouts": last_stockouts,
		"last_turned_away": last_turned_away,
		"last_catalogue_orders": last_catalogue_orders,
		"last_catalogue_shipped": last_catalogue_shipped,
		"last_catalogue_stockouts": last_catalogue_stockouts,
		"last_instore_revenue": last_instore_revenue,
		"last_catalogue_revenue": last_catalogue_revenue,
		"last_income": last_income,
		"start_cash": _start_cash,
		"base_traffic": base_traffic,
		"growth_goal": growth_goal,
		"max_days": max_days,
		"overhead": overhead,
		"wage": wage,
		"throughput_per_staff": throughput_per_staff,
		"max_staff_total": max_staff_total,
		"floor_total": floor_total,
		"marketing_cost": marketing_cost,
		"marketing_span": marketing_span,
		"marketing_mult": marketing_mult,
		"catalogue_cost": catalogue_cost,
		"catalogue_span": catalogue_span,
		"catalogue_reach": catalogue_reach,
		"base_catalogue_demand": base_catalogue_demand,
		"catalogue_lead_time": catalogue_lead_time,
		"catalogue_fulfill_cost": catalogue_fulfill_cost,
		"catalogue_capacity": catalogue_capacity,
		"markdown_elasticity": markdown_elasticity,
		"max_markdown_bp": max_markdown_bp,
		"markdown_age_threshold": markdown_age_threshold,
		"restock_coverage": restock_coverage,
		"interest_bp": interest_bp,
		"max_debt": max_debt,
		"bankruptcy_floor": bankruptcy_floor,
		"bankruptcy_patience": bankruptcy_patience,
		"rep_drift": rep_drift,
		"service_k": service_k,
		"salvage_frac_num": salvage_frac_num,
		"salvage_frac_den": salvage_frac_den,
		"asset_frac_num": asset_frac_num,
		"asset_frac_den": asset_frac_den,
		"staff": _staff.duplicate(),
		"space": _space.duplicate(),
		"on_hand": _on_hand.duplicate(),
		"purchased": _purchased.duplicate(),
		"consumed": _consumed.duplicate(),
		"markdown": _markdown.duplicate(),
		"age": _age.duplicate(),
		"ship_line": _ship_line.duplicate(),
		"ship_day": _ship_day.duplicate(),
		"ship_rev": _ship_rev.duplicate(),
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
	reputation = float(data["reputation"])
	marketing_left = int(data["marketing_left"])
	catalogue_left = int(data["catalogue_left"])
	catalogues_published = int(data["catalogues_published"])
	bankruptcy_days = int(data["bankruptcy_days"])
	win_target = int(data["win_target"])
	illegal_attempts = int(data["illegal_attempts"])
	last_traffic = int(data["last_traffic"])
	last_instore_sales = int(data["last_instore_sales"])
	last_stockouts = int(data["last_stockouts"])
	last_turned_away = int(data["last_turned_away"])
	last_catalogue_orders = int(data["last_catalogue_orders"])
	last_catalogue_shipped = int(data["last_catalogue_shipped"])
	last_catalogue_stockouts = int(data["last_catalogue_stockouts"])
	last_instore_revenue = int(data["last_instore_revenue"])
	last_catalogue_revenue = int(data["last_catalogue_revenue"])
	last_income = int(data["last_income"])
	_start_cash = int(data["start_cash"])
	base_traffic = int(data["base_traffic"])
	growth_goal = int(data["growth_goal"])
	max_days = int(data["max_days"])
	overhead = int(data["overhead"])
	wage = int(data["wage"])
	throughput_per_staff = int(data["throughput_per_staff"])
	max_staff_total = int(data["max_staff_total"])
	floor_total = int(data["floor_total"])
	marketing_cost = int(data["marketing_cost"])
	marketing_span = int(data["marketing_span"])
	marketing_mult = float(data["marketing_mult"])
	catalogue_cost = int(data["catalogue_cost"])
	catalogue_span = int(data["catalogue_span"])
	catalogue_reach = float(data["catalogue_reach"])
	base_catalogue_demand = int(data["base_catalogue_demand"])
	catalogue_lead_time = int(data["catalogue_lead_time"])
	catalogue_fulfill_cost = int(data["catalogue_fulfill_cost"])
	catalogue_capacity = int(data["catalogue_capacity"])
	markdown_elasticity = float(data["markdown_elasticity"])
	max_markdown_bp = int(data["max_markdown_bp"])
	markdown_age_threshold = int(data["markdown_age_threshold"])
	restock_coverage = float(data["restock_coverage"])
	interest_bp = int(data["interest_bp"])
	max_debt = int(data["max_debt"])
	bankruptcy_floor = int(data["bankruptcy_floor"])
	bankruptcy_patience = int(data["bankruptcy_patience"])
	rep_drift = float(data["rep_drift"])
	service_k = float(data["service_k"])
	salvage_frac_num = int(data["salvage_frac_num"])
	salvage_frac_den = int(data["salvage_frac_den"])
	asset_frac_num = int(data["asset_frac_num"])
	asset_frac_den = int(data["asset_frac_den"])
	_staff = (data["staff"] as PackedInt32Array).duplicate()
	_space = (data["space"] as PackedInt32Array).duplicate()
	_on_hand = (data["on_hand"] as PackedInt32Array).duplicate()
	_purchased = (data["purchased"] as PackedInt32Array).duplicate()
	_consumed = (data["consumed"] as PackedInt32Array).duplicate()
	_markdown = (data["markdown"] as PackedInt32Array).duplicate()
	_age = (data["age"] as PackedFloat32Array).duplicate()
	_ship_line = (data["ship_line"] as PackedInt32Array).duplicate()
	_ship_day = (data["ship_day"] as PackedInt32Array).duplicate()
	_ship_rev = (data["ship_rev"] as PackedInt32Array).duplicate()
	# Rebuild per-line day telemetry (not persisted; recomputed shape).
	_day_sales = PackedInt32Array()
	_day_stockouts = PackedInt32Array()
	_day_sales.resize(LINE_COUNT)
	_day_stockouts.resize(LINE_COUNT)
	for i in LINE_COUNT:
		_day_sales[i] = 0
		_day_stockouts[i] = 0
	_cat_totals = (data["cat_totals"] as Dictionary).duplicate(true)
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(data["rng_seed"])
	_rng.state = int(data["rng_state"])


## A canonical, order-stable serialization for byte-identical comparison in tests.
func snapshot_string() -> String:
	return JSON.stringify(save_data())
