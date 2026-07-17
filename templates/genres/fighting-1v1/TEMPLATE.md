# Fighting Game Template (Street Fighter / MK-lite 1v1 with real frame data, 2D)

A Street-Fighter / Mortal-Kombat-lineage **1-v-1 fighting game** run as a
**deterministic fixed-timestep sim** at 60 ticks/sec with **real frame data** — so play
is about **frame advantage, spacing, blocking high/low, and combos**, not ad-hoc timers.
It is OUR OWN engine with generic content (no trademarks) — a pure, seedable,
deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py fighting-1v1 <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`FightEngine`** (`scripts/fight_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. Its single RNG seeds the AI personalities +
  a little starting jitter and the sim is otherwise pure, so a whole best-of-3 replays
  **byte-identically** from a seed — exactly what a **rollback / lockstep netcode**
  fighter needs:
  - **5 moves** (light/heavy punch, light/heavy kick, a special **projectile**) each with
    genuine **startup / active / recovery** frames, damage, hit/blockstun, range, and a
    hit **height** (high overhead / mid / low).
  - **A fighter state machine** — idle / walk / jump (with gravity) / crouch / block /
    attack / hitstun / blockstun — driven by a per-tick input `{dir, up, down, atk}`.
  - **Blocking** by holding away, with the **correct guard required per height** (stand-
    block overheads, crouch-block lows), and **chip damage** on block.
  - **Combos** via hitstun + special-**cancels** out of cancelable normals that have
    connected; **pushback** + body separation.
  - **Projectiles** that travel and hit; **rounds** as a **best-of-3** with a 60-second
    timer (higher HP wins a timeout) and KO detection.
  - **`checksum()`** — an FNV-1a fold over the whole state — the cross-process determinism
    proof.
  - `save_data()` / `load_data()` snapshot the **entire** match including RNG state.
- **Heuristic AI** (`ai_input`) with a **seeded personality** (aggression + reaction):
  blocks on reaction, **anti-airs** jump-ins with heavy punch, pokes/combos in range,
  **zones** with the projectile, and manages spacing. `auto_step()` / `auto_play_to_end()`
  drive **both** fighters for a full self-playing match.
- **`GameManager` autoload** — steps the sim in `_physics_process` (60Hz) with the human's
  sampled inputs (P1) against the AI (P2), plus the NoxDev save/load ABI and a `player_auto`
  attract toggle.
- **Play surface** (`scenes/fight_view.tscn` + `scripts/fight_view.gd`) — draws the stage,
  both fighters **with the active-frame hitbox extended** (so spacing + whiffs read), health
  bars, round pips, the timer, and projectiles. **P1**: A/D move (hold back = block) · W
  jump · S crouch · F/G/V/B/H attacks · **T** attract · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the frame-data move system, the fighter state machine, blocking by height,
combos + cancels, projectiles, pushback, and the round/match flow — lives in `FightEngine`
as pure data + functions stepped by `tick(input0, input1)`. The view only samples inputs
and reads state, which is why the whole match is playable and testable with **no UI**, and
why it **drops in as the fighting core of a larger game** (story mode, character select):
keep the engine, feed two input dicts per frame, read `f` / `wins`.

**Frame data is the design.** Because moves resolve in exact startup/active/recovery
counts and the sim is deterministic + input-driven, the same seed and input stream produce
an identical match across processes — the foundation a **rollback-netcode** fighter is
built on (predict + re-simulate), and what lets NoxQA smoke-run an AI-vs-AI match headlessly
and diff the checksum.

## How to extend

1. **Motion inputs**: add a buffer + a QCF/DP/charge parser so specials need motions; the
   move system already keys off a move name.
2. **Super meter + supers**: track meter built on hit/block/whiff and gate a cinematic
   super move (a longer, higher-damage entry in `MOVES`).
3. **More characters**: give each fighter its own `MOVES` table + walk/jump values and a
   character-select; the engine is per-fighter data already.
4. **Deeper combo system**: add juggle states, launchers, and gravity scaling on air hits
   (the jump arc + hitstun are already there).
5. **Rollback netcode**: `save_data`/`load_data` + the deterministic `tick(in0, in1)` are a
   ready save-state + step API — wire a GGPO-style predict/rollback layer or nox_netcode
   lockstep.
6. **Training mode**: expose frame advantage (`mframe` vs move totals) and a dummy that
   blocks/reversals for a lab.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean (the sim advances with
no runtime errors), and the headless **determinism + playability probe**
(`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed played to completion twice yields an identical final
  `checksum()`; a **different seed diverges** (seeded AI personalities produce a different
  match).
- **partial determinism** — 400 frames of the same seed produce an identical mid-match
  checksum across runs.
- **real match** — rounds are actually won and the match reaches a genuine **winner** who
  took the **best-of-3** (someone hit 2 rounds), not a stall. Validated: a seeded AI-vs-AI
  match ends in **~1466 frames with a clean 2-0**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> end_frame=1466 winner=1 rounds=0-2
# → PROBE PASS
```
