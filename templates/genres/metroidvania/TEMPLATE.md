# Metroidvania Template

2D metroidvania base on **MetSys** (KoBeWi's Metroidvania-System). Scaffold with:

```bash
python templates/tools/scaffold.py metroidvania <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). MetSys is vendored from the
`4.6` branch at a pinned commit — the repo publishes no tags and `master` tracks the
next Godot dev version, so do not re-pin without re-validating.

## What you get

- **MetSys wired end to end**: `MetSys` autoload, `MetSysSettings.tres` (Exquisite
  map theme), a 2-room world map in `maps/MapData.txt`, and the MetSys editor
  (Map view in the editor's main screen toolbar) ready for drawing more rooms.
- **Two connected rooms** (`maps/room_a.tscn`, `maps/room_b.tscn`): one map cell
  each, joined by a passage border. Walk right through the marked gap in Room A
  and MetSys' `RoomTransitions` module swaps scenes and repositions the player.
- **Platformer player** (`scenes/player.tscn` + `scripts/player.gd`): coyote time,
  jump buffering, variable jump height, terminal velocity, and an ability-gate
  list (`abilities`) with double jump implemented as the worked example.
- **Game shell** (`scenes/main.tscn` + `scripts/main.gd` extending MetSysGame):
  starting-room load, spawn-point placement, camera limits clamped to the current
  room, minimap (MetSys `Minimap.tscn`, top-right HUD).
- **NoxDev template ABI**: `Master`/`Music`/`SFX` audio buses
  (`default_bus_layout.tres`), `"player"` + `"persistent"` groups on the player,
  `"game_manager"` + `"persistent"` on the `GameManager` autoload, `save_data() ->
  Dictionary` / `load_data()` on both, platformer input actions (`move_left`,
  `move_right`, `jump`, `crouch`, `attack`, `interact`, `pause` — keyboard + gamepad).

## Map data model (the part worth understanding)

`maps/MapData.txt` is MetSys' database. Each `[x,y,z]` block is one map cell:
`borders|colors|symbol|assigned_scene` where borders are `right,down,left,up` with
`-1` = same room continues, `0` = wall, `1` = passage. Cells reference room scenes
by **UID** — each room `.tscn` carries a stable `uid="uid://..."` header, and
MapData points at those UIDs. When you add rooms in the MetSys editor it maintains
all of this for you; only hand-edit MapData if you keep the UID pairing intact.

## How to extend

1. **New rooms**: duplicate a room scene (give it a fresh `uid=` or let the editor
   save assign one), open the MetSys main screen, draw the cells, and assign the
   scene to them (Assign Scene mode). Keep the `RoomInstance` child — it is what
   registers the room with MetSys at runtime.
2. **Abilities**: gate movement on `player.has_ability(&"dash")` etc.; grant with
   `grant_ability()` from pickups. Persist via the existing `save_data()` path.
3. **Saving**: drop in godotsmith's `save_system` template — the player and
   GameManager already implement the `persistent` contract it queries. MetSys'
   own map/visited state serializes via `MetSys.get_save_data()`; store it in the
   same save dict (see `SaveManager.gd` in the addon's `Template/Scripts`).
4. **Menus/settings**: godotsmith `menu_system` + `settings_system` drop in
   unchanged (buses and groups already match).
5. **Art**: see `assetPlanHints` in the registry entry. The rooms are flat-color
   `Polygon2D` blockouts on purpose — replace visuals with tiles/parallax, keep the
   `Walls` StaticBody2D collision (or rebuild it from your TileMapLayer physics).
6. **Camera**: the player's Camera2D uses smoothing + per-room limits. For
   deadzone/look-ahead behavior swap in the `camera-rigs` sidescroller rig.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` (zero errors, first and
second import), booted headless 60 frames (zero errors; MetSys resolves both cells
and the player rests on Room A's floor). `player.gd`/`game_manager.gd` pass
`--check-only`; `main.gd` references the MetSys autoload so it is validated by the
runtime boot instead (autoloads do not exist in `--check-only --script` runs).

## Vendored addon notes

- The vendoring step applies three tiny guards to `MetSysPlugin.gd` (see
  `patches` in the registry entry) so bootstrap `--import` runs — where the UID
  cache does not exist yet and editor plugins load before it — produce zero
  errors. Game-runtime code paths are untouched.
- License: MIT (`addons/MetroidvaniaSystem/LICENSE.txt`, manifest in
  `addons/LICENSES.md`).
- Docs: https://github.com/KoBeWi/Metroidvania-System (README + sample project).
