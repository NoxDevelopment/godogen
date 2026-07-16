extends RefCounted
class_name VideoStoreEngine
## res://scripts/video_store_engine.gd
## THE PURE ENGINE — a deterministic, seedable 80s VHS-RENTAL-STORE management sim
## (a Blockbuster-of-the-neon-era in the mall-tycoon / tycoon-economy lineage). You
## OWN the store: a CATALOG of VHS TITLES across six genres, each of which you can
## BUY COPIES of. Every day a seeded FOOT TRAFFIC of customers walks in, each wants
## a TITLE (weighted by that title's CURRENT rental DEMAND) and RENTS an available
## copy; if every copy of the title they want is out, that's a MISSED rental (lost
## goodwill). Rentals RETURN after a few days — some LATE (late fees, a real revenue
## stream, but a harsh late-fee policy CHURNS members), a few DAMAGED (the tape
## leaves stock). You grow CASH and NET WORTH by stocking the right number of copies
## of the hot NEW RELEASES vs the evergreen catalogue. Reach a net-worth goal to
## WIN, or bankrupt out to LOSE.
##
## THE HEART OF THE SIM — NEW-RELEASE HYPE. A title's rental DEMAND is a pure
## function of time: a NEW RELEASE spikes to a multiple of its baseline the week it
## drops, then DECAYS exponentially over the following weeks toward its evergreen
## catalogue baseline (demand(t,day) = baseline + amp * e^(-lambda * weeks)). Stock
## too few copies of a hot release and you eat missed rentals + lost goodwill; stock
## too many and the hype fades before they pay for themselves. That trade-off — hot
## release vs evergreen catalogue — is the core decision every day.
##
## Everything — traffic, which title each customer wants, returns + late fees +
## damage, membership sign-up / churn, reputation drift, the auto-play heuristic,
## win/loss — is a pure function of (state, day, seeded RNG). The same seed + the
## same scripted actions always yield a BYTE-IDENTICAL store after N days. No Godot
## node dependency: this class is fully headless-testable. GameManager owns one
## instance and adds the autoload ABI + save; store.gd only reads state + forwards a
## player's chosen action.
##
## MONEY DISCIPLINE (why conservation holds): every mutation of `cash` goes through
## _apply_cash(delta, category) which also folds delta into _cat_totals. The
## invariant cash == _start_cash + sum(_cat_totals.values()) holds at all times — no
## code path may touch `cash` directly. All money is INTEGER dollars, so replays and
## save round-trips are exact; reputation / demand / member churn are floats (they
## never touch the cash ledger).
##
## TICK DISCIPLINE: tick_day() runs a fixed pipeline — process returns (late fees,
## damage, restock shelves) → generate foot traffic → serve customers (rentals,
## misses, throughput gated by staff) → pay daily bills (rent, wages) → decay
## marketing → update membership (sign-ups + churn) → drift reputation → advance the
## day → on a month boundary charge loan interest → judge win/loss. Every stochastic
## choice draws from the SEEDED RNG whose state is saved, so replays are exact.

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
#  Genres
# =====================================================================
const GENRE_NAME: PackedStringArray = ["Action", "Comedy", "Horror", "Drama", "Family", "SciFi"]
const G_ACTION: int = 0
const G_COMEDY: int = 1
const G_HORROR: int = 2
const G_DRAMA: int = 3
const G_FAMILY: int = 4
const G_SCIFI: int = 5

