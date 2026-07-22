# Battlemap Assets — the tactical-scale library, architectural conventions, and VTT stamp system

[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) covers the **region/world** symbol
vocabulary (a peak is a *sign*, placed sparsely). This doc is its **tactical-scale
sibling**: the **battlemap** (a.k.a. VTT map) — a top-down, grid-scaled plan of a
single location (a dungeon room, a tavern, a forest clearing) where a stamp is not a
sign for "a building" but the *building itself* at 1 grid square ≈ 5 ft. Different
scale, different rules, different asset tree. This is our bar for
[MAP_TYPES.md](MAP_TYPES.md)'s "VTT battlemap" and "dungeon" types and the tabletop
layer of the narrative VTT ([VTT_TOOLING_GAPS.md](VTT_TOOLING_GAPS.md)).

The competitor to clone is **Dungeondraft** (its pack format is openly documented and
already round-trips to every major VTT), with **Inkarnate** for stamp breadth,
**Forgotten Adventures / 2-Minute Tabletop** for asset ecosystems, and **Roll20 /
Fantasy Grounds / d20PRO** for the wall/lighting model. Read
[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) for the idiom and
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) (`battleMap.ts`) for our implementation
touchpoints.

> **Why a battlemap is not a region map:** it is a **horizontal section cut ~4 ft above
> the floor** (architectural convention), viewed straight down, at a *fixed metric
> scale* (5 ft/cell). Walls block movement and sight; the grid is load-bearing; props
> are placed by a human, not a density model. The region-map "restraint" law relaxes —
> a furnished tavern *should* be busy — but coherence, one light, and top-down
> readability are absolute.

---

## 0. The three primitives of a battlemap (mirror Dungeondraft's tool model)

Every battlemap tool decomposes into the same small set of tools. Design to these:

- **Terrain / floor brushes (area)** — seamless textures painted as fills: grass,
  cobble, plank, dungeon flagstone, water, lava, cave floor. In Dungeondraft these are
  **seamless PNGs (~2048²) whose alpha channel encodes elevation blending** (brighter
  alpha = "higher," so edges blend instead of hard-cutting). Also **patterns**
  (seamless fills, with a *colorable* variant where a red-masked region is recolored
  at paint time).
- **Walls / paths / portals (line)** — drawn along a **spline/polyline**, textured by a
  tileable strip:
  - **Wall** = a **black-and-white seamless strip, 256 px wide**, tiling left→right,
    paired with a `_end.png` cap. The tool **auto-generates a line-of-sight blocker
    down the wall centerline** — this is the whole dynamic-lighting story (see §3).
  - **Path** = a long seamless strip with a 1px transparent gap top/bottom, drawn as a
    **smooth curve** (roads, rivers, fences, curbs).
  - **Portal** (door/window) = a PNG **exactly 256 px wide, centered**; **placing it
    auto-cuts the wall to fit**, and it can be flagged "allow light" (a window passes
    light while blocking movement).
- **Objects / props (point)** — PNGs at **256 px = 1 grid inch** (a 5 ft cell). Tables,
  barrels, torches, statues. A *colorable* object paints its recolor region red and
  tags "Colorable." **Lights** are a special object: a grayscale **square** PNG where
  white pixels define the light's shape/gobo.

Tilesets are the corridor-intelligent flavor of floors: **Simple (16 tiles)** random
fill, **Smart (32)** = 16 fill + 16 auto-placed corridor pieces (T-junctions, corners,
dead-ends when you draw 1-cell corridors), **Smart Double (64)** = same with more
variety.

---

## 1. Real top-down architectural drawing conventions (the grammar to render)

Battlemap art is a **re-skin of real floor-plan drafting**. Encode this grammar or the
map reads wrong. Sources: Cedreo, SmartDraw, MT Copeland, Coohom floor-plan-symbol
references (see Sources).

### 1a. Line-weight hierarchy = z-layer hierarchy (the #1 convention)
A plan cut ranks lines by *how close the cut passes*:
- **Heaviest = things the cut passes THROUGH** — walls, columns. → render on **top**,
  as textured bands.
