# Dot IO Template (Hole.io / Agar.io grow-by-absorbing arena, 2D)

A Hole.io / Agar.io-lineage **.io grow-arena** game run as a **deterministic fixed-timestep
sim** (4 of the top-10 downloaded hypercasual games are .io games): steer your "hole",
**swallow** objects (and rival holes) smaller than your current size to **grow**, and
out-mass the AI rivals before the timer ends. It is OUR OWN engine with generic content
(no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py dot-io <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`DotIoEngine`** (`scripts/dotio_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG places the objects + drives the
  rival AI, so a whole match replays **byte-identically** from a seed (the checksum is
  **position-quantized** so it survives cross-process float math):
  - **An arena** of scattered objects of varied sizes.
  - **A size-gated swallow rule** — a hole absorbs any object with size ≤ its own within its
    radius — that **grows** the hole (`radius = sqrt(size)`) and scores the swallowed mass, with
    objects respawning to keep the arena stocked (Hole.io endless growth, tuned to a believable
    curve).
  - **Hole-vs-hole predation** — a hole 1.12× bigger swallows a smaller one on overlap (the small
    hole respawns at start size).
  - **A rival AI** that heads for the nearest swallowable object and **flees** a much bigger hole
    nearby; a **60-second match timer**; and a **winner by mass**.
  - **`checksum()`** — an FNV-1a fold over the quantized state — the cross-process determinism
    proof.
  - `save_data()` / `load_data()` snapshot the **entire** match including RNG state.
- **A deterministic auto-play** that drives every hole (all-AI) for a full match.
- **`GameManager` autoload** — steps the sim in `_physics_process` (60Hz) steering the player
  toward the mouse, plus the NoxDev save/load ABI and a `player_auto` attract toggle.
- **Play surface** (`scenes/dotio_view.tscn` + `scripts/dotio_view.gd`) — the arena, objects, the
  player + rival holes sized by mass, a leaderboard + a timer HUD. Move toward the mouse ·
  **T** attract · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — object placement, the size-gated swallow, hole growth, hole-vs-hole predation,
the rival AI, and the match/winner — lives in `DotIoEngine` as pure data + functions stepped by
`tick(input)`. The view only steers the player and reads state, which is why the whole match is
playable and testable with **no UI**.

Two design notes worth knowing: **growth is exponential** (each swallow makes you bigger so you
can swallow more), so `OBJ_GROWTH` is tuned down to keep a match on a *believable* curve rather
than ballooning past the arena — that constant is your difficulty dial. And because it is a
deterministic fixed-timestep sim driven by input, the same seed + inputs reproduce the match,
which is the base a **real-time .io multiplayer** (server-authoritative or lockstep) builds on,
and what lets NoxQA smoke-run an all-AI match headlessly and diff the checksum.

## How to extend

1. **A themed swallow-world (Hole.io)**: replace the abstract objects with a top-down city of
   props at increasing sizes (cones → benches → cars → buildings) and a hole shader.
2. **Agar.io split/eject**: add a split ability (spawn two smaller holes) and mass-ejection for
   the cell-eat-cell flavour.
3. **Real multiplayer**: the deterministic `tick(input)` + `save_data`/`load_data` are the base
   for a server-authoritative or lockstep .io — send steering inputs, reconcile positions.
4. **Powerups + hazards**: speed pads, magnets, spikes that shrink you.
5. **Bots with personalities**: aggressive hunters vs greedy farmers (tune `_ai_dir`).
6. **A minimap + zoom-out as you grow** (Agar.io camera).
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the whole match already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed, first try), a **40-frame headless main-scene smoke** runs clean, and the
headless **determinism + playability probe** (`_probes/determinism_probe.tscn`) passes
(`PROBE PASS`):

- **seed determinism** — the same seed played to time twice yields an identical final
  `checksum()`; a **different seed places a different arena**.
- **partial determinism** — 500 ticks of the same seed produce an identical checksum across runs.
- **real growth + a winner** — the match reaches time, a **winner is decided**, and holes
  actually **grow well past the start size** (proving swallowing works). Validated: the player
  grows from size **22 to ~4652** for score **~33k** and wins the arena.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> winner=0 end_tick=3600 player_size=4652 player_score=33050 max_size=4652
# → PROBE PASS
```
