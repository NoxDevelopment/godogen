# Falling Sand Template (cellular-automata physics sandbox, 2D)

A falling-sand physics **sandbox** in the Noita / The Powder Toy / Sandspiel
lineage: a cellular-automata world where every cell is a **material** that obeys
deterministic physics rules, and the player paints materials with a brush and
watches emergent chemistry. Scaffold with:

```bash
python templates/tools/scaffold.py falling-sand <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`SandWorld` engine** (`scripts/sand_world.gd`, `class_name SandWorld`,
  `RefCounted`) — the whole simulation as pure, seedable, headless-testable
  logic with **no engine/scene dependencies**:
  - A **W×H grid of cells** stored in packed arrays: `_cells` (a material id per
    cell) + `_aux` (one byte of per-cell state — fire/gas lifetime, lava
    cool-timer). Fast, cache-friendly, and serializable.
  - **14 materials** with distinct behaviour: `EMPTY`, `SAND` (powder, piles at
    a rest angle), `WATER` (liquid, spreads + levels), `STONE` (static wall),
    `WOOD` (flammable static), `PLANT` (flammable, grows on water), `OIL`
    (light flammable liquid), `LAVA` (slow, ignites + cools), `FIRE` (spreads,
    burns out), `SMOKE` (rises, dissipates), `STEAM` (rises, condenses), `ACID`
    (dissolves solids), `ICE` (melts near heat), `ASH` (fire residue powder).
  - **11 reactions** (real chemistry, all probe-verified): water+lava →
    stone+steam · fire ignites wood/oil/plant (fuel consumed) · lava ignites
    flammables · fire burns out → ash/empty + smoke · lava cools → stone · acid
    dissolves a solid (both consumed) · watered plant grows into empty · steam
    condenses → water · ice melts near fire/lava → water.
  - A **density model** so fluids/powders sink through anything lighter (water
    sinks through oil → they separate; sand sinks through both).
  - **Brush API**: `paint(material, x, y, radius)` stamps a filled disc;
    `clear()` wipes the grid.
  - `snapshot()` / `restore()` of the **entire grid + RNG state** (base64-packed,
    JSON-portable) — a fully replayable save.
- **Sandbox screen** (`scenes/main.tscn` + `scripts/main.gd`) — built in code:
  the grid is rendered one-pixel-per-cell (material→colour) to an `ImageTexture`
  on a nearest-filtered `TextureRect`, stepped on the physics tick. A **material
  palette** (buttons), **mouse-drag painting**, a **brush-size** stepper, and
  **pause / step / clear** controls. A live status line reads cell counts.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the
  whole grid + RNG state persist); `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

**The step is a pure function of `(grid, tick, seeded RNG)`.** Each `step()`
scans rows **bottom→top** (so a falling cell resolves in one pass) and each row
**left→right on even ticks / right→left on odd ticks** (cancelling directional
bias) — the scan order depends only on `tick`. A cell that moves or transmutes
is flagged in a per-tick `_moved` mask and is **never touched twice**, so every
cell updates at most once per step: the step is **bounded O(W·H)** with no
infinite loops. Every non-deterministic choice — which diagonal a grain slides,
whether a flame spreads this tick, where a plant grows — is drawn from a
**seeded RNG** whose state is part of save/load. Therefore **the same seed +
the same scripted brush inputs produce a byte-identical grid after N steps**,
and replays/saves are exact. That is why the whole thing is playable and
testable with **no UI**, and drops in as a physics layer of a larger game: keep
the engine, call `paint()` + `step()`, read `get_cells()`.

## How to extend

1. **More materials**: add an id + a colour + a movement/reaction branch in
   `_update_cell`. Powders reuse `_update_powder`, liquids `_flow`, gases
   `_update_gas`; give it a `DENSITY` entry and (if reactive) a rule.
2. **Rigid bodies / structures**: stamp `STONE`/`WOOD` shapes as level geometry;
   the CA flows around them for free.
3. **Digging / destructible terrain**: a bullet or explosion is just a brush —
   `paint(EMPTY, …)` to carve, `paint(FIRE, …)` to burn.
4. **Temperature field**: promote `_aux` to a heat value and drive melting /
   ignition / boiling off it for richer thermodynamics.
5. **Art**: swap the flat material colours for a palette texture or per-material
   shaders (glow for lava/fire, translucency for water/steam).
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the world already serialises through `save_data()`.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with
zero script errors (all vars typed), and six headless probes each `fails=0`:

- **Physics probe**: a sand column falls + piles into the bottom rows (count
  conserved), a water column spreads/levels (span 1→30), nothing leaves the grid
  bounds, and every cell holds a valid material id.
- **Reactions probe**: each of the eight-plus key reactions fires within a few
  steps in its own fresh world — water+lava→stone+steam, fire consumes
  wood/oil, lava cools to stone, acid dissolves stone (and depletes), a watered
  plant grows, steam condenses to water, ice melts by lava.
- **Determinism probe**: same seed + same scripted brush inputs → byte-identical
  cells/aux/RNG-state after 70 steps; a different seed diverges where randomness
  is involved.
- **Conservation / bounds probe**: sand is conserved while only falling; a
  chaotic all-materials world (with cells stamped at every edge) keeps its grid
  size, never produces an invalid id, and every step terminates.
- **UI-build probe**: the scene builds (grid texture + populated palette
  present), a scripted paint changes the grid, and the rendered frame shows it.
- **Save/load probe**: paint + step + snapshot; mutate; restore → grid, aux,
  RNG state and tick all equal the snapshot, and the restored world resumes
  byte-identically to a control that never left.