- **Medium = objects below the cut you look down on** — furniture, fixtures. → **mid**
  layer, lighter presence.
- **Lightest = surface/texture** — floor tile joints, hatch, material fill. → **bottom**
  layer.
- **Dashed = hidden/overhead** — beams, soffits, upper cabinets, anything above the cut.
- **Exterior/load-bearing walls thicker than interior partitions.**

**⇒ our renderer:** map these four ranks to explicit z-layers in `battleMap.ts`
(floor-pattern < furniture/props < walls/portals < overhead-dashed < grid < effects <
tokens). Never let a prop render over a wall.

### 1b. Walls — **poché**
A wall is **two parallel lines separated by the wall thickness, with the gap filled**
("poché" — solid fill or masonry hatch). This solid-filled thickness is *the*
signature of a cut wall vs a mere line. Dungeondraft's 256 px B/W wall strip **is** the
poché band, textured with stone/brick/wood. Exterior walls thick; interior partitions
thinner (and may use a different hatch).

### 1c. Doors — the **quarter-circle swing symbol**
- **Break the wall poché** at the opening (gap width = door width).
- **Door leaf** = a straight line perpendicular to the wall (open position), length =
  door width.
- **Swing** = a **90° arc (quarter circle)** from the leaf tip to the closed jamb, with
  **radius = the leaf/door width**; the arc's side + direction show which way it opens.
- **Double door** = two mirrored leaves + two arcs (reads as "M"). **Sliding** =
  parallel rectangles + slide arrow (no arc). **Pocket** = leaf vanishing into the wall
  thickness. **Bifold** = two small peaks.

**⇒ our renderer:** a door is a **portal prop that cuts the wall** and stores an
open/closed state; render the wooden-door art for the closed state and (optionally) the
swing-arc + gap for the open state. The portal is a **movable LoS break** (§3).

### 1d. Windows — **break filled with parallel lines**
A window = a break in the wall poché **filled with ~3 parallel lines** (outer faces +
glazing centerline) running the opening's length. It **passes light/sight but blocks
movement** — the "allow light" portal flag.

### 1e. Stairs
- **Rectangle divided by evenly-spaced parallel lines** (one per tread).
- **Direction arrow** along the run centerline labeled **UP** / **DN**.
- **Break line** (zigzag) where the section clips the flight: treads below the cut
  **solid**, treads continuing above **dashed**.
- **Spiral** = circle of pie-wedge treads around a center pole.

### 1f. Columns / beams / furniture
- **Column** = small filled square/circle (8–16 in). **Beam** = **dashed** line between
  supports (overhead ⇒ dashed).
- **Furniture top-down silhouettes** (drawn medium weight, never as heavy as walls):
  **bed** = rectangle + smaller pillow rectangle at the head; **table** = circle/oval/
  rect, often ringed by chairs; **chair** = small back-facing shape; **sofa** = long
  rectangle + thin back-rectangle on one long edge; **sink/toilet/tub** = oval/rounded
  fixtures (toilet = oval bowl + tank rect; tub = large rounded rect); **stove** =
  square + 4 burner circles.

### 1g. Scale
Architectural standard **¼" = 1'-0" (1:48)** for rooms, **⅛" = 1'-0" (1:96)** for whole
buildings; metric **1:50 / 1:100**. Always a **scale bar** (alternating black/white
segments). VTT bridge: **grid cell = 5 ft ≈ 256 px/cell** — directly interchangeable
with a ¼"=1' plan. Keep our battlemap export at a stated px/cell so it drops into any
VTT at true scale.

### 1h. Fantasy translation (real grammar → rendered art)
| Drafting symbol | Battlemap render |
|---|---|
| Wall poché | textured stone/brick/wood **wall strip** (256px B/W band) + auto LoS centerline |
| Door swing arc | **door portal** prop that cuts the wall; movable LoS break, open/closed state |
| Window 3-line break | **barred/glazed portal** that passes light (blocks movement) |
| Floor hatch/tile pattern | seamless **terrain/pattern brush** (cobble, plank, cave) |
| Furniture symbol | rendered **top-down prop** (table, throne, altar, bed) |
| — (no real equivalent) | **dungeon dressing**: barrels, bones, rubble, braziers (biggest bucket) |

