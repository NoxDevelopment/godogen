---
name: asset-reuse
description: Reuse-first asset economy — search, adapt, and compose existing assets before generating anything new. Use at asset-plan time for every game project, and whenever an asset request looks similar to something that already exists. Encodes the classic 16-bit reuse playbook (palette swaps, mirroring, modular parts, kit-first) on top of the modern generation stack.
---

# Asset Reuse — generate LAST, not first

Fresh generation is the most expensive, least consistent way to get an asset.
Every asset request goes through this ladder; generation is the bottom rung.

## The reuse ladder (stop at the first rung that works)

1. **Already made?** — `asset-manifest` search in THIS project (`find` by label/params).
2. **Made in another project?** — ml-workbench gallery (`GET :8787/api/gallery`)
   and prior projects' `assets/manifest.json`. Import + restyle beats regenerate.
3. **Owned kit covers it?** — CC0/owned packs first (Kenney kits, NAS bundles at
   `\\DXP4800PLUS-A79\NoxDev`). Kit asset + restyle pass (rung 5) = consistent AND cheap.
4. **Derive from an existing asset** — the 16-bit playbook, all deterministic,
   all free:
   - **Palette swap** (`tools/palette_swap.py`) — enemy tiers, team colors,
     biome variants of tiles. One goblin sprite = green/frost/shadow goblin.
   - **Mirror/flip** — walk-left from walk-right; symmetric UI corners from one.
   - **9-slice** — one panel texture = every panel size (engine-export emits
     patch margins; never generate multiple panel sizes).
   - **Rotation/tint/scale instancing** — props and foliage: 1 asset + engine
     variation (random flip, ±hue, ±scale) reads as many.
   - **Modular parts (paper-doll)** — split characters into layers
     (body/outfit/hair/weapon). `qwen-layered-t2i` generates parts WITH alpha;
     recombine for outfit/equipment variants instead of regenerating characters.
   - **Tile deltas** — a tileset variant = base tile + small edits
     (`qwen-edit-instruct`: "add cracks", "add moss"), not a new set.
5. **Restyle an existing asset** — `qwen-edit-instruct` / image-pipeline
   `--reference`: keeps composition/readability, applies the project's
   VisualIdentity/style-anchor. This is how kit assets and cross-project imports
   join the project's look.
6. **Generate new** — image-pipeline (workflow-library path), then immediately:
   register in asset-manifest with rich labels, and if it's a reusable archetype
   (character base, tileset, UI kit piece), flag it for gallery promotion so
   rung 2 works for the next project.

## Rules

- **Asset-plan must show the ladder**: for each planned asset, record which rung
  sourced it. A plan where everything is rung-6 is a failed plan — expect ≥50%
  of assets from rungs 1–5 in any non-first project.
- **Variants are NEVER regenerated**: same subject, different color/size/state
  (damaged, iced, elite) → rungs 4–5 only. Regenerating a variant breaks style
  lock AND wastes GPU time.
- **Sprite animation reuses frames**: idle→blink = 2 deltas on one frame, not a
  new cycle; attack anticipation frames can mirror recovery frames. Budget
  cycles per `animation-pipeline`, don't generate per-frame from scratch.
- **Promote aggressively**: any asset used ≥2 projects belongs in the shared
  gallery with tags (`POST :8787/api/gallery` with provenance + baseModel/style
  tags). The library compounds; per-project folders don't.
- **License check at rung 3**: CC0 = free use; CC-BY = attribution file entry;
  never pull NC assets into a commercial project.

## tools/palette_swap.py

Deterministic recolor for sprites/tiles (PNG in, PNG out, alpha preserved):

```
python tools/palette_swap.py in.png out.png --mode hue --shift 120          # hue rotate
python tools/palette_swap.py in.png out.png --mode map --from "#4a8f3c,#2d5c24" --to "#7ec8e3,#3a7ca5"   # exact color remap (16-bit style)
python tools/palette_swap.py in.png out.png --mode ramp --target "#c0392b"  # remap dominant ramp to a target hue, keep value/sat structure
```

Use `--mode map` for pixel art (exact palette control), `--mode hue`/`ramp` for
painted assets.
