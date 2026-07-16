# Mall Tycoon Template (80s shopping-mall management sim, 2D)

An 80s **shopping-mall management sim** in the Theme-Park / RollerCoaster-Tycoon /
SimTower-of-retail lineage. You OWN the mall: a grid of leasable retail UNITS
across several floors. **Lease** units to tenants for steady rent, or
**owner-operate** stores yourself for a higher ceiling and higher risk. Pull in
**foot traffic** with amenities, anchor stores and marketing; customers spend and
you grow your **net worth**. Reach a net-worth goal to WIN, or bankrupt out to
LOSE. Scaffold with:

```bash
python templates/tools/scaffold.py mall-tycoon <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`MallEngine`** (`scripts/mall_engine.gd`) — the whole tycoon as a pure,
  seedable, headless-testable `RefCounted`:
  - A **grid of units** across floors, each `EMPTY` / `LEASED` / `OWNER-OPERATED`,
    with a **location desirability** (anchor ends and ground floor draw the crowd;
    upper mid-corners are quiet).
  - **9 store types** (Record Store, Arcade, Video Rental, Food Court, Department
    Store [anchor], Toy Store, Electronics, Apparel, Bookstore) — each with a
    customer **appeal**, average **spend**, base **rent**, wholesale cost and an
    anchor flag.
  - **The customer economy** (the sim core): each day seeded **foot traffic** =
    base × reputation × amenities × anchors × marketing × noise. Customers
    distribute to occupied stores by **appeal × desirability** and SPEND →
    revenue. A LEASED unit pays you **rent** (a tenant pays out of the sales their
    store makes — a store starved of traffic defaults, so rent is tied to the
    economy, not free money). An OWNER store keeps **revenue − stock − staff**.
  - **Economy with money conservation**: cash flow = rent + owner profit −
    maintenance − wages − amenity upkeep − loan interest. Every dollar moves
    through a NAMED ledger flow — `cash == starting cash + Σ(ledger)` always
    holds. Tracks **CASH** and **NET WORTH** (cash + property value − debt). All
    money is integer, so replays + saves are exact.
  - **`is_legal`-gated actions**: `lease` / `operate` / `buy_stock` / `hire_staff`
    / `set_rent` / `add_amenity` (4 amenities) / `evict` / `run_marketing` /
    `take_loan` / `repay_loan`. Illegal ones (unaffordable, occupied unit,
    evict-empty, over max debt) are rejected and leave state **byte-identical**.
  - **Time**: `tick_day()` runs a fixed pipeline (traffic → serve → bills →
    marketing decay → reputation drift → tenant satisfaction + retention → month
    close for rent + interest → judge). Unhappy tenants quit → vacancy.
  - **Win / loss**: reach `net worth ≥ start + growth_goal` to WIN; sit below the
    bankruptcy floor too long to LOSE. Both genuinely reachable.
  - **`auto_play_step()`** — a deterministic heuristic (lease vacant units for
    variety incl. an anchor, restock owner stores, buy amenities + marketing when
    comfortable) for demos + the full-run test.
  - `save_data()/load_data()` of the FULL state incl. the RNG (`snapshot_string()`
    gives a byte-identical canonical form). A `config` dict on `setup()` overrides
    any tuning constant (difficulty presets).
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `MallEngine`,
  forwards every action (re-emitting `changed`), and adds the NoxDev ABI.
- **Mall screen** (`scenes/mall.tscn` + `scripts/mall.gd`) — built in code: the
  mall grid (units coloured by state / store type), a HUD (cash, net worth,
  reputation, month/day, foot traffic + income, occupancy, debt), an action panel
  (store/amenity pickers + lease/operate/evict/restock/hire/marketing/loan/rent/
  next-day/auto-play), and a live tenant + finance readout.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the
  whole mall persists); `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

**Everything is a pure function of `(state, day, seeded RNG)`** — traffic, customer
distribution, every action's effect, tenant satisfaction + retention, reputation
drift, the auto-play heuristic, win/loss. The **same seed + the same scripted
actions always yield a byte-identical mall after N days**, and the whole thing is
playable and testable with no UI. Money is integer and only ever changes through
`_apply_cash(delta, category)`, so the conservation invariant is exact and saves
round-trip perfectly. Tune it by editing the constants at the top of the file or
passing a `config` dict — rates, rents, bills, difficulty are all auditable.

## How to extend

1. **More floors / bigger malls**: bump `floors` / `cols` in the config; the grid,
   desirability and economy all scale.
2. **Richer stores**: add rows to the `STORE_*` catalogue (name/appeal/spend/rent/
   wholesale/anchor) — the sim picks them up with no other change.
3. **Events + seasons**: seed holiday traffic spikes / recessions into
   `_generate_traffic()`; they stay deterministic through the seeded RNG.
4. **Tenant personalities**: give each store type a rent-tolerance / haggling
   curve feeding `_age_tenants()` for negotiation mechanics.
5. **Art**: swap the grid `Panel` blockout colours for store-front sprites and the
   readout rows for tenant portrait cards.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the mall already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor` import exit 0 with zero
script errors (all vars typed), and seven headless probes (all `fails=0`):

- **economy** — 120 days: the per-day reported cash delta equals the real change,
  the conservation invariant holds every day, net worth is computed right, every
  ledger category is a DEFINED flow, and month-close rent equals the solvent
  tenants' rent.
- **customer** — traffic is deterministic under a seed; amenities + reputation
  raise traffic vs an identical-seed control (every day and in total); a leased
  unit yields full rent on healthy traffic; a stocked owner store earns revenue
  while a stock-less one earns nothing.
- **actions** — lease / operate / buy_stock / amenity / set_rent / marketing /
  loan / evict each have their real effect, and every illegal variant is rejected
  with byte-identical state.
- **fullrun** — a deterministic auto-play reaches a **WIN** on a good config and a
  **LOSS** (bankruptcy) on a harsh one, legal states throughout, within the cap.
- **determinism** — same seed + same scripted actions → byte-identical snapshot;
  a different seed diverges; auto-play is deterministic too.
- **uibuild** — the scene builds (18 unit cells + HUD + action panel) and an
  action advances the day + refreshes the HUD.
- **saveload** — mid-game save → mutate → load equals the snapshot, byte-identical,
  through both the engine and the GameManager ABI, with lockstep continuation.
