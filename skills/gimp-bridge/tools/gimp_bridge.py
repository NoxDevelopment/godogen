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
    python gimp_bridge.py brightness-contrast <in> <out> --brightness 20 --contrast 10
    python gimp_bridge.py hue-saturation <in> <out> --hue 40 --saturation -20  # recolour
    python gimp_bridge.py blur    <in> <out> --radius 4      # gaussian soft-focus / glow
    python gimp_bridge.py sharpen <in> <out> --amount 0.8    # unsharp-mask crisp-up
    python gimp_bridge.py rotate  <in> <out> --degrees 90    # sprite variants (90/180/270)
    python gimp_bridge.py flip    <in> <out> --axis horizontal   # mirror a sprite
    python gimp_bridge.py drop-shadow <in> <out> --offset-x 4 --offset-y 4 --blur 8  # UI depth
    python gimp_bridge.py grain   <in> <out> --amount 40    # retro film/FMV grain
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
    """Locate a GIMP executable (PATH first, then common install dirs incl. a
    per-user AppData install — GIMP's installer offers 'just for me')."""
    for name in ("gimp-console-2.10", "gimp-2.10", "gimp-console-3.0", "gimp-console", "gimp"):
        p = shutil.which(name)
        if p:
            return p
    bases = [
        r"C:/Program Files/GIMP 2/bin",
        r"C:/Program Files/GIMP 2.10/bin",
        r"C:/Program Files/GIMP 3/bin",
    ]
    local = os.environ.get("LOCALAPPDATA")
    if local:
        bases += [
            os.path.join(local, "Programs", "GIMP 2", "bin"),
            os.path.join(local, "Programs", "GIMP 3", "bin"),
        ]
    for base in bases:
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
    save = f"(gimp-image-flatten image) (gimp-file-save RUN-NONINTERACTIVE image (car (gimp-image-get-active-drawable image)) {_q(out_path)} {_q(out_path)}) (gimp-image-delete image))"

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
    if op == "brightness-contrast":
        # user-facing -127..127 (the familiar GIMP slider range) → the 2.10
        # gimp-drawable-brightness-contrast DOUBLE range -1..1.
        b = max(-127, min(127, int(kw.get("brightness", 0)))) / 127.0
        c = max(-127, min(127, int(kw.get("contrast", 0)))) / 127.0
        body = f"(gimp-drawable-brightness-contrast drawable {b:.4f} {c:.4f})"
        return load + " " + body + " " + save
    if op == "hue-saturation":
        # recolour a sprite/tile: shift hue, lift/drop saturation & lightness.
        # HUE-RANGE-ALL = 0; ranges hue -180..180, lightness/saturation -100..100.
        hue = max(-180, min(180, int(kw.get("hue", 0))))
        light = max(-100, min(100, int(kw.get("lightness", 0))))
        sat = max(-100, min(100, int(kw.get("saturation", 0))))
        body = f"(gimp-drawable-hue-saturation drawable 0 {hue} {light} {sat} 0)"
        return load + " " + body + " " + save
    if op == "blur":
        # gaussian soft-focus / glow / soft-shadow prep. radius in px (IIR method).
        r = max(0.1, float(kw.get("radius", 4)))
        body = f"(plug-in-gauss RUN-NONINTERACTIVE image drawable {r:.2f} {r:.2f} 0)"
        return load + " " + body + " " + save
    if op == "sharpen":
        # unsharp-mask crisp-up (radius px, amount 0..5, threshold 0..255).
        r = max(0.0, float(kw.get("radius", 2)))
        amt = max(0.0, float(kw.get("amount", 0.5)))
        thr = max(0, min(255, int(kw.get("threshold", 0))))
        body = f"(plug-in-unsharp-mask RUN-NONINTERACTIVE image drawable {r:.2f} {amt:.2f} {thr})"
        return load + " " + body + " " + save
    if op == "rotate":
        # 90/180/270 CW → ROTATE-90=0, ROTATE-180=1, ROTATE-270=2 (sprite variants).
        deg = int(kw.get("degrees", 90)) % 360
        rot = {90: 0, 180: 1, 270: 2}.get(deg)
        if rot is None:
            raise ValueError("rotate: degrees must be 90, 180, or 270")
        body = f"(gimp-image-rotate image {rot})"
        return load + " " + body + " " + save
    if op == "flip":
        # mirror a sprite. ORIENTATION-HORIZONTAL=0, ORIENTATION-VERTICAL=1.
        axis = 1 if str(kw.get("axis", "horizontal")).lower().startswith("v") else 0
        body = f"(gimp-image-flip image {axis})"
        return load + " " + body + " " + save
    if op == "drop-shadow":
        # UI/sprite depth via the bundled script-fu-drop-shadow (needs alpha to
        # read against; our save flattens the result). Black shadow; resize off by
        # default so pipeline dimensions are preserved (enable to keep the full blur).
        ox = int(kw.get("offset_x", 4))
        oy = int(kw.get("offset_y", 4))
        blur = max(0, int(kw.get("blur", 8)))
        opacity = max(0, min(100, int(kw.get("opacity", 60))))
        resize = "TRUE" if str(kw.get("resize", "false")).lower() in ("1", "true", "yes") else "FALSE"
        body = (
            "(gimp-image-set-active-layer image drawable) "
            f"(script-fu-drop-shadow image drawable {ox} {oy} {blur} '(0 0 0) {opacity} {resize})"
        )
        return load + " " + body + " " + save
    if op == "grain":
        # retro film/FMV value-noise grain via plug-in-hsv-noise (dulling 1..8, then
        # hue 0, saturation 0, value = grain strength 0..255).
        dulling = max(1, min(8, int(kw.get("dulling", 2))))
        amount = max(0, min(255, int(kw.get("amount", 40))))
        body = f"(plug-in-hsv-noise RUN-NONINTERACTIVE image drawable {dulling} 0 0 {amount})"
        return load + " " + body + " " + save
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
    ops = (
        "scale", "indexed", "flatten", "convert",
        "brightness-contrast", "hue-saturation", "blur", "sharpen",
        "rotate", "flip", "drop-shadow", "grain", "script",
    )
    for name in ops:
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
        if name == "brightness-contrast":
            sp.add_argument("--brightness", type=int, default=0, help="-127..127")
            sp.add_argument("--contrast", type=int, default=0, help="-127..127")
        if name == "hue-saturation":
            sp.add_argument("--hue", type=int, default=0, help="-180..180")
            sp.add_argument("--lightness", type=int, default=0, help="-100..100")
            sp.add_argument("--saturation", type=int, default=0, help="-100..100")
        if name == "blur":
            sp.add_argument("--radius", type=float, default=4.0, help="gaussian radius px")
        if name == "sharpen":
            sp.add_argument("--radius", type=float, default=2.0)
            sp.add_argument("--amount", type=float, default=0.5, help="0..5")
            sp.add_argument("--threshold", type=int, default=0, help="0..255")
        if name == "rotate":
            sp.add_argument("--degrees", type=int, default=90, choices=[90, 180, 270])
        if name == "flip":
            sp.add_argument("--axis", default="horizontal", choices=["horizontal", "vertical"])
        if name == "drop-shadow":
            sp.add_argument("--offset-x", dest="offset_x", type=int, default=4)
            sp.add_argument("--offset-y", dest="offset_y", type=int, default=4)
            sp.add_argument("--blur", type=int, default=8, help="shadow blur px")
            sp.add_argument("--opacity", type=int, default=60, help="0..100")
            sp.add_argument("--resize", default="false", choices=["true", "false"],
                            help="grow the canvas to fit the shadow")
        if name == "grain":
            sp.add_argument("--amount", type=int, default=40, help="grain strength 0..255")
            sp.add_argument("--dulling", type=int, default=2, help="1..8 (higher = softer)")
        if name == "script":
            sp.add_argument("--scriptfu", required=True, help="script-fu with {IN}/{OUT} tokens")
    args = p.parse_args()
    kw = {k: v for k, v in vars(args).items() if k not in ("op", "in_path", "out_path")}
    print(json.dumps(run_op(args.op, args.in_path, args.out_path, **kw), indent=2))


if __name__ == "__main__":
    main()
