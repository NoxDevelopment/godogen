# Inkscape Bridge

Headless, CLI-driven **vector / SVG** ops for the asset pipeline — wired the same
way `gimp-bridge`, `blender-bridge`, and `daz-bridge` are: shell out to the DCC,
degrade gracefully when it isn't installed (an honest `{ok:false,error}`, never a
fake success).

Where `gimp-bridge` covers **raster** game-asset work, this covers the **vector**
side — crisp, resolution-independent UI: icons, logos, HUD elements, app-icon /
favicon ladders, and clean SVG for engine ingestion. Vector text renders exactly
(no raster/diffusion hallucination), which is why it's the right tool for UI/UX
and marketing art.

The **CLI builder is pure + unit-tested** (`_selftest_inkscape.py`, 23 checks);
execution needs **Inkscape 1.x** with `inkscape` on PATH (or a standard install
dir — auto-detected; the console `inkscape.com` is preferred on Windows).

> **Reuse-first (`skills/asset-reuse`).** Before authoring/generating a source SVG,
> check owned/CC0 icon & UI kits (Kenney UI, NAS bundles) — this skill's job is
> often to rasterize/derive from an existing vector, not to originate one. Eyeball
> shipped icons/logos, register outputs in `asset-manifest` (stable IDs, not
> hardcoded paths) for Studio swap, and meet `skills/parity-build/STANDARDS.md`.

## Ops

```bash
python3 .claude/skills/inkscape-bridge/tools/inkscape_bridge.py png     in.svg out.png --width 256 --height 256 [--area drawing] [--background white]
python3 .claude/skills/inkscape-bridge/tools/inkscape_bridge.py pdf     in.svg out.pdf [--text-to-path]
python3 .claude/skills/inkscape-bridge/tools/inkscape_bridge.py layer   in.svg out.png --id logo [--width 128]
python3 .claude/skills/inkscape-bridge/tools/inkscape_bridge.py iconset in.svg out_dir/ [--sizes 16,32,48,64,128,256,512]
python3 .claude/skills/inkscape-bridge/tools/inkscape_bridge.py plain-svg in.svg out.svg
python3 .claude/skills/inkscape-bridge/tools/inkscape_bridge.py actions in.svg out.svg --actions "select-all;object-to-path"
```

- **png** (alias **svg2png**) — rasterise an SVG at **exact pixel** dimensions. `--area drawing` crops to the artwork bounding box (icons), `--area page` keeps the page. `--background` makes it opaque (default: transparent, ideal for UI); `--dpi` as an alternative to width/height.
- **pdf** — SVG → PDF; `--text-to-path` embeds glyphs as outlines so the PDF renders identically without the fonts (print/marketing).
- **layer** — export a **single object/layer by id** (`--export-id-only`) — isolate one HUD element / icon out of a multi-layer master SVG.
- **iconset** — one SVG → a square **app-icon / favicon ladder** (`icon-16.png … icon-512.png`); one Inkscape invocation per size (robust across 1.x point releases).
- **plain-svg** — normalise to **plain SVG** + `--vacuum-defs`, dropping Inkscape-specific cruft and unused defs so an engine / web importer gets a lean file.
- **actions** — escape hatch: run a list of Inkscape **transform** actions (object-to-path, boolean ops, …); the bridge owns the export to `out_path` via flags (the reliable Inkscape-1.x pattern — export-inside-actions is finicky across releases). Supply only transforms.

## Install
Inkscape 1.x; ensure `inkscape` is on PATH, or install to
`C:/Program Files/Inkscape/bin` (auto-detected). Until then every op returns a
clear "Inkscape not found" — the bridge is ready, the executable is the only gap.

## Provenance / status
Clean-room built from Inkscape's **public 1.x command-line interface** (documented
flags — `--export-type`, `--export-filename`, `--export-width/height`,
`--export-id`, `--actions`), **no third-party code adopted**. Grokked from a
community "gimp-inkscape" skill (the Inkscape *idea*, not its code) alongside the
`gimp-bridge` op expansion.

**VALIDATED END-TO-END 2026-07-18** on Inkscape 1.4.4: all seven ops produce real
output — png (exact px + opaque bg), layer isolation, pdf (text-to-path), plain-svg,
a 6-size iconset ladder, and actions (object-to-path turned live `<text>` into
`<path>`). Offline builder selftest: 23 checks, no Inkscape needed.
