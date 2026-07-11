---
name: character-mime
description: Make 2D/3D characters speak and emote — offline viseme baking for game dialogue and realtime TTS-driven avatars (companion apps, VTuber-style). Use for lipsync, talking portraits, facial animation, or "make the character mime the speech" requests. Research-verified 2026-07-11.
---

# Character Mime — lipsync & facial animation

Fidelity ladder: volume/VU < MFCC vowel-class < **TTS phoneme timestamps → viseme
table** < neural audio→blendshape (adds co-articulation + emotion). Pick the
lowest rung that reads well — phoneme→viseme is free and deterministic.

## Offline baking — Godot/Unity game dialogue

1. **TTS lines (Kokoro/Orpheus)**: emit the viseme track AT SYNTHESIS TIME.
   Kokoro's pipeline exposes per-token phoneme timestamps; map phoneme →
   Oculus-15/ARKit viseme via table (met4citizen **HeadTTS** ships the exact
   Kokoro mapping — MIT, copy it). Zero GPU, deterministic.
2. **Recorded audio**: **Rhubarb Lip Sync** (MIT) — audio(+transcript) → 9 timed
   mouth shapes. Godot: **godot-baked-lipsync** addon (auto-installs Rhubarb;
   3D-blendshape AND 2D-sprite-swap demos) or Rhubarb TPI. Unity: community
   script or uLipSync offline bake (MIT, MFCC).
3. **High-fidelity 3D**: **NVIDIA Audio2Face-3D** as a local baker — WAV → 52
   ARKit blendshapes (+16 tongue) + emotion, >60fps gen, ~4 GB VRAM, MIT SDK,
   commercial-OK model license. No Godot plugin exists: write the small importer
   (per-frame weights → Godot `Animation` on ARKit-named blendshapes) — ~1 day,
   works for VRM/Daz-derived rigs (Faceit outputs ARKit names; see daz-bridge).
   ⚠️ **OVRLipSync is EOL 2026 — never build on it.**

## Realtime companion avatar (3090)

- **3D (VRM/GLB)**: copy the **TalkingHead/HeadTTS architecture** — one call
  returns audio + phoneme timings; play visemes with ~50ms lookahead easing.
  Upgrade when mouth-only feels dead: Audio2Face-3D interactive (52 shapes +
  emotion @60fps, ~4GB) or NeuroSync (Python, 61 ARKit shapes). Front ends:
  three-vrm (web), Godot VRM addon, or puppet VTube Studio/Warudo over API/VMC.
- **2D anime**: (a) rigged puppet — Live2D via VTube Studio API, or **Inochi2D**
  (BSD-2 — the license-free Live2D alternative; our own rig source = Qwen-Layered
  RGBA layer split + Faceit-style part naming); (b) single image, NO rigging —
  **THA3/Raven poser** (~520MB VRAM, 40+fps, 28 emotions, TTS-phoneme lipsync —
  best companion-app fit). Photoreal: **Ditto** (Apache, audio-driven realtime,
  prebuilt Ampere TensorRT) or MuseTalk 1.5 (30fps loop inpainting).
- Face tracking (user-driven instead of TTS): **MediaPipe Face Landmarker**
  (Apache, 52 blendshapes) or OpenSeeFace (BSD, CPU) — the open backbone pair.
- Reference architectures: TalkingHead+HeadTTS (cleanest), OpenAvatarChat
  (modular VAD→ASR→LLM→TTS→swappable 2D/3D avatar), AIRI, Raven.

## VN talking portraits (dialogue-ready sprite sets)

No packaged tool exists — the recipe: character sheet + emotion variants
(**VNCCS ComfyUI pack — already installed in our ComfyUI**; or qwen-edit
same-seed expression variants) → mouth-region inpainting keyed to Rhubarb's
A–F shapes (6–9 mouth sprites per emotion) → sprite-swap at runtime from the
baked viseme track. Same-seed trick: fix the seed, vary ONLY the prompt —
same-face consistency across expressions (regenerate artifact frames rather
than chasing cross-frame perfection).

## Full 3D pipeline (Daz/Blender chain)

Daz character → daz-bridge (Diffeomorphic → Blender) → **Faceit** ARKit-52 rig →
glTF per blender-bridge rules (morph normals on, ARKit shape names) → engine →
Audio2Face/HeadTTS track drives the blendshapes. This replaces Live2D-style
licensing entirely with owned tools.

License-safe core: Rhubarb/uLipSync/HeadTTS/OpenSeeFace/Ditto/Inochi2D/
Audio2Face (MIT/BSD/Apache/NOML). Avoid: OVRLipSync (EOL), Project Babble
(NC default).
