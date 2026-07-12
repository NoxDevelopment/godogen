---
name: daz-bridge
description: Daz3D as a character-asset source — batch render-to-2D (the license-free path), and the Daz→Blender→glTF→engine leg for hero characters. Use for any Daz Studio task, "use our Daz library" requests, and Daz character imports to Godot/Unity.
---

# Daz Bridge

## Licensing FIRST (this decides the pipeline)

Per `noxdev-daz-licensing/ADR-001` (2026-06-27):
- **Render-to-2D = license-free** for ALL owned content (2D renders ship freely;
  no 3D data leaves the machine). This is the default path and our moat.
- **Live 3D in a shipped game**: ONLY Daz-Originals content under the
  grandfathered Indie Game Developer License (<$100k/yr), or per-SKU Interactive
  Licenses ($50/SKU) for Published-Artist content. Confirmation email to Daz
  Sales is drafted in that repo — send before shipping any live-3D Daz asset.
- When in doubt: render to 2D.

Setup status (2026-07-12): **Daz Studio 6 installed** at
`C:\Daz 3D\Applications\64-bit\DAZ 3D\DAZStudio6\DAZStudio.exe`; content at
`C:\Daz 3D\Applications\Data\DAZ 3D\My DAZ 3D Library` (G3F→G9 + poses/
wardrobe/environments/aniBlocks). [SETUP.md](SETUP.md) keeps the DIM install
steps for reference.

## Scene composer (P1, validated 2026-07-12) — the default way to render

`tools/daz_compose.py` — JSON scene spec → generated DazScript → headless DS6
render → PNGs + `manifest.json`. See [SCENE_COMPOSER_SPEC.md](SCENE_COMPOSER_SPEC.md)
for the spec schema and DS6 API findings.

```bash
python tools/daz_compose.py configs/example-scene.json          # render
python tools/daz_compose.py scene.json --dry-run                # generate .dsa only
```

Figures (with optional pose + placement), optional environment/lighting .duf,
orbit cameras (yaw/pitch/distance around the figure bbox), exact pixel sizes
(DzImageRenderHandler path — fixes the turnaround's imageSize issue). Missing
pose/env/lighting refs are warnings in the manifest, not hard fails. Script
errors: grep `Script Error` in `%APPDATA%/DAZ 3D/Studio6 [noxcompose]/log.txt`.

## Render-to-2D pipeline (default)

Purpose: character turnarounds/pose grids → ComfyUI img2img restyle → character
LoRA training (see ml-workbench/training) → infinite consistent 2D art.

1. **Batch rendering via dzscript**: launch headless-ish —
   `DAZStudio.exe <script.dsa> -scriptArg "key=value" -noPrompt`. A config-driven
   scene loop loads .duf, iterates cameras/poses/wardrobe, sets Iray settings,
   renders PNG (alpha on), quits. **Fork Autodazzler**
   (github.com/ephread/Autodazzler) — it already does exactly this batch loop.
2. Standard sets: 8-angle turnaround + 10-pose grid + expression sheet, neutral
   lighting, transparent background, 1024².
3. Feed to: `qwen-edit-instruct`/img2img for style transfer, then LoRA training
   (`training/zimage-character-lora-24gb.yaml`) — Daz gives PERFECT identity
   consistency across the training set, which is the hard part of character LoRAs.
4. Prefer Genesis 8.1 figures (ADR note: best morph/asset coverage for our library).

## Live-3D pipeline (hero characters only, license-checked)

`Daz Studio (.duf) → Diffeomorphic DAZ Importer → Blender → glTF → engine`

- **Diffeomorphic v5.1** (moving Bitbucket→GitHub `Diffeomorphic/import_daz`;
  update bookmarks — Bitbucket wikis die 2026-08-20): imports with full
  morphs/JCMs, converts rig to Rigify or keeps Daz rig.
- In Blender: decimate (Daz meshes are dense — target <60k tris for game chars),
  bake Iray-ish materials to PBR textures (Principled only), **Faceit** to
  generate ARKit-52 blendshapes for the face (enables lipsync — Audio2Face-3D
  drives these), then export per blender-bridge glTF rules (≤4 bone influences,
  no bone scale keys, morph normals on).
- Budget ~0.5–2 days/hero character (ADR estimate) — this does NOT batch.

## Fits

- asset-reuse rung 3: the Daz library is an owned kit — always check it before
  generating a character from scratch.
- Face/mime: Faceit ARKit rig + TTS audio → Audio2Face-3D → blendshape tracks →
  Godot (glTF morph animations) / Unity (BlendShapes) — the full chain is
  Phase 6 in the roadmap; landscape research on lipsync alternatives pending.

Status notes (2026-07-11): **Autodazzler cloned** (reference) at
`C:\code\ai\_vendor\Autodazzler` (v0.2.0, GPL — build-time tool only, renders
unencumbered). **[SETUP.md](SETUP.md) has the full manual install path**
(DIM → Daz Studio + Genesis 8/8.1 essentials — interactive, Jesus does this)
plus the one-time turnaround scene/preset prep and the exact batch command;
[`configs/turnaround-g81-8angle.json`](configs/turnaround-g81-8angle.json) is
the ready 8-angle config (8 named cameras, render-settings preset on entry 1).
Diffeomorphic path documented from research, validation spike pending
(ADR lists it as a ~1-day task).
