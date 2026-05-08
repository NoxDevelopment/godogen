# Visual Target

Generate the **reference.png anchor** that locks art direction for every downstream stage (scaffold, asset planner, task agents, all per-asset image gen). This is the highest-leverage single artifact in the pipeline — invest in the prompt.

## CLI

```bash
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type reference \
  --prompt "{prompt}" \
  --size 1K --aspect-ratio 16:9 -o reference.png
```

The `--type reference` flag tells the router this is the project anchor. Subsequent character/portrait/avatar assets will img2img against this file automatically.

## Prompt — required components

Vague prompts produce generic output. Every reference prompt MUST include all six:

1. **Camera angle** — top-down, isometric, side-scrolling, third-person over-the-shoulder, first-person, pseudo-3D, etc.
2. **Time of day / lighting** — golden hour neon, overcast noon, lit-by-fire dusk, fluorescent-lit indoor, moonlit, etc.
3. **Palette description** — explicit color words (`muted ochre and teal`, `neon pink + electric blue on near-black`, `warm earth + sage green`).
4. **2-3 named visual references** — actual games or art styles. *"Like Hotline Miami's neon-noir Miami palette"*, *"Stardew Valley overhead but with Resurrect-64 palette"*, *"Risk of Rain 2's silhouette readability"*.
5. **Key gameplay moment** — peak action mid-frame, NOT a menu/title/establishing shot.
6. **HUD framing** — *"HUD visible: health bar top-left, ammo bottom-right"* etc. Anchors the camera distance.

### Template

```
Screenshot of a {genre} {2D/3D} video game. {Camera angle}. {Key gameplay moment — peak action}. {Environment details — specific objects in frame}. {Art style — palette + technique + 2-3 named visual references}. {Lighting — time of day, key light direction}. In-game camera perspective. HUD visible: {what HUD elements are on screen}. Clean digital rendering, game engine output.
```

### Examples

**Bad:** *"Cool retro top-down shooter game screenshot."*

**Good:** *"Screenshot of a top-down twin-stick shooter video game. Camera 90° straight down. Player character mid-dash through a graffiti-covered alley, three enemies firing tracer rounds toward them, muzzle flashes. Cracked concrete floor, dumpster, fire escape ladders. Hand-painted Hotline Miami neon-noir palette: hot pink + electric blue + chartreuse on near-black. Lighting: late-night sodium-vapor streetlamps casting hard cyan shadows. In-game camera perspective. HUD visible: ammo counter top-right, score top-center, dash cooldown bottom-left. Clean digital rendering, game engine output."*

## Why `--type reference`

The router treats this asset specially:
- No pixel-art post-process (the reference is a target *aesthetic*, not a final asset)
- Wider aspect ratio default if you ask for one
- Subsequent asset calls of `--type portrait`/`character`/`avatar` automatically pick up `reference.png` as their img2img conditioning input — that's the style-lock for the whole project

This image is the visual QA target — every stylistic choice you bake in here becomes a requirement downstream agents must deliver. Don't invent complexity the user didn't ask for; pick a style that serves the game, not one that looks impressive as concept art.

## Output

`reference.png` — 1K 16:9 image at the project root.

Write the art direction into `ASSETS.md` — the asset planner uses it as context when crafting individual asset prompts (not as a literal prefix):

```markdown
# Assets

**Art direction:** <the art style description>

**Palette:** <extracted from reference.png — see below>
```

## After generation: extract the palette

Immediately after `reference.png` is saved, extract the dominant palette so every subsequent pixel-art asset can lock to it:

```bash
python3 .claude/skills/image-pipeline/tools/pixel_art_toolkit.py palettize \
  reference.png --colors 16 -o reference_palette.png
```

This produces a 16-color quantized version. Open it, eyeball the colors, and either:
- Pick a built-in palette closest to it (`pico8`, `endesga32`, `sweetie16`, `resurrect64`, `apollo`, etc.) and use `--palette {name}` on subsequent calls, OR
- Note the hex codes in `ASSETS.md` and pass `--colors 16` to lock cardinality.
