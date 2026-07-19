#!/usr/bin/env python3
"""netcode_gen — multiplayer drop-in generator for Godot 4 genre templates.

Injects the reusable `nox_netcode` addon into a scaffolded Godot project, wires
its autoloads into project.godot, writes the `[nox_netcode]` settings block, and
(for the authority-turn profile) applies the pinned SessionState guard patch that
makes the template's story-state autoload network-aware WITHOUT touching scene
code. Every write is idempotent — re-running is a no-op beyond confirming state.

Two profiles (spec: MULTIPLAYER_TEMPLATE_SPEC.md):
  authority-turn  turn-based shared state + a DM seat (the FF gamebook)
  realtime        per-peer avatar sync (the future obby)

Both share the `Net` autoload + lobby; authority-turn adds the `NetBridge`
autoload + the SessionState patch; realtime adds the spawner/synchronizer/events
scripts (already in the addon, wired by the level).

Usage:
  python netcode_gen.py list
  python netcode_gen.py plan   --profile authority-turn
  python netcode_gen.py inject --project <dir> --profile authority-turn [--transport enet]
                               [--arbitration leader] [--dry-run]
  python netcode_gen.py all    --project <dir> --profile realtime --transport enet
  python netcode_gen.py authority-turn --project <dir> [--transport enet] [--arbitration ...]
  python netcode_gen.py realtime       --project <dir> [--transport enet]
  python netcode_gen.py session --project <dir>   # shared core only (Net autoload)
  python netcode_gen.py lobby   --project <dir>   # lobby files only

Exit codes: 0 ok, 1 usage/registry error, 2 project/patch error.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

SPEC = "Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md"

# The canonical addon source that ships with this skill.
ADDON_SRC = Path(__file__).resolve().parent.parent / "addon" / "nox_netcode"
ADDON_TARGET_REL = "addons/nox_netcode"

# --- Profiles / transports / arbitration -------------------------------------

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
    "webrtc": "UDP P2P, native web / GDExtension on desktop, needs signaling + STUN/TURN (not bundled)",
}

ARBITRATION = {
    "leader": "a designated player decides the party's choice",
    "vote": "majority of players; host breaks ties",
    "dm-confirm": "the DM seat approves a choice before it commits",
}

# Autoloads each profile registers (name -> res:// script).
BASE_AUTOLOADS = {"Net": f"res://{ADDON_TARGET_REL}/net_session.gd"}
PROFILE_AUTOLOADS = {
    "authority-turn": {"NetBridge": f"res://{ADDON_TARGET_REL}/session_bridge.gd"},
    "realtime": {},
}

# Default [nox_netcode] settings. `transport`/`arbitration`/`profile` are
# overridden per invocation.
DEFAULT_SETTINGS = {
    "default_port": 24567,
    "max_peers": 8,
    "disconnect_policy": {
        "authority-turn": "pause-and-wait",
        "realtime": "drop-and-continue",
    },
}

# --- The pinned SessionState guard patch (authority-turn) --------------------
# find/replace pairs applied to <project>/scripts/session_state.gd. `find` must
# match exactly (tabs + newlines) or the patch hard-fails so the pin gets
# re-verified. `MARKER` presence means the file is already patched (idempotent).

SESSION_STATE_FILE = "scripts/session_state.gd"
PATCH_MARKER = "NetBridge.intercept_advance"

SESSION_STATE_PATCHES = [
    # advance_passage — suppress on clients; host broadcasts.
    (
        "func advance_passage(passage_id: String) -> void:\n"
        "\tcurrent_passage = passage_id",
        "func advance_passage(passage_id: String) -> void:\n"
        "\tif Net.active and not has_meta(\"_net_applying\") and NetBridge.intercept_advance(passage_id):\n"
        "\t\treturn  # nox_netcode: client renders off the host broadcast\n"
        "\tcurrent_passage = passage_id",
    ),
    # choose — route the party decision through the host's arbitration.
    (
        "func choose(next_id: String, choice_text := \"\") -> String:\n"
        "\tchoice_made.emit(next_id, choice_text)\n"
        "\treturn next_id",
        "func choose(next_id: String, choice_text := \"\") -> String:\n"
        "\tif Net.active and not has_meta(\"_net_applying\"):\n"
        "\t\treturn NetBridge.intercept_choose(next_id, choice_text)  # nox_netcode\n"
        "\tchoice_made.emit(next_id, choice_text)\n"
        "\treturn next_id",
    ),
    # roll — the host rolls with the shared seed; clients replay.
    (
        "func roll(stat: String) -> bool:\n"
        "\tvar ok: bool = await Dice.test(stat)",
        "func roll(stat: String) -> bool:\n"
        "\tif Net.active and not has_meta(\"_net_applying\"):\n"
        "\t\treturn await NetBridge.intercept_roll(stat, false)  # nox_netcode\n"
        "\tvar ok: bool = await Dice.test(stat)",
    ),
    # roll_luck — same, and LUCK attrition happens host-side.
    (
        "func roll_luck() -> bool:\n"
        "\tvar ok: bool = await Dice.test_luck()",
        "func roll_luck() -> bool:\n"
        "\tif Net.active and not has_meta(\"_net_applying\"):\n"
        "\t\treturn await NetBridge.intercept_roll(\"luck\", true)  # nox_netcode\n"
        "\tvar ok: bool = await Dice.test_luck()",
    ),
    # dm_push_passage — route the DM's push through the host in MP; keep the local
    # (single-player DM) behavior otherwise. Anchored on the current real hook.
    (
        "func dm_push_passage(passage_id: String) -> bool:\n"
        "\tadvance_passage(passage_id)\n"
        "\treturn true",
        "func dm_push_passage(passage_id: String) -> bool:\n"
        "\tif Net.active and not has_meta(\"_net_applying\"):\n"
        "\t\treturn NetBridge.dm_push_passage(passage_id)  # nox_netcode\n"
        "\tadvance_passage(passage_id)\n"
        "\treturn true",
    ),
    # dm_override_roll — route through the host in MP; keep local behavior otherwise.
    (
        "func dm_override_roll(result: Dictionary) -> bool:\n"
        "\tvar forced := result.duplicate(true)",
        "func dm_override_roll(result: Dictionary) -> bool:\n"
        "\tif Net.active and not has_meta(\"_net_applying\"):\n"
        "\t\treturn NetBridge.dm_override_roll(result)  # nox_netcode\n"
        "\tvar forced := result.duplicate(true)",
    ),
]


# --- File plan (for list/plan/dry-run) ---------------------------------------

SHARED_CORE = [
    ("addons/nox_netcode/net_session.gd", 'autoload "Net": host/join, transport, peer lifecycle -> clean signals, lobby state, seats + DM seat, seed broadcast, authority helpers, disconnect policy'),
    ("addons/nox_netcode/lobby.tscn", "lobby screen: Host/Join, name + host/IP, peer list + ready, host-only Start, DM-seat picker (authority-turn)"),
    ("addons/nox_netcode/lobby.gd", "lobby controller (binds to Net signals only)"),
    ("addons/nox_netcode/net_probe.gd", "headless self-test (drives the API, prints one DEBUG line, quits)"),
    ("addons/nox_netcode/net_probe.tscn", "scene wrapper for the probe"),
]

PROFILE_FILES = {
    "authority-turn": [
        ("addons/nox_netcode/session_bridge.gd", 'autoload "NetBridge": host-authoritative advance/choose/roll, arbitration (leader/vote/dm-confirm), seeded dice broadcast, real dm_push_passage/dm_override_roll (require_dm)'),
        ("scripts/session_state.gd [PATCH]", "pinned guard: advance/choose/roll route through NetBridge when Net.active; the two DM hooks flip from no-op to host-side implementations"),
    ],
    "realtime": [
        ("addons/nox_netcode/net_player.gd", "authority-at-spawn CharacterBody2D avatar; code-built MultiplayerSynchronizer (position/velocity always, facing/moving on-change)"),
        ("addons/nox_netcode/net_spawner.gd", "MultiplayerSpawner wiring: one avatar per peer, spawn points from the net_spawn_point group, despawn on leave"),
        ("addons/nox_netcode/net_events.gd", "host-validated checkpoint/respawn/finish RPCs + shared race clock (netfox NetworkTime if present, else host-owned float)"),
    ],
}


def _print_plan(profile: str | None) -> None:
    print("Shared core (both profiles) - copied into the project + `Net` autoload registered:")
    for path, desc in SHARED_CORE:
        print(f"  {path}\n      {desc}")
    if profile:
        p = PROFILES[profile]
        print(f"\nProfile `{profile}` adds:")
        for path, desc in PROFILE_FILES[profile]:
            print(f"  {path}\n      {desc}")
        print(f"\n  sync             : {p['sync']}")
        print(f"  default transport: {p['default_transport']}  ({TRANSPORTS[p['default_transport']]})")
        print(f"  consumes         : {p['consumes']}")
        autoloads = dict(BASE_AUTOLOADS)
        autoloads.update(PROFILE_AUTOLOADS[profile])
        print("  autoloads        : " + ", ".join(f"{k}={v}" for k, v in autoloads.items()))


# --- project.godot manipulation (idempotent) ---------------------------------

def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def register_autoloads(text: str, autoloads: dict[str, str]) -> tuple[str, list[str], list[str]]:
    """Add missing `Name="*res://..."` lines to [autoload]. Returns (text, added, skipped)."""
    added: list[str] = []
    skipped: list[str] = []
    m = re.search(r"(?ms)^\[autoload\]\s*?\n(.*?)(?=^\[|\Z)", text)
    lines = []
    for name, script in autoloads.items():
        if re.search(rf"(?m)^{re.escape(name)}\s*=", text):
            skipped.append(name)
        else:
            lines.append(f'{name}="*{script}"')
            added.append(name)
    if not lines:
        return text, added, skipped
    block = "\n".join(lines) + "\n"
    if m:
        # Insert right after the last autoload entry, keeping one blank line
        # before the next section (clean, human-diffable project.godot).
        body = m.group(1)
        stripped = body.rstrip("\n")
        text = (text[:m.start(1)] + stripped + "\n" + block + "\n"
                + text[m.end(1):])
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += f"\n[autoload]\n\n{block}"
    return text, added, skipped


def write_settings(text: str, settings: dict) -> str:
    """Replace (or append) the [nox_netcode] section wholesale so transport /
    profile stay in sync with the invocation. Idempotent."""
    lines = [f"[nox_netcode]", ""]
    for key, value in settings.items():
        if isinstance(value, str):
            lines.append(f'{key}="{value}"')
        elif isinstance(value, bool):
            lines.append(f"{key}={'true' if value else 'false'}")
        else:
            lines.append(f"{key}={value}")
    section = "\n".join(lines) + "\n"
    existing = re.search(r"(?ms)^\[nox_netcode\]\s*?\n.*?(?=^\[|\Z)", text)
    if existing:
        text = text[: existing.start()] + section + text[existing.end():]
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += "\n" + section
    return text


# --- SessionState guard patch (authority-turn) -------------------------------

def patch_session_state(project: Path, dry_run: bool) -> str:
    """Apply the pinned guard patch. Returns a status string. Hard-fails (exit 2)
    if the file exists but an anchor is missing and it isn't already patched."""
    target = project / SESSION_STATE_FILE
    if not target.is_file():
        return "skipped (no scripts/session_state.gd — not a SessionState template)"
    text = _read(target)
    if PATCH_MARKER in text:
        return "already applied (idempotent no-op)"
    # Verify every anchor is present BEFORE writing anything.
    for find, _replace in SESSION_STATE_PATCHES:
        if find not in text:
            sys.exit(
                f"[netcode] session_state.gd patch anchor not found "
                f"(template drifted from the pinned shape?):\n  {find.splitlines()[0]!r}"
            )
    if dry_run:
        return "would apply 6 guards (dry-run)"
    for find, replace in SESSION_STATE_PATCHES:
        text = text.replace(find, replace, 1)
    _write(target, text)
    return "applied (advance/choose/roll guards + DM hooks)"