---

## 2. The full battlemap asset CATEGORY TREE + realistic counts

Counts are **per themed pack** (what a competitor ships in one set), triangulated from
the 2-Minute Tabletop "Dungeon Wall & Floor" pack (**272 objects / 17 walls / 33
patterns**), Inkarnate's battlemap packs (**2,200+** assets across Castle/Dungeon/Camp/
Tavern), and Forgotten Adventures' consolidated multi-thousand library. A **full
library** (all themes) multiplies each bucket ~5–15×. **Objects/dressing always
dominate (~50–60% of total asset count.)**

### TERRAIN / FLOORS — seamless brushes + patterns (~30–60/theme; 200+ full)
Grass, dirt/mud, stone floor, wood plank, cobblestone, water (still/flowing), lava,
sand, snow, cave floor, dungeon flagstone, marble, carpet/rug fills. *(2MT dungeon
pack: 33 floor patterns, each also a terrain brush.)* Ship each as a seamless PNG with
alpha-elevation blending + a colorable variant where sensible.

### WALLS / STRUCTURE — wall strips + portals + vertical (~15–40/theme; 100+ full)
- **Wall strips:** stone, brick, worked-block dungeon, wood, cave wall, cliff/rock
  face, fence, hedge, palisade. *(2MT: 17 walls, each mirrored as a path.)*
- **Portals/openings:** wooden door, double door, iron door, gate, portcullis, secret
  door, window, arrow slit, archway.
- **Vertical structure:** pillar/column, buttress, stairs (straight/spiral), ramp,
  bridge.

### FURNITURE / INTERIOR — top-down props (~60–120/theme)
Tables (dining/round/work), chairs, stools, benches, beds/bedrolls, chests/coffers,
bookshelves, cabinets, wardrobes, thrones, altars, bars/counters, kegs, desks, rugs,
tapestries/wall hangings, fireplaces, anvils, forges.

