#!/usr/bin/env python3
"""scaffold.py — instantiate a genre template into a new Godot project.

Copies the template's skeleton project, vendors its pinned addons (via
vendor_addons.py), runs the bootstrap import, enables the addon plugins, and
patches the project name.

The bootstrap import runs BEFORE plugins are enabled on purpose: editor
plugins that load before the first asset import / UID cache exist (Popochiu,
MetSys, most non-trivial addons) spew bogus load errors. Import first, enable
after — same order a human follows — and every subsequent import/run is clean.

Usage:
    python scaffold.py <genre-id> <target-dir> --name "Game Name"
    python scaffold.py metroidvania C:/games/hollow_dark --name "Hollow Dark"
    python scaffold.py point-and-click ./day-of-the-burrito --name "Day of the Burrito"

Options:
    --registry PATH   registry.json to read (default: templates/registry.json)
    --godot PATH      godot executable for the bootstrap import (default: $GODOT,
                      then `godot` on PATH, then common install dirs)
    --no-vendor       copy the skeleton only; skip addon vendoring
    --no-import       skip the bootstrap import (plugins are enabled immediately;
                      the FIRST editor import will show one-time bootstrap noise)
    --force           allow scaffolding into a non-empty directory

Exit codes: 0 ok, 1 usage/registry error, 2 vendoring/import error, 3 copy/patch error.
"""

from __future__ import annotations

import argparse
import glob as globmod
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vendor_addons  # noqa: E402  (sibling module)

DEFAULT_REGISTRY = Path(__file__).resolve().parent.parent / "registry.json"

GODOT_SEARCH_GLOBS = [
    "C:/godot/Godot_v*console.exe",
    "C:/godot/Godot*console.exe",
    "C:/godot/Godot.exe",
    "C:/godot*/Godot.exe",
    os.path.expanduser("~/godot/Godot*.exe"),
]


def find_godot(explicit: str | None) -> str | None:
    """Locate a Godot executable: --godot, $GODOT, PATH, then common dirs."""
    candidates: list[str] = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("GODOT"):
        candidates.append(os.environ["GODOT"])
    on_path = shutil.which("godot")
    if on_path:
        candidates.append(on_path)
    for pattern in GODOT_SEARCH_GLOBS:
        candidates.extend(sorted(globmod.glob(pattern), reverse=True))
    for cand in candidates:
        if cand and Path(cand).is_file():
            return str(Path(cand))
    return None


def bootstrap_import(godot: str, project_dir: Path) -> None:
    """Run the first headless import (addons copied, plugins not yet enabled)."""
    print(f"[scaffold] bootstrap import with {godot} ...")
    proc = subprocess.run(
        [godot, "--headless", "--path", str(project_dir), "--import"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=600,
    )
    if proc.returncode != 0:
        # Some GDExtensions (e.g. TimeTick 1.1 on Godot 4.6.1) crash Godot's
        # shutdown path on the very first import — AFTER the import itself has
        # fully completed and written a valid cache. Verify with a second
        # import: a clean exit means the project is fine and we proceed.
        retry = subprocess.run(
            [godot, "--headless", "--path", str(project_dir), "--import"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=600,
        )
        if retry.returncode == 0:
            print(f"[scaffold] bootstrap import crashed on exit (exit {proc.returncode}) "
                  "but the verification import is clean — continuing (known "
                  "GDExtension first-import shutdown quirk)")
            return
        tail = "\n".join((proc.stdout + proc.stderr).splitlines()[-25:])
        sys.exit(f"[scaffold] bootstrap import failed (exit {proc.returncode}):\n{tail}")
    print("[scaffold] bootstrap import ok")


def copy_skeleton(skeleton_dir: Path, target_dir: Path, force: bool) -> None:
    if not skeleton_dir.is_dir():
        sys.exit(f"[scaffold] skeleton dir missing: {skeleton_dir}")
    if target_dir.exists() and any(target_dir.iterdir()) and not force:
        sys.exit(f"[scaffold] target dir is not empty: {target_dir} (use --force)")
    target_dir.mkdir(parents=True, exist_ok=True)
    shutil.copytree(skeleton_dir, target_dir, dirs_exist_ok=True)
    print(f"[scaffold] copied skeleton -> {target_dir}")


def patch_project_name(project_dir: Path, name: str) -> None:
    project_godot = project_dir / "project.godot"
    if not project_godot.is_file():
        sys.exit(f"[scaffold] skeleton has no project.godot: {project_godot}")
    escaped = name.replace("\\", "\\\\").replace('"', '\\"')
    text = project_godot.read_text(encoding="utf-8")
    new_text, count = re.subn(
        r'^config/name=".*"$', f'config/name="{escaped}"', text, count=1, flags=re.M
    )
    if count == 0:
        sys.exit("[scaffold] could not find config/name= line in project.godot")
    project_godot.write_text(new_text, encoding="utf-8", newline="\n")
    print(f'[scaffold] project name set to "{name}"')


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("genre", help="template id from the registry, e.g. metroidvania")
    ap.add_argument("target", type=Path, help="directory to create the project in")
    ap.add_argument("--name", required=True, help='game name, e.g. "Hollow Dark"')
    ap.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    ap.add_argument("--godot", help="godot executable for the bootstrap import")
    ap.add_argument("--no-vendor", action="store_true", help="skip addon vendoring")
    ap.add_argument("--no-import", action="store_true",
                    help="skip the bootstrap import step")
    ap.add_argument("--force", action="store_true",
                    help="scaffold into a non-empty directory / replace addons")
    args = ap.parse_args(argv)

    registry = vendor_addons.load_registry(args.registry)
    template = vendor_addons.find_template(registry, args.genre)

    registry_dir = args.registry.resolve().parent
    skeleton_dir = registry_dir / template["skeleton"]
    target_dir = args.target.resolve()

    copy_skeleton(skeleton_dir, target_dir, force=args.force)
    patch_project_name(target_dir, args.name)

    if args.no_vendor:
        print("[scaffold] --no-vendor: skipping addon vendoring")
    else:
        godot = None if args.no_import else find_godot(args.godot)
        defer = godot is not None
        records = vendor_addons.vendor_template(
            template, target_dir, force=args.force, defer_enable=defer
        )
        pending = [p for r in records for p in (r.get("enable") or [])]
        if defer:
            bootstrap_import(godot, target_dir)
            if pending:
                vendor_addons.enable_plugins(target_dir / "project.godot", pending)
                print(f"[scaffold] enabled {len(pending)} plugin(s) after bootstrap import")
        elif pending and not args.no_import:
            # No godot found: vendor_template enabled the plugins immediately.
            print("[scaffold] WARNING: no godot executable found — plugins enabled "
                  "without a bootstrap import; the first editor import will show "
                  "one-time addon bootstrap noise. Set $GODOT or pass --godot to fix.")

    engine = f"{template.get('engine', 'godot')} {template.get('engineVersion', '')}".strip()
    doc = registry_dir / template.get("doc", "")
    print()
    print(f"[scaffold] '{template['name']}' scaffolded at {target_dir}")
    print(f"[scaffold] engine pin: {engine}")
    if doc.is_file():
        print(f"[scaffold] template guide: {doc}")
    print("[scaffold] next steps:")
    print(f"    godot --headless --path \"{target_dir}\" --import   # first import")
    print(f"    godot --path \"{target_dir}\"                        # open the editor")
    return 0


if __name__ == "__main__":
    sys.exit(main())
