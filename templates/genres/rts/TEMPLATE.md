# RTS Template (Real-Time Strategy — StarCraft/AoE-lite base-build + army, 2D)

A StarCraft/AoE-lineage **real-time strategy**: mine minerals with workers, spend
them to train more workers + a barracks + soldiers, and **raze the enemy town hall**
before yours falls. It is OUR OWN engine with generic content (no trademarks). The
trick that keeps a *real-time* game inside the NoxDev pure-engine pattern:
`RtsEngine` runs as a **deterministic fixed-timestep lockstep sim**. Scaffold with:

```bash
python templates/tools/scaffold.py rts <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`RtsEngine`** (`scripts/rts_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. Play advances in **discrete ticks**;
  commands are **queued and applied in a fixed sorted order**; one seeded RNG drives
  world-gen + tie-breaks + AI — so an entire match replays **byte-identically** from
  a seed and can be driven headlessly:
  - **World**: two symmetric bases (a town hall, starting workers, and a 4-patch
    mineral field), with a little **seeded opening jitter** so matches differ by seed.
  - **Worker economy** — a real state machine: walk to a patch → **mine** a load over
    `MINE_TICKS` → haul `CARRY` back to a town hall → **deposit** (minerals rise) →
    auto-resume the nearest live patch. Patches deplete and workers re-path.
  - **Production** — the town hall trains **workers**, the barracks trains
    **soldiers**, one at a time per building, **paid on queue**; the finished unit
    spawns on a free adjacent tile and rallies out.
  - **Movement** — greedy tile-stepping that **slides around buildings** (speed =
    ticks per tile), fully deterministic.
  - **Combat** — vision-based **target acquisition** (nearest enemy unit in `VISION`,
    else nearest enemy building), close to `range`, trade blows on an
    `ATTACK_COOLDOWN`. Attack-move advances toward a point while acquiring targets.
  - **Construction** — a worker walks out, lays a **barracks**, and builds it over
    `BUILD_BARRACKS_TICKS` before it can produce.
  - **Victory** — a match ends the instant one side's **town hall is razed**
    (or a draw if both fall on the same tick).
  - **`checksum()`** — an **FNV-1a fold over the entire state** (minerals + every
    building + every unit + every patch) — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the whole match **including RNG state**.
- **Weighted-heuristic macro AI** (`ai_take_turn(owner)`) that can drive **either
  side**: keep every idle worker mining, train up to a worker target, **tech to a
  barracks**, pump soldiers, and once the army hits a threshold **attack-move the
  whole army at the enemy hall**. `auto_step()` / `auto_play_to_end()` drive **both
  sides** for a full self-playing match.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `RtsEngine`,
  steps it (`advance()`), drives the AI opponent (and optionally the player side),
  and adds the NoxDev save/load ABI.
- **Play surface** (`scenes/rts_view.tscn` + `scripts/rts_view.gd`) — steps the sim
  in `_physics_process` for a real-time feel and draws the board in code: mineral
  patches, **team-coloured** buildings + units, HP bars, and a live HUD. **Left-drag
  box** selects your units; **right-click** issues a context command (gather a patch,
  attack an enemy, else move / attack-move). Hotkeys: **Q** train worker · **E** train
  soldier · **B** build barracks · **Space** pause · **F** hand your side to the AI ·
  **[ / ]** sim speed · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine that
  slots into any scene tree.

## The engine (the part worth understanding)

Every rule — world-gen, the worker economy, production, movement, combat, target
acquisition, construction, victory, and the macro AI — lives in `RtsEngine` as pure
data + functions driven by one `RandomNumberGenerator` seeded in `setup(seed)`. The
view only reads state and enqueues commands, which is why the whole game is playable
and testable with **no UI**, and why it **drops in as the strategy core of a larger
game**: keep the engine, call `cmd_*()`, `step()`, read `units` / `buildings` /
`minerals`.

**Determinism is the load-bearing property.** Real-time games usually desync because
frame timing leaks into the simulation; here nothing calls `Time` or an unseeded RNG,
commands are applied in a **sorted deterministic order** every tick, and units iterate
by **sorted id** — so `checksum()` after any number of ticks is identical across two
separate processes given the same seed and command stream. That is exactly what a
**lockstep multiplayer RTS** needs (send commands, not state), and what lets NoxQA
smoke-run a whole AI-vs-AI match headlessly in CI.

## How to extend

1. **More unit/building types**: add a kind to `_make_unit()` / the production
   branches + its stats block; combat, movement, and save/load pick it up.
2. **Tech tree / upgrades**: gate `cmd_train`/`cmd_build` on owned buildings, and add
   an upgrade that bumps `atk`/`range`/`speed` for an owner.
3. **Terrain & real pathfinding**: mark blocked tiles in the world and swap the greedy
   `_step_toward` for a cached BFS/flow-field (the roguelike template's BFS is a
   drop-in reference).
4. **Fog of war / minimap**: the engine already has per-owner vision (`VISION`); track
   a `seen[]` grid per owner for a real fog + minimap.
5. **Smarter AI**: `ai_take_turn` is one heuristic; add build-order openings, scouting,
   army composition, and retreat — or wire an LLM-assist commander that emits `cmd_*`.
6. **Lockstep multiplayer**: because the sim is deterministic and command-driven, drop
   in the `nox_netcode` addon and exchange **command lists per tick** (not state) for a
   true networked RTS.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop
   in unchanged; the whole match already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script
errors (all vars typed), a **30-frame headless main-scene smoke** runs clean (the sim
advances with no runtime errors), and the headless **determinism + playability probe**
(`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed played to completion twice yields an identical
  final `checksum()`; a **different seed diverges** (different world + match).
- **partial determinism** — 500 ticks of the same seed produce an identical mid-match
  checksum across runs.
- **seeded world-gen** — two seeds produce **different initial states**.
- **economy runs** — within 1200 ticks a side has actually **built a barracks or
  fielded a soldier** (workers mined, deposited, and the minerals were spent).
- **real decision** — `auto_play_to_end` reaches a genuine **winner** (a town hall
  razed), not a stalled cap draw. Validated: a seeded AI-vs-AI match ends at
  **tick 1788** with a real winner.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> end_tick=1788 winner=0 rax=true army=true
# → PROBE PASS
```
