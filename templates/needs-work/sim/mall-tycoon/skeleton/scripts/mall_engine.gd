extends RefCounted
class_name MallEngine
## res://scripts/mall_engine.gd
## THE PURE ENGINE — a deterministic, seedable 80s SHOPPING-MALL management sim
## (Theme-Park / RollerCoaster-Tycoon / SimTower-of-retail lineage). You OWN the
## mall: a grid of leasable retail UNITS across several floors plus common areas.
## Each unit is EMPTY, LEASED to a tenant (steady rent, lower ceiling), or
## OWNER-OPERATED (you buy stock + hire staff for revenue−costs, higher ceiling
## and higher risk). Each day, seeded FOOT TRAFFIC is generated as a function of
## mall REPUTATION + AMENITIES + ANCHOR stores + MARKETING; customers distribute
## to occupied stores by appeal × location desirability and SPEND, producing
## store revenue. A month closes rent + bills. You grow CASH and NET WORTH; reach
## a net-worth goal to WIN, or bankrupt out to LOSE.
##
## Everything — traffic, customer distribution, every action's effect, tenant
## satisfaction + retention, reputation drift, the auto-play heuristic, win/loss —
## is a pure function of (state, day, seeded RNG). The same seed + the same
## scripted actions always yield a BYTE-IDENTICAL mall after N days. No Godot node
## dependency: this class is fully headless-testable. GameManager owns one
## instance and adds the autoload ABI + save; mall.gd only reads state + forwards
## a player's chosen action.
##
## MONEY DISCIPLINE (why conservation holds): every mutation of `cash` goes
## through _apply_cash(delta, category) which also folds delta into _cat_totals.
## The invariant cash == _start_cash + sum(_cat_totals.values()) holds at all
## times — no code path may touch `cash` directly. All money is INTEGER dollars,
## so replays and save round-trips are exact; reputation / desirability /
## satisfaction are floats (they never touch the cash ledger).
##
## TICK DISCIPLINE: tick_day() runs a fixed pipeline — generate traffic → serve
## customers (revenue, owner profit) → pay daily bills (maintenance, wages,
## amenity upkeep) → decay marketing → drift reputation → age tenant satisfaction
## and evict quitters → on a month boundary close rent + loan interest → judge
## win/loss → advance the day. Every stochastic choice draws from the SEEDED RNG
## whose state is saved, so replays are exact.

# =====================================================================
#  Unit state machine
# =====================================================================
const U_EMPTY := 0   ## vacant, leasable
const U_LEASED := 1  ## rented to a tenant — you collect rent, tenant keeps sales
const U_OWNER := 2   ## you operate it — you keep sales, pay stock + staff

# =====================================================================
#  Outcome
# =====================================================================
const ONGOING := 0
const WON := 1
const LOST := 2

# =====================================================================
#  Store catalogue (>= 8 generic 80s-mall store types)
#  Each: name, appeal (customer draw), spend (avg $/customer), rent (base
#  monthly), wholesale (owner cost per unit sold), anchor (pulls extra traffic).
# =====================================================================
const STORE_NAME: PackedStringArray = [
	"Record Store", "Arcade", "Video Rental", "Food Court", "Department Store",
	"Toy Store", "Electronics", "Apparel", "Bookstore",
]
const STORE_APPEAL: PackedFloat32Array = [7.0, 8.0, 6.0, 9.0, 10.0, 7.0, 8.0, 8.0, 5.0]
const STORE_SPEND: PackedInt32Array = [18, 12, 9, 14, 30, 16, 40, 28, 15]
const STORE_RENT: PackedInt32Array = [900, 1000, 700, 1100, 2500, 850, 1400, 1300, 650]
const STORE_WHOLESALE: PackedInt32Array = [10, 5, 4, 6, 18, 9, 26, 17, 8]
const STORE_ANCHOR: PackedInt32Array = [0, 0, 0, 0, 1, 0, 0, 0, 0]  ## Department Store is the anchor
const STORE_COUNT := 9

# =====================================================================
#  Amenity catalogue (>= 4) — each: name, cost, daily upkeep. Every amenity you
#  own lifts foot traffic and reputation. One of each type may be owned.
# =====================================================================
const AMENITY_NAME: PackedStringArray = ["Restrooms", "Decor", "Parking", "Security"]
const AMENITY_COST: PackedInt32Array = [1500, 2000, 4000, 3000]
const AMENITY_UPKEEP: PackedInt32Array = [5, 4, 8, 10]
const AMENITY_COUNT := 4

