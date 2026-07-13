#!/usr/bin/env python3
"""netcode_gen — multiplayer drop-in generator for Godot 4 genre templates.

Skeleton stage (Phase 0). `list` and `plan` are fully functional; the emit
subcommands (`session`, `lobby`, `authority-turn`, `realtime`, `all`) report the
exact file plan and skeleton status without writing game code yet — the emitters
are filled in per the phased plan in
Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md and validated headless before
a template flips to `multiplayer: validated`.

Design contract (do not drift from the spec):
  - Host-authoritative: clients request, the host validates + broadcasts.
  - Zero scene changes: intercept at the autoload/signal boundary.
  - Two profiles share the `Net` autoload + lobby; profiles add only their layer.

Usage:
  python3 netcode_gen.py list
  python3 netcode_gen.py plan --profile authority-turn
  python3 netcode_gen.py session       --output res://scripts/net/
  python3 netcode_gen.py lobby         --output res://scenes/net/
  python3 netcode_gen.py authority-turn --project <dir> [--transport websocket] [--arbitration dm-confirm]
  python3 netcode_gen.py realtime      --project <dir> [--transport enet]
  python3 netcode_gen.py all --profile authority-turn --project <dir>
"""
from __future__ import annotations

import argparse
import sys

SPEC = "Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md"

# --- Profiles -----------------------------------------------------------------

PROFILES = {
    "authority-turn": {
        "for": "gamebook, board/card, any turn-based shared state (has a DM seat)",
        "sync": "host-authoritative command RPC; clients render off signals",
        "default_transport": "websocket",
        "consumes": "the template's SessionState autoload (advance_passage/choose/roll + DM hooks)",
    },
    "realtime": {
        "for": "obby, party platformer, co-op action",
        "sync": "MultiplayerSpawner + per-peer MultiplayerSynchronizer; peer owns its avatar",
        "default_transport": "enet",
        "consumes": "a spawn parent + a NetPlayer avatar scene + spawn points",
    },
}

TRANSPORTS = {
    "enet": "UDP, built-in, lowest latency, desktop/LAN only (no browser)",
    "websocket": "TCP, built-in, desktop + web on one path, higher latency (HOL blocking)",
    "webrtc": "UDP P2P, native web / GDExtension on desktop, needs signaling + STUN/TURN",
}

ARBITRATION = {
    "leader": "a designated player decides the party's choice",
    "vote": "majority of players; host breaks ties",
    "dm-confirm": "the DM seat approves a choice before it commits",
}

# --- File plans (what each subcommand emits, by phase) ------------------------
# Paths are project-relative; {out} is the --output dir for the shared-core files.

SHARED_CORE = [
    ("scripts/net/net_session.gd",
     'autoload "Net": host/join, transport select, peer lifecycle -> clean '
     'signals, lobby state, authority helpers, disconnect policy'),
    ("scenes/net/lobby.tscn",
     "lobby screen: Host/Join, session code or IP, peer list + ready, host-only "
     "Start, seat picker (DM seat in authority-turn)"),
    ("scenes/net/lobby.gd", "lobby controller (binds to Net signals)"),
]

PROFILE_FILES = {
    "authority-turn": [
        ("scripts/net/session_bridge.gd",
         "wraps SessionState: host-authoritative advance/choose/roll, seeded dice "
         "broadcast, arbitration, real dm_push_passage/dm_override_roll (require_dm)"),
        ("scripts/session_state.gd [PATCH]",
         "pinned registry find/replace: insert 3-line network guard at the top of "
         "advance_passage/choose/roll; point the two DM hooks at the bridge"),
    ],
    "realtime": [
        ("scripts/net/net_player.gd",
         "authority-at-spawn avatar; MultiplayerSynchronizer for position/velocity/"
         "state (unreliable-ordered); ignores local input when not authority"),
        ("scenes/<level>.tscn [WIRING]",
         "MultiplayerSpawner under the level root; spawn points; host assigns a "
         "spawn per peer; despawn on leave"),
        ("scripts/net/net_events.gd",
         "host-validated reliable event RPCs (checkpoint/respawn/finish) + shared "
         "timer using netfox NetworkTime"),
    ],
}


def _phase_note(subcmd: str) -> str:
    return (
        f"[netcode:skeleton] `{subcmd}` does not emit game code yet (Phase 0).\n"
        f"  The file plan above is the contract. Implement per the phased plan in\n"
        f"  {SPEC} and validate headless (two peers) before flipping a template to\n"
        f"  `multiplayer: validated`. Run `plan --profile <p>` for a profile's full plan."
    )


