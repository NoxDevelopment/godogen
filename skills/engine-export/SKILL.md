# Engine Export

Take a finished asset (sprite, spritesheet, tileset, audio, video, mesh) and emit **engine-native scaffolds** so it lands ready-to-use in Godot 4 or Unity. Pure text — no ComfyUI / Tripo3D / model dependencies.

## TL;DR

```bash
python3 .claude/skills/engine-export/tools/export_gen.py {sprite-frames|sprite-prefab|tileset-tres|audio-scene|video-scene|list} [opts]
```

Every emit subcommand takes `--asset <path>`, `--engine <godot|unity>`, and `-o <output_path>`. Defaults are chosen so the emitted file is `git diff`-able and drops straight into the engine's editor.

## Stable-ID asset binding (`--slot-id`) — REQUIRED for template/product work

By default the Godot emitters bake the asset's `res://` path straight into the
`.tres`/`.tscn`. That's fine for a throwaway standalone resource, but it makes
"drop in / replace an asset from the Studio" impossible without a scene edit —
which violates `skills/parity-build/STANDARDS.md` → **Studio integration & live
asset wiring**.

Pass **`--slot-id <id>`** to any Godot export and it switches to **slot mode**:

- The emitted **scene references a stable slot ID**, not the asset path. A small
  binder script (`NoxAssetBinder`) resolves the id → current `res://` path **at
  load** through a per-project **`assets.manifest.json`**.
- **No hardcoded `res://` asset path is baked into the scene.** Swapping/replacing
  an asset = editing that one manifest entry (`file` + `provenance`). Zero scene
  edits; next boot binds the new asset (call `NoxAssetBinder.reload()` for hot
  reload).
- The resolver + slot node scripts are **auto-scaffolded** into
  `res://scripts/nox_asset_binding/` on first use (idempotent), and the slot is
  registered in the manifest with a **sensible default binding = the asset you
  passed**, so the project still runs out of the box.

```bash
# Slot-bound sprite (emits an AnimatedSprite2D .tscn, NOT a frozen .tres)
python3 .claude/skills/engine-export/tools/export_gen.py sprite-frames \
  --asset assets/sprites/knight_walk.png --frame-count 8 --fps 12 \
  --animation-name walk --slot-id sprite/knight \
  --provider image-pipeline.zit --license CC0-1.0 --style-pack default-pixel \
  -o scenes/knight.tscn

# Later, from the Studio: swap the art with ZERO scene edits —
#   edit assets.manifest.json → slot "sprite/knight" → "file": "res://.../knight_v2.png"
```

Provenance flags (`--policy`, `--provider`, `--license`, `--source`, `--style-pack`)
are recorded on the slot. The manifest schema (`schemaVersion 2`, `stylePack`,
`slots[]` of `{slotId, kind, policy, file, provenance}`) matches the ff-gamebook
`AssetBinder` contract, so it plugs into the Studio asset board.

Bootstrap the resolver up-front (before any export) with:

```bash
python3 .claude/skills/engine-export/tools/export_gen.py scaffold-binder \
  --project . --style-pack default-pixel
```

> The per-project `assets.manifest.json` is the **runtime binding** contract
> (slot id → current file). It is complementary to the `asset-manifest` skill's
> `assets/manifest.json`, which is the **provenance/credits index** — keep
> registering generated/reused assets there too (`manifest.py add --license …`)
> so the credits screen stays complete.

## Why this skill exists

After our generators produce assets (PNGs, WAVs, MP4s, GLBs), there's still a step the agent often forgets: **wiring the asset into the engine**. A spritesheet PNG is useless until you author a `SpriteFrames` resource around it; an audio WAV is useless until an `AudioStreamPlayer` knows about it. This skill closes that gap with one-shot emission of the bridging resources.

The skill is **deliberately simple** — it doesn't try to guess animation timings or layout. You give it raw asset paths and explicit parameters (frame count, FPS, grid dimensions), and it emits the boilerplate.

> **Studio live-wiring + verify (`skills/parity-build/STANDARDS.md`).** For template/product
> work the emitted resource must bind its asset **through the Studio-managed
> manifest by stable asset ID**, not a frozen hardcoded `res://` path — so Jesus can
> drop-in/replace the asset from the Studio without a code edit. **Do this by passing
> `--slot-id`** (see "Stable-ID asset binding" above); also register provenance in
> `asset-manifest`. After emitting, **verify it loads**: scoped `godot --headless
> --path . --import` then boot — never an unscoped import (it rewrites sibling
> templates' `project.godot`).

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
  --separation 2 --margin 0 \
  -o assets/tilesets/grass.tres
```

Emits ONE `TileSetAtlasSource` (with a per-cell present-marker for every grid cell); the agent adds custom data layers (collisions, navigation) in the editor. Pass `--separation`/`--margin` to **match a `pixeltool tileset` atlas** built with gutters (they set the atlas source's `separation`/`margins`). It also auto-writes a `<asset>.import` sidecar (lossless, **mipmaps off**, alpha-border fixed) so pixel tiles don't import blurry — pass `--no-import` to skip it. Note: final **Nearest FILTERING** is a node/project setting (`TileMapLayer.texture_filter = Nearest` / project `default_texture_filter`), not a texture-import field — see the `pixel-perfect` tileset example scene.

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

### scaffold-binder — Emit the resolver + an empty manifest

```bash
python3 .claude/skills/engine-export/tools/export_gen.py scaffold-binder \
  --project . --style-pack default-pixel
```

Writes `res://scripts/nox_asset_binding/nox_asset_binder.gd` (the stable-ID
resolver) plus the slot node scripts, and an empty `assets.manifest.json` if one
doesn't exist. Idempotent — safe to run at project setup. Slot-mode exports call
this automatically, so you only need it to adopt binding before any export.

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

- `tools/export_gen.py` — the CLI (single file). Also holds the scaffolded
  GDScript templates: `NoxAssetBinder` (the resolver) + the slot node scripts
  (`slot_animated_sprite`, `slot_audio_player`[`_3d`], `slot_video_player`,
  `slot_tilemap_layer`) written into a project on first slot-mode export.
- `SKILL.md` — this file.

## Follow-ups (tracked, not fully in scope here)

- **Narrative voice-over → credits.** `audio-scene --voice` tags the slot kind
  `audio_voice` (and `--music` → `audio_music`) so VO surfaces are distinguishable
  in the binding manifest. For the **credits screen**, also register each VO clip
  in the provenance index with its license/author:
  `asset-manifest/tools/manifest.py add --kind audio_voice --license … --author …`
  — `export --format credits` then picks it up. (The provenance index is a
  separate manifest from the runtime binding manifest; both should carry VO.)
- **vfx-particles / skeleton-rig eyeball-verify gates.** Out of engine-export's
  scope (it's a bridging-emit skill). Deferred to those skills' own emit + a
  `playtest`/design-review screenshot gate; engine-export only guarantees the
  headless import+boot verify noted above.

## Composition

- **animation-pipeline** — generates the spritesheet PNG; `sprite-frames` here wraps it for Godot.
- **character-sheet** — generates 9 individual pose PNGs; you can build a SpriteFrames per pose (each pose = one frame, fps=1) or combine select poses into a manual spritesheet first.
- **scene-art** — generates the tileset PNG; `tileset-tres` here wraps it for Godot's TileMap.
- **audio-pipeline** — generates SFX/music/speech WAVs; `audio-scene` here wraps them for playback.
- **video-pipeline** — generates MP4s; `video-scene` here wraps for cutscene playback.
- **3d-asset-pipeline** — already emits its own engine sidecars (`--engine godot|unity`), so doesn't need this skill.
