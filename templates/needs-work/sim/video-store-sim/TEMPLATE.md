# Video Store Sim Template (80s VHS-rental-store management sim, 2D)

An 80s **VHS rental-store management sim** in the neon-Blockbuster / retail-tycoon
lineage. You OWN the store: a CATALOG of VHS TITLES across six genres, each of which
you BUY COPIES of. Every day a seeded FOOT TRAFFIC of customers walks in, each wants
a title (weighted by that title's **current rental demand**) and RENTS an available
copy — or, if every copy is out, MISSES (lost goodwill). Rentals return a few days
later; some LATE (late fees, a real revenue stream — but a harsh late-fee policy
CHURNS members), a few DAMAGED (the tape leaves stock). The core decision is how many
copies of the hot **new releases** vs the evergreen catalogue to stock. Reach a
net-worth goal to WIN, or bankrupt out to LOSE. Scaffold with:

```bash
python templates/tools/scaffold.py video-store-sim <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no
addons.

## What you get

- **`VideoStoreEngine`** (`scripts/video_store_engine.gd`) — the whole sim as a pure,
  seedable, headless-testable `RefCounted` (~950 lines):
  - **24 VHS titles** across six genres (Action / Comedy / Horror / Drama / Family /
    SciFi). 14 are evergreen **catalogue** titles (released in the past — at baseline
    demand from day 0); 10 are **new releases** that arrive during the run at a set
    day, each with a baseline popularity and a per-copy purchase cost (new releases
    cost more to buy). Reference data as hardcoded constants, never a DB table.
  - **New-release HYPE (the heart of the sim)** — a title's rental DEMAND is a pure
    function of time: `demand(t, day) = baseline + baseline·gain · e^(−lambda·weeks)`.
    A new release SPIKES to a multiple of its baseline the week it drops, then DECAYS
    exponentially over the weeks back toward its evergreen baseline. Stock too few
    copies of a hot release → missed rentals + lost goodwill; too many → the hype
    fades before they pay for themselves.
  - **The customer economy**: each day seeded **foot traffic** = base × reputation ×
    marketing × selection-breadth × membership × noise. Staff **throughput** caps how
    many are served (the rest are turned away). Each served customer wants a title
    (weighted by current demand) and RENTS an available copy → **rental income** (a
    NEW-RELEASE premium price), scheduling a return; if every copy is out it's a
    **MISSED** rental.
  - **Returns + late fees + damage**: rentals come back after 1–4 days; a return past
    its due date accrues a **late fee** (`late_days × policy`); a small chance the
    returned tape is **DAMAGED** and leaves stock entirely. Inventory integrity
    `owned == on-shelf + rented` holds for every title every day.
  - **Economy with strict MONEY CONSERVATION**: cash flow = rental income + late fees
    − tape purchases − rent − wages − loan interest (+ tape salvage, loan draws). Every
    dollar moves through a NAMED ledger flow — `cash == starting cash + Σ(ledger)`
    always holds. Tracks **CASH** and **NET WORTH** (cash + depreciated inventory −
    debt). All money is integer, so replays + saves are exact.
  - **Membership**: happy renters SIGN UP (members multiply foot traffic → repeat
    business); missed rentals + a harsh late-fee policy CHURN them.
  - **`is_legal`-gated actions**: `buy_copies` / `remove_copy` / `set_staff` /
    `hire_staff` / `set_late_fee` / `run_marketing` / `take_loan` / `repay_loan`.
    Illegal ones (unaffordable, non-positive quantity, unreleased title, over max
    staff / debt, repay with no debt) are rejected and leave state **byte-identical**
    (only an `illegal_attempts` counter moves).
  - **Progression**: reach `net worth ≥ start + growth_goal` to WIN; sit below the
    bankruptcy floor too long to LOSE; a `max_days` cap guarantees termination and is
    judged by net worth. Both outcomes are genuinely reachable by the deterministic
    auto-play.
  - **`auto_play_step()` / `auto_play_to_end()`** — a deterministic heuristic (size
    staff to the crowd, stock each title in proportion to its CURRENT demand so hot
    releases get more copies, run marketing when reputation sags, borrow to stay
    liquid while solvent) for demos + the full-run test.
  - `save_data()/load_data()` of the FULL state incl. the RNG (`snapshot_string()`
    gives a canonical form; `state_checksum()` an FNV-1a fingerprint). A `config` dict
    on `setup()` overrides any tuning constant (difficulty presets).
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one
  `VideoStoreEngine`, forwards every action (re-emitting `changed`), and adds the
  NoxDev ABI.
- **Store screen** (`scenes/store.tscn` + `scripts/store.gd`) — built in code: a HUD
  (cash, net worth, reputation, members, day/month, traffic + income + debt + staff),
  a scrollable CATALOG (each title's genre, current demand + new-release flag, copies
  owned / on-shelf / out, today's rentals vs misses), an ACTION panel (title picker +
  a quantity slider to BUY COPIES, a late-fee-policy slider, marketing / hire / fire /
  loan / repay, next-day + auto-play), and a live finance readout.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the whole
  store persists); `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

**Everything is a pure function of `(state, day, seeded RNG)`** — foot traffic, which
title each customer wants, returns + late fees + damage, membership sign-up / churn,
reputation drift, the auto-play heuristic, win/loss. The **same seed + the same
scripted actions always yield a byte-identical store after N days** (the
`state_checksum()` is stable within and across processes), and the whole thing is
playable and testable with no UI. Money is integer and only ever changes through
`_apply_cash(delta, category)`, so the conservation invariant is exact and saves
round-trip perfectly. Tune it by editing the constants at the top of the file or
passing a `config` dict — traffic, prices, hype gain/decay, bills, difficulty are all
auditable.

## How it plugs into the factory

- **Registry id** `video-store-sim` (`templates/registry.json`) — Godot 4.6.1-stable,
  `status: "validated"`.
- **Skeleton** `needs-work/sim/video-store-sim/skeleton` scaffolds with the standard NoxDev
  ABI, so godotsmith `menu_system` / `save_system` / `settings_system` drop in
  unchanged (the store already serialises through `save_data()/load_data()`).
- **Pure-engine + headless-probe convention**: the sibling of `mall-tycoon` — a
  deterministic integer-money economy with money conservation verified daily, driven
  by six headless probes.

## How to extend

1. **Bigger catalogue / more genres**: add rows to the `TITLE_*` constants (name /
   genre / baseline / release day / cost) — the demand, economy and UI pick them up
   with no other change.
2. **Sharper hype**: tune `hype_gain` / `hype_lambda` (config) for blockbuster spikes
   or slow-burn cult hits; add per-genre decay curves.
3. **Rental tiers**: overnight vs weekly rentals, member discounts, reservations for
   out-of-stock hot titles (feed the missed-rental path into a waitlist).
4. **Events + seasons**: seed holiday traffic spikes / a new-console recession into
   `_generate_traffic()`; they stay deterministic through the seeded RNG.
5. **Art**: swap the catalogue rows for VHS box-art cards keyed by genre and a
   neon-storefront backdrop.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the store already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor` import exit 0 with zero
script errors (all vars explicitly typed), and six headless probes (all `fails=0`):

- **economy** — 400 days of a scripted policy: the per-day reported `last_income`
  equals the tick's real cash change, the conservation invariant `cash == start +
  Σledger` holds every day, every ledger category is a DEFINED flow, net worth is
  computed right, and inventory integrity `owned == on-shelf + rented` holds per title.
- **determinism** — same seed → identical FNV-1a `state_checksum` mid-run and at the
  end AND across two separate processes (the `CANON=` value); a different seed
  diverges; setup/world state is itself seeded.
- **rental** — renting decrements available copies + schedules a return; a normal
  return restores the copy; overdue returns accrue late fees; a damaged tape leaves
  stock (owned drops, shelf not restored); availability gates rentals (all copies out
  → misses); inventory integrity holds through a mixed run.
- **hype** — a new release's demand spikes at release then decays monotonically over
  the weeks toward baseline (0 before release, converged after ~10 weeks); the same
  number of copies on a hot new release captures MORE rentals than on a cold catalogue
  title.
- **progression** — the deterministic auto-play reaches a **WIN** (net-worth goal) on
  the default store and a **LOSS** (bankruptcy) on a harsh config, every seed/policy
  run terminates under `max_days`, and a terminal store is frozen (further ticks are
  no-ops).
- **rules_ui** — every illegal action is rejected with meaningful state untouched
  (only `illegal_attempts` rises); the main scene builds its code UI (a CanvasLayer +
  101 labels + 9 buttons + 2 sliders + an option button); and the store round-trips
  through save/load unchanged via both the engine and the GameManager ABI, with
  lockstep continuation.
