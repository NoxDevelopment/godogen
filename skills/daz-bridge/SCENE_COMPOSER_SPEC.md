# Daz Scene Composer — JSON scene spec → posed renders from our apps

**Ask (Jesus, 2026-07-11):** generate whole posed scenes with Daz assets —
models, scenes, poses, wardrobe, environments, "other Daz Studio things" —
driven from NoxDev Studio / ml-workbench / godotsmith, for **visual novels**,
**lip-syncing**, and **animations**.

**Install of record:** `C:\Daz 3D\Applications\64-bit\DAZ 3D\DAZStudio6\DAZStudio.exe`
(Daz Studio 6, PostgreSQL CMS). Content root: `C:\Users\Public\Documents\My DAZ 3D Library`
(empty until DIM content installs land — Genesis 8.1 Starter Essentials first).

## Why this shape

Daz Studio has a full scripting engine (DazScript, ECMAScript + Dz* API,
stable since DS4). Everything the UI does is scriptable: load figures/props
by asset path, apply pose/expression/wardrobe presets, place cameras and
lights, set Iray render settings, render to PNG, headless-ish via
`DAZStudio.exe <script.dsa> -scriptArg ... -noPrompt`. So the composer is:

```
JSON scene spec ──(generator, python)──► generated .dsa ──► DAZStudio.exe ──► PNGs/frames
        ▲                                                        │
   Studio/app form or API                              renders → pipelines below
```

No Autodazzler dependency for this lane (it stays as reference for
config-driven multi-render batches); the composer generates its own script
per spec.

## Scene spec v1 (draft)

```jsonc
{
  "figures": [{
    "asset": "People/Genesis 8.1 Female/Genesis 8.1 Basic Female.duf",
    "id": "her",
    "pose": "Poses/Base Poses/Standing/Base Pose Standing A.duf",
    "expression": null,                  // optional expression preset .duf
    "wardrobe": ["path/to/outfit.duf"],  // wearables applied in order
    "position": [0, 0, 0], "rotationY": 15
  }],
  "environment": "Environments/…/set.duf",   // optional scene/set .duf
  "cameras": [
    { "name": "shot_main", "focalMM": 65, "aimAt": "her:head",
      "orbit": { "yawDeg": 20, "pitchDeg": 5, "distanceCM": 220 } }
  ],
  "lighting": "hdri:studio_neutral",      // preset name or .duf
  "render": { "width": 1024, "height": 1536, "transparent": true,
              "engine": "iray", "samples": 300, "outDir": "D:/Daz/NoxDev/renders/<job>" },
  "frames": null                           // v2: { "animPreset": …, "range": [0, 90], "fps": 30 } → image sequence
}
```

## Consumers (the point of all this)

1. **Visual novels** — godogen `visual-novel` template: character sprites
   (transparent PNG, expression variants) + backgrounds (environment renders,
   cameras only). Preset grids: same figure × N expressions × M poses.
2. **Lip-sync** — portrait-framed render → `infinitetalk-talking-photo`
   workflow (ml-workbench) + Kokoro/Orpheus/Qwen3-TTS audio → talking
   character videos. Daz gives perfect identity consistency across shots.
3. **Animations** — v2: aniMate/pose-preset animations rendered as frame
   sequences → sprite sheets (pixel pipeline) or I2V/VACE conditioning
   (`wan22-*` workflows). Also: 8-view turnarounds → character LoRA training
   sets (`training/zimage-character-lora-24gb.yaml`).

## Delivery plan

- **P0 (now):** `tools/daz_turnaround.dsa` — self-contained turnaround
  renderer (loads a figure, builds N orbit cameras + 3-point light,
  transparent Iray renders, manifest.json) parameterized via `-scriptArg`.
  No scene prep needed. Validates the whole headless loop on DS6.
- **P1:** `tools/daz_compose.py` — spec JSON → .dsa generator + runner +
  output manifest; CLI mirror of the pixeltool pattern.
- **P2:** godotsmith endpoint `POST /api/daz/compose` (spec in, render paths
  out) → Studio "Daz Scene" form (with guides/tooltips per the UX pass) +
  ml-workbench tab + MCP tool.
- **P3:** expression/pose grid presets for VN sprite sheets; animation
  frame-sequence renders.

## License note

Render-to-2D output is license-free for owned content (interactive license
only needed for shipping live 3D assets). The Daz Sales confirmation email
(drafted in noxdev-daz-licensing) is only needed for live-3D shipping.
