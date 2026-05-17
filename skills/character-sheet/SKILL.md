# Character Sheet

Generate a **3×3 grid of poses for one character in a single ComfyUI call**, then post-process — magenta-key the background, slice into 9 cells, tight-crop each sprite, pad to a target aspect, and save 9 individual pose PNGs. 9× cheaper and 9× faster than running `animation-pipeline` for the same set of poses, with **perfect style consistency** because all nine sprites come from the same image bytes.

## TL;DR

```bash
python3 .claude/skills/character-sheet/tools/sheet_gen.py generate \
  --character "an armored knight in a crimson cape, weathered iron plate, brown leather straps" \
  --poses idle,walk_a,walk_b,attack,hurt,death,jump_up,jump_down,cast \
  --style default-pixel \
  --cell-size 64 \
  --output-dir assets/sprites/knight/
```

Outputs (with the call above):

```
assets/sprites/knight/
  ├── _raw_sheet.png            # 3x3 grid as generated (192x192 at cell_size=64)
  ├── _sheet_keyed.png          # same grid, magenta background removed
  ├── knight_idle.png           # 64x96 (padded to 2:3 aspect)
  ├── knight_walk_a.png
  ├── knight_walk_b.png
  ├── knight_attack.png
  ├── knight_hurt.png
  ├── knight_death.png
  ├── knight_jump_up.png
  ├── knight_jump_down.png
  ├── knight_cast.png
  └── manifest.json             # if --manifest is also passed (asset-manifest format)
```

## Why this skill exists

`animation-pipeline cycle walk` generates one image per frame, takes 9× as many API calls, and even with a shared seed the per-pose prompt can drift the style slightly. For character work where you want a **fixed catalog of poses** (idle, walk_a, walk_b, attack, hurt, death, jump_up, jump_down, cast), a single 3×3 grid is dramatically better:

- **One call** instead of nine — 9× faster, 9× cheaper, 9× less to fail
- **Same image bytes** for all nine poses, so style is literally identical
- **Diffusion model sees the whole sheet at once** and can plan pose contrast (idle distinct from walk, hurt distinct from death) — animations often look "samey" when generated independently
- **One prompt to maintain** — no per-frame prompt suffix wrangling

The trade-off: 3×3 fixed layout (9 poses max, not arbitrary frame counts). For frame-by-frame walk cycles use `animation-pipeline`. For a pose **catalog**, use this.

## Subcommands

### generate — Generate a character sheet end-to-end

```bash
python3 .claude/skills/character-sheet/tools/sheet_gen.py generate \
  --character "<character description>" \
  --poses pose1,pose2,...,pose9 \
  --style <style-key> \
  --cell-size 64 \
  --output-dir <dir>
```

Required:
- `--character` — character description prompt (silhouette, colors, gear, posture, vibe)
- `--output-dir` — where outputs land

