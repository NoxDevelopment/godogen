"""Inkscape bridge — headless, CLI-driven **vector/SVG** ops for the asset
pipeline, wired the same way the gimp/blender/daz bridges are (shell out to the
DCC, degrade gracefully when it isn't installed with an honest {ok:false,error},
never a fake success).

Where the GIMP bridge covers raster game-asset work, this covers the VECTOR side —
crisp, resolution-independent UI: icons, logos, HUD elements, app-icon/favicon
ladders, and clean SVG for engine ingestion. Text renders exactly (no raster
hallucination), which is why vector is the right tool for UI/UX and marketing art.

The command BUILDER (build_args) is pure + unit-testable offline; execution
(run_op) needs Inkscape 1.x on PATH (or a standard install dir) and returns an
honest {ok:false,error} if it's absent. Clean-room: built from Inkscape's public
1.x command-line interface, no third-party code adopted.

Usage:
    python inkscape_bridge.py png     in.svg out.png --width 256 --height 256 [--area drawing]
    python inkscape_bridge.py pdf     in.svg out.pdf [--text-to-path]
    python inkscape_bridge.py layer   in.svg out.png --id logo [--width 128]
    python inkscape_bridge.py iconset in.svg out_dir/ [--sizes 16,32,48,64,128,256,512]
    python inkscape_bridge.py plain-svg in.svg out.svg          # clean/normalise for engines
    python inkscape_bridge.py actions in.svg out.svg --actions "select-all;object-to-path"  # transforms; bridge exports
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

DEFAULT_ICON_SIZES = [16, 32, 48, 64, 128, 256, 512]


def find_inkscape() -> str | None:
    """Locate an Inkscape executable. Prefer the console `inkscape.com` on Windows
    (it attaches stdout properly); fall back to `inkscape`/`inkscape.exe`. Checks
    PATH first, then the standard install dirs."""
    for name in ("inkscape.com", "inkscape"):
        p = shutil.which(name)
        if p:
            return p
    bases = [
        r"C:/Program Files/Inkscape/bin",
        r"C:/Program Files/Inkscape",
        r"C:/Program Files (x86)/Inkscape/bin",
        r"C:/Program Files (x86)/Inkscape",
    ]
    local = os.environ.get("LOCALAPPDATA")
    if local:
        bases.append(os.path.join(local, "Programs", "Inkscape", "bin"))
    for base in bases:
        for exe in ("inkscape.com", "inkscape.exe"):
            cand = os.path.join(base, exe)
            if os.path.isfile(cand):
                return cand
    return None


def build_args(op: str, in_path: str, out_path: str, **kw) -> list[str]:
    """Build the Inkscape CLI argv (everything AFTER the exe). Pure — no IO. This
    is the testable heart of the bridge. `iconset` is compound (N invocations) and
    is handled in run_op, not here."""
    ip = in_path.replace("\\", "/")
    op_out = out_path.replace("\\", "/")

    if op in ("png", "svg2png"):
        args = [ip, "--export-type=png", f"--export-filename={op_out}"]
        if kw.get("width"):
            args.append(f"--export-width={int(kw['width'])}")
        if kw.get("height"):
            args.append(f"--export-height={int(kw['height'])}")
        if kw.get("dpi"):
            args.append(f"--export-dpi={float(kw['dpi'])}")
        area = str(kw.get("area", "")).lower()
        if area == "drawing":
            args.append("--export-area-drawing")
        elif area == "page":
            args.append("--export-area-page")
        bg = kw.get("background")
        if bg:
            # opaque background (else PNG stays transparent, the default we want for UI).
            args.append(f"--export-background={bg}")
            args.append(f"--export-background-opacity={float(kw.get('bg_opacity', 1.0))}")
        return args
    if op == "pdf":
        args = [ip, "--export-type=pdf", f"--export-filename={op_out}"]
        if kw.get("text_to_path"):
            # embed glyphs as paths → the PDF renders identically without the fonts.
            args.append("--export-text-to-path")
        return args
    if op == "layer":
        lid = str(kw.get("id", "")).strip()
        if not lid:
            raise ValueError("layer: --id (object/layer id) is required")
        args = [
            ip,
            f"--export-id={lid}",
            "--export-id-only",
            "--export-type=png",
            f"--export-filename={op_out}",
        ]
        if kw.get("width"):
            args.append(f"--export-width={int(kw['width'])}")
        if kw.get("height"):
            args.append(f"--export-height={int(kw['height'])}")
        return args
    if op == "plain-svg":
        # normalise to plain SVG (drop Inkscape-specific cruft) + vacuum unused defs
        # so an engine/web importer gets a lean file.
        return [
            ip,
            "--export-type=svg",
            "--export-plain-svg",
            "--vacuum-defs",
            f"--export-filename={op_out}",
        ]
    if op == "actions":
        # Escape hatch: run a list of Inkscape TRANSFORM actions (object-to-path,
        # boolean ops, etc.), then the bridge exports to out_path via flags — the
        # reliable Inkscape-1.x pattern (export-in-actions is finicky across point
        # releases). Supply only the transforms; the bridge owns the export.
        acts = str(kw.get("actions", "")).strip()
        if not acts:
            raise ValueError("actions: --actions '<action-list>' is required")
        ext = op_out.rsplit(".", 1)[-1].lower() if "." in op_out else "svg"
        args = [ip, f"--actions={acts}", f"--export-filename={op_out}", f"--export-type={ext}"]
        if ext == "svg":
            args.append("--export-plain-svg")
        return args
    raise ValueError(f"unknown op '{op}'")


def _parse_sizes(raw) -> list[int]:
    if not raw:
        return list(DEFAULT_ICON_SIZES)
    out: list[int] = []
    for tok in str(raw).replace(",", " ").split():
        try:
            n = int(tok)
        except ValueError:
            continue
        if 1 <= n <= 4096:
            out.append(n)
    return out or list(DEFAULT_ICON_SIZES)


def _run_iconset(ink: str, in_path: str, out_dir: str, **kw) -> dict:
    """Export one SVG into a square app-icon / favicon ladder (icon-<size>.png).
    A separate Inkscape invocation per size — robust across 1.x point releases."""
    sizes = _parse_sizes(kw.get("sizes"))
    stem = str(kw.get("stem", "icon"))
    os.makedirs(out_dir, exist_ok=True)
    made: list[str] = []
    for s in sizes:
        out_path = os.path.join(out_dir, f"{stem}-{s}.png")
        args = build_args("png", in_path, out_path, width=s, height=s, area=kw.get("area", ""))
        try:
            subprocess.run(
                [ink, *args], capture_output=True, text=True, timeout=int(kw.get("timeout", 120))
            )
        except (subprocess.TimeoutExpired, OSError) as e:
            return {"ok": False, "error": f"inkscape invocation failed at {s}px: {e}", "op": "iconset"}
        if os.path.exists(out_path):
            made.append(out_path)
    if not made:
        return {"ok": False, "error": "iconset produced no output (check the SVG opens in Inkscape).", "op": "iconset"}
    return {"ok": True, "op": "iconset", "outputs": made, "dir": out_dir, "sizes": sizes, "inkscape": ink}


def run_op(op: str, in_path: str, out_path: str, **kw) -> dict:
    ink = find_inkscape()
    if ink is None:
        return {
            "ok": False,
            "error": "Inkscape not found. Install Inkscape 1.x (inkscape on PATH, or "
            "C:/Program Files/Inkscape/bin) — the bridge is ready; this op needs the executable.",
            "op": op,
        }
    if not os.path.exists(in_path):
        return {"ok": False, "error": f"input not found: {in_path}", "op": op}
    if op == "iconset":
        return _run_iconset(ink, in_path, out_path, **kw)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    try:
        args = build_args(op, in_path, out_path, **kw)
    except ValueError as e:
        return {"ok": False, "error": str(e), "op": op}
    try:
        proc = subprocess.run(
            [ink, *args], capture_output=True, text=True, timeout=int(kw.get("timeout", 120))
        )
    except (subprocess.TimeoutExpired, OSError) as e:
        return {"ok": False, "error": f"inkscape invocation failed: {e}", "op": op}
    if not os.path.exists(out_path):
        return {"ok": False, "error": f"inkscape produced no output. stderr: {proc.stderr[:500]}", "op": op}
    return {"ok": True, "op": op, "output": out_path, "inkscape": ink}


def main() -> None:
    p = argparse.ArgumentParser(description="inkscape-bridge: headless Inkscape vector/SVG ops")
    sub = p.add_subparsers(required=True, dest="op")
    for name in ("png", "svg2png", "pdf", "layer", "iconset", "plain-svg", "actions"):
        sp = sub.add_parser(name)
        sp.add_argument("in_path")
        sp.add_argument("out_path")
        if name in ("png", "svg2png", "layer"):
            sp.add_argument("--width", type=int)
            sp.add_argument("--height", type=int)
        if name in ("png", "svg2png"):
            sp.add_argument("--dpi", type=float)
            sp.add_argument("--area", default="", choices=["", "drawing", "page"])
            sp.add_argument("--background", help="e.g. white / #101010 (default: transparent)")
            sp.add_argument("--bg-opacity", dest="bg_opacity", type=float, default=1.0)
        if name == "pdf":
            sp.add_argument("--text-to-path", dest="text_to_path", action="store_true")
        if name == "layer":
            sp.add_argument("--id", required=True, help="object/layer id to isolate")
        if name == "iconset":
            sp.add_argument("--sizes", default="", help="comma list, default 16,32,48,64,128,256,512")
            sp.add_argument("--stem", default="icon")
            sp.add_argument("--area", default="", choices=["", "drawing", "page"])
        if name == "actions":
            sp.add_argument("--actions", required=True, help="Inkscape action list (;-separated)")
    args = p.parse_args()
    kw = {k: v for k, v in vars(args).items() if k not in ("op", "in_path", "out_path") and v is not None}
    print(json.dumps(run_op(args.op, args.in_path, args.out_path, **kw), indent=2))


if __name__ == "__main__":
    main()