# --- Addon copy --------------------------------------------------------------

def copy_addon(project: Path, dry_run: bool) -> list[str]:
    """Copy the addon into <project>/addons/nox_netcode (idempotent overwrite).
    Returns the list of project-relative files present after the copy."""
    if not ADDON_SRC.is_dir():
        sys.exit(f"[netcode] addon source missing: {ADDON_SRC}")
    dst = project / ADDON_TARGET_REL
    files: list[str] = []
    for src in sorted(ADDON_SRC.rglob("*")):
        if src.is_dir() or "__pycache__" in src.parts:
            continue
        rel = src.relative_to(ADDON_SRC)
        files.append(f"{ADDON_TARGET_REL}/{rel.as_posix()}")
    if not dry_run:
        dst.mkdir(parents=True, exist_ok=True)
        for src in sorted(ADDON_SRC.rglob("*")):
            if src.is_dir() or "__pycache__" in src.parts:
                continue
            rel = src.relative_to(ADDON_SRC)
            out = dst / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, out)
    return files


# --- The injection flow ------------------------------------------------------

def _resolve_project(arg: str | None) -> Path:
    if not arg:
        sys.exit("[netcode] --project <dir> is required for this subcommand.")
    project = Path(arg).resolve()
    if not (project / "project.godot").is_file():
        sys.exit(f"[netcode] no project.godot in {project} (scaffold the template first).")
    return project


