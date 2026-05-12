# Image Pipeline

Generate game art that **matches the visual target**, with the right tool for the right asset type. Use this whenever you need to produce an image — **prefer this over any other image-generation path.**

**Primary model:** **Z-Image-Turbo** (`z_image_turbo_bf16.safetensors`) — Flux-class, 8-step sampling, paired with the `pixel_art_style_z_image_turbo.safetensors` LoRA for pixel-art games. The dispatcher auto-selects the ZIT workflow and auto-loads the pixel-art LoRA for relevant asset types (`sprite`, `character`, `portrait`, `tile`, etc.). SD/SDXL/Pony are fallback paths used only when `--checkpoint` explicitly names a non-ZIT model.

## TL;DR

```bash
python3 ${CLAUDE_SKILL_DIR}/image-pipeline/tools/asset_gen.py image \
  --type {asset-type} \
  --prompt "{description}" \
  --size 1K --aspect-ratio 1:1 \
  -o {output_path}
```

Always pass `--type`. The router picks the workflow, prefix, post-process, and (for character/portrait) reference-image conditioning. **Skipping `--type` produces generic output — that's the bug we're fixing.**

## Asset types and when to use each

| `--type` | Use for | Workflow | Post-process |
|---|---|---|---|
| `reference` | The visual-target anchor image (one per project, generated first) | txt2img wide aspect | none |
| `portrait` | Character face, NPC headshot, dialog avatar | **img2img against `reference.png`** | none |
| `character` | Full-body character sprite, hero, enemy | img2img against reference | pixelize if pixel art game |
| `avatar` | UI avatar, profile picture | img2img against reference | none |
| `sprite` | Generic game sprite (item, prop, animated) | txt2img + pixel LoRA | pixelize, palette lock |
| `tile` / `tileset` | Floor / wall / terrain tiles | seamless tiling workflow | palette lock, edge check |
| `item` / `icon` | Inventory icon, pickup sprite | txt2img item prefix | pixelize, transparent crop |
| `landscape` | Background, parallax, sky | txt2img wide aspect | palette lock if pixel art |
| `environment` | In-game scene, level vista | txt2img | optional palette lock |
| `ui` | HUD element, button, panel | txt2img with UI prefix | clean transparent edges |
| `general` | Anything that doesn't fit above | basic txt2img | none |

## Pipeline order — always

1. **Visual target first.** Generate `reference.png` at the project root with `--type reference`. Make the prompt vivid: camera angle, lighting/time-of-day, palette, 2-3 named visual references (e.g. "like Hotline Miami's neon-noir Miami palette", "isometric like Stardew Valley's overview"). Every other asset will use this as anchor.
2. **Extract palette from reference.** Run `pixel_art_toolkit.py palettize` on `reference.png` once, save the palette to `ASSETS.md`. Pass `--palette {name}` (or supply the colors as a list) to every subsequent pixel-art asset call.
3. **Generate one test asset of each kind.** Verify style matches before generating the full set. Re-prompt if it drifts.
4. **Generate the rest in batches by type.** All characters together, all tiles together, etc. — the consistent prompt prefix and reference image keep style locked.
5. **Final pass on faces.** For any portrait/avatar the face still looks off, re-run with the face-detailer workflow (see *Face Detailing* below).

## Backend selection (transparent)

- **ComfyUI** at `$COMFYUI_URL` (default `http://localhost:8188`) is the primary path. Free, fast on a local GPU, supports LoRA, IPAdapter-style img2img, batch generation.
- **Gemini fallback** kicks in only when ComfyUI is unreachable. Costs 5-15¢ per image, budget-capped via `set_budget`.
- Force a backend with `ASSET_GEN_BACKEND=gemini` (or `comfyui`) in env.

The CLI surface is identical either way — your prompt and `--type` work the same.

## ComfyUI tuning flags

```
--checkpoint {filename}      # auto-default: z_image_turbo_bf16.safetensors (ZIT)
                             # override with COMFYUI_CHECKPOINT env or --checkpoint
                             # name containing "z_image" → ZIT workflow
                             # anything else → SD/SDXL/Pony workflow
--lora {filename}            # ZIT default: pixel_art_style_z_image_turbo.safetensors
                             #              (auto for sprite/character/portrait/etc.)
                             # Mutually exclusive with --style.
--lora-strength 0.8          # ZIT pixel-art sweet spot per apatero guide
--style {key}                # Named style from zit_styles.STYLES — loads the style's LoRA stack
                             # (1 or more LoRAs), injects trigger words after the type prefix, and
                             # appends the style descriptor. See "Named styles via --style" below.
--steps {N}                  # ZIT auto: 8   |   SD auto: 25
--cfg {N}                    # ZIT auto: 4.5 |   SD auto: 7.0
--denoise 0.6                # img2img only — lower = closer to reference
--reference {path}           # explicit img2img reference (auto-detects reference.png otherwise)
```

