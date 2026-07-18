# GIMP Bridge

Headless, script-driven **GIMP** image ops for the asset pipeline — wired the same
way `blender-bridge` and `daz-bridge` are: shell out to the DCC, degrade
gracefully when it isn't installed (an honest `{ok:false,error}`, never a fake
success).

GIMP has no importable module; the bridge drives GIMP's batch mode
(`gimp -i -b '<script-fu>'`). The **script-fu builder is pure + unit-tested**
(`_selftest_gimp.py`, 22 checks); execution needs **GIMP 2.10+** with
`gimp-console` on PATH (or a standard Windows install dir — auto-detected).

## Ops (chosen for game-asset work ComfyUI/sharp don't cover as cleanly)

**12 ops.** The core four:

```bash
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py scale   in.png out.png --width 64 --height 64 --interp none
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py indexed in.png out.png --colors 16 --dither none
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py flatten in.xcf out.png
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py convert in.png out.webp
```

- **scale** — resize with `--interp none` for **pixel-art-safe** nearest scaling (or linear/cubic).
- **indexed** — reduce to a tight **game palette** (`--colors`, optimal palette, optional Floyd dither).
- **flatten** — flatten a layered **XCF/PSD** to a single layer.
- **convert** — pure re-encode by output extension.

Adjust / effect ops (added 2026-07-18, clean-room from the ops a GIMP-3 MCP gateway
exposed; all validated live on GIMP 2.10):

```bash
python3 …/gimp_bridge.py brightness-contrast in.png out.png --brightness 30 --contrast 15   # -127..127
python3 …/gimp_bridge.py hue-saturation      in.png out.png --hue 60 --saturation -25       # recolour a sprite/tile
python3 …/gimp_bridge.py blur    in.png out.png --radius 3      # gaussian soft-focus / glow / soft-shadow prep
python3 …/gimp_bridge.py sharpen in.png out.png --amount 0.9    # unsharp-mask crisp-up
python3 …/gimp_bridge.py rotate  in.png out.png --degrees 90    # 90/180/270 sprite variants
python3 …/gimp_bridge.py flip    in.png out.png --axis horizontal   # mirror a sprite
python3 …/gimp_bridge.py drop-shadow in.png out.png --offset-x 4 --offset-y 4 --blur 8 --opacity 60   # UI/sprite depth
python3 …/gimp_bridge.py grain   in.png out.png --amount 40     # retro film/FMV value-noise grain
python3 …/gimp_bridge.py script  in.png out.png --scriptfu '(...)'   # {IN}/{OUT} tokens — anything else
```

- **brightness-contrast / hue-saturation** — palette-mood tweaks + non-destructive sprite recolours (the `-127..127` slider range maps to GIMP 2.10's float API).
- **blur / sharpen** — `plug-in-gauss` soft-focus and `plug-in-unsharp-mask` crisp-up.
- **rotate / flip** — cheap sprite variants (quadrant rotations + mirror).
- **drop-shadow** — the bundled `script-fu-drop-shadow` for UI/sprite depth (needs alpha; `--resize` grows the canvas to fit the blur, off by default to preserve pipeline dimensions).
- **grain** — `plug-in-hsv-noise` value-channel grain for a retro film/FMV look.
- **script** — run arbitrary **script-fu** (`{IN}` / `{OUT}` substituted) for anything else.

## Install
GIMP 2.10+ ; ensure `gimp-console-2.10` (or `gimp`) is on PATH, or install to
`C:/Program Files/GIMP 2/bin` (auto-detected). Until then every op returns a
clear "GIMP not found" — the bridge is ready, the executable is the only gap.

## Status
Tooling shipped 2026-07-17 (builder + invoker + graceful degrade + probe).
**Studio surface SHIPPED 2026-07-17**: a `gimpProcess` action in the
Studio `dcc.ts` (next to blender/daz) + a `/gimp` page (op picker + result
preview), registered under the Train area.
**EXPANDED 2026-07-18** — 4 → 12 ops (adjust/effect set above), 11 → 22-check probe.
The action parses the tool's JSON result (the tool always exits 0). **VALIDATED END-TO-END 2026-07-18** on a real GIMP 2.10 install: all ops (scale /
indexed / flatten / convert) produce output. Two fixes made when GIMP was first
installed: detect a per-user AppData install (%LOCALAPPDATA%/Programs/GIMP 2/bin),
and the save procedure was `file-save` (an unbound variable — never exercised while
GIMP was absent) → corrected to `gimp-file-save`.
