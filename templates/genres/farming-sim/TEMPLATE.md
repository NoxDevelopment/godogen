# Farming Sim Template

2D farming base (Stardew-like) on the **TimeTick** GDExtension plus
first-party farm/crop/day-night systems. Scaffold with:

```bash
python templates/tools/scaffold.py farming-sim <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable).
Kit pin: `shoyguer/time-tick` **1.1**, vendored from the **sha256-pinned
release zip** (`time_tick_1.1.zip`, `e30cd7c1…`) — the repo tag is C++
source only; prebuilt GDExtension binaries (Windows/Linux/macOS/Android/
iOS/Web) ship in the release asset. MIT. GDExtensions self-register — no
plugin to enable.

Survey note: the Wave-2 pick for day/night (maetzemax
`day-and-night-cycle` 0.3.0) was evaluated and is **3D-only** (its
CycleController extends Node3D and drives a DirectionalLight3D +
WorldEnvironment sky) — it cannot tint a 2D TileMap farm, so this template's
day/night layer is first-party. If your project goes 3D, swap `DayNight`
for that addon (MIT, Godot 4.5).

## What you get

- **TimeSystem** (`scripts/time_system.gd`, autoload): thin wrapper around
  `TimeTick` — tick → minute (0-59) → hour (0-23) → day (1..) at 0.1 s real
  per game minute (a full day ≈ 2.4 real minutes; `set_time_scale` to taste),
  days start 06:00, derived 28-day **seasons**
  (spring/summer/autumn/winter), re-emitted `minute/hour/day/season_changed`
  signals, `sleep_to_next_day()` and `set_hour()` clock jumps (probe/cutscene
  hooks), clock save/load via the `persistent` contract.
- **Day/night tint** (`scripts/day_night.gd` on a `CanvasModulate`):
  samples a 24-hour gradient (night blues → dawn → clear noon → dusk) from
  `TimeSystem.get_day_fraction()`; `day_started`/`night_started` fire at
  06:00/19:00. HUD lives on a CanvasLayer so it stays untinted.
- **Farm field** (`scripts/farm.gd` on a `TileMapLayer`): 20x12 field painted
  in code from the 3-tile atlas (grass/tilled/watered,
  `assets/tiles/farm_tiles.png`), `till`/`plant`/`harvest` API with
  signals, harvest totals recorded to `GameManager.flags`. **Growth is
  idempotent**: crop stage is recomputed from `today - planted_day` on every
  `day_changed`, so duplicate day signals can never double-grow a crop.
  Tilled cells and plantings save/load (crop markers rebuild).
- **Crop resource** (`scripts/crop.gd` + `resources/crops/turnip.tres`):
  data-driven growth — `stage_count`, `days_per_stage`, harvest yield,
  blockout stage colors (markers grow and recolor per stage). New crops are
  new `.tres` files, zero code.
- **Farmer** (`scenes/player.tscn`): top-down movement + one contextual
  `interact` (E) on the tile underfoot — harvest > plant (equipped crop) >
  till. `interact_here()` is the programmatic entry point.
- **HUD**: day/season/clock (+ `[night]` marker), harvest tally, controls
  hint.
- **NoxDev template ABI**: buses, groups, `save_data()` contracts on
  TimeSystem/Farm/Player/GameManager, `scalable_text`, `pause` action.

## Tooling note (first-import crash)

TimeTick 1.1 on Godot 4.6.1 crashes Godot's **shutdown path** on the very
first `--import` of a fresh project — after the import has completed and
written a valid cache. `scaffold.py` detects this, runs a verification
import (clean = continue), and prints the quirk. Every subsequent import,
editor open, and run is clean. If you import manually instead of via
scaffold.py, just run `--import` twice.

## How to extend

1. **Crops**: add `.tres` files (stage colors → spritesheets later); wire a
   hotbar that swaps `player.equipped_crop`.
2. **Watering**: `TILE_WATERED` is already in the atlas — gate growth on
   watered state in `_on_day_changed` (reset to tilled each morning).
3. **Seasons**: gate `plant()` on `TimeSystem.get_season()` per-crop
   (`@export var seasons: Array[String]` on Crop).
4. **NPCs/schedules**: townsfolk run off `hour_changed` (schedule tables);
   `companion-npcs` imports deep personas as Pandora entities.
5. **Interiors/village**: one `farm.gd` TileMapLayer per farmable map;
   `world-layout` for the town graybox.
6. **Saves/menus**: godotsmith drop-ins fit the ABI unchanged — TimeSystem,
   Farm, Player, and GameManager all already implement `save_data()`.

## Validation status

`status: "validated"` — scaffolded (archive vendored + sha256 verified),
post-scaffold `--headless --import` exit 0 with zero errors, 120-frame
headless boot exit 0 with zero script errors. Boot probe:

```
DEBUG: farming-sim core loop ready — time_tick=true day=3 tilled=true planted=true stage_after_2_days=2 night=true tint_shift=true
```

(TimeTick class registered and clock live; the farmer tilled and planted the
tile underfoot; two `sleep_to_next_day()` jumps advanced the turnip two
growth stages; jumping the clock to 22:00 flipped `is_night` and shifted the
CanvasModulate tint.)
