# Skeleton Rig

Render **stick-figure pose images** (OpenPose-style skeletons) from a built-in pose library or custom joint coordinates. Pair with `image-pipeline`'s `--reference` flag (img2img) to bend a character reference into any pose, OpenPose-ControlNet-style — but locally, without external services.

## TL;DR

```bash
python3 .claude/skills/skeleton-rig/tools/rig_gen.py {pose|sequence|library|custom} [opts]
```

## Why this skill exists

We don't have a true rigging primitive (no IK, no skinning, no `.fbx` export). What we have is far cheaper and 90% as useful for sprite-art: **emit a stick-figure pose image at the resolution and aspect you want**, then let ZIT img2img conform a character reference to it. Output is a sprite of your character in that pose.

This is what pixellab's "skeleton animation" feature gives you under the hood — they just render a skeleton conditioning image, then run img2img against it with controlnet-style guidance. We do the same, except free + local, with our 21-LoRA style stack.

The skill **does not call ComfyUI**. It only emits PNGs. Composing it with `image-pipeline image --reference <pose.png>` is the agent's job (or use `character-sheet` for the pose-catalog version).

## Subcommands

### library — Print the built-in pose catalog

```bash
python3 .claude/skills/skeleton-rig/tools/rig_gen.py library
```

Returns JSON with 24 named poses: `idle`, `walk_a`, `walk_b`, `run_a`, `run_b`, `attack_swing`, `attack_thrust`, `attack_overhead`, `hurt`, `death_fallen`, `jump_takeoff`, `jump_peak`, `jump_landing`, `crouch`, `cast`, `block`, `aim`, `climb`, `swim`, `sit`, `lay`, `cheer`, `wave`, `point`.

Each entry has its joint coordinates in a 100×150 reference frame; the renderer scales to whatever `--width` / `--height` you ask for.

### pose — Render one named pose

```bash
python3 .claude/skills/skeleton-rig/tools/rig_gen.py pose \
  --name walk_a \
  --width 256 --height 384 \
  -o assets/poses/walk_a.png
```

Output is a single PNG: stick figure on a transparent background. Default colors: limbs white, joints colored (head red, torso green, hands/feet blue) for downstream OpenPose-compatibility. Disable with `--mono` for plain white-on-transparent.

### sequence — Render a sequence as a spritesheet

```bash
python3 .claude/skills/skeleton-rig/tools/rig_gen.py sequence \
  --names walk_a,walk_b \
  --width 256 --height 384 \
  -o assets/poses/walk_sheet.png
```

Concatenates each named pose horizontally. Pair with `--interpolate-frames 4` to bake N interpolated frames between every pair of poses (linear joint interpolation — works fine for walk/run cycles, breaks for poses that cross limbs).

### custom — Render from explicit joint coords (JSON)

```bash
python3 .claude/skills/skeleton-rig/tools/rig_gen.py custom \
  --joints-json my_pose.json \
  --width 256 --height 384 \
  -o assets/poses/my_pose.png
```

`my_pose.json` shape:

```json
{
  "head":       [50, 12],
  "neck":       [50, 25],
  "shoulder_l": [42, 30], "shoulder_r": [58, 30],
  "elbow_l":    [38, 50], "elbow_r":    [62, 50],
  "hand_l":     [36, 70], "hand_r":     [64, 70],
  "hip":        [50, 80],
  "hip_l":      [46, 82], "hip_r":      [54, 82],
  "knee_l":     [44, 105], "knee_r":    [56, 105],
  "foot_l":     [42, 130], "foot_r":    [58, 130]
}
```

Coordinate space is **0-100 horizontal, 0-150 vertical** (relative); the renderer scales to `--width` × `--height`. Skipping a joint omits the bone segments connected to it.

## Composing with image-pipeline (the killer use case)

```bash
# 1. Get the character reference — REUSE FIRST (run skills/asset-reuse: reuse an
#    existing character, or restyle a gallery/kit one). Generate a fresh ref only
#    if rungs 1-5 can't supply it — generation is the last rung.
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type character --prompt "armored knight in crimson cape" \
  --style default-pixel --size 1K \
  -o assets/characters/knight_ref.png

# 2. Emit the pose skeleton
python3 .claude/skills/skeleton-rig/tools/rig_gen.py pose \
  --name attack_swing --width 1024 --height 1024 \
  -o assets/poses/attack_skeleton.png

# 3. img2img: knight reference + pose skeleton → knight in pose
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type character --prompt "armored knight in crimson cape, attacking" \
  --reference assets/poses/attack_skeleton.png \
  --denoise 0.7 \
  --style default-pixel --size 1K \
  -o assets/characters/knight_attack.png
```

The lower `--denoise` (0.6-0.7) preserves more of the pose skeleton; higher (0.85+) lets ZIT diverge more freely.

## Cardinal rules

- **The stick figure is a guide, not the output.** It exists so the diffusion model has a skeletal layout to follow. Don't ship the stick figure to the player.
- **Use img2img + low denoise (~0.7) for pose adherence.** Pure t2v ignores the reference; high denoise (>0.9) treats the skeleton as a faint suggestion.
- **Joint coords are abstracted to 0-100 / 0-150.** This decouples the pose definition from the output resolution. Same pose works at 64×96 or 1024×1536.
- **For walk/run cycles, use `character-sheet` first.** It's faster and cheaper (one ZIT call for 9 poses). Skeleton-rig is for **single bespoke poses** you can't get from a fixed pose catalog.

## Files

- `tools/rig_gen.py` — the CLI (single file).
- `SKILL.md` — this file.

## Composition

- **image-pipeline** — the killer combo. Skeleton → img2img → character-in-pose.
- **character-sheet** — for the standard 9 poses, character-sheet's 3×3 grid is faster + cheaper. Use this skill when you need a *specific* pose not in the catalog.
- **animation-pipeline** — for a smooth walk cycle, render two skeletons (walk_a + walk_b), interpolate frames with `sequence --interpolate-frames N`, then img2img each frame against your character. Slower than animation-pipeline's native cycle command but gives you per-frame control.
