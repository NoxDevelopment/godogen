# Adult Sandbox Template (mature-themed open life/relationship sandbox — SYSTEMS ONLY, 2D)

A mature-**themed** open **life / relationship sandbox** run as a **deterministic sim**. (This also
completes the original 17-genre taxonomy as gap **#17**.)

> **This template ships the SANDBOX SYSTEMS ONLY.** An open map of locations, a time-of-day /
> day-of-week clock, player needs (energy / money / fitness / mood), NPCs on seeded weekly
> **schedules**, and multi-NPC **relationships** with stages — plus a `mature_content` **gating flag
> that is OFF by default** and only calls **empty author hooks**. It contains **no explicit
> content**. An author who adds mature content is responsible for their own assets, an
> **age-verification gate**, and platform compliance. (Same clean-room approach as `dating-sim`,
> `adult-management`, `adult-trainer`, and `adult-puzzle-dating`.)

Scaffold with:

```bash
python templates/tools/scaffold.py adult-sandbox <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

## What you get

- **`SandboxEngine`** (`scripts/sandbox_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG lays out the NPC schedules, so a whole
  run replays **byte-identically** from a seed:
  - **An open map** of 7 locations (home / work / gym / bar / park / cafe / shop) with **free travel**
    (repositioning) and a **block-based clock** — 6 time blocks per day across 21 days, with a
    day-of-week.
  - **Player needs** — energy / money / fitness / mood — driven by context **actions**: *work* earns
    + drains, *train* raises fitness, *sleep* recovers + advances the day, *relax* lifts mood, *buy*
    stocks a gift, *wait* passes a block.
  - **NPCs on seeded weekly schedules** — each NPC is at a specific public location each
    day-of-week/block, so you have to **find them** to interact.
  - **Multi-NPC relationships** with 5 **stages** (Stranger → Acquaintance → Friend → Close →
    Partner), advanced by socializing (scaled by mood + per-NPC affinity) and gifting.
  - **An open-ended progress score** — no hard win; the sandbox just runs its days.
  - **A `mature_content` gate** (off) whose `_mature_hook()` is **intentionally empty** — the gated
    milestone (a Partner-stage relationship) calls it and nothing happens; no content ships.
  - **`checksum()`** — an FNV-1a fold over the state — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A deterministic resident auto-seat** — manages needs (sleep when exhausted, work when broke,
  train once a day, stock a gift when flush) and deepens the best relationship by travelling to where
  that NPC is *this block* and socializing/gifting. `auto_play_to_end()` plays a whole run.
- **`GameManager` autoload** — drives travel + actions, plus the NoxDev save/load ABI and an
  `autoplay` toggle.
- **Play surface** (`scenes/sandbox_view.tscn` + `scripts/sandbox_view.gd`) — the location map (with
  *who is where*), the day/block clock, the needs bars, the NPCs present + their stages, the context
  actions, and an **OFF-by-default mature-content gate toggle** with a SYSTEMS-ONLY notice.
  **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the map + clock, the needs economy, the seeded NPC schedules, and the relationship
stages — lives in `SandboxEngine` as pure data + functions. The view only draws the map/bars and
forwards clicks, which is why a whole run is testable with **no UI**.

Two design choices make it a *sandbox* rather than a script: **travel is free but actions cost
time**, so the interesting decision each block is *what to do and with whom*, not pathfinding; and
**NPCs live on seeded weekly schedules**, so who you can deepen a relationship with depends on when
and where you show up. The deterministic seat proves both — it reads each NPC's current-block
location, goes there, and socializes — and because that seat and the human's clicks call the *same*
action functions, they can't diverge. The mature layer is deliberately just a flag + an empty hook at
the Partner stage: the life-and-relationships loop is the whole game.

## How to extend

1. **A walkable map + storylets**: a 2D town you move through, NPC personalities, quest/storylet
   chains triggered by stage + time.
2. **Deeper needs + economy**: hunger/hygiene/social meters, jobs with promotions, rent, an
   apartment you furnish.
3. **Relationship depth**: memory of past interactions, jealousy, group events, per-NPC preferences
   and gift tastes (borrow the `adult-puzzle-dating` preference model).
4. **A phone/menu layer**: message NPCs, schedule dates, track quests.
5. **Your gated layer (optional)**: if you ship a mature edition, wire `_mature_hook()` behind a real
   **age-verification** gate with **your own** assets and keep the default build gate-off.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed lays out different NPC schedules** (→ different relationship outcomes, verified by
  differing checksums).
- **partial determinism** — 30 steps of the same seed produce an identical checksum across runs.
- **a real run** — the greedy resident navigates the map, manages needs, and deepens multi-NPC
  relationships to a genuine terminal (the end of the sandbox). Validated: it lifts all four NPCs to
  **Close+ with a Partner-stage relationship** (progress 246) — while the **`mature_content` gate
  stays OFF** for the whole run (asserted: SYSTEMS ONLY).

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> day=22 progress=246 best=Partner maxrel=100 won=true mature=false
# → PROBE PASS
```
