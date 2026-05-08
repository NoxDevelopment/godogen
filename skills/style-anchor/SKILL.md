# Style Anchor

`reference.png` is **ground truth**. Every asset must match its palette, perspective, scale, and rendering style. This skill is the discipline layer on top of the [image-pipeline](../image-pipeline/SKILL.md) — what to do *before* any image generation and how to verify *after*.

## The cardinal rule

> **If you can't tell the asset came from the same project as `reference.png`, it doesn't ship.**

This bar is non-negotiable. A pretty asset that doesn't match the reference is worse than a plain asset that does, because the mismatched one breaks scene cohesion every time it appears.

## Workflow

### 1. Treat `reference.png` as immutable

- **Never overwrite it during a refine.** If the user wants a different look, they'll replace it before invoking the refine.
- **Never regenerate it because "the new one looks better."** Drift from the user's anchor is the bug.
- **Check it exists before any per-asset gen.** If not, generate it first via `--type reference` (see [visual-target.md](../godogen/visual-target.md)).

### 2. Extract the palette (one-time, at the start of every project / refine)

```bash
python3 .claude/skills/image-pipeline/tools/pixel_art_toolkit.py palettize \
  reference.png --colors 16 -o reference_palette.png
```

Open `reference_palette.png` and identify the closest built-in palette by eye:

| Reference look | Likely built-in match |
|---|---|
| Bright, saturated, ~16 colors | `pico8`, `sweetie16` |
| Muted, naturalistic, dark blues/greens | `apollo`, `journey` |
| High-contrast retro | `nes`, `c64` |
| Modern indie, nuanced | `endesga32`, `endesga64`, `resurrect64` |
| Monochrome / 4-shade | `gameboy`, `1bit`, `1bit_amber` |
| Atmospheric, smoky | `steamlords`, `nostalgia` |

If no built-in matches well, use `--colors 16` (or whatever count is appropriate) without `--palette` — the auto k-means will quantize each asset to a consistent count.

### 3. Write the anchor declaration to `ASSETS.md`

This is the contract every subsequent generation must respect:

```markdown
# Assets

**Visual anchor:** reference.png

**Palette:** endesga32 (16 colors quantized down from full reference)

**Camera angle:** top-down 90°

**Tile scale:** 16px tiles, 16px hero (1:1)

**Rendering style:** flat-shaded pixel art, hard-edge outlines, no anti-aliasing,
muted accents (red, teal, orange) on near-black road surface

**Asset call template:**
  --type {kind} --palette endesga32 --reference reference.png --pixelize --target-size 64

**Negative prompts (always include):**
  blurry, anti-aliased, smooth gradient, photo, 3D render, jpeg artifacts,
  inconsistent lighting, mismatched perspective
```

The asset planner reads this when choosing per-asset prompts.

### 4. Generate one test asset per category, verify, then batch

Don't generate the full asset set first. Verify the anchor *holds* with a single test, then scale.

```bash
# Test ONE asset of each category before generating the full set
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type sprite \
  --prompt "test: red sedan car, 4-direction sprite sheet" \
  --palette endesga32 --pixelize \
  -o test_assets/test_car.png
```

