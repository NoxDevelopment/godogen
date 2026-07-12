#!/usr/bin/env python3
"""vendor_addons.py — vendor pinned third-party Godot addons into a project.

Reads a template entry from the genre-template registry (templates/registry.json),
git-clones each vendored addon at its pinned ref/commit, copies only the addon
payload into the target project's addons/ folder, enables editor plugins in
project.godot, and writes addons/LICENSES.md.

Handles plugin-addons (payload contains plugin.cfg -> enabled in
[editor_plugins]), script-only kits (payload copied verbatim, nothing to
enable), and — for kits distributed as prebuilt release archives instead of
git checkouts (GDExtension binaries: TimeTick, godot_voxel) — sha256-pinned
zip downloads via an `archive` entry: {"url": ..., "sha256": ...}. A hash
mismatch hard-fails vendoring, which is the archive analogue of a moved
commit pin.

Usage:
    python vendor_addons.py --template metroidvania --project C:/path/to/game
    python vendor_addons.py --template point-and-click --project ./game --force

Exit codes: 0 ok, 1 usage / registry error, 2 git/download error, 3 copy/patch error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from datetime import date
from pathlib import Path

DEFAULT_REGISTRY = Path(__file__).resolve().parent.parent / "registry.json"
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")

# ---------------------------------------------------------------------------
# registry
# ---------------------------------------------------------------------------


def load_registry(path: Path) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        sys.exit(f"[vendor] registry not found: {path}")
    except json.JSONDecodeError as exc:
        sys.exit(f"[vendor] registry is not valid JSON: {path}: {exc}")


def find_template(registry: dict, template_id: str) -> dict:
    for entry in registry.get("templates", []):
        if entry.get("id") == template_id:
            return entry
    known = ", ".join(t.get("id", "?") for t in registry.get("templates", []))
    sys.exit(f"[vendor] unknown template id '{template_id}' (known: {known})")


# ---------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------


def _git(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    """Run git with long-path support (required for deep addon trees on Windows)."""
    cmd = ["git", "-c", "core.longpaths=true", *args]
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace"
    )


def clone_pinned(repo: str, ref: str | None, commit: str | None, dest: Path) -> str:
    """Clone `repo` at the pinned ref/commit into `dest`. Returns checked-out SHA.

    Strategy:
    1. If a commit SHA is pinned, fetch exactly that commit (shallow) — works on
       GitHub/GitLab which allow fetching reachable SHAs.
    2. Otherwise (or as fallback) shallow-clone the branch/tag `ref`, then verify
       HEAD matches `commit` when both are given.
    """
    dest.mkdir(parents=True, exist_ok=True)

    if commit and SHA_RE.match(commit):
        res = _git(["init", "-q", str(dest)])
        if res.returncode == 0:
            _git(["remote", "add", "origin", repo], cwd=dest)
            res = _git(["fetch", "-q", "--depth", "1", "origin", commit], cwd=dest)
            if res.returncode == 0:
                res = _git(["checkout", "-q", "--detach", "FETCH_HEAD"], cwd=dest)
                if res.returncode == 0:
                    return _head_sha(dest)
            # Fall through to branch/tag clone below.
            print(f"[vendor]   direct SHA fetch failed ({res.stderr.strip() or 'unknown'}); "
                  f"falling back to ref clone", file=sys.stderr)
            _rmtree(dest)
            dest.mkdir(parents=True, exist_ok=True)

    if not ref:
        sys.exit(f"[vendor] addon {repo}: no ref and SHA fetch failed — cannot pin")

    res = _git(["clone", "-q", "--depth", "1", "--branch", ref, repo, str(dest)])
    if res.returncode != 0:
        sys.exit(f"[vendor] git clone failed for {repo}@{ref}:\n{res.stderr}")

    head = _head_sha(dest)
    if commit and not head.startswith(commit) and not commit.startswith(head):
        # Branch moved past the pin — deepen and check out the pinned commit.
        res = _git(["fetch", "-q", "--depth", "200", "origin", ref], cwd=dest)
        res = _git(["checkout", "-q", "--detach", commit], cwd=dest)
        if res.returncode != 0:
            sys.exit(
                f"[vendor] {repo}: branch '{ref}' is at {head[:12]}, pinned commit "
                f"{commit[:12]} not reachable in shallow history:\n{res.stderr}"
            )
        head = _head_sha(dest)
    return head


def fetch_archive(url: str, sha256: str, work_dir: Path) -> Path:
    """Download a pinned release archive, verify its sha256, extract it.

    Returns the extraction root (the archive analogue of a git clone dir).
    """
    work_dir.mkdir(parents=True, exist_ok=True)
    zip_path = work_dir / "archive.zip"
    try:
        with urllib.request.urlopen(url, timeout=300) as resp, open(zip_path, "wb") as fh:
            shutil.copyfileobj(resp, fh)
    except OSError as exc:
        sys.exit(f"[vendor] archive download failed for {url}: {exc}")

    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    if digest != sha256.lower():
        sys.exit(
            f"[vendor] archive sha256 mismatch for {url}:\n"
            f"  expected {sha256}\n  got      {digest}\n"
            f"(upstream re-published the asset? re-verify the pin)"
        )

    extract_dir = work_dir / "x"
    try:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(extract_dir)
    except zipfile.BadZipFile as exc:
        sys.exit(f"[vendor] archive is not a valid zip: {url}: {exc}")
    return extract_dir


def _head_sha(repo_dir: Path) -> str:
    res = _git(["rev-parse", "HEAD"], cwd=repo_dir)
    if res.returncode != 0:
        sys.exit(f"[vendor] rev-parse failed in {repo_dir}:\n{res.stderr}")
    return res.stdout.strip()


def _rmtree(path: Path) -> None:
    """shutil.rmtree that also clears read-only bits (git object files on Windows)."""

    def _onerror(func, p, _exc):
        try:
            Path(p).chmod(stat.S_IWRITE)
            func(p)
        except OSError:
            pass

    if path.exists():
        shutil.rmtree(path, onerror=_onerror)


# ---------------------------------------------------------------------------
# copy + license
# ---------------------------------------------------------------------------


def copy_payload(clone_dir: Path, payload: str, project_dir: Path, target_dir: str,
                 force: bool) -> Path:
    src = (clone_dir / payload).resolve() if payload not in ("", ".") else clone_dir
    if not src.is_dir():
        sys.exit(f"[vendor] payload dir not found in clone: {payload}")

    dst = project_dir / target_dir
    if dst.exists():
        if not force:
            sys.exit(f"[vendor] target already exists: {dst} (use --force to replace)")
        _rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns(".git", ".github", ".gitignore"))
    return dst


def copy_license(clone_dir: Path, license_file: str | None, addon_dst: Path) -> str | None:
    """Copy the addon's license file into the vendored dir. Returns dest filename."""
    candidates = [license_file] if license_file else []
    candidates += ["LICENSE", "LICENSE.txt", "LICENSE.md", "LICENCE", "COPYING"]
    for cand in candidates:
        if not cand:
            continue
        src = clone_dir / cand
        if src.is_file():
            dst = addon_dst / Path(cand).name
            if not dst.exists():  # payload may already ship its own copy
                shutil.copy2(src, dst)
            return Path(cand).name
    print(f"[vendor]   WARNING: no license file found in {clone_dir}", file=sys.stderr)
    return None