# =====================================================================
#  Default tuning (auditable; overridable via setup config)
# =====================================================================
const DEFAULTS := {
	"floors": 3,
	"cols": 6,
	"start_cash": 20000,
	"initial_debt": 0,
	"base_traffic": 300,
	"growth_goal": 80000,          ## WIN = start net worth + this
	"time_cap": 720,               ## days (24 months) to hit the goal
	"unit_value": 8000,            ## base property value of a max-desirability unit
	"open_cost": 3000,             ## fit-out to owner-operate a unit
	"staff_wage": 25,              ## $/day per staff member (owner stores)
	"maintenance": 8,              ## $/day per occupied unit
	"marketing_cost": 1500,
	"marketing_days": 14,
	"marketing_mult": 1.6,
	"interest_bp": 100,            ## monthly loan interest, basis points (1.00%)
	"max_debt": 50000,
	"bankruptcy_floor": -8000,     ## cash below this…
	"bankruptcy_patience": 60,     ## …for this many consecutive days => LOSE
	"rep_start": 40.0,
	"rep_drift": 0.10,             ## fraction of the gap to target closed per day
	"evict_hit": 8.0,              ## reputation lost on an eviction / tenant leaving
	"sat_start": 60.0,
	"sat_up": 1.5,                 ## satisfaction gained on a good day
	"sat_down": 2.5,               ## satisfaction lost on a bad day
	"leave_threshold": 20.0,       ## satisfaction below this is "unhappy"
	"leave_patience": 20,          ## consecutive unhappy days before a tenant quits
}
const MONTH_DAYS := 30

# =====================================================================
#  Tuning (resolved from DEFAULTS + config in setup)
# =====================================================================
var floors: int = 3
var cols: int = 6
var base_traffic: int = 300
var growth_goal: int = 80000
var time_cap: int = 720
var open_cost: int = 3000
var staff_wage: int = 25
var maintenance: int = 8
var marketing_cost: int = 1500
var marketing_span: int = 14
var marketing_mult: float = 1.6
var interest_bp: int = 100
var max_debt: int = 50000
var bankruptcy_floor: int = -8000
var bankruptcy_patience: int = 60
var rep_drift: float = 0.10
var evict_hit: float = 8.0
var sat_start: float = 60.0
var sat_up: float = 1.5
var sat_down: float = 2.5
var leave_threshold: float = 20.0
var leave_patience: int = 20

# =====================================================================
#  State
# =====================================================================
var day: int = 0
var outcome: int = ONGOING
var cash: int = 0
var debt: int = 0
var reputation: float = 40.0
var marketing_left: int = 0
var bankruptcy_days: int = 0
var win_target: int = 0                 ## net worth needed to WIN (computed in setup)

var last_traffic: int = 0               ## foot traffic generated on the most recent day
var last_income: int = 0                ## player cash delta on the most recent day (signed)

var _start_cash: int = 0
var _base_property: int = 0             ## constant sum of unit property values
var _amenity_value: int = 0             ## cash sunk into amenities (an asset)

# Units — parallel arrays, index i = floor*cols + col.
var _u_state := PackedInt32Array()
var _u_store := PackedInt32Array()      ## store type index, -1 if empty
var _u_desir := PackedFloat32Array()    ## 0..1 location desirability (fixed at setup)
var _u_stock := PackedInt32Array()      ## owner stores: units of stock on hand
var _u_staff := PackedInt32Array()      ## owner stores: staff hired
var _u_rent := PackedInt32Array()       ## leased units: monthly rent charged
var _u_sat := PackedFloat32Array()      ## leased units: tenant satisfaction 0..100
var _u_lowdays := PackedInt32Array()    ## leased units: consecutive unhappy days
var _u_month_rev := PackedInt32Array()  ## store revenue accumulated this month (info)
var _u_day_rev := PackedInt32Array()    ## store revenue served on the most recent day

# Amenities — count of each type owned (0 or 1).
var _amenities := PackedInt32Array()

# Money ledger — every cash delta folded by category.
var _cat_totals: Dictionary = {}

var _rng := RandomNumberGenerator.new()


# =====================================================================
#  Lifecycle
# =====================================================================

