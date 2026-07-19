# Department Store Sim Template (80s big-box department-store & mail-order sim, 2D)

An 80s **big-box department-store** management sim in the Kmart / Sears-of-the-catalog
era — a sibling of `mall-tycoon` and `video-store-sim`, sharing their deterministic
integer-money economy and **money-conservation discipline**, but distinct: this is a
MULTI-DEPARTMENT retailer with a **mail-order CATALOGUE** channel and **seasonal
demand**, not a mall of leased units and not a single-category rental shop. You OWN the
store: EIGHT DEPARTMENTS, each with its own product lines, inventory, staffing, floor
space and seasonal demand profile. Stock each department AHEAD of its season, work the
catalogue, and clear the leftovers before the next season. Reach a net-worth goal to
WIN, or bankrupt out to LOSE. Scaffold with:

```bash
python templates/tools/scaffold.py dept-store-sim <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no
addons.

## What you get

- **`DeptStoreEngine`** (`scripts/dept_store_engine.gd`) — the whole sim as a pure,
  seedable, headless-testable `RefCounted` (~1,000 lines):
  - **8 departments × 4 product lines = 32 lines** (Apparel, Electronics, Toys,
    Appliances, Home & Garden, Automotive, Jewelry, Sporting Goods). Each line has a
    per-unit cost, a base shelf price (→ margin), and a baseline demand weight; each
    department carries its own staffing, floor-space allocation and seasonal profile.
    Reference data as hardcoded constants, never a DB table.
  - **Seasonal demand (a real curve, not a table)** — each department's demand is a pure
    function of the day-of-year, a sum of wrapped-Gaussian season bumps
    `season(dept, day) = 1 + Σ_k amp_k · e^(−dist(doy, center_k)² / (2·width_k²))`.
    Toys & Electronics SPIKE in the Christmas window; Home & Garden peaks in spring;
    Jewelry at Valentine's, Mother's Day and Christmas; Automotive & Sporting Goods in
    summer. `demand(line, day) = base · season(dept, day) · markdown_boost`.
  - **The mail-order CATALOGUE (the distinctive channel)** — PUBLISH a seasonal catalogue
    (an up-front print cost) and for its run you open a SECOND demand stream that reaches
    buyers the physical floor never sees (rural / remote — NOT gated by store foot
    traffic or floor staff), drawing from the SAME shared inventory. Catalogue orders
    RESERVE stock into transit and SHIP after a LEAD TIME (cash lands later) with a
    per-order fulfillment fee. A real trade-off: print + fulfillment vs incremental
    reach — a well-stocked store with little floor traffic still moves units through the
    book.
  - **In-store customer economy**: each day seeded **foot traffic** = base × reputation ×
    marketing × overall-season × staff-presence × noise. Each customer visits a
    DEPARTMENT (weighted by its lines' demand × its floor space) and wants a line within
    it; per-department STAFF THROUGHPUT caps how many that department serves (the rest
    are turned away). A served customer BUYS if the line has stock (→ revenue, on_hand
    consumed) — otherwise it's a STOCKOUT (lost sale + goodwill hit).
  - **Markdowns / clearance**: unsold seasonal stock AGES; a per-line MARKDOWN cuts the
    shelf price (recovering cash but slashing margin) AND lifts the line's demand pull,
    clearing aging inventory before it dead-weights the floor. A `liquidate` lever dumps
    dead stock to a jobber at salvage value as a last resort.
  - **Economy with strict INTEGER MONEY CONSERVATION**: cash flow = in-store revenue +
    catalogue revenue + liquidation − restock purchases − wages − overhead − marketing −
    catalogue print − catalogue fulfillment − loan interest (+ loan draws/repay). Every
    dollar moves through a NAMED ledger flow via `_apply_cash(delta, category)` — `cash
    == starting cash + Σ(ledger)` holds every day. Tracks **CASH** and **NET WORTH**
    (cash + depreciated inventory − debt). All money is integer, so replays + saves are
    exact.
  - **Unit inventory invariant**: for every product line,
    `purchased == on_hand + in_transit + consumed` at all times — restock, in-store sale,
    catalogue reservation, shipment and liquidation are the only unit transitions; no
    unit is ever minted or lost.
  - **Reputation** moves with in-stock rate (fill rate), service (staffing adequacy vs
    turn-aways) and fair pricing (active markdowns), dragged by stockouts.
  - **`is_legal`-gated actions**: `restock` / `liquidate` / `set_markdown` /
    `set_dept_staff` / `hire_staff` / `set_dept_space` / `publish_catalogue` /
    `run_marketing` / `take_loan` / `repay_loan`. Illegal ones (unaffordable, non-positive
    qty, invalid line, over the staff headcount cap, over the floor total, out-of-range
    markdown, liquidate more than on hand, over-borrow, repay with no debt) are rejected
    and leave state **byte-identical** (only an `illegal_attempts` counter moves).
  - **Progression**: reach `net worth ≥ start + growth_goal` to WIN; sit below the
    bankruptcy floor too long to LOSE; a `max_days` cap guarantees termination (judged by
    net worth). Both outcomes are genuinely reachable by the deterministic auto-play.
  - **`auto_play_step()` / `auto_play_to_end()`** — a deterministic heuristic (allocate
    staff + floor space toward the departments in season, stock each line ahead of its
    demand, mark down aging stock to clear it, publish a catalogue when the book's season
    is strong, run marketing when reputation sags, borrow to stay liquid) for demos + the
    full-run test.
  - `save_data()/load_data()` of the FULL state incl. the RNG (`snapshot_string()` gives
    a canonical form; `state_checksum()` an FNV-1a fingerprint). A `config` dict on
    `setup()` overrides any tuning constant (difficulty presets).
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `DeptStoreEngine`,
  forwards every action (re-emitting `changed`), and adds the NoxDev ABI.
- **Store-floor screen** (`scenes/store_floor.tscn` + `scripts/store_floor.gd`) — built
  in code: a HUD (cash, net worth, reputation, day/month + season, floor traffic +
  in-store/catalogue income), a per-DEPARTMENT panel (season, staff, space, on-hand,
  today's sales), a per-LINE list of the selected department (cost / shelf price /
  on-hand / age / markdown / today), an ACTION panel (department + line pickers, quantity
  slider to restock, markdown slider, hire/space +/−, publish-catalogue, marketing, loan,
  next-day + auto-play), and a live finance readout.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the whole
  store persists); `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