# =====================================================================
#  Title catalogue (24 seeded VHS titles across the six genres). Each: name, genre,
#  baseline evergreen demand weight, RELEASE day (0 == already in the catalogue; > 0
#  == a NEW RELEASE that arrives during the run), and purchase COST per copy (new
#  releases cost more to buy). Reference data → hardcoded constants, never a table.
# =====================================================================
const TITLE_NAME: PackedStringArray = [
	"Neon Nights", "Laugh Track", "Midnight Terror", "Tears of Autumn",
	"Puppy Playhouse", "Star Voyager", "Karate Fury", "Office Chaos",
	"The Crawling Dark", "Letters Home", "Cartoon Carnival", "Galaxy Rangers",
	"Highway Pursuit", "Sitcom Summer",
	"Blade Horizon", "Prom Night Panic", "Space Dominion II", "The Big Giggle",
	"Dragon's Oath", "Haunted Arcade", "Family Road Trip", "Quantum Cop",
	"Heartstrings", "Comet Riders",
]
const TITLE_GENRE: PackedInt32Array = [
	G_ACTION, G_COMEDY, G_HORROR, G_DRAMA, G_FAMILY, G_SCIFI, G_ACTION, G_COMEDY,
	G_HORROR, G_DRAMA, G_FAMILY, G_SCIFI, G_ACTION, G_COMEDY,
	G_ACTION, G_HORROR, G_SCIFI, G_COMEDY, G_ACTION, G_HORROR, G_FAMILY, G_SCIFI,
	G_DRAMA, G_SCIFI,
]
const TITLE_BASEPOP: PackedFloat32Array = [
	2.5, 2.0, 1.8, 1.5, 2.2, 2.6, 2.0, 1.6,
	1.4, 1.2, 2.0, 2.3, 1.9, 1.3,
	2.8, 2.4, 3.0, 2.2, 2.7, 2.5, 2.3, 2.9,
	2.1, 3.1,
]
## Catalogue titles (0..13) were released in the PAST (negative day) — their hype has
## already decayed, so at day 0 they sit at their evergreen baseline. New releases
## (14..23) arrive during the run at a positive day and spike the hype curve.
const TITLE_RELEASE: PackedInt32Array = [
	-120, -95, -140, -60, -110, -130, -80, -100,
	-150, -70, -90, -125, -105, -85,
	21, 35, 50, 70, 95, 125, 160, 200,
	250, 310,
]
const TITLE_COST: PackedInt32Array = [
	38, 32, 34, 30, 36, 42, 35, 31,
	30, 30, 34, 40, 33, 30,
	65, 60, 70, 58, 66, 62, 55, 68,
	56, 72,
]
const TITLE_COUNT: int = 24

# =====================================================================
#  Default tuning (auditable; overridable via a config dict in setup)
# =====================================================================
const DEFAULTS: Dictionary = {
	"policy": "balanced",           ## auto-play flavour: "balanced" | "aggressive"
	"start_cash": 6000,
	"initial_debt": 0,
	"base_traffic": 40,             ## baseline daily walk-ins before modifiers
	"growth_goal": 20000,           ## WIN = starting net worth + this
	"max_days": 540,                ## hard cap — guarantees termination
	"rental_period": 2,            ## days until a rental is DUE
	"rental_price_catalog": 4,      ## $ per catalogue rental
	"rental_price_new": 6,          ## $ per NEW-RELEASE rental (premium)
	"new_release_window": 21,       ## days a title counts as a "new release" for pricing
	"late_fee_per_day": 2,          ## $ per day overdue (player-adjustable policy)
	"max_late_fee": 8,              ## cap on the late-fee policy knob
	"damage_chance": 0.03,          ## chance a returned tape is damaged (leaves stock)
	"return_min_hold": 1,           ## a rental is held at least this many days
	"return_max_hold": 4,           ## …and at most this many (holds > period == late)
	"store_rent": 40,               ## $ per day storefront rent
	"staff_wage": 18,               ## $ per day per staff member
	"throughput_per_staff": 60,     ## customers one staff member can serve per day
	"max_staff": 5,
	"start_staff": 1,
	"marketing_cost": 800,
	"marketing_days": 10,
	"marketing_mult": 1.5,
	"interest_bp": 100,             ## monthly loan interest, basis points (1.00%)
	"max_debt": 20000,
	"bankruptcy_floor": -3000,      ## cash below this…
	"bankruptcy_patience": 45,      ## …for this many consecutive days => LOSE
	"rep_start": 45.0,
	"rep_drift": 0.10,              ## fraction of the gap to target closed per day
	"hype_gain": 5.0,               ## new-release demand peak == baseline * (1 + gain)
	"hype_lambda": 0.45,            ## exponential hype decay per week
	"member_signup_rate": 0.08,     ## fraction of a day's happy renters who join
	"member_traffic_k": 0.003,      ## each member lifts traffic by this fraction
	"member_base_churn": 0.005,     ## baseline daily member attrition
	"asset_frac_num": 1,            ## tape asset value == cost * num/den (depreciated)
	"asset_frac_den": 2,
}
const MONTH_DAYS: int = 30

