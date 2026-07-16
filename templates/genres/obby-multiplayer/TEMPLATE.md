# Obby Multiplayer Template (2D obstacle course + netcode drop-in)

A 2D **obby** — an obstacle-course platformer where you race across platforms,
clear checkpoints in order, respawn when you fall or hit a hazard, and reach the
finish for a time — that ships the **`nox_netcode` realtime drop-in pre-wired**.
The exact same course plays as a complete single-player obby offline and as a
host-authoritative multiplayer race online, from one codebase. Scaffold with:

```bash
python templates/tools/scaffold.py obby-multiplayer <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Bundles the first-party
`nox_netcode` addon (MIT) in `addons/nox_netcode/` — no third-party addons, no
scaffold-time clone.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the run as pure,
  headless-testable logic: **monotonic checkpoint progress** (only the very next
  gate counts — the same anti-skip rule the host enforces online), death count,
  a live clock + a persisted **best time**, and `save_data()/load_data()` of the
  whole run. The course and the network layer only read + drive this.
- **A DATA-DRIVEN course** — `scripts/obby.gd` builds the level (static platforms,
  ordered checkpoint gates, hazard kill-zones, a finish, a fall line, spawn points
  in the `net_spawn_point` group, a trailing camera, a HUD of checkpoint x/N · time
  · deaths · best) from a **`CourseData`** instance (`scripts/course_data.gd`), not
  hardcoded consts. `CourseData` is the ONE course format — `{name, author, created,
  start_spawn, platforms:[Rect2], checkpoints:[Vector2] (ordered), hazards:[Rect2],
  finish:Rect2, kill_y}` — with lossless `to_dict`/`from_dict` (in-memory) and
  `to_json`/`from_json` (files + the wire; `Vector2`→`[x,y]`, `Rect2`→`[x,y,w,h]`).
  The scene (`scenes/obby.tscn`) stays a bare `Node2D` + the netcode nodes + one
  `CourseSync` child.
- **Course library + designer + share** (all `CourseData`, no divergence):
  - **`CourseLibrary` autoload** (`scripts/course_library.gd`) unifies **built-in**
    courses (the original obby as `Starter Climb`, plus a harder `Sky Gauntlet`),
    **user** courses saved to `user://courses/<slug>.json`, and **imported** shared
    files. `list_courses()` / `load_course(id)` / `save_course()` / `export_course()`
    / `import_course()`. `pending_course` is the one-slot hand-off obby.gd plays
    (null → the built-in default, so running the level directly is unchanged).
  - **In-game designer** (`scenes/course_editor.tscn` + `course_editor.gd`): place/
    delete platforms & hazards (drag-rect), drop auto-numbered ordered checkpoints,
    set start & finish, on a 20px snap grid, via a `scalable_text` palette. Save-as
    writes to the library; **Test** loads the just-built course into the play level.
    Everything routes through one authoring API (`set_tool` / `place_platform` /
    `add_checkpoint` / `add_hazard` / `set_start` / `set_finish` / `build_course_data`)
    that mouse and code share.
  - **Course-SELECT screen** (`scenes/course_select.tscn`): list built-in + user +
    imported, Play / New / Edit / **Export** a portable `.json` / **Import** one from
    a path. Server publishing is a documented seam (`CourseLibrary` — "Studio
    course-exchange integration point"), out of template scope.
- **The avatar** (`scenes/player.tscn`) is `nox_netcode`'s `net_player.gd` — a
  `CharacterBody2D` that drives from local input for its owner and renders synced
  transform for everyone else, mapped to this template's `move_left/move_right/
  jump` actions.
- **`nox_netcode` realtime, pre-wired**: `Net` autoload + a `[nox_netcode]`
  settings block (`profile=realtime`, `transport=enet`); a **`NetSpawner`**
  (`MultiplayerSpawner` → one avatar per peer from the spawn-point group) and a
  **`NetEvents`** child (host-validated checkpoint / respawn / finish RPCs + a
  shared race clock) already on the level root.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (your
  best time persists); a `pause` action (+ `restart`); `"scalable_text"` on the
  HUD.

## Offline ↔ online — one seam (the part worth understanding)

The whole level is identical either way; a single seam (`_net_active()` in
`obby.gd`) decides who owns checkpoint / respawn / finish:

- **Offline** (no session — `Net.active == false`): `obby.gd` spawns **one**
  local avatar and handles everything itself. Touch a checkpoint →
  `GameManager.reach_checkpoint()`; fall past `KILL_Y` or hit a hazard →
  `GameManager.die()` + teleport to your last checkpoint; cross the finish →
  `GameManager.finish()`. A complete single-player obby with **zero** multiplayer
  dependency — the netcode nodes are present but inert.
- **Online** (a `nox_netcode` session running): the `NetSpawner` spawns an avatar
  per peer, and the same course events **route through `NetEvents`** instead —
  clients request, the **host validates** (monotonic checkpoints, authoritative
  finish order) and broadcasts, and `obby.gd` applies the host's decisions
  (`checkpoint_confirmed` / `player_respawned` / `player_finished`). Host = peer
  1 = the single source of truth, so the race is cheat-resistant. The **`CourseSync`**
  child (`scripts/course_sync.gd`) extends the same host-authoritative philosophy to
  the COURSE itself: at race start the host publishes its chosen course to every
  peer (a built-in by id, a custom course as full `CourseData` JSON), and clients
  build the identical course — so everyone races the host's pick, custom or not.
  `CourseSync` is game-layer (it never touches the `nox_netcode` addon) and fully
  inert offline.

Because the offline core never calls the network, the single-player game behaves
byte-identically whether or not a session is ever started.

## How to extend

1. **The course**: build one in-game with the designer (`course_editor.tscn`) and
   Save/Test it, or add a new built-in in `CourseLibrary` (`starter_climb()` /
   `sky_gauntlet()` are the pattern; register it in `_builtin_registry()`). obby.gd
   rebuilds from any `CourseData`. Add moving platforms (an `AnimatableBody2D` + a
   tween) or one-way platforms as new build helpers keyed off new `CourseData` fields.
2. **Feel**: tune `speed` / `jump_velocity` / `gravity` on `player.tscn`
   (net_player exports); add coyote-time / double-jump in `net_player.gd`
   (the authority branch of `_physics_process`).
3. **Art**: swap the `ColorRect` platforms + avatar for tiles + a sprite
   (recipes: tiles via `zit-seamless-tile`, player via `zit-pixel-art`, run/jump
   cycles via `wan22-sprite-animate`); a parallax backdrop via
   `image-parallax-depthflow`.
4. **Lobby / more peers**: `res://addons/nox_netcode/lobby.tscn` is a ready
   host/join screen; bump `max_peers` in the `[nox_netcode]` settings.
5. **3D**: the netcode wiring is dimension-agnostic — swap `net_player.gd`'s base
   to `CharacterBody3D` and the `Vector2` fields to `Vector3`; the
   authority/spawn/sync code is identical.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the best time already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
script errors, and headless probes (all `fails=0`) covering the data-driven course
system + the pre-existing run/offline/netcode/config checks. As with every genre
template in this repo, probe scenes are **ephemeral** — they are written under
`res://_probes/`, run during the build, and removed afterward (the committed
skeleton ships only the game, not its test scaffolds). The checks were:

- **Course round-trip** (`fails=0`): a `CourseData` built in code survives
  dict, JSON, and file (`save_course`→`load_course`) round-trips deep-equal.
- **Editor → course** (`fails=0`): driving the designer API (2 platforms + 2
  ordered checkpoints + a hazard + start + finish) yields a VALID `CourseData`, and
  the SAME `obby.gd` builds a level from it that an avatar completes end-to-end.
- **Library** (`fails=0`): both built-ins load + list, and a saved user course
  appears in the listing and loads back by id and by name.
- **Regression** (`fails=0`): the default `Starter Climb` is byte-identical to the
  pre-refactor hardcoded course, the offline avatar still lands + completes, the
  course-sync codec resolves built-in-by-id and custom-by-json, and `net` stays inert.

Plus the pre-existing checks (still green):

- **Run-engine probe** (pure `GameManager`, `fails=0`): checkpoint progression
  with anti-skip rejection, death counting, the live clock, finish + best time,
  restart keeping the best, and a `save_data()/load_data()` round-trip.
- **Offline integration probe** (`fails=0`): the real level builds
  (`platforms=8 checkpoints=3 hazards=1 net=false`), spawns a local avatar that
  **falls and lands on a platform** (y≈440, no tunnelling to the kill line), and
  touching checkpoint 0 advances the run offline.
- **Netcode API self-probe** (`addons/nox_netcode/net_probe.tscn` → `=> OK`): the
  `Net` API (host/roster/seat/seed/teardown) is sound in the scaffolded project.
- **Config probe** (`fails=0`): `profile=realtime` + `transport=enet` are read,
  the `Net` autoload is present and **dormant offline**, and `NetEvents` is inert
  offline.

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
  shipped **in** this skeleton because the obby is its reference realtime
  consumer. It is normally injected into other templates by the `netcode`
  godogen skill (`skills/netcode/tools/netcode_gen.py`); here it is pre-wired.
- Keep it in sync with the skill's canonical copy at
  `godogen/skills/netcode/addon/nox_netcode/`.