## Build a fresh mall. seed == 0 → randomised; any other value is deterministic.
## `config` overrides any DEFAULTS key (used to make win-friendly / harsh runs).
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	var cfg := DEFAULTS.duplicate(true)
	for k in config.keys():
		cfg[k] = config[k]

	floors = maxi(1, int(cfg["floors"]))
	cols = maxi(1, int(cfg["cols"]))
	base_traffic = maxi(0, int(cfg["base_traffic"]))
	growth_goal = int(cfg["growth_goal"])
	time_cap = maxi(1, int(cfg["time_cap"]))
	open_cost = int(cfg["open_cost"])
	staff_wage = int(cfg["staff_wage"])
	maintenance = int(cfg["maintenance"])
	marketing_cost = int(cfg["marketing_cost"])
	marketing_span = int(cfg["marketing_days"])
	marketing_mult = float(cfg["marketing_mult"])
	interest_bp = int(cfg["interest_bp"])
	max_debt = int(cfg["max_debt"])
	bankruptcy_floor = int(cfg["bankruptcy_floor"])
	bankruptcy_patience = int(cfg["bankruptcy_patience"])
	rep_drift = float(cfg["rep_drift"])
	evict_hit = float(cfg["evict_hit"])
	sat_start = float(cfg["sat_start"])
	sat_up = float(cfg["sat_up"])
	sat_down = float(cfg["sat_down"])
	leave_threshold = float(cfg["leave_threshold"])
	leave_patience = int(cfg["leave_patience"])

	day = 0
	outcome = ONGOING
	reputation = float(cfg["rep_start"])
	marketing_left = 0
	bankruptcy_days = 0
	last_traffic = 0
	last_income = 0
	_amenity_value = 0

	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

	var n := floors * cols
	_u_state = PackedInt32Array()
	_u_store = PackedInt32Array()
	_u_desir = PackedFloat32Array()
	_u_stock = PackedInt32Array()
	_u_staff = PackedInt32Array()
	_u_rent = PackedInt32Array()
	_u_sat = PackedFloat32Array()
	_u_lowdays = PackedInt32Array()
	_u_month_rev = PackedInt32Array()
	_u_day_rev = PackedInt32Array()
	_u_state.resize(n)
	_u_store.resize(n)
	_u_desir.resize(n)
	_u_stock.resize(n)
	_u_staff.resize(n)
	_u_rent.resize(n)
	_u_sat.resize(n)
	_u_lowdays.resize(n)
	_u_month_rev.resize(n)
	_u_day_rev.resize(n)

	_base_property = 0
	var unit_value := int(cfg["unit_value"])
	for i in n:
		_u_state[i] = U_EMPTY
		_u_store[i] = -1
		_u_stock[i] = 0
		_u_staff[i] = 0
		_u_rent[i] = 0
		_u_sat[i] = 0.0
		_u_lowdays[i] = 0
		_u_month_rev[i] = 0
		_u_day_rev[i] = 0
		var d := _desirability_of(i)
		_u_desir[i] = d
		var v := int(unit_value * (0.6 + 0.8 * d))
		_base_property += v

	_amenities = PackedInt32Array()
	_amenities.resize(AMENITY_COUNT)
	for a in AMENITY_COUNT:
		_amenities[a] = 0

	# Money ledger + starting position.
	_cat_totals = {}
	cash = 0
	_start_cash = 0
	debt = 0
	_apply_cash(int(cfg["start_cash"]), "seed_capital")
	_start_cash = cash   # baseline for the conservation invariant
	var start_debt := int(cfg["initial_debt"])
	if start_debt > 0:
		debt = start_debt

	win_target = net_worth() + growth_goal


## Location desirability 0..1 — ground floor and anchor ends draw the crowd;
## upper floors and mid-corners are quieter. Pure function of the grid position.
func _desirability_of(i: int) -> float:
	var f := i / cols
	var c := i % cols
	var d := 0.5
	# Floor: lower floors are busier.
	d += 0.25 * float(floors - 1 - f) / float(maxi(1, floors - 1))
	# Anchor ends of a row pull traffic; the dead-centre less so.
	if c == 0 or c == cols - 1:
		d += 0.20
	elif c == 1 or c == cols - 2:
		d += 0.08
	return clampf(d, 0.0, 1.0)


# =====================================================================
#  Money ledger (the ONLY way cash may change)
# =====================================================================

