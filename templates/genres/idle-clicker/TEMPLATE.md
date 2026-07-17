# Idle Clicker Template (Cookie Clicker-lite incremental with generators + prestige, 2D)

A Cookie-Clicker-lineage **incremental / idle** game run as a **deterministic
fixed-timestep sim** at 60 ticks/sec: tap to earn currency, spend it on **generators**
(each with a ×1.15 escalating cost + passive output) and one-off **upgrades**, and chase
seeded **golden** bonuses on the way to a prestige-style **ascension** milestone. It is OUR
OWN engine with generic content (no trademarks) — a pure, seedable, deterministic engine.
Scaffold with:

```bash
python templates/tools/scaffold.py idle-clicker <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`IdleEngine`** (`scripts/idle_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. The **only** randomness is the seeded
  golden-bonus schedule, so a whole run replays **byte-identically** from a seed:
  - **7 generators** (Clicker … Lab) with **compounding ×1.15 costs** + per-building output.
  - **8 one-off upgrades** gated by ownership — click-power ×2s, per-generator ×2s, and an
    all-generator ×2.
  - **A manual click** whose power scales with upgrades (and frenzy).
  - **Golden bonuses** that spawn on a seeded **15–40s** cadence and, if tapped in their 5s
    window, grant either a **lump** (90s of current output, with an early-game floor) or a
    **×7 frenzy** for 7s (boosting both click + passive income).
  - **Ascension** — a total-earned milestone as the **prestige seam**.
  - **Big numbers** are handled in doubles, and the `checksum()` folds **string-formatted**
    floats so it never overflows and stays cross-process byte-identical.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A greedy auto-seat** (`ai_input`) — clicks, grabs every golden, and buys the best value
  (cheapest available upgrade, else the best cps-per-cost generator). `auto_step()` /
  `auto_play_ticks(n)` run a whole idle session.
- **`GameManager` autoload** — steps the sim in `_physics_process` applying the player's
  captured clicks/buys/taps, plus the NoxDev save/load ABI and an `autoplay` toggle.
- **Play surface** (`scenes/idle_view.tscn` + `scripts/idle_view.gd`) — the big **clickable
  cookie** (frenzy-tinted), the counter + cps, a **generator shop**, the available
  **upgrades**, an **ascension** progress bar, and the golden bonus when it appears — with
  abbreviated **K/M/B/T** formatting. Click the cookie · click a shop row to buy · click the
  golden · **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — click + passive income, the compounding generator costs, the gated upgrades,
the golden schedule + bonuses, frenzy, and ascension — lives in `IdleEngine` as pure data +
functions stepped by `tick(input)`. The view only captures input and reads state, which is
why the whole run is playable and testable with **no UI**, and why it **drops in as a
meta-layer** in a bigger game (an idle sub-economy, an offline-earnings screen): keep the
engine, feed a `{click, buy_gen, buy_up, tap}` dict per tick, read `cookies` / `cps()`.

A note on determinism with an idle game: an idle economy is *already* a pure function of the
tick count and the player's buys — the one place randomness enters is the golden schedule, so
that is the only thing seeded. And because the currency grows into the billions, the checksum
folds **`%.4f`-formatted** values rather than raw ints, so it can't overflow and still matches
across processes — which is what lets NoxQA smoke-run the greedy seat headlessly and diff it.

## How to extend

1. **Prestige loop**: on ascension, reset and grant a permanent multiplier from a
   heavenly-chip count (total-earned ^ 0.5) — the ascension flag is the hook.
2. **Offline earnings**: on load, credit `cps() × elapsed` (elapsed passed in, not read from a
   clock — keep it deterministic/testable).
3. **More generators + tiered upgrades**: extend `GENERATORS` / `UPGRADES`; the shop, AI, and
   save/load pick them up.
4. **Achievements + a news ticker**: track milestones and surface flavour text.
5. **Golden variety**: add "click frenzy", "lucky", and "wrath" (risk) golden kinds in the
   `tap_golden` branch.
6. **Balancing**: the costs, outputs, and golden cadence are constants at the top — tune the
   curve or add a spreadsheet-driven table.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the whole run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed; note GDScript's `%` has no `%e` specifier so numbers use `%f`/abbreviation),
a **40-frame headless main-scene smoke** runs clean, and the headless **determinism +
playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run to completion twice yields an identical final
  `checksum()`; a **different seed diverges** (the golden schedule differs).
- **partial determinism** — 3,000 ticks of the same seed produce an identical mid-run
  checksum.
- **real economy** — the greedy seat grows the currency, **buys generators + upgrades**, and
  **reaches the ascension milestone**. Validated: over 12 sim-minutes the seat bakes **1.41M
  total at 1067/s across 142 generators + 5 upgrades**, reaching ascension.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> total=1411448 cookies=40236 cps=1066.6 buildings=142 upgrades=5 ascended=true
# → PROBE PASS
```