# =====================================================================
#  Tuning (resolved from DEFAULTS + config in setup)
# =====================================================================
var _policy: String = "balanced"
var base_traffic: int = 64
var growth_goal: int = 22000
var max_days: int = 540
var rental_period: int = 3
var rental_price_catalog: int = 3
var rental_price_new: int = 5
var new_release_window: int = 21
var late_fee_per_day: int = 2
var max_late_fee: int = 8
var damage_chance: float = 0.03
var return_min_hold: int = 2
var return_max_hold: int = 6
var store_rent: int = 55
var staff_wage: int = 20
var throughput_per_staff: int = 45
var max_staff: int = 5
var marketing_cost: int = 800
var marketing_span: int = 10
var marketing_mult: float = 1.5
var interest_bp: int = 100
var max_debt: int = 20000
var bankruptcy_floor: int = -3000
var bankruptcy_patience: int = 45
var rep_drift: float = 0.10
var hype_gain: float = 5.0
var hype_lambda: float = 0.45
var member_signup_rate: float = 0.08
var member_traffic_k: float = 0.004
var member_base_churn: float = 0.005
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
var members: int = 0
var staff: int = 1
var marketing_left: int = 0
var bankruptcy_days: int = 0
var win_target: int = 0
var illegal_attempts: int = 0

# Most-recent-day telemetry (info + probes; folded into no ledger).
var last_traffic: int = 0
var last_served: int = 0
var last_turned_away: int = 0
var last_rentals: int = 0
var last_missed: int = 0
var last_returns: int = 0
var last_late: int = 0
var last_damaged: int = 0
var last_income: int = 0

var _seed: int = 0
var _start_cash: int = 0

# Inventory — index i == title id.
var _owned: PackedInt32Array = PackedInt32Array()       ## copies owned (asset)
var _available: PackedInt32Array = PackedInt32Array()   ## copies on the shelf now
var _day_rentals: PackedInt32Array = PackedInt32Array() ## rentals of this title today
var _day_misses: PackedInt32Array = PackedInt32Array()  ## missed rentals of this title today

# Active rentals — parallel arrays (order-stable for determinism).
var _r_title: PackedInt32Array = PackedInt32Array()
var _r_due: PackedInt32Array = PackedInt32Array()
var _r_return: PackedInt32Array = PackedInt32Array()
var _r_new: PackedInt32Array = PackedInt32Array()       ## rented while a new release?

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
	rental_period = maxi(1, int(cfg["rental_period"]))
	rental_price_catalog = int(cfg["rental_price_catalog"])
	rental_price_new = int(cfg["rental_price_new"])
	new_release_window = maxi(1, int(cfg["new_release_window"]))
	late_fee_per_day = int(cfg["late_fee_per_day"])
	max_late_fee = int(cfg["max_late_fee"])
	damage_chance = float(cfg["damage_chance"])
	return_min_hold = maxi(1, int(cfg["return_min_hold"]))
	return_max_hold = maxi(return_min_hold, int(cfg["return_max_hold"]))
	store_rent = int(cfg["store_rent"])
	staff_wage = int(cfg["staff_wage"])
	throughput_per_staff = maxi(1, int(cfg["throughput_per_staff"]))
	max_staff = maxi(1, int(cfg["max_staff"]))
	marketing_cost = int(cfg["marketing_cost"])
	marketing_span = maxi(1, int(cfg["marketing_days"]))
	marketing_mult = float(cfg["marketing_mult"])
	interest_bp = int(cfg["interest_bp"])
	max_debt = int(cfg["max_debt"])
	bankruptcy_floor = int(cfg["bankruptcy_floor"])
	bankruptcy_patience = maxi(1, int(cfg["bankruptcy_patience"]))
	rep_drift = float(cfg["rep_drift"])
	hype_gain = float(cfg["hype_gain"])
	hype_lambda = float(cfg["hype_lambda"])
	member_signup_rate = float(cfg["member_signup_rate"])
	member_traffic_k = float(cfg["member_traffic_k"])
	member_base_churn = float(cfg["member_base_churn"])
	asset_frac_num = int(cfg["asset_frac_num"])
	asset_frac_den = maxi(1, int(cfg["asset_frac_den"]))

	day = 0
	outcome = ONGOING
	reputation = float(cfg["rep_start"])
	members = 0
	staff = clampi(int(cfg["start_staff"]), 0, max_staff)
	marketing_left = 0
	bankruptcy_days = 0
	illegal_attempts = 0
	last_traffic = 0
	last_served = 0
	last_turned_away = 0
	last_rentals = 0
	last_missed = 0
	last_returns = 0
	last_late = 0
	last_damaged = 0
	last_income = 0

	_seed = seed_value
	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

	_owned = PackedInt32Array()
	_available = PackedInt32Array()
	_day_rentals = PackedInt32Array()
	_day_misses = PackedInt32Array()
	_owned.resize(TITLE_COUNT)
	_available.resize(TITLE_COUNT)
	_day_rentals.resize(TITLE_COUNT)
	_day_misses.resize(TITLE_COUNT)
	for i in TITLE_COUNT:
		_owned[i] = 0
		_available[i] = 0
		_day_rentals[i] = 0
		_day_misses[i] = 0

	_r_title = PackedInt32Array()
	_r_due = PackedInt32Array()
	_r_return = PackedInt32Array()
	_r_new = PackedInt32Array()

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


