"""Offline probe for the Inkscape CLI builder (no Inkscape needed). Run:
python _selftest_inkscape.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from inkscape_bridge import _parse_sizes, build_args, find_inkscape, run_op

fail = 0


def check(name, cond):
    global fail
    print(("  ok  " if cond else "FAIL  ") + name)
    if not cond:
        fail += 1


png = build_args("png", "in.svg", "out.png", width=256, height=256, area="drawing")
check("png sets export-type + filename", "--export-type=png" in png and "--export-filename=out.png" in png)
check("png sets exact width/height", "--export-width=256" in png and "--export-height=256" in png)
check("png area=drawing crops to content", "--export-area-drawing" in png)
check("png input is first arg", png[0] == "in.svg")

pngbg = build_args("png", "in.svg", "out.png", background="white", bg_opacity=1.0)
check("png background sets colour + opacity", "--export-background=white" in pngbg and "--export-background-opacity=1.0" in pngbg)

pdf = build_args("pdf", "in.svg", "out.pdf", text_to_path=True)
check("pdf exports pdf", "--export-type=pdf" in pdf and "--export-filename=out.pdf" in pdf)
check("pdf text-to-path embeds glyphs", "--export-text-to-path" in pdf)

pdf2 = build_args("pdf", "in.svg", "out.pdf")
check("pdf without text-to-path omits the flag", "--export-text-to-path" not in pdf2)

lay = build_args("layer", "in.svg", "out.png", id="logo", width=128)
check("layer isolates by id", "--export-id=logo" in lay and "--export-id-only" in lay)
check("layer exports png at size", "--export-type=png" in lay and "--export-width=128" in lay)
try:
    build_args("layer", "in.svg", "out.png")
    check("layer requires --id", False)
except ValueError:
    check("layer requires --id", True)

plain = build_args("plain-svg", "in.svg", "out.svg")
check("plain-svg normalises + vacuums", "--export-plain-svg" in plain and "--vacuum-defs" in plain)

act = build_args("actions", "in.svg", "out.svg", actions="select-all;object-to-path")
check("actions passes the transform list", "--actions=select-all;object-to-path" in act)
check("actions has the bridge own the export", "--export-filename=out.svg" in act and "--export-type=svg" in act)
try:
    build_args("actions", "in.svg", "out.svg")
    check("actions requires --actions", False)
except ValueError:
    check("actions requires --actions", True)

check("sizes default when empty", _parse_sizes("") == [16, 32, 48, 64, 128, 256, 512])
check("sizes parse comma list", _parse_sizes("16, 32,64") == [16, 32, 64])
check("sizes drop junk + clamp", _parse_sizes("32 x 99999 64") == [32, 64])

# windows backslashes normalise to forward slashes
wp = build_args("png", r"C:\a\in.svg", r"C:\b\out.png")
check("windows paths become forward slashes", wp[0] == "C:/a/in.svg" and "--export-filename=C:/b/out.png" in wp)

# graceful degrade / honest structured result
res = run_op("png", "does_not_exist_zzz.svg", "out.png")
check("run_op returns a structured result (no fake success)", res.get("ok") is False and "error" in res)
print("inkscape on PATH:", find_inkscape())

print("PASS" if fail == 0 else f"FAILED ({fail})")
sys.exit(1 if fail else 0)
