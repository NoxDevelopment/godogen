# Zelda-like Template

Top-down action-adventure base (classic Zelda structure), **pure
first-party** — no vendored kit. The Wave-3 survey found no clearly-maintained
MIT Zelda kit to pin, and the genre's adventure layer (screen-grid rooms,
doors/keys/flags, an item slot) is build-cheap on top of the top-down-action
archetype already in the registry — this template is that archetype **plus the
adventure structure**: where top-down-action is one arena with mouse-aim
hitscan, zelda-like is rooms, dungeon logic, and a sword. Scaffold with:

```bash
python templates/tools/scaffold.py zelda-like <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No addons, no pins
to track.

## What you get

- **Hero** (`scenes/player.tscn` + `scripts/player.gd`): 4-directional
  movement (the dominant input axis wins — no diagonals, classic grid feel),
  a **sword-arc sweep** (Space; distance + angle hit-test against the
  `"enemies"` group, 130° arc), an **item button** (Shift) driving the
  equipped-item slot, an **interact button** (E) for chests, hearts with a
  post-hit grace window, and small-key / item inventory. `attack()`,
  `use_item()`, `interact()` and `face()` are public — bots, cutscenes and
  the boot probe drive the hero through the exact routines the input actions
  call. Death respawns at the spawn point with full hearts; keys, items and
  world flags are kept.
- **Boomerang** (`scripts/boomerang.gd`, a child of the player): thrown with
  the item button, flies `throw_range` in the facing direction, homes back to
  the player, and **stuns** every enemy touched on either leg (once per
  flight). One throw in flight at a time.
- **Room-based world** (`scenes/room.tscn` + `scripts/room.gd`, three rooms
  in `main.tscn`): rooms sit on a screen grid (position = grid coord ×
  1152x648) and build their own floor + perimeter walls **in code**, leaving
  a 128px doorway gap on any side flagged `gap_*` — scenes stay free of
  dozens of wall shapes. `main.gd` watches which room the player stands in;
  crossing a doorway **snaps the camera** to the new room and wakes only that
  room's enemies (classic Zelda screens).
- **Dungeon fundamentals**: a **small key** (`key_pickup.tscn`) → a **locked
  door** (`door.tscn`, LOCKED) that consumes the key when a carrying player
  bumps it; a latching **pressure plate** (`switch_plate.tscn`) that opens
  its `target_door` (SWITCH doors only open via `open()`); a **treasure
  chest** (`chest.tscn`, `"interactables"` group) that grants + equips the
  boomerang through `player.give_item()`. Every key/door/plate/chest writes
  a `GameManager` flag (`flag_id`) and restores itself from it in `_ready`,
  so world state survives room transitions **and** scene reloads.
- **Two enemy archetypes** on a shared chassis (`enemy_base.gd`: health +
  `take_hit` contract, boomerang `stun()`, touch damage on a cooldown,
  per-room activation): the **patroller** ping-pongs along `patrol_axis` and
  the **chaser** runs straight at the player inside `aggro_range`. Deaths
  roll a heart drop (`heart_drop_chance`, seedable via `main.set_seed()`).
- **HUD**: hearts row (code-managed ColorRects), key count, equipped-item
  icon + label, control hints.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"player"` +
  `"persistent"` groups on the player, `"game_manager"` + `"persistent"` on
  `GameManager`, `save_data()/load_data()` contracts (player saves
  hearts/keys/equipped item/inventory/position; GameManager saves flags),
  `"scalable_text"` HUD labels, `pause` action declared.

## The room grid + flags (the part worth understanding)

The world is **one scene**: rooms are instances of `room.tscn` whose
*position* is their grid coordinate times `ROOM_SIZE` (1152x648 — one
screen). There is no scene switching on transitions; `main.gd` just derives
`floor(player_pos / ROOM_SIZE)` each physics frame, and when it changes it
snaps the camera and flips per-room enemy activation. Doors are placed on the
shared boundary between two rooms' doorway gaps and block the 128px corridor
until opened.

Persistence is **flag-driven, not node-driven**: doors, chests, keys and
plates each own a `flag_id` in `GameManager.flags`. They write it when
opened/taken and re-apply it in `_ready`, so the same main scene can be
reloaded (death screens, save/load, debugging) and the dungeon stays solved.
The *item* a chest granted is not a flag — it lives in the player's saved
inventory — so a restored chest only re-opens its lid and never
double-grants.

Combat is distance-checked, not physics-checked (iso-arpg style): the sword
arc and the boomerang both scan the `"enemies"` group, and enemies
distance-check the player for touch damage. Collision layers (1 world,
2 player, 3 enemies, 4 pickups) exist for walls, closed doors and the
pickup/sensor Areas, not for hit-tests.

## How to extend

1. **More rooms**: instance `room.tscn` at the next grid position, flag the
   doorway gaps on both sides of each shared edge, and drop a `door.tscn` on
   the boundary (or leave the gap open). Give each new door/chest/key a
   unique `flag_id`.
2. **More items**: add a `match` arm in `player.use_item()` (bombs, bow…)
   and grant the id from a chest — `give_item()` equips whatever it is
   handed. An item-cycling UI is one extra input action away.
3. **Enemies**: extend `enemy_base.gd` and implement `_move(delta, player)`
   — the chassis provides health, stun, touch damage and room gating. Ranged
   enemies can reuse the boomerang's fly-out pattern for projectiles.
4. **Real Zelda scroll**: `_update_room()` snaps `_camera.position`; tween it
   over ~0.5s (and pause enemy physics during the slide) for the classic
   scroll transition.
5. **Half hearts / more hearts**: hearts are ints — double the unit
   (`max_hearts = 6`, damage 1 = half a heart) and draw pairs in
   `_on_hearts_changed`, or bump `max_hearts` from a heart-container chest.
6. **Saving/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged — player and GameManager already
   implement the `persistent` contract.
7. **Art**: see `assetPlanHints` in the registry entry. Rooms are code-built
   `Polygon2D` blockouts — when a tileset lands, replace `_build_floor()` /
   `_build_walls()` with a `TileMapLayer` painted per room (keep the wall
   collision rects and the doorway gap geometry).

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
errors, 120-frame headless boot (`--quit-after 120`) exit 0 with zero script
errors, stable across 5 boots on 2 fresh scaffolds. Boot probe:

```
DEBUG: zelda-like core loop ready — key_picked=true sword_kill=true locked_door=true room_transition=true switch_door=true chest_item=boomerang boomerang_stun=true transitions=2
```

(`key_picked` = the small-key Area2D fed `gain_key()`; `sword_kill` = two
public `attack()` arc sweeps killed the patroller; `locked_door` =
`try_open()` — the door's own bump routine — consumed the key and opened;
`room_transition` = walking through the opened doorway snapped the room
watcher to (1,0); `switch_door` = standing on the pressure plate latched it
and opened the switch door; `chest_item=boomerang` = `interact()` opened the
chest and the boomerang landed in the equipped slot; `boomerang_stun` = a
real throw stunned the chaser mid-flight; `transitions=2` = A→B→C.) The only
log line is the benign Camera2D physics-interpolation notice also present in
top-down-action, iso-arpg and vampire-survivors.