**Everything is a pure function of `(state, day, seeded RNG)`** — foot traffic, which
department each customer visits, catalogue orders + shipments, reputation drift, the
auto-play heuristic, win/loss. The **same seed + the same scripted actions always yield a
byte-identical store after N days** (the `state_checksum()` is stable within and across
processes), and the whole thing is playable and testable with no UI. Money is integer and
only ever changes through `_apply_cash(delta, category)`, so the conservation invariant is
exact and saves round-trip perfectly; every unit is accounted for across
shelf / in-transit / consumed. Tune it by editing the constants at the top of the file or
passing a `config` dict — traffic, prices, season bumps, catalogue reach/lead-time,
markdown elasticity, bills, difficulty are all auditable.

## How it plugs into the factory

- **Registry id** `dept-store-sim` (`templates/registry.json`) — Godot 4.6.1-stable,
  `status: "validated"`.
- **Skeleton** `needs-work/sim/dept-store-sim/skeleton` scaffolds with the standard NoxDev ABI,
  so godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged (the
  store already serialises through `save_data()/load_data()`).
- **Pure-engine + headless-probe convention**: the sibling of `mall-tycoon` and
  `video-store-sim` — a deterministic integer-money economy with money conservation
  verified daily, driven by six headless probes.

## How to extend

1. **More departments / lines**: add rows to the `DEPT_*`, `SEASON_BUMPS` and `LINE_*`
   constants — the demand, economy and UI pick them up with no other change.
2. **Sharper seasons**: retune the `SEASON_BUMPS` centers / widths / amplitudes (Black
   Friday, tax-refund spring, summer clearance) or add per-line season overrides.
3. **Richer catalogue**: tiered shipping speeds, catalogue-only exclusives, backorders
   (feed catalogue stockouts into a waitlist), a separate warehouse inventory.
4. **Credit + private label**: store-charge accounts (interest income), house brands with
   fatter margins, loss-leaders that pull traffic.
5. **Art**: swap the department/line text rows for department-front sprites and a
   catalogue-page backdrop; add currency / department icons.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the store already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor` import exit 0 with zero script
errors (all vars explicitly typed), and six headless probes (all `fails=0`):

- **economy** — 400 days of a scripted policy: the per-day reported `last_income` equals
  the tick's real cash change, the conservation invariant `cash == start + Σledger` holds
  every day, every ledger category is a DEFINED flow, net worth is computed right, and the
  unit inventory invariant `purchased == on_hand + in_transit + consumed` holds per line.
- **determinism** — same seed → identical FNV-1a `state_checksum` mid-run and at the end
  AND across two separate processes (the `CANON=` value); a different seed diverges;
  setup/world state is itself seeded.
- **dept_catalogue** — an in-store sale decrements the right department's line stock;
  a stockout blocks a sale (no oversell); with the floor's traffic throttled to near
  zero, publishing a catalogue moves far MORE units than the no-catalogue baseline
  (incremental reach), and its print cost is charged up front while revenue lands only
  AFTER the lead time (cost + lead time modeled).
- **seasonal** — each department's `season_mult` peaks in its window (Toys / Electronics
  at Christmas, Home & Garden in spring, Jewelry at Valentine's) versus its trough, and a
  department's share of total demand rises in season; a MARKDOWN on aged stock clears
  MORE units (less leftover) at a lower price / thinner margin while still recovering
  cash above salvage value.
- **progression** — the deterministic auto-play reaches a **WIN** (net-worth goal) on the
  default store and a **LOSS** (bankruptcy) on a harsh config, every seed/policy run
  terminates under `max_days`, and a terminal store is frozen (further ticks are no-ops).
- **rules_ui** — every illegal action is rejected with meaningful state untouched (only
  `illegal_attempts` rises); the main scene builds its code UI (a CanvasLayer + 101
  labels + 14 buttons + 2 sliders + 2 option buttons); and the store round-trips through
  save/load unchanged via both the engine and the GameManager ABI, with lockstep
  continuation.
