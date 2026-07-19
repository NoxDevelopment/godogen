---
name: netcode
description: |
  Multiplayer netcode drop-in for Godot 4 genre templates. Use when a template
  needs to become playable together — a lobby, peer connect, spawn/sync, and a
  host-authoritative authority model — without hand-rolling networking. Two
  profiles: `authority-turn` (turn-based shared state + a DM seat, e.g. the FF
  gamebook) and `realtime` (per-peer avatar sync, e.g. an obby). Ships the
  reusable `nox_netcode` Godot addon + an idempotent generator that injects it,
  registers autoloads, patches project.godot, and (authority-turn) applies the
  SessionState guard patch. Full design: Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md
---

# Netcode — multiplayer drop-in

Make a scaffolded Godot 4 genre template multiplayer. One drop-in, two profiles,
a host-authoritative model, and a transport chosen for the profile. Scenes never
change — the layer intercepts at the autoload/signal boundary, the same promise the
asset-binding manifest makes for art.

> **This closes the Definition of Done "Multiplayer" row** (`skills/parity-build/STANDARDS.md`): "local + net, authoritative-host, where the genre wants it." A template whose genre wants MP isn't done until this is wired and verified two-instance.

> **Status: implemented (Phase 1–2 + realtime contract).** The reusable
> `nox_netcode` addon ships under `skills/netcode/addon/nox_netcode/` and
> `netcode_gen.py inject` wires it into a target project idempotently. Validated
> headless on Godot 4.6.1: editor import clean, the addon API self-probe passes,
> and an opted-in `ff-gamebook`'s single-player boot probe stays byte-identical
> (the guard is inert offline). True two-peer sync needs two running instances
> (see `addon/nox_netcode/README.md`) — it is not validatable headless. WebRTC
> (web realtime) is the one deferred transport (spec Phase 5, not bundled).
> Authoritative design: `Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md`.

## TL;DR

```bash
SKILL=skills/netcode/tools/netcode_gen.py   # (.claude/skills/... when installed)

# Profiles, transports, arbitration modes:
python3 $SKILL list

# Dry-run the exact files/patch a profile would write (no writes):
python3 $SKILL plan --profile authority-turn
python3 $SKILL inject --project <dir> --profile authority-turn --dry-run

# Make the FF gamebook playable together (inject addon + autoloads + patch):
python3 $SKILL inject --project <dir> --profile authority-turn --transport enet \
    --arbitration leader   # leader works with the unmodified book; vote/dm-confirm need an MP-aware book hook

# Make a realtime (obby/platformer) project multiplayer:
python3 $SKILL inject --project <dir> --profile realtime --transport enet

# Shared core only (Net autoload, no profile layer):
python3 $SKILL session --project <dir>
```

Every write is **idempotent** — re-running only confirms state. Verify with:

```bash
Godot --headless --editor --path <dir> --quit                       # import (parse check)
Godot --headless --path <dir> res://addons/nox_netcode/net_probe.tscn   # API self-probe
```

## Profiles

| Profile | For | Sync model | Transport default |
|---------|-----|-----------|-------------------|
| `authority-turn` | gamebook, board/card, any turn-based shared state | Host-authoritative command RPC; clients render off signals; a **DM seat** can steer | **WebSocket** (desktop + web, one path) |
| `realtime` | obby, party platformer, co-op action | `MultiplayerSpawner` + per-peer `MultiplayerSynchronizer`; each peer is authority over its own avatar | **ENet** (desktop/LAN) → WebRTC (web, phased) |

Both profiles share the **`Net` autoload** (host/join, transport, peer lifecycle,
lobby state, authority helpers) and the **lobby scene**. Profiles add only their
layer on top.

## The `nox_netcode` addon (what gets injected)

The reusable addon lives at `skills/netcode/addon/nox_netcode/` and is copied
wholesale into a target project's `addons/nox_netcode/`:

| File | Profile | Autoload | Role |
|------|---------|----------|------|
| `net_session.gd` | both | **`Net`** | Host/join, transport (ENet/WebSocket; WebRTC = clear not-bundled error), peer lifecycle → clean signals, lobby roster, seats + DM seat, shared-seed broadcast, `is_host`/`local_id`/`is_dm`/`require_host`/`require_dm`, disconnect policy. |
| `lobby.tscn` + `lobby.gd` | both | — | Host/Join screen: name + host/IP, peer list + ready, host-only Start, DM-seat picker. `scalable_text` labels → `ui-theme` re-skins it, no code change. |
| `session_bridge.gd` | authority-turn | **`NetBridge`** | Wraps `SessionState`: host-authoritative `advance_passage`/`choose`/`roll`, arbitration (`leader`/`vote`/`dm-confirm`), seeded dice broadcast, real `dm_push_passage`/`dm_override_roll` (`require_dm`). |
| `net_player.gd` | realtime | — | Authority-at-spawn `CharacterBody2D` avatar; code-built `MultiplayerSynchronizer` (position/velocity always, facing/moving on-change). |
| `net_spawner.gd` | realtime | — | `MultiplayerSpawner` wiring: one avatar per peer, spawn points from the `net_spawn_point` group, despawn on leave. |
| `net_player_3d.gd` | realtime | — | **3D twin** of `net_player.gd` — a `CharacterBody3D` authority avatar, `Vector3` position/velocity synced, yaw (`facing`) applied on both owner and remote. For 3D obbies / co-op / party games. |
| `net_spawner_3d.gd` | realtime | — | **3D twin** of `net_spawner.gd` — spawns `Node3D`-rooted avatars from the `net_spawn_point` group (`Node3D`/`Marker3D`) with `Vector3` positions. |
| `net_events.gd` | realtime | — | Host-validated checkpoint/respawn/finish RPCs + shared race clock (netfox `NetworkTime` if present, else host-owned float). **Dimension-agnostic** — the same file drives 2D and 3D obbies unchanged. |
| `net_probe.tscn/.gd` | both | — | Headless self-test: drives the API, prints one `DEBUG:` line, quits. |

## Subcommands

| Subcommand | Does | Profile |
|------------|------|---------|
| `inject` (= `all`) | Copy the addon, register autoloads (`Net`; +`NetBridge` for authority-turn), write `[nox_netcode]` settings, and (authority-turn) apply the `session_state.gd` guard patch. Idempotent. `--dry-run` prints the plan. | both |
| `authority-turn` / `realtime` | Thin wrappers → `inject` with that profile. | one |
| `session` / `lobby` | Shared core only: copy the addon + register just the `Net` autoload (no profile layer, no patch). | both |
| `list` | Print profiles, transports, arbitration modes. | — |
| `plan` | Print the exact files a profile writes (dry run). | — |

## Authority model (why host-authoritative)

The host (peer id 1) is the single source of truth. Clients **request**; the host
**validates then broadcasts**; clients apply and render. This is the anti-cheat
posture and the only model in which a **DM seat** is meaningful.

- **General:** every state change is an `@rpc` request to the host with explicit
  authority + transfer mode; every peer-driven node calls
  `set_multiplayer_authority()` at spawn.
- **DM seat (gamebook):** a privileged *player* role (may be the host or a delegated
  peer) that can force the party's passage and override dice. Maps exactly onto the
  `ff-gamebook` template's two shipped no-op hooks (`dm_push_passage`,
  `dm_override_roll`), which this profile turns into real host-side implementations.

## How a template opts in

Registry-only + one skill invocation (no bespoke networking per template):

1. Add `{skill: "netcode", params: {profile, transport, arbitration}}` to the
   template's `primitives`, and a `multiplayer: {profile, transport, ...}` field on
   the registry entry so the Studio picker shows a "Playable together" badge. The
   `ff-gamebook` entry is the worked example. `authority-turn` needs **no**
   `vendoredAddons` (native `@rpc` suffices); a `realtime` template that wants the
   netfox shared clock / rollback pins netfox separately (MIT, per the kit survey).
2. Run `netcode_gen.py inject --project <dir> --profile <p>` (opt-in — it is not
   auto-applied by scaffolding because authority-turn edits `session_state.gd`).
3. The skill copies the addon, registers autoloads, writes settings, and applies
   the guard patch (authority-turn). All idempotent.