def inject(project: Path, profile: str, transport: str, arbitration: str,
           dry_run: bool, autoloads_only: dict | None = None,
           do_patch: bool = True) -> dict:
    """Full injection: copy addon, register autoloads, write settings, patch.
    `autoloads_only` restricts registration (used by the partial `session`/
    `lobby` subcommands); None means the profile's full autoload set."""
    project_godot = project / "project.godot"

    files = copy_addon(project, dry_run)

    autoloads = dict(BASE_AUTOLOADS)
    if autoloads_only is not None:
        autoloads = autoloads_only
    elif profile in PROFILE_AUTOLOADS:
        autoloads.update(PROFILE_AUTOLOADS[profile])

    text = _read(project_godot)
    text, added, skipped = register_autoloads(text, autoloads)

    settings = {
        "profile": profile,
        "transport": transport,
        "arbitration": arbitration,
        "default_port": DEFAULT_SETTINGS["default_port"],
        "max_peers": DEFAULT_SETTINGS["max_peers"],
        "disconnect_policy": DEFAULT_SETTINGS["disconnect_policy"].get(profile, "pause-and-wait"),
    }
    if autoloads_only is None:
        text = write_settings(text, settings)

    if not dry_run:
        _write(project_godot, text)

    patch_status = "n/a"
    if do_patch and profile == "authority-turn" and autoloads_only is None:
        patch_status = patch_session_state(project, dry_run)

    return {
        "ok": True,
        "project": str(project),
        "profile": profile,
        "transport": transport,
        "arbitration": arbitration if profile == "authority-turn" else None,
        "dry_run": dry_run,
        "addon_files": len(files),
        "autoloads_added": added,
        "autoloads_present_already": skipped,
        "settings": settings if autoloads_only is None else None,
        "session_state_patch": patch_status,
        "next_steps": [
            f"Import once: Godot --headless --editor --path {project} --quit",
            f"Self-test:   Godot --headless --path {project} res://{ADDON_TARGET_REL}/net_probe.tscn",
            "Two-instance play: run res://addons/nox_netcode/lobby.tscn in two instances "
            "(Host in one, Join 127.0.0.1 in the other) — see the addon README.",
        ],
    }