func _apply_cash(delta: int, category: String) -> void:
	cash += delta
	_cat_totals[category] = int(_cat_totals.get(category, 0)) + delta


func category_total(category: String) -> int:
	return int(_cat_totals.get(category, 0))


## Every ledger category that has seen a flow — lets tests confirm that money only
## ever moves through DEFINED, named flows (no undefined path created cash).
func category_keys() -> Array:
	return _cat_totals.keys()


## The conservation invariant: cash equals starting cash plus the sum of every
## recorded ledger delta. True by construction — the probe recomputes it to prove
## no path bypasses the ledger.
func conservation_ok() -> bool:
	var s := 0
	for k in _cat_totals.keys():
		s += int(_cat_totals[k])
	return cash == s


# =====================================================================
#  Derived queries
# =====================================================================

func unit_count() -> int:
	return _u_state.size()

func unit_state(i: int) -> int:
	return _u_state[i]

func unit_store(i: int) -> int:
	return _u_store[i]

func unit_desir(i: int) -> float:
	return _u_desir[i]

func unit_stock(i: int) -> int:
	return _u_stock[i]

func unit_staff(i: int) -> int:
	return _u_staff[i]

func unit_rent(i: int) -> int:
	return _u_rent[i]

func unit_satisfaction(i: int) -> float:
	return _u_sat[i]

func unit_day_revenue(i: int) -> int:
	return _u_day_rev[i]

func amenity_owned(a: int) -> bool:
	return a >= 0 and a < AMENITY_COUNT and _amenities[a] > 0

func amenity_count() -> int:
	var c := 0
	for a in AMENITY_COUNT:
		c += _amenities[a]
	return c

func occupied_count() -> int:
	var c := 0
	for i in _u_state.size():
		if _u_state[i] != U_EMPTY:
			c += 1
	return c

func occupancy_rate() -> float:
	var n := _u_state.size()
	if n == 0:
		return 0.0
	return float(occupied_count()) / float(n)

func anchor_count() -> int:
	var c := 0
	for i in _u_state.size():
		if _u_state[i] != U_EMPTY and _u_store[i] >= 0 and STORE_ANCHOR[_u_store[i]] == 1:
			c += 1
	return c

func store_variety() -> int:
	var seen: Dictionary = {}
	for i in _u_state.size():
		if _u_state[i] != U_EMPTY and _u_store[i] >= 0:
			seen[_u_store[i]] = true
	return seen.size()

func avg_tenant_satisfaction() -> float:
	var total := 0.0
	var n := 0
	for i in _u_state.size():
		if _u_state[i] == U_LEASED:
			total += _u_sat[i]
			n += 1
	if n == 0:
		return 0.0
	return total / float(n)


## The rent a store type would command in a given unit (location-adjusted).
func rent_for(store_type: int, unit_index: int) -> int:
	var d := _u_desir[unit_index]
	return int(STORE_RENT[store_type] * (0.7 + 0.6 * d))


func property_value() -> int:
	return _base_property + _amenity_value


func net_worth() -> int:
	return cash + property_value() - debt


# =====================================================================
#  Legality — actions are is_legal-gated; illegal ones never mutate state
# =====================================================================

func _valid_index(i: int) -> bool:
	return i >= 0 and i < _u_state.size()

func can_lease(unit_index: int, store_type: int) -> bool:
	return outcome == ONGOING and _valid_index(unit_index) \
		and _u_state[unit_index] == U_EMPTY \
		and store_type >= 0 and store_type < STORE_COUNT

func can_operate(unit_index: int, store_type: int) -> bool:
	return outcome == ONGOING and _valid_index(unit_index) \
		and _u_state[unit_index] == U_EMPTY \
		and store_type >= 0 and store_type < STORE_COUNT \
		and cash >= open_cost

func can_buy_stock(unit_index: int, qty: int) -> bool:
	if outcome != ONGOING or not _valid_index(unit_index) or _u_state[unit_index] != U_OWNER:
		return false
	if qty <= 0:
		return false
	return cash >= qty * STORE_WHOLESALE[_u_store[unit_index]]

func can_hire(unit_index: int, count: int) -> bool:
	return outcome == ONGOING and _valid_index(unit_index) \
		and _u_state[unit_index] == U_OWNER and count > 0

func can_set_rent(unit_index: int, value: int) -> bool:
	return outcome == ONGOING and _valid_index(unit_index) \
		and _u_state[unit_index] == U_LEASED and value >= 0

