# Voxel Sandbox Template

3D blocky voxel base (Minecraft-like) on **Zylann/godot_voxel**, GDExtension
edition. Scaffold with:

```bash
python templates/tools/scaffold.py voxel-sandbox <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable, official build).
Kit pin: `Zylann/godot_voxel` **1.6 GDExtension**, vendored from the
**sha256-pinned release zip** (`GodotVoxelExtension.zip` @ release tag
`v1.6x`, `dfee985a…`) — prebuilt Windows/Linux/macOS/iOS/Android binaries,
self-registering, no plugin to enable. MIT.

**Do not confuse the editions**: the plain `v1.6` release is the *module*
edition — a full custom engine build. `v1.6x` is the GDExtension that runs
on the official engine. The extension edition drops a few module-only
features (notably **no FastNoise2**; use `VoxelGeneratorNoise2D` with
Godot's own FastNoiseLite instead). Exports work out of the box on official
export templates.

## What you get

- **Code-built terrain** (`scripts/main.gd`): the entire voxel setup is
  constructed in `_build_terrain()` — a 2-model `VoxelBlockyLibrary`
  (air + colored cube) on `VoxelMesherBlocky` over a flat TYPE-channel
  `VoxelGeneratorFlat`, streamed by a `VoxelTerrain` around a `VoxelViewer`
  attached to the player. Built in code on purpose: `main.tscn` stays
  parseable without the extension and the whole setup is diffable GDScript
  instead of opaque `.tres` blobs.
- **First-person fly controller** (`scripts/player.gd`): click to capture
  the mouse (`pause`/Esc releases), mouse look with pitch clamp, WASD +
  Space/Shift flight with sprint multiplier. Fly-mode keeps the skeleton
  collision-free; walking is a documented extension below.
- **Dig / place** through `VoxelToolTerrain.raycast` from the camera —
  LMB (`dig`) zeroes the aimed voxel, RMB (`place`) writes
  `build_block_id` against the hit face (`previous_position`). Both emit
  signals (`block_dug`, `block_placed`); `main.gd` counts edits into
  `GameManager.flags` and the HUD.
- **HUD**: edit counter + controls hint on a CanvasLayer.
- **NoxDev template ABI**: Master/Music/SFX buses, `game_manager` +
  `persistent` groups, `save_data()`/`load_data()` contract on GameManager,
  `pause` action, gamepad bindings on every action.

## Quirks (both auto-handled / benign)

- **First-import shutdown crash**: like TimeTick, godot_voxel 1.6 on 4.6.1
  crashes Godot's shutdown path on the very first `--import` of a fresh
  project — after a valid import cache is written. `scaffold.py` detects
  this, runs a clean verification import, and continues. Importing
  manually? Run `--import` twice.
- **Headless boot noise**: under `--headless` the dummy rendering server
  rejects the extension's mesh uploads (`Attempting to initialize the wrong
  RID` / `mesh_set_blend_shape_mode` spam) and the process segfaults on
  quit — *after* the probe completes. Pure dummy-renderer artifact: a
  windowed run exits 0 with zero errors. Judge headless probes by the DEBUG
  line, not the exit code.

## How to extend

1. **Block types**: add `VoxelBlockyModelCube`s to the library (one per
   block); a texture atlas + per-face tiles replaces the flat colors
   (`image-pipeline` makes the atlas). Hotbar = swapping
   `player.build_block_id`.
2. **Real terrain**: swap `VoxelGeneratorFlat` for `VoxelGeneratorNoise2D`
   (FastNoiseLite) or `VoxelGeneratorGraph` for caves/biomes.
3. **Walking player**: enable collision on the terrain
   (`generate_collisions`), replace the fly Node3D with a CharacterBody3D +
   gravity; keep `setup()`/dig/place unchanged.
4. **Persistence of edits**: `VoxelTerrain.stream` (e.g.
   `VoxelStreamSQLite`) persists modified chunks natively; wire world seed +
   stream path into `save_data()`.
5. **Smooth terrain**: `VoxelMesherTransvoxel` + SDF channel is the
   smooth-world variant of the same node graph.
6. **Saves/menus**: godotsmith drop-ins fit the ABI unchanged.

## Validation status

`status: "validated"` — scaffolded (archive vendored + sha256 verified),
bootstrap import clean (first-import quirk auto-handled), windowed
120-frame boot **exit 0 with zero errors**. Boot probe:

```
DEBUG: voxel-sandbox core loop ready — terrain=true loaded=true(3 frames) ground_voxel=1 block_placed=true block_dug=true
```

(VoxelTerrain streamed around the origin within 3 frames; the flat
generator's ground voxel read back as block 1; a block was placed into air,
read back, then dug out again through the same VoxelTool used by the
player's LMB/RMB.)
