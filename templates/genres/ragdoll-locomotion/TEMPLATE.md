# Ragdoll Locomotion Template (QWOP-style physics-comedy walker + netcode drop-in)

A QWOP-lineage **ragdoll locomotion** game: you actuate an athlete's individual
muscles — four groups mapped to **Q / W / O / P** — to stagger an articulated
body **forward** as far as possible before it topples. Reach the goal distance to
**WIN**; faceplant or time out to **LOSE**. It ships the **nox_netcode** realtime
drop-in pre-wired, so the same codebase runs OFFLINE (one local athlete) or ONLINE
(a race — every peer walks its own athlete down the track side-by-side).

## KEY DESIGN DECISION — deterministic CUSTOM physics (not RigidBody2D)

Godot's `RigidBody2D` / `PhysicsServer2D` solver is **not** guaranteed identical
across runs / builds / platforms, which would break byte-identical replays + the
determinism probe. So `RagdollEngine` (a pure `extends RefCounted`, **no**
Godot-node dependency) is our OWN fixed-timestep articulated-body sim:

- The athlete is **11 point masses** (head, neck/shoulder, hip, knees, ankles,
  toes, elbow, hand) wired by **10 rigid BONE distance-constraints** — the >= 7
  rigid segments (head, torso, thighL, shinL, footL, thighR, shinR, footR,
  upperArm, lowerArm).
- Each fixed step (**DT = 1/120**): integrate velocities under gravity + air drag
  (semi-implicit Euler), integrate positions, then a **fixed 10-pass relaxation**
  (XPBD-style): rigidify bones → drive **MUSCLE angular-constraints** toward the
  player's target angles → a torso **balance reflex** → resolve **ground contact +
  Coulomb friction**. Velocities are re-derived from the projected motion, so a
  constraint can never inject energy — **no NaN, no explosion**. A per-node speed
  clamp (with a bone-reconciliation pass) means the athlete must genuinely WALK,
  never teleport/slide.
- A **planted foot grips** the floor (traction), so a hip that extends against a
  gripped foot levers the torso **forward** — real walking, not skating.
- The physics has **zero randomness**; the only RNG is one seeded generator for an
  optional tiny start jitter (`config.jitter`, default 0) and it is part of
  save/load. **MAX_STEPS** bounds every run → a timeout, never an infinite stagger.

Given `(seed, config, per-frame muscle inputs)` the trajectory is 100%
reproducible and **byte-identical across separate processes**.

## What you get

- **`scripts/ragdoll_engine.gd`** — the pure `RagdollEngine` (~900 lines): the
  articulated-body sim, the muscle model, ground contact + traction, the balance
  reflex, fall / win / timeout rules, deterministic FNV-1a checksums, full
  save/load, and two canned deterministic policies (`policy_walk`, `policy_fall`).
- **Four muscle groups** (the QWOP inputs), each an **antagonistic joint pair**:
  `Q` right thigh forward / left thigh back, `W` the mirror, `O` right knee
  straighten / left knee bend, `P` the mirror. `set_muscle(i, on)` shifts the
  pair's joint target angles; the joint springs chase them each step.
- **Three difficulty presets** — `easy` (a forgiving walk, 6 m goal), `normal`
  (stable, the full 100 m), `hard` (a weak balance reflex, a true teeter).
- **`scripts/game_manager.gd`** — the `GameManager` autoload owning one engine,
  in the `game_manager` + `persistent` groups with `save_data()/load_data()` (the
  whole run — body state, inputs, progress, difficulty + RNG — persists).
- **`scripts/track.gd` + `scenes/track.tscn`** — the play surface built entirely
  in code: the athlete, the scrolling ground with metre markers + a goal line, a
  distance HUD, and per-frame muscle input. Offline solo or online race via the
  `_net_active()` seam.
- **Vendored `addons/nox_netcode/`** — the NoxDev realtime multiplayer drop-in
  (Net autoload, realtime profile, ENet). Ships `net_athlete.gd` (the ragdoll
  avatar) alongside the stock `net_player.gd` / `net_spawner.gd` / `net_events.gd`,
  exactly as obby-3d-multiplayer adds `net_player_3d.gd` (added **to the vendored
  copy** — the shared source addon is never edited).

## Controls

- **Q / W** — thighs (hips). **O / P** — calves (knees). Alternate them to walk.
- **R** — restart the run. **Esc** — pause.

## Offline ↔ online — one seam (the part worth understanding)

