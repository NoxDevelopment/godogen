"""blender_worker.py — headless Blender asset worker for the blender-bridge skill.

Runs inside Blender's bundled Python (no external deps):

    blender -b -P blender_worker.py -- import-normalize <in.(fbx|obj|gltf|glb)> <out.glb>
    blender -b -P blender_worker.py -- turnaround <in.(fbx|obj|gltf|glb)> <outdir> \
        [--views 8] [--res 1024] [--samples 16] [--no-normalize]

Install of record: Blender 4.3 at "D:\\Blender Foundation\\Blender 4.3\\blender.exe".

Commands
--------
import-normalize
    Import FBX/OBJ/glTF, apply rotation+scale, rescale to meters via a
    power-of-ten heuristic (plausible asset band 0.05m..30m, target ~1.7m),
    move origin to bottom-center (feet at Z=0), then export an engine-clean
    GLB per the blender-bridge skill rules (Y-up, modifiers applied,
    <=4 bone influences, morph targets + normals, one glTF animation per
    action on a single armature).

turnaround
    Same import(+normalize), then orbit a camera rig (camera + 3-point light
    rig parented to a pivot empty so every view is identically lit) around
    the asset and render N transparent-background PNGs at res x res
    (EEVEE, low samples by default — these feed ComfyUI img2img / LoRA
    training, not final art). Writes manifest.json alongside the renders.
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

PLAUSIBLE_MIN_M = 0.05   # below this, the asset was almost surely not meters
PLAUSIBLE_MAX_M = 30.0   # above this, ditto (cm/mm exports land at 100x/1000x)
TARGET_SIZE_M = 1.7      # bias for the power-of-ten correction (human height)


def log(msg: str) -> None:
    print(f"[blender_worker] {msg}", flush=True)


def die(msg: str) -> None:
    print(f"[blender_worker] ERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def clean_scene() -> None:
    """Start from a truly empty scene (no default cube/camera/light)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_asset(path: str) -> list:
    """Import by extension; return the list of newly created objects."""
    if not os.path.isfile(path):
        die(f"input file not found: {path}")
    before = set(bpy.data.objects)
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)  # Blender 4.x native OBJ importer
    elif ext in (".gltf", ".glb"):
        bpy.ops.import_scene.gltf(filepath=path)
    else:
        die(f"unsupported input extension '{ext}' (fbx/obj/gltf/glb)")
    imported = [o for o in bpy.data.objects if o not in before]
    if not imported:
        die("import produced no objects")
    log(f"imported {len(imported)} object(s) from {os.path.basename(path)}: "
        + ", ".join(f"{o.name}({o.type})" for o in imported))
    return imported


def geometry_objects(objs: list) -> list:
    return [o for o in objs if o.type in ("MESH", "CURVE", "SURFACE", "META", "FONT")]


def world_bbox(objs: list):
    """(min, max) world-space corners across all geometry objects."""
    geo = geometry_objects(objs)
    if not geo:
        die("no geometry objects found (only empties/lights/cameras?)")
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in geo:
        eval_obj = obj.evaluated_get(deps)
        for corner in eval_obj.bound_box:
            wc = eval_obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, wc))
            hi = Vector(map(max, hi, wc))
    return lo, hi


def select_only(objs: list) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def top_level(objs: list) -> list:
    """Objects whose parent is not part of the imported set."""
    objset = set(objs)
    return [o for o in objs if o.parent not in objset]


def apply_transforms(objs: list, location=False, rotation=True, scale=True) -> None:
    select_only(objs)
    # Multi-user data blocks make transform_apply fail — split them first.
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=location, rotation=rotation, scale=scale)


