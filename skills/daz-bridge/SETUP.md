# Daz Bridge — one-time setup (manual steps for Jesus)

Daz Studio is **not installed** yet — only DIM at `D:\DAZ 3D\DAZ3DIM1\DAZ3DIM.exe`.
The DIM installer flow is interactive (Daz account login), so an agent can't do it.
Everything below the install section is prepared and ready.

Reminder before ANY live-3D shipping: send the Daz Sales license-confirmation
email drafted in `noxdev-daz-licensing`. Render-to-2D (this pipeline) is
license-free for all owned content.

## 1. Install Daz Studio + content via DIM (manual, ~20 min + downloads)

1. Launch `D:\DAZ 3D\DAZ3DIM1\DAZ3DIM.exe`, log in with the Daz account.
2. Advanced Settings (gear icon) → **Installation** tab → set install paths on
   D: to keep C: clean, e.g. software to `D:\DAZ 3D\` and content to
   `D:\Daz\Library\` (any path is fine — just note the content path; the
   Autodazzler scene/preset paths below assume `D:\Daz\`).
3. **Ready to Download** tab → install, in this order:
   - **DAZ Studio 4.2x Pro (64-bit)** — the app itself (free).
   - **Default Resources for DAZ Studio** (auto-selected with the app).
   - **Genesis 8 Starter Essentials** and **Genesis 8.1 Starter Essentials**
     — 8.1 figures reference Genesis 8 base content, install both.
     (ADR-001: Genesis 8.1 is our standard figure — best morph/asset
     coverage for the owned library.)
4. Launch Daz Studio once interactively (first-run registration + CMS init),
   confirm a Genesis 8.1 figure loads from Smart Content.
5. Optional but recommended for the render pipeline: also DIM-install any
   owned character/pose/wardrobe packs you want in the first batches.

Install of record once done: `D:\DAZ 3D\DAZStudio4 64-bit\DAZStudio.exe`
(adjust below if DIM put it elsewhere).

## 2. Autodazzler (batch renderer — plan of record)

Reference clone (done, 2026-07-11): `C:\code\ai\_vendor\Autodazzler`
(github.com/ephread/Autodazzler, GPL, v0.2.0 — GPL is fine here: it's a
build-time tool, its output renders are unencumbered).

Get the runnable `.dsa` either way:

- **Download** (fastest): grab the precompiled `Autodazzler.dsa` from
  https://github.com/ephread/Autodazzler/releases (v0.2.0) and save it as
  `C:\code\ai\_vendor\Autodazzler\dist\Autodazzler.dsa`.
- **Build from the clone**: `cd C:\code\ai\_vendor\Autodazzler && npm install
  && npm run build` (rollup emits the bundled script; put/rename the output at
  `dist\Autodazzler.dsa`).

## 3. One-time scene + preset prep (in Daz Studio, ~15 min)

Autodazzler switches **named cameras** per render, so the 8-angle turnaround
is a scene with 8 cameras — no pose gymnastics needed:

1. New scene → load a Genesis 8.1 figure (or a full dressed character), feet
   at origin, neutral A/T-pose.
2. Create 8 cameras named `cam_yaw000, cam_yaw045, … cam_yaw315`, orbited
   around the figure at 45° steps, equal distance, aimed at chest height
   (frame full body with a small margin; ~65 mm focal keeps proportions).
   Fastest way: one camera framed right, then duplicate + rotate its parent
   null by 45° each time.
3. Render Settings: Iray, 1024×1024, transparent background
   (Environment → Dome and Scene OFF / draw dome off, PNG with alpha),
   headlamp off, neutral 3-point or HDRI lighting parented into the scene so
   every camera sees the same light.
4. Save as scene: `D:\Daz\NoxDev\scenes\turnaround-g81.duf`.
5. Save the render settings as a Render Settings preset:
   `D:\Daz\NoxDev\presets\NoxDev_Turnaround_RenderSettings.duf`.

For new characters later: open the scene, swap/dress the figure, save under a
new name, point the config's `scenePath` at it. Pose grids and expression
sheets are the same trick with pose/expression **presets** per render entry
(`"presets": [{ "Genesis 8.1 Female": "path/to/pose.duf" }]`).

## 4. Run the batch (headless-ish)

Config (checked in): [`configs/turnaround-g81-8angle.json`](configs/turnaround-g81-8angle.json)
— 8 renders, one per camera, render-settings preset applied on the first
entry (it sticks for the rest of the scene). Copy it anywhere, fix paths if
your content lives elsewhere. **All paths in the config use forward slashes,
must be absolute.**

```powershell
& "D:\DAZ 3D\DAZStudio4 64-bit\DAZStudio.exe" `
    "C:\code\ai\_vendor\Autodazzler\dist\Autodazzler.dsa" `
    -scriptArg "autodazzlerConfigPath='C:/code/ai/godogen/skills/daz-bridge/configs/turnaround-g81-8angle.json'" `
    -noPrompt
```

Daz Studio opens, renders the 8 views to
`D:\Daz\NoxDev\renders\turnaround-g81\`, and quits (`quitAutomatically` is
inferred true when the config comes from `-scriptArg`).

## 5. Where the renders go next

Per the daz-bridge SKILL.md render-to-2D pipeline: turnaround PNGs →
ComfyUI img2img restyle (`qwen-edit-instruct`) → character LoRA training
(`ml-workbench` `training/zimage-character-lora-24gb.yaml`). Daz's perfect
identity consistency across the 8 views is exactly what the LoRA set needs.
