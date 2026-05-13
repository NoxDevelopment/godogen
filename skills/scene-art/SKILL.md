# Scene Art

Generators for scene-level game art that goes beyond single sprites: parallax backgrounds, skyboxes, tilesets, and wide-aspect environment references. Outputs are written in Godot- and Unity-friendly naming and (when `--engine` is passed) drop companion `.tscn` / `.tres` / `.json` files that wire the PNGs into a working asset.

This skill **composes** the `image-pipeline` primitives — `comfyui_client`, `zit_styles`, `pixel_art_toolkit`, and the 53-preset `pixel_art_presets` — into scene-level workflows. Run `--preset` and `--style` here and you get the same look as your sprites.

## TL;DR

```bash
python3 .claude/skills/scene-art/tools/scene_gen.py {parallax|skybox|tileset|environment} [opts]
```

All four subcommands accept `--preset NAME` (genre/era prefab) and `--style KEY` (named ZIT LoRA stack). Lock the project's aesthetic up front and reuse it across asset types.

## Subcommands

### parallax — N layered scrolling backgrounds

```bash
python3 .claude/skills/scene-art/tools/scene_gen.py parallax \
  --prompt "sunset forest valley with distant ruins" \
  --layers 5 --width 1920 --height 1080 \
  --preset fantasy_rpg \
  --engine both \
  -o assets/backgrounds/forest_valley/
```

Produces `layer_00_sky.png` ... `layer_04_foreground.png` plus a `parallax.tscn` (Godot ParallaxBackground) and `parallax_layout.json` (Unity script data). Foreground layer gets a luminance-based alpha cut so it composites cleanly over the mid/far layers.

Layer counts supported: **3, 4, 5, 6, 7**. Higher counts split the depth bands more finely. Scroll speeds are auto-assigned (sky ~0.05, foreground ~0.95).

By default all layers share one seed for tight stylistic coherence. Pass `--vary-seed` if you want each layer's composition independently random.

### skybox — 6-cube or equirectangular panorama

```bash
# Cube faces — best for Unity 6-Sided skybox material
python3 .claude/skills/scene-art/tools/scene_gen.py skybox \
  --prompt "alien planet sky, twin moons, aurora curtains" \
  --type cube --size 1024 \
  --preset scifi --engine unity \
  -o assets/skyboxes/alien/

# Equirectangular — best for Godot PanoramaSkyMaterial / Unity Skybox/Panoramic
python3 .claude/skills/scene-art/tools/scene_gen.py skybox \
  --prompt "stormy sea horizon, dramatic clouds" \
  --type equirect --size 2048 \
  --engine godot \
  -o assets/skyboxes/storm/
```

**Honest caveat**: ZIT does **not** stitch true panoramas. Cube faces share a seed and a directional prompt but edges between adjacent faces will have visible seams. This is fine for stylized games; for photorealistic skies, use a dedicated panorama model and import the result via the same pipeline.

Cube output: `px.png / nx.png / py.png / ny.png / pz.png / nz.png` plus optional `skybox.tres` (Godot Cubemap stub — wire into a ShaderMaterial in editor; stock Godot 4 has no 6-cube sky material) and `README.md` (Unity setup steps).

Equirect output: `sky_equirect.png` plus optional `skybox.tres` (Godot PanoramaSkyMaterial — works out of the box) and `README.md`.

### tileset — seamless tile atlas + slice

```bash
python3 .claude/skills/scene-art/tools/scene_gen.py tileset \
  --prompt "stone dungeon floor and wall tiles, top-down" \
  --tile 16 --grid 4x4 \
  --preset dungeon_map \
  --slice --engine both \
  -o assets/tilesets/dungeon.png
```

Pipeline:
1. Render the full atlas at a ZIT-friendly resolution (multiple of 64, ≥ tile×grid).
2. Nearest-neighbor downscale to the exact atlas size (cols×tile × rows×tile).
3. Palette quantize via `pixel_art_toolkit.reduce_palette` using `--palette` (or the preset's `suggested_palette`).
4. If `--slice` is passed, also write each tile to `<output_stem>_tiles/tile_NNN_X_Y.png`.

Engine companions:
- Godot: `<atlas>.tres` — TileSet resource with TileSetAtlasSource ready to drop on a TileMap.
- Unity: `<atlas>.unity.json` — slice metadata for the Sprite Editor's "Grid by Cell Size" import.

Common tile sizes: **16** (NES/GB era), **32** (16-bit / Genesis), **64** (modern pixel art).

### environment — wide-aspect scene reference

```bash
python3 .claude/skills/scene-art/tools/scene_gen.py environment \
  --type forest --aspect 21:9 --size 1792 \
  --prompt "ancient ruins half-swallowed by giant tree roots" \
  --preset fantasy_rpg \
  -o assets/references/forest_ruins.png
```

Single wide-aspect PNG. Pair with `--reference path.png` for img2img against an existing project reference (keeps style locked to a previously generated anchor).

Built-in environment types: `forest`, `dungeon`, `city`, `cave`, `space`, `desert`, `ruins`, `tundra`, `swamp`, `ocean`, plus `custom` (no auto-prefix; use your own prompt).

No engine companion file — these are just textures; drop them in your project wherever scene references live.

## Cross-cutting flags

Available on all four subcommands:

- `--preset NAME` — pixel-art preset from `pixel_art_presets.py` (run `asset_gen.py list-presets` to see the 53 names)
- `--style KEY` — named ZIT LoRA stack from `zit_styles.STYLES` (e.g. `pc98`, `zx-spectrum`, `16bit-game`)
- `--seed N` — base seed; 0 = random
- `--timeout N` — ComfyUI poll timeout in seconds
- `--engine godot|unity|both|none` — engine companion file emission

For pixel-art variants of any output: `--pixelize`, `--palette`, `--colors`, `--dither`, `--target-width`/`--target-height`.

## Pipeline order — typical project

1. **Set the aesthetic**: pick one `--preset` (e.g. `fantasy_rpg`) and one `--style` (e.g. `16bit-game`). Use these on every scene-art call below so the project hangs together.
2. **Anchor reference**: `environment --type forest -o references/anchor.png`. Treat this as the visual target.
3. **Backgrounds**: `parallax --reference references/anchor.png ...` for each scrolling scene.
4. **Tilesets**: `tileset --preset <same> ...` so floor/wall colors match the parallax.
5. **Skybox** (if 3D): `skybox --type cube ...` with the same preset palette.
6. **Verify** in-engine — open the generated `.tscn` / `.tres` in Godot, or run the Unity import.

## What NOT to do

- Don't run `tileset` without a `--palette` for a pixel-art project — atlases come out looking like upscaled art photos.
- Don't expect cube-face seams to be invisible. ZIT cube skyboxes look great for stylized games; for AAA-realistic skies use a panorama-trained model.
- Don't generate every layer with `--vary-seed` unless you actually want disjoint compositions — same-seed is the default for a reason.
- Don't bypass the `--preset` / `--style` system on scene art when the rest of the project uses it. Visual continuity is the whole point.

## Verification

Each subcommand emits JSON to stdout with paths and (when applicable) engine outputs:

```json
{
  "ok": true,
  "subcommand": "parallax",
  "layer_count": 5,
  "layers": [...],
  "engine_outputs": {"godot_tscn": "...", "unity_json": "..."}
}
```

Use this to script downstream steps (e.g. an agent that runs `parallax`, parses the JSON, then immediately runs `tileset` for the floor of the same scene).
