#!/usr/bin/env python3
"""scaffold_unity.py — instantiate a Unity genre template into a new project.

Unity analogue of scaffold.py. Copies the template's skeleton project
(Assets/, Packages/manifest.json, ProjectSettings/), patches the product
name, merges the registry's pinned UPM packages into Packages/manifest.json
(the registry is the source of truth for pins, like vendoredAddons on the
Godot side), then — when a Unity editor is available — runs a batchmode
validation pass and parses the log for compile errors.

Unity may not be installed. That is a first-class case: the scaffold still
completes (a Unity project is plain files; the editor resolves UPM packages
and imports assets on first open) and the tool exits 0 with a clear warning
that validation was skipped.

Usage:
    python scaffold_unity.py <template-id> <target-dir> --name "Game Name"
    python scaffold_unity.py top-down-action-unity C:/games/neon_rat --name "Neon Rat"

Options:
    --registry PATH   registry.json to read (default: templates/registry.json)
    --unity PATH      Unity.exe for validation (default: $UNITY, then `Unity`
                      on PATH, then Unity Hub install dirs, then the Hub CLI)
    --no-validate     skip the batchmode validation even if Unity is installed
    --force           allow scaffolding into a non-empty directory

Exit codes: 0 ok (including "Unity not installed, validation skipped"),
1 usage/registry error, 2 validation failed, 3 copy/patch error.
"""

from __future__ import annotations

import argparse
import glob as globmod
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vendor_addons  # noqa: E402  (sibling module: load_registry/find_template)

DEFAULT_REGISTRY = Path(__file__).resolve().parent.parent / "registry.json"

UNITY_HUB_EDITOR_GLOBS = [
    "C:/Program Files/Unity/Hub/Editor/*/Editor/Unity.exe",
    "C:/Program Files/Unity *//Editor/Unity.exe",
    os.path.expanduser("~/Unity/Hub/Editor/*/Editor/Unity"),
    "/Applications/Unity/Hub/Editor/*/Unity.app/Contents/MacOS/Unity",
]

UNITY_HUB_CLI = [
    "C:/Program Files/Unity Hub/Unity Hub.exe",
    "/Applications/Unity Hub.app/Contents/MacOS/Unity Hub",
    os.path.expanduser("~/Applications/Unity Hub.AppImage"),
]

# Log lines that mean validation failed (C# compile errors and batchmode aborts).
ERROR_PATTERNS = [
    re.compile(r"error CS\d{4}", re.I),
    re.compile(r"Scripts have compiler errors", re.I),
    re.compile(r"Compilation failed", re.I),
    re.compile(r"executeMethod (class|method) .* (could not be found|does not exist)", re.I),
    re.compile(r"Aborting batchmode due to failure", re.I),
]
LICENSE_PATTERNS = [
    re.compile(r"No valid Unity Editor license", re.I),
    re.compile(r"License is invalid", re.I),
    re.compile(r"Token not found in cache", re.I),
]