## Every ledger category that has seen a flow — lets tests confirm that money only
## ever moves through DEFINED, named flows (no undefined path created cash).
func category_keys() -> Array:
	return _cat_totals.keys()


## The conservation invariant: cash equals starting cash plus the sum of every
## recorded ledger delta. True by construction — the probe recomputes it to prove no
## path bypasses the ledger.
func conservation_ok() -> bool:
	var s: int = 0
	for k in _cat_totals.keys():
		s += int(_cat_totals[k])
	return cash == s


# =====================================================================
#  Demand — the NEW-RELEASE HYPE curve (the heart of the sim)
# =====================================================================

## A title's rental demand weight at a given day. Before release: 0 (not out yet).
## After release: baseline + amp * e^(-lambda * weeks), i.e. a spike at release that
## decays exponentially over the weeks toward the evergreen catalogue baseline.
func demand(title: int, at_day: int) -> float:
	if title < 0 or title >= TITLE_COUNT:
		return 0.0
	if at_day < TITLE_RELEASE[title]:
		return 0.0
	var baseline: float = TITLE_BASEPOP[title]
	var weeks: float = float(at_day - TITLE_RELEASE[title]) / 7.0
	var amp: float = baseline * hype_gain
	var hype: float = amp * exp(-hype_lambda * weeks)
	return baseline + hype


## Is a title a "new release" for pricing purposes on a given day?
func is_new_release(title: int, at_day: int) -> bool:
	if title < 0 or title >= TITLE_COUNT:
		return false
	if at_day < TITLE_RELEASE[title]:
		return false
	return (at_day - TITLE_RELEASE[title]) < new_release_window


func is_released(title: int, at_day: int) -> bool:
	return title >= 0 and title < TITLE_COUNT and at_day >= TITLE_RELEASE[title]


func rental_price(title: int, at_day: int) -> int:
	return rental_price_new if is_new_release(title, at_day) else rental_price_catalog


# =====================================================================
#  Derived queries
# =====================================================================

func title_count() -> int:
	return TITLE_COUNT

func title_owned(title: int) -> int:
	return _owned[title]

func title_available(title: int) -> int:
	return _available[title]

func title_rented_out(title: int) -> int:
	return _owned[title] - _available[title]

func title_day_rentals(title: int) -> int:
	return _day_rentals[title]

func title_day_misses(title: int) -> int:
	return _day_misses[title]

func active_rentals() -> int:
	return _r_title.size()

func total_copies_owned() -> int:
	var c: int = 0
	for i in _owned.size():
		c += _owned[i]
	return c

func total_copies_available() -> int:
	var c: int = 0
	for i in _available.size():
		c += _available[i]
	return c

## Distinct titles with at least one copy owned — the breadth of the selection.
func selection_breadth() -> int:
	var c: int = 0
	for i in _owned.size():
		if _owned[i] > 0:
			c += 1
	return c

func released_count() -> int:
	var c: int = 0
	for i in TITLE_COUNT:
		if is_released(i, day):
			c += 1
	return c

## Count active rentals whose title id == the given title (integrity check helper).
func rentals_of_title(title: int) -> int:
	var c: int = 0
	for i in _r_title.size():
		if _r_title[i] == title:
			c += 1
	return c

## Depreciated asset value of one copy of a title.
func tape_asset_value(title: int) -> int:
	return TITLE_COST[title] * asset_frac_num / asset_frac_den

func inventory_value() -> int:
	var v: int = 0
	for i in _owned.size():
		v += _owned[i] * tape_asset_value(i)
	return v

func net_worth() -> int:
	return cash + inventory_value() - debt

func staff_capacity() -> int:
	return staff * throughput_per_staff

## Fill rate over the most recent day — availability quality (rentals / demand seen).
func fill_rate() -> float:
	var seen: int = last_rentals + last_missed
	if seen <= 0:
		return 1.0
	return float(last_rentals) / float(seen)

