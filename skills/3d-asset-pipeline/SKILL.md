# 3D Asset Pipeline

PNG → GLB via Tripo3D, with quality presets, batch processing, and one-shot prop generation that chains image-pipeline (txt2img) → mesh → engine sidecars in a single command.

**Tripo3D is a paid API** — every `mesh` call costs 30–60¢. Use `batch` carefully; pre-budget with `asset_gen.py set_budget` (the budget gate is shared across all paid generators in the godogen stack).

## TL;DR

```bash
python3 .claude/skills/3d-asset-pipeline/tools/mesh_gen.py {mesh|batch|prop|list-presets} [opts]
```

## Subcommands

### mesh — Convert a PNG to GLB

```bash
python3 .claude/skills/3d-asset-pipeline/tools/mesh_gen.py mesh \
  --image renders/sword_hero.png \
  --quality high \
  --engine both \
  -o assets/3d/sword_hero.glb
```

Wrapper around `tripo3d.image_to_glb` with the quality preset table. Source PNG should have a clean transparent background (or solid bright color) — Tripo3D infers depth from the silhouette, so cluttered backgrounds hurt geometry quality.

Emits `<output>.glb` plus engine sidecars:
- Godot: `<output>.glb.import` — pre-emitted import descriptor (lets Godot skip the editor round-trip on first scan)
- Unity: `<output>.unity.json` — ModelImporter settings the user applies via the inspector

### batch — Many PNGs → many GLBs

```bash
# Mode 1: directory of PNGs
python3 .claude/skills/3d-asset-pipeline/tools/mesh_gen.py batch \
  --input-dir renders/props/ \
  --output-dir assets/3d/props/ \
  --quality lowpoly \
  --engine godot

# Mode 2: explicit manifest JSON
python3 .claude/skills/3d-asset-pipeline/tools/mesh_gen.py batch \
  --manifest project/3d_manifest.json \
  --quality medium
```

Manifest shape:
```json
{
  "items": [
    {"image": "in/sword.png",  "output": "out/sword.glb"},
    {"image": "in/shield.png", "output": "out/shield.glb"}
  ]
}
```

Per-item failures don't abort the batch — each gets recorded with `"ok": false`. Total cost is summed across successes.

### prop — One-shot: txt2img → mesh

```bash
python3 .claude/skills/3d-asset-pipeline/tools/mesh_gen.py prop \
  --prompt "ornate silver chalice, gemstones on stem" \
  --image-type item --image-size 1K \
  --style 16bit-game \
  --quality medium \
  --engine both \
  -o assets/3d/chalice.glb
```

Pipeline: image-pipeline `asset_gen.py image --type item` (clean prop render) → Tripo3D mesh → engine sidecars. The intermediate PNG is kept at `<output>.ref.png` so you can re-mesh at a different quality without re-rendering.

Auto-disables face-detailer (3D reconstruction doesn't need refined faces) and pixelize (Tripo3D wants the smooth high-res render). Pass `--style` / `--preset` to keep aesthetic consistent with 2D assets in the same project.

### list-presets — Show quality table

```
lowpoly  cost=40c  Game-ready under 5k tris. Best for mobile / VR / large counts.
medium   cost=30c  Default. ~20k tris. Suitable for most desktop game props.
high     cost=40c  High-poly with detailed textures. For hero props and close-ups.
ultra    cost=60c  Maximum detail. Cinematic. Slow. Don't use in bulk.
```

## Pipeline order — typical 3D-game asset batch

```bash
# 1. Generate all reference PNGs first (cheap, zero API cost on ComfyUI)
for prop in sword shield chalice torch chest; do
  python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
    --type item --prompt "$prop, ornate, fantasy, transparent background" \
    --style 16bit-game --no-face-detailer \
    -o "renders/${prop}.png"
done

# 2. Review the renders. Re-roll any bad ones. Free up to this point.

# 3. Batch mesh — costs $1.50 for 5 props at medium
python3 .claude/skills/3d-asset-pipeline/tools/mesh_gen.py batch \
  --input-dir renders/ --output-dir assets/3d/ \
  --quality medium --engine both
```

**Don't skip step 2.** Tripo3D is the expensive step. Iterating on the source PNG is free; iterating on the mesh is not.

## What NOT to do

- Don't run `batch` on a fresh image set without reviewing the PNGs first — bad sources = wasted credits
- Don't use `ultra` quality in bulk — it's for hero assets only
- Don't expect Tripo3D to recover detail from a 64×64 pixelized sprite — it needs at least 512×512 with clean alpha
- Don't `mesh` an image that already has clutter or shadows on the floor — Tripo3D will incorporate them into the mesh

## Cost guardrails

The budget file is shared with image-pipeline (`assets/budget.json`). Set a cap before bulk runs:

```bash
python3 .claude/skills/image-pipeline/tools/asset_gen.py set_budget 500   # $5.00
```

Each `mesh` call calls `check_budget(cost_cents)` and aborts if over.

## Verification

JSON to stdout includes `cost_cents` per mesh. `batch` mode includes a `total_cost_cents` sum across successful items.

```json
{
  "ok": true, "subcommand": "mesh",
  "path": "...", "cost_cents": 30, "quality": "medium",
  "engine_outputs": {"godot_import": "...", "unity_json": "..."},
  "source_image": "..."
}
```

Open the GLB in Godot or Unity (drag-drop) for a visual check before committing.