# --- Subcommands -------------------------------------------------------------

def cmd_list(_args) -> int:
    print("netcode - multiplayer drop-in for Godot 4 templates\n")
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
    print("\nSubcommands: list | plan | inject | all | authority-turn | realtime | session | lobby")
    print(f"Addon source: {ADDON_SRC}")
    print(f"Full design : {SPEC}")
    return 0


def cmd_plan(args) -> int:
    if args.profile and args.profile not in PROFILES:
        print(f"unknown profile: {args.profile}", file=sys.stderr)
        return 1
    _print_plan(args.profile)
    return 0


def _resolve_transport(args, profile: str) -> str:
    if getattr(args, "transport", None):
        return args.transport
    return PROFILES[profile]["default_transport"]


def cmd_inject(args) -> int:
    if args.profile not in PROFILES:
        print(f"unknown profile: {args.profile}", file=sys.stderr)
        return 1
    project = _resolve_project(args.project)
    transport = _resolve_transport(args, args.profile)
    arbitration = getattr(args, "arbitration", "leader")
    if args.dry_run:
        _print_plan(args.profile)
        print()
    result = inject(project, args.profile, transport, arbitration, args.dry_run)
    print(json.dumps(result, indent=2))
    return 0


def cmd_authority_turn(args) -> int:
    args.profile = "authority-turn"
    return cmd_inject(args)


