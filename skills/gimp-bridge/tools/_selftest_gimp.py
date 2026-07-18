"""Offline probe for the GIMP script-fu builder (no GIMP needed). Run:
python _selftest_gimp.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gimp_bridge import build_scriptfu, find_gimp, run_op

fail = 0


def check(name, cond):
    global fail
    print(("  ok  " if cond else "FAIL  ") + name)
    if not cond:
        fail += 1


s = build_scriptfu("scale", "in.png", "out.png", width=64, height=64, interp="none")
check("scale loads the input", "gimp-file-load" in s and "in.png" in s)
check("scale sets 64x64", "gimp-image-scale image 64 64" in s)
check("scale interp none = 0", "gimp-context-set-interpolation 0" in s)
check("scale saves the output", "file-save" in s and "out.png" in s)

idx = build_scriptfu("indexed", "a.png", "b.png", colors=16, dither="none")
check("indexed 16 colors, no dither", "gimp-image-convert-indexed image 0 0 16" in idx)
idx2 = build_scriptfu("indexed", "a.png", "b.png", colors=8, dither="floyd")
check("indexed floyd dither = 1", "gimp-image-convert-indexed image 1 0 8" in idx2)

flat = build_scriptfu("flatten", "a.xcf", "b.png")
check("flatten flattens", "gimp-image-flatten image" in flat)

conv = build_scriptfu("convert", "a.png", "b.webp")
check("convert re-encodes to output ext", "b.webp" in conv and "gimp-file-load" in conv)

bc = build_scriptfu("brightness-contrast", "a.png", "b.png", brightness=127, contrast=-127)
check("brightness-contrast maps -127..127 to -1..1", "gimp-drawable-brightness-contrast drawable 1.0000 -1.0000" in bc)

hs = build_scriptfu("hue-saturation", "a.png", "b.png", hue=40, lightness=0, saturation=-20)
check("hue-saturation uses HUE-RANGE-ALL(0) + args", "gimp-drawable-hue-saturation drawable 0 40 0 -20 0" in hs)

bl = build_scriptfu("blur", "a.png", "b.png", radius=4)
check("blur is gaussian IIR", "plug-in-gauss RUN-NONINTERACTIVE image drawable 4.00 4.00 0" in bl)

sh = build_scriptfu("sharpen", "a.png", "b.png", radius=2, amount=0.8, threshold=0)
check("sharpen is unsharp-mask", "plug-in-unsharp-mask RUN-NONINTERACTIVE image drawable 2.00 0.80 0" in sh)

r90 = build_scriptfu("rotate", "a.png", "b.png", degrees=90)
r270 = build_scriptfu("rotate", "a.png", "b.png", degrees=270)
check("rotate 90 -> ROTATE-90(0)", "gimp-image-rotate image 0" in r90)
check("rotate 270 -> ROTATE-270(2)", "gimp-image-rotate image 2" in r270)
try:
    build_scriptfu("rotate", "a.png", "b.png", degrees=45)
    check("rotate rejects non-quadrant angles", False)
except ValueError:
    check("rotate rejects non-quadrant angles", True)

fh = build_scriptfu("flip", "a.png", "b.png", axis="horizontal")
fv = build_scriptfu("flip", "a.png", "b.png", axis="vertical")
check("flip horizontal -> 0", "gimp-image-flip image 0" in fh)
check("flip vertical -> 1", "gimp-image-flip image 1" in fv)

ds = build_scriptfu("drop-shadow", "a.png", "b.png", offset_x=4, offset_y=4, blur=8, opacity=60)
check("drop-shadow calls script-fu-drop-shadow", "script-fu-drop-shadow image drawable 4 4 8 '(0 0 0) 60 FALSE" in ds)

gr = build_scriptfu("grain", "a.png", "b.png", amount=40, dulling=2)
check("grain is hsv-noise value channel", "plug-in-hsv-noise RUN-NONINTERACTIVE image drawable 2 0 0 40" in gr)

scr = build_scriptfu("script", "a.png", "b.png", scriptfu="(do {IN} -> {OUT})")
check("script substitutes IN/OUT tokens", "a.png" in scr and "b.png" in scr and "{IN}" not in scr)

# path quoting handles backslashes -> forward slashes
sw = build_scriptfu("convert", r"C:\x\in.png", r"C:\y\out.png")
check("windows paths become forward slashes", "C:/x/in.png" in sw and "\\" not in sw.split("gimp-quit")[0].replace('\\"', ""))

# run_op degrades gracefully when GIMP is absent (or reports the exe if present)
res = run_op("convert", "does_not_exist_zzz.png", "out.png")
check(
    "run_op returns a structured result (no fake success)",
    res.get("ok") is False and "error" in res,
)
print("gimp on PATH:", find_gimp())

print("PASS" if fail == 0 else f"FAILED ({fail})")
sys.exit(1 if fail else 0)