## How harsh the current late-fee policy is, 0..1 (drives churn + reputation drag).
func late_fee_harshness() -> float:
	return clampf(float(late_fee_per_day - 2) / 6.0, 0.0, 1.0)


# =====================================================================
#  Legality — actions are is_legal-gated; illegal ones never mutate state
# =====================================================================

func _valid_title(title: int) -> bool:
	return title >= 0 and title < TITLE_COUNT

func can_buy_copies(title: int, qty: int) -> bool:
	if outcome != ONGOING or not _valid_title(title):
		return false
	if qty <= 0:
		return false
	if not is_released(title, day):
		return false
	return cash >= qty * TITLE_COST[title]

func can_remove_copy(title: int) -> bool:
	## Remove an on-shelf (available) copy — sell it back / retire it.
	return outcome == ONGOING and _valid_title(title) and _available[title] > 0

func can_set_staff(count: int) -> bool:
	return outcome == ONGOING and count >= 0 and count <= max_staff

func can_set_late_fee(value: int) -> bool:
	return outcome == ONGOING and value >= 0 and value <= max_late_fee

func can_run_marketing() -> bool:
	return outcome == ONGOING and cash >= marketing_cost

func can_take_loan(amount: int) -> bool:
	return outcome == ONGOING and amount > 0 and debt + amount <= max_debt

func can_repay_loan(amount: int) -> bool:
	return outcome == ONGOING and amount > 0 and debt > 0 and cash >= amount


# =====================================================================
#  Actions (each returns true on success; false leaves state untouched)
# =====================================================================

## Buy `qty` copies of a title. Cash → inventory asset (depreciated), so net worth
## dips by the depreciation only. Copies land on the shelf immediately.
func buy_copies(title: int, qty: int) -> bool:
	if not can_buy_copies(title, qty):
		illegal_attempts += 1
		return false
	var cost: int = qty * TITLE_COST[title]
	_apply_cash(-cost, "tape_purchase")
	_owned[title] += qty
	_available[title] += qty
	return true


## Retire one on-shelf copy and recover its depreciated asset value in cash.
func remove_copy(title: int) -> bool:
	if not can_remove_copy(title):
		illegal_attempts += 1
		return false
	_owned[title] -= 1
	_available[title] -= 1
	_apply_cash(tape_asset_value(title), "tape_salvage")
	return true


func set_staff(count: int) -> bool:
	if not can_set_staff(count):
		illegal_attempts += 1
		return false
	staff = count
	return true


func hire_staff(count: int) -> bool:
	return set_staff(staff + count)


func set_late_fee(value: int) -> bool:
	if not can_set_late_fee(value):
		illegal_attempts += 1
		return false
	late_fee_per_day = value
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
#  The daily tick — returns, the customer economy, bills, membership, time
# =====================================================================

## Advance the store one day. Returns the player's signed cash delta for the day.
func tick_day() -> int:
	if outcome != ONGOING:
		return 0
	var cash_before: int = cash

	_process_returns()             # late fees, damage, tapes back on the shelf
	var traffic: int = _generate_traffic()
	last_traffic = traffic
	_serve_customers(traffic)      # rentals (income), misses, throughput gating
	_pay_daily_bills()             # rent + wages
	if marketing_left > 0:
		marketing_left -= 1
	_update_membership()           # sign-ups + churn
	_drift_reputation()

	day += 1
	if day % MONTH_DAYS == 0:
		_close_month()             # loan interest

	_judge()

	last_income = cash - cash_before
	return last_income


## Return every rental scheduled to come back today (in stable order). A late return
## accrues a fee (late_days * late_fee_per_day). A returned tape has a small chance
## of being DAMAGED — it leaves stock entirely; otherwise it goes back on the shelf.
func _process_returns() -> void:
	last_returns = 0
	last_late = 0
	last_damaged = 0
	if _r_title.is_empty():
		return
	var keep_title: PackedInt32Array = PackedInt32Array()
	var keep_due: PackedInt32Array = PackedInt32Array()
	var keep_return: PackedInt32Array = PackedInt32Array()
	var keep_new: PackedInt32Array = PackedInt32Array()
	for i in _r_title.size():
		if _r_return[i] != day:
			keep_title.append(_r_title[i])
			keep_due.append(_r_due[i])
			keep_return.append(_r_return[i])
			keep_new.append(_r_new[i])
			continue
		var t: int = _r_title[i]
		last_returns += 1
		var late_days: int = maxi(0, _r_return[i] - _r_due[i])
		if late_days > 0:
			var fee: int = late_days * late_fee_per_day
			if fee > 0:
				_apply_cash(fee, "late_fees")
			last_late += 1
		var damaged: bool = _rng.randf() < damage_chance
		if damaged:
			_owned[t] -= 1          # the tape leaves stock (rented copy destroyed)
			last_damaged += 1
		else:
			_available[t] += 1      # back on the shelf
	_r_title = keep_title
	_r_due = keep_due
	_r_return = keep_return
	_r_new = keep_new


