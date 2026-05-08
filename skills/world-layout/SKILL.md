# World Layout

Author maps **deliberately**. Random tile placement produces "streets everywhere" — the most common failure mode in agent-generated games. Before any tile is placed, sketch the layout as ASCII, validate it, then transcribe it into Godot's TileMap with explicit grid coordinates.

## When this skill applies

Any task that involves placing things in a 2D grid: a city, dungeon, platformer level, arena, world map, ship interior, building floor plan. If the player will see "where things are," this skill applies.

## The cardinal rule

> **If you typed a `for` loop with `randi()` in it to place tiles, you did it wrong. Layouts are *authored*, not procedural.**

Procedural placement is acceptable ONLY when the game's premise *is* roguelike procgen — and even then, generate via a structured algorithm with named regions, not by sprinkling tiles.

## Workflow

### 1. Read the visual target

Open `reference.png` (or scan the user's pitch for layout cues). Identify:
- **Camera angle** — top-down, isometric, side-scrolling? Determines tile orientation.
- **Scale** — how big is one tile relative to the player? (16px hero on 16px tiles → 1:1; 32px hero on 16px tiles → 1:2)
- **Density** — packed urban? sparse rural? cramped dungeon?
- **Hierarchy clues** — wide roads vs. narrow alleys? Boss room vs. corridor? Main street vs. side street?

### 2. Sketch the layout as ASCII *before any code*

Write a 2D grid with single-character symbols. Save to `LAYOUT.md` so it survives later refines.

**City example (the user's reference):**

```
Legend:
. = sidewalk      H = house      O = office
# = road          S = shop       T = tree/park
| = lane line     P = parking    @ = traffic light
+ = crosswalk     ~ = water      X = landmark/anchor

       0   4   8   12  16  20  24  28
     0 . . . . . . . . . . . . . . . .
     1 . H H . S S . . . O O O O . T T
     2 . H H . S S . . . O O O O . T T
     3 . . . . . . . . . . . . . . T T
     4 + + + + + + + + + + + + + + + +
     5 # # # # # # # | # # # # # # # #
     6 # # # # # # # | # # # # # # # #
     7 + + + + + + + + + + + + + + + +
     8 . P P P . T T . . S S . H H H .
     9 . P P P . T T . . S S . H H H .
```

Anchor major landmarks first, then primary corridors (arterial roads, main halls), then secondary (side streets, branching corridors), then fill (buildings, decorations).

### 3. Validate the sketch

Before transcribing to Godot, check:
- **Connectivity** — every walkable cell reachable from spawn? Run a mental BFS or use `python -c "..."` flood-fill.
- **Density bounds** — no >5×5 unbroken block of the same tile (boring). No <2 cells between corridors (cramped).
- **Spacing constraints** — for cities: park every 8-12 blocks, traffic light every 4-6 cells on arterials. For dungeons: save room every 6-10 rooms. For levels: rest beat every 30s of forward motion.
- **Silhouette readability** — can you tell at a glance what each region IS? If it reads as "tile soup," redo.

### 4. Transcribe with explicit cell coordinates

In Godot, NEVER do this:

```gdscript
# ❌ WRONG — random scatter
for i in range(100):
    var x = randi() % map_width
    var y = randi() % map_height
    tilemap.set_cell(0, Vector2i(x, y), 0, Vector2i.ZERO)
```

Instead, do this:

```gdscript
# ✅ RIGHT — authored from the LAYOUT.md sketch
const LAYOUT = [
    ".....HHHH.SSSS.....OOOOO..TT",  # row 0
    ".....HHHH.SSSS.....OOOOO..TT",  # row 1
    "............................",  # row 2 (sidewalk)
    "++++++++++++++++++++++++++++",  # row 3 (crosswalk)
    "############################",  # row 4 (road)
    # ... etc
]

const TILE_MAP = {
    ".": Vector2i(0, 0),  # sidewalk
    "#": Vector2i(1, 0),  # road
    "+": Vector2i(2, 0),  # crosswalk
    "H": Vector2i(0, 1),  # house tile
    "S": Vector2i(0, 2),  # shop tile
    "O": Vector2i(0, 3),  # office tile
    "T": Vector2i(0, 4),  # tree tile
}

for y in range(LAYOUT.size()):
    for x in range(LAYOUT[y].length()):
        var ch = LAYOUT[y][x]
        if ch in TILE_MAP:
            tilemap.set_cell(0, Vector2i(x, y), 0, TILE_MAP[ch])
```

The string-grid approach makes layout editable as text, diff-able in git, and impossible to accidentally re-randomize.

### 5. Add hierarchy through tile *types*, not tile *count*

A real city has roads of different widths. Encode this in your tile vocabulary, not by piling more of the same tile:
- `=` arterial road (4 cells wide, lane lines, traffic lights at intersections)
- `#` collector street (2 cells wide, no lane lines)
- `,` alley (1 cell, no markings)

A real dungeon has rooms of different *kinds* (treasure, save, shop, boss, mini-boss, puzzle, breather). Sprinkle them deliberately, don't repeat the same "12×12 stone room" shape.

## Common layout templates

### Top-down city (the user's reference style)

```
Block size: 8x8 cells (4 cells building parcel + 2 sidewalk + 2 road buffer)
Arterial spacing: every 24 cells (3 blocks)
Crosswalks: at every arterial intersection
Park frequency: 1 per 4 blocks
Traffic lights: every arterial junction
Variety: rotate between residential / commercial / office blocks; max 2 same-type adjacent
```

### Side-scrolling platformer level

```
Length: 60-200 cells horizontal
Pacing rhythm: intro (calm 20 cells) → first challenge (10 cells) → breather (5) → harder challenge (15) → optional path (10) → boss approach (20) → boss room (12)
Vertical depth: 12-24 cells (with 4-8 cells of safe ground)
Required: at least 1 checkpoint per 60 cells
```

### Dungeon (top-down or isometric)

```
Room types: spawn / treasure / shop / save / puzzle / combat / mini-boss / boss
Layout: spawn → 3-5 rooms → mini-boss / shop → 4-6 rooms → boss
Connectivity: every room reachable from spawn; boss room has exactly 1 entry
Corridor length: 2-6 cells between rooms
```

### Arena (e.g. twin-stick shooter)

```
Shape: irregular polygon, NOT a rectangle (rectangles spawn-camp easily)
Size: 30x30 to 60x60 cells
Cover: 8-15% of cells are cover obstacles, distributed in clusters not uniform
Dead ends: zero — every cover cell must have a flank path
Spawn points: 4+, at boundary, equidistant
```

## Save the layout

Write `LAYOUT.md` at the project root with the ASCII sketch + legend + the cell-size constant. The next refine reads this and preserves the authored layout instead of regenerating it from scratch.

```markdown
# LAYOUT — viceland

## Cell size: 16px

## Legend
- `.` sidewalk
- `#` road (1-lane)
- `=` arterial (2-lane with center line)
- `+` crosswalk
- `H` house parcel (4×4)
- `S` shop parcel (4×4)
- `O` office parcel (4×4)
- `T` tree/park
- `@` traffic light
- `X` landmark (named in the legend below)

## Map (28 cols × 16 rows = 448 cells)
... (the ASCII grid here)

## Named landmarks
- (12, 4) X1 — police station
- (20, 14) X2 — diner ("Lou's")
```

## What NOT to do

- ❌ `for _ in range(N): set_cell(randi() % w, randi() % h, ...)`
- ❌ Generating buildings before drawing the road graph
- ❌ Uniform tile density (real places have hot spots and dead zones)
- ❌ Authoring the whole map in scaffold without the visual reference open
- ❌ Throwing away `LAYOUT.md` on refine — it's the canonical spec

## Verification

After implementing the layout, capture an in-game screenshot from a wide camera. Compare to the `reference.png`:
- Do the road widths match? (arterial = wide, side street = narrow)
- Do buildings sit on parcels with visible sidewalks?
- Are there variety beats (parks, parking lots, landmarks) breaking up the building grid?
- Can you tell what *kind* of place this is at a glance?

If the screenshot reads as "tile soup," go back to `LAYOUT.md` and redo the sketch — don't try to fix it by tweaking individual tiles.
