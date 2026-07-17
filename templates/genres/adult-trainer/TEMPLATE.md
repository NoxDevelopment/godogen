# Adult Trainer Template (mature-themed raise/trainer sim, Princess-Maker lineage — SYSTEMS ONLY, 2D)

A mature-**themed** raise / **trainer** sim (Princess-Maker lineage) run as a **deterministic sim**.

> **This template ships the RAISER SYSTEMS ONLY.** A companion with five stat tracks, a weekly
> schedule of training activities with stamina/mood/money trade-offs, seeded events, an affection
> relationship meter, and stat-gated endings — plus a `mature_content` **gating flag that is OFF by
> default** and only calls **empty author hooks**. It contains **no explicit content**. An author
> who adds mature content is responsible for their own assets, an **age-verification gate**, and
> platform compliance. (Same clean-room approach as `dating-sim` and `adult-management`.)

Scaffold with:

```bash
python templates/tools/scaffold.py adult-trainer <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

## What you get

- **`TrainerEngine`** (`scripts/trainer_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG drives the weekly events, so a whole
  24-week raise replays **byte-identically** from a seed:
  - **Five stat tracks** — discipline / grace / wit / fitness / artistry.
  - **An activity table** — *study / etiquette / combat / art / drill* raise stats, *work* earns,
    *rest* recovers, *outing* courts affection — each with money / stamina / mood / affection deltas.
  - **Overtraining** — a draining activity attempted with too little stamina yields **halved gains +
    an extra mood hit**; and a **mood-scaled learning multiplier** (a happy trainee learns better).
  - **Seeded weekly events** — inspiration, a bad week, a fond moment, a windfall.
  - **A stat-gated ending resolver** — *Burnout* if mood/affection collapse, else *Devoted \<Track\>*
    / *\<Track\> Prodigy* / *Beloved Companion* / *Well-Rounded*.
  - **A `mature_content` gate** (off) whose `_mature_hook()` is **intentionally empty** — the gated
    milestone (an affection threshold) calls it and nothing happens; no content ships.
  - **`checksum()`** — an FNV-1a fold over the state — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** raise including RNG state.
- **A deterministic trainer auto-seat** — raises toward a target path (keep money/stamina/mood/
  affection above floors, then push the target stat + affection). `auto_play_to_end()` plays a whole
  raise.
- **`GameManager` autoload** — picks each week's activity, plus the NoxDev save/load ABI and an
  `autoplay` toggle.
- **Play surface** (`scenes/trainer_view.tscn` + `scripts/trainer_view.gd`) — the five stat-track
  bars, the money / stamina / mood / affection HUD, the weekly activity buttons, and an
  **OFF-by-default mature-content gate toggle** with a SYSTEMS-ONLY notice. **T** autoplay ·
  **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the stat tracks, the activity deltas, overtraining, the mood multiplier, the event
table, and the ending resolver — lives in `TrainerEngine` as pure data + functions. The view only
draws bars and forwards a weekly choice, which is why a whole raise is testable with **no UI**.

The heart is the trade-off loop: every activity spends *something* (money, stamina, mood, or
affection) to buy *something else*, and the ending is a pure function of where the companion lands
after 24 weeks — so "play" is resource management toward a target profile, not scripted beats. The
mature layer is deliberately just a flag + an empty hook at one affection milestone: the raise is
the whole game.

## How to extend

1. **A schedule planner**: let the player queue several weeks and preview the resource curve.
2. **Deeper activities + branching events**: prerequisites, tiered activities, event chains that
   fork on stats/affection.
3. **Multiple target endings + routes**: career, relationship, and hybrid endings with their own
   thresholds; a New Game+ that carries a stat over.
4. **A reactive portrait**: a companion portrait that shifts with mood/affection, plus a gift/
   wardrobe economy.
5. **Your gated layer (optional)**: if you ship a mature edition, wire `_mature_hook()` behind a real
   **age-verification** gate with **your own** assets and keep the default build gate-off.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed drives different events**.
- **partial determinism** — 12 weeks of the same seed produce an identical checksum across runs.
- **a real raise** — the greedy trainer runs a full 24-week raise, training the target stat while
  keeping resources above floors and courting affection, to a stat-gated ending. Validated: it
  reaches a **"Wit Prodigy" ending with wit 100 and affection 67** (meeting the target) — while the
  **`mature_content` gate stays OFF** for the whole run (asserted: SYSTEMS ONLY).

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> ending=Wit Prodigy wit=100 aff=67 total=157 won=true mature=false
# → PROBE PASS
```
