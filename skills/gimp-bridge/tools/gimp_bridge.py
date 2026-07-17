"""GIMP bridge — headless, script-driven image ops for the asset pipeline, wired
the same way the Blender/Daz bridges are (shell out to the DCC, graceful degrade
when it isn't installed).

GIMP has no `pip` module; we drive its batch mode:
    gimp -i -b '<script-fu>' -b '(gimp-quit 0)'

The command BUILDER (build_scriptfu) is pure + unit-testable offline; execution
(run_op) needs GIMP on PATH and returns an honest {ok:false,error} if it's
absent — no fake success. Ops chosen for game-asset work that ComfyUI/sharp don't
cover as cleanly: pixel-art-safe nearest scaling, palette (indexed) reduction,
flatten, format convert, and an arbitrary script-fu passthrough.

Usage:
    python gimp_bridge.py scale   <in> <out> --width 64 --height 64 [--interp none]
    python gimp_bridge.py indexed <in> <out> --colors 16 [--dither none]
    python gimp_bridge.py flatten <in> <out>
    python gimp_bridge.py convert <in> <out>            # by output extension
    python gimp_bridge.py script  <in> <out> --scriptfu '(...)'   # {IN}/{OUT} tokens
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

INTERP = {"none": 0, "linear": 1, "cubic": 2, "nohalo": 3, "lohalo": 3}  # gimp INTERPOLATION-*


def find_gimp() -> str | None:
    """Locate a GIMP executable (PATH first, then common Windows install dirs)."""
    for name in ("gimp-console-2.10", "gimp-2.10", "gimp-console", "gimp"):
        p = shutil.which(name)
        if p:
            return p
    for base in (
        r"C:/Program Files/GIMP 2/bin",
        r"C:/Program Files/GIMP 2.10/bin",
    ):
        if os.path.isdir(base):
            for f in sorted(os.listdir(base)):
                if f.startswith("gimp-console") and f.endswith(".exe"):
                    return os.path.join(base, f)
    return None


def _q(path: str) -> str:
    """Quote a path for a script-fu string literal (GIMP wants forward slashes)."""
    return '"' + path.replace("\\", "/").replace('"', '\\"') + '"'


def build_scriptfu(op: str, in_path: str, out_path: str, **kw) -> str:
    """Build the script-fu batch string for an op. Pure — no IO. This is the
    testable heart of the bridge."""
    load = f"(let* ((image (car (gimp-file-load RUN-NONINTERACTIVE {_q(in_path)} {_q(in_path)}))) (drawable (car (gimp-image-get-active-drawable image))))"
    save = f"(gimp-image-flatten image) (file-save RUN-NONINTERACTIVE image (car (gimp-image-get-active-drawable image)) {_q(out_path)} {_q(out_path)}) (gimp-image-delete image))"

    if op == "scale":
        w = int(kw.get("width", 0))
        h = int(kw.get("height", 0))
        interp = INTERP.get(str(kw.get("interp", "none")), 0)
        body = f"(gimp-context-set-interpolation {interp}) (gimp-image-scale image {w} {h})"
        return load + " " + body + " " + save
    if op == "indexed":
        colors = int(kw.get("colors", 16))
        dither = 0 if str(kw.get("dither", "none")) == "none" else 1
        # MAKE-PALETTE = 0 (optimal), then convert; keeps a tight game palette.
        body = f"(gimp-image-convert-indexed image {dither} 0 {colors} FALSE FALSE \"\")"
        return load + " " + body + " " + save
    if op == "flatten":
        return load + " (gimp-image-flatten image) " + save
    if op == "convert":
        # load + save (format is chosen by out_path extension) — a pure re-encode.
        return load + " " + save
    if op == "script":
        sf = str(kw.get("scriptfu", "")).replace("{IN}", in_path.replace("\\", "/")).replace(
            "{OUT}", out_path.replace("\\", "/")
        )
        return sf
    raise ValueError(f"unknown op '{op}'")


def run_op(op: str, in_path: str, out_path: str, **kw) -> dict:
    gimp = find_gimp()
    if gimp is None:
        return {
            "ok": False,
            "error": "GIMP not found. Install GIMP 2.10+ (gimp-console on PATH) — the bridge is "
            "ready; this op needs the executable.",
            "op": op,
        }
    if not os.path.exists(in_path):
        return {"ok": False, "error": f"input not found: {in_path}", "op": op}
    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    scriptfu = build_scriptfu(op, in_path, out_path, **kw)
    try:
        proc = subprocess.run(
            [gimp, "-i", "-d", "-f", "-b", scriptfu, "-b", "(gimp-quit 0)"],
            capture_output=True,
            text=True,
            timeout=int(kw.get("timeout", 180)),
        )
    except (subprocess.TimeoutExpired, OSError) as e:
        return {"ok": False, "error": f"gimp invocation failed: {e}", "op": op}
    if not os.path.exists(out_path):
        return {"ok": False, "error": f"gimp produced no output. stderr: {proc.stderr[:500]}", "op": op}
    return {"ok": True, "op": op, "output": out_path, "gimp": gimp}


def main() -> None:
    p = argparse.ArgumentParser(description="gimp-bridge: headless GIMP image ops")
    sub = p.add_subparsers(required=True, dest="op")
    for name in ("scale", "indexed", "flatten", "convert", "script"):
        sp = sub.add_parser(name)
        sp.add_argument("in_path")
        sp.add_argument("out_path")
        if name == "scale":
            sp.add_argument("--width", type=int, required=True)
            sp.add_argument("--height", type=int, required=True)
            sp.add_argument("--interp", default="none", choices=list(INTERP.keys()))
        if name == "indexed":
            sp.add_argument("--colors", type=int, default=16)
            sp.add_argument("--dither", default="none", choices=["none", "floyd"])
        if name == "script":
            sp.add_argument("--scriptfu", required=True, help="script-fu with {IN}/{OUT} tokens")
    args = p.parse_args()
    kw = {k: v for k, v in vars(args).items() if k not in ("op", "in_path", "out_path")}
    print(json.dumps(run_op(args.op, args.in_path, args.out_path, **kw), indent=2))


if __name__ == "__main__":
    main()
