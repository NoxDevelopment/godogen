# Tower Defense Template (lane + towers, 2D)

A classic tower-defense base: enemies march a fixed lane, towers placed on the
buildable cells beside it auto-fire at the nearest enemy in range, waves scale
up, gold comes from kills and lives from leaks. Data-driven tower catalogue + a
scaling wave curve + full save/load. Scaffold with:

```bash
python templates/tools/scaffold.py tower-defense <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No third-party addons —
pure first-party Godot, imports clean anywhere.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the meta-state + rules
  as pure, headless-testable logic:
  - Resources: **gold / lives / wave**.
  - A **data-driven tower catalogue** (`TOWER_TYPES`): each entry sets cost,
    range (px), damage, seconds-between-shots, and a blockout colour. Ships two —
    **Arrow** (cheap, fast, low damage) and **Cannon** (pricey, slow, hard-hitting).
  - `place_tower()` / `demolish_tower()` (occupancy + affordability), `award_kill()`,
    `lose_life()`, `is_defeated()`, `begin_wave()`, and the scaling curves
    `enemy_count_for_wave()` / `enemy_hp_for_wave()`.
- **Playfield** (`scenes/main.tscn` + `scripts/td.gd`) — a lane (waypoint path)
  enemies walk; a grid of **buildable cells** (any cell clear of the lane corridor);
  real-time enemy movement, tower targeting-and-firing (nearest enemy in range,
  per-tower cooldown, instant-hit with a fire flash), a wave spawner that sends
  the next wave on the "Start wave" button and re-enables it when the field
  clears, enemy HP bars, a resource HUD, and a tower palette. Esc pauses
  (movement + firing halt; input still toggles pause).
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (gold,
  lives, wave, and placed towers persist); a `pause` input action;
  `"scalable_text"` on the HUD labels + palette buttons.

## The loop (the part worth understanding)

`td.gd._process()` drives everything each frame (guarded off while paused):
spawn from the wave's remaining count, advance each enemy along the path (a leak
calls `GameManager.lose_life()` and removes it), then for each tower tick its
cooldown and — when ready — pick the nearest enemy inside its range, deal damage,
and on a kill remove the enemy and call `GameManager.award_kill()`. A wave clears
when nothing is left to spawn and no enemies remain. Enemies and fire flashes are
transient (not saved); towers + economy live in `GameManager` and serialise.

## How to extend

1. **Towers**: add to `TOWER_TYPES` — e.g. a `frost` tower (add a `slow` field and
   apply it in `_fire_towers`) or a `sniper` (huge range, high cost). The palette
   + firing pick it up automatically.
2. **Enemy variety**: give the enemy dict a `speed`/`armor` field and vary it per
   wave in `_spawn_step`; tougher/faster types for later waves.
3. **The lane / multiple paths**: edit `_build_path()` (waypoints) or swap to a
   `TileMapLayer` with a baked path; `_is_buildable()` already keeps towers clear
   of the corridor via `PATH_CLEARANCE`.
4. **Art**: replace the `_draw()` blockout shapes with sprites (tower `Sprite2D`
   per type_id, enemy scenes, a tiled ground) — see the genre→workflow recipes:
   tiles via `zit-seamless-tile`, tower/enemy sprites via `zit-pixel-art`, icons
   via `qwen-icon`.
5. **Saving/menus**: godotsmith `save_system` / `menu_system` / `settings_system`
   drop in unchanged; the run (economy + placed towers) already serialises via
   `GameManager.save_data()`.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0, and a headless
probe: places towers (affordability + occupancy checked), applies damage to a
modelled enemy set (kill → gold, leak → life), advances waves with the scaling
curves, checks defeat at zero lives, and round-trips save/load — all green, zero
script errors; the live scene boots clean.