## Seeded foot traffic: base × reputation × marketing × selection breadth × members.
func _generate_traffic() -> int:
	var rep_factor: float = 0.4 + reputation / 100.0
	var marketing_factor: float = marketing_mult if marketing_left > 0 else 1.0
	var breadth_factor: float = 1.0 + 0.02 * float(selection_breadth())
	var member_factor: float = 1.0 + member_traffic_k * float(members)
	var noise: float = _rng.randf_range(0.9, 1.1)
	var t: float = float(base_traffic) * rep_factor * marketing_factor * breadth_factor * member_factor * noise
	return maxi(0, int(t))


## Serve the day's customers. Staff throughput caps how many can be served; the rest
## are TURNED AWAY. Each served customer wants a title (weighted by that title's
## current demand) and RENTS an available copy — or, if every copy is out, records a
## MISSED rental. Rental income lands as cash; a return day is scheduled per rental.
func _serve_customers(traffic: int) -> void:
	for i in TITLE_COUNT:
		_day_rentals[i] = 0
		_day_misses[i] = 0
	last_rentals = 0
	last_missed = 0

	var capacity: int = staff_capacity()
	var served: int = mini(traffic, capacity)
	last_served = served
	last_turned_away = traffic - served
	if served <= 0:
		return

	# Demand weights over released titles (customers want titles that exist).
	var weight: PackedFloat32Array = PackedFloat32Array()
	weight.resize(TITLE_COUNT)
	var total_w: float = 0.0
	for t in TITLE_COUNT:
		var w: float = demand(t, day)
		weight[t] = w
		total_w += w
	if total_w <= 0.0:
		return

	for _c in served:
		var pick: int = _weighted_pick(weight, total_w)
		if pick < 0:
			continue
		if _available[pick] > 0:
			_available[pick] -= 1
			var price: int = rental_price(pick, day)
			_apply_cash(price, "rental_income")
			var hold: int = _rng.randi_range(return_min_hold, return_max_hold)
			_r_title.append(pick)
			_r_due.append(day + rental_period)
			_r_return.append(day + hold)
			_r_new.append(1 if is_new_release(pick, day) else 0)
			_day_rentals[pick] += 1
			last_rentals += 1
		else:
			_day_misses[pick] += 1
			last_missed += 1


## Weighted index draw over the demand weights using the seeded RNG.
func _weighted_pick(weight: PackedFloat32Array, total_w: float) -> int:
	var r: float = _rng.randf() * total_w
	var acc: float = 0.0
	for t in TITLE_COUNT:
		acc += weight[t]
		if r < acc:
			return t
	# floating-point tail — return the last title with positive weight.
	for t in range(TITLE_COUNT - 1, -1, -1):
		if weight[t] > 0.0:
			return t
	return -1


func _pay_daily_bills() -> void:
	if store_rent > 0:
		_apply_cash(-store_rent, "rent")
	var wages: int = staff * staff_wage
	if wages > 0:
		_apply_cash(-wages, "wages")


## Membership: a fraction of the day's happy renters join; churn rises with missed
## rentals (bad availability) and a harsh late-fee policy.
func _update_membership() -> void:
	var signups: int = int(float(last_rentals) * member_signup_rate * (reputation / 100.0))
	var seen: int = last_rentals + last_missed
	var fail_ratio: float = 0.0
	if seen > 0:
		fail_ratio = float(last_missed) / float(seen)
	var churn_rate: float = member_base_churn + 0.05 * fail_ratio + 0.03 * late_fee_harshness()
	var churn: int = int(float(members) * churn_rate)
	members = maxi(0, members + signups - churn)


func _drift_reputation() -> void:
	var target: float = _target_reputation()
	reputation = clampf(reputation + (target - reputation) * rep_drift, 0.0, 100.0)