### DUNGEON DRESSING — the largest object bucket (~80–200+/theme)
Barrels, crates, sacks/bags, pottery/urns, bones/skeletons/skulls, rubble/debris,
chains/manacles, cobwebs, torches/wall sconces, braziers, candles/candelabra,
cauldrons, statues/idols, coin/treasure piles, cages, weapon racks, blood/gore props.
*(2MT's 272 objects are dominated by exactly this category.)*

### NATURE OBJECTS — outdoor props (~60–150/theme)
Trees (deciduous/pine/dead/palm), bushes/shrubs, rocks/boulders (multi-size), logs,
stumps, roots, flowers/plants, ferns, mushrooms, grass tufts, lily pads, reeds, vines,
crystals/stalagmites (cave).

### EFFECTS / OVERLAYS — decals & atmospherics (~40–80/theme; Inkarnate ships 65+ in one pack)
Blood splatter, scorch/burn marks, magic circles/runes, fog/mist, smoke, fire/flame,
water splash, light gradients & gobos (radial, torch, filtered/dappled), shadow
overlays, sparkles/glow, **grid overlay**, cracks/damage decals.

### LIGHTS — functional (grayscale square, white = light shape) (~10–30)
Radial soft/hard falloff, torch flicker, gobo shapes (window-cast, leaf-dappled,
grate), colored ambient, sunbeam.

**Budget:** a serious themed pack ≈ **300–500 discrete assets**; a full commercial
library ≈ **thousands–tens of thousands** across themes. Plan generation quotas by
bucket ratio: **dressing > nature > terrain/patterns > walls/portals > effects >
lights.**

---

## 3. Walls, line-of-sight & dynamic lighting — the model to adopt

The whole dynamic-lighting feature reduces to two mechanics:
1. **Auto-generate a LoS blocker down each wall's centerline** as it's drawn, and
2. **Auto-cut the wall + insert a movable LoS break when a portal (door/window) is
   placed.**

**Adopt the Roll20 barrier color taxonomy** as the internal LoS model (clean, proven):
- **Blue** = walls / immovable blockers (also tree lines, cliffs).
- **Orange** = doors, secret doors, curtains — **movable/removable** LoS breaks.
- **Cyan** = transparent barriers — windows, cell bars, portcullis (block movement,
  **pass light/sight**).
- **Pink** = one-way lines.

Lights are **light-emitting tokens/objects** (torch sconce, campfire, lamp) with
**Range / Intensity / Color** (+ flicker); **walls and portals cast shadows**, props
generally don't. Fantasy Grounds adds a **map-level light direction + shadow length**;
Dungeondraft lets a light ignore walls via a shadow toggle.

**Interchange:** the de-facto standard is the **Universal VTT** file (`.dd2vtt` /
`.uvtt` / `.df2vtt`) carrying **floor image + wall lines + portals + light sources**.
Roll20 imports via the UniversalVTTImporter API script. **If our battlemap exporter
emits `.dd2vtt`, our maps drop into Foundry/Roll20/Fantasy Grounds with lighting
intact** — a major interoperability win and the single highest-leverage export target.

---

## 4. Pack format — clone Dungeondraft's layout verbatim (it's the interchange standard)

```
[PackName]/
├── preview.png            (256 x 320)
├── pack.json              (Name, Author, Version, unique ID;
│                           allow_3rd_party_mapping_software_to_read: true)
├── textures/
│   ├── objects/           PNG props, 256 px per grid inch (+ colorable = red-mask region)
│   ├── terrain/           seamless 2048², alpha = elevation blend
│   ├── materials/         paired name_tile.png + name_border.png (≥1px gap top/bottom)
│   ├── tilesets/          simple 16 / smart 32 / smart_double 64 tiles
│   ├── patterns/          normal/ (fixed) + colorable/ (red-mask recolor)
│   ├── walls/             B/W seamless strip 256px wide + name_end.png cap
│   ├── paths/             long seamless strip, 1px transparent gap top/bottom
│   ├── portals/           PNG exactly 256px wide, centered (doors/windows)
│   └── lights/            grayscale square PNG, white = light passes
└── data/
    ├── default.dungeondraft_tags      (Tags + Sets grouping)
    ├── tilesets/[name].dungeondraft_tileset  ({Path,Name,Type,Color})
    └── walls/[name].dungeondraft_wall
```

**⇒ our renderer / asset pipeline:** this is the target our battlemap asset kits and
`battleMap.ts` stamp registry should conform to, bound by **stable ID** through the
[asset-manifest](../asset-manifest/SKILL.md) (same contract as region stamps in
[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) §3). Climb the same reuse ladder:
[asset-reuse](../asset-reuse/SKILL.md) → owned/CC0 battlemap kits on NAS + Forgotten
Adventures/2MT-style packs (check `pieces/asset-kits/_library/BY_THEME.md`) → derive/
restyle → generate LAST via [image-pipeline](../image-pipeline/SKILL.md). Record every
license for [credits](../credits/SKILL.md).

---

## 5. Consistency & the "one hand" test still apply (tactical scale)
Every §2 consistency rule from [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) holds:
one idiom, one line weight, **one global light direction** (top-down battlemaps
conventionally light from the top of the frame; shadows fall consistently down-frame),
one palette, transparent alpha with **no baked grid/shadow** (grid + lighting are
composited *once, globally* by the renderer). A prop pack drawn by five different hands
under five light directions fails the same way a region symbol set does — cull before
adding breadth.

---

## Actionable summary (battlemap)
1. **Clone the Dungeondraft pack layout** (§4) — it round-trips to every VTT; bind by
   stable ID.
2. **Emit `.dd2vtt` on export** (§3) — floor + walls + portals + lights — so maps drop
   into Foundry/Roll20/FG with lighting intact.
3. **Wall = poché band + auto LoS centerline; portal = auto-cut + movable LoS break**
   (§1b–d, §3); adopt Roll20's blue/orange/cyan/pink barrier taxonomy.
4. **Encode drafting grammar as z-layers** (§1a): floor-pattern < furniture < walls <
   overhead-dashed < grid < effects < tokens.
5. **Budget assets by bucket** (§2): dressing dominates (~272 in one dungeon pack),
   then nature, terrain patterns (~33), walls (~17), effects, lights — target ~300–500
   per themed pack.

---

*Siblings: [SKILL.md](SKILL.md) · [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) ·
[MAP_TYPES.md](MAP_TYPES.md) · [MAP_REFERENCE_GALLERY.md](MAP_REFERENCE_GALLERY.md) ·
[VTT_TOOLING_GAPS.md](VTT_TOOLING_GAPS.md) ·
[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) ·
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) ·
[../asset-reuse/SKILL.md](../asset-reuse/SKILL.md) ·
[../asset-manifest/SKILL.md](../asset-manifest/SKILL.md) ·
[../image-pipeline/SKILL.md](../image-pipeline/SKILL.md)*