def normalize(objs: list) -> None:
    """Apply transforms, heuristic-rescale to meters, feet/bottom at origin."""
    if bpy.context.view_layer.objects.active is None and objs:
        bpy.context.view_layer.objects.active = objs[0]
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    # 1. bake importer rotation/scale (FBX loves 0.01-scale + 90deg X)
    apply_transforms(objs, rotation=True, scale=True)

    # 2. scale-to-meters heuristic
    lo, hi = world_bbox(objs)
    max_dim = max(hi - lo)
    if max_dim <= 0.0:
        die("degenerate bounding box (zero size)")
    if not (PLAUSIBLE_MIN_M <= max_dim <= PLAUSIBLE_MAX_M):
        factor = 10.0 ** round(math.log10(TARGET_SIZE_M / max_dim))
        log(f"rescale heuristic: max dimension {max_dim:.4f} outside "
            f"[{PLAUSIBLE_MIN_M}, {PLAUSIBLE_MAX_M}] m -> scaling by {factor:g}")
        for obj in top_level(objs):
            obj.scale = [s * factor for s in obj.scale]
        apply_transforms(objs, rotation=False, scale=True)
        lo, hi = world_bbox(objs)
        max_dim = max(hi - lo)
    else:
        log(f"rescale heuristic: max dimension {max_dim:.4f} m is plausible, no rescale")

    # 3. origin fix: bottom-center of the combined bbox to world origin
    center = (lo + hi) / 2.0
    offset = Vector((-center.x, -center.y, -lo.z))
    if offset.length > 1e-9:
        log(f"origin fix: translating by ({offset.x:.4f}, {offset.y:.4f}, {offset.z:.4f})")
        for obj in top_level(objs):
            obj.location += offset
        apply_transforms(objs, location=True, rotation=False, scale=False)

    lo, hi = world_bbox(objs)
    dim = hi - lo
    log(f"normalized bbox: {dim.x:.3f} x {dim.y:.3f} x {dim.z:.3f} m, "
        f"bottom-center at origin (min z = {lo.z:.5f})")


def export_glb(out_path: str) -> None:
    """Engine-clean GLB per the blender-bridge skill export rules."""
    out_path = os.path.abspath(out_path)
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    kwargs = dict(
        filepath=out_path,
        export_format="GLB",
        export_yup=True,               # Godot + Unity are Y-up
        export_apply=True,             # apply modifiers
        export_materials="EXPORT",     # Principled BSDF only survives anyway
        export_animations=True,
        export_anim_single_armature=True,  # one glTF animation per action
        export_frame_range=False,
        export_skins=True,
        export_all_influences=False,
        export_influence_nb=4,         # engines truncate >4 silently
        export_morph=True,             # blendshapes (ARKit names pass through)
        export_morph_normal=True,
        export_texcoords=True,
        export_normals=True,
        use_selection=False,
    )
    # Filter against this Blender's exporter signature (params drift across versions).
    available = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    dropped = [k for k in kwargs if k != "filepath" and k not in available]
    if dropped:
        log(f"gltf exporter: dropping unsupported params {dropped}")
    kwargs = {k: v for k, v in kwargs.items() if k == "filepath" or k in available}
    bpy.ops.export_scene.gltf(**kwargs)
    size = os.path.getsize(out_path)
    log(f"exported {out_path} ({size} bytes)")


# --------------------------------------------------------------------------- #
# commands
# --------------------------------------------------------------------------- #

def cmd_import_normalize(args) -> None:
    clean_scene()
    objs = import_asset(args.input)
    normalize(objs)
    export_glb(args.output)
    print(f"OK import-normalize {args.input} -> {os.path.abspath(args.output)}")


def setup_render(scene, res: int, samples: int) -> None:
    # EEVEE ('BLENDER_EEVEE_NEXT' since 4.2; plain 'BLENDER_EEVEE' before)
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = samples
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"


