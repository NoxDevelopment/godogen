#!/usr/bin/env python3
"""scene-populate Kit Index — semantic map from kit_tag -> concrete set-dressing.

The Kit Index unifies four asset sources behind one lookup and records which
reuse-ladder rung sourced each tag (asset-reuse's ladder, made queryable):

    rung 1  project manifest      manifest.py find --labels <tag>
    rung 2  cross-project gallery GET :8787/api/gallery
    rung 3  owned kits            CC0 (godotsmith /api/catalog) | NAS (blender_worker)
    rung 4-5 derive/restyle       palette_swap / qwen-edit-instruct
    rung 6  generate              scene-art (backdrops) | 3d-asset-pipeline (props)
    greybox last-resort primitive so a scene can be blocked out with zero assets

This tool does the *lookup, bookkeeping, and planning*. The heavy actions
(installing a CC0 kit, running Blender normalization, generating a prop) are
performed by the agent per SKILL.md — this tool tells it WHICH action to run for
each tag and records the result in kits/index.json so the next run reuses it.

License gate (mandatory, per NoxDev/README.md flags): every index entry carries
a `license` + `commercial_ok`. `build-plan --commercial` marks any entry that is
not commercially cleared (e.g. Morteza personal-use-only creature packs) as
BLOCKED so the emitter refuses to bake it into a commercial build.

stdlib only. Network calls (gallery, catalog) are best-effort with a short
timeout and degrade to the next rung when offline — so this runs headless.

Subcommands
-----------
  init         Create kits/index.json (optionally seeded from biome_kits.json).
  resolve      Resolve ONE kit_tag through the ladder -> entry + recommendation.
  add          Record a resolved asset into the index.
  greybox      Emit a primitive greybox entry for a tag (deterministic shape/colour).
  build-plan   Resolve EVERY unique tag in a LAYOUT.json -> resolved.json + rung report.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Any, Optional

INDEX_VERSION = 1
HERE = Path(__file__).resolve().parent
DEFAULT_BIOME_KITS = HERE / "biome_kits.json"

# Tag -> greybox primitive + colour category. Lets a scene be blocked out with
# zero installed assets (grey-boxing is standard level-design practice, and it
# is what makes the whole pipeline runnable/verifiable headless with no NAS).
# (primitive shape, greybox RGB, ground footprint [w, d] in metres). Primitive
# HEIGHT is derived by the emitter from the tag category — footprint stays a
# ground measurement so the solver's spacing math is correct.
GREYBOX_SHAPES = {
    "conifer": ("cone", [0.16, 0.45, 0.22], [1.0, 1.0]),
    "broadleaf": ("sphere", [0.24, 0.60, 0.28], [1.6, 1.6]),
    "dead": ("cylinder", [0.35, 0.28, 0.22], [0.5, 0.5]),
    "tree": ("cone", [0.20, 0.55, 0.25], [1.2, 1.2]),
    "fern": ("cone", [0.20, 0.65, 0.30], [0.5, 0.5]),
    "bush": ("sphere", [0.22, 0.55, 0.26], [0.7, 0.7]),
    "grass": ("cone", [0.30, 0.70, 0.30], [0.3, 0.3]),
    "rock": ("box", [0.55, 0.55, 0.55], [0.6, 0.6]),
    "boulder": ("box", [0.50, 0.50, 0.50], [1.4, 1.4]),
    "log": ("cylinder", [0.45, 0.30, 0.20], [0.6, 2.0]),
    "mushroom": ("sphere", [0.85, 0.30, 0.30], [0.3, 0.3]),
    "shrine": ("box", [0.70, 0.70, 0.80], [1.4, 1.4]),
    "statue": ("box", [0.75, 0.75, 0.78], [1.0, 1.0]),
    "well": ("cylinder", [0.60, 0.60, 0.60], [1.4, 1.4]),
    "lantern": ("cylinder", [0.95, 0.85, 0.30], [0.3, 0.3]),
    "building": ("box", [0.60, 0.55, 0.50], [4.0, 4.0]),
    "wall": ("box", [0.55, 0.55, 0.55], [1.0, 1.0]),
    "sign": ("box", [0.60, 0.45, 0.30], [0.5, 0.5]),
    "crate": ("box", [0.65, 0.50, 0.35], [1.0, 1.0]),
    "barrel": ("cylinder", [0.55, 0.40, 0.28], [0.7, 0.7]),
    "pillar": ("cylinder", [0.70, 0.70, 0.70], [0.8, 0.8]),
    "cactus": ("cylinder", [0.25, 0.55, 0.30], [0.5, 0.5]),
    "tent": ("box", [0.75, 0.65, 0.45], [2.5, 2.0]),
}
GREYBOX_DEFAULT = ("box", [0.60, 0.60, 0.62], [0.8, 0.8])


def _greybox_for(tag: str) -> dict:
    key = None
    for k in GREYBOX_SHAPES:
        if k in tag:
            key = k
            break
    shape, color, foot = GREYBOX_SHAPES.get(key, GREYBOX_DEFAULT)
    # Deterministic per-tag hue nudge so distinct tags read differently.
    h = int.from_bytes(hashlib.sha256(tag.encode()).digest()[:2], "big") / 65535.0
    r, g, b = color
    jitter = (h - 0.5) * 0.15
    color = [max(0.05, min(0.95, r + jitter)), max(0.05, min(0.95, g - jitter * 0.5)),
             max(0.05, min(0.95, b + jitter * 0.5))]
    return {
        "asset": f"primitive:{shape}",
        "greybox_color": [round(c, 3) for c in color],
        "footprint": foot,
        "multimesh_ok": ("fern" in tag or "grass" in tag or "bush" in tag),
        "scale_base": 1.0,
    }


# ---------------------------------------------------------------------------
# Index IO
# ---------------------------------------------------------------------------

def _load_index(path: Path) -> dict:
    if not path.exists():
        return {"version": INDEX_VERSION, "entries": []}
    return json.loads(path.read_text(encoding="utf-8"))


def _save_index(path: Path, index: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")


def _find_entry(index: dict, tag: str, dimension: Optional[str]) -> Optional[dict]:
    for e in index.get("entries", []):
        if e.get("kit_tag") == tag and (dimension is None or e.get("dimension") == dimension):
            return e
    return None


def _load_biome_kits(path: Optional[str]) -> dict:
    p = Path(path) if path else DEFAULT_BIOME_KITS
    if not p.exists():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Ladder rungs (best-effort, offline-safe)
# ---------------------------------------------------------------------------

def _manifest_find(tag: str, project_dir: Path) -> Optional[dict]:
    """rung 1 — is this tag already a manifested asset in THIS project?"""
    manifest = project_dir / "assets" / "manifest.json"
    if not manifest.exists():
        return None
    # Prefer the real manifest.py (published alongside), else parse JSON directly.
    manifest_py = project_dir / ".claude" / "skills" / "asset-manifest" / "tools" / "manifest.py"
    if manifest_py.exists():
        try:
            out = subprocess.run(
                [sys.executable, str(manifest_py), "find", "--manifest", str(manifest),
                 "--labels", tag],
                capture_output=True, text=True, timeout=20,
            )
            if out.returncode == 0:
                rows = json.loads(out.stdout or "[]")
                if rows:
                    return {"asset": "res://" + rows[0]["path"].lstrip("/"),
                            "source": "manifest:" + rows[0]["asset_id"], "rung": 1}
        except Exception:
            pass
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
        for e in data.get("assets", []):
            if tag in (e.get("labels") or []):
                return {"asset": "res://" + e["path"].lstrip("/"),
                        "source": "manifest:" + e["asset_id"], "rung": 1}
    except Exception:
        pass
    return None


def _http_json(url: str, timeout: float = 2.5) -> Optional[Any]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


def _gallery_find(tag: str, gallery_url: str) -> Optional[dict]:
    """rung 2 — cross-project gallery."""
    data = _http_json(f"{gallery_url.rstrip('/')}/api/gallery")
    if not data:
        return None
    items = data.get("items", data) if isinstance(data, dict) else data
    if not isinstance(items, list):
        return None
    for it in items:
        tags = " ".join(str(t) for t in (it.get("tags") or [])) + " " + str(it.get("name", ""))
        if tag.replace("_", " ") in tags.lower() or tag in tags.lower():
            return {"asset": it.get("path") or it.get("url"),
                    "source": "gallery:" + str(it.get("id", "?")), "rung": 2}
    return None


def _catalog_recommend(tag: str, biome: str, biome_kits: dict) -> Optional[dict]:
    """rung 3 (CC0 lane) — recommend a godotsmith catalog kit to install."""
    src = (biome_kits.get(biome, {}).get("kit_tag_sources", {}) or {}).get(tag, {})
    if src.get("cc0"):
        return {
            "rung": 3, "lane": "cc0_kit", "source": f"cc0_kit:{src['cc0']}",
            "command": f"POST /api/catalog/install {{\"id\": \"{src['cc0']}\"}} "
                       f"-> assets/kits/  (then kit_index.py add --tag {tag} ...)",
            "license": "CC0", "commercial_ok": True,
        }
    return None


def _nas_recommend(tag: str, biome: str, biome_kits: dict) -> Optional[dict]:
    """rung 3 (NAS lane) — recommend a Blender-normalize of a NAS bundle."""
    src = (biome_kits.get(biome, {}).get("kit_tag_sources", {}) or {}).get(tag, {})
    if src.get("nas"):
        return {
            "rung": 3, "lane": "nas_bundle", "source": f"nas:{src['nas']}",
            "command": (f"blender_worker.py import-normalize <mesh from NAS "
                        f"\\\\DXP4800PLUS-A79\\NoxDev\\blender-tools-and-assets\\{src['nas']}> "
                        f"assets/kits/nas_{tag}/{tag}.glb  (honor NoxDev/README license flags)"),
            "license": "royalty-free (verify NoxDev/README flag; Morteza=personal-only)",
            "commercial_ok": None,  # must be confirmed against the pack's flag
        }
    return None


def _gen_recommend(tag: str, biome: str, biome_kits: dict) -> Optional[dict]:
    """rung 6 — generation recipe (last resort)."""
    src = (biome_kits.get(biome, {}).get("kit_tag_sources", {}) or {}).get(tag, {})
    if src.get("gen"):
        return {
            "rung": 6, "lane": "generate", "source": "gen",
            "command": src["gen"], "license": "owned", "commercial_ok": True,
        }
    return None


# ---------------------------------------------------------------------------
# resolve — one tag through the ladder
# ---------------------------------------------------------------------------

def resolve_tag(
    tag: str,
    biome: str,
    dimension: str,
    index: dict,
    project_dir: Path,
    biome_kits: dict,
    gallery_url: Optional[str],
    allow_greybox: bool,
) -> dict:
    # rung 0 — already in the index? (fastest, and how re-runs stay stable)
    hit = _find_entry(index, tag, dimension) or _find_entry(index, tag, None)
    if hit and hit.get("path"):
        return {"kit_tag": tag, "resolved": True, "rung": hit.get("rung", 3),
                "entry": _entry_to_resolved(hit), "recommendation": None,
                "source": hit.get("source"), "license": hit.get("license"),
                "commercial_ok": hit.get("commercial_ok", True)}

    # rung 1 — project manifest
    m = _manifest_find(tag, project_dir)
    if m:
        return {"kit_tag": tag, "resolved": True, "rung": 1,
                "entry": {"asset": m["asset"], "footprint": _greybox_for(tag)["footprint"],
                          "multimesh_ok": _greybox_for(tag)["multimesh_ok"], "scale_base": 1.0},
                "recommendation": None, "source": m["source"],
                "license": "owned", "commercial_ok": True}

    # rung 2 — gallery
    if gallery_url:
        g = _gallery_find(tag, gallery_url)
        if g and g["asset"]:
            return {"kit_tag": tag, "resolved": True, "rung": 2,
                    "entry": {"asset": g["asset"], "footprint": _greybox_for(tag)["footprint"],
                              "multimesh_ok": _greybox_for(tag)["multimesh_ok"], "scale_base": 1.0},
                    "recommendation": None, "source": g["source"],
                    "license": "owned", "commercial_ok": True}

    # rung 3-6 — recommend an action (agent performs it, then calls `add`)
    rec = (_catalog_recommend(tag, biome, biome_kits)
           or _nas_recommend(tag, biome, biome_kits)
           or _gen_recommend(tag, biome, biome_kits))

    # greybox — always resolvable so layout iteration never blocks on assets
    gb = _greybox_for(tag) if allow_greybox else None
    return {
        "kit_tag": tag,
        "resolved": bool(gb),
        "rung": "greybox" if gb else None,
        "entry": {**gb, "greybox": True} if gb else None,
        "recommendation": rec,
        "source": "greybox" if gb else None,
        "license": "n/a" if gb else None,
        "commercial_ok": True,
    }


def _entry_to_resolved(entry: dict) -> dict:
    fp = entry.get("footprint_m") or entry.get("footprint") or [1.0, 1.0]
    return {
        "asset": "res://" + entry["path"].lstrip("/") if not entry["path"].startswith(("res://", "primitive:")) else entry["path"],
        "footprint": fp,
        "multimesh_ok": bool(entry.get("multimesh_ok", False)),
        "scale_base": float(entry.get("scale_base", 1.0)),
        "greybox_color": entry.get("greybox_color"),
    }


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_init(args) -> None:
    path = Path(args.index)
    if path.exists() and not args.force:
        raise SystemExit(f"index already exists: {path} (pass --force)")
    index = {"version": INDEX_VERSION, "entries": []}
    if args.seed_from_biome:
        # Pre-seed CC0 kit tags (engine-ready, no install step recorded — the
        # agent still installs, but the tag->kit mapping is captured up front).
        bk = _load_biome_kits(args.biome_kits)
        for biome, spec in bk.items():
            if biome.startswith("_") or not isinstance(spec, dict):
                continue
            for tag, src in (spec.get("kit_tag_sources", {}) or {}).items():
                if src.get("cc0"):
                    index["entries"].append({
                        "kit_tag": tag, "biome": [biome], "dimension": "3d",
                        "path": "", "source": f"cc0_kit:{src['cc0']}",
                        "license": "CC0", "commercial_ok": True,
                        "footprint_m": _greybox_for(tag)["footprint"],
                        "pivot": "bottom_center", "pending_install": True,
                    })
    _save_index(path, index)
    print(json.dumps({"ok": True, "index": str(path), "entries": len(index["entries"])}, indent=2))


def cmd_resolve(args) -> None:
    index = _load_index(Path(args.index))
    biome_kits = _load_biome_kits(args.biome_kits)
    res = resolve_tag(
        args.tag, args.biome, args.dimension, index, Path(args.project_dir),
        biome_kits, args.gallery_url, allow_greybox=not args.no_greybox,
    )
    print(json.dumps(res, indent=2))


def cmd_add(args) -> None:
    path = Path(args.index)
    index = _load_index(path)
    fp = [float(x) for x in args.footprint.split(",")] if args.footprint else [1.0, 1.0]
    entry = {
        "kit_tag": args.tag,
        "biome": [b.strip() for b in (args.biome or "").split(",") if b.strip()],
        "dimension": args.dimension,
        "path": args.path,
        "source": args.source,
        "license": args.license,
        "commercial_ok": None if args.commercial_ok == "unknown" else args.commercial_ok == "yes",
        "footprint_m": fp,
        "pivot": args.pivot,
        "multimesh_ok": args.multimesh_ok,
        "scale_base": args.scale_base,
        "rung": args.rung,
    }
    # Replace an existing same-tag/dimension entry (idempotent re-resolve).
    index["entries"] = [e for e in index.get("entries", [])
                        if not (e.get("kit_tag") == args.tag and e.get("dimension") == args.dimension)]
    index["entries"].append(entry)
    _save_index(path, index)
    print(json.dumps({"ok": True, "kit_tag": args.tag, "path": args.path}, indent=2))


def cmd_greybox(args) -> None:
    print(json.dumps({args.tag: _greybox_for(args.tag)}, indent=2))


def _collect_tags(layout: dict) -> list[str]:
    seen: list[str] = []
    for zone in layout.get("zones", []):
        for slot in zone.get("slots", []):
            t = slot.get("kit_tag")
            if t and t not in seen:
                seen.append(t)
    return seen


def cmd_build_plan(args) -> None:
    layout = json.loads(Path(args.layout).read_text(encoding="utf-8"))
    index = _load_index(Path(args.index))
    biome_kits = _load_biome_kits(args.biome_kits)
    biome = args.biome or layout.get("biome", "forest")
    dimension = layout.get("dimension", "3d")

    resolved: dict[str, dict] = {}
    report: list[dict] = []
    blocked: list[str] = []
    rung_hist: dict[str, int] = {}

    for tag in _collect_tags(layout):
        res = resolve_tag(tag, biome, dimension, index, Path(args.project_dir),
                          biome_kits, args.gallery_url, allow_greybox=not args.no_greybox)
        rung = str(res.get("rung"))
        rung_hist[rung] = rung_hist.get(rung, 0) + 1
        # License gate for commercial builds.
        commercial_ok = res.get("commercial_ok")
        is_blocked = bool(args.commercial) and commercial_ok is False
        if is_blocked:
            blocked.append(tag)
        if res.get("entry"):
            resolved[tag] = res["entry"]
        report.append({
            "kit_tag": tag, "rung": res.get("rung"), "resolved": res.get("resolved"),
            "source": res.get("source"), "recommendation": res.get("recommendation"),
            "license": res.get("license"), "commercial_ok": commercial_ok,
            "blocked": is_blocked,
        })

    # Write resolved.json for scatter.py.
    Path(args.out).write_text(json.dumps(resolved, indent=2) + "\n", encoding="utf-8")

    all_greybox = all(r.get("rung") == "greybox" for r in report) and bool(report)
    summary = {
        "ok": not blocked,
        "biome": biome, "dimension": dimension,
        "tags": len(report), "resolved_out": args.out,
        "rungs": rung_hist,
        "all_greybox": all_greybox,
        "blocked_commercial": blocked,
        "report": report,
    }
    if all_greybox:
        summary["note"] = ("Every tag resolved to greybox — no real assets found. This blocks "
                           "out the scene but is a 'failed plan' per asset-reuse: install CC0 "
                           "kits / normalize NAS bundles (see per-tag recommendation) then re-run.")
    print(json.dumps(summary, indent=2))
    if blocked:
        sys.exit(2)


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="scene-populate Kit Index")
    sub = ap.add_subparsers(required=True, dest="cmd")

    def _idx(p):
        p.add_argument("--index", default="kits/index.json")

    p = sub.add_parser("init", help="Create kits/index.json")
    _idx(p)
    p.add_argument("--force", action="store_true")
    p.add_argument("--seed-from-biome", action="store_true",
                   help="Pre-seed CC0 kit tag mappings from biome_kits.json")
    p.add_argument("--biome-kits", default=None)
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("resolve", help="Resolve one kit_tag through the ladder")
    _idx(p)
    p.add_argument("--tag", required=True)
    p.add_argument("--biome", default="forest")
    p.add_argument("--dimension", default="3d", choices=["2d", "3d"])
    p.add_argument("--project-dir", default=".")
    p.add_argument("--biome-kits", default=None)
    p.add_argument("--gallery-url", default=None, help="e.g. http://localhost:8787")
    p.add_argument("--no-greybox", action="store_true")
    p.set_defaults(func=cmd_resolve)

    p = sub.add_parser("add", help="Record a resolved asset in the index")
    _idx(p)
    p.add_argument("--tag", required=True)
    p.add_argument("--path", required=True, help="res:// path or primitive:<shape>")
    p.add_argument("--source", required=True)
    p.add_argument("--license", default="owned")
    p.add_argument("--commercial-ok", default="yes", choices=["yes", "no", "unknown"])
    p.add_argument("--biome", default="")
    p.add_argument("--dimension", default="3d", choices=["2d", "3d"])
    p.add_argument("--footprint", default="1.0,1.0", help="w,d in metres")
    p.add_argument("--pivot", default="bottom_center")
    p.add_argument("--multimesh-ok", action="store_true")
    p.add_argument("--scale-base", type=float, default=1.0)
    p.add_argument("--rung", default="3")
    p.set_defaults(func=cmd_add)

    p = sub.add_parser("greybox", help="Emit a primitive greybox entry for a tag")
    p.add_argument("--tag", required=True)
    p.set_defaults(func=cmd_greybox)

    p = sub.add_parser("build-plan", help="Resolve every tag in a LAYOUT.json -> resolved.json")
    _idx(p)
    p.add_argument("--layout", required=True)
    p.add_argument("--out", default="resolved.json")
    p.add_argument("--biome", default=None)
    p.add_argument("--project-dir", default=".")
    p.add_argument("--biome-kits", default=None)
    p.add_argument("--gallery-url", default=None)
    p.add_argument("--commercial", action="store_true",
                   help="Enforce the license gate (block personal-use-only entries)")
    p.add_argument("--no-greybox", action="store_true")
    p.set_defaults(func=cmd_build_plan)

    args = ap.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
