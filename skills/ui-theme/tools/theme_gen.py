#!/usr/bin/env python3
"""Godot 4 Theme generator — emits a project-styled `.theme` (.tres) resource
from a palette, so the ui-screens scaffolds stop looking like default gray Godot.

The ui-screens skill lays out title/menu/hud/inventory/dialog Control trees with
sensible anchors, but they render in Godot's default theme. This tool produces a
single `theme.tres` you assign to the root Control's `theme` property (it cascades
to every child), giving the whole UI a coherent look derived from the project's
palette — the same palette as `reference.png` (see the style-anchor skill).

Generates StyleBoxFlat styles + font colors for the common controls: Button,
PanelContainer/Panel, Label, LineEdit, ProgressBar, CheckBox, HSlider.

Usage:
  python3 theme_gen.py \
    --surface "#16213e" --surface-variant "#1a2547" --text "#e8e8e8" \
    --text-dim "#9aa0b4" --accent "#e94560" \
    --corner-radius 6 --font "res://assets/fonts/main.ttf" \
    -o assets/ui/theme.tres

Pass colors as hex (#rrggbb or #rrggbbaa). Hover/pressed/disabled shades are
derived automatically from the base colors. Output: JSON to stdout, theme to -o.
"""

import argparse
import json
import sys
from pathlib import Path


# --- color helpers ---------------------------------------------------------
def hex_to_rgba(h: str) -> tuple[float, float, float, float]:
    h = h.lstrip("#")
    if len(h) == 6:
        h += "ff"
    if len(h) != 8:
        raise ValueError(f"bad hex color {h!r} (want #rrggbb or #rrggbbaa)")
    r, g, b, a = (int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4, 6))
    return (r, g, b, a)


def lighten(c, amt):  # amt in [-1,1]; +lighten, -darken
    r, g, b, a = c
    if amt >= 0:
        return (r + (1 - r) * amt, g + (1 - g) * amt, b + (1 - b) * amt, a)
    return (r * (1 + amt), g * (1 + amt), b * (1 + amt), a)


def mix(c1, c2, t):  # t=0 → c1, t=1 → c2
    return tuple(a + (b - a) * t for a, b in zip(c1, c2))


def with_alpha(c, a):
    return (c[0], c[1], c[2], a)


def color_str(c) -> str:
    return f"Color({c[0]:.4g}, {c[1]:.4g}, {c[2]:.4g}, {c[3]:.4g})"


# --- theme assembly --------------------------------------------------------
class ThemeBuilder:
    def __init__(self):
        self._subs: list[tuple[str, list[str]]] = []  # (id, lines)
        self._props: list[str] = []

    def stylebox_flat(
        self, sid: str, bg, *, radius: int, border_color=None, border_w: int = 0,
        margin=(16.0, 8.0, 16.0, 8.0), expand: int = 0,
    ) -> str:
        lines = [
            f"content_margin_left = {margin[0]}",
            f"content_margin_top = {margin[1]}",
            f"content_margin_right = {margin[2]}",
            f"content_margin_bottom = {margin[3]}",
            f"bg_color = {color_str(bg)}",
        ]
        if border_w:
            for side in ("left", "top", "right", "bottom"):
                lines.append(f"border_width_{side} = {border_w}")
            lines.append(f"border_color = {color_str(border_color)}")
        for corner in ("top_left", "top_right", "bottom_right", "bottom_left"):
            lines.append(f"corner_radius_{corner} = {radius}")
        if expand:
            for side in ("left", "top", "right", "bottom"):
                lines.append(f"expand_margin_{side} = {expand}")
        self._subs.append((sid, lines))
        return sid

    def prop(self, key: str, value: str):
        self._props.append(f"{key} = {value}")

    def render(self) -> str:
        load_steps = len(self._subs) + 1
        out = [f'[gd_resource type="Theme" load_steps={load_steps} format=3]', ""]
        for sid, lines in self._subs:
            out.append(f'[sub_resource type="StyleBoxFlat" id="{sid}"]')
            out.extend(lines)
            out.append("")
        out.append("[resource]")
        out.extend(self._props)
        out.append("")
        return "\n".join(out)