func can_add_amenity(amenity: int) -> bool:
	return outcome == ONGOING and amenity >= 0 and amenity < AMENITY_COUNT \
		and _amenities[amenity] == 0 and cash >= AMENITY_COST[amenity]

func can_evict(unit_index: int) -> bool:
	return outcome == ONGOING and _valid_index(unit_index) and _u_state[unit_index] != U_EMPTY

func can_run_marketing() -> bool:
	return outcome == ONGOING and cash >= marketing_cost

func can_take_loan(amount: int) -> bool:
	return outcome == ONGOING and amount > 0 and debt + amount <= max_debt

func can_repay_loan(amount: int) -> bool:
	return outcome == ONGOING and amount > 0 and debt > 0 and cash >= amount


# =====================================================================
#  Actions (each returns true on success; false leaves state untouched)
# =====================================================================

## Lease a unit to a tenant of `store_type`. Free to sign; you collect monthly
## rent (location-adjusted) and the tenant keeps their sales.
func lease(unit_index: int, store_type: int) -> bool:
	if not can_lease(unit_index, store_type):
		return false
	_u_state[unit_index] = U_LEASED
	_u_store[unit_index] = store_type
	_u_rent[unit_index] = rent_for(store_type, unit_index)
	_u_sat[unit_index] = sat_start
	_u_lowdays[unit_index] = 0
	_u_month_rev[unit_index] = 0
	_u_day_rev[unit_index] = 0
	return true


## Take a unit over yourself. Costs a fit-out (open_cost); starts with no stock
## and one staff member. You keep sales but pay stock + wages.
func operate(unit_index: int, store_type: int) -> bool:
	if not can_operate(unit_index, store_type):
		return false
	_apply_cash(-open_cost, "fitout")
	_u_state[unit_index] = U_OWNER
	_u_store[unit_index] = store_type
	_u_stock[unit_index] = 0
	_u_staff[unit_index] = 1
	_u_month_rev[unit_index] = 0
	_u_day_rev[unit_index] = 0
	return true


## Restock an owner store. Stock is consumed by sales; wholesale is paid now.
func buy_stock(unit_index: int, qty: int) -> bool:
	if not can_buy_stock(unit_index, qty):
		return false
	var cost := qty * STORE_WHOLESALE[_u_store[unit_index]]
	_apply_cash(-cost, "stock")
	_u_stock[unit_index] += qty
	return true


func hire_staff(unit_index: int, count: int) -> bool:
	if not can_hire(unit_index, count):
		return false
	_u_staff[unit_index] += count
	return true


func set_staff(unit_index: int, count: int) -> bool:
	if outcome != ONGOING or not _valid_index(unit_index) \
			or _u_state[unit_index] != U_OWNER or count < 0:
		return false
	_u_staff[unit_index] = count
	return true


func set_rent(unit_index: int, value: int) -> bool:
	if not can_set_rent(unit_index, value):
		return false
	_u_rent[unit_index] = value
	return true


## Buy an amenity: cash → asset (property_value rises by the same amount, so net
## worth is unchanged on purchase), and it lifts traffic + reputation thereafter.
func add_amenity(amenity: int) -> bool:
	if not can_add_amenity(amenity):
		return false
	_apply_cash(-AMENITY_COST[amenity], "amenity")
	_amenity_value += AMENITY_COST[amenity]
	_amenities[amenity] = 1
	return true


## Kick out a tenant / close your own store. The unit goes vacant; reputation
## takes a hit for the disruption.
func evict(unit_index: int) -> bool:
	if not can_evict(unit_index):
		return false
	_vacate(unit_index)
	reputation = clampf(reputation - evict_hit, 0.0, 100.0)
	return true


func _vacate(unit_index: int) -> void:
	_u_state[unit_index] = U_EMPTY
	_u_store[unit_index] = -1
	_u_stock[unit_index] = 0
	_u_staff[unit_index] = 0
	_u_rent[unit_index] = 0
	_u_sat[unit_index] = 0.0
	_u_lowdays[unit_index] = 0
	_u_month_rev[unit_index] = 0
	_u_day_rev[unit_index] = 0


func run_marketing() -> bool:
	if not can_run_marketing():
		return false
	_apply_cash(-marketing_cost, "marketing")
	marketing_left = marketing_span
	return true


