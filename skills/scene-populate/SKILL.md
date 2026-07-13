---
name: scene-populate
description: Natural-language level population / set-dressing for Godot — "build me a forest clearing", "dress this scene as a market street", "scatter rocks and ferns around the clearing". Turns an NL placement request into placed nodes + instanced scenes in a real Godot project, sourcing set-dressing from CC0 kits / NAS-normalized GLBs / prior generations / (last) fresh generation via a reuse ladder, with deterministic authored-zone placement (poisson/cluster/ring/along/grid). Use whenever the request is SPATIAL set-dressing of a scene rather than a behavior/logic change. The 3D analog of world-layout.
---

# Scene Populate — natural-language set-dressing over a real Godot scene

Turn `"build me a forest clearing"` into a dressed, runnable `.tscn`: trees ring a
clearing, ferns and grass carpet the ground (batched into MultiMesh), rock clumps
break up the floor, a lantern-lined path leads to a mossy shrine — and the player
spawn stays clear. This is the **3D analog of `world-layout`**: population never
sprays `randi()` over the whole map, it places inside **authored zones**.

## When this skill applies

The request is **spatial set-dressing** of a scene: "dress / populate / build / fill
this level with …", "a forest clearing", "a market street", "a torch-lit crypt",
"scatter X around Y". If the change is *behavior* ("add double-jump", "enemies
flee at low HP"), that is a plain iterate — not this skill.

## The cardinal rule (inherited from world-layout)

> **Set-dressing is AUTHORED into named zones, never sprayed over the whole map.**
> Every instance lands inside a zone you designed (a clearing circle, a treeline
> annulus, a path spline). There is no `randi()`-over-the-map path in the solver.

## The pipeline (probe → author → resolve → solve → emit → verify)

Work in the project's real directory (this skill is published into every project's
`.claude/skills/`). Tools live in `${CLAUDE_SKILL_DIR}/tools/`.

### 1. Parse intent → `intent.json`

From the panel fields + free text, normalize:

```jsonc
{ "biome": "forest", "feature": "clearing", "dimension": "3d",
  "density": "medium", "mood": ["overgrown","calm"],
  "target_scene": "res://scenes/level_1.tscn", "focal": "a mossy shrine off-center",
  "seed": 1337 }
```

`dimension` is **inferred, not guessed**: probe the target scene's root — `Node3D`
→ 3d, `Node2D`/`TileMap` → 2d. `target_scene: "NEW"` creates a fresh scene with the
right root + a ground plane.

### 2. Probe the scene (know before you place)

Introspect the target scene (godotsmith `/api/introspect/scene?path=…`, or parse the
`.tscn` locally — it is plain text). Extract, and write into the LAYOUT:

- **Ground surface + extents** — a `Ground`/`Terrain`/`Floor` node, a `CSGBox3D`, a
  `TileMap`, or the largest horizontal mesh AABB. Defines the placement plane and
  `ground.bounds`.
- **Up-axis / dimension** — 3D places on XZ (Y-up); 2D on XY with `y_sort_enabled`.
- **Keep-out anchors** — player spawn, doors/portals, existing colliders, nav nodes
  → `keepout` shapes so dressing never buries a spawn or seals a doorway.

If the scene has no ground (empty `NEW`), the emitter lays one sized to the bounds.

### 3. Author `LAYOUT.json` (named zones + per-zone slots)

Author zones deliberately — this is where the "author, don't randomize" rule lives.
Seed the structure from `tools/biome_kits.json` (biome → slot templates + kit_tags),
then place zones against the probed bounds. See `reference.md` for the full schema,
zone shapes (`circle · annulus · rect · polygon · spline`), and the rules table.
Add the walkable path/clearing to `keepout` for the tree zones so dressing stays
walkable. **Commit `LAYOUT.json`** — it is re-read on the next populate (idempotent,
like `LAYOUT.md`), and a human can hand-edit it.

### 4. Resolve assets via the reuse ladder — `tools/kit_index.py`

**Population must not default to generation.** Every `kit_tag` walks
`asset-reuse`'s ladder; record the rung. Build the whole plan at once:

```bash
python3 tools/kit_index.py init --index kits/index.json --seed-from-biome
python3 tools/kit_index.py build-plan --index kits/index.json --layout LAYOUT.json \
    --project-dir . --biome forest --out resolved.json        # [--commercial] to gate licenses
```

`build-plan` resolves each tag through: **index → project manifest (rung 1) →
gallery (rung 2) → owned kits (rung 3: CC0 catalog | NAS bundle) → generate (rung 6)
→ greybox**. It prints a per-tag `recommendation` (the exact install/normalize/gen
command to run) and writes `resolved.json` for the solver. For any tag it recommends
a real source, PERFORM that action, then record it:

- **CC0 kit (default 3D fast path, no Blender):** godotsmith
  `POST /api/catalog/install {"id":"kenney-nature-kit"}` → drops GLBs into
  `assets/kits/`. Then `kit_index.py add --tag conifer_tree --path assets/kits/kenney_nature/tree_pineTallA.glb --source cc0_kit:kenney-nature-kit --license CC0 --footprint 1.2,1.2`.
- **NAS bundle (normalize-first):** extract in Blender +
  `blender_worker.py import-normalize <mesh> assets/kits/nas_<pack>/<name>.glb`, then
  `add` with `--source nas:… --license "…" --commercial-ok yes|no|unknown` per the
  **NoxDev/README license flag** (Morteza creature packs = personal-use-only → block
  from commercial builds).
- **Generate (last):** backdrops via `scene-art skybox|parallax|environment` (free);
  novel hero props via `3d-asset-pipeline prop` (budget-gated); 2D sprites via
  `daz-bridge`/`blender_worker turnaround`. Then `manifest.py add` + `kit_index.py add`.

**A plan that is all-greybox is a failed plan** (build-plan flags `all_greybox`):
it blocks the scene out, but install kits / normalize bundles before shipping.
Greybox (labelled coloured primitives) is the deliberate last resort so layout
iteration never blocks on assets.

### 5. Solve placement — `tools/scatter.py`

Deterministic blue-noise inside the authored zones:

```bash
python3 tools/scatter.py --layout LAYOUT.json --resolved resolved.json \
    --seed 1337 --out placements.json                          # [--density sparse|medium|dense]
```

Same LAYOUT + seed → byte-identical `placements.json` (sha256-derived RNG, immune to
PYTHONHASHSEED). Blue-noise (Bridson) honors `min_spacing`; collision-aware against
solid props + keep-out; dense `poisson_multimesh` foliage intermixes freely and is
routed to MultiMesh groups. Rules: `single · poisson · poisson_multimesh · cluster ·
ring · scatter_along · grid_along · grid` (see `reference.md`).

### 6. Emit the scene builder — `tools/emit_scene.py` + `tools/dress_template.gd`

```bash
python3 tools/emit_scene.py --placements placements.json \
    --target res://scenes/level_1.tscn --out scenes/build_level_1_dress.gd
godot --headless --path . --script scenes/build_level_1_dress.gd
```

The emitted `extends SceneTree` builder **patches** the target scene: it adds/replaces
a single `SetDressing` node (gameplay nodes untouched), grouping instances into
category nodes, GLB AABB-scaled to footprint, dense species batched into one
`MultiMeshInstance3D` each, owner-chain set with the GLB-recursion guard. Re-running
replaces only `SetDressing` — a clean idempotent re-dress. (For a `NEW` scene pass
`--target NEW --output-scene res://scenes/<feature>.tscn --ground=xmin,zmin,xmax,zmax`.)

### 7. Verify + persist

- `godot --headless --path . --quit` → **no `Parser Error` / `SCRIPT ERROR`** (RID
  leak warnings at exit are benign).
- Wide-cam screenshot → `screenshots/populate_<feature>/` so the change shows in the
  studio gallery.
- Write `LAYOUT.md` (human render of the zones + named hero props) so the next
  refine preserves authored intent; `manifest.py add` every new asset.
- `git add -A && git commit -m "populate: forest clearing"`.

## Composes with (does not duplicate)

`world-layout` (authorship rule, 2D TileMap string-grid) · `godot-task/scene-generation`
(emitter rules: owner-chain, GLB guard, AABB-scale, MultiMesh) · `asset-reuse` +
`asset-manifest` (the ladder + manifest) · `blender-bridge` (NAS normalize) ·
`scene-art` (skybox/parallax backdrops) · `3d-asset-pipeline` + `daz-bridge`
(prop/sprite generation). This skill orchestrates them for spatial set-dressing.

## What NOT to do

- ❌ Spray instances over the whole map — always author zones.
- ❌ Default to generation — walk the ladder; ≥50% of tags should be rungs 1–3.
- ❌ Individual GLB instances for dense foliage — MultiMesh is mandatory (perf).
- ❌ Recurse owner into instanced GLB internals — bloats the `.tscn` to 100 MB.
- ❌ Bury the player spawn / seal a doorway — add them to `keepout`.
- ❌ Rebuild the whole scene — patch the `SetDressing` subtree only.
