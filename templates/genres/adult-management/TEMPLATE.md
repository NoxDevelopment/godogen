# Adult Management Template (mature-themed venue/agency tycoon — SYSTEMS ONLY, 2D)

A mature-**themed** venue / agency **management tycoon** run as a **deterministic sim**.

> **This template ships the MANAGEMENT SYSTEMS ONLY.** A staff roster, station upgrades, a seeded
> daily client flow, a skill-matching shift-assignment algorithm, and a cash/reputation economy —
> plus a `mature_content` **gating flag that is OFF by default** and only calls **empty author
> hooks**. It contains **no explicit content**. An author who adds mature content is responsible for
> their own assets, an **age-verification gate**, and platform compliance. (Same clean-room approach
> as the `dating-sim` template.)

Scaffold with:

```bash
python templates/tools/scaffold.py adult-management <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

## What you get

- **`VenueMgmtEngine`** (`scripts/venue_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG drives the client flow, so a whole
  run replays **byte-identically** from a seed:
  - **A staff roster** — skill / stamina / mood / popularity / wage per person; **hire** toward a
    cap.
  - **Stations** you open and **upgrade** — each adds shift capacity and an income multiplier.
  - **A seeded daily client flow** — count + tier scale with **reputation** + **marketing**.
  - **A pure greedy shift-assignment algorithm** — rested staff (sorted by skill) matched to the
    highest-budget clients across the best rooms, with an **effective-skill vs client-demand** check
    that pays out + builds reputation on a good match and loses reputation on an under-skilled one.
  - **A close-of-day economy** — wages + a **rising overhead** (late-game pressure), then rest
    recovery — and **win** (a revenue + reputation goal) / **lose** (bankruptcy or the day cap).
  - **A `mature_content` gate** (off) whose `_mature_hook()` is **intentionally empty** — the gated
    milestone (`premium_service`) calls it and nothing happens; no content ships.
  - **`checksum()`** — an FNV-1a fold over the state — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A deterministic manager auto-seat** — hires toward a full roster, opens/upgrades stations on a
  cash buffer, runs marketing when reputation lags, and advances the shift. `auto_play_to_end()`
  plays a whole run.
- **`GameManager` autoload** — drives the management actions + advances the day, plus the NoxDev
  save/load ABI and an `autoplay` toggle.
- **Play surface** (`scenes/venue_view.tscn` + `scripts/venue_view.gd`) — the roster with stat bars,
  the stations, a cash / reputation / day HUD, management buttons, and an **OFF-by-default
  mature-content gate toggle** with a SYSTEMS-ONLY notice. **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the roster, station capacity/multipliers, the seeded client flow, the shift
assignment, the close-of-day economy, and win/lose — lives in `VenueMgmtEngine` as pure data +
functions. The view only draws bars and forwards button clicks, which is why a whole run is testable
with **no UI**.

The core is the shift: it's a small **assignment problem** solved greedily — clients sorted by
budget, staff by skill, rooms by bonus, then matched down the line with an effective-skill check
that decides payout vs a reputation hit. That single algorithm is what both the human's *Advance
day* and the AI manager call, so they can't diverge. The mature layer is deliberately just a
flag + an empty hook at one milestone: the economy is the whole game.

## How to extend

1. **Hands-on assignment**: let the player drag specific staff onto specific clients / stations
   instead of the auto-shift, and add a weekly **schedule grid**.
2. **Staff depth**: traits, specialities, training, contracts, morale events, loyalty.
3. **Events + risk**: a compliance/"heat" meter, inspections, random event cards, competing venues.
4. **Progression**: multiple venues, a prestige/relocation loop, reputation-gated client tiers.
5. **Your gated layer (optional)**: if you ship a mature edition, wire `_mature_hook()` behind a
   real **age-verification** gate with **your own** assets and keep the default build gate-off.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed drives a different client flow**.
- **partial determinism** — 6 managed days of the same seed produce an identical checksum across
  runs.
- **a real run** — the greedy manager hires, upgrades, and runs seeded shifts to grow cash +
  reputation to a genuine terminal. Validated: it **hits the goal by day 11 with $12,063 and
  reputation 92** — while the **`mature_content` gate stays OFF for the whole run** (asserted by the
  probe: SYSTEMS ONLY, no explicit content).

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> day=11 cash=12063 rep=92 staff=6 rooms=3 won=true mature=false
# → PROBE PASS
```