def _editor_version_of(project_dir: Path) -> str | None:
    pv = project_dir / "ProjectSettings" / "ProjectVersion.txt"
    if not pv.is_file():
        return None
    m = re.search(r"^m_EditorVersion:\s*(\S+)", pv.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else None


def _hub_cli_editors() -> list[str]:
    """Ask the Unity Hub CLI for installed editors. Best-effort; never fatal."""
    paths: list[str] = []
    for hub in UNITY_HUB_CLI:
        if not Path(hub).is_file():
            continue
        try:
            proc = subprocess.run(
                [hub, "--", "--headless", "editors", "--installed"],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                timeout=30,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        # Lines look like: "6000.0.40f1 , installed at C:\...\Editor\Unity.exe"
        for line in proc.stdout.splitlines():
            m = re.search(r"installed at\s+(.+?)\s*$", line)
            if m and Path(m.group(1)).is_file():
                paths.append(m.group(1))
    return paths


def find_unity(explicit: str | None, wanted_version: str | None) -> str | None:
    """Locate a Unity editor: --unity, $UNITY, PATH, Hub install dirs, Hub CLI.

    Prefers an editor matching the skeleton's ProjectVersion.txt exactly, then
    the same major.minor stream, then the newest install found.
    """
    candidates: list[str] = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("UNITY"):
        candidates.append(os.environ["UNITY"])
    on_path = shutil.which("Unity") or shutil.which("unity")
    if on_path:
        candidates.append(on_path)
    for pattern in UNITY_HUB_EDITOR_GLOBS:
        candidates.extend(sorted(globmod.glob(pattern), reverse=True))
    if not any(Path(c).is_file() for c in candidates if c):
        candidates.extend(_hub_cli_editors())

    existing = [str(Path(c)) for c in candidates if c and Path(c).is_file()]
    if not existing:
        return None
    if wanted_version:
        for cand in existing:
            if wanted_version in cand:
                return cand
        stream = ".".join(wanted_version.split(".")[:2])  # e.g. "6000.0"
        for cand in existing:
            if f"{os.sep}{stream}." in cand or f"/{stream}." in cand:
                return cand
    return existing[0]


def copy_skeleton(skeleton_dir: Path, target_dir: Path, force: bool) -> None:
    if not skeleton_dir.is_dir():
        sys.exit(f"[scaffold-unity] skeleton dir missing: {skeleton_dir}")
    if target_dir.exists() and any(target_dir.iterdir()) and not force:
        sys.exit(f"[scaffold-unity] target dir is not empty: {target_dir} (use --force)")
    target_dir.mkdir(parents=True, exist_ok=True)
    shutil.copytree(skeleton_dir, target_dir, dirs_exist_ok=True)
    print(f"[scaffold-unity] copied skeleton -> {target_dir}")


def patch_product_name(project_dir: Path, name: str) -> None:
    settings = project_dir / "ProjectSettings" / "ProjectSettings.asset"
    if not settings.is_file():
        sys.exit(f"[scaffold-unity] skeleton has no ProjectSettings.asset: {settings}")
    text = settings.read_text(encoding="utf-8")
    new_text, count = re.subn(
        r"^(\s*productName:).*$", rf"\g<1> {name}", text, count=1, flags=re.M
    )
    if count == 0:
        sys.exit("[scaffold-unity] could not find productName: in ProjectSettings.asset")
    settings.write_text(new_text, encoding="utf-8", newline="\n")
    print(f'[scaffold-unity] productName set to "{name}"')


def merge_upm_packages(project_dir: Path, upm_packages: list[dict]) -> None:
    """Merge the registry's pinned UPM packages into Packages/manifest.json.

    The registry pin wins over whatever the skeleton shipped, so re-pinning a
    package is a one-line registry edit (mirrors vendoredAddons discipline).
    """
    manifest_path = project_dir / "Packages" / "manifest.json"
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            sys.exit(f"[scaffold-unity] manifest.json is not valid JSON: {exc}")
    else:
        manifest = {}
    deps = manifest.setdefault("dependencies", {})
    changed = 0
    for pkg in upm_packages or []:
        name, version = pkg["name"], pkg["version"]
        if deps.get(name) != version:
            deps[name] = version
            changed += 1
    if changed:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n"
        )
    print(f"[scaffold-unity] manifest.json: {len(upm_packages or [])} pinned "
          f"package(s), {changed} updated from registry")


def validate_batchmode(unity: str, project_dir: Path,
                       execute_method: str | None) -> int:
    """Run Unity batchmode against the scaffolded project and parse the log.

    Returns 0 on a clean run, 2 on compile errors / batchmode failure.
    The first run resolves UPM packages and imports everything — minutes, not
    seconds. With an executeMethod (e.g. the NoxBootstrap scene builder) the
    run also proves the editor scripts actually execute, not just compile.
    """
    log_path = project_dir / "Logs" / "noxdev_validate.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [unity, "-batchmode", "-quit", "-nographics",
           "-projectPath", str(project_dir), "-logFile", str(log_path)]
    if execute_method:
        cmd += ["-executeMethod", execute_method]
    print(f"[scaffold-unity] batchmode validation with {unity} ...")
    print(f"[scaffold-unity]   (first import resolves packages — this takes a few minutes)")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=1800)
    except subprocess.TimeoutExpired:
        print("[scaffold-unity] VALIDATION FAILED: batchmode timed out after 30 min",
              file=sys.stderr)
        return 2

    log_text = log_path.read_text(encoding="utf-8", errors="replace") \
        if log_path.is_file() else ""
    log_lines = log_text.splitlines()

    license_hits = [ln for ln in log_lines
                    if any(p.search(ln) for p in LICENSE_PATTERNS)]
    error_hits = [ln for ln in log_lines
                  if any(p.search(ln) for p in ERROR_PATTERNS)]

    if license_hits and proc.returncode != 0:
        print("[scaffold-unity] VALIDATION SKIPPED: Unity editor found but not "
              "licensed for batchmode:", file=sys.stderr)
        for ln in license_hits[:5]:
            print(f"    {ln.strip()}", file=sys.stderr)
        print("[scaffold-unity] sign in via Unity Hub, then re-run validation.",
              file=sys.stderr)
        return 0  # scaffold itself is fine; honesty over false failure

    if proc.returncode != 0 or error_hits:
        print(f"[scaffold-unity] VALIDATION FAILED (exit {proc.returncode}), "
              f"log: {log_path}", file=sys.stderr)
        for ln in error_hits[:20] or log_lines[-20:]:
            print(f"    {ln.strip()}", file=sys.stderr)
        return 2

    print(f"[scaffold-unity] validation ok — batchmode compile clean"
          + (f", {execute_method} ran" if execute_method else "")
          + f" (log: {log_path})")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("template", help="template id, e.g. top-down-action-unity")
    ap.add_argument("target", type=Path, help="directory to create the project in")
    ap.add_argument("--name", required=True, help='game name, e.g. "Neon Rat"')
    ap.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    ap.add_argument("--unity", help="Unity.exe for batchmode validation")
    ap.add_argument("--no-validate", action="store_true",
                    help="skip batchmode validation")
    ap.add_argument("--force", action="store_true",
                    help="scaffold into a non-empty directory")
    args = ap.parse_args(argv)

    registry = vendor_addons.load_registry(args.registry)
    template = vendor_addons.find_template(registry, args.template)
    if template.get("engine") != "unity":
        sys.exit(f"[scaffold-unity] template '{args.template}' has "
                 f"engine={template.get('engine')!r} — use scaffold.py for Godot "
                 f"templates")

    registry_dir = args.registry.resolve().parent
    skeleton_dir = registry_dir / template["skeleton"]
    target_dir = args.target.resolve()

    copy_skeleton(skeleton_dir, target_dir, force=args.force)
    patch_product_name(target_dir, args.name)
    merge_upm_packages(target_dir, template.get("upmPackages", []))

    rc = 0
    if args.no_validate:
        print("[scaffold-unity] --no-validate: skipping batchmode validation")
    else:
        unity = find_unity(args.unity, _editor_version_of(target_dir))
        if unity is None:
            print("[scaffold-unity] WARNING: Unity not installed — scaffold "
                  "complete, validation skipped. Install a Unity 6000.0.x LTS "
                  "editor via Unity Hub (or pass --unity / set $UNITY) and open "
                  "the project; the first import resolves UPM packages and the "
                  "NoxBootstrap editor script builds the demo scene.")
        else:
            rc = validate_batchmode(unity, target_dir,
                                    template.get("validateMethod"))

    engine = f"{template.get('engine')} {template.get('engineVersion', '')}".strip()
    doc = registry_dir / template.get("doc", "")
    print()
    print(f"[scaffold-unity] '{template['name']}' scaffolded at {target_dir}")
    print(f"[scaffold-unity] engine pin: {engine}")
    if doc.is_file():
        print(f"[scaffold-unity] template guide: {doc}")
    print("[scaffold-unity] next steps:")
    print(f"    open the project in Unity Hub (add {target_dir})")
    print("    first import builds Assets/Scenes/Main.unity via NoxDev > Rebuild Demo Scene")
    return rc


if __name__ == "__main__":
    sys.exit(main())