def setup_world(neutral_strength: float = 0.35) -> None:
    world = bpy.data.worlds.new("TurnaroundWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.9, 0.9, 0.9, 1.0)  # neutral gray env light
        bg.inputs[1].default_value = neutral_strength
    bpy.context.scene.world = world


def apply_clay_material(objs: list, force: bool) -> None:
    """Neutral mid-gray clay on meshes with no material (or all, if force).

    White/absent basecolors blow out under the neutral rig; mid-gray keeps
    form shading readable for ComfyUI img2img and LoRA reference sets.
    """
    clay = bpy.data.materials.new("TurnaroundClay")
    clay.use_nodes = True
    bsdf = clay.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.6
    for obj in geometry_objects(objs):
        if force:
            obj.data.materials.clear()
        if not obj.data.materials:
            obj.data.materials.append(clay)
            log(f"clay material assigned to {obj.name}")


def build_camera_rig(center: Vector, max_dim: float):
    """Pivot empty at asset center; camera + 3-point lights parented to it.

    Rotating the pivot orbits camera AND lights together, so every view is
    identically lit — what LoRA training sets want.
    """
    scene = bpy.context.scene

    pivot = bpy.data.objects.new("TurnaroundPivot", None)
    pivot.location = center
    scene.collection.objects.link(pivot)

    cam_data = bpy.data.cameras.new("TurnaroundCam")
    cam_data.lens = 50.0
    cam = bpy.data.objects.new("TurnaroundCam", cam_data)
    dist = max(max_dim * 2.0, 0.5)
    cam.location = Vector((0.0, -dist, 0.0))  # relative to pivot after parenting
    scene.collection.objects.link(cam)
    cam.parent = pivot
    track = cam.constraints.new(type="TRACK_TO")
    track.target = pivot
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    scene.camera = cam

    def add_light(name, kind, energy, loc, size=None):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        if size is not None and hasattr(data, "size"):
            data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        scene.collection.objects.link(obj)
        obj.parent = pivot
        c = obj.constraints.new(type="TRACK_TO")
        c.target = pivot
        c.track_axis = "TRACK_NEGATIVE_Z"
        c.up_axis = "UP_Y"
        return obj

    # Neutral 3-point rig, scaled to the asset (area lights, watts scale ~ dist^2)
    w = 120.0 * dist * dist
    add_light("Key", "AREA", w, Vector((-dist, -dist, dist * 0.8)), size=max_dim)
    add_light("Fill", "AREA", w * 0.3, Vector((dist, -dist, dist * 0.4)), size=max_dim * 1.5)
    add_light("Rim", "AREA", w * 0.6, Vector((0.0, dist, dist * 0.9)), size=max_dim)
    return pivot


def cmd_turnaround(args) -> None:
    clean_scene()
    objs = import_asset(args.input)
    if not args.no_normalize:
        normalize(objs)

    lo, hi = world_bbox(objs)
    center = (lo + hi) / 2.0
    max_dim = max(hi - lo)

    outdir = os.path.abspath(args.outdir)
    os.makedirs(outdir, exist_ok=True)

    scene = bpy.context.scene
    setup_render(scene, args.res, args.samples)
    setup_world()
    apply_clay_material(objs, force=args.clay)
    pivot = build_camera_rig(center, max_dim)

    views = []
    for i in range(args.views):
        yaw_deg = 360.0 * i / args.views
        pivot.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
        bpy.context.view_layer.update()
        filename = f"view_{i:02d}_yaw{int(round(yaw_deg)):03d}.png"
        scene.render.filepath = os.path.join(outdir, filename)
        bpy.ops.render.render(write_still=True)
        if not os.path.isfile(scene.render.filepath):
            die(f"render did not produce {scene.render.filepath}")
        log(f"rendered {filename}")
        views.append({"index": i, "yaw_deg": yaw_deg, "file": filename})

    manifest = {
        "source": os.path.abspath(args.input),
        "normalized": not args.no_normalize,
        "resolution": args.res,
        "samples": args.samples,
        "engine": scene.render.engine,
        "bbox_meters": {"size": list(hi - lo), "min": list(lo), "max": list(hi)},
        "views": views,
    }
    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"OK turnaround {args.views} views -> {outdir}")


# --------------------------------------------------------------------------- #
# entry
# --------------------------------------------------------------------------- #

def main() -> None:
    try:
        argv = sys.argv[sys.argv.index("--") + 1:]
    except ValueError:
        die("no arguments after '--' (see module docstring for usage)")

    parser = argparse.ArgumentParser(prog="blender_worker.py")
    sub = parser.add_subparsers(dest="command", required=True)

    p_norm = sub.add_parser("import-normalize", help="import + normalize + export GLB")
    p_norm.add_argument("input")
    p_norm.add_argument("output")
    p_norm.set_defaults(func=cmd_import_normalize)

    p_turn = sub.add_parser("turnaround", help="orbit renders for the 2D pipeline")
    p_turn.add_argument("input")
    p_turn.add_argument("outdir")
    p_turn.add_argument("--views", type=int, default=8)
    p_turn.add_argument("--res", type=int, default=1024)
    p_turn.add_argument("--samples", type=int, default=16)
    p_turn.add_argument("--no-normalize", action="store_true",
                        help="render the asset as-imported (skip normalize)")
    p_turn.add_argument("--clay", action="store_true",
                        help="replace ALL materials with neutral gray clay "
                             "(material-less meshes get clay automatically)")
    p_turn.set_defaults(func=cmd_turnaround)

    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
