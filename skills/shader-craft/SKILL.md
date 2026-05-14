# Shader Craft

Godot 4 `.gdshader` and Unity ShaderLab/HLSL generators for five common game shaders with sensible defaults. Pure text emission — no ComfyUI / Tripo3D / model dependencies. Each shader ships with tuned defaults that work out of the box and a JSON cheatsheet describing exactly how to apply it in the editor.

## TL;DR

```bash
python3 .claude/skills/shader-craft/tools/shader_gen.py {water|fog|dissolve|outline|pixel-dither|list} [opts]
```

Every emit subcommand takes `--engine godot|unity`, `--target canvas_item|spatial` (where the shader has both 2D and 3D variants), and `-o output_path`.

## Shaders

### water — Animated water surface

```bash
# Godot 2D water plane
python3 .claude/skills/shader-craft/tools/shader_gen.py water \
  --engine godot --target canvas_item \
  -o assets/shaders/water_2d.gdshader

# Godot 3D water (requires PlaneMesh with subdivide >= 64 for vertex waves)
python3 .claude/skills/shader-craft/tools/shader_gen.py water \
  --engine godot --target spatial \
  -o assets/shaders/water_3d.gdshader
```

Uniforms: `color_shallow`, `color_deep`, `scroll_speed`, `ripple_amplitude`, `ripple_frequency`. The 3D variant adds `wave_height`, `wave_frequency`, `fresnel_power`.

### fog — Distance + height volumetric-ish fog

```bash
python3 .claude/skills/shader-craft/tools/shader_gen.py fog \
  --engine godot --target spatial \
  -o assets/shaders/fog.gdshader
```

3D only. Apply to a large BoxMesh surrounding the play area (or use as a WorldEnvironment fog volume material). Cheaper stylized alternative to Godot 4's built-in `FogMaterial` — good for pixel-art-styled 3D where you want chunky, controllable fog.

Uniforms: `fog_color`, `fog_density`, `fog_height`, `fog_height_falloff`, `noise_scale`, `scroll_speed`.

### dissolve — Edge-burning dissolve transition

```bash
# 2D sprite dissolve
python3 .claude/skills/shader-craft/tools/shader_gen.py dissolve \
  --engine godot --target canvas_item \
  -o assets/shaders/dissolve_2d.gdshader

# 3D mesh dissolve
python3 .claude/skills/shader-craft/tools/shader_gen.py dissolve \
  --engine godot --target spatial \
  -o assets/shaders/dissolve_3d.gdshader
```

Drive `dissolve_amount` 0→1 to dissolve (or 1→0 to materialize) via AnimationPlayer or Tween. Needs a grayscale noise texture assigned to `noise_texture`. The 3D variant emits at the edge band for a burning-glow look.

### outline — Sprite or mesh outline

```bash
# 2D pixel-perfect sprite outline (1-px dilation)
python3 .claude/skills/shader-craft/tools/shader_gen.py outline \
  --engine godot --target canvas_item \
  -o assets/shaders/outline_2d.gdshader

# 3D inverted-hull mesh outline
python3 .claude/skills/shader-craft/tools/shader_gen.py outline \
  --engine godot --target spatial \
  -o assets/shaders/outline_3d.gdshader
```

The 2D variant samples 4 neighbors — outline_width=1 gives pixel-perfect outlines on pixel-art sprites. The 3D variant uses the classic inverted-hull trick (cull_front + vertex push along normal); apply as a **second** surface_material_override on the MeshInstance3D after the regular material.

### pixel-dither — Bayer-pattern fade transparency

```bash
python3 .claude/skills/shader-craft/tools/shader_gen.py pixel-dither \
  --engine godot --target canvas_item \
  -o assets/shaders/pixel_dither.gdshader
```

For fade-in / fade-out on pixel-art sprites WITHOUT smooth alpha blending (which looks wrong at 1× scale). Drive `alpha` 0..1. Uses a 4×4 Bayer matrix sampled at screen-space pixel coords. Set `bayer_size` to 2/4/8 for chunky/medium/fine dither patterns.

### list — Enumerate everything

```bash
python3 .claude/skills/shader-craft/tools/shader_gen.py list
```

Output:
```
Available shaders:
  water          engine=godot  targets=['canvas_item', 'spatial']
  water          engine=unity  targets=['canvas_item', 'spatial']
  fog            engine=godot  targets=['spatial']
  ...
```

## Cheatsheet

Each emit subcommand prints a JSON line with a `cheatsheet` field — the exact editor steps to wire it up. Read it once per shader; the agent doesn't need to re-discover the workflow each time.

```json
{
  "ok": true, "shader": "outline", "engine": "godot", "target": "spatial",
  "path": "assets/shaders/outline_3d.gdshader", "extension": ".gdshader",
  "cheatsheet": "Inverted-hull mesh outline. Apply as a SECOND surface_material_override on MeshInstance3D (after the regular material). cull_front + vertex push gives silhouette."
}
```

## What NOT to do

- Don't write your own water shader from scratch when this one handles 90% of cases — it's faster to tune uniforms on this template than to debug your own
- Don't apply the 2D outline shader at outline_width > 1 on pixel-art sprites — it breaks pixel-perfect alignment; for thicker outlines use a larger sprite + outline_width=1
- Don't use smooth alpha fade on pixel-art sprites; that's what `pixel-dither` is for
- Don't put the 3D outline shader on the same material slot as the regular surface — it must be a separate slot