`track.gd` gates everything on `_net_active()` (`/root/Net` present **and**
`Net.active`), exactly like the obby template:

- **OFFLINE** (no session): `track.gd` drives `GameManager`'s one `RagdollEngine`
  on a fixed-timestep accumulator and renders it — a complete single-player QWOP
  game with zero multiplayer dependency. The `NetSpawner` / `NetEvents` children
  sit inert, so the offline run is **byte-identical whether or not the netcode
  nodes are present** (proven by `netcode_probe`).
- **ONLINE** (a nox_netcode session running): `NetSpawner` spawns one
  `net_athlete` per peer via `MultiplayerSpawner`; each peer sims its **own**
  athlete from local input and syncs its body **pose** (the flat node snapshot) via
  a code-built `MultiplayerSynchronizer`; `NetEvents` arbitrates the authoritative
  finish order. Authority is **per-peer over its own athlete** — the exact obby
  `net_player` seam (authority set from the node name at spawn, owner-drives /
  others-render), only the replicated payload is an articulated pose instead of a
  single transform. **No new protocol.**

## How to extend

- **More joints / a richer skeleton** — add nodes to `POSE` + `MASS`, bones to
  `BONES`, joints to `JOINTS`; muscle joints just need a `"muscle_*"` kind + a
  mapping in `_joint_target()`.
- **Levels / hazards** — the ground is a plane in `_solve_ground`; add slopes,
  gaps, or a treadmill by varying `GROUND_Y` per x.
- **Art** — swap the code-drawn bones/joints for a sprite skeleton driven by
  `bone_segments()` (recipes: athlete sprite via `zit-pixel-art`, backdrop via
  `zit-txt2img`).
- **Tune the feel** — `MUSCLE_STIFFNESS`, `HIP_SWING`, `KNEE_THROW`, `FOOT_GRIP`,
  and each preset's `balance_gain` are the dials.

## Validation status

All probes run headless and report `fails=0` (see `_probes/`):

| Probe | Proves |
|-------|--------|
| `physics_probe` | segments fall under gravity; a planted foot gives traction (not a slide); bones stay rigid (< 3% stretch) under thrash; no NaN / explosion |
| `determinism_probe` | same seed + canned input → identical body checksum (mid + full run); different input diverges; **identical across two separate processes** |
| `locomotion_probe` | the scripted walk advances a positive distance by stepping (feet lift), bounded to a physical speed (no teleport), and **reaches the WIN goal on easy** |
| `fall_probe` | a tip policy ends the run as a FALL (head-down — LOSS reachable); MAX_STEPS bounds every run (even a standing athlete) |
| `rules_ui_probe` | the main scene builds its HUD; illegal / edge muscle inputs are rejected + counted; the run round-trips through save/load |
| `netcode_probe` | Net realtime API present; the seam is inert offline; the per-peer athlete avatar is wired (authority from name, code-built synchronizer, replicated pose); the offline run is byte-identical with the netcode nodes present vs a pure engine |

Plus the vendored addon's own self-test `addons/nox_netcode/net_probe.tscn` → OK.

Run one:

```bash
C:/godot/Godot_v4.6.1-stable_win64_console.exe --headless --path skeleton \
  res://_probes/locomotion_probe.tscn --quit-after 800
```

Import gate: `--headless --editor --path skeleton --quit` exits 0 with no
script/parse errors.

## Manual two-instance test (true peer sync)

The headless netcode probe proves the drop-in loads + the seam is sound; real
two-peer sync needs two running processes:

```bash
# Terminal 1 — host:
Godot --path skeleton res://addons/nox_netcode/lobby.tscn
#   Name=Host → Host → (wait for the client) → Start

# Terminal 2 — client (same machine, loopback):
Godot --path skeleton res://addons/nox_netcode/lobby.tscn
#   Name=Client, Host/IP=127.0.0.1 → Join → Ready
```

After Start, each peer controls its own athlete (Q/W/O/P) and sees the others
stagger down the track alongside it; `NetEvents` records the authoritative finish
order.

## How it plugs into the factory

Standard NoxDev genre-template ABI: `GameManager` autoload in the `game_manager` +
`persistent` groups with `save_data()/load_data()`; buses via
`default_bus_layout.tres`; `pause` + `restart` inputs; `scalable_text` HUD labels;
clean headless boot. Registry id: **`ragdoll-locomotion`**. Drops in standalone or
as the locomotion minigame / traversal core of a larger game.
