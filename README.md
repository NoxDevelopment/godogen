# Godogen: Claude Code skills that build complete Godot 4 projects

[![Watch the video](https://img.youtube.com/vi/eUz19GROIpY/maxresdefault.jpg)](https://youtu.be/eUz19GROIpY)

[Watch the demos](https://youtu.be/eUz19GROIpY) · [Prompts](demo_prompts.md)

You describe what you want. An AI pipeline designs the architecture, generates the art, writes every line of code, captures screenshots from the running engine, and fixes what doesn't look right. The output is a real Godot 4 project with organized scenes, readable scripts, and proper game architecture. Handles 2D and 3D, runs on commodity hardware.

## How it works

- **Two core skills** orchestrate the pipeline — `godogen` plans, `godot-task` executes — backed by a library of specialized skills (asset, animation, shader, UI, audio, narrative, save/input/camera, world-layout, and more). Each task runs in a fresh context to stay focused.
- **Godot 4 output, Unity scaffolds** — real Godot projects with proper scene trees, scripts, and asset organization; several skills also emit Unity-native sidecars (prefab/ScriptableObject JSON).
- **Asset generation** — local ComfyUI / Z-Image-Turbo (with pixel-art LoRA) is the primary 2D image path, Gemini remains a fallback; Tripo3D converts selected images to 3D models; LTX 2.3 video and local TTS/SFX/music round it out. Budget-aware: maximizes visual impact per cent spent.
- **GDScript expertise** — custom-built language reference and lazy-loaded API docs for all 850+ Godot classes compensate for LLMs' thin training data on GDScript.
- **Visual QA closes the loop** — captures actual screenshots from the running game and analyzes them with Gemini Flash vision. Catches z-fighting, missing textures, broken physics.
- **Runs on commodity hardware** — any PC with Godot and Claude Code works.

## Status

_Last updated: 2026-05-17._

**Done**
- Two-skill core pipeline (`godogen` orchestrator + `godot-task` executor) with progressive sub-file loading and forked task context.
- 25 skills total. Beyond the core pair, the library now covers: `image-pipeline` (ComfyUI dispatcher, ZIT styles registry, multi-LoRA, auto face-detailer, 53 presets), `scene-art`, `animation-pipeline`, `character-sheet`, `skeleton-rig`, `3d-asset-pipeline` (Tripo3D), `shader-craft`, `ui-screens`, `ui-elements`, `world-layout`, `narrative`, `audio-pipeline` (Kokoro/Orpheus/EdgeTTS, SFX, music), `video-pipeline` (LTX 2.3 on 8 GB VRAM), `input-handling`, `save-system`, `camera-rigs`, `playtest`, `style-anchor`, `asset-manifest`, `provider-preflight`, and `engine-export`.
- Local-first asset generation: ComfyUI / Z-Image-Turbo as the primary 2D path (Gemini retained as fallback), plus local audio and LTX video on commodity GPUs.
- Multi-engine export: Godot `.tscn`/`.tres` plus Unity prefab / ScriptableObject JSON sidecars from the asset, animation, scene-art, UI, narrative, and `engine-export` skills.
- `publish.sh` does per-skill sync (preserving sibling-repo skills) with a Windows fallback path.
- `provider-preflight` health-checks every external dependency before long asset batches; `asset-manifest` indexes every generated asset (origin, SHA, prompt/style/preset).

**In progress / recent direction**
- Migrating the primary image path off paid cloud generation toward local ComfyUI/ZIT (image-pipeline is the preferred path; remaining Gemini usage is fallback + visual QA vision).
- Engine-agnostic output: Unity scaffolds are emitted alongside Godot but the end-to-end Unity build path is less exercised than Godot.

**Next**
- Recipes for game builds (e.g. Android export).
- Animated sprites from video generation.
- Publish a full game end-to-end as a public demo.

**Features still needed / known gaps**
- macOS is untested — screenshot capture depends on X11/xvfb/Vulkan and needs a native capture path.
- Animation remains the main visual gap relative to static-asset quality.
- Explore C# (as a GDScript alternative) and Bevy (as a Godot alternative).

## Getting started

### Prerequisites

- [Godot 4](https://godotengine.org/download/) (headless or editor) on `PATH`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- API keys as environment variables:
  - `GOOGLE_API_KEY` — Gemini, used for image generation and visual QA
  - `TRIPO3D_API_KEY` — [Tripo3D](https://platform.tripo3d.ai/), used for image-to-3D model conversion (only needed for 3D games)
- Python 3 with pip (asset tools install their own deps)
- Tested on Ubuntu and Debian. macOS is untested — screenshot capture depends on X11/xvfb/Vulkan and will need a native capture path to work.

### Create a game project

This repo is the skill development source. To start making a game, run `publish.sh` to set up a new project folder with all skills installed:

```bash
./publish.sh ~/my-game          # uses teleforge.md as CLAUDE.md
./publish.sh ~/my-game local.md # uses a custom CLAUDE.md instead
```

This creates the target directory with `.claude/skills/` and a `CLAUDE.md`, then initializes a git repo. Open Claude Code in that folder and tell it what game to make — the `/godogen` skill handles everything from there.

### Running on a VM

A single generation run can take several hours. Running on a cloud VM keeps your local machine free and gives the pipeline a GPU for Godot's screenshot capture. A basic GCE instance with a T4 or L4 GPU works well.

The default `CLAUDE.md` (`teleforge.md`) is set up for [Teleforge](https://github.com/htdt/teleforge) — a lightweight Telegram bridge that lets you monitor progress and send messages to the running session from your phone. If you don't use Teleforge, pass your own `CLAUDE.md` to `publish.sh` or edit the generated one after publishing.

## Is Claude Code the only option?

The skills were tested across different setups. Claude Code with Opus 4.6 delivers the best outcome. Sonnet 4.6 works but requires more guidance from the user. [OpenCode](https://opencode.ai/) was quite nice and porting the skills is straightforward — I'd recommend it if you're looking for an alternative.

## Roadmap

- Animated sprites from video generation (now built on the local `video-pipeline` / LTX 2.3)
- Add recipes for game builds (Android export)
- Explore C# as GDScript alternative
- Publish a full game end-to-end as a public demo
- Explore Bevy Engine as Godot alternative

Follow progress: [@alex_erm](https://x.com/alex_erm)
