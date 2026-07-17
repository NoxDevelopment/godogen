"""Offline probe for the engine-agnostic sprite-sheet JSON (Aseprite/TexturePacker
hash format). No IO / no ffmpeg. Run: python _selftest_sheet_json.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from engine_writers import build_sheet_json

fail = 0


def check(name, cond):
    global fail
    print(("  ok  " if cond else "FAIL  ") + name)
    if not cond:
        fail += 1


# single-row cycle: 4 frames, 32px, 4 columns, 8 fps
d = build_sheet_json("walk.png", (32, 32), 4, 4, 8, "walk", True)
check("4 frame entries", len(d["frames"]) == 4)
check("frame keys namespaced", "walk 0.png" in d["frames"] and "walk 3.png" in d["frames"])
f0 = d["frames"]["walk 0.png"]["frame"]
f3 = d["frames"]["walk 3.png"]["frame"]
check("frame 0 at origin", f0 == {"x": 0, "y": 0, "w": 32, "h": 32})
check("frame 3 at x=96 row 0", f3 == {"x": 96, "y": 0, "w": 32, "h": 32})
check("duration = 125ms @ 8fps", d["frames"]["walk 0.png"]["duration"] == 125)
check("meta size 128x32", d["meta"]["size"] == {"w": 128, "h": 32})
tag = d["meta"]["frameTags"][0]
check("frameTag spans 0..3 forward", tag == {"name": "walk", "from": 0, "to": 3, "direction": "forward"})
check("meta carries image + fps + loop", d["meta"]["image"] == "walk.png" and d["meta"]["fps"] == 8 and d["meta"]["loop"] is True)

# two-row wrap: 6 frames, 4 columns -> row 1 starts at frame 4
d2 = build_sheet_json("run.png", (16, 16), 6, 4, 12, "run", True)
check("6 frames, 2 rows, size 64x32", d2["meta"]["size"] == {"w": 64, "h": 32})
check("frame 4 wraps to row 1 (x0,y16)", d2["frames"]["run 4.png"]["frame"] == {"x": 0, "y": 16, "w": 16, "h": 16})
check("frame 5 at x16,y16", d2["frames"]["run 5.png"]["frame"] == {"x": 16, "y": 16, "w": 16, "h": 16})
check("duration = 83ms @ 12fps", d2["frames"]["run 0.png"]["duration"] == 83)

print("PASS" if fail == 0 else f"FAILED ({fail})")
sys.exit(1 if fail else 0)
