# City Builder Template (grid economy, 2D)

A grid-based city-builder base: place buildings on a tile grid, each producing or
consuming resources on a steady economy tick, with a live resource HUD and a
building palette. Data-driven building catalogue + full save/load. Scaffold with:

```bash
python templates/tools/scaffold.py city-builder <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No third-party addons —
pure first-party Godot, so it imports clean anywhere.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the whole economy as
  pure, headless-testable logic:
  - Resources: **gold / food / population**.
  - A **data-driven building catalogue** (`BUILDING_TYPES`): each entry sets cost,
    per-tick gold/food deltas, population added, whether it needs population to
    operate, and a blockout colour. Ships three — **House** (+2 pop, eats 1 food),
    **Farm** (+3 food), **Market** (+4 gold, needs population). Add a building by
    adding one dictionary entry.
  - `place()` / `demolish()` (occupancy + affordability checked), `tick()` (each
    building produces/consumes; markets idle at zero population; resources floor
    at 0), `reset()`.
- **City view** (`scenes/main.tscn` + `scripts/city.gd`) — a 16×9 build grid drawn
  in code (blockout colours; swap for sprites later), left-click to place the
  selected building, right-click to demolish, a 1-second economy tick, a resource
  HUD, and a building palette that disables unaffordable options and highlights
  the selection. Esc pauses (the tick halts; input still toggles pause).
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (so
  godotsmith's `save_system` drop-in persists the whole city); a `pause` input
  action; `"scalable_text"` on the HUD labels + palette buttons.

## The economy (the part worth understanding)

Buildings are entries in `GameManager.BUILDING_TYPES`; `tick()` walks the placed
grid and sums each building's deltas into gold/food. Population is derived from
houses (`_recompute_population()` on every place/demolish) and gates the market —
so the loop is: farms feed houses, houses make population, population powers
markets, markets make gold, gold buys more buildings. A starter economy (1 house
+ 1 farm + 1 market) nets positive food and gold.

## How to extend

1. **Buildings**: add to `BUILDING_TYPES` — e.g. a `mine` (`gold +6, needs_pop`)
   or a `granary` (raises a food cap you add). The palette + tick pick it up with
   no other changes.
2. **Art**: replace the `_draw()` blockout rects with sprites (a `TileMapLayer`
   or per-building `Sprite2D`) keyed by type_id — pair with the `pixel-perfect`
   or asset-gen skills (see the genre→workflow recipes: tiles via
   `zit-seamless-tile`, building icons via `qwen-icon`).
3. **Win/lose + goals**: read `GameManager.population`/`gold` on the tick for a
   target (reach N population) or a fail (food hits 0 for M ticks).
4. **Saving/menus**: godotsmith `save_system` / `menu_system` / `settings_system`
   drop in unchanged; the city (resources + placed grid) already serialises via
   `GameManager.save_data()`.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0, and a headless
economy probe: places a house+farm+market, runs ticks, and asserts affordability
gating, population derivation, market-needs-population, resource flooring, and
save/load round-trip — all green, zero script errors.