## Sources
- Dungeondraft Custom Assets Guide (official wiki): https://github.com/Megasploot/Dungeondraft/wiki/Custom-Assets-Guide
- Dungeondraft-GoPackager: https://github.com/Ryex/Dungeondraft-GoPackager
- Ultimate Guide to Dungeondraft — Packing Assets: https://dungeondraft-encyclopaedia.gitbook.io/guide/custom-assets-and-mods/importing-assets/packing-your-assets
- 2-Minute Tabletop — Beginner's Guide to Dungeondraft Custom Assets: https://2minutetabletop.com/beginners-guide-to-dungeondraft-custom-assets/
- 2-Minute Tabletop — Dungeon Wall & Floor Assets Pack (per-category counts): https://2minutetabletop.com/product/dungeon-wall-floor-assets-pack/
- Arkenforge — Preparing Dungeondraft Asset Packs: https://arkenforge.com/dungeondraft-asset-packs-how-to/
- Cartography Assets — Dungeondraft category: https://cartographyassets.com/asset-category/specific-assets/dungeondraft/
- Forgotten Adventures — Dungeondraft Integration 3.5: https://www.forgotten-adventures.net/product/map-making/assets/dungeondraft-integration/
- Groupfinder — Dungeondraft Battlemap Guide: https://groupfinder.eu/library/dungeondraft
- Encounter Library — Dungeondraft Light & Text Tools: https://encounterlibrary.com/dungeondraft-basics/lighting-text-tools/
- Roll20 — UniversalVTTImporter (dd2vtt import): https://app.roll20.net/forum/post/11268197/
- Roll20 — How To Set Up Dynamic Lighting: https://help.roll20.net/hc/en-us/articles/4403861702679-How-To-Set-Up-Dynamic-Lighting
- Roll20 Wiki — Layers: https://wiki.roll20.net/Layers
- Roll20 — Dynamic Lighting tips (barrier color coding): https://app.roll20.net/forum/post/10223959/
- Studio WyldFurr — Map Building in Fantasy Grounds Unity: https://www.wyldfurr.com/tutorial-map-building-in-fantasy-grounds-unity/
- Fantasy Grounds — Adding Lights to Maps and Tokens: https://fantasygroundsunity.atlassian.net/wiki/spaces/FGCP/pages/1312784387/
- d20PRO Guide — Draw Tools (walls/doors/FoW): https://guide.d20pro.com/gg_draw_tools.html
- Inkarnate — Updates/changelog (asset counts): https://inkarnate.com/updates
- Cedreo — Floor Plan Symbols: https://cedreo.com/blog/floor-plan-symbols/
- SmartDraw — Floor Plan Symbols: https://www.smartdraw.com/floor-plan/floor-plan-symbols.htm
- MT Copeland — Complete Guide to Blueprint Symbols (line weights/scale): https://mtcopeland.com/blog/complete-guide-to-blueprint-symbols-floor-plan-symbols-mep-symbols-rcp-symbols-and-more/
- Coohom — Stair Symbol on a Floor Plan: https://www.coohom.com/article/symbol-for-stairs-on-a-floor-plan
