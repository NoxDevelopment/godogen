# scene-populate — reference

Full schemas, zone shapes, the placement-rules vocabulary, biome→kit_tag maps, and
the license gate. Read alongside `SKILL.md`.

## LAYOUT.json — the placement model

The authored input. Named zones each carry placement slots. Committed and re-read
on the next populate (idempotent). Plane coordinates are 2D `(a, b)`; the solver
maps them to 3D `(a → x, ground.y → y, b → z)` or 2D `(a → x, b → y)`.

```jsonc
{
  "version": 1,
  "seed": 1337,
  "dimension": "3d",                 // "2d" | "3d"  (inferred from scene root)
  "biome": "forest",                 // used by kit_index build-plan
  "density": "medium",               // sparse | medium | dense  (scales counts + spacing)
  "ground": { "type": "plane", "bounds": [-20, -20, 20, 20], "y": 0.0 },  // xmin,zmin,xmax,zmax
  "keepout": [                       // placement mask — gameplay anchors to protect
    { "shape": "circle", "center": [0, -18], "radius": 2.5, "reason": "player_spawn" }
  ],
  "backdrop": { "skybox": "forest_dusk", "far_parallax": null },  // → WorldEnvironment / scene-art
  "zones": [
    { "id": "clearing", "shape": "circle", "center": [0, 0], "radius": 6, "slots": [ ... ] },
    { "id": "treeline", "shape": "annulus", "center": [0, 0], "inner": 6, "outer": 15, "slots": [ ... ] }
  ]
}
```

### Zone shapes

| shape | fields | membership test |
|---|---|---|
| `circle` | `center`, `radius` | dist(center) ≤ radius |
| `annulus` | `center`, `inner`, `outer` | inner ≤ dist(center) ≤ outer |
| `rect` | `bounds:[x0,z0,x1,z1]` **or** `center`+`size:[w,h]` | inside the box |
| `polygon` | `points:[[a,b],…]` | ray-cast even-odd |
| `spline` | `points:[[a,b],…]`, `width` | within `width/2` of the polyline |

For 2D these are cell regions over the TileMap; a `fill` field can additionally
stamp a TileMap pattern via world-layout's string-grid transcription.

### Slot schema (per zone)

```jsonc
{ "kit_tag": "conifer_tree",   // semantic tag resolved by kit_index
  "count": 42,                 // target instance count (scaled by density)
  "rule": "poisson",           // distribution (table below)
  "min_spacing": 2.2,          // metres, within-slot (poisson/cluster)
  "scale_jitter": [0.8, 1.35], // per-instance uniform scale range
  "yaw": "random",             // "random" | <degrees> | "face_center"
  "at": [1.5, -1],             // single: offset from zone centroid
  "clusters": 6,               // cluster: number of clumps
  "per_cluster": [3, 7],       // cluster: members per clump (inclusive range)
  "spacing": 3.0,              // grid / grid_along: fixed step
  "side": "both",              // grid_along: left | right | both
  "band": [0.6, 1.2],          // scatter_along: lateral offset as fraction of half-width
  "footprint": [1.2, 1.2] }    // optional override of the asset's ground footprint (w,d m)
```

## Placement rules (the solver's vocabulary)

| rule | distribution | typical use | multimesh? |
|---|---|---|---|
| `single` | one instance at `at` (offset from centroid) or centroid | hero props: shrine, well, statue | no |
| `poisson` | seeded blue-noise (Bridson), honors `min_spacing` | trees, boulders — natural, non-overlapping | no |
| `poisson_multimesh` | same points, routed to one `MultiMeshInstance3D` | dense foliage: grass, ferns — perf | **yes** |
| `cluster` | N clumps (`clusters`), each poisson-filled `per_cluster` | rock piles, mushroom rings, debris | no |
| `ring` | evenly on a circle of `radius` | henge, campfire seating | no |
| `scatter_along` | random arc-length along a spline, lateral `band` jitter | path stones, scattered debris | no |
| `grid_along` | fixed `spacing` along a spline, one/both `side`s | fence posts, lanterns, pillars | no |
| `grid` | regular lattice within the zone bbox, optional `jitter` | urban lots, crop rows, dungeon pillars | no |