## Reputation the store trends toward: driven by availability (fill rate), selection
## breadth and membership; dragged down by turned-away crowds and harsh late fees.
func _target_reputation() -> float:
	var t: float = 25.0
	t += 35.0 * fill_rate()
	t += minf(15.0, 0.6 * float(selection_breadth()))
	t += minf(20.0, 0.04 * float(members))
	t -= 15.0 * late_fee_harshness()
	if last_turned_away > 0:
		t -= 8.0
	return clampf(t, 0.0, 100.0)


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

## Take one day's worth of prudent decisions, then advance the day. Sizes staff to
## the recent crowd, stocks each released title's copies in proportion to its CURRENT
## demand (so hot new releases get more copies than cold catalogue), runs marketing
## when reputation sags, borrows to stay liquid while solvent, and keeps a fair
## late-fee policy. Pure & deterministic given the seed. Returns the day's cash delta.
func auto_play_step() -> int:
	if outcome != ONGOING:
		return 0
	var aggressive: bool = _policy == "aggressive"

	# 1) Staff sized to yesterday's traffic (at least one).
	var target_staff: int = 1
	if last_traffic > 0:
		target_staff = clampi(int(ceil(float(last_traffic) / float(throughput_per_staff))), 1, max_staff)
	set_staff(target_staff)

	# 2) Fair late-fee policy (aggressive squeezes a little harder).
	set_late_fee(3 if aggressive else 2)

	# 3) Marketing push when reputation is low and cash is comfortable.
	if marketing_left == 0 and reputation < 55.0 and cash > marketing_cost + 600 and can_run_marketing():
		run_marketing()

	# 4) Stock copies for every released title, sized to its current demand.
	var buffer: int = 400 if aggressive else 700
	for t in TITLE_COUNT:
		if not is_released(t, day):
			continue
		var want: int = _auto_target_copies(t)
		if _owned[t] >= want:
			continue
		var need: int = want - _owned[t]
		var cost: int = need * TITLE_COST[t]
		if cash - cost > buffer and can_buy_copies(t, need):
			buy_copies(t, need)

	# 5) Draw a loan to stay liquid while still solvent.
	if cash < 300 and net_worth() > 2500 and debt + 2000 <= max_debt and can_take_loan(2000):
		take_loan(2000)

	return tick_day()


