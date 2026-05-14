# Animation Pipeline

Sprite animation cycles, frame interpolation, and sprite-sheet assembly. Generates temporally-phased animations (idle / walk / run / attack / hurt / death / jump / cast) by running one Z-Image-Turbo txt2img per frame with a shared seed and a phase-specific prompt suffix. Style stays consistent (shared seed + style/preset); pose changes per frame (phase prompt).

Composes the `image-pipeline` primitives (`build_zit_txt2img_workflow`, `build_zit_img2img_workflow`, `pixel_art_toolkit.make_spritesheet` / `save_gif`). `--preset` and `--style` work identically to `asset_gen.py` so animations match the rest of the project's aesthetic.

## TL;DR

```bash
python3 .claude/skills/animation-pipeline/tools/animation_gen.py {cycle|interpolate|sheet} [opts]
```

## Subcommands

### cycle — Full N-frame animation cycle

```bash
python3 .claude/skills/animation-pipeline/tools/animation_gen.py cycle \
  --type walk --direction right \
  --prompt "knight in plate armor with crimson cape" \
  --preset fantasy_rpg --style 16bit-game \
  --frame-size 256 --target-size 64 --palette endesga32 \
  --fps 8 --gif --engine both \
  -o assets/animations/knight/walk_right.png
```

Built-in cycle types and their natural frame counts:

| `--type`   | Frames | Phases                                                |
|------------|--------|-------------------------------------------------------|
| `idle`     | 4      | gentle breathing/bobbing                              |
| `walk`     | 8      | contact / recoil / passing / high — both legs         |
| `run`      | 6      | strike / recoil / flight (each leg)                   |
| `attack`   | 5      | wind-up → commit → strike → recover → reset          |
| `hurt`     | 3      | impact → stagger → recover                            |
| `death`    | 4      | hit → falling → collapse → rest                       |
| `jump`     | 5      | crouch → launch → apex → descent → land               |
| `cast`     | 4      | gather → focus → release → recover                    |

`--frames N` overrides the natural count (resamples the phase list).

Directions: `right` / `left` / `up` / `down` / `front` / `back`. Each maps to a 1-line camera/silhouette descriptor that gets prepended to every frame.

**`--use-reference`** mode: generates frame 0 via txt2img, then runs img2img against frame 0 for the remaining frames at `--denoise 0.45`. Tighter character continuity, slightly slower. Default mode is per-frame txt2img with shared seed (faster, looser character consistency but uses ZIT's batch-style determinism).

Loop flag is auto-set: `idle` / `walk` / `run` loop; `attack` / `hurt` / `death` / `jump` / `cast` are one-shots.

Output:
- `<output>.png` — sprite sheet (1 row × N columns)
- `<output>_frames/` directory (only if `--keep-frames`)
- `<output>.gif` (only if `--gif`)
- `<output>.tscn` — Godot AnimatedSprite2D with SpriteFrames resource (if `--engine godot|both`)
- `<output>.unity.json` — Unity import + AnimationClip data (if `--engine unity|both`)

### interpolate — In-between frames between two key poses

```bash
python3 .claude/skills/animation-pipeline/tools/animation_gen.py interpolate \
  --start poses/knight_idle.png --end poses/knight_attack.png \
  --frames 4 \
  --prompt "knight in plate armor mid-motion, transitional pose" \
  -o assets/animations/knight/idle_to_attack/
```

Uses img2img with a **triangular denoise curve**: low near endpoints (close to the key poses), peaks in the middle (creative latitude for mid-motion). Default range `0.30 ... 0.55`. Half-way switches reference image from `--start` to `--end` so motion blends from both directions.

Output: directory containing `frame_000.png` (start copy) → `frame_N+1.png` (end copy), with `--frames` intermediate frames in between. Run `sheet` next to assemble.

### sheet — Assemble existing per-frame PNGs

```bash
python3 .claude/skills/animation-pipeline/tools/animation_gen.py sheet \
  --input-dir hand_drawn/walk_frames/ \
  --columns 8 --anim-name walk_right --fps 8 --loop --gif \
  --engine both \
  -o assets/animations/walk_right.png
```

Use when frames came from elsewhere (Aseprite export, hand-drawn, interpolate's output). Same engine-companion emission as `cycle`.

## Cross-cutting flags

- `--preset NAME` — pixel-art preset (53 options in image-pipeline)
- `--style KEY` — named ZIT LoRA stack
- `--engine godot|unity|both|none` — engine companion files
- `--seed N` — base seed (0 = random); shared across all frames
- `--gif` — save preview .gif at the listed fps
- `--target-size`, `--palette`, `--colors`, `--dither` — pixelize post-process

## Pipeline order — character animation set

For a complete character with all standard cycles:

```bash
char="knight in plate armor with crimson cape"
preset="fantasy_rpg"
style="16bit-game"

for action in idle walk run attack hurt death jump; do
  python3 .claude/skills/animation-pipeline/tools/animation_gen.py cycle \
    --type $action --direction right \
    --prompt "$char" --preset $preset --style $style \
    --frame-size 256 --target-size 64 --palette endesga32 \
    --use-reference --fps 8 --gif --engine godot \
    -o "assets/animations/knight/${action}_right.png"
done
```

8 cycles × ~30s each ≈ 4 minutes for a complete character animation set.

For 4-direction games, repeat with `--direction left/up/down`. The shared seed (pass `--seed 12345`) keeps the character recognizable across directions.

## What NOT to do

- Don't run without `--style` or `--preset` on a styled project — frames will drift between calls
- Don't expect per-frame perfect character likeness in default mode — use `--use-reference` for that
- Don't `--vary-seed` across animation frames (no such flag — animation cycles MUST share seed for coherence)
- Don't request `--frames` significantly higher than the cycle's natural length — resampling duplicates phases, but going from 8 → 32 frames produces 4×-duplicated frames, not smooth interpolation. For smoother cycles, use `interpolate` between adjacent natural frames.

## Verification

JSON to stdout:
```json
{
  "ok": true, "subcommand": "cycle",
  "action": "walk", "direction": "right",
  "sheet": "...", "frame_count": 8, "frame_size": [64, 64],
  "fps": 8, "gif": "...",
  "engine_outputs": {"godot_tscn": "...", "unity_json": "..."}
}
```

Open the `.gif` for a visual sanity check before committing 8+ frames.
