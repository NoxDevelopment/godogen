# Isometric ARPG Template

Isometric action-RPG base (Diablo-like), **pure first-party** — no vendored kit.
The Wave-2 survey found the genre's core loop build-cheap (navigation, ability
cooldowns, weighted loot tables are all plain Godot), so everything here is
first-party. Scaffold with:

```bash
python templates/tools/scaffold.py iso-arpg <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No addons, no pins to track.

## What you get

- **Click-to-move player** (`scenes/player.tscn` + `scripts/player.gd`):
  `NavigationAgent2D` pathing on the arena's `NavigationRegion2D`; holding
  `move_click` (LMB) re-paths continuously, Diablo style.
  `command_move_to(world_pos)` is the programmatic entry point (used by the
  boot probe — bots/cutscenes can drive the player the same way). Health with
  post-hit grace + respawn.
- **Ability bar**: `[1]` melee swing (radius 90, 0.4s cooldown) and `[2]` AoE
  nova (radius 190, damage 4, 4s cooldown, expanding-ring flash). Cooldown
  readout lives in the HUD; `ability_used(slot, cooldown_left)` is the
  game-feel hook.
- **Loot system** (`scripts/loot_system.gd`, autoload `LootSystem`):
  Pandora-style item database in `data/items.json` (5 items, 4 rarities).
  `roll_drop()` picks an item, rolls a weighted rarity
  (common 55 / magic 30 / rare 12 / legendary 3) and scales the base stat by
  the rarity multiplier ±15%. `drop_loot(pos)` spawns a rarity-tinted ground
  pickup (`scenes/loot_pickup.tscn`) collected on walk-over into
  `LootSystem.inventory`. Seedable RNG (`set_seed`) for deterministic tests.
- **Three chaser enemies** (`scenes/enemy.tscn`): the top-down-action chaser
  archetype — `NavigationAgent2D` repath 4x/sec, contact damage on cooldown,
  `take_hit` contract; each death rolls a loot drop.
- **Isometric floor** (`scripts/floor.gd` on a `TileMapLayer`): diamond-down
  128x64 tileset built from the committed 2-tile atlas
  (`assets/tiles/iso_tiles.png`); the 10x10 diamond is painted in code at boot
  so the scene file stays free of opaque packed tile data.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"player"` +
  `"persistent"` groups on the player, `"game_manager"` + `"persistent"` on
  `GameManager`, `LootSystem` also `"persistent"` (inventory survives saves),
  `save_data()/load_data()` contracts, `"scalable_text"` HUD labels, `pause`
  action declared.

## Movement model (the part worth understanding)

Movement is **navigation-constrained, not collision-constrained**: player and
enemies only ever follow `NavigationAgent2D` paths inside the diamond
`NavigationPolygon`, so the arena needs no boundary walls. When you add wall
props, re-author the nav polygon around them (or bake it) — agents will path
around anything the polygon excludes. Collision layers (1 world, 2 player,
3 enemies, 4 loot) exist for hit-tests and pickups, not for containment.

Abilities use distance checks against the `"enemies"` group rather than
Area2D shapes — cheap, and trivially extended to arcs/cones by filtering on
angle before applying `take_hit`.

## How to extend

1. **Items**: add entries to `data/items.json` — new rarities and stats need
   zero code. Affix systems slot into `roll_drop()` (roll N affixes scaled by
   the same rarity multiplier).
2. **Abilities**: copy the `use_nova()` pattern (cooldown field + effect +
   `ability_used` emit); bind a new input action and HUD slot.
3. **Enemies**: subclass `enemy.gd` for ranged/elite variants; elites can
   call `LootSystem.drop_loot()` multiple times or bias the rarity roll.
4. **Dungeon floors**: duplicate `main.tscn`; each floor keeps one
   `NavigationRegion2D` whose polygon matches its painted tiles.
5. **Saving/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged.
6. **Art**: see `assetPlanHints` in the registry entry. The atlas PNG and all
   `Polygon2D` blockouts are placeholders; keep collision shapes and the
   tileset's 128x64 diamond geometry.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
errors, 120-frame headless boot exit 0 with zero script errors. Boot probe:

```
DEBUG: iso-arpg core loop ready — click_move=true enemies=3 enemy_chasing=true loot_roll=[rare] Quick Boots +20 move_speed
```

(`click_move=true` = a programmatic click-move left the agent holding a live
path; `enemy_chasing=true` = a chaser holds a path to the player; the loot
roll exercised the weighted rarity table.) The only log line is the benign
Camera2D physics-interpolation notice also present in top-down-action.
