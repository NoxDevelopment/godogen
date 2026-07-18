# GIMP Bridge

Headless, script-driven **GIMP** image ops for the asset pipeline — wired the same
way `blender-bridge` and `daz-bridge` are: shell out to the DCC, degrade
gracefully when it isn't installed (an honest `{ok:false,error}`, never a fake
success).

GIMP has no importable module; the bridge drives GIMP's batch mode
(`gimp -i -b '<script-fu>'`). The **script-fu builder is pure + unit-tested**
(`_selftest_gimp.py`, 11 checks); execution needs **GIMP 2.10+** with
`gimp-console` on PATH (or a standard Windows install dir — auto-detected).

## Ops (chosen for game-asset work ComfyUI/sharp don't cover as cleanly)

```bash
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py scale   in.png out.png --width 64 --height 64 --interp none
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py indexed in.png out.png --colors 16 --dither none
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py flatten in.xcf out.png
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py convert in.png out.webp
python3 .claude/skills/gimp-bridge/tools/gimp_bridge.py script  in.png out.png --scriptfu '(...)'   # {IN}/{OUT} tokens
```

- **scale** — resize with `--interp none` for **pixel-art-safe** nearest scaling (or linear/cubic).
- **indexed** — reduce to a tight **game palette** (`--colors`, optimal palette, optional Floyd dither).
- **flatten** — flatten a layered **XCF/PSD** to a single layer.
- **convert** — pure re-encode by output extension.
- **script** — run arbitrary **script-fu** (`{IN}` / `{OUT}` substituted) for anything else.

## Install
GIMP 2.10+ ; ensure `gimp-console-2.10` (or `gimp`) is on PATH, or install to
`C:/Program Files/GIMP 2/bin` (auto-detected). Until then every op returns a
clear "GIMP not found" — the bridge is ready, the executable is the only gap.

## Status
Tooling shipped 2026-07-17 (builder + invoker + graceful degrade + 11-check
probe). **Studio surface SHIPPED 2026-07-17**: a `gimpProcess` action in the
Studio `dcc.ts` (next to blender/daz) + a `/gimp` page (op picker for
scale/indexed/flatten/convert + result preview), registered under the Train area.
The action parses the tool's JSON result (the tool always exits 0). GIMP 2.10+ on
PATH is the only remaining gap; until then the surface degrades honestly.
