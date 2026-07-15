# Obby 3D Multiplayer Template (3D obstacle course + netcode drop-in)

A 3D **obby** — an obstacle-course platformer where you run and jump across a
staircase of floating platforms, clear checkpoints in order, respawn when you
fall off or hit a hazard, and reach the finish for a time — that ships the
**`nox_netcode` realtime drop-in pre-wired**. The exact same course plays as a
complete single-player obby offline and as a host-authoritative multiplayer race
online, from one codebase. It is the 3D twin of `obby-multiplayer`: same
`GameManager` run engine, same offline↔online seam, `CharacterBody3D` avatars and
a code-built 3D course. Scaffold with:

```bash
python templates/tools/scaffold.py obby-3d-multiplayer <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Bundles the first-party
`nox_netcode` addon (MIT) in `addons/nox_netcode/` — no third-party addons, no
scaffold-time clone.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the run as pure,
  headless-testable logic, **reused verbatim from the 2D obby** because it is
  dimension-agnostic: **monotonic checkpoint progress** (only the very next gate
  counts — the same anti-skip rule the host enforces online), death count, a live
  clock + a persisted **best time**, and `save_data()/load_data()` of the whole
  run. The course and the network layer only read + drive this.
- **The course, built entirely in code** (`scripts/obby3d.gd`) from the
  `PLATFORMS` / `CHECKPOINTS` / `HAZARDS` / `FINISH` / `KILL_Y` data at the top of
  the file — `StaticBody3D`+`BoxShape3D`+`BoxMesh` platforms, ordered `Area3D`
  checkpoint gates, `Area3D` hazard kill-zones, a finish `Area3D`, a `KILL_Y` fall
  line, spawn points (the `net_spawn_point` group), a fixed **follow `Camera3D`**,
  a sun + world environment, and a HUD (checkpoint x/N · time · deaths · best).
  The scene (`scenes/obby3d.tscn`) stays a bare `Node3D` + the netcode nodes.
- **The avatar** (`scenes/player.tscn`) is `nox_netcode`'s **`net_player_3d.gd`** —
  a `CharacterBody3D` that drives world-relative WASD movement + jump from local
  input for its owner and renders synced transform (`position`/`velocity` always,
  `facing`/`moving` on change) for everyone else, mapped to this template's
  `move_left/move_right/move_forward/move_back/jump` actions.
- **`nox_netcode` realtime, pre-wired**: `Net` autoload + a `[nox_netcode]`
  settings block (`profile=realtime`, `transport=enet`); a **`NetSpawner`**
  (**`net_spawner_3d.gd`** → `MultiplayerSpawner` → one avatar per peer from the
  spawn-point group, `Vector3` positions) and a **`NetEvents`** child
  (`net_events.gd`, reused as-is — host-validated checkpoint / respawn / finish
  RPCs + a shared race clock) already on the level root.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (your
  best time persists); a `pause` action (+ `restart`); `"scalable_text"` on the
  HUD.

## Offline ↔ online — one seam (the part worth understanding)

The whole level is identical either way; a single seam (`_net_active()` in
`obby3d.gd`) decides who owns checkpoint / respawn / finish:

- **Offline** (no session — `Net.active == false`): `obby3d.gd` spawns **one**
  local avatar and handles everything itself. Touch a checkpoint →
  `GameManager.reach_checkpoint()`; fall past `KILL_Y` or hit a hazard →
  `GameManager.die()` + teleport to your last checkpoint; cross the finish →
  `GameManager.finish()`. A complete single-player 3D obby with **zero**
  multiplayer dependency — the netcode nodes are present but inert.
- **Online** (a `nox_netcode` session running): the `NetSpawner` spawns an avatar
  per peer, and the same course events **route through `NetEvents`** instead —
  clients request, the **host validates** (monotonic checkpoints, authoritative
  finish order) and broadcasts, and `obby3d.gd` applies the host's decisions
  (`checkpoint_confirmed` / `player_respawned` / `player_finished`). Host = peer
  1 = the single source of truth, so the race is cheat-resistant.

Because the offline core never calls the network, the single-player game behaves
byte-identically whether or not a session is ever started.

## How to extend

1. **The course**: edit the `PLATFORMS` (`AABB`) / `CHECKPOINTS` (`Vector3`) /
   `HAZARDS` / `FINISH` / `KILL_Y` data at the top of `obby3d.gd` — it rebuilds
   from that. Add moving platforms (an `AnimatableBody3D` + a tween) or rotating
   pads as new build helpers.
2. **Feel**: tune `speed` / `jump_velocity` / `gravity` / `acceleration` /
   `friction` on `player.tscn` (net_player_3d exports); add coyote-time /
   double-jump in `net_player_3d.gd` (the authority branch of `_physics_process`).
3. **Art**: swap the `BoxMesh` platforms + capsule avatar for real meshes and a
   rigged character (`.glb` imports); add materials/normal maps; a skybox via a
   `PanoramaSkyMaterial` on the `WorldEnvironment`.
4. **Lobby / more peers**: `res://addons/nox_netcode/lobby.tscn` is a ready
   host/join screen; bump `max_peers` in the `[nox_netcode]` settings.
5. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the best time already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with
zero script errors, and four headless probes:

- **Run-engine probe** (pure `GameManager`, `fails=0`): checkpoint progression
  with anti-skip rejection, death counting, the live clock, finish + best time,
  restart keeping the best, and a `save_data()/load_data()` round-trip.
- **3D integration probe** (`fails=0`): the real level builds
  (`platforms=8 checkpoints=3 hazards=1 net=false`), spawns a local
  `CharacterBody3D` avatar, and is driven through **each checkpoint IN ORDER via
  real `Area3D` overlaps**, then forced below `KILL_Y` (asserts a death +
  respawn to the last checkpoint), then into the finish `Area3D` (asserts
  `GameManager.finished` + a finish time) — all via real overlaps, never by
  calling `GameManager` directly.
- **Netcode API self-probe** (`addons/nox_netcode/net_probe.tscn` → `=> OK`): the
  `Net` API (host/roster/seat/seed/teardown) is sound in the scaffolded project.
- **Offline-config probe** (`fails=0`): with no session, `_net_active()` is
  false, exactly one avatar is spawned, and the `Net` autoload + `NetSpawner` /
  `NetEvents` seam is present but **dormant/inert** offline.

## Manual two-instance test (true peer sync)

The headless probes prove the drop-in loads, the API is sound, and single-player
is complete; **real two-peer sync needs two running processes** (ENet loopback):

```bash
# Terminal 1 — host:
godot --path <project> res://addons/nox_netcode/lobby.tscn
#   Name=Host → Host → (wait for the client) → Start

# Terminal 2 — client (same machine, loopback):
godot --path <project> res://addons/nox_netcode/lobby.tscn
#   Name=Client, Host/IP=127.0.0.1 → Join → Ready
```

On Start the host spawns both avatars; each player drives their own and sees the
other move; checkpoints/finishes resolve in the host's authoritative order. LAN
across machines: use the host's LAN IP and open the port (24567). Web: the
realtime default is ENet (desktop/LAN); for a browser build switch `transport` to
`websocket` (higher latency) — see `addons/nox_netcode/README.md`.

## Bundled addon notes

- `addons/nox_netcode/` is the first-party NoxDev multiplayer drop-in (MIT),
  shipped **in** this skeleton. It carries the 2D avatar/spawner (`net_player.gd`,
  `net_spawner.gd`) **and** their 3D twins (`net_player_3d.gd`,
  `net_spawner_3d.gd`) used here; the dimension-agnostic core (`net_session.gd`,
  `net_events.gd`) is shared unchanged. Keep it in sync with the skill's canonical
  copy at `godogen/skills/netcode/addon/nox_netcode/`.
- True 2-peer sync needs two running instances (see above).
