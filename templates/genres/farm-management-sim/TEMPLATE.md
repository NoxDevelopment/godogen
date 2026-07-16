# Farm Management Sim Template (whole-farm operation & commodity economy sim, 2D)

A deeper redo of Maxis's **SIMFARM**: you run a whole farm **BUSINESS** from a top-down
desk — fields, crop rotation, soil chemistry, irrigation, weather, livestock, commodity
markets and machinery — as a deterministic integer-money economy sim. It is a sibling of
`dept-store-sim` and `mall-tycoon`, sharing their **money-conservation discipline** and
seasonal wrapped-Gaussian curves, but distinct: this is an **agronomy + commodity**
operation, not a retailer. It is also **distinct from `farming-sim`**, which is a
hands-on 2D top-down crop-tending game — this is the top-down MANAGEMENT/economy sim of
the whole farm operation. Rotate your fields, read the weather and the market, keep the
herds fed, and grow your net worth to a prosperity goal to WIN — or bankrupt out and get
FORECLOSED to LOSE. Scaffold with:

```bash
python templates/tools/scaffold.py farm-management-sim <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no
addons.

## What you get

- **`FarmEngine`** (`scripts/farm_engine.gd`) — the whole sim as a pure, seedable,
  headless-testable `RefCounted` (~1,200 lines):
  - **9 FIELDS (a 3×3 grid)**, each with its own **soil quality** and a live **soil
    NITROGEN** level. **6 CROPS** (corn, wheat, soybeans, cotton, hay, vegetables) — each
    with a growth duration, water need, plantable seasons, a nitrogen DRAW (or, for the
    soybean legume, a nitrogen FIX), a seed cost and a yield curve. Plant → grow →
    harvest. Reference data as hardcoded constants, never a DB table.
  - **Soil + crop ROTATION as a real per-field nitrogen balance (a distinctive system).**
    A field's yield is a function of its soil nitrogen: harvesting a heavy-feeder crop
    DRAWS nitrogen down, so replanting the same nutrient-draining crop (a MONOCULTURE)
    measurably DEPLETES the field and its yields DECLINE. Rotating in the nitrogen-FIXING
    legume (soybeans), applying FERTILIZER, or resting the field REPLENISHES nitrogen and
    yields hold or recover. `nutrient_factor(N) = clamp(N / optimal, floor, 1)` folds
    straight into the yield.
  - **Deterministic WEATHER + four SEASONS (a distinctive system).** `weather_for_day(d)`
    is a PURE HASH of `(seed, day)` — independent of the RNG stream the livestock draw
    from — so a season's rain / drought / frost / heat / pest events are reproducible and
    testable. Season shapes the odds (drought/heat cluster in summer, frost in winter).
    Weather modulates each field's daily growth condition and can DAMAGE a crop (frost
    hits warm-season crops, pests cut yield). **IRRIGATION** (a per-field toggle with a
    daily cost) buys back the water a drought takes away.
  - **LIVESTOCK**: three herds (cattle → milk, pigs → meat, chickens → eggs). Animals eat
    FEED from your feed stock (hay you grow, or feed you buy), produce daily goods that
    accumulate into commodity stock, BREED when well-fed (bounded by a per-type cap), and
    face daily MORTALITY (higher when underfed) resolved by the seeded RNG.
  - **COMMODITY MARKET as a real computed price curve (a distinctive system).** Each
    commodity's price is `base × (1 + Σ_k amp_k · sin(2π·day/period_k + phase_k))` with a
    seed-derived phase per commodity — a genuine multi-frequency wave, not a table — so a
    commodity's price VARIES over the year and **sell-timing changes revenue**. Buying
    seed / feed / fertilizer / machinery / livestock costs; selling crop and livestock
    products books at the CURRENT price.
  - **MACHINERY**: tractors and harvesters raise field THROUGHPUT (fields plantable /
    harvestable per day) and HARVEST EFFICIENCY (fewer losses at harvest), and trim the
    labour bill, at a purchase + daily maintenance + daily DEPRECIATION cost.
  - **Economy with strict INTEGER MONEY CONSERVATION**: cash flow = crop sales +
    livestock-product sales + livestock salvage − seed − feed − fertilizer − irrigation −
    machinery − maintenance − wages − overhead − livestock purchase − loan interest
    (+ loan draws/repay). Every dollar moves through a NAMED ledger flow via
    `_apply_cash(delta, category)` — `cash == starting cash + Σ(ledger)` holds **every
    day** (`conservation_ok()` recomputes it). Tracks **CASH** and **NET WORTH** (cash +
    land + depreciated machinery + stock + herds − debt). All money is integer, so replays
    and save round-trips are exact.
  - **Progression**: WIN by reaching `starting net worth + growth_goal`; LOSE on sustained
    bankruptcy (cash below the floor for the patience window); a MAX (`max_years × 360`)
    cap guarantees termination. Both outcomes are genuinely reachable by the deterministic
    auto-play heuristic.
  - **Determinism**: an FNV-1a `state_checksum()` folds the whole farm (fields, herds,
    stock, machinery, ledger, RNG state) into one int — byte-identical replays, stable
    ACROSS SEPARATE PROCESSES. Full `save_data()` / `load_data()` incl. the RNG.

- **`GameManager`** (`scripts/game_manager.gd`) — autoload singleton in the
  `game_manager` + `persistent` groups; owns one `FarmEngine`, forwards actions
  (each re-emits `changed`), and implements the NoxDev save ABI (the whole farm persists).

- **`farm.gd`** (`scripts/farm.gd`) — the farm-office screen, built entirely in code: the
  root `Control` `_draw()`s the 3×3 FIELD GRID (each cell coloured by its crop with a
  nitrogen-shaded soil tint, an irrigation border, a maturity ring, and projected-yield
  text), while a `CanvasLayer` holds the HUD (cash / net worth / day-season-year / weather
  / work capacity), a MARKET panel (per-commodity price + your stock), a
  HERDS · MACHINERY · FINANCE readout, and an ACTION panel (field / crop / animal /
  commodity pickers, a quantity slider, and buttons to plant / harvest / fertilize /
  irrigate / buy+sell livestock / buy feed / sell commodity / buy machinery / loan /
  advance-day + auto-play). Reads engine state and forwards actions only.

## Controls

- **Field / crop pickers + Plant / Harvest / Fertilize / Irrigate** — field-scoped
  agronomy: plant the picked crop into the picked fallow field, harvest a mature field,
  fertilize to add nitrogen, toggle a field's irrigation.
- **Animal / commodity pickers + quantity slider + Buy/Sell Herd, Buy Feed, Sell
  Commodity** — livestock and market actions.
- **Buy Tractor / Buy Harvester** — machinery. **Loan +6000 / Repay 6000** — finance.
- **> Next Day** advances one day; **>> Auto-Play** runs the deterministic heuristic.
- **Esc** pause · **F5** restart (input map: `pause`, `restart`).

## Headless probes (`_probes/`)

Each probe boots headless, prints one `DEBUG: … fails=N => OK` line, and quits:

- **`economy_probe`** — INTEGER money conservation holds every day over a multi-year run
  (`cash == start + Σledger`); `last_income` equals the tick's cash delta; every ledger
  category is a defined named flow; net worth reconciles.
- **`determinism_probe`** — same seed → identical FNV-1a checksum (mid-run and full-run)
  AND across two separate processes (`CANON=`); a different seed diverges; world-gen is
  seeded.
- **`soil_rotation_probe`** — under matched forced-clear weather, a monoculture field's
  corn yield DECLINES below its first cycle and below both a legume-rotated and a
  fertilized field's; irrigation lifts a drought-struck field's yield.
- **`livestock_market_probe`** — herds consume feed and produce sellable milk/eggs/meat
  (and breed); an unfed herd stops producing and loses head; a commodity's price varies
  over time so selling the same stock on a high-price day beats a low-price day.
- **`progression_probe`** — auto-play reaches a WIN (net-worth goal) and a LOSS
  (bankruptcy), every run terminates under the cap, and a terminal farm is frozen.
- **`rules_ui_probe`** — illegal actions are rejected with byte-identical state (harvest
  empty / plant out-of-season / plant over cash / over-cap livestock / oversell / sell
  feed / over-borrow / repay with no debt); the main scene builds its code UI; save/load
  round-trips through the engine and the GameManager ABI.

Run one:

```bash
C:/godot/Godot_v4.6.1-stable_win64_console.exe --headless \
  --path templates/genres/farm-management-sim/skeleton \
  res://_probes/economy_probe.tscn --quit-after 8000
```

## How it plugs into the factory

- **Registry id**: `farm-management-sim` (see `templates/registry.json`) — `status:
  validated`, skeleton at `genres/farm-management-sim/skeleton`.
- **NoxDev ABI**: autoload in `game_manager` + `persistent` groups with
  `save_data()`/`load_data()`; `default_bus_layout.tres` (Master/Music/SFX); `pause` +
  `restart` input actions; `scalable_text` group on UI. Wires straight into godotsmith's
  `menu_system` / `save_system` / `settings_system`.
- **Make it yours**: swap the CROP, LIVESTOCK, MACHINERY and COMMODITY catalogues and the
  weather / season / price-wave parameters — the money-conservation ledger, the nitrogen
  balance, the pure-hash weather and the computed market curve stay intact. Replace the
  `_draw()` field-grid blockout with field / crop / livestock sprites via the primitive
  recipes (see the registry `assetPlanHints`).