## Deterministic target copy count for a title under auto-play: proportional to its
## CURRENT demand (hot new releases pull well above their eventual baseline), capped.
func _auto_target_copies(title: int) -> int:
	var d: float = demand(title, day)
	var per: float = 3.0 if _policy == "aggressive" else 2.5
	return clampi(int(round(d * per)), 0, 20)


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
	h = _fold(h, members)
	h = _fold(h, staff)
	h = _fold(h, marketing_left)
	h = _fold(h, late_fee_per_day)
	h = _fold(h, bankruptcy_days)
	h = _fold(h, win_target)
	h = _fold(h, illegal_attempts)
	h = _fold(h, last_income)
	for i in TITLE_COUNT:
		h = _fold(h, _owned[i])
		h = _fold(h, _available[i])
	for i in _r_title.size():
		h = _fold(h, _r_title[i])
		h = _fold(h, _r_due[i])
		h = _fold(h, _r_return[i])
		h = _fold(h, _r_new[i])
	for cat in ["rental_income", "late_fees", "tape_purchase", "wages", "rent", "interest", "marketing", "loan_draw", "loan_repay", "tape_salvage"]:
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
		"members": members,
		"staff": staff,
		"marketing_left": marketing_left,
		"bankruptcy_days": bankruptcy_days,
		"win_target": win_target,
		"illegal_attempts": illegal_attempts,
		"last_traffic": last_traffic,
		"last_served": last_served,
		"last_turned_away": last_turned_away,
		"last_rentals": last_rentals,
		"last_missed": last_missed,
		"last_returns": last_returns,
		"last_late": last_late,
		"last_damaged": last_damaged,
		"last_income": last_income,
		"start_cash": _start_cash,
		"base_traffic": base_traffic,
		"growth_goal": growth_goal,
		"max_days": max_days,
		"rental_period": rental_period,
		"rental_price_catalog": rental_price_catalog,
		"rental_price_new": rental_price_new,
		"new_release_window": new_release_window,
		"late_fee_per_day": late_fee_per_day,
		"max_late_fee": max_late_fee,
		"damage_chance": damage_chance,
		"return_min_hold": return_min_hold,
		"return_max_hold": return_max_hold,
		"store_rent": store_rent,
		"staff_wage": staff_wage,
		"throughput_per_staff": throughput_per_staff,
		"max_staff": max_staff,
		"marketing_cost": marketing_cost,
		"marketing_span": marketing_span,
		"marketing_mult": marketing_mult,
		"interest_bp": interest_bp,
		"max_debt": max_debt,
		"bankruptcy_floor": bankruptcy_floor,
		"bankruptcy_patience": bankruptcy_patience,
		"rep_drift": rep_drift,
		"hype_gain": hype_gain,
		"hype_lambda": hype_lambda,
		"member_signup_rate": member_signup_rate,
		"member_traffic_k": member_traffic_k,
		"member_base_churn": member_base_churn,
		"asset_frac_num": asset_frac_num,
		"asset_frac_den": asset_frac_den,
		"owned": _owned.duplicate(),
		"available": _available.duplicate(),
		"r_title": _r_title.duplicate(),
		"r_due": _r_due.duplicate(),
		"r_return": _r_return.duplicate(),
		"r_new": _r_new.duplicate(),
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
	members = int(data["members"])
	staff = int(data["staff"])
	marketing_left = int(data["marketing_left"])
	bankruptcy_days = int(data["bankruptcy_days"])
	win_target = int(data["win_target"])
	illegal_attempts = int(data["illegal_attempts"])
	last_traffic = int(data["last_traffic"])
	last_served = int(data["last_served"])
	last_turned_away = int(data["last_turned_away"])
	last_rentals = int(data["last_rentals"])
	last_missed = int(data["last_missed"])
	last_returns = int(data["last_returns"])
	last_late = int(data["last_late"])
	last_damaged = int(data["last_damaged"])
	last_income = int(data["last_income"])
	_start_cash = int(data["start_cash"])
	base_traffic = int(data["base_traffic"])
	growth_goal = int(data["growth_goal"])
	max_days = int(data["max_days"])
	rental_period = int(data["rental_period"])
	rental_price_catalog = int(data["rental_price_catalog"])
	rental_price_new = int(data["rental_price_new"])
	new_release_window = int(data["new_release_window"])
	late_fee_per_day = int(data["late_fee_per_day"])
	max_late_fee = int(data["max_late_fee"])
	damage_chance = float(data["damage_chance"])
	return_min_hold = int(data["return_min_hold"])
	return_max_hold = int(data["return_max_hold"])
	store_rent = int(data["store_rent"])
	staff_wage = int(data["staff_wage"])
	throughput_per_staff = int(data["throughput_per_staff"])
	max_staff = int(data["max_staff"])
	marketing_cost = int(data["marketing_cost"])
	marketing_span = int(data["marketing_span"])
	marketing_mult = float(data["marketing_mult"])
	interest_bp = int(data["interest_bp"])
	max_debt = int(data["max_debt"])
	bankruptcy_floor = int(data["bankruptcy_floor"])
	bankruptcy_patience = int(data["bankruptcy_patience"])
	rep_drift = float(data["rep_drift"])
	hype_gain = float(data["hype_gain"])
	hype_lambda = float(data["hype_lambda"])
	member_signup_rate = float(data["member_signup_rate"])
	member_traffic_k = float(data["member_traffic_k"])
	member_base_churn = float(data["member_base_churn"])
	asset_frac_num = int(data["asset_frac_num"])
	asset_frac_den = int(data["asset_frac_den"])
	_owned = (data["owned"] as PackedInt32Array).duplicate()
	_available = (data["available"] as PackedInt32Array).duplicate()
	_r_title = (data["r_title"] as PackedInt32Array).duplicate()
	_r_due = (data["r_due"] as PackedInt32Array).duplicate()
	_r_return = (data["r_return"] as PackedInt32Array).duplicate()
	_r_new = (data["r_new"] as PackedInt32Array).duplicate()
	# Rebuild per-title day telemetry arrays (not persisted; recomputed shape).
	_day_rentals = PackedInt32Array()
	_day_misses = PackedInt32Array()
	_day_rentals.resize(TITLE_COUNT)
	_day_misses.resize(TITLE_COUNT)
	for i in TITLE_COUNT:
		_day_rentals[i] = 0
		_day_misses[i] = 0
	_cat_totals = (data["cat_totals"] as Dictionary).duplicate(true)
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(data["rng_seed"])
	_rng.state = int(data["rng_state"])


## A canonical, order-stable serialization for byte-identical comparison in tests.
func snapshot_string() -> String:
	return JSON.stringify(save_data())