def cmd_realtime(args) -> int:
    args.profile = "realtime"
    args.arbitration = "leader"  # unused by realtime; kept for a uniform call
    return cmd_inject(args)


def cmd_session(args) -> int:
    """Shared core only: copy the addon + register just the `Net` autoload."""
    project = _resolve_project(args.project)
    result = inject(project, "authority-turn",
                    _resolve_transport(args, "authority-turn"), "leader",
                    args.dry_run, autoloads_only=dict(BASE_AUTOLOADS), do_patch=False)
    result["note"] = "shared core only (Net autoload); run a profile subcommand to add its layer"
    print(json.dumps(result, indent=2))
    return 0


def cmd_lobby(args) -> int:
    """Lobby files are part of the addon copy; this ensures the addon is present
    and the Net autoload is registered (the lobby has no autoload of its own)."""
    return cmd_session(args)


# --- CLI ---------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="netcode_gen.py",
        description="Multiplayer netcode drop-in generator for Godot 4 templates.",
    )
    sub = parser.add_subparsers(required=True, dest="cmd")

    def add_project(p, with_arbitration=False):
        p.add_argument("--project", help="Target Godot project dir (must contain project.godot)")
        p.add_argument("--transport", choices=list(TRANSPORTS),
                       help="Override the profile's default transport")
        p.add_argument("--dry-run", action="store_true",
                       help="Print the file/patch plan without writing")
        if with_arbitration:
            p.add_argument("--arbitration", choices=list(ARBITRATION), default="leader",
                           help="Party-choice arbitration mode (default leader — works with the unmodified book; vote/dm-confirm need an MP-aware book hook)")

    sub.add_parser("list", help="List profiles, transports, and the emit plan")

    p = sub.add_parser("plan", help="Print the file plan a profile would emit (dry run)")
    p.add_argument("--profile", choices=list(PROFILES),
                   help="Include this profile's added files (omit for shared core only)")

    p = sub.add_parser("inject", help="Copy the addon, register autoloads, patch project.godot")
    p.add_argument("--profile", required=True, choices=list(PROFILES))
    add_project(p, with_arbitration=True)

    p = sub.add_parser("all", help="Alias for inject (shared core + one profile)")
    p.add_argument("--profile", required=True, choices=list(PROFILES))
    add_project(p, with_arbitration=True)

    p = sub.add_parser("authority-turn", help="Inject the authority-turn profile (SessionState + DM seat)")
    add_project(p, with_arbitration=True)

    p = sub.add_parser("realtime", help="Inject the realtime profile (spawn/sync avatars)")
    add_project(p)

    p = sub.add_parser("session", help="Shared core only (Net autoload)")
    add_project(p)

    p = sub.add_parser("lobby", help="Ensure the lobby files + Net autoload are present")
    add_project(p)

    return parser


DISPATCH = {
    "list": cmd_list,
    "plan": cmd_plan,
    "inject": cmd_inject,
    "all": cmd_inject,
    "authority-turn": cmd_authority_turn,
    "realtime": cmd_realtime,
    "session": cmd_session,
    "lobby": cmd_lobby,
}


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return DISPATCH[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