**Z-Image-Turbo vs SD** — the dispatcher branches on the checkpoint filename:
- Filename contains `z_image` / `z-image` / `zimage` → ZIT workflow (UNETLoader + CLIPLoader[qwen_3_4b] + VAELoader[ae] + ModelSamplingFlux + FluxGuidance + 8-step KSampler)
- Anything else → SD workflow (CheckpointLoaderSimple + 25-step KSampler)

You almost never need to override the model — ZIT is the right call for nearly every game asset type on this rig.

For **portraits/characters/avatars** the router automatically uses `reference.png` as the img2img anchor if it exists. Don't override unless you have a specific reason — the whole point is style continuity.

## Z-Image-Turbo prompt structure

Per the [apatero ZIT pixel-art guide](https://apatero.com/blog/z-image-turbo-pixel-art-lora-complete-guide-2025), the pixel-art LoRA reacts to one of three trigger words:

| Trigger | When the dispatcher uses it |
|---|---|
| `pixel art sprite` | `--type sprite` / `character` / `item` / `icon` |
| `pixel art portrait` | `--type portrait` / `avatar` |
| `pixel art scene` | `--type landscape` / `environment` / `reference` |
| `pixel art tile, seamless tileable` | `--type tile` / `tileset` |

Template (auto-applied — your `--prompt` becomes the `{subject}` part):

```
{trigger}, {your prompt}, {style descriptor}
```

**Example:**

```bash
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type character \
  --prompt "a knight in plate armor with a crimson cape, side view, 4-direction sprite" \
  --palette endesga32 \
  -o assets/sprites/knight.png
```

The actual prompt sent to ZIT becomes:

```
pixel art sprite, a knight in plate armor with a crimson cape, side view, 4-direction sprite
```

LoRA auto-loaded: `pixel_art_style_z_image_turbo.safetensors` at strength 0.8.

**Avoid** photorealistic descriptors ("realistic skin texture", "natural soft lighting", "ultra detailed") in pixel-art prompts — the LoRA fights against them.

**Step count** — Z-Image-Turbo is *optimized for exactly 8 steps*. Going higher doesn't improve quality and just slows generation. CFG 4–5 is the safe range; going above 5 introduces artifacts.

**Resolution** — ZIT trains at 1024×1024 native. Other dimensions work but pixel art usually wants smaller targets anyway, so generate at 1024 and let the post-process pixelize step downscale to the target pixel grid (default 64px).

## Named styles via `--style`

For the curated set of 21 pixel-art / game-style ZIT LoRAs the user has on this rig, use `--style <key>` instead of `--lora <filename>`. The style registry (`tools/zit_styles.py`) maps each key to its LoRA stack, trigger words, and prompt descriptor — so the dispatcher injects the right text and loads the right file(s) automatically.

```bash
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type sprite \
  --prompt "a knight in plate armor with a crimson cape, side view" \
  --style zx-spectrum \
  -o assets/sprites/knight_zxs.png
```

**Pure style LoRAs** (impose an aesthetic without overriding the subject):

| Key | What it gives you |
|---|---|
| `default-pixel` | Original baseline pixel-art LoRA. Reliable default. |
| `zx-spectrum` | UK 8-bit micro: attribute clash, two-color cells, vivid yellow palette. |
| `pc98` | Japanese 80s/90s VGA anime: cyan/magenta dithered palette. |
| `16bit-game` | SNES/Genesis era. Royal blue + saturated highlights. |
| `pixel-hard` | Hard 1px outlines, no anti-aliasing. |
| `soft-pixel-8x` / `soft-pixel-512` | Soft shading inside the pixel grid. Stack at 0.5/0.5. |
| `pixel-6x6` | 6x6 pixel grid alignment. |
| `pixelart-perfect` | Sharp grid, clean palette. |
| `pixel-pix-ce` | Generic pixelated aesthetic (CreativeEdge). |
| `elusarca-detailed` | Detailed pixel art, rich color depth. |
| `aziib-pixel` | Aziib's pixel-art baseline. |
| `tartarus-pixel` | Dark fantasy pixel art (TARPIXV1). |
| `desimulate` | Stylized illustrative aesthetic. |
| `trippy-pixel` | Psychedelic surreal pixel art. |
| `kof-portrait` | King of Fighters victory-portrait composition. |
| `experimental-pixel` | Refined pixel-art experiment. |

**Concept / identity LoRAs** (these bias the *subject*, not just the style — strength clamped to 0.5 in the registry; use only when you want their concept):

| Key | What it pulls toward |
|---|---|
| `skyhill` | Sky scene; will override your subject. |
| `carrtoon-cute` | Cute mini chibi female; fights male/large subjects. |
| `sues-body` | NSFW body shape + swimwear. |

**SDXL-only style** — gated; needs an Illustrious/SDXL checkpoint:

| Key | Notes |
|---|---|
| `new-pixel-core-ill` | SDXL/Illustrious base. Pass `--checkpoint <sdxl ckpt>` to use, otherwise asset_gen.py raises with a clear message. |

`--style` and `--lora` are mutually exclusive. Programmatic listing: `from zit_styles import list_styles; list_styles()` returns all keys; `list_styles("zimage")` filters to ZIT-compatible ones.

The `tools/style_smoketest.py` driver runs every zimage style against a fixed prompt and writes a labeled contact sheet to `assets/style_smoketest/_contact_sheet.png` — useful when adding a new style to the registry. Smoketest outputs (`assets/style_smoketest*/`, `*.log`) are gitignored — see `.gitignore` in this skill for the canonical "what's tracked vs regenerable" list. Re-run the driver any time you want a fresh contact sheet (~11 min on an RTX 3090).

## Other ZIT LoRAs available (in `D:\AI\Loras\ZIT\`)

If pixel art isn't the right aesthetic, override `--lora` with a relevant style LoRA. Selection (curated):

| Aesthetic | LoRA file |
|---|---|
| Pixel art (default) | `pixel_art_style_z_image_turbo.safetensors` |
| Alternative pixel | `NewPixelCore-Z-ImageTurbo_by_VisionaryAI.safetensors`, `elusarca-pixel-art.safetensors` |
| Anime / 90s anime | `90s_anime_aesthetic_style_z_image_turbo.safetensors`, `AnimeMix_Zturbo.safetensors`, `Flat_AnimeStyle_Agino_ZImage_Clear.safetensors` |
| Stylized 3D / Pixar | `Stylized 3D ZIT_000001176.safetensors`, `Pixar style v2.1.safetensors` |
| Frazetta / Vallejo fantasy | `Frazetta_E14.safetensors`, `boris vallejo ep6-zit[borisv]-gmr.safetensors` |
| Comic book / Moebius | `comic book page style v2.1.safetensors`, `moebius-style-zit.safetensors` |
| Cyberpunk / neon noir | `retro_neon_cyberpunk_z_image_turbo.safetensors`, `neon_noir_style_z_image_turbo_000008750.safetensors` |
| Retro film / vaporwave | `Retro80sVaporwaveZ_000003000.safetensors`, `90s_anime_melancholy_style_z_image_turbo.safetensors` |
| Tarot / illustration | `tarot-card-z-image-turbo-lora.safetensors` |
| GTA-style | `gta-san-andreas-style.safetensors`, `gta6 concept z.safetensors` |

Pass via `--lora "{filename}"`; combine with `--lora-strength 0.6-1.0`. Many ZIT LoRAs are NSFW-tuned — don't auto-load those for game projects unless that's the user's brief.

## Genre presets via `--preset`

`presets/pixel_art_presets.py` ships 53 named presets (RetroDiffusion-style) that bundle a prompt prefix, a negative-extras snippet, a suggested palette, and a target pixel-grid resolution in a single flag. Use it to lock a project's aesthetic up front:

```bash
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type sprite \
  --prompt "a sturdy knight with a crimson cape" \
  --preset fantasy_rpg \
  -o assets/sprites/knight.png
```

What `--preset fantasy_rpg` does on top of your prompt:
- prepends `"16-bit fantasy RPG pixel art, rich warm colors, medieval setting,"`
- appends `"modern, sci-fi, realistic, photo"` to the negative
- sets `--palette endesga32` (if you didn't already)
- sets `--target-size 64` (if you didn't already)
- forces `--pixelize`

Explicit CLI flags always win — pass `--palette pico8 --preset fantasy_rpg` and the palette stays pico8.

`--preset` and `--style` are **orthogonal**: `--preset` shapes prompt/palette/resolution; `--style` picks the ZIT LoRA stack. Combine them freely (e.g. `--preset scifi --style pc98` for an 80s-anime sci-fi aesthetic).

Enumerate presets with `python3 .claude/skills/image-pipeline/tools/asset_gen.py list-presets`. Common picks:

| Preset | Era / Look | Palette | Res |
|---|---|---|---|
| `fantasy_rpg` | 16-bit medieval | endesga32 | 64 |
| `scifi` | Cyberpunk / neon | sweetie16 | 64 |
| `horror` | Eerie / desaturated | endesga32 | 64 |
| `painterly` | Soft brushstroke pixel | endesga64 | 96 |
| `isometric` | 3/4 dimetric | endesga32 | 128 |
| `nes_retro` | NES era | nes | 32 |
| `gameboy` | Original GB green | gameboy | 32 |
| `gba` / `gbc` | GBA / GB Color | endesga32 / sweetie16 | 64 / 32 |
| `c64` / `cga` / `1_bit` | 80s home computer | c64 / cga / 1bit | 32 / 32 / 64 |
| `low_res` | PICO-8 chunky | pico8 | 16 |
| `mc_item` / `mc_texture` | Minecraft items / blocks | mc | 16 |

## Pixel art post-process

When `--type` is `sprite`, `tile`, `tileset`, `item`, or `icon`, the toolkit auto-runs:
- `pixelize()` — nearest-neighbor downscale to a target pixel-grid size (default 64px)
- `reduce_palette()` — k-means quantize, or snap to a named palette

Override behavior:
```
--target-size 32           # finer pixel grid
--palette endesga32        # see "Built-in palettes" below
--colors 16                # cap distinct colors (with auto-detect when 0)
--dither                   # Floyd-Steinberg dithering
--pixelize                 # force pixel-art processing on a non-pixel asset type
```

### Built-in palettes (in `pixel_art_toolkit.PALETTES`)

`pico8`, `gameboy`, `nes`, `c64`, `zx`, `msx`, `cga`, `cga_red`, `1bit`, `1bit_amber`, `1bit_green`, `endesga32`, `endesga64`, `aap64`, `sweetie16`, `nostalgia`, `resurrect64`, `apollo`, `steamlords`, `journey`, `mc`.

Pick one that matches the game's pitch:
- **PICO-8 / Sweetie-16** — small, charming, retro-arcade feel
- **NES / GameBoy** — strict retro authenticity
- **ENDESGA-32 / Resurrect-64** — modern indie, nuanced shading
- **Apollo / Journey / Steamlords** — atmospheric, larger range

## Sprite sheets

```bash
python3 ${CLAUDE_SKILL_DIR}/image-pipeline/tools/asset_gen.py spritesheet \
  --prompt "warrior 16-frame run cycle, side view, consistent silhouette" \
  --frames 16 --columns 4 --frame-size 512 \
  --palette endesga32 --pixelize \
  -o assets/warrior_run.png
```

On ComfyUI, this batches all frames in a single generation pass — they share style/lighting because they share the same KSampler call. On Gemini fallback, it uses the 4×4 template trick from the old asset_gen.

## Face detailing (auto for portrait / character / avatar)

When `--type` is `portrait`, `character`, or `avatar` and the backend is Z-Image-Turbo, `asset_gen.py` now **auto-invokes** a second pass through `workflows/face_detailer.json` (SAM + YOLO mask → Z-Image inpaint → ColorMatch blend). This runs after the base txt2img completes and before any `--pixelize` post-process, so the cleaner face geometry survives the downsample.

For pixel-art runs (`--pixelize`, or asset_type in PIXEL_ART_TYPES), the detailer's hard-coded "ultra realistic face" prompt is auto-swapped for a pixel-art-friendly variant so the inpaint doesn't clash with the surrounding LoRA aesthetic.

**Opt out** with `--no-face-detailer` when you want the raw base output (e.g. for diffing whether the detailer helped, or when you're stacking your own post-process).

**One-time setup** — the detailer needs the API-format export of the workflow:
1. Open ComfyUI in the browser.
2. Load `workflows/face_detailer.json`.
3. `File > Save (API Format)`, save as `workflows/face_detailer_api.json` next to the UI version.

Until that file exists, the auto pass is a no-op (logged as `[asset_gen] face-detailer skipped: ...` and the base image is kept).

## What NOT to do

- ❌ Don't call `asset_gen.py image` without `--type` — you'll get generic output
- ❌ Don't generate `reference.png` after other assets — every asset depends on it
- ❌ Don't generate characters one-at-a-time without using `reference.png` as anchor — they'll drift
- ❌ Don't skip palette extraction for pixel art games — palette continuity is more important than per-asset polish
- ❌ Don't bypass to a raw text-to-image API when this skill is available

## Verification

After each asset generation, the JSON output includes `backend` (`comfyui` or `gemini`) and `asset_type`. If you got `backend: gemini` and didn't expect to, ComfyUI isn't reachable — investigate before committing the assets.

For pixel art assets, also verify:
- Edges are sharp (no anti-aliased halo around silhouettes)
- Colors snap to the palette (open in an editor, check histogram)
- Proportions match other assets generated with the same prompt prefix