func take_loan(amount: int) -> bool:
	if not can_take_loan(amount):
		return false
	_apply_cash(amount, "loan_draw")
	debt += amount
	return true


func repay_loan(amount: int) -> bool:
	if not can_repay_loan(amount):
		return false
	var pay := mini(amount, debt)
	_apply_cash(-pay, "loan_repay")
	debt -= pay
	return true


# =====================================================================
#  The daily tick — the customer economy + bills + time
# =====================================================================

## Advance the mall one day. Returns the player's signed cash delta for the day.
func tick_day() -> int:
	if outcome != ONGOING:
		return 0
	var cash_before := cash

	var traffic := _generate_traffic()
	last_traffic = traffic
	_serve_customers(traffic)      # owner revenue lands as cash; records per-store rev
	_pay_daily_bills()             # maintenance, owner wages, amenity upkeep
	if marketing_left > 0:
		marketing_left -= 1
	_drift_reputation()
	_age_tenants()                 # satisfaction + retention (may vacate quitters)

	day += 1
	if day % MONTH_DAYS == 0:
		_close_month()             # collect rent, charge loan interest, reset month rev

	_judge()

	last_income = cash - cash_before
	return last_income


## Seeded foot traffic: base × reputation × amenities × anchors × marketing × noise.
func _generate_traffic() -> int:
	var rep_factor := 0.4 + reputation / 100.0
	var amenity_factor := 1.0 + 0.08 * float(amenity_count())
	var anchor_factor := 1.0 + 0.15 * float(anchor_count())
	var marketing_factor := marketing_mult if marketing_left > 0 else 1.0
	var noise := _rng.randf_range(0.9, 1.1)
	var t := float(base_traffic) * rep_factor * amenity_factor * anchor_factor * marketing_factor * noise
	return maxi(0, int(t))


## Distribute customers to occupied stores by appeal × desirability, then take
## their money. Owner stores are stock-limited and their profit lands as cash;
## leased tenants keep sales (you get rent at month close).
func _serve_customers(traffic: int) -> void:
	var n := _u_state.size()
	# Effective appeal weight per occupied unit.
	var weight := PackedFloat32Array()
	weight.resize(n)
	var total_weight := 0.0
	for i in n:
		_u_day_rev[i] = 0
		if _u_state[i] != U_EMPTY and _u_store[i] >= 0:
			var w := STORE_APPEAL[_u_store[i]] * (0.6 + 0.8 * _u_desir[i])
			weight[i] = w
			total_weight += w
		else:
			weight[i] = 0.0
	if total_weight <= 0.0:
		return

	for i in n:
		if weight[i] <= 0.0:
			continue
		var customers := int(float(traffic) * weight[i] / total_weight)
		if customers <= 0:
			continue
		var store := _u_store[i]
		var spend := STORE_SPEND[store]
		if _u_state[i] == U_LEASED:
			var rev := customers * spend
			_u_day_rev[i] = rev
			_u_month_rev[i] += rev
		else: # U_OWNER — limited by stock; profit lands as cash
			var sold := mini(customers, _u_stock[i])
			if sold > 0:
				var revenue := sold * spend
				_u_stock[i] -= sold
				_u_day_rev[i] = revenue
				_u_month_rev[i] += revenue
				_apply_cash(revenue, "store_revenue")


func _pay_daily_bills() -> void:
	var bill := 0
	var wages := 0
	for i in _u_state.size():
		if _u_state[i] != U_EMPTY:
			bill += maintenance
		if _u_state[i] == U_OWNER:
			wages += _u_staff[i] * staff_wage
	if bill > 0:
		_apply_cash(-bill, "maintenance")
	if wages > 0:
		_apply_cash(-wages, "wages")
	var upkeep := 0
	for a in AMENITY_COUNT:
		if _amenities[a] > 0:
			upkeep += AMENITY_UPKEEP[a]
	if upkeep > 0:
		_apply_cash(-upkeep, "amenity_upkeep")


func _drift_reputation() -> void:
	var target := _target_reputation()
	reputation = clampf(reputation + (target - reputation) * rep_drift, 0.0, 100.0)


## Reputation the mall trends toward: driven by occupancy, variety, amenities and
## tenant happiness; dragged down by vacancy.
func _target_reputation() -> float:
	var occ := occupancy_rate()
	var t := 20.0
	t += 30.0 * occ
	t += 3.0 * float(store_variety())
	t += 4.0 * float(amenity_count())
	t += 0.2 * avg_tenant_satisfaction()
	t -= 25.0 * (1.0 - occ)   # vacancy drag
	return clampf(t, 0.0, 100.0)


