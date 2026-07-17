"""Round-trip + CC validation for pixeltool `extract` (run from this dir).
GRID: extracting the assembled overworld atlas recovers its 4 cells.
CC:   the 3-blob sprites sheet yields 3 tiles at the drawn bounding boxes."""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
TOOL = HERE.parent.parent / "tools" / "pixeltool.py"


def run(args):
    out = subprocess.check_output([sys.executable, str(TOOL), "extract", *args, "--json"], text=True)
    return json.loads(out.splitlines()[-1])


g = run([str(HERE.parent / "tileset-example" / "overworld.png"), "-o", str(HERE / "grid"),
         "--mode", "grid", "--tile-size", "32", "--separation", "2"])
assert g["tile_count"] == 4, g

c = run([str(HERE / "sprites_sheet.png"), "-o", str(HERE / "cc"), "--mode", "cc", "--connectivity", "8"])
assert c["tile_count"] == 3, c
assert sorted((t["w"], t["h"]) for t in c["tiles"]) == [(16, 16), (16, 24), (24, 20)], c

print("extract round-trip OK: grid=4 cells, cc=3 blobs")