4. ABI is automatic — `Net` joins `persistent`, the lobby uses standard widgets and
   `scalable_text`; `menu_system` / `save_system` / `settings_system` / `ui-theme`
   drop in unchanged.
5. Validate headless (import clean + API self-probe + single-player probe
   byte-identical), do the manual two-instance sync check, then flip the entry's
   `multiplayer.status` to `validated` for the pinned engine version.

### The obby (realtime) opts in the same way

When the Wave-3 obby template is built it adds
`{skill: "netcode", params: {profile: "realtime", transport: "enet"}}` and a
`multiplayer: {profile: "realtime", transport: "enet"}` field, then its level
provides what the `realtime` profile consumes (spec "Obby integration points"):
a level root holding a `net_spawner.gd` node (its `player_scene` = a
`net_player.gd`-rooted avatar) and a `NetEvents` child; spawn points tagged into
the `net_spawn_point` group; checkpoints/finish calling
`NetEvents.report_checkpoint(i)` / `report_finish()` so the host owns the order.
No scene code changes for the netcode itself — same intercept-at-the-boundary
promise. **Both obby templates now ship this pre-wired:** `obby-multiplayer`
(2D, `net_player.gd`/`net_spawner.gd`) and `obby-3d-multiplayer` (3D,
`net_player_3d.gd`/`net_spawner_3d.gd`) — same `Net`, same `NetEvents`, same
offline↔online seam, only the avatar dimension differs. Each is boot-verified
headless (import clean + the addon self-probe + a run-engine/integration probe
`fails=0`); true 2-peer avatar sync still needs two live instances.

## Transport choice

| Transport | Web | Desktop | Latency | Best for |
|-----------|-----|---------|---------|----------|
| ENet (UDP) | ❌ | ✅ built-in | lowest | realtime obby, desktop/LAN |
| WebSocket (TCP) | ✅ | ✅ built-in | higher (HOL) | authority-turn gamebook everywhere, low-rate |
| WebRTC (UDP P2P) | ✅ | ⚠️ GDExtension | low | realtime obby on web — **not bundled** (spec Phase 5) |

**ENet is the LAN default and the validated path** for both profiles here — it is
built-in, lowest-latency, and what the two-instance test uses. **WebSocket is
implemented** and is the spec's web-shippable authority-turn default (spec
Phase 3): pass `--transport websocket` for one desktop+web code path. **WebRTC is
deferred** — selecting it raises a clear `connection_error` (it needs the
`webrtc-native` GDExtension + a signaling server + STUN/TURN). Transport is a
`[nox_netcode]` project setting, overridable per invocation via `--transport` or
at runtime via the `Net.host()/join()` config.

## Validation

Three gates, all headless + CI-friendly:

1. **Import clean** — `Godot --headless --editor --path <dir> --quit`: zero parse /
   script errors across the injected addon (all profiles).
2. **API self-probe** — `res://addons/nox_netcode/net_probe.tscn`: one process hosts
   on loopback ENet and drives the API, printing e.g.
   `DEBUG: nox_netcode probe … host=true is_dm=true … seed=true teardown=true => OK`.
   Proves the drop-in loads and the transport/authority/DM-seat/seed API is sound.
3. **Regression** — the opted-in template's single-player boot probe must stay
   **byte-identical** (the guard is inert when `Net.active` is false). Verified on
   `ff-gamebook` @ 4.6.1: identical to the pre-injection line, `dm_noop=true` and all.

**Honest limitation:** true two-peer sync (a client choice routing through the
host, the DM steering both books, avatars moving on the other screen) needs **two
running instances** and cannot be validated headless — the boot-probe proves it
loads and the API is sound, not that packets flow between two peers. Run the manual
two-instance steps in `addon/nox_netcode/README.md` to confirm live sync. A template
is `validated` only for the exact engine version it was checked against.

## Do not

- Do **not** mutate shared state on clients — request from the host.
- Do **not** edit scene code to add networking — intercept at the autoload boundary.
- Do **not** trust a caller's role claim — re-check `require_host()` / `require_dm()`
  host-side on every privileged RPC.
- Do **not** roll client-local dice or use client-local randomness for shared
  outcomes — the host rolls with the broadcast seed; clients replay.
