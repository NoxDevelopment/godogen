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
