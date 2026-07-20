"""Asset Manifest — durable index of every generated asset in a project.

A single assets/manifest.json tracks asset_id, sha12, source provider, params,
labels, and references for every generated asset. Composes with the rest of
the godogen asset-generation pipeline (image-pipeline, character-sheet,
scene-art, animation-pipeline, 3d-asset-pipeline, audio-pipeline).

Subcommands
-----------
init     Initialize an empty manifest.json.
add      Record a generated asset (path + kind + provider + labels + params).
find     Query by labels / kind / provider / references-id.
list     Counts grouped by provider / kind / labels.
verify   Cross-check manifest vs files on disk (missing / modified / untracked).
prune    Remove manifest entries for missing files.
export   Emit a flat lookup table (Godot .gd / Unity JSON / flat JSON).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any

MANIFEST_VERSION = 1

KIND_CHOICES = [
    "sprite", "character", "portrait", "tile", "tileset", "parallax",
    "skybox", "environment", "ui", "icon", "mesh3d", "texture",
    "animation_frame", "spritesheet", "audio_sfx", "audio_music",
    "audio_voice", "reference", "other",
]

CONVENTIONAL_PROVIDERS = [
    "image-pipeline.zit", "image-pipeline.sdxl",
    "character-sheet.zit",
    "3d-asset-pipeline.tripo3d",
    "scene-art.zit", "animation-pipeline.zit",
    "audio-pipeline.sfx", "audio-pipeline.music", "audio-pipeline.speech",
    # "external.<vendor>" — anything else (manual, MCP-based providers, etc.)
]


# ---------------------------------------------------------------------------
# IO helpers
# ---------------------------------------------------------------------------

def _utc_now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _sha12(file_path: Path) -> str:
    h = hashlib.sha256()
    with file_path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()[:12]


def _load_manifest(path: Path) -> dict:
    if not path.exists():
        raise SystemExit(f"manifest not found: {path}. Run 'init' first.")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise SystemExit(f"manifest JSON parse error in {path}: {e}")


def _save_manifest(path: Path, manifest: dict) -> None:
    manifest["updated"] = _utc_now_iso()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def _slug(label: str) -> str:
    out = []
    for ch in label.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in (" ", "-", "_"):
            out.append("_")
    s = "".join(out).strip("_")
    while "__" in s:
        s = s.replace("__", "_")
    return s


def _make_asset_id(kind: str, labels: list[str], sha12: str) -> str:
    label_part = "_".join(_slug(l) for l in labels if l) or "unlabeled"
    return f"{kind}_{label_part}_{sha12[:8]}"


def _rel_to_root(path: Path, root: Path) -> str:
    """Return path expressed as posix relative-to-root if possible, else absolute posix."""
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_init(args) -> None:
    manifest_path = Path(args.manifest)
    if manifest_path.exists() and not args.force:
        existing = _load_manifest(manifest_path)
        raise SystemExit(
            f"manifest already exists ({manifest_path}) with "
            f"{len(existing.get('assets', []))} entries. Pass --force to overwrite."
        )
    root = Path(args.root)
    root.mkdir(parents=True, exist_ok=True)
    manifest = {
        "version": MANIFEST_VERSION,
        "created": _utc_now_iso(),
        "updated": _utc_now_iso(),
        "root": root.as_posix() if not root.is_absolute() else root.resolve().as_posix(),
        "assets": [],
    }
    _save_manifest(manifest_path, manifest)
    print(json.dumps({"ok": True, "manifest": str(manifest_path),
                      "root": manifest["root"]}, indent=2))


def cmd_add(args) -> None:
    manifest_path = Path(args.manifest)
    manifest = _load_manifest(manifest_path)
    root = Path(manifest["root"])

    asset_path = Path(args.path)
    if not asset_path.exists():
        raise SystemExit(f"asset file does not exist: {asset_path}")
    if not asset_path.is_file():
        raise SystemExit(f"asset path is not a file: {asset_path}")

    sha = _sha12(asset_path)
    labels = [l.strip() for l in (args.labels or "").split(",") if l.strip()]

    # Dedupe by SHA — if we've seen these bytes before, return the existing id.
    for entry in manifest["assets"]:
        if entry.get("sha12") == sha:
            print(json.dumps({
                "ok": True, "asset_id": entry["asset_id"], "duplicate": True,
                "existing_path": entry["path"], "sha12": sha,
            }, indent=2))
            return

    params: dict[str, Any] = {}
    for p in (args.param or []):
        if "=" not in p:
            raise SystemExit(f"--param {p!r} must be key=value")
        k, v = p.split("=", 1)
        # Try to coerce numerics for nicer downstream queries
        if v.isdigit():
            params[k] = int(v)
        else:
            try:
                params[k] = float(v)
            except ValueError:
                params[k] = v

    rel_path = _rel_to_root(asset_path, root)
    asset_id = _make_asset_id(args.kind, labels, sha)

    references = [r.strip() for r in (args.references or "").split(",") if r.strip()]
    # Validate references actually exist in the manifest
    known_ids = {e["asset_id"] for e in manifest["assets"]}
    bad_refs = [r for r in references if r not in known_ids]
    if bad_refs:
        raise SystemExit(f"--references contains unknown asset_ids: {bad_refs}")

    entry = {
        "asset_id": asset_id,
        "sha12": sha,
        "path": rel_path,
        "kind": args.kind,
        "provider": args.provider,
        "labels": labels,
        "params": params,
        "references": references,
        # First-class provenance for the credits screen (STANDARDS "credits").
        # license is the SPDX-ish tag (CC0-1.0, OFL-1.1, CC-BY-4.0, proprietary, ...).
        "license": (args.license or "").strip(),
        "source": (args.source or "").strip(),   # kit/pack/dataset the asset came from
        "author": (args.author or "").strip(),    # creator to attribute (CC-BY etc.)
        "url": (args.url or "").strip(),           # where it was obtained
        "created": _utc_now_iso(),
    }
    manifest["assets"].append(entry)
    _save_manifest(manifest_path, manifest)
    print(json.dumps({"ok": True, "asset_id": asset_id, "sha12": sha,
                      "path": rel_path}, indent=2))


def _filter_entries(entries: list[dict], args) -> list[dict]:
    filtered = entries
    if args.kind:
        filtered = [e for e in filtered if e.get("kind") == args.kind]
    if args.provider:
        # Substring match — `--provider spritecook` matches `spritecook.gemini-3.1-flash`
        filtered = [e for e in filtered if args.provider in e.get("provider", "")]
    if args.labels:
        wanted = {l.strip() for l in args.labels.split(",") if l.strip()}
        filtered = [e for e in filtered if wanted.issubset(set(e.get("labels", [])))]
    if args.references_id:
        filtered = [e for e in filtered if args.references_id in e.get("references", [])]
    if args.sha:
        filtered = [e for e in filtered if e.get("sha12", "").startswith(args.sha)]
    return filtered


def cmd_find(args) -> None:
    manifest = _load_manifest(Path(args.manifest))
    matches = _filter_entries(manifest["assets"], args)
    print(json.dumps(matches, indent=2))


def cmd_list(args) -> None:
    manifest = _load_manifest(Path(args.manifest))
    entries = manifest["assets"]
    if not entries:
        print(json.dumps({"total": 0, "groups": {}}, indent=2))
        return
    groups: dict[str, int] = {}
    if args.by == "provider":
        for e in entries:
            groups[e.get("provider", "(unknown)")] = groups.get(e.get("provider", "(unknown)"), 0) + 1
    elif args.by == "kind":
        for e in entries:
            groups[e.get("kind", "(unknown)")] = groups.get(e.get("kind", "(unknown)"), 0) + 1
    elif args.by == "labels":
        for e in entries:
            for lbl in e.get("labels", []) or ["(unlabeled)"]:
                groups[lbl] = groups.get(lbl, 0) + 1
    print(json.dumps({"total": len(entries),
                      "by": args.by,
                      "groups": dict(sorted(groups.items(), key=lambda kv: -kv[1]))},
                     indent=2))


def cmd_verify(args) -> None:
    manifest_path = Path(args.manifest)
    manifest = _load_manifest(manifest_path)
    root = Path(manifest["root"])

    missing: list[dict] = []
    modified: list[dict] = []
    ok: int = 0
    tracked_paths: set[Path] = set()
    for entry in manifest["assets"]:
        rel = entry["path"]
        abs_path = root / rel if not Path(rel).is_absolute() else Path(rel)
        tracked_paths.add(abs_path.resolve())
        if not abs_path.exists():
            missing.append({"asset_id": entry["asset_id"], "path": rel})
            continue
        if _sha12(abs_path) != entry.get("sha12"):
            modified.append({"asset_id": entry["asset_id"], "path": rel,
                             "expected_sha": entry["sha12"]})
            continue
        ok += 1

    # Untracked files under root (best-effort: skip dotfiles, manifest itself)
    untracked: list[str] = []
    if root.exists():
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            if p.resolve() == manifest_path.resolve():
                continue
            if any(part.startswith(".") for part in p.relative_to(root).parts):
                continue
            if p.resolve() not in tracked_paths:
                untracked.append(p.relative_to(root).as_posix())

    report = {
        "ok_count": ok, "missing_count": len(missing),
        "modified_count": len(modified), "untracked_count": len(untracked),
        "missing": missing, "modified": modified, "untracked": untracked,
    }
    print(json.dumps(report, indent=2))
    if missing or modified:
        sys.exit(1)


def cmd_prune(args) -> None:
    manifest_path = Path(args.manifest)
    manifest = _load_manifest(manifest_path)
    root = Path(manifest["root"])
    kept: list[dict] = []
    dropped: list[dict] = []
    for entry in manifest["assets"]:
        rel = entry["path"]
        abs_path = root / rel if not Path(rel).is_absolute() else Path(rel)
        if abs_path.exists():
            kept.append(entry)
        else:
            dropped.append({"asset_id": entry["asset_id"], "path": rel})
    if args.dry_run:
        print(json.dumps({"would_drop": dropped, "would_keep": len(kept)}, indent=2))
        return
    manifest["assets"] = kept
    _save_manifest(manifest_path, manifest)
    print(json.dumps({"dropped": dropped, "kept": len(kept)}, indent=2))


def _render_credits(entries: list[dict], args) -> str:
    """Assemble attribution grouped by license → source/author.

    Emits JSON (default, for the `credits` skill to merge with fonts/tools/engine)
    or Markdown. Also surfaces LoRA/style packs (params.lora) and the provider mix
    (the generation tools that produced assets) so nothing goes un-attributed.
    """
    by_license: dict[str, dict[str, dict]] = {}
    loras: set[str] = set()
    providers: set[str] = set()
    unlicensed: list[str] = []
    for e in entries:
        lic = (e.get("license") or "").strip() or "UNSPECIFIED"
        src = (e.get("source") or "").strip() or (e.get("provider") or "generated")
        key = f"{src} {e.get('author', '').strip()} {e.get('url', '').strip()}"
        grp = by_license.setdefault(lic, {})
        item = grp.setdefault(key, {
            "source": src, "author": e.get("author", "").strip(),
            "url": e.get("url", "").strip(), "count": 0,
        })
        item["count"] += 1
        if e.get("provider"):
            providers.add(e["provider"])
        lora = (e.get("params") or {}).get("lora")
        if lora:
            loras.add(str(lora))
        if lic == "UNSPECIFIED":
            unlicensed.append(e.get("asset_id", "?"))

    payload = {
        "generated": _utc_now_iso(),
        "by_license": {
            lic: sorted(grp.values(), key=lambda i: (-i["count"], i["source"]))
            for lic, grp in sorted(by_license.items())
        },
        "loras": sorted(loras),
        "providers": sorted(providers),
        "unlicensed": sorted(set(unlicensed)),
    }
    if args.credits_format == "json":
        return json.dumps(payload, indent=2) + "\n"

    # Markdown
    lines = ["# Credits — assets & attribution", ""]
    if payload["unlicensed"]:
        lines += [f"> ⚠ {len(payload['unlicensed'])} asset(s) have NO license tag — "
                  "fix before ship (`manifest.py add --license …`).", ""]
    for lic, items in payload["by_license"].items():
        lines.append(f"## {lic}")
        for it in items:
            who = f" — {it['author']}" if it["author"] else ""
            url = f" <{it['url']}>" if it["url"] else ""
            lines.append(f"- {it['source']}{who} ({it['count']} asset(s)){url}")
        lines.append("")
    if payload["loras"]:
        lines += ["## Style / LoRA models", *[f"- {l}" for l in payload["loras"]], ""]
    if payload["providers"]:
        lines += ["## Generation tools",
                  *[f"- {p}" for p in payload["providers"]], ""]
    return "\n".join(lines)


def cmd_export(args) -> None:
    manifest = _load_manifest(Path(args.manifest))
    root = Path(manifest["root"])
    entries = manifest["assets"]
    fmt = args.format
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    if fmt == "json":
        flat = {e["asset_id"]: e["path"] for e in entries}
        out.write_text(json.dumps(flat, indent=2), encoding="utf-8")
    elif fmt == "godot":
        lines = [
            "## Auto-generated by asset-manifest skill — DO NOT EDIT.",
            "## Regenerate with: manifest.py export --format godot --output …",
            "class_name AssetRegistry",
            "extends RefCounted",
            "",
        ]
        for e in entries:
            const_name = _slug("_".join([e["kind"]] + (e["labels"] or ["unlabeled"]))).upper()
            res_path = "res://" + e["path"].lstrip("/")
            lines.append(f"## {e.get('provider', '?')} · {', '.join(e.get('labels', []))}")
            lines.append(f"const {const_name} := \"{res_path}\"")
            lines.append("")
        out.write_text("\n".join(lines), encoding="utf-8")
    elif fmt == "unity":
        flat = {e["asset_id"]: e["path"] for e in entries}
        # Unity-friendly: serializable dictionary shape (string -> string).
        out.write_text(json.dumps({"map": flat}, indent=2), encoding="utf-8")
    elif fmt == "credits":
        out.write_text(_render_credits(entries, args), encoding="utf-8")
    else:
        raise SystemExit(f"Unknown --format {fmt!r}")

    print(json.dumps({"ok": True, "format": fmt, "wrote": str(out),
                      "entries": len(entries)}, indent=2))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _add_manifest_arg(p):
    p.add_argument("--manifest", default="assets/manifest.json",
                   help="Manifest path (default assets/manifest.json)")


def main():
    parser = argparse.ArgumentParser(
        description="asset-manifest: durable index of generated assets")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("init", help="Initialize an empty manifest")
    _add_manifest_arg(p)
    p.add_argument("--root", default="assets/", help="Asset root dir (default assets/)")
    p.add_argument("--force", action="store_true", help="Overwrite an existing manifest")
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("add", help="Record a generated asset")
    _add_manifest_arg(p)
    p.add_argument("--path", required=True, help="Path to the asset file")
    p.add_argument("--kind", required=True, choices=KIND_CHOICES)
    p.add_argument("--provider", required=True,
                   help="Provider string, e.g. image-pipeline.zit or spritecook.gemini-3.1-flash")
    p.add_argument("--labels", default="", help="Comma-separated labels")
    p.add_argument("--param", action="append",
                   help="key=value param (repeatable). Numeric values are coerced.")
    p.add_argument("--references", default="",
                   help="Comma-separated asset_ids this asset depends on (e.g. animation frames -> sprite)")
    p.add_argument("--license", default="",
                   help="License tag for the credits screen (CC0-1.0, OFL-1.1, CC-BY-4.0, proprietary, ...)")
    p.add_argument("--source", default="",
                   help="Kit/pack/dataset the asset came from (e.g. 'Kenney UI RPG Expansion')")
    p.add_argument("--author", default="",
                   help="Creator to attribute (required by CC-BY and similar)")
    p.add_argument("--url", default="", help="Where the asset was obtained")
    p.set_defaults(func=cmd_add)

    p = sub.add_parser("find", help="Query the manifest")
    _add_manifest_arg(p)
    p.add_argument("--kind", choices=KIND_CHOICES)
    p.add_argument("--provider", help="Substring match against provider field")
    p.add_argument("--labels", help="Comma-separated labels that must ALL be present")
    p.add_argument("--references-id", help="Find entries referencing this asset_id")
    p.add_argument("--sha", help="Match by sha12 prefix")
    p.set_defaults(func=cmd_find)

    p = sub.add_parser("list", help="Print counts grouped by provider/kind/labels")
    _add_manifest_arg(p)
    p.add_argument("--by", default="provider", choices=["provider", "kind", "labels"])
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("verify", help="Cross-check manifest vs files on disk")
    _add_manifest_arg(p)
    p.set_defaults(func=cmd_verify)

    p = sub.add_parser("prune", help="Drop entries for missing files")
    _add_manifest_arg(p)
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_prune)

    p = sub.add_parser("export", help="Emit a flat lookup table")
    _add_manifest_arg(p)
    p.add_argument("--format", required=True,
                   choices=["godot", "unity", "json", "credits"])
    p.add_argument("--credits-format", default="json", choices=["json", "md"],
                   help="For --format credits: machine-readable json (default) or Markdown")
    p.add_argument("--output", required=True)
    p.set_defaults(func=cmd_export)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
