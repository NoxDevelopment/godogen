"""Offline probe for the 3D backend dispatch — no ComfyUI / no network.

Run: python _selftest_backend.py   (exits 0 on pass, 1 on failure)
Validates the pure logic: graph construction, quality→faces mapping, explicit
backend resolution, and the missing-image guard. The live end-to-end path
(upload → generate → copy .glb) is exercised by an actual `mesh_gen.py mesh`
run against a ComfyUI, not here.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import hunyuan3d
import mesh_gen

fail = 0


def check(name, cond):
    global fail
    print(("  ok  " if cond else "FAIL  ") + name)
    if not cond:
        fail += 1


# --- graph construction (offline) ---
shape = hunyuan3d._shape_graph("img.png", "3D/x", max_faces=20000, steps=30, octree=384)
check("shape graph has 6 nodes", len(shape) == 6)
check("shape graph ends in Hy3DExportMesh", shape["6"]["class_type"] == "Hy3DExportMesh")
check("shape max_facenum wired", shape["5"]["inputs"]["max_facenum"] == 20000)

tex = hunyuan3d._textured_graph("img.png", "3D/x", 40000, 30, 384, 2048, 25)
check("textured graph has 15 nodes", len(tex) == 15)
check("textured has the paint bake node", tex["12"]["class_type"] == "Hy3DBakeFromMultiview")
check("textured export takes the applied-texture mesh", tex["15"]["inputs"]["trimesh"] == ["14", 0])
check("textured render texture_size wired", tex["9"]["inputs"]["texture_size"] == 2048)

# --- quality → faces mapping ---
check("lowpoly=5000 faces", mesh_gen._HY3D_FACES["lowpoly"] == 5000)
check("medium=20000 faces", mesh_gen._HY3D_FACES["medium"] == 20000)

# --- explicit backend resolution (no auto/network) ---
check("resolve tripo3d", mesh_gen._resolve_backend("tripo3d") == "tripo3d")
check("resolve hunyuan3d", mesh_gen._resolve_backend("hunyuan3d") == "hunyuan3d")

# --- missing-image guard (offline, no network reached) ---
try:
    hunyuan3d.image_to_glb(Path("does_not_exist_zzz.png"), Path("out.glb"))
    check("missing image raises", False)
except FileNotFoundError:
    check("missing image raises FileNotFoundError", True)
except Exception as e:
    check(f"missing image raises FileNotFoundError (got {type(e).__name__})", False)

print(("PASS" if fail == 0 else f"FAILED ({fail})"))
sys.exit(1 if fail else 0)
