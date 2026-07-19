# nox_netcode — multiplayer drop-in for Godot 4

Reusable, host-authoritative multiplayer for NoxDev genre templates. One
autoload (`Net`) + a themeable lobby give any project host/join, peer lifecycle,
lobby state, seat assignment, deterministic seeding and disconnect handling.
Two profiles layer on top:

- **authority-turn** — turn-based shared state + a privileged **DM seat**
  (`NetBridge`). For the FF gamebook, board/card, any low-message-rate game.
- **realtime** — per-peer avatar sync via `MultiplayerSpawner` +
  `MultiplayerSynchronizer` (`net_player.gd` / `net_spawner.gd` / `net_events.gd`).
  For the obby, party platformers, co-op action.

This addon is **injected + wired by the `netcode` godogen skill**
(`skills/netcode/tools/netcode_gen.py`) — it is not enabled by hand. Full design:
`Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md`.

## Files

| File | Profile | Role |
|------|---------|------|
| `net_session.gd` | both | Autoload **`Net`**: host/join, transport (ENet/WebSocket), peer lifecycle → clean signals, lobby roster, seats + DM seat, shared-seed broadcast, authority helpers (`is_host`/`local_id`/`is_dm`/`require_host`/`require_dm`), disconnect policy. |
| `lobby.tscn` + `lobby.gd` | both | Host/Join screen, peer list, ready toggle, host-only Start, DM-seat picker (authority-turn). `scalable_text` labels → `ui-theme` re-skins it. |
| `session_bridge.gd` | authority-turn | Autoload **`NetBridge`**: host-authoritative advance/choose/roll, arbitration (`leader`/`vote`/`dm-confirm`), seeded dice broadcast, real `dm_push_passage` / `dm_override_roll` (`require_dm`). |
| `net_player.gd` | realtime | Authority-at-spawn `CharacterBody2D` avatar; code-built `MultiplayerSynchronizer` (position/velocity always, facing/moving on-change). |
| `net_spawner.gd` | realtime | `MultiplayerSpawner` wiring: one avatar per peer, spawn points from the `net_spawn_point` group, despawn on leave. |
| `net_events.gd` | realtime | Host-validated checkpoint/respawn/finish RPCs + shared race clock (netfox `NetworkTime` if present, else host-owned float). |
| `net_probe.gd` | both | Headless self-test — drives the API in one process, prints one `DEBUG:` line, quits. |

## Autoloads registered

- `Net` → `res://addons/nox_netcode/net_session.gd` (both profiles)
- `NetBridge` → `res://addons/nox_netcode/session_bridge.gd` (authority-turn only)

The generator writes these into `project.godot` idempotently, plus a
`[nox_netcode]` settings block (`profile`, `transport`, `arbitration`,
`default_port`, `max_peers`, `disconnect_policy`) that `Net` reads at boot.

## Transports

- **ENet** (UDP, built-in) — LAN default, lowest latency. Desktop only.
- **WebSocket** (TCP, built-in) — desktop **and** web on one path; the
  authority-turn default so a hosted gamebook is web-shippable. Higher latency
  (fine for a few commands per turn).
- **WebRTC** (UDP P2P, web) — **not bundled**. Needs the `webrtc-native`
  GDExtension + a signaling server + STUN/TURN (spec Phase 5). Selecting it
  raises a clear `connection_error`; use ENet or WebSocket until it lands.

## Authority model (why host-authoritative)

Host = peer id 1 = the single source of truth. Clients **request**; the host
**validates then broadcasts**; clients apply and render. Every DM-only RPC
re-checks `require_dm()` host-side against the actual sender id — a caller's
role claim is never trusted. Dice are seeded from `Net.session_seed` (broadcast
at Start), so rolls replay identically on every peer.

Offline (`Net.active == false`) every guard/hook is inert: the single-player
core of an opted-in template behaves byte-identically.

## Manual two-instance test (true peer sync)

Headless boot-probe proves the drop-in loads and the API is sound, but real
two-peer sync needs two running processes:

```bash
# Terminal 1 — host:
Godot --path <project> res://addons/nox_netcode/lobby.tscn
#   set Name=Host → Host → (wait) → Start

# Terminal 2 — client (same machine, loopback):
Godot --path <project> res://addons/nox_netcode/lobby.tscn
#   set Name=Client, Host/IP=127.0.0.1 → Join → toggle Ready
```

The host's peer list should show both players; Start broadcasts the seed and
begins. For a gamebook, a host advance/choice/roll should appear on the client;
DM push/override (from the DM-seat holder) should steer both. LAN across two
machines: use the host's LAN IP in the client's Host/IP field (open the port on
the host's firewall). Web: export the client to HTML5 and point it at a
WebSocket host (`ws://host:port`).

## How the obby (realtime) opts in — contract

When the obby template is built it opts into `profile: realtime` and provides a
level whose root holds a `net_spawner.gd` node (with `player_scene` = a
`net_player.gd`-rooted avatar) and a `NetEvents` child (net_events.gd). Spawn
points are any nodes in the `net_spawn_point` group. Checkpoints/finish call
`NetEvents.report_checkpoint(i)` / `report_finish()`; the host assigns the
authoritative order. Until the template exists, the realtime profile is
validated against a scratch `CharacterBody2D` platformer.

## License

MIT — see `LICENSE.md`. Uses only Godot's built-in high-level multiplayer API;
netfox is an optional, separately-pinned dependency for the realtime shared
clock / rollback (not required).
