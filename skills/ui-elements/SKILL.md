# UI Elements

Generate individual UI sprite assets — **buttons** (with hover/pressed states), **icons**, **healthbars** (frame + fill), **panels** (9-slice-ready) — at sprite resolutions appropriate for game HUDs. Wraps `image-pipeline` with curated prompts per category, post-processes outputs into clean transparent PNGs.

> **Generation is the LAST rung (`skills/asset-reuse`).** Before generating UI, check owned/CC0 UI kits first — the house shell (`ui-shell`/`nox_ui`) already ships real **Kenney CC0** 9-slice buttons/panels (rung 3), and the gallery/manifest may hold on-style elements from prior projects. Derive states via brightness/palette passes (rung 4), restyle a kit piece to the project look (rung 5), and generate only what those can't supply. Eyeball outputs on a contact sheet (not just a green `{ok:true}`), register them in `asset-manifest`, and meet `skills/parity-build/STANDARDS.md`.

## TL;DR

```bash
python3 .claude/skills/ui-elements/tools/ui_elements_gen.py {button|icon|healthbar|panel|cursor|frame} [opts]
```

## Why this skill exists

`image-pipeline` is excellent at character sprites but UI assets need different prompting: tight isolation on transparency, fixed proportions, clean edges, **and matching variants per state** (normal/hover/pressed buttons must look like the same button at three brightness levels, not three different buttons).

This skill encodes those conventions:

- Buttons emit three matched PNGs from one prompt (one ComfyUI call, then post-process brightness/saturation for hover + pressed) — guarantees state consistency.
- Icons render on a transparent background with a tight crop, sized for HUD use (64×64 default).
- Healthbars emit two matched assets (frame + fill) with the same width so they overlap pixel-perfectly.
- Panels are emitted at a power-of-2 size friendly to 9-slice import in Godot/Unity.
- Cursors are 32×32 with a clear hotspot (top-left for `arrow`, center for `crosshair`).

All categories take `--style` (any `image-pipeline` style key — pixel-art, smooth, painterly, etc.) so a single project's UI stays visually coherent.

## Subcommands

### button — Button with normal / hover / pressed states

```bash
python3 .claude/skills/ui-elements/tools/ui_elements_gen.py button \
  --label "Start Game" \
  --shape rounded \
  --color "#3a7dff" \
  --style default-pixel \
  --width 192 --height 48 \
  --output-dir assets/ui/buttons/start/
```

Outputs three PNGs in `--output-dir`:

```
button_start_normal.png       (base render)
button_start_hover.png        (+18% brightness, +10% saturation)
button_start_pressed.png      (-12% brightness, -8% saturation, 1px y-shift)
```

Shapes: `rounded`, `sharp`, `pill`, `beveled`, `glass`. Pass `--no-label` to skip text and render a blank button (good for icon buttons).

### icon — Single icon (HUD-sized, transparent BG)

```bash
python3 .claude/skills/ui-elements/tools/ui_elements_gen.py icon \
  --concept "treasure chest with gold spilling out" \
  --style default-pixel \
  --size 64 \
  --output assets/ui/icons/treasure.png
```

Auto-prompts for a centered icon on transparent background. Default 64×64; pass `--size 32` for status-bar icons, `--size 128` for skill-tree icons.

### healthbar — Matched frame + fill pair

```bash
python3 .claude/skills/ui-elements/tools/ui_elements_gen.py healthbar \
  --style "fantasy ornate gold" \
  --width 256 --height 32 \
  --output-dir assets/ui/hud/
```

Outputs:

```
healthbar_frame.png    (transparent fill area; just the frame/border art)
healthbar_fill.png     (solid fill the same width × height; intended to be drawn UNDER the frame)
```

Drive HP by clipping `healthbar_fill.png` to `width * (current_hp / max_hp)` at runtime.

### panel — 9-slice-ready panel sprite

```bash
python3 .claude/skills/ui-elements/tools/ui_elements_gen.py panel \
  --style "dark scifi UI panel with thin neon border" \
  --size 128 \
  --output assets/ui/panels/inventory_bg.png
```

Renders a square panel at power-of-2 size (default 128). Designed so Godot's `NinePatchRect.patch_margin_left/right/top/bottom = size/4` works correctly out of the box.

### cursor — Mouse cursor sprite

```bash
python3 .claude/skills/ui-elements/tools/ui_elements_gen.py cursor \
  --kind arrow \
  --style "white outline pixel art" \
  --output assets/ui/cursors/arrow.png
```

Kinds: `arrow`, `hand`, `crosshair`, `move`, `text`. Always 32×32. Hotspot conventions documented in the JSON output.

### frame — Decorative frame (window/dialog/portrait)

```bash
python3 .claude/skills/ui-elements/tools/ui_elements_gen.py frame \
  --style "ornate gold leaf flourishes" \
  --width 320 --height 240 \
  --output assets/ui/frames/portrait.png
```

Renders a rectangular decorative border. Use over any background; the center is fully transparent.

## Cardinal rules

- **One project, one `--style`.** UI cohesion comes from style consistency — pick a style and stick with it for every button/icon/panel/frame.
- **Buttons must ship as 3 matched PNGs.** Single-state buttons feel dead. The skill enforces this by always emitting normal+hover+pressed for `button`.
- **Healthbar frame + fill must be exactly the same dimensions.** Otherwise they don't align at runtime. The skill emits them as a pair to guarantee this.
- **Panels are square + power-of-2 for 9-slice compatibility.** Other shapes need custom slice margins — fine, but emit the rectangular variant via custom `image-pipeline` calls instead of this skill.
- **Cursor PNGs are always 32×32 with the hotspot baked at the conventional position.** Pass to Godot's `Input.set_custom_mouse_cursor(image, shape, hotspot)`.

## Files

- `tools/ui_elements_gen.py` — the CLI (single file).
- `SKILL.md` — this file.

## Composition

- **image-pipeline** — every subcommand here calls `image-pipeline asset_gen.py image` under the hood. To customize beyond this skill's options, call image-pipeline directly with `--type ui`.
- **ui-screens** — emits `.tscn` / Canvas-prefab scaffolds; UI elements from this skill drop into those scaffolds' placeholder slots.
- **engine-export** — for buttons/icons as Godot resources, the 9-slice panel emitted here can be wrapped with `engine-export` into a `NinePatchRect` `.tscn` (planned).
- **style-anchor** — the project's `reference.png` should be a small UI element (button or icon) so subsequent `--style` calls inherit the same UI aesthetic.