Optional:
- `--poses` — comma-separated pose list. Default: `idle,walk_a,walk_b,attack,hurt,death,jump_up,jump_down,cast`. Fewer than 9 OK; extras beyond 9 raise an error.
- `--style` — godogen `image-pipeline` style key (default: `default-pixel`)
- `--cell-size` — output sprite cell size in pixels (default: 64). Generation runs at `3 * cell_size` per dimension, then slices.
- `--aspect` — output aspect ratio for padded sprites (default: `2:3` — vertical, character-sized). Pass `1:1` for square sprites.
- `--bg` — sentinel background color name (default: `magenta` = `#FF00FF`). The skill prompts the model to use this color and then keys it out.
- `--tolerance` — background-removal color tolerance 0–100 (default: 25). Higher tolerates JPEG-style fringing; lower removes only exact matches.
- `--retries` — number of retries if the model produces fewer than 9 distinct blobs (default: 2)
- `--manifest` — path to an `assets/manifest.json` to record into (uses `asset-manifest` skill's schema)
- `--keep-raw` — keep `_raw_sheet.png` after slicing (default: keep; pass `--no-keep-raw` to delete)
- `--seed` — override the random seed (default: random per run)

### list-poses — Print the default pose catalog

```bash
python3 .claude/skills/character-sheet/tools/sheet_gen.py list-poses
```

Returns the default 9-pose catalog with a one-line phrase describing each pose used in the generation prompt.

## The prompt strategy

The generated prompt is:

> A 3x3 grid sprite sheet of `<character description>`. The sheet has 9 cells arranged in 3 rows and 3 columns. From left to right, top to bottom, the cells show: `<pose1 phrase>`, `<pose2 phrase>`, ..., `<pose9 phrase>`. All cells are full-body, same character, same lighting, same scale, same outline thickness. **The background of every cell is solid magenta (#FF00FF) — a single flat color with no gradients or texture.** Pixel art, consistent palette across all cells. The character is centered in each cell with comfortable headroom.

The model gets:
- A single character description (no per-pose drift)
- The full pose list in reading order (so it doesn't shuffle them)
- An explicit sentinel background (so post-processing can key it out reliably)
- Constraints on consistency (same lighting, scale, outline)

The skill validates the result by counting distinct non-magenta blobs in the rendered sheet. If fewer than 9 are found, it retries with a new seed up to `--retries` times before erroring.

## Post-processing pipeline (after generation)

1. **Magenta-key** — flood-fill or pixel-replace any pixel within `--tolerance` of `#FF00FF` with full transparency. Uses Pillow's `getdata()` for an exact-color sweep; flood-fill handles the gradient-fringe case when tolerance > 0.
2. **Slice** — split the keyed image into 9 cells by integer division (sheet width / 3, sheet height / 3). No clever blob detection — the 3×3 layout is rigid by prompt contract.
3. **Tight-crop** — for each cell, find the alpha-channel bounding box and crop to it. Sprites end up "centered on themselves" rather than on the cell center.
4. **Pad to aspect** — pad each tight-cropped sprite to the target `--aspect` (default 2:3) by adding transparent pixels equally on the shorter axis. Keeps sprite collision boxes consistent across the whole pose catalog.
5. **Save** — each cell becomes `<character_label>_<pose>.png` in `--output-dir`. The character label is derived from the first 1-2 words of `--character`.
6. **Record to manifest** (if `--manifest`) — each pose PNG is added with `kind=sprite`, `provider=character-sheet.zit`, `labels=[<char>, <pose>]`, params recording the source sheet, pose name, style, seed.

## Cardinal rules

- **Default to 9 poses (3×3).** The model is good at this layout. 2×2 or 4×4 sometimes work but degrade quickly — stick with 3×3 unless you've smoke-tested otherwise.
- **Use a sentinel background, not "transparent" or "white".** Models can't reliably generate true transparent backgrounds, and "white" collides with armor highlights. Magenta (`#FF00FF`) is the convention because it almost never occurs in natural character art.
- **Don't post-process the raw sheet manually.** If the sheet looks bad, regenerate. Trying to fix a misaligned 3×3 grid in Photoshop is more work than just rerunning with `--seed <new>`.
- **`--cell-size 64` is the sweet spot for ZIT pixel-art.** Below 32 the model loses detail; above 128 you may as well use one-image-per-pose for better individual quality.
- **Always record to the manifest.** The 9 sprites all share params (same prompt, same seed) and asset-manifest can detect that and let you regenerate the whole set with one command later.

## Files

- `tools/sheet_gen.py` — the CLI (single file).
- `SKILL.md` — this file.

## Composition

- **image-pipeline** — character-sheet *uses* image-pipeline's ComfyUI/ZIT builders directly. You don't need to run image-pipeline separately first.
- **asset-manifest** — pass `--manifest assets/manifest.json` to auto-record the 9 sprites with shared provenance.
- **provider-preflight** — before running on a tight budget, `preflight.py check --required-style <style>` confirms ComfyUI and the LoRA are ready.
- **style-anchor** — the `--character` description is your project's character contract; consider keeping it in `ASSETS.md` so future regenerations stay consistent.
- **animation-pipeline** — if you need a smooth walk cycle (more than 2 frames), use `animation-pipeline cycle walk` instead. character-sheet is for **pose catalogs**, animation-pipeline is for **frame sequences**.
- **godot-task** — the 9 output PNGs are ready to import into a Godot `AnimationPlayer` or `AnimatedSprite2D`. godot-task can scaffold the SpriteFrames resource.