# ---------------------------------------------------------------------------
# project.godot patching
# ---------------------------------------------------------------------------


def apply_patches(addon_dst: Path, patches: list[dict], addon_name: str) -> None:
    """Apply small pinned find/replace patches to the vendored copy.

    Each patch: {"file": rel path in payload, "find": str, "replace": str,
    "reason": str}. A missing needle means the pin changed under us — hard fail
    so the pin and the patch get re-verified together.
    """
    for patch in patches:
        target = addon_dst / patch["file"]
        if not target.is_file():
            sys.exit(f"[vendor] {addon_name}: patch target missing: {target}")
        text = target.read_text(encoding="utf-8")
        needle = patch["find"]
        if needle not in text:
            sys.exit(
                f"[vendor] {addon_name}: patch needle not found in {patch['file']} "
                f"(upstream changed? re-verify the pin): {needle[:80]!r}"
            )
        text = text.replace(needle, patch["replace"], 1)
        target.write_text(text, encoding="utf-8", newline="\n")
        print(f"[vendor] {addon_name}: patched {patch['file']} "
              f"({patch.get('reason', 'no reason given')})")


def find_plugin_cfgs(addon_dst: Path, project_dir: Path) -> list[str]:
    """All plugin.cfg files inside the vendored addon, as res:// paths."""
    cfgs = []
    for cfg in sorted(addon_dst.rglob("plugin.cfg")):
        rel = cfg.relative_to(project_dir).as_posix()
        cfgs.append(f"res://{rel}")
    return cfgs


def enable_plugins(project_godot: Path, plugin_paths: list[str]) -> None:
    """Merge plugin.cfg res:// paths into [editor_plugins] enabled=PackedStringArray(...)."""
    if not plugin_paths:
        return
    if not project_godot.is_file():
        sys.exit(f"[vendor] project.godot not found: {project_godot}")

    text = project_godot.read_text(encoding="utf-8")
    existing: list[str] = []
    m = re.search(r'^\[editor_plugins\]\s*$(.*?)(?=^\[|\Z)', text, re.M | re.S)
    if m:
        em = re.search(r'enabled\s*=\s*PackedStringArray\((.*?)\)', m.group(1), re.S)
        if em:
            existing = re.findall(r'"((?:[^"\\]|\\.)*)"', em.group(1))

    merged = existing + [p for p in plugin_paths if p not in existing]
    array = "PackedStringArray(" + ", ".join(f'"{p}"' for p in merged) + ")"

    if m and re.search(r'enabled\s*=\s*PackedStringArray\(', m.group(1), re.S):
        # Replace the existing enabled= line inside the section.
        section = m.group(0)
        new_section = re.sub(
            r'enabled\s*=\s*PackedStringArray\(.*?\)', f"enabled={array}", section, flags=re.S
        )
        text = text.replace(section, new_section)
    elif m:
        insert_at = m.end(0)
        text = text[:m.start(1)] + f"\nenabled={array}\n" + text[m.end(1):]
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += f"\n[editor_plugins]\n\nenabled={array}\n"

    project_godot.write_text(text, encoding="utf-8", newline="\n")


