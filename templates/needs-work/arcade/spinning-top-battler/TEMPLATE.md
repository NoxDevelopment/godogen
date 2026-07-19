# Spinning Top Battler Template (Beyblade-style arena, 2D)

A Beyblade-lineage **spinning-top arena battler**: build a top from **parts** (an
attack ring + a weight disk + a tip), launch it into a circular **stadium**, and
collide to drain the opponent's **stamina** (spin-finish), knock it out of the
**ring** (ring-out), or **burst** it in one big hit — across a best-of match and a
**tournament** ladder of AI opponents. Scaffold with:

```bash
python templates/tools/scaffold.py spinning-top-battler <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## KEY DESIGN DECISION — deterministic CUSTOM physics (not RigidBody2D)

Godot's `RigidBody2D` solver is **not** guaranteed identical across runs/builds,
which would break byte-identical replays + probes. So the top-vs-top physics is
**our own fixed-timestep circle sim**. A top is a circle (position, velocity, plus
**WEIGHT** and **SPIN** which encodes **STAMINA** + a spin **direction**) advanced
at a fixed `dt` inside a circular bowl. Motion is a pure deterministic sum of a
**bowl slope** (a centre spring), passive **friction**, an aggression **wander** (a
deterministic sine of the top's age, **not** an RNG), and a **seek** toward the
nearest opponent. Collisions are pure circle-circle geometry: overlap → weighted
elastic momentum transfer along the contact normal + an attack **knockback** + a
**stamina drain** scaled by `attacker.attack / defender.defense` and the
**same-spin / opposite-spin** interaction (opposite spin = heavy "spin-steal"
drain, same spin = more knockback). Given (part builds, launches, seed) the
trajectories, stamina curves, and result are **100% reproducible**; the only
randomness in the engine (the tournament ladder + AI launch jitter) comes from one
seeded RNG whose state is part of save/load — the physics has **zero** randomness.
A `MAX_STEPS` cap bounds every battle → a stamina tiebreak, never an infinite spin.

## What you get

- **`TopEngine`** (`scripts/top_engine.gd`) — a pure `RefCounted class_name`, no
  Godot-node dependency, fully headless-testable:
  - **Parts + building** — a `PART_DB` of **14 parts** (**6 attack rings, 4 weight
    disks, 4 tips**); `build_top(ring, disk, tip, spin)` derives the **EXACT**
    stats (attack, defense, stamina-max, weight, aggression, friction, drain, grip)
    as auditable additive sums. The parts form an **attack / stamina / defense
    triangle** (attack KOs stamina before it outlasts; stamina outlasts defense;
    defense survives attack) so every opponent has a real counter.
  - **Physics** — `simulate_battle()`: the pure circle sim → `{winner, reason,
    steps, checksum, tops, collisions, trace}`. Deterministic, bounded.
  - **Match** — best-of points: **spin-finish = 1, ring-out = 2, burst = 2**,
    timeout = 1 (stamina tiebreak). First to `POINTS_TO_WIN`.
  - **Tournament** — a **ladder** of AI opponents; win a match → advance **and
    unlock a part**; lose → eliminated; beat the last rung → **WIN**.
  - **Auto-play** — `best_counter_build()` / `auto_take_turn()`: a deterministic
    heuristic that dry-simulates candidate builds, picks the best counter, aims,
    and launches — driving a whole tournament to WIN or LOSS with no UI.
  - `is_legal()` rejects illegal actions (launch with no/invalid build, an unowned
    part combo, acting after the run is over); `to_dict()/from_dict()` +
    `run_checksum()` save the whole run and prove determinism.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `TopEngine` and
  adds the **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (owned
  parts, current build, rung, match score, difficulty + RNG persist); `pause` +
  `restart` input; `"scalable_text"`.
- **Arena** (`scenes/arena.tscn` + `scripts/arena.gd`) — the play surface built in
  code: the circular stadium + the two spinning tops (markers ringed by a stamina
  arc) with the last battle's deterministic trajectory replayed via `_draw()`, plus
  the **part-builder** (ring / disk / tip / spin pickers + the derived stats), a
  **launch control** (a power meter + an aim slider + Launch), the match score +
  the rung roster, an **Auto Step** demo button, and a log.

## The engine (the part worth understanding)

Every rule — the part→stat derivation, the circle sim, collision drain/knockback,
ring-out / spin-finish / burst, point scoring, the ladder + unlocks — lives in
`TopEngine` and is pure. The arena only reads state and forwards one chosen action.
That is why it is fully playable and testable with **no UI**, and why it **drops in
as the battle core of a larger game**: keep the engine, call `select_build()` +
`launch()`, read `last_result`. All tuning is explicit constants at the top of the
file (arena size, drain rates, knockback, the spin factors, the part tables, the
ladder), so it is auditable and easy to re-balance.

## How to extend

1. **More parts**: add rings/disks/tips to the `PART_DB` — the derived-stat sums
   and the builder pick them up automatically. Keep the triangle intact.
2. **Real characters**: give each AI rung a `companion-npcs` persona + voice for
   pre-match taunts (bridge to the VN / dating-sim side).
3. **Deeper progression**: turn the ladder into a roguelike map, add per-win part
   upgrades, a currency + a parts shop (the unlock hook is already there).
4. **A burst meter / special moves**: the `big_hit` field per top is tracked — wire
   a charge-up special or a launch-timing minigame onto it.
5. **Art**: swap the flat circles for real top sprites + a stadium backdrop
   (recipes: top/part icons via `qwen-icon`, stadium splash via `zit-txt2img`).
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with zero
script errors + all vars typed, and six headless probes (all `fails=0`):

- **Physics** — two tops launched (fixed seed + builds) collide (≥1), stay in the
  arena bounds until a ring-out, drain stamina on hits + over time, and terminate
  within the step cap with a definite result; spin-finish AND ring-out are both
  reachable; the trajectory is deterministic (identical checksum on re-run).
- **Determinism** — same seed + launches + builds → byte-identical battle
  (positions, stamina, result) and byte-identical whole tournaments; a different
  seed / launch diverges.
- **Parts/stats** — four combos produce the EXACT expected derived stats; the part
  counts are ≥6/≥4/≥4; and a high-attack top drains a low-defense opponent far
  faster than a defensive control (both as a one-hit preview and in a real battle).
- **Battle/match** — the point mapping is exactly spin=1 / ring=2 / burst=2; a real
  match scores every round consistently and resolves to a winner; the burst
  mechanic and a ring-out (both 2-pointers) are reachable.
- **Tournament** — the deterministic auto-play reaches a WIN (clears the ladder)
  AND a LOSS (eliminated at high difficulty); it always terminates; actions are
  rejected after the run is over.
- **Rules/UI/save-load** — illegal actions rejected; the arena scene builds (stadium
  + tops via `_draw`, score labels, the part-builder options, the power/aim sliders,
  a launch button) and a live launch resolves; a mid-run save → mutate → load equals
  the snapshot.
