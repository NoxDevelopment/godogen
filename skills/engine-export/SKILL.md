# Engine Export

Take a finished asset (sprite, spritesheet, tileset, audio, video, mesh) and emit **engine-native scaffolds** so it lands ready-to-use in Godot 4 or Unity. Pure text — no ComfyUI / Tripo3D / model dependencies.

## TL;DR

```bash
python3 .claude/skills/engine-export/tools/export_gen.py {sprite-frames|sprite-prefab|tileset-tres|audio-scene|video-scene|list} [opts]
```

Every emit subcommand takes `--asset <path>`, `--engine <godot|unity>`, and `-o <output_path>`. Defaults are chosen so the emitted file is `git diff`-able and drops straight into the engine's editor.

## Why this skill exists

After our generators produce assets (PNGs, WAVs, MP4s, GLBs), there's still a step the agent often forgets: **wiring the asset into the engine**. A spritesheet PNG is useless until you author a `SpriteFrames` resource around it; an audio WAV is useless until an `AudioStreamPlayer` knows about it. This skill closes that gap with one-shot emission of the bridging resources.

The skill is **deliberately simple** — it doesn't try to guess animation timings or layout. You give it raw asset paths and explicit parameters (frame count, FPS, grid dimensions), and it emits the boilerplate.

## Subcommands

### sprite-frames — Godot SpriteFrames `.tres` from a spritesheet

```bash
python3 .claude/skills/engine-export/tools/export_gen.py sprite-frames \
  --asset assets/sprites/knight_walk_8frame.png \
  --frame-count 8 \
  --fps 12 \
  --animation-name walk \
  -o assets/sprites/knight.tres
```

Emits a `SpriteFrames` resource Godot loads into an `AnimatedSprite2D` (or `AnimatedSprite3D`). Frame slicing is column-major from the source PNG; `--frame-count` is required because the skill doesn't try to infer it from the image.

`--animation-name` is the key under which the animation appears in the editor — pass it again with `--append <existing.tres>` to add another animation to an existing resource.

Repeatable for multiple animations:

```bash
# Build a SpriteFrames with idle + walk + attack
python3 ... sprite-frames --asset idle.png --frame-count 4 --fps 6  --animation-name idle  -o knight.tres
python3 ... sprite-frames --asset walk.png --frame-count 8 --fps 12 --animation-name walk  -o knight.tres --append
python3 ... sprite-frames --asset attack.png --frame-count 6 --fps 18 --animation-name attack -o knight.tres --append
```

### sprite-prefab — Unity SpriteRenderer prefab JSON

```bash
python3 .claude/skills/engine-export/tools/export_gen.py sprite-prefab \
  --asset Assets/Sprites/knight_walk.png \
  --frame-count 8 \
  --fps 12 \
  -o Assets/Prefabs/knight.prefab.json
```

Emits a JSON prefab that Unity's `AssetImporter` will reconstruct as a GameObject with `SpriteRenderer` + `Animator`. The output is intentionally JSON rather than `.prefab` YAML — Unity's prefab YAML has GUIDs that change per project, so JSON-as-intermediate is portable across projects. Run `Tools → Re-create Prefabs From JSON` (or any Unity import script) to materialize.

### tileset-tres — Godot 4 TileSet `.tres`

```bash
python3 .claude/skills/engine-export/tools/export_gen.py tileset-tres \
  --asset assets/tilesets/grass_32px_4x4.png \
  --tile-size 32 \
  --grid 4x4 \
  -o assets/tilesets/grass.tres
```

Emits a `TileSet` resource with one `TileSetAtlasSource` per tile. Each tile gets its `texture_region` set correctly; the agent can then add custom data layers (collisions, navigation) in the editor.

### audio-scene — Godot AudioStreamPlayer scene

```bash
python3 .claude/skills/engine-export/tools/export_gen.py audio-scene \
  --asset assets/audio/jump_sfx.wav \
  --volume-db -6 \
  -o assets/audio/jump_sfx.tscn
```

Emits a one-node `.tscn` with `AudioStreamPlayer` (or `AudioStreamPlayer3D` if `--spatial` is passed). The `.wav` is referenced by `res://` path — point at the asset that lives inside the project.

### video-scene — Godot VideoStreamPlayer scene

```bash
python3 .claude/skills/engine-export/tools/export_gen.py video-scene \
  --asset assets/videos/intro.mp4 \
  -o scenes/intro_video.tscn
```

Emits a `Control` containing a `VideoStreamPlayer` filling the viewport. Useful for cutscenes / title intros. Godot 4 supports MP4 (Theora removed); the asset path is the MP4 the video-pipeline produced.

### list — Enumerate available exports

```bash
python3 .claude/skills/engine-export/tools/export_gen.py list
```

## Cardinal rules

- **The asset path must be inside the project tree.** Godot's `res://` resolution and Unity's `Assets/` rooting both require this. The skill writes whatever path you give it; if the asset isn't in the engine project, the resource won't load.
- **Don't hand-edit the emitted `.tres` / JSON.** Regenerate. They're meant to be reproducible from the asset + params.
- **For Godot `.tres` append mode, the existing file must be a `SpriteFrames` resource.** The skill won't reformat a generic `.tres` into one.
- **Spritesheet layout is left-to-right, top-to-bottom.** Other layouts aren't supported in MVP; if you need column-major or weird grids, slice the spritesheet yourself with `image-pipeline`'s pixel toolkit first.

## Files

- `tools/export_gen.py` — the CLI (single file).
- `SKILL.md` — this file.

## Composition

- **animation-pipeline** — generates the spritesheet PNG; `sprite-frames` here wraps it for Godot.
- **character-sheet** — generates 9 individual pose PNGs; you can build a SpriteFrames per pose (each pose = one frame, fps=1) or combine select poses into a manual spritesheet first.
- **scene-art** — generates the tileset PNG; `tileset-tres` here wraps it for Godot's TileMap.
- **audio-pipeline** — generates SFX/music/speech WAVs; `audio-scene` here wraps them for playback.
- **video-pipeline** — generates MP4s; `video-scene` here wraps for cutscene playback.
- **3d-asset-pipeline** — already emits its own engine sidecars (`--engine godot|unity`), so doesn't need this skill.