def _print_plan(profile: str | None) -> None:
    print("Shared core (both profiles):")
    for path, desc in SHARED_CORE:
        print(f"  {path}\n      {desc}")
    if profile:
        p = PROFILES[profile]
        print(f"\nProfile `{profile}` adds:")
        for path, desc in PROFILE_FILES[profile]:
            print(f"  {path}\n      {desc}")
        print(f"\n  sync            : {p['sync']}")
        print(f"  default transport: {p['default_transport']}  ({TRANSPORTS[p['default_transport']]})")
        print(f"  consumes         : {p['consumes']}")


# --- Subcommands --------------------------------------------------------------

def cmd_list(_args) -> int:
    print("netcode - multiplayer drop-in for Godot 4 templates (skeleton stage)\n")
    print("PROFILES:")
    for name, p in PROFILES.items():
        print(f"  {name:<15} {p['for']}")
        print(f"  {'':<15} sync: {p['sync']}")
        print(f"  {'':<15} default transport: {p['default_transport']}")
    print("\nTRANSPORTS:")
    for name, desc in TRANSPORTS.items():
        print(f"  {name:<11} {desc}")
    print("\nARBITRATION (authority-turn):")
    for name, desc in ARBITRATION.items():
        print(f"  {name:<11} {desc}")
    print("\nSubcommands: list | plan | session | lobby | authority-turn | realtime | all")
    print(f"Full design: {SPEC}")
    return 0


def cmd_plan(args) -> int:
    if args.profile and args.profile not in PROFILES:
        print(f"unknown profile: {args.profile}", file=sys.stderr)
        return 2
    _print_plan(args.profile)
    return 0


def _emit(subcmd: str, profile: str | None) -> int:
    # Skeleton: print the plan + honest status. Emitters land per the phased plan.
    if profile:
        _print_plan(profile)
    else:
        print("Shared core (both profiles):")
        for path, desc in SHARED_CORE:
            print(f"  {path}\n      {desc}")
    print()
    print(_phase_note(subcmd))
    return 0


def cmd_session(args) -> int:
    return _emit("session", None)


def cmd_lobby(args) -> int:
    return _emit("lobby", None)


def cmd_authority_turn(args) -> int:
    return _emit("authority-turn", "authority-turn")


def cmd_realtime(args) -> int:
    return _emit("realtime", "realtime")


def cmd_all(args) -> int:
    if args.profile not in PROFILES:
        print(f"unknown profile: {args.profile}", file=sys.stderr)
        return 2
    return _emit("all", args.profile)


# --- CLI ----------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="netcode_gen.py",
        description="Multiplayer netcode drop-in generator for Godot 4 templates (skeleton).",
    )
    sub = parser.add_subparsers(required=True, dest="cmd")

    def add_out(p):
        p.add_argument("--output", default="res://scripts/net/",
                       help="Output dir for emitted scripts (default res://scripts/net/)")

    def add_project(p):
        p.add_argument("--project", help="Target Godot project dir (profile emit)")
        p.add_argument("--transport", choices=list(TRANSPORTS),
                       help="Override the profile's default transport")

    sub.add_parser("list", help="List profiles, transports, and the emit plan")

    p = sub.add_parser("plan", help="Print the file plan a profile would emit (dry run)")
    p.add_argument("--profile", choices=list(PROFILES),
                   help="Include this profile's added files (omit for shared core only)")

    p = sub.add_parser("session", help="Emit the Net autoload (shared core)")
    add_out(p)

    p = sub.add_parser("lobby", help="Emit the lobby scene + script (shared core)")
    add_out(p)

    p = sub.add_parser("authority-turn",
                       help="Emit the SessionState bridge + DM-seat model")
    add_project(p)
    p.add_argument("--arbitration", choices=list(ARBITRATION), default="dm-confirm",
                   help="Party-choice arbitration mode (default dm-confirm)")

    p = sub.add_parser("realtime", help="Emit avatar spawn/sync wiring")
    add_project(p)

    p = sub.add_parser("all", help="Emit the shared core + one profile")
    p.add_argument("--profile", required=True, choices=list(PROFILES))
    add_project(p)
    p.add_argument("--arbitration", choices=list(ARBITRATION), default="dm-confirm")

    return parser


DISPATCH = {
    "list": cmd_list,
    "plan": cmd_plan,
    "session": cmd_session,
    "lobby": cmd_lobby,
    "authority-turn": cmd_authority_turn,
    "realtime": cmd_realtime,
    "all": cmd_all,
}


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return DISPATCH[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
