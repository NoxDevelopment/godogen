# Twin-Stick Shooter Template (Enter the Gungeon / Nuclear Throne-lite arena survival, 2D)

An Enter-the-Gungeon / Nuclear-Throne-lineage **twin-stick shooter** run as a
**deterministic fixed-timestep sim** at 60 ticks/sec: **move** with one stick and
**aim/fire** with the other while waves of enemies pour in from the edges. It is OUR OWN
engine with generic content (no trademarks) — a pure, seedable, deterministic engine.
Scaffold with:

```bash
python templates/tools/scaffold.py twin-stick-shooter <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`ShooterEngine`** (`scripts/shooter_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. Its single RNG seeds the spawns + enemy
  jitter and the sim is otherwise pure, so a whole run replays **byte-identically** from a
  seed (checksum is **position-quantized** so it is robust across processes):
  - **True twin-stick control** — independent **move** and **aim** vectors with a fire
    cooldown; bullets inherit the aim direction.
  - **Bullets** (player + enemy) with velocity + lifetime + **circle collision**.
  - **Three enemy archetypes** with distinct behaviour — a **chaser** that rushes for
    contact damage, a ranged **shooter** that keeps mid-range and fires **aimed** bullets,
    and a tanky **brute** — each with hp / speed / radius / contact / xp.
  - **Escalating waves** — count + roster deepen (shooters from wave 2, brutes from wave 3,
    a brute-heavy final wave), spawned from the arena edges.
  - **Player i-frames** after a hit; **score** per kill; a **survive-all-waves win** vs a
    death lose.
  - **`checksum()`** — an FNV-1a fold over the quantized state — the cross-process
    determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **Heuristic kite-and-fire auto-seat** (`ai_input`) — aims at the nearest enemy, kites when
  crowded / closes when far / strafes at range, edges away from walls, dodges the closest
  incoming bullet, and always fires. `auto_step()` / `auto_play_to_end()` drive a full run.
- **`GameManager` autoload** — steps the sim in `_physics_process` (60Hz), plus the NoxDev
  save/load ABI and a `player_auto` attract toggle.
- **Play surface** (`scenes/shooter_view.tscn` + `scripts/shooter_view.gd`) — draws the
  arena, player (aim line + **i-frame flash**), enemies (colour + **HP ring** by type),
  bullets, and a HP / wave / score HUD. **WASD** move · **mouse** aim · hold **LMB/Space**
  to fire · **T** attract · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — twin-stick movement, bullets + collision, the three enemy behaviours, the
wave curve, i-frames, score, and win/lose — lives in `ShooterEngine` as pure data +
functions stepped by `tick(input)`. The view only samples input and reads state, which is
why the whole run is playable and testable with **no UI**, and why it **drops in as the
combat core of a bigger roguelike** (rooms, drops, upgrades): keep the engine, feed a
`{move, aim, fire}` dict per frame, read `player` / `enemies` / `bullets`.

Determinism is deliberate: positions are `Vector2` floats (same-platform bit-identical), and
`checksum()` **quantizes** them to integers so two processes agree exactly — which lets
NoxQA smoke-run the kite-seat headlessly and diff the checksum, and is the base a
**lockstep-multiplayer** co-op shooter would build on.

## How to extend

1. **Weapons + pickups**: give the player a weapon table (spread, rate, damage) and
   drop weapons/hearts on kills; the bullet spawn is one call.
2. **Dash / roll i-frames**: add a dodge state (the player already has an i-frame timer).
3. **Rooms + a run structure**: wrap waves in rooms with doors + a shop between them for a
   full Gungeon-style run.
4. **Boss enemies**: add a boss archetype with phases + bullet patterns (the bullet system
   already supports arbitrary velocities).
5. **More enemy behaviours**: orbiter, splitter, bomber — each is a branch in
   `_tick_enemies`.
6. **Lockstep co-op**: the deterministic `tick(input)` + `save_data`/`load_data` are a ready
   step + save-state API; exchange inputs per tick (nox_netcode) for netplay.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean (the sim advances with
no runtime errors), and the headless **determinism + playability probe**
(`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed played to completion twice yields an identical final
  `checksum()`; a **different seed diverges** (seeded spawns).
- **partial determinism** — 300 frames of the same seed produce an identical mid-run
  checksum across runs.
- **real run** — the kite-seat actually **scores kills** and **clears past the first wave**,
  reaching a genuine terminal. Validated: the seat **clears all 6 waves to a WIN**, score
  **1032**, in **~1928 frames**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> end_frame=1928 won=true wave=7 score=1032
# → PROBE PASS
```