## Tenant satisfaction ages daily against whether their sales cover their rent.
## A tenant unhappy for too long quits — the unit goes vacant (reputation hit).
func _age_tenants() -> void:
	var expected_per_day := 0
	for i in _u_state.size():
		if _u_state[i] != U_LEASED:
			continue
		expected_per_day = int(float(_u_rent[i]) / float(MONTH_DAYS))
		if _u_day_rev[i] >= expected_per_day:
			_u_sat[i] = clampf(_u_sat[i] + sat_up, 0.0, 100.0)
		else:
			_u_sat[i] = clampf(_u_sat[i] - sat_down, 0.0, 100.0)
		if _u_sat[i] < leave_threshold:
			_u_lowdays[i] += 1
		else:
			_u_lowdays[i] = 0
		if _u_lowdays[i] >= leave_patience:
			_vacate(i)
			reputation = clampf(reputation - evict_hit, 0.0, 100.0)


## Month close: each tenant pays rent OUT OF the sales their store made this
## month — a thriving store pays in full, but a tenant starved of foot traffic
## can only pay what it took in and DEFAULTS on the rest (rent is therefore tied
## to the customer economy, not free money). Then loan interest is charged.
func _close_month() -> void:
	var rent_total := 0
	for i in _u_state.size():
		if _u_state[i] == U_LEASED:
			rent_total += mini(_u_rent[i], _u_month_rev[i])
		_u_month_rev[i] = 0
	if rent_total > 0:
		_apply_cash(rent_total, "rent_income")
	if debt > 0:
		var interest := int(float(debt) * float(interest_bp) / 10000.0)
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
	# Victory: net-worth goal reached in time.
	if net_worth() >= win_target:
		outcome = WON
		return
	# Time cap: judged by net worth at the deadline.
	if day >= time_cap:
		outcome = WON if net_worth() >= win_target else LOST


# =====================================================================
#  Auto-play heuristic (deterministic) — for the full-run probe / demo
# =====================================================================

## Take one day's worth of prudent decisions, then advance the day. Leases every
## vacant unit to a variety of store types (one anchor), buys amenities and runs
## marketing when comfortably affordable, keeps owner stores stocked. Pure &
## deterministic given the seed. Returns the day's cash delta.
func auto_play_step() -> int:
	if outcome != ONGOING:
		return 0
	# 1) Lease every vacant unit — signing is free and adds rent income.
	for i in _u_state.size():
		if _u_state[i] == U_EMPTY:
			lease(i, _auto_store_for(i))
	# 2) Keep owner stores stocked (if we run any).
	for i in _u_state.size():
		if _u_state[i] == U_OWNER and _u_stock[i] < 40 and can_buy_stock(i, 40):
			buy_stock(i, 40)
	# 3) Buy the cheapest un-owned amenity when we have a healthy buffer.
	if cash > 12000:
		var best := -1
		for a in AMENITY_COUNT:
			if _amenities[a] == 0 and (best == -1 or AMENITY_COST[a] < AMENITY_COST[best]):
				best = a
		if best != -1 and can_add_amenity(best):
			add_amenity(best)
	# 4) Marketing push when reputation is low and cash is comfortable.
	if marketing_left == 0 and reputation < 60.0 and cash > 8000 and can_run_marketing():
		run_marketing()
	return tick_day()


## Deterministic store choice for auto-play — the busiest anchor spot gets the
## Department Store, everything else cycles the catalogue for variety.
func _auto_store_for(unit_index: int) -> int:
	if _u_desir[unit_index] >= 0.9 and anchor_count() == 0:
		return 4  # Department Store (anchor)
	return unit_index % STORE_COUNT


# =====================================================================
#  Persistence — full state incl. RNG (byte-identical round-trip)
# =====================================================================

