---
name: blender-bridge
description: Blender as a headless asset factory — import/normalize purchased or generated 3D assets, export engine-clean glTF for Godot/Unity, batch-render turnarounds for the 2D pipeline, and drive Blender from agents. Use for any Blender task, any "get this 3D asset into the engine" request, and NAS asset-bundle work.
---

# Blender Bridge

Install of record: **Blender 4.3** at `D:\Blender Foundation\Blender 4.3\`.
Purchased addons/assets: NAS `\\DXP4800PLUS-A79\NoxDev\` (`blender-tools-and-assets\`,
`superhive-creature-character-bundle\`).

Installed into 4.3 (2026-07-11, verified enabled on fresh boot):
- **Faceit 2.3.71** (ARKit-52 facial rigging) — legacy addon, module `faceit`.
  Known quirk: headless file-loads fire a benign `load_pre` handler error
  (`bpy.ops.faceit.receiver_cancel not found`) — harmless; use
  `--factory-startup` for batch work to silence it.
- **RetopoFlow 4.1.9** — extension `bl_ext.user_default.retopoflow`
  (RF4 is the right variant for 4.2+; the NAS RF 3.4.4 zip targets ≤4.2).
- **Blaze Puppeteer 1.2.0** — extension `bl_ext.user_default.blaze_puppeteer`
  (use the `windows-blender-4.2-5.0` zip; 4 GB — bundles torch cu128 wheels).

Extension zips (blender_manifest.toml at root) install headless via
`bpy.ops.extensions.package_install_files(filepath=..., repo="user_default",
enable_on_install=True)`; legacy zips (bl_info) via
`bpy.ops.preferences.addon_install` + `addon_enable`. Save prefs with
`bpy.ops.wm.save_userpref()` or the enable won't persist.

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
- **Verify (look at it):** open the normalized GLB in-engine (scoped `--path .`)
  and eyeball the turnaround grid before it feeds the engine or a LoRA set — the
  manifest is not a visual gate. glTF/art bar: `skills/parity-build/STANDARDS.md`.

## bpy worker (SHIPPED 2026-07-11)

[`tools/blender_worker.py`](tools/blender_worker.py) — validated on a NAS
base-mesh (FBX in → normalized GLB out → 8×768² turnaround PNGs + manifest.json):

```
blender -b --factory-startup -P tools/blender_worker.py -- \
    import-normalize <in.(fbx|obj|gltf|glb)> <out.glb>
blender -b --factory-startup -P tools/blender_worker.py -- \
    turnaround <in> <outdir> [--views 8] [--res 1024] [--samples 16] [--clay]
```

`import-normalize`: import → apply rot/scale → power-of-ten rescale-to-meters
heuristic (plausible band 0.05–30 m, target ~1.7 m) → bottom-center origin →
GLB export per the rules above (exporter params are filtered against the
running Blender's signature, so it survives version drift).
`turnaround`: same normalize, then a pivot-parented camera + 3-point light rig
(lights orbit WITH the camera → identical lighting every view, what LoRA sets
want), EEVEE, film_transparent, RGBA PNGs + `manifest.json` (yaw/bbox/files).
`--clay` forces neutral gray clay; material-less meshes get clay automatically
(white/absent basecolor blows out otherwise).

Status notes (2026-07-11): addons installed + worker shipped/validated (above).
Remaining Phase 6 items: NAS asset-library indexing, Blender MCP wiring,
Faceit→Audio2Face chain.
