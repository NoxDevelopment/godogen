# Animation Generation — 2026-07 Research Reference

Upgrades this skill's shared-seed phase-prompt approach with video-model
pipelines. Full research: Noxdev-Studio/docs/ECOSYSTEM_AUDIT_AND_GENERATION_ROADMAP_2026-07.md §4.1.

## Sprite animation (the new primary path)

anchor sprite (chroma bg #FF00FF) → **Wan2.2-I2V-A14B + styly-agents
`Wan2-2-pixel-animate` LoRA (Apache 2.0)** [+ Civitai walk/attack sprite LoRAs
per cycle — check per-model license] + lightx2v 4-step distills → 45 frames →
chroma key / RMBG-2.0 per frame → sample 8–16 feet-aligned frames →
pixel-perfect snap (ONE grid + palette across frames) → kjnodes Image Grid →
`engine-export sprite-frames`.

LoRA local path: `D:\AI\Loras\WAN\pixel-animate\` (includes reference workflow
`wan2-2-video.json`). Blueprint repo: chongdashu/ai-game-spritesheets (MIT).

## Keyframe inbetweening

- NOW: **Wan2.2 FLF2V** (native ComfyUI first/last-frame template).
- NEXT: ToonComposer (TencentARC — inbetween+colorize one pass) when a Kijai
  wrapper/GGUF lands (57 GB unquantized; watch WanVideoWrapper#1058).

## Other lanes

- Anime/cel shots: **Index-AniSora V3.2 + AnyMask** (Apache, Wan2.2-based, 8-step).
- Motion-source → stylized character: Wan2.2-Animate; **Animate-X** (Apache) for
  non-humanoid mascots; **LayerAnimate** for per-layer motion (pairs with
  Qwen-Image-Layered RGBA output).
- Cel interpolation: **DRBA** (+MultiPassDedup) preserves animation on 2s/3s;
  engines GMFSS pg104 / GIMM-VFI. NEVER interpolate pixel sprites.
- Flipbook VFX: LTX-2/Wan same-first-last-frame loop trick → SubUV flipbooks.
- 3D: auto-rig = **SkinTokens (MIT)** supersedes UniRig; text-to-motion = hold
  (AMASS contamination) or HY-Motion 1.0 (EU/UK/KR territory cap).

## Pixellab-parity backlog (P4 in PIXEL_STUDIO_SPEC.md)

skeleton estimation from sprite · frozen-frame keyframe regen · animation→
animation retargeting · frame interpolation with re-snap · outfit transfer.