**Collision model.** Within a slot, `min_spacing` (blue-noise). Across
slots/zones, a spatial-hash occupancy grid keeps solid props apart and off
keep-out. Dense `poisson_multimesh` foliage is *ground cover*: it dodges solid
props + keep-out but intermixes freely with other foliage (grass and ferns are
allowed to interleave — that is the point of MultiMesh). Parametric rules
(`single`/`ring`/`*_along`/`grid`) are also filtered against bounds + keep-out;
a `single` hero keeps its authored spot unless it lands in keep-out.

**Determinism.** Every RNG is seeded from `sha256(seed : zone_id : slot_index :
tag : …)`, so results are byte-identical across machines and immune to
`PYTHONHASHSEED`. Re-dressing with the same seed only moves what the layout
changed.

## placements.json — the solver output

```jsonc
{ "version": 1, "seed": 1337, "dimension": "3d", "ground_y": 0.0,
  "backdrop": { "skybox": "forest_dusk" },
  "instances": [
    { "kit_tag": "shrine", "category": "clearing",
      "asset": "res://assets/generated/shrine_mossy.glb",
      "pos": [1.5, 0.0, -1.0], "yaw_deg": 210, "scale": 1.0, "footprint": [1.4, 1.4] } ],
  "multimesh": [
    { "group": "fern", "category": "understory", "asset": "res://assets/kits/nas/fern_01.glb",
      "footprint": [0.4, 0.4],
      "transforms": [ [x, y, z, yaw_deg, scale], ... ] } ],   // 2D: [x, y, yaw_deg, scale]
  "stats": [ { "zone": "treeline", "kit_tag": "conifer_tree", "rule": "poisson",
               "requested": 42, "placed": 42 } ],
  "warnings": [ ... ],
  "totals": { "instances": 57, "multimesh_groups": 2, "multimesh_instances": 820 } }
```

`asset` values: `res://…` (real GLB/sprite), `primitive:<box|cylinder|cone|sphere>`
(greybox), or `unresolved:<tag>` (the emitter greyboxes these too).

## kits/index.json — the Kit Index

Semantic map from `kit_tag` to concrete, engine-ready set-dressing. Unifies four
sources behind one lookup; the join point with the Promethean asset-search feature
(entries carry tags the same scorer ranks).

```jsonc
{ "version": 1, "entries": [
  { "kit_tag": "conifer_tree", "biome": ["forest","tundra"], "dimension": "3d",
    "path": "assets/kits/kenney_nature/tree_pineTallA.glb",
    "source": "cc0_kit:kenney-nature-kit", "license": "CC0", "commercial_ok": true,
    "footprint_m": [1.2, 1.2], "pivot": "bottom_center", "rung": "3" },
  { "kit_tag": "fern", "biome": ["forest","swamp"], "dimension": "3d",
    "path": "assets/kits/nas_undergrowth/fern_01.glb",
    "source": "nas:asset-packs/tVFX-Undergrowth", "license": "royalty-free (Superhive std)",
    "commercial_ok": true, "footprint_m": [0.4, 0.4], "multimesh_ok": true } ] }
```

### kit_index.py commands

```bash
kit_index.py init --index kits/index.json --seed-from-biome     # pre-seed CC0 tag mappings
kit_index.py resolve --tag conifer_tree --biome forest --dimension 3d --project-dir . \
    [--gallery-url http://localhost:8787] [--no-greybox]
kit_index.py build-plan --layout LAYOUT.json --biome forest --project-dir . \
    --out resolved.json [--commercial] [--gallery-url …]        # resolve every tag
kit_index.py add --tag conifer_tree --path assets/kits/kenney_nature/tree_pineTallA.glb \
    --source cc0_kit:kenney-nature-kit --license CC0 --commercial-ok yes \
    --footprint 1.2,1.2 [--multimesh-ok] [--biome forest] [--rung 3]
kit_index.py greybox --tag shrine                                # inspect a greybox entry
```

## The reuse ladder (rung recorded per tag)

