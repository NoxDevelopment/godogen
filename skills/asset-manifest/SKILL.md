# Asset Manifest

A single, durable index of every generated asset in the project — its origin (`image-pipeline` / `3d-asset-pipeline` / `scene-art` / `animation-pipeline` / etc.), its SHA, the prompt + style + preset that produced it, plus human-readable labels and tags. Lives at `assets/manifest.json` by default.

> **This is rung 1 of the [`asset-reuse`](../asset-reuse/SKILL.md) ladder** — `find` here is the first thing every asset request does before any generation. It's also the mechanism behind the Definition of Done's Studio asset-wiring (`skills/parity-build/STANDARDS.md` → "Studio integration & live asset wiring"): assets bound by **stable `asset_id`** with provenance (source, LoRA/style, license) are what let Jesus drop in a replacement from the Studio without code edits. Register every generated/reused asset here with rich labels + provenance.

## Why this skill exists

Without a manifest, three things go wrong in any project past month 1:

1. **Asset thrash.** The agent regenerates a sprite it already produced last week because it can't see what's there. `image-pipeline` outputs accrete in `assets/` with names like `knight_64x64_a8f0.png` and no one (least of all the agent) remembers which prompt made which.
2. **Inconsistent reuse.** `animation-pipeline` and `scene-art` need a `--reference-asset` flag, but referencing by relative path makes refactors painful. A stable `asset_id` decouples reference from filesystem layout.
3. **Hidden provider mix and cost blindness.** Some assets come from local ZIT (free), some from `3d-asset-pipeline.tripo3d` (paid per call), some hand-imported from external tools. Without the manifest, you can't tell which assets cost real money (and shouldn't be regenerated lightly) vs. free (regenerate any time).

The manifest fixes all three by giving every asset a stable id, recording where it came from, and letting any tool query "do we already have a `village_oak` portrait at 128×128?" before spending money or time.

## TL;DR

```bash
python3 .claude/skills/asset-manifest/tools/manifest.py {add|find|list|verify|prune|export|init} [opts]
```

Manifest schema (`assets/manifest.json`):

```json
{
  "version": 1,
  "created": "2026-05-17T12:00:00Z",
  "updated": "2026-05-17T12:00:00Z",
  "root": "assets/",
  "assets": [
    {
      "asset_id": "sprite_knight_idle_a8f0c1b2",
      "sha12": "a8f0c1b287d3",
      "path": "sprites/knight_idle.png",
      "kind": "sprite",
      "provider": "image-pipeline.zit",
      "labels": ["knight", "hero", "idle"],
      "params": {
        "prompt": "armored knight with crimson cape, idle stance",
        "style": "default-pixel", "preset": "rpg_hero",
        "size": [64, 64], "lora": "pixel_art_style_z_image_turbo.safetensors"
      },
      "references": [],
      "created": "2026-05-17T12:01:23Z"
    }
  ]
}
```

`asset_id` is `<kind>_<labels-joined>_<sha8>`. Stable across re-runs as long as bytes don't change. SHA is over the file content (PNG/GLB/etc).

## Subcommands

### init — Create an empty manifest

```bash
python3 .claude/skills/asset-manifest/tools/manifest.py init \
  --manifest assets/manifest.json --root assets/
```

Initializes a fresh `manifest.json` with an empty assets array. Safe to run once at project setup. Idempotent — won't clobber an existing manifest unless `--force` is passed.

### add — Record a generated asset

```bash
python3 .claude/skills/asset-manifest/tools/manifest.py add \
  --path assets/sprites/knight_idle.png \
  --kind sprite \
  --provider image-pipeline.zit \
  --labels knight,hero,idle \
  --param prompt="armored knight with crimson cape, idle stance" \
  --param style=default-pixel \
  --param preset=rpg_hero
```

`--kind` is one of: `sprite`, `character`, `portrait`, `tile`, `tileset`, `parallax`, `skybox`, `environment`, `ui`, `icon`, `mesh3d`, `texture`, `animation_frame`, `spritesheet`, `audio_sfx`, `audio_music`, `audio_voice`, `other`.

`--provider` is a free-form string but should be one of the conventional values:

| Provider | Use when |
|----------|----------|
| `image-pipeline.zit` | Local Z-Image-Turbo via our `image-pipeline` skill |
| `image-pipeline.sdxl` | Local SDXL/Pony fallback path |
| `character-sheet.zit` | Local ZIT via `character-sheet` (3×3 pose grids) |
| `3d-asset-pipeline.tripo3d` | Paid Tripo3D mesh generation |
| `scene-art.zit` | Local ZIT via `scene-art` |
| `animation-pipeline.zit` | Local ZIT animation cycles |
| `audio-pipeline.sfx` / `.music` / `.speech` | Local audio synthesis |
| `external.<vendor>` | Anything else (manual, Photoshop, MCP-based providers, etc.) |

`--param key=value` may be repeated. Returns the assigned `asset_id` on stdout. If the SHA already exists in the manifest, returns the existing id and skips re-adding.