Open `test_assets/test_car.png` next to `reference.png`. Side-by-side, ask:
- Same palette? (no extra hues that aren't in reference)
- Same rendering style? (same edge sharpness, same shading style)
- Same scale? (hero-relative; if the reference has 16px buildings, the test sprite should be ≤16px)
- Same camera angle? (top-down stays top-down; no mixed perspectives)

If any answer is "no" — don't fix the test asset, fix the **prompt template**. Tweak `ASSETS.md`'s prompt template until ONE category passes, then apply the same template to the others.

### 5. Generate by category, in batches

```bash
# All vehicles in one batch — same prompt prefix, same palette, sharing style
for vehicle in "red sedan" "blue van" "yellow taxi" "green truck"; do
  python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
    --type sprite --palette endesga32 --pixelize --target-size 64 \
    --prompt "$vehicle, top-down 4-direction view, viceland city style" \
    -o "assets/sprites/${vehicle// /_}.png"
done
```

Generating a category in one shell loop (or a ComfyUI batch via the spritesheet command) keeps style locked because the surrounding context is identical.

### 6. Visual QA pass — and regenerate outliers ruthlessly

After each batch, open all of them in a contact-sheet view (drag into an image viewer's grid layout, or build one with `pixel_art_toolkit.py spritesheet`). Find the assets that read as "different" — they have:
- A color outside the palette
- Edges that are too soft or too sharp relative to the rest
- Different lighting direction
- Different scale

Regenerate those individually. **It's cheaper to throw away 2 of 16 and redo than to ship 16 inconsistent assets.**

### 7. Character/portrait specifics

Faces drift fastest. The image-pipeline auto-uses `reference.png` as img2img conditioning for `--type portrait/character/avatar`, but if the resulting face is still wonky:

- **Always include `--reference reference.png` explicitly.** The auto-detect can fail if the working dir is unusual.
- **Use the face_detailer.json workflow** for any portrait that the auto-pass produced badly (see [image-pipeline/workflows/face_detailer.json](../image-pipeline/workflows/face_detailer.json)).
- **For character-consistent faces across many sprites** (e.g. the same NPC shows up in 20 dialog frames), provide a face reference photo and use Reactor's face swap instead of relying on text prompts to "look like the same person."

### 8. Z-Image-Turbo specifics (primary model)

Z-Image-Turbo is the default backend for new generations. The pixel-art LoRA (`pixel_art_style_z_image_turbo.safetensors`) is auto-loaded by the dispatcher for any `--type` of `sprite/character/portrait/avatar/tile/tileset/item/icon/landscape/environment/ui`. Prompt template:

```
{trigger word}, {your prompt}
```

where the trigger is `pixel art sprite` / `pixel art portrait` / `pixel art scene` / `pixel art tile, seamless tileable` based on `--type`. The template is auto-applied — you write the subject only.

**ZIT prompt rules** (per the [apatero pixel-art guide](https://apatero.com/blog/z-image-turbo-pixel-art-lora-complete-guide-2025)):

- ❌ **Don't** describe the LoRA's job for it: `"pixel art, low-poly, 16-bit retro"` — redundant and confuses the LoRA
- ❌ **Don't** include photorealism words: `"realistic skin texture"`, `"natural soft lighting"`, `"ultra detailed"` — fights the LoRA
- ✅ **Do** describe the *subject* concretely: `"a knight in plate armor with a crimson cape, side view"`
- ✅ **Do** specify camera/composition once: `"side view"`, `"top-down"`, `"3/4 perspective"`
- ✅ **Do** keep prompts short: 15-30 words is the LoRA's sweet spot

**ZIT settings (auto-applied — don't override unless you know why):**

- **Steps: 8** — the model is optimized for exactly this. Going higher doesn't help.
- **CFG: 4.5** — anything above 5 introduces artifacts.
- **LoRA strength: 0.8** — sweet spot for 16-bit feel; lower (0.6) for subtler pixel-art, higher (1.0) for stronger LoRA influence.
- **Resolution: 1024×1024 native** — generate at 1024, let the pixelize post-process downscale to target grid (64px default).

## The "is this drift?" decision tree

After generating an asset, ask in order:

1. **Does it match the palette?** No → regenerate with explicit `--palette {name}` and stronger LoRA strength.
2. **Does it match the camera angle?** No → regenerate with explicit angle in prompt prefix; check `--type` is correct.
3. **Does it match the scale?** No → regenerate with `--target-size {match-existing}` to lock pixel grid.
4. **Does it look like it came from the same artist?** No → use img2img with `--reference reference.png --denoise 0.5` (lower denoise = closer to reference style).
5. **All four pass?** Ship it.

## What NOT to do

- ❌ Generate per-asset with no `--palette` — quantization is the cheapest way to enforce consistency
- ❌ "Just regenerate" without changing the prompt template — same prompt gives same drift
- ❌ Mix asset_gen calls with backend=`gemini` and backend=`comfyui` in the same project — different models, different drift; pick one
- ❌ Skip the test-asset-first step — generating 50 assets and then seeing they all drift wastes hours
- ❌ Edit `reference.png` to match the assets — that's the wrong direction; match the assets to the reference

## Verification at the scene level

Once the asset library is built, drop them into a scene per `LAYOUT.md` and screenshot. Compare to `reference.png`. Differences to flag:
- **Palette drift** — color picker shows hues outside the reference palette → regenerate offenders
- **Scale mismatch** — buildings tower over hero or vice versa → re-pixelize at correct target size
- **Perspective mismatch** — some assets are isometric while reference is top-down → category-wide regeneration
- **Lighting inconsistency** — shadows go different directions → bake the light direction into ASSETS.md template

## Integration with refine runs

When the user refines a prototype:
1. **Read `ASSETS.md`** — the contract from the original generation
2. **Re-validate the contract holds** — reference.png unchanged? palette unchanged? template unchanged? If user replaced reference.png, re-extract palette and update template
3. **Apply changes only to assets that need to change** — don't regenerate the whole library
4. **For new assets added by the refine, use the existing template** — don't invent new prompt formats
