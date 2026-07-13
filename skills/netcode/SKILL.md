---
name: netcode
description: |
  Multiplayer netcode drop-in for Godot 4 genre templates. Use when a template
  needs to become playable together — a lobby, peer connect, spawn/sync, and a
  host-authoritative authority model — without hand-rolling networking. Two
  profiles: `authority-turn` (turn-based shared state + a DM seat, e.g. the FF
  gamebook) and `realtime` (per-peer avatar sync, e.g. an obby). Skeleton stage:
  the shared-core generator and file plan are defined; profile emitters are being
  built per the phased plan. Full design: Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md
---

# Netcode — multiplayer drop-in

Make a scaffolded Godot 4 genre template multiplayer. One drop-in, two profiles,
a host-authoritative model, and a transport chosen for the profile. Scenes never
change — the layer intercepts at the autoload/signal boundary, the same promise the
asset-binding manifest makes for art.

> **Status: skeleton.** Phase 0 of the build plan. `list` and `plan` are working;
> the shared-core (`session`, `lobby`) and profile emitters (`authority-turn`,
> `realtime`) are being filled in per the spec's phased plan and validated headless
> before a template flips to `multiplayer: validated`. The authoritative design is
> `Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md` — read it before implementing.

## TL;DR

```bash
# What this skill can emit and the two profiles:
python3 .claude/skills/netcode/tools/netcode_gen.py list

# See exactly which files a profile would write into a project (no writes):
python3 .claude/skills/netcode/tools/netcode_gen.py plan --profile authority-turn

# Emit the shared core (autoload + lobby) into a project:
python3 .claude/skills/netcode/tools/netcode_gen.py session --output res://scripts/net/
python3 .claude/skills/netcode/tools/netcode_gen.py lobby   --output res://scenes/net/

# Everything for a profile at once:
python3 .claude/skills/netcode/tools/netcode_gen.py all --profile authority-turn --project <dir>
```

## Profiles

| Profile | For | Sync model | Transport default |
|---------|-----|-----------|-------------------|
| `authority-turn` | gamebook, board/card, any turn-based shared state | Host-authoritative command RPC; clients render off signals; a **DM seat** can steer | **WebSocket** (desktop + web, one path) |
| `realtime` | obby, party platformer, co-op action | `MultiplayerSpawner` + per-peer `MultiplayerSynchronizer`; each peer is authority over its own avatar | **ENet** (desktop/LAN) → WebRTC (web, phased) |

Both profiles share the **`Net` autoload** (host/join, transport, peer lifecycle,
lobby state, authority helpers) and the **lobby scene**. Profiles add only their
layer on top.

## What this emits

| Subcommand | Files | Profile | Purpose |
|------------|-------|---------|---------|
| `session` | `net_session.gd` (autoload `Net`) | both | Host/join, transport selection (ENet/WebSocket/WebRTC), peer lifecycle → clean signals, lobby state, authority helpers (`is_host`/`is_dm`/`require_host`/`require_dm`), disconnect policy. |
| `lobby` | `lobby.tscn` + `lobby.gd` | both | Host/Join screen: session code or IP, peer list + ready, host-only Start, seat picker (DM seat in `authority-turn`). NoxDev UI ABI so `ui-theme` re-skins it. |
| `authority-turn` | `session_bridge.gd` + a pinned `session_state.gd` guard patch | authority-turn | Wraps the template's `SessionState`: host-authoritative `advance_passage`/`choose`/`roll`, seeded dice broadcast, arbitration (`leader`/`vote`/`dm-confirm`), and the real `dm_push_passage`/`dm_override_roll` (host-side, `require_dm`). |
| `realtime` | `net_player.gd` + spawner/synchronizer wiring | realtime | Authority-at-spawn avatars, transform/state sync (unreliable-ordered), spawn points, host-validated event RPCs (checkpoint/finish), netfox `NetworkTime` clock. |
| `all` | the shared core + one profile | — | One-shot for a template opt-in. |
| `list` | *(none)* | — | Print profiles, transports, and emit plan. |
| `plan` | *(none)* | — | Print the exact file list a profile writes (dry run). |

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

1. Add the netcode addon (**netfox**, pinned SHA, MIT) to the template's
   `vendoredAddons`. `authority-turn`-only templates may skip it (native `@rpc`
   suffices) or pin just `NetworkTime`.
2. Add `{skill: "netcode", params: {profile: "...", transport: "...", ...}}` to the
   template's `primitives`.
3. Scaffold runs the skill → emits the shared core + profile files, registers the
   `Net` autoload, and (authority-turn) applies the `SessionState` guard patch.
4. ABI is automatic — the autoload joins `persistent`, uses the standard buses /
   `pause` action, lobby labels are `scalable_text`; `menu_system` / `save_system` /
   `settings_system` / `ui-theme` drop in unchanged.
5. Validate headless (two peers), then flip the template's `multiplayer` status to
   `validated` for the pinned engine + addon SHA.

## Transport choice

| Transport | Web | Desktop | Latency | Best for |
|-----------|-----|---------|---------|----------|
| ENet (UDP) | ❌ | ✅ built-in | lowest | realtime obby, desktop/LAN |
| WebSocket (TCP) | ✅ | ✅ built-in | higher (HOL) | authority-turn gamebook everywhere, low-rate |
| WebRTC (UDP P2P) | ✅ | ⚠️ GDExtension | low | realtime obby on web (needs signaling + STUN/TURN) |

Default: gamebook → WebSocket (one path, web-shippable day one); obby → ENet first,
WebRTC for web later. Overridable via the `transport` param / `Net` config.

## Validation

Two `--headless` peers on loopback; a boot probe drives the scripted flow and prints
a deterministic line (ff-gamebook probe convention). The single-player boot probe of
any opted-in template must stay byte-identical — the network guard is inert offline.
A template is `validated` only for the exact engine version **and** netcode-addon SHA.

## Do not

- Do **not** mutate shared state on clients — request from the host.
- Do **not** edit scene code to add networking — intercept at the autoload boundary.
- Do **not** trust a caller's role claim — re-check `require_host()` / `require_dm()`
  host-side on every privileged RPC.
- Do **not** roll client-local dice or use client-local randomness for shared
  outcomes — the host rolls with the broadcast seed; clients replay.
