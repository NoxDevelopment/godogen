# Turn-Based 4X Template (Civilization-lite — eXplore / eXpand / eXploit / eXterminate, 2D)

A Civilization-lineage **turn-based 4X strategy**: eXplore a seeded map through fog
of war, eXpand by founding cities with settlers, eXploit tiles for
food/production/science/gold, and eXterminate rivals by capturing their cities. It is
OUR OWN engine with generic content (no trademarks) — a pure, seedable, deterministic
strategy engine. Scaffold with:

```bash
python templates/tools/scaffold.py tbs-4x <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`TbsEngine`** (`scripts/tbs_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls; one seeded RNG builds the map + starts
  and every turn is pure logic, so a whole game replays **byte-identically** from a
  seed and drives headlessly:
  - **Seeded map generation** — smoothed random elevation + moisture fields →
    ocean / plains / grass / forest / hill / mountain, edge-biased so continents form
    inland. Each terrain has a `[food, prod, gold]` yield and a defensive multiplier.
  - **Two civs, alternating turns**, each with **fog of war** (`seen[]` grids
    revealed by units and cities).
  - **Cities** work their **pop-best surrounding tiles** each turn: food drives
    **growth** (accumulate to a pop-scaled cost → +1 pop), production drives a
    **build queue**, and science accumulates civ-wide. Cities heal and can be
    besieged.
  - **A 4-step tech tree** researched in order: *bronze working* → spearman,
    *pottery* → granary (+food), *writing* → library (+science), *mathematics* →
    walls (+city HP/def).
  - **Units** — **settler** (founds a city with minimum spacing), **warrior**, and
    the tech-gated **spearman** — with movement points and greedy 8-direction stepping
    around impassable terrain.
  - **HP-based combat that is fully deterministic** (no RNG): effective strength =
    `str × (hp/100) × terrain_def`, damage from the attacker/defender ratio, with a
    **melee advance** onto a cleared tile.
  - **City siege + capture** — a garrison defends; otherwise the city's innate defense
    trades HP. At 0 HP an adjacent melee unit **flips ownership**, halves the pop, and
    garrisons the city.
  - **Domination victory** — a civ with no cities and no settlers is eliminated — with
    a **score fallback** at the turn cap.
  - **`checksum()`** — an FNV-1a fold over the whole state (terrain + cities + units +
    per-civ science/gold/tech) — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** game including RNG + fog.
- **Weighted-heuristic macro AI** (`ai_take_turn(civ)`) that drives **either** civ:
  research the next tech, build settlers up to a city target then military, expand
  settlers to the nearest well-spaced spot, and **hunt + attack** the nearest enemy
  unit/city. `auto_step()` / `auto_play_to_end()` drive **both** civs for a full
  self-playing game.
- **`GameManager` autoload** — runs the player's turn, then hands the AI its whole turn
  (`ai_take_turn`), plus the NoxDev save/load ABI. A `player_auto` flag lets the AI play
  your side too.
- **Play surface** (`scenes/tbs_view.tscn` + `scripts/tbs_view.gd`) — renders the
  **fogged** map, team-coloured cities (pop + HP) and units in code. **Click** selects
  your unit/city or moves/attacks; **Enter** ends the turn; **F** founds a city; **1-6**
  set the selected city's build; **Tab** cycles units; **A** auto-plays; **R** restarts.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — map-gen, fog, city yields + growth + production, the tech tree, movement,
deterministic combat, siege/capture, victory, and the macro AI — lives in `TbsEngine`
as pure data + functions driven by one seeded RNG. The view only reads state and issues
commands, which is why the whole game is playable and testable with **no UI**, and why
it **drops in as the strategy core of a larger game**: keep the engine, call the
`move_unit` / `attack` / `found_city` / `set_city_build` / `end_turn` command API, read
`cities` / `units` / `civ_techs`.

Because turns are pure and the only randomness is the seeded map, `checksum()` after any
number of turns is identical across two separate processes — the same property a
**deterministic multiplayer 4X** needs, and what lets NoxQA smoke-run a whole AI-vs-AI
game headlessly in CI.

## How to extend

1. **More units/buildings**: add to `UNIT_DEF` / `BUILDING_DEF` (+ its tech gate); the
   build queue, combat, and save/load pick it up.
2. **Deeper tech tree**: extend `TECHS` + `TECH_COST` and gate new unlocks — the AI
   researches in list order automatically.
3. **Tile improvements / workers**: add a worker unit that builds farms/mines that bump
   a tile's yield, and factor it into `_city_yields`.
4. **Diplomacy / more civs**: raise `N_CIVS`, give each civ a stance, and branch the AI
   target selection on war/peace.
5. **Hex grid**: swap the square grid + `_dirs8` for axial hex coords and a 6-neighbour
   step; the yield/city/combat logic is grid-agnostic.
6. **Real pathfinding + a minimap**: the greedy stepper can become a cached BFS
   (the roguelike template's BFS is a drop-in reference), and the per-civ `seen[]` grid
   is ready for a fog minimap.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop
   in unchanged; the whole game already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **20-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes
(`PROBE PASS`):

- **seed determinism** — the same seed played to completion twice yields an identical
  final `checksum()`; a **different seed diverges**.
- **partial determinism** — 30 turns of the same seed produce an identical mid-game
  checksum across runs.
- **seeded map** — two seeds produce **different initial states**.
- **eXpand + eXploit** — the AI actually **founded extra cities** (max 7 in the
  validated game) and **completed research** (all 4 techs).
- **real decision** — `auto_play_to_end` reaches a genuine **winner** by domination,
  not a stalled cap draw. Validated: a seeded AI-vs-AI game ends at **turn 60**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> end_turn=60 winner=0 max_cities=7 max_tech=4
# → PROBE PASS
```
