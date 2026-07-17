# Arcade Sports Template (top-down 3v3 arcade soccer with team AI, 2D)

A top-down **arcade sports** game (arcade **soccer**, NBA-Jam-style end-to-end scoring)
run as a **deterministic fixed-timestep sim** at 60 ticks/sec: two teams of 3 chase one
ball, contest possession, dribble, **pass** and **shoot** at goal. It is OUR OWN engine
with generic content (no trademarks) — a pure, seedable, deterministic engine. Scaffold
with:

```bash
python templates/tools/scaffold.py sports-arcade <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`SportsEngine`** (`scripts/sports_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG only sets the kickoff jitter +
  a per-team **aggression**, so a whole match replays **byte-identically** from a seed:
  - **Ball physics** (velocity + friction + wall bounces) with **possession** (a free ball
    within a control radius is grabbed by the nearest player).
  - **Dribbling** (the ball rides just ahead of the carrier toward their goal), **tackling**
    (an opponent within tackle range of a carried ball steals it, with a settle window to
    stop ping-pong), **passing** (to the best open teammate ahead) and **shooting** (a
    **distance-scaled deterministic spread** so long shots are wilder + miss more).
  - **Goal detection** on the correct mouths, **kickoffs** to the conceding team, a **match
    timer**, and a decisive full-time **winner** (draw possible).
  - **A full team AI** for both sides: the ball-nearest player chases/carries; the carrier
    shoots in range / passes only under a tight mark / else dribbles at goal (shooting range
    **widens with the team's seeded aggression**, so different seeds play differently); off-ball
    players hold a ball-shifted formation.
  - **`checksum()`** — an FNV-1a fold over quantized positions + state — the cross-process
    determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** match including RNG state.
- **`GameManager` autoload** — steps the sim in `_physics_process`; the human steers team 0's
  active (ball-nearest) player and the AI plays everyone else; plus the NoxDev save/load ABI
  and a `player_auto` (both-AI) toggle.
- **Play surface** (`scenes/sports_view.tscn` + `scripts/sports_view.gd`) — the pitch, goals,
  both teams (the active + ball-owning players **ringed**), the ball, and a **scoreboard +
  match clock**. **WASD/arrows** move · **Space** shoot · **X** pass · **T** attract · **R**
  restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — ball physics, possession, dribbling, tackling, passing, shooting with spread,
goal detection, kickoffs, and the team AI — lives in `SportsEngine` as pure data + functions
stepped by `tick(input)`. The view only samples input and reads state, which is why the whole
match is playable and testable with **no UI**, and why it **drops in as the match core** of a
season/career game: keep the engine, feed a `{dir, pass, shoot}` dict per tick, read `players`
/ `ball` / `score`.

Like the RTS and fighting templates, this is a **real-time** game kept deterministic by the
fixed-timestep sim: the same seed + inputs reproduce the match exactly, which lets NoxQA
smoke-run an AI-vs-AI match headlessly and diff the checksum, and is the base a **lockstep
multiplayer** sports game builds on. The scoring is deliberately **arcade** (fast, end-to-end,
high-scoring) — tune the goal size, tackle radius, and shooting range for a tighter simulation.

## How to extend

1. **Player switching + sprint/tackle buttons**: let the human cycle the controlled player and
   add a sprint (speed burst) / slide-tackle input.
2. **A goalkeeper**: add a keeper role that hugs the goal line and clears shots.
3. **Other sports**: swap the goal for a hoop (basketball) or net (hockey) and retune — the
   possession + shooting core is sport-agnostic.
4. **Stamina / skill ratings**: give players ratings that modulate speed, tackle success, and
   shot accuracy for a career mode.
5. **Season / tournament**: wrap matches in a bracket or league table (the match already yields
   a score + winner).
6. **Lockstep multiplayer**: the deterministic `tick(input)` + `save_data`/`load_data` are a
   ready step + save-state API; exchange inputs per tick (nox_netcode) for netplay.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean (the sim advances with
no runtime errors), and the headless **determinism + playability probe**
(`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed played to full time twice yields an identical final
  `checksum()`; a **different seed diverges** (seeded kickoff jitter + aggression change the
  match).
- **partial determinism** — 900 ticks of the same seed produce an identical mid-match checksum.
- **real soccer happens** — the two-AI match reaches full time and **goals are scored**,
  proving possession, tackling, passing, shooting, goal detection, and kickoffs all work.
  Validated: a seeded AI-vs-AI match ends **14-13 at full time with a decisive winner**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> final=14-13 winner=0 end_tick=5400
# → PROBE PASS
```
