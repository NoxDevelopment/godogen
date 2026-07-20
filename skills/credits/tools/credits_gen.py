"""credits_gen — assemble a game's credits from asset-manifest provenance.

Merges the machine-readable asset attribution emitted by
`asset-manifest export --format credits` (grouped by license, plus LoRAs and
generation tools) with a hand-authored `credits.extra.json` (people/roles, fonts,
audio, engine, tools, special thanks) into shippable credits:

  credits.txt          plain text for the nox_ui inline Credits panel (short games)
  credits.bbcode.txt   BBCode (headings/colors) for the scrolling scene
  credits.md           human-readable draft for review
  credits.gd/.tscn     themed, auto-scrolling Credits scene (rich games)

Typography is deferred: the scene applies the project theme.tres, so the display/
body faces come from the `typography` skill — this tool never hardcodes fonts.

Subcommands
-----------
init-extra   Write a template credits.extra.json to fill in.
assemble     Merge assets-credits + extra -> the four outputs above.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


EXTRA_TEMPLATE = {
    "game_title": "",
    "studio": "NoxDev Studio",
    "roles": [
        {"role": "Design & Code", "names": ["Jesus Canez Jr."]},
    ],
    "fonts": [
        # {"name": "Cinzel", "license": "OFL-1.1", "author": "Natanael Gama",
        #  "url": "https://fonts.google.com/specimen/Cinzel"},
    ],
    "audio": [
        # {"name": "Fantasy Ambience Pack", "license": "CC-BY-4.0",
        #  "author": "Studio X", "url": "..."},
    ],
    "engine": "Godot Engine (MIT)",
    "tools": ["ComfyUI", "Z-Image-Turbo"],
    "special_thanks": [],
}


def cmd_init_extra(args) -> None:
    out = Path(args.output)
    if out.exists() and not args.force:
        raise SystemExit(f"{out} exists; pass --force to overwrite")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(EXTRA_TEMPLATE, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "wrote": str(out)}, indent=2))


def _load_json(path: str | None) -> dict:
    if not path:
        return {}
    p = Path(path)
    if not p.exists():
        raise SystemExit(f"file not found: {p}")
    return json.loads(p.read_text(encoding="utf-8"))


def _sections(assets: dict, extra: dict) -> list[tuple[str, list[str]]]:
    """Return ordered (heading, [lines]) blocks. Pure text — formatting layered on top."""
    blocks: list[tuple[str, list[str]]] = []

    # People / roles first.
    role_lines = []
    for r in extra.get("roles", []):
        names = ", ".join(r.get("names", []))
        role_lines.append(f"{r.get('role', '')}: {names}" if names else r.get("role", ""))
    if role_lines:
        blocks.append((extra.get("studio", "Credits"), role_lines))

    # Assets grouped by license (from the manifest export).
    for lic, items in (assets.get("by_license") or {}).items():
        lines = []
        for it in items:
            who = f" — {it['author']}" if it.get("author") else ""
            url = f"  {it['url']}" if it.get("url") else ""
            lines.append(f"{it.get('source', '?')}{who}"
                         f" ({it.get('count', 0)} asset(s)){url}")
        blocks.append((f"Art & Assets · {lic}", lines))

    # Fonts (from extra — typography records these).
    if extra.get("fonts"):
        lines = []
        for f in extra["fonts"]:
            who = f" — {f['author']}" if f.get("author") else ""
            lic = f" [{f['license']}]" if f.get("license") else ""
            lines.append(f"{f.get('name', '?')}{who}{lic}")
        blocks.append(("Typefaces", lines))

    # Audio (from extra).
    if extra.get("audio"):
        lines = []
        for a in extra["audio"]:
            who = f" — {a['author']}" if a.get("author") else ""
            lic = f" [{a['license']}]" if a.get("license") else ""
            lines.append(f"{a.get('name', '?')}{who}{lic}")
        blocks.append(("Music & Sound", lines))

    # Style / LoRA models (from manifest).
    if assets.get("loras"):
        blocks.append(("Style / LoRA Models", list(assets["loras"])))

    # Tools + generation providers.
    tools = list(extra.get("tools", []))
    tools += [p for p in assets.get("providers", []) if p not in tools]
    if extra.get("engine"):
        tools = [extra["engine"]] + tools
    if tools:
        blocks.append(("Built With", tools))

    if extra.get("special_thanks"):
        blocks.append(("Special Thanks", list(extra["special_thanks"])))

    return blocks


def cmd_assemble(args) -> None:
    assets = _load_json(args.assets)
    extra = _load_json(args.extra)
    outdir = Path(args.output_dir)
    outdir.mkdir(parents=True, exist_ok=True)
    title = extra.get("game_title") or "Credits"

    unlicensed = assets.get("unlicensed", [])
    blocks = _sections(assets, extra)

    # --- plain text (nox_ui inline panel) ---
    txt = [title, ""]
    for head, lines in blocks:
        txt.append(head)
        txt += [f"  {l}" for l in lines]
        txt.append("")
    (outdir / "credits.txt").write_text("\n".join(txt), encoding="utf-8")

    # --- BBCode (scrolling scene; headings + dim accent) ---
    bb = [f"[center][font_size=48]{title}[/font_size][/center]", ""]
    for head, lines in blocks:
        bb.append(f"[center][font_size=28][b]{head}[/b][/font_size][/center]")
        for l in lines:
            bb.append(f"[center]{l}[/center]")
        bb.append("")
    bbcode = "\n".join(bb)
    (outdir / "credits.bbcode.txt").write_text(bbcode, encoding="utf-8")

    # --- Markdown draft ---
    md = [f"# {title} — Credits", ""]
    if unlicensed:
        md += [f"> ⚠ {len(unlicensed)} asset(s) missing a license — fix before ship.", ""]
    for head, lines in blocks:
        md.append(f"## {head}")
        md += [f"- {l}" for l in lines]
        md.append("")
    (outdir / "credits.md").write_text("\n".join(md), encoding="utf-8")

    # --- Godot scrolling scene (script builds UI; theme cascades from theme.tres) ---
    esc = bbcode.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    theme = args.theme
    gd = f'''extends Control
## Auto-generated by the `credits` skill from asset-manifest provenance.
## Regenerate with credits_gen.py — do not hand-edit; edit credits.extra.json instead.
## Auto-scrolling credits. Back / Esc returns to the menu. Reduced-motion aware.

const CREDITS_BBCODE := "{esc}"

@onready var _scroll: ScrollContainer = $Scroll
@onready var _text: RichTextLabel = $Scroll/Text
var _speed := 40.0        # px/sec
var _auto := true

func _ready() -> void:
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.text = CREDITS_BBCODE
	# Respect the accessibility reduced-motion setting if the shell exposes it.
	if Engine.has_singleton("NoxSettings") or (get_node_or_null("/root/NoxSettings") != null):
		var s := get_node_or_null("/root/NoxSettings")
		if s and "reduced_motion" in s and s.reduced_motion:
			_auto = false

func _process(delta: float) -> void:
	if _auto:
		_scroll.scroll_vertical += int(_speed * delta)
		var maxv := int(_text.size.y - _scroll.size.y)
		if _scroll.scroll_vertical >= maxv:
			_auto = false   # settle at the end; player scrolls/backs out

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_auto = false
		if get_node_or_null("/root/NoxShell") != null:
			NoxShell.to_menu()
	elif e.is_action_pressed("ui_accept"):
		_auto = not _auto   # pause / resume the crawl
'''
    (outdir / "credits.gd").write_text(gd, encoding="utf-8")

    theme_line = f'\n[ext_resource type="Theme" path="{theme}" id="2_theme"]' if theme else ""
    theme_prop = '\ntheme = ExtResource("2_theme")' if theme else ""
    tscn = f'''[gd_scene load_steps={3 if theme else 2} format=3]

[ext_resource type="Script" path="res://credits.gd" id="1_credits"]{theme_line}

[node name="Credits" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1_credits"){theme_prop}

[node name="Scroll" type="ScrollContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 120.0
offset_top = 60.0
offset_right = -120.0
offset_bottom = -60.0

[node name="Text" type="RichTextLabel" parent="Scroll"]
layout_mode = 2
size_flags_horizontal = 3
bbcode_enabled = true
fit_content = true
'''
    (outdir / "credits.tscn").write_text(tscn, encoding="utf-8")

    print(json.dumps({
        "ok": True,
        "outputs": ["credits.txt", "credits.bbcode.txt", "credits.md",
                    "credits.gd", "credits.tscn"],
        "output_dir": str(outdir),
        "blocks": [b[0] for b in blocks],
        "unlicensed_count": len(unlicensed),
        "warning": (f"{len(unlicensed)} asset(s) missing a license — fix before ship"
                    if unlicensed else None),
    }, indent=2))


def main() -> None:
    ap = argparse.ArgumentParser(description="Assemble game credits from provenance")
    sub = ap.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("init-extra", help="Write a template credits.extra.json")
    p.add_argument("--output", default="credits.extra.json")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_init_extra)

    p = sub.add_parser("assemble", help="Merge provenance + extra into credits outputs")
    p.add_argument("--assets", help="JSON from `manifest.py export --format credits`")
    p.add_argument("--extra", help="Hand-authored credits.extra.json")
    p.add_argument("--output-dir", default="assets/ui/credits/")
    p.add_argument("--theme", help="res:// path to theme.tres for the scrolling scene")
    p.set_defaults(func=cmd_assemble)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