def build_theme(args) -> str:
    surface = hex_to_rgba(args.surface)
    surface_variant = hex_to_rgba(args.surface_variant) if args.surface_variant else lighten(surface, 0.08)
    text = hex_to_rgba(args.text)
    text_dim = hex_to_rgba(args.text_dim) if args.text_dim else with_alpha(text, 0.55)
    accent = hex_to_rgba(args.accent)
    radius = args.corner_radius

    btn_normal = surface_variant
    btn_hover = lighten(surface_variant, 0.10)
    btn_pressed = mix(surface_variant, accent, 0.35)
    btn_disabled = with_alpha(lighten(surface_variant, -0.15), 0.6)

    t = ThemeBuilder()
    # Button states
    s_normal = t.stylebox_flat("btn_normal", btn_normal, radius=radius)
    s_hover = t.stylebox_flat("btn_hover", btn_hover, radius=radius)
    s_pressed = t.stylebox_flat("btn_pressed", btn_pressed, radius=radius)
    s_disabled = t.stylebox_flat("btn_disabled", btn_disabled, radius=radius)
    s_focus = t.stylebox_flat(
        "btn_focus", with_alpha(accent, 0.0), radius=radius, border_color=accent, border_w=2
    )
    # Panels
    s_panel = t.stylebox_flat(
        "panel", surface, radius=radius + 2, border_color=lighten(surface, 0.12),
        border_w=1, margin=(16.0, 16.0, 16.0, 16.0),
    )
    s_lineedit = t.stylebox_flat(
        "lineedit", lighten(surface, -0.05), radius=radius,
        border_color=lighten(surface, 0.15), border_w=1, margin=(10.0, 6.0, 10.0, 6.0),
    )
    s_pb_bg = t.stylebox_flat("pb_bg", lighten(surface, -0.08), radius=radius)
    s_pb_fill = t.stylebox_flat("pb_fill", accent, radius=radius)

    # Button
    t.prop("Button/colors/font_color", color_str(text))
    t.prop("Button/colors/font_hover_color", color_str(lighten(text, 0.15)))
    t.prop("Button/colors/font_pressed_color", color_str(text))
    t.prop("Button/colors/font_disabled_color", color_str(text_dim))
    t.prop("Button/colors/font_focus_color", color_str(text))
    t.prop("Button/styles/normal", f'SubResource("{s_normal}")')
    t.prop("Button/styles/hover", f'SubResource("{s_hover}")')
    t.prop("Button/styles/pressed", f'SubResource("{s_pressed}")')
    t.prop("Button/styles/disabled", f'SubResource("{s_disabled}")')
    t.prop("Button/styles/focus", f'SubResource("{s_focus}")')
    if args.font:
        t.prop("Button/fonts/font", f'ExtResource("{args.font}")') if args.font.startswith("ExtResource") else None
    if args.button_font_size:
        t.prop("Button/font_sizes/font_size", str(args.button_font_size))

    # Panels
    t.prop("PanelContainer/styles/panel", f'SubResource("{s_panel}")')
    t.prop("Panel/styles/panel", f'SubResource("{s_panel}")')

    # Label
    t.prop("Label/colors/font_color", color_str(text))
    if args.label_font_size:
        t.prop("Label/font_sizes/font_size", str(args.label_font_size))

    # LineEdit
    t.prop("LineEdit/colors/font_color", color_str(text))
    t.prop("LineEdit/colors/font_placeholder_color", color_str(text_dim))
    t.prop("LineEdit/colors/caret_color", color_str(accent))
    t.prop("LineEdit/styles/normal", f'SubResource("{s_lineedit}")')

    # ProgressBar
    t.prop("ProgressBar/styles/background", f'SubResource("{s_pb_bg}")')
    t.prop("ProgressBar/styles/fill", f'SubResource("{s_pb_fill}")')

    # CheckBox / CheckButton font colors
    for ctrl in ("CheckBox", "CheckButton", "OptionButton"):
        t.prop(f"{ctrl}/colors/font_color", color_str(text))
        t.prop(f"{ctrl}/colors/font_hover_color", color_str(lighten(text, 0.15)))
        t.prop(f"{ctrl}/colors/font_disabled_color", color_str(text_dim))

    return t.render()


def main():
    ap = argparse.ArgumentParser(description="Generate a Godot 4 Theme (.tres) from a palette.")
    ap.add_argument("--surface", required=True, help="Base UI surface color (#rrggbb).")
    ap.add_argument("--surface-variant", default="", help="Button/raised surface (default: surface +8%).")
    ap.add_argument("--text", required=True, help="Primary text color.")
    ap.add_argument("--text-dim", default="", help="Dim/secondary text (default: text @55%).")
    ap.add_argument("--accent", required=True, help="Accent / highlight color.")
    ap.add_argument("--corner-radius", type=int, default=6)
    ap.add_argument("--font", default="", help='Optional ExtResource id for a font (advanced).')
    ap.add_argument("--button-font-size", type=int, default=0)
    ap.add_argument("--label-font-size", type=int, default=0)
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    try:
        theme = build_theme(args)
    except ValueError as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        sys.exit(1)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(theme, encoding="utf-8")
    print(json.dumps({"ok": True, "path": str(out), "controls": [
        "Button", "Panel", "PanelContainer", "Label", "LineEdit", "ProgressBar",
        "CheckBox", "CheckButton", "OptionButton",
    ]}))


if __name__ == "__main__":
    main()