1. **Project manifest** — `manifest.py find --labels <tag>`. Already made? Reuse. (rung 1)
2. **Cross-project gallery** — `GET :8787/api/gallery` by tag; import + restyle. (rung 2)
3. **Owned kits (rung 3) — two lanes:**
   - **CC0, engine-ready today (default 3D fast path):** godotsmith
     `/api/catalog/search?q=<biome>` → `/api/catalog/install` → Kenney
     nature-kit / fantasy-town-kit / modular-dungeon-kit into `assets/kits/`. No Blender.
   - **NAS bundles, normalize-first:** `\\DXP4800PLUS-A79\NoxDev\blender-tools-and-assets\`
     — `asset-packs/tVFX-Undergrowth` (dense foliage), `asset-packs/ProceduralAlleys`
     / `ProceduralSigns` (urban), `terrain-environment/*` (True Terrain, GeoScatter,
     TrueSky). Extract in Blender + `blender_worker.py import-normalize <mesh>
     assets/kits/nas_<pack>/<name>.glb` (1u=1m, bottom-center pivot, engine-clean).
4. **Derive (rung 4–5)** — palette-swap / restyle an existing kit asset to the
   project `STYLE_PROFILE` (`asset-reuse/tools/palette_swap.py`, `qwen-edit-instruct`).
   Variants are never regenerated.
5. **Generate (rung 6, last)** — backdrops via `scene-art skybox|parallax|environment`
   (local ZIT, free); novel hero props via `3d-asset-pipeline prop` (Tripo3D,
   budget-gated); 2D sprites via `daz-bridge` / `blender_worker turnaround`.

Every newly resolved asset is `manifest.py add`-ed and `kit_index.py add`-ed so the
next populate (and asset-search) finds it — the library compounds.

## License gate (mandatory)

Each index entry carries `license` + `commercial_ok` (`true`/`false`/`null`=unknown).
`build-plan --commercial` marks any entry that is not commercially cleared as
**BLOCKED** and exits non-zero, so the emitter refuses to bake a personal-use-only
asset into a commercial build. Honor the flags in `NoxDev/README.md`:

- **Superhive (Blender Market) standard** — royalty-free, commercial OK.
- **Morteza creature packs** — **personal-use-only** → block from any commercial
  project until upgraded. Set `--commercial-ok no` when indexing.
- **Addons** — GPL tool / royalty-free output.

The `commercial` flag itself lives on the project (wire to the existing IP/legal +
daz-licensing surfaces), not a new one.

## 2D vs 3D asset shape

| | 2D | 3D |
|---|---|---|
| Ground | `TileMap` (world-layout string-grid) | `CSGBox3D` / `GridMap` / heightmap mesh |
| Set-dressing | `Sprite2D`, `y_sort_enabled`; greybox → `Polygon2D` | GLB `MeshInstance3D`; dense → `MultiMeshInstance3D` |
| Backdrop | `ParallaxBackground` (scene-art parallax) | `WorldEnvironment` sky (scene-art skybox / NAS TrueSky) |
| Dense foliage | scattered sprites / tilemap scatter layer | one `MultiMesh` per species (thousands = 1 draw call) |
| CC0 kits | Kenney tiny-town/roguelike, LimeZu; pixel-studio | Kenney nature/town/dungeon CC0 GLB |

## biome_kits.json

The shared seed catalog: `biome → { features, slots (tag templates), kit_tag_sources
(tag → {cc0 kit id | nas path | gen recipe}) }`. Seeded for forest, city, dungeon,
desert, cave, interior. Extend it as new biomes/kits are indexed — it is the semantic
backbone `kit_index.py` reads for recommendations and `init --seed-from-biome`.

## Greybox mode

When a tag has no real asset yet (offline, kit not installed), `kit_index` resolves it
to a `primitive:<shape>` greybox and the emitter renders a labelled coloured primitive
(trees green cones, rocks grey boxes, foliage green cones, hero props tan boxes, with a
per-tag hue nudge). This is deliberate grey-boxing — it blocks out the scene and makes
the whole pipeline runnable/verifiable with zero assets. `build-plan` flags an
all-greybox result as a **failed plan**: block it out, then install kits / normalize
bundles and re-run.