### find — Query existing assets

```bash
# Find any sprites of a character before regenerating
python3 .claude/skills/asset-manifest/tools/manifest.py find \
  --labels knight \
  --kind sprite

# Find anything that came from the paid 3D pipeline
python3 .claude/skills/asset-manifest/tools/manifest.py find \
  --provider tripo3d

# Find assets that reference another asset (animation frames of a sprite)
python3 .claude/skills/asset-manifest/tools/manifest.py find \
  --references-id sprite_knight_idle_a8f0c1b2
```

Filters combine with AND. JSON array on stdout. Exits 0 even if no matches (empty array); exits 1 only on manifest read errors.

Use `find` **before** `image-pipeline image …` to avoid regenerating something that already exists.

### list — Print summary

```bash
python3 .claude/skills/asset-manifest/tools/manifest.py list
python3 .claude/skills/asset-manifest/tools/manifest.py list --by provider
python3 .claude/skills/asset-manifest/tools/manifest.py list --by kind
```

Counts grouped by provider, kind, or labels. Useful for `paid-vs-free` audits.

### verify — Cross-check SHAs vs. files on disk

```bash
python3 .claude/skills/asset-manifest/tools/manifest.py verify
```

For each manifest entry: does the file still exist? Does its SHA match? Reports:

- **Missing** — entry references a file that's gone (asset deleted; manifest needs prune)
- **Modified** — file SHA no longer matches manifest (probably manually edited; needs re-add)
- **Untracked** — files under `--root` that aren't in the manifest (probably orphaned)

Exits non-zero if any *modified* or *missing* entries are found. Untracked files are warnings, not errors.

### prune — Remove manifest entries for missing files

```bash
python3 .claude/skills/asset-manifest/tools/manifest.py prune
```

Drops any manifest entry whose file no longer exists on disk. Use after a manual cleanup. Dry-run with `--dry-run` to see what would be removed.

### export — Emit a flat lookup table

```bash
python3 .claude/skills/asset-manifest/tools/manifest.py export \
  --format godot --output assets/asset_registry.gd

python3 .claude/skills/asset-manifest/tools/manifest.py export \
  --format unity --output Assets/AssetRegistry.json
```

`--format godot` writes a `class_name AssetRegistry extends RefCounted` module with `const KNIGHT_IDLE := "res://sprites/knight_idle.png"` lines, allowing typed asset references in code instead of stringly-typed paths.

`--format unity` writes a JSON `Dictionary<string, string>` that a runtime AssetRegistry class can deserialize.

`--format json` writes a flat `{asset_id: relative_path}` map.

## How the manifest plugs into other skills

The expected pattern is: **every generator skill writes to the manifest at the end of its run**.

```bash
# Generate
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type sprite --prompt "armored knight" --style default-pixel \
  -o assets/sprites/knight_idle.png

# Record
python3 .claude/skills/asset-manifest/tools/manifest.py add \
  --path assets/sprites/knight_idle.png \
  --kind sprite --provider image-pipeline.zit \
  --labels knight,hero,idle \
  --param prompt="armored knight" --param style=default-pixel
```

The two-step flow is intentional. The generator skills don't import the manifest module — they just emit files. The agent (or a shell wrapper) records into the manifest as the second step. Keeps the dependency arrow clean and means manually-curated assets can also be manifest-tracked.

For a one-shot wrapper that does both, see the `tools/record_after.sh` example in this skill's directory.

## Cardinal rules

- **Check the manifest before regenerating.** `find --labels X --kind Y` first. If it exists, reuse. Only regenerate when you genuinely need a new variant or the params have changed.
- **Track paid assets carefully.** Anything from `3d-asset-pipeline.tripo3d` (or any future paid provider) costs real money. Treat the manifest entry as the source-of-record; never delete the asset without checking it's unreferenced.
- **One manifest per project.** Don't shard by kind or provider. The whole point of the manifest is one place to look.
- **Manifest is committed.** It's text JSON, diffs well in git. The actual asset files may or may not be committed (depends on your `.gitignore`), but the manifest always is.
- **Don't hand-edit `asset_id`.** It's derived from kind + labels + sha. Hand-editing breaks reproducibility. To rename, drop the old entry and add a new one with the desired labels.

## Files

- `tools/manifest.py` — the CLI (single file).
- `tools/record_after.sh` — convenience wrapper showing the two-step generate-then-record flow.
- `SKILL.md` — this file.

## Composition

- **image-pipeline / scene-art / animation-pipeline / 3d-asset-pipeline / audio-pipeline** — all generator skills should be followed by a `manifest.py add` call.
- **provider-preflight** — manifest size + paid-asset counts feed into the preflight summary so the agent knows how much it's already spent before kicking off a new batch.
- **style-anchor** — `style-anchor` uses `reference.png` as ground truth; that reference image should be `add`ed to the manifest with `--kind reference` and `--labels style-anchor` so it's discoverable.
- **playtest** — playtest reports can include "assets produced this session" by diffing `manifest.json` against the pre-run state.