func save_data() -> Dictionary:
	return {
		"day": day,
		"outcome": outcome,
		"cash": cash,
		"debt": debt,
		"reputation": reputation,
		"marketing_left": marketing_left,
		"bankruptcy_days": bankruptcy_days,
		"win_target": win_target,
		"last_traffic": last_traffic,
		"last_income": last_income,
		"start_cash": _start_cash,
		"base_property": _base_property,
		"amenity_value": _amenity_value,
		"floors": floors,
		"cols": cols,
		"base_traffic": base_traffic,
		"growth_goal": growth_goal,
		"time_cap": time_cap,
		"open_cost": open_cost,
		"staff_wage": staff_wage,
		"maintenance": maintenance,
		"marketing_cost": marketing_cost,
		"marketing_span": marketing_span,
		"marketing_mult": marketing_mult,
		"interest_bp": interest_bp,
		"max_debt": max_debt,
		"bankruptcy_floor": bankruptcy_floor,
		"bankruptcy_patience": bankruptcy_patience,
		"rep_drift": rep_drift,
		"evict_hit": evict_hit,
		"sat_start": sat_start,
		"sat_up": sat_up,
		"sat_down": sat_down,
		"leave_threshold": leave_threshold,
		"leave_patience": leave_patience,
		"u_state": _u_state.duplicate(),
		"u_store": _u_store.duplicate(),
		"u_desir": _u_desir.duplicate(),
		"u_stock": _u_stock.duplicate(),
		"u_staff": _u_staff.duplicate(),
		"u_rent": _u_rent.duplicate(),
		"u_sat": _u_sat.duplicate(),
		"u_lowdays": _u_lowdays.duplicate(),
		"u_month_rev": _u_month_rev.duplicate(),
		"u_day_rev": _u_day_rev.duplicate(),
		"amenities": _amenities.duplicate(),
		"cat_totals": _cat_totals.duplicate(true),
		"rng_seed": _rng.seed,
		"rng_state": _rng.state,
	}


func load_data(data: Dictionary) -> void:
	day = int(data["day"])
	outcome = int(data["outcome"])
	cash = int(data["cash"])
	debt = int(data["debt"])
	reputation = float(data["reputation"])
	marketing_left = int(data["marketing_left"])
	bankruptcy_days = int(data["bankruptcy_days"])
	win_target = int(data["win_target"])
	last_traffic = int(data["last_traffic"])
	last_income = int(data["last_income"])
	_start_cash = int(data["start_cash"])
	_base_property = int(data["base_property"])
	_amenity_value = int(data["amenity_value"])
	floors = int(data["floors"])
	cols = int(data["cols"])
	base_traffic = int(data["base_traffic"])
	growth_goal = int(data["growth_goal"])
	time_cap = int(data["time_cap"])
	open_cost = int(data["open_cost"])
	staff_wage = int(data["staff_wage"])
	maintenance = int(data["maintenance"])
	marketing_cost = int(data["marketing_cost"])
	marketing_span = int(data["marketing_span"])
	marketing_mult = float(data["marketing_mult"])
	interest_bp = int(data["interest_bp"])
	max_debt = int(data["max_debt"])
	bankruptcy_floor = int(data["bankruptcy_floor"])
	bankruptcy_patience = int(data["bankruptcy_patience"])
	rep_drift = float(data["rep_drift"])
	evict_hit = float(data["evict_hit"])
	sat_start = float(data["sat_start"])
	sat_up = float(data["sat_up"])
	sat_down = float(data["sat_down"])
	leave_threshold = float(data["leave_threshold"])
	leave_patience = int(data["leave_patience"])
	_u_state = (data["u_state"] as PackedInt32Array).duplicate()
	_u_store = (data["u_store"] as PackedInt32Array).duplicate()
	_u_desir = (data["u_desir"] as PackedFloat32Array).duplicate()
	_u_stock = (data["u_stock"] as PackedInt32Array).duplicate()
	_u_staff = (data["u_staff"] as PackedInt32Array).duplicate()
	_u_rent = (data["u_rent"] as PackedInt32Array).duplicate()
	_u_sat = (data["u_sat"] as PackedFloat32Array).duplicate()
	_u_lowdays = (data["u_lowdays"] as PackedInt32Array).duplicate()
	_u_month_rev = (data["u_month_rev"] as PackedInt32Array).duplicate()
	_u_day_rev = (data["u_day_rev"] as PackedInt32Array).duplicate()
	_amenities = (data["amenities"] as PackedInt32Array).duplicate()
	_cat_totals = (data["cat_totals"] as Dictionary).duplicate(true)
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(data["rng_seed"])
	_rng.state = int(data["rng_state"])


## A canonical, order-stable serialization for byte-identical comparison in tests.
func snapshot_string() -> String:
	return JSON.stringify(save_data())
