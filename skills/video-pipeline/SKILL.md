# Video Pipeline

LTX 2.3 video generation tuned for **8 GB VRAM** rigs via Deno's workflow architecture (GGUF Q4 UNet + Gemma 3 12B FP4 text encoder + RIFE frame interpolation + RTX VSR upscale, with explicit VRAM eviction between passes).

Bundles Deno's reference workflows as the source-of-truth ComfyUI graphs (`workflows/ltx23_8gb_base.json`, `workflows/ltx23_8gb_with_audio.json`) and provides a Python wrapper that patches user-facing knobs (prompt, resolution, length, fps, output filename) and submits to ComfyUI.

Credit: ComfyUI workflow + `Deno2026/comfyui-deno-custom-nodes` by [Extension-Yard1918](https://reddit.com/u/Extension-Yard1918) (the original LTX 2.3 8GB VRAM author). This skill packages and parameterizes it; it does not modify Deno's node graph.

## TL;DR

```bash
python3 .claude/skills/video-pipeline/tools/video_gen.py {t2v|i2v|bundle|inject|run|models|presets} [opts]
```

## Why this skill exists

LTX 2.3 is a 22B-parameter video model. Naively, it needs 24+ GB VRAM. Deno's workflow gets it onto an RTX 3060/3070 (8 GB) by combining:

- **Q4_K_M GGUF** quantization of the UNet (LTX-2.3-22B-distilled-1.1-Q4_K_M.gguf)
- **Gemma 3 12B FP4** for the text encoder (gemma_3_12B_it_fp4_mixed.safetensors) — way smaller than T5
- **Tiled VAE decode** to avoid the attention working-set blowup
- **Sequential offload + sage attention** for the text-encoder pass
- **Pass-splitting + RAMCleanup** — base diffusion → cleanup → interp → cleanup → upscale, so ComfyUI evicts the UNet before RIFE/RTX VSR load

The skill bundles this workflow and parameterizes the inputs you actually care about (prompt, resolution, length, output filename) without forcing you to learn the node graph. For everything else (sampler settings, NAG params, multi-image keyframe sequencer), open the saved workflow in ComfyUI Web and edit there.

## Subcommands

### t2v — Text-to-video (one-shot)

```bash
python3 .claude/skills/video-pipeline/tools/video_gen.py t2v \
  --prompt "A cinematic shot of a samurai walking through a misty forest at dawn, slow camera dolly, golden hour lighting" \
  --width 544 --height 960 --length 121 --fps 24 \
  --output-prefix "samurai_dawn" \
  --run
```

Defaults: 544×960 (portrait, Deno's tested vertical layout), 121 frames @ 24 fps (~5 seconds). Override with `--width`/`--height`/`--length`/`--fps`.

Without `--run` the skill patches the workflow JSON to a temp file and prints the path; load it in ComfyUI Web and queue manually. With `--run` it submits to ComfyUI and polls for completion.

Output lands in ComfyUI's `output/` folder with prefix `--output-prefix`. Pass `--copy-to <dir>` to copy the finished MP4 to your project tree.

### i2v — Image-to-video

```bash
python3 .claude/skills/video-pipeline/tools/video_gen.py i2v \
  --image assets/characters/knight_portrait.png \
  --prompt "The knight slowly raises his sword to the sky, dramatic clouds part overhead" \
  --width 544 --height 960 --length 121 --fps 24 \
  --output-prefix "knight_raise_sword" \
  --run
```

`--image` is uploaded to ComfyUI's input folder via `/upload/image` and wired into Deno's `MultiImageLoader` slot 1.

### bundle — Copy Deno's reference workflow somewhere editable

```bash
python3 .claude/skills/video-pipeline/tools/video_gen.py bundle \
  --preset base \
  --output workflows/ltx23_my_project.json
```

Presets: `base`, `with-audio` (the audio-driven lip-sync variant).

Use this when you want to edit the full 60-node graph in ComfyUI Web (adjust sampler, NAG params, the 50-slot keyframe sequencer, etc.) — the skill ships Deno's exact JSON.

### inject — Patch widgets in a saved workflow JSON without running

```bash
python3 .claude/skills/video-pipeline/tools/video_gen.py inject \
  --in workflows/ltx23_my_project.json \
  --prompt "new prompt here" \
  --width 720 --height 1280 --length 145 --fps 24 \
  --output-prefix "shot_001" \
  --out workflows/ltx23_my_project_shot_001.json
```

Useful for templating: produce N variant workflows that all share your edits to the base graph but differ in prompt / resolution / output name. Then queue them in ComfyUI Web one at a time.

### run — Submit a patched workflow to ComfyUI and wait

```bash
python3 .claude/skills/video-pipeline/tools/video_gen.py run \
  --workflow workflows/ltx23_my_project_shot_001.json \
  --copy-to assets/cutscenes/ \
  --manifest assets/manifest.json
```

Converts the saved workflow format to ComfyUI's API format, submits via `/prompt`, polls `/history/<id>`, optionally copies the output MP4 to `--copy-to` and records it in `--manifest` (using the asset-manifest schema with `provider=video-pipeline.ltx23`, `kind=other`).

### models — Verify required model files are present

```bash
python3 .claude/skills/video-pipeline/tools/video_gen.py models
```

Cross-checks ComfyUI's reported model dirs against the LTX 2.3 8GB model set:

- `LTX-2.3-22B-distilled-1.1-Q4_K_M.gguf` (UNet)
- `LTX23_video_vae_bf16.safetensors`
- `LTX23_audio_vae_bf16.safetensors`
- `gemma_3_12B_it_fp4_mixed.safetensors`
- `ltx-2.3_text_projection_bf16.safetensors`
- `flownet.pkl` (RIFE, optional — only used if interp pass enabled)

Exits non-zero with a download checklist if anything's missing. The Deno custom-node pack includes a `DenoLTXModelDownloader` that can fetch them in-graph; otherwise pull from Hugging Face directly.

### presets — List bundled workflows

```bash
python3 .claude/skills/video-pipeline/tools/video_gen.py presets
```

## Cardinal rules

- **Stay at Deno's resolutions until you've tested headroom.** 544×960 / 121 frames is the safe-zone on 8 GB. Pushing past 720p or 8 sec needs `--variations 1` and patience; OOM is the failure mode and it kills the whole pass.
- **One generation at a time on 8 GB.** Batch size stays at 1; ComfyUI cannot evict a partial batch.
- **Always preflight ComfyUI before a long run.** `provider-preflight comfyui` first. A 6-minute generation failing at minute 5 because ComfyUI was OOM-killed by another process is the worst outcome.
- **Don't disable the RAMCleanup nodes.** They're the trick that keeps everything in 8 GB. Removing them is the most common source of OOM on this workflow.
- **Use i2v for character/portrait videos.** t2v drifts on identity across frames because every frame is conditioned on the text alone. i2v anchors frame 1 to your reference image. Per Deno + r/StableDiffusion discussion.
- **Treat the bundled workflow JSON as upstream.** If Deno publishes an updated version, re-bundle with `bundle --preset base` and merge your edits — don't fork the JSON indefinitely.

## Files

- `tools/video_gen.py` — the CLI (single file).
- `workflows/ltx23_8gb_base.json` — Deno's base 8 GB workflow (t2v + i2v).
- `workflows/ltx23_8gb_with_audio.json` — Deno's audio-driven variant (lip-sync).
- `SKILL.md` — this file.

## Composition

- **provider-preflight** — `preflight.py comfyui` before each run; `preflight.py disk --min-free-gb 5` because video files are big.
- **asset-manifest** — pass `--manifest assets/manifest.json` to `run` to record output MP4s with `provider=video-pipeline.ltx23`, `kind=other`, params capturing prompt + resolution + length.
- **image-pipeline** — generate the `--image` reference for i2v via `image-pipeline image --type portrait`. Anchoring the first frame on a clean portrait usually beats free-form t2v.
- **character-sheet** — the 9 pose PNGs from `character-sheet` are excellent i2v inputs for short character animations (one i2v per pose, 2-second loops).
- **audio-pipeline** — for the `with-audio` workflow variant, generate the driving audio via `audio-pipeline speech` (Kokoro/Orpheus/EdgeTTS).