# ---------------------------------------------------------------------------
# LICENSES.md
# ---------------------------------------------------------------------------


def write_licenses_md(project_dir: Path, records: list[dict]) -> Path:
    addons_dir = project_dir / "addons"
    addons_dir.mkdir(exist_ok=True)
    out = addons_dir / "LICENSES.md"
    lines = [
        "# Vendored Addon Licenses",
        "",
        f"Generated by `templates/tools/vendor_addons.py` on {date.today().isoformat()}.",
        "Do not edit by hand — regenerate by re-running the vendoring tool.",
        "",
        "| Addon | Version | Pinned commit | License | Source |",
        "|-------|---------|---------------|---------|--------|",
    ]
    for r in records:
        lines.append(
            f"| {r['name']} | {r.get('version', '-')} | `{r['sha'][:12]}` "
            f"| {r.get('license', '?')} | {r['repo']} |"
        )
    lines.append("")
    for r in records:
        lic = r.get("license_dest")
        loc = f"`{r['target_dir']}/{lic}`" if lic else "(license file missing from upstream!)"
        lines.append(f"- **{r['name']}** — full license text: {loc}")
    lines.append("")
    out.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return out


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def vendor_template(template: dict, project_dir: Path, force: bool = False,
                    defer_enable: bool = False) -> list[dict]:
    """Vendor all addons of one registry template entry into project_dir.

    With defer_enable=True, plugins are NOT enabled in project.godot; each
    returned record carries its `enable` list instead. Callers use this to run
    a bootstrap `godot --headless --import` first (editor plugins that load
    before the initial asset import / UID cache exist produce bogus errors),
    then call enable_plugins() themselves.
    """
    addons = template.get("vendoredAddons", [])
    if not addons:
        print(f"[vendor] template '{template['id']}' has no vendored addons — nothing to do")
        return []

    project_godot = project_dir / "project.godot"
    records: list[dict] = []
    tmp_root = Path(tempfile.mkdtemp(prefix="gdvnd_"))
    try:
        for i, addon in enumerate(addons):
            name = addon["name"]
            archive = addon.get("archive")
            if archive:
                url = archive["url"]
                print(f"[vendor] {name}: downloading {url} ...")
                clone_dir = fetch_archive(url, archive["sha256"], tmp_root / f"a{i}")
                sha = archive["sha256"]
                repo = addon.get("repo", url)
                print(f"[vendor] {name}: archive verified sha256:{sha[:12]}")
            else:
                repo = addon["repo"]
                ref = addon.get("ref")
                commit = addon.get("commit")
                print(f"[vendor] {name}: cloning {repo} @ {ref or commit} ...")
                clone_dir = tmp_root / f"a{i}"
                sha = clone_pinned(repo, ref, commit, clone_dir)
                print(f"[vendor] {name}: checked out {sha[:12]}")

            dst = copy_payload(
                clone_dir, addon.get("payload", "."), project_dir, addon["targetDir"], force
            )
            lic_dest = copy_license(clone_dir, addon.get("licenseFile"), dst)

            if addon.get("patches"):
                apply_patches(dst, addon["patches"], name)

            enable = addon.get("enablePlugins")
            if enable is None:  # not specified -> auto-detect
                enable = find_plugin_cfgs(dst, project_dir)
            if enable and not defer_enable:
                enable_plugins(project_godot, enable)
                print(f"[vendor] {name}: enabled {len(enable)} plugin(s) in project.godot")
            elif enable:
                print(f"[vendor] {name}: {len(enable)} plugin(s) pending enable (deferred)")
            else:
                print(f"[vendor] {name}: script-only kit (no plugin.cfg) — copied only")

            records.append({
                "name": name,
                "repo": repo,
                "version": addon.get("version", addon.get("ref", "")),
                "sha": sha,
                "license": addon.get("license", "?"),
                "license_dest": lic_dest,
                "target_dir": addon["targetDir"],
                "enable": enable,
            })
    finally:
        _rmtree(tmp_root)

    out = write_licenses_md(project_dir, records)
    print(f"[vendor] wrote {out}")
    return records


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY,
                    help=f"registry.json path (default: {DEFAULT_REGISTRY})")
    ap.add_argument("--template", required=True, help="template id, e.g. metroidvania")
    ap.add_argument("--project", required=True, type=Path,
                    help="target Godot project dir (contains project.godot)")
    ap.add_argument("--force", action="store_true",
                    help="replace addon dirs that already exist")
    args = ap.parse_args(argv)

    registry = load_registry(args.registry)
    template = find_template(registry, args.template)
    project_dir = args.project.resolve()
    if not (project_dir / "project.godot").is_file():
        sys.exit(f"[vendor] {project_dir} does not look like a Godot project "
                 f"(no project.godot)")

    vendor_template(template, project_dir, force=args.force)
    print("[vendor] done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
