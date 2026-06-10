# UI Theme

Generate a project-styled Godot 4 **`theme.tres`** from the project palette, so the
[ui-screens](../ui-screens/SKILL.md) scaffolds stop rendering in Godot's default
gray theme and instead look like *this game*.

> **Why this exists:** `ui-screens` lays out title/menu/hud/inventory/dialog with
> good anchors, but a well-laid-out screen in the default theme still looks
> generic. One `theme.tres` assigned to the root Control cascades to every child —
> buttons, panels, labels, inputs, bars — giving the whole UI a coherent look
> derived from the same palette as `reference.png` (see [style-anchor](../style-anchor/SKILL.md)).

## TL;DR

```bash
python3 .claude/skills/ui-theme/tools/theme_gen.py \
  --surface "#16213e" --surface-variant "#1a2547" \
  --text "#e8e8e8" --text-dim "#9aa0b4" --accent "#e94560" \
  --corner-radius 6 \
  -o assets/ui/theme.tres
```

Then in each emitted UI `.tscn`, set the root Control's `theme` to
`res://assets/ui/theme.tres` (or set it once on an autoload UI root). Everything
inherits it — no per-control styling.

## Inputs

Pull these from the project palette (the `reference.png` colors / the GDD's art
direction — keep them consistent with style-anchor):

| Flag | What it colors |
|---|---|
| `--surface` (required) | Panel/menu background |
| `--surface-variant` | Button face (default: surface +8% lightness) |
| `--text` (required) | Primary label/button text |
| `--text-dim` | Secondary/disabled/placeholder text (default: text @55%) |
| `--accent` (required) | Highlight: pressed buttons, focus borders, caret, progress fill |
| `--corner-radius` | Roundness (default 6; use 0 for pixel/retro) |
| `--button-font-size` / `--label-font-size` | Optional font sizes |

Hover / pressed / disabled / focus shades are derived automatically — you supply
the base palette, not every state.

## What it themes

`Button` (normal/hover/pressed/disabled/focus styles + font colors),
`PanelContainer`/`Panel`, `Label`, `LineEdit` (incl. placeholder + caret),
`ProgressBar` (bg + accent fill), `CheckBox`/`CheckButton`/`OptionButton`.

## Workflow (with the other UI skills)

1. **style-anchor** — establish `reference.png` + the palette.
2. **ui-theme** (this) — generate `theme.tres` from that palette. **Once per project.**
3. **ui-screens** — scaffold the screens; assign `theme.tres` to each root Control.
4. **image-pipeline** (`--type icon` / `--type ui`) — generate the element textures
   (icons, button art) that drop into the scaffolds' `TextureRect`/`Button` slots.

Result: laid-out screens (ui-screens) + coherent styling (ui-theme) + on-style
textures (image-pipeline + style-anchor) = UI that looks designed, not defaulted.

## Notes

- **Pixel/retro games:** pass `--corner-radius 0` and a tight palette; assign a
  pixel font via the Godot editor (or the `--font` ExtResource advanced flag).
- Re-running with the same palette is deterministic — safe to regenerate.
- This is a *resource* generator, not an image generator — it costs nothing and
  needs no backend.
