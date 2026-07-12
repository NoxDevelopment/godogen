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

## Figure generations (Genesis 1 → 9): support them all

Loading is generation-agnostic — every generation ships as `.duf` and
`openFile` handles any of them, so `figures`/`environment`/`cameras`/`render`
work unchanged from Genesis 1 through Genesis 9 (incl. G9 Toon anime).
What is generation-BOUND is preset application:

- **Poses/expressions**: authored per generation (G3 pose ≠ G9 rig). DS has
  conversion paths but they're lossy. Composer rule: detect the loaded
  figure's generation (from its asset id / `data/DAZ 3D/Genesis N` payload
  path), tag pose/expression presets with their target generation in the
  spec, and **warn + skip on mismatch** rather than silently mangling.
- **Wardrobe/hair**: auto-fit crosses generations via clones — allowed, but
  the manifest records `autofit: true` so bad fits are traceable.
- **Morph packs**: strictly per-generation; same tag-and-validate rule.

Installed today (`C:\Daz 3D\Applications\Data\DAZ 3D\My DAZ 3D Library`):
G3F, G8F/M, G8.1F/M, G9, G9 Toon + poses/morphs/wardrobe/hair/environments/
light presets/shaders/**aniMate packs** (the P3 animation leg has content).
Validation matrix: one turnaround + one posed render per installed
generation before calling a generation supported.

## Consumers (the point of all this)

1. **Visual novels** — godogen `visual-novel` template: character sprites
   (transparent PNG, expression variants) + backgrounds (environment renders,
   cameras only). Preset grids: same figure × N expressions × M poses.
2. **Lip-sync** — portrait-framed render → `infinitetalk-talking-photo`
   workflow (ml-workbench) + Kokoro/Orpheus/Qwen3-TTS audio → talking
   character videos. Daz gives perfect identity consistency across shots.
3. **Videos from any Daz still (works today, zero new code)** — every
   ml-workbench video workflow takes a start image: `wan22-i2v-lightning`
   (animate the scene), the effect presets (`fx-squish`/`fx-orbit-360`/
   aging pack…), `wan22-vace-restyle` (one Daz render → anime/ghibli/
   claymation/pixel-world variants), `infinitetalk-talking-photo`
   (portrait + TTS → talking character).
4. **Animations** — v2: aniMate/pose-preset animations rendered as frame
   sequences → sprite sheets (pixel pipeline) or I2V/VACE conditioning
   (`wan22-*` workflows) — pose-perfect motion control without mocap.
   Also: 8-view turnarounds → character LoRA training sets
   (`training/` — see ml-workbench TRAINING_STUDIO_SPEC.md).

## Delivery plan

- **P0 (now):** `tools/daz_turnaround.dsa` — self-contained turnaround
  renderer (loads a figure, builds N orbit cameras + 3-point light,
  transparent Iray renders, manifest.json) parameterized via `-scriptArg`.
  No scene prep needed. Validates the whole headless loop on DS6.
- **P1 (DONE, validated 2026-07-12):** `tools/daz_compose.py` — spec JSON →
  generated .dsa → headless DS6 render → manifest.json; CLI mirror of the
  pixeltool pattern. Validated end-to-end on DS6: G8.1 Basic Female,
  2 cameras (front + 3/4 at chest height), exact 512×512 PNGs + manifest in
  `D:/Daz/NoxDev/renders/compose-test` (~12 s/view CPU Iray).
  `python tools/daz_compose.py configs/example-scene.json` (`--dry-run`
  generates the .dsa only; `--timeout`, `--content-dir`, `--daz-exe`).
  - **Implemented spec subset:** `figures[{asset,id,pose?,position,rotationY}]`,
    `environment?`, `cameras[{name,focalMM,orbit{yawDeg,pitchDeg,distanceCM}}]`,
    `lighting?` (.duf presets; `hdri:*` warns → default headlamp),
    `render{width,height,outDir}`. Missing pose/env/lighting refs are
    generation-tagged **warnings in the manifest, not hard fails**.
  - **Not yet (P2/P3):** `expression`, `wardrobe`, `aimAt`, `transparent`,
    `engine`/`samples`, `frames`.
  - **DS6 findings (beyond the turnaround's validated patterns):**
    `DzImageRenderHandler` + `renderer.render()` honors an explicit `Size`
    — this FIXES the turnaround's imageSize-not-applied issue (doRender path
    kept as fallback). `contentMgr.findFile()` can return empty in a fresh
    `-instanceName` instance right after `addContentDirectory` — resolve by
    joining the content dir directly. After `openFile`, the **first** new
    skeleton is the body; later ones are followers (G8.1F "Tear"/eyelashes),
    so transforms/bbox must target `Scene.getSkeleton(nBefore)`. G8.1 Basic
    Female's real library path is `People/Genesis 8 Female/…` (folder says
    "Genesis 8", not "8.1"). `MainWindow.close()` does not always terminate
    the process — the Python runner kills the instance if it lingers >60 s
    after the manifest lands.
- **P2:** godotsmith endpoint `POST /api/daz/compose` (spec in, render paths
  out) → Studio "Daz Scene" form (with guides/tooltips per the UX pass) +
  ml-workbench tab + MCP tool.
- **P3:** expression/pose grid presets for VN sprite sheets; animation
  frame-sequence renders.

## License note

Render-to-2D output is license-free for owned content (interactive license
only needed for shipping live 3D assets). The Daz Sales confirmation email
(drafted in noxdev-daz-licensing) is only needed for live-3D shipping.
