# Endless Runner Template (Subway Surfers / Temple Run 3-lane dodge, 2D)

A Subway-Surfers / Temple-Run-lineage **endless runner** run as a **deterministic
fixed-timestep sim**: you auto-run forward down 3 **lanes**, **switch** lanes / **jump** /
**slide** to dodge seeded obstacles, grab coins, and survive as the speed ramps up. It is
OUR OWN engine with generic content (no trademarks) — a pure, seedable, deterministic
engine. Scaffold with:

```bash
python templates/tools/scaffold.py endless-runner <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

## What you get

- **`RunnerEngine`** (`scripts/runner_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG lays out the obstacles + coins
  ahead, so a whole run replays **byte-identically** from a seed:
  - **An auto-advancing runner** whose **speed ramps** with distance.
  - **A rolling procedural track** spawned ahead — rows of obstacles that **tighten with
    distance** but **never block all 3 lanes** (a guaranteed fair path) — with three obstacle
    kinds: **block** (must not share its lane), **hurdle** (must be jumping), **duck** (must be
    sliding) — plus coin lines on the free lane.
  - **Lane-switch + timed jump + timed slide** actions with posture windows; **collision** that
    ends the run (recording what you crashed on) unless you cleared the obstacle correctly.
  - **A distance + coins score**; a survive-the-distance-cap **win**.
  - **`checksum()`** — an FNV-1a fold over the quantized state — the cross-process determinism
    proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A deterministic dodge auto-seat** — routes to the nearest fully-clear lane, jumps hurdles,
  slides ducks, and drifts for coins when safe. `auto_step()` / `auto_play_to_end()` run a run.
- **`GameManager` autoload** — feeds the player's per-tick intent, plus the NoxDev save/load ABI
  and an `autoplay` toggle.
- **Play surface** (`scenes/runner_view.tscn` + `scripts/runner_view.gd`) — the 3 lanes, the
  player with jump/slide posture, scrolling obstacles (colour-coded by kind) + coins, and a
  distance/coins/score/speed HUD. **A/D** lanes · **W/↑/Space** jump · **S/↓** slide · **T**
  autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — track generation (with the never-block-all-lanes fairness guarantee), speed ramp,
the three obstacle kinds, lane/jump/slide, collision, coins, and the dodge AI — lives in
`RunnerEngine` as pure data + functions stepped by `tick(input)`. The view only renders state
and forwards intent, which is why the whole run is testable with **no UI**.

Two things worth knowing: the track is spawned **procedurally ahead of the player** and
deliberately **never blocks all three lanes at once**, so there is always a fair path — that
constraint (in `_spawn_row`) is what keeps a random runner *possible*. And because it is a
deterministic seeded sim, the same seed reproduces the exact track, which lets NoxQA smoke-run
the dodge AI headlessly, diff the checksum, and is the base for **daily-run seeds** and
**ghost/replay** races.

## How to extend

1. **Swipe controls + a runner character**: swap keys for swipes (the mobile default) and the
   rects for a sprite with run/jump/slide anims + parallax scenery.
2. **Powerups + a hoverboard**: magnets (auto-collect coins), a shield (one free crash), a jetpack
   segment.
3. **Missions + meta-progression**: daily missions, coin-bought upgrades, a character/skin roster.
4. **Set-piece patterns + biomes**: hand-authored obstacle sequences and biome swaps as distance
   climbs (extend `_spawn_row`).
5. **Ghost races**: a run is a seed + input stream — store and race a friend's ghost.
6. **A 3-D / 2.5-D view**: the engine is lane + distance based, so a perspective camera drops on
   top unchanged.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed lays out a different track**.
- **partial determinism** — 300 ticks of the same seed produce an identical checksum across runs.
- **a real run** — the dodge AI runs a **long distance**, dodging seeded obstacles and grabbing
  **coins**, to a genuine terminal (a crash, or surviving the cap). Validated: the seat runs
  **2029 m collecting 38 coins for score 2409** before the ramping speed finally beats a slide.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> dist=2029 coins=38 score=2409 survived=false crash=duck
# → PROBE PASS
```
