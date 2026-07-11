---
name: blender-bridge
description: Blender as a headless asset factory — import/normalize purchased or generated 3D assets, export engine-clean glTF for Godot/Unity, batch-render turnarounds for the 2D pipeline, and drive Blender from agents. Use for any Blender task, any "get this 3D asset into the engine" request, and NAS asset-bundle work.
---

# Blender Bridge

Install of record: **Blender 4.3** at `D:\Blender Foundation\Blender 4.3\`.
Purchased addons/assets: NAS `\\DXP4800PLUS-A79\NoxDev\` (`blender-tools-and-assets\`,
`superhive-creature-character-bundle\` — includes **Faceit** (ARKit-52 facial rigging)
and **Blaze Puppeteer** (posing/animation); NOT yet installed into 4.3 — install from
the NAS zips before relying on them).

## Headless batch pattern (the workhorse)

```
blender -b [file.blend] -P script.py -- [args]     # -b headless, args after --
```

`pip install bpy` wheels exist (py3.11) for worker services — prefer plain
`blender -b` for batch (deterministic, no version skew). Scripts read args via
`sys.argv[sys.argv.index("--")+1:]`.

Core recipes (bpy):
- **Import anything**: `bpy.ops.import_scene.fbx/obj/gltf(filepath=...)` — then
  normalize: apply transforms (`bpy.ops.object.transform_apply`), set scale so
  1 unit = 1 meter, origin to bottom-center for props / feet for characters.
- **Turnaround renders** (feeds ComfyUI img2img / LoRA training): fixed camera
  rig at 8–12 yaw angles, neutral HDRI, `bpy.context.scene.render.film_transparent
  = True` for alpha, render 1024². One asset → training/reference set.
- **Asset library indexing**: `obj.asset_mark()` + catalog files to make the NAS
  bundles searchable from Blender's Asset Browser.

## Engine-clean glTF export (the part that's usually messy)

`bpy.ops.export_scene.gltf(...)` settings that import cleanly:

- `export_format='GLB'` (single file), `export_yup=True` (both engines are Y-up).
- **Apply modifiers** (`export_apply=True`) — else engines see the base mesh.
- Materials: Principled BSDF ONLY — anything else flattens or vanishes. Bake
  procedural/node materials to textures first (Cycles bake: basecolor/normal/
  roughness-metallic; ORM packing for glTF).
- Rigs: ≤4 bone influences per vertex (`export_influence_nb=4`, engines truncate
  extras silently → skinning glitches); root bone at origin; NO bone scale keys
  (Godot mangles them — use location/rotation).
- Blendshapes: `export_morph=True` + normals; name shape keys with ARKit names
  when they'll drive facial anim (Faceit outputs these).
- Animations: `export_anim_single_armature=True`, push each action as its own
  glTF animation (NLA tracks), 30fps bake for mixed-rate sources.

**Godot import**: .glb drops into the project; set import preset — meshes:
generate LODs off for stylized; materials → "Keep" to allow Godot material
overrides; animations import as `AnimationLibrary`. Scale mismatch = forgot
transform_apply.
**Unity import**: prefer glTF via **UnityGLTF or glTFast** package (FBX round-trip
loses Principled fidelity); humanoid rigs → set Avatar to Humanoid + verify
T-pose; blendshapes arrive as BlendShapes on SkinnedMeshRenderer.

## Agent driving (interactive work)

- **Official Blender MCP server** (Blender 5.1+, blender.org/lab/mcp-server) for
  agent-driven scene work — prefer once we move to 5.x; on 4.3 use
  ahujasid/blender-mcp (community, works, has PolyHaven hooks).
- Keep BATCH work as plain bpy scripts — faster, deterministic, no LLM loop.

## Pipeline fits

- Generated meshes (TRELLIS.2 GLB) → import → normalize → re-export = engine-clean
  version of a raw AI mesh (fixes scale/origin/material bindings).
- Auto-rig: SkinTokens/UniRig output → import GLB → verify weights → export with
  the rig rules above.
- Render-to-2D: NAS bundle asset or Daz export → turnaround renders → ComfyUI
  img2img with project style → 2D sprite set (see daz-bridge for the Daz leg,
  asset-reuse rung 3 for when to do this).

Status notes (2026-07): no bpy worker service exists yet (Phase 6 roadmap item);
recipes above are the validated-in-community patterns to build it from.
