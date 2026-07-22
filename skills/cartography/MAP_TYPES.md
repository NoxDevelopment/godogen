# Map Types — the catalog, each with purpose, conventions, exemplar, and our recipe

There is no such thing as "a map." There are *map types*, each a distinct genre
with its own purpose, conventions, forbidden moves, and reference exemplar. A world
map and a subway diagram are as different as a novel and a spreadsheet. The #1
category error is applying one type's idiom to another (parchment texture on a
transit diagram; rhumb lines on a dungeon). **Pick the type first** — it dictates
every downstream choice.

This is the catalog. For each: **Purpose** (the argument it makes), **Conventions /
must-haves** (the non-negotiables that make it read as that type), the **Reference
exemplar** (the tool or artifact to sit beside at the same scale — verified below),
and **Our recipe** (how Map Studio makes it, or would). What Map Studio **ships
today** is called out per type; the rest is **roadmap**.

Read [SKILL.md](SKILL.md) for the Ten Laws and the build pipeline every type shares,
[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) and
[REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md) for the two style traditions, and
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) — the gate every render clears before
it counts as done.

> **Map Studio today** renders two full **themes** in `mapStudio.ts`
> (`MapTheme = "parchment" | "blueprint"`) with square/hex grid overlays, plus a
> separate **battlemap** renderer (`battleMap.ts`). So of the twelve types below,
> **parchment region/world**, **blueprint star/sector**, and **VTT battlemap** ship;
> the rest are roadmap in priority order noted per type.

---

## Anatomy shared by (almost) every type

Regardless of type, most maps carry the same **marginalia furniture**, and getting
it right (or knowing when to omit it) is half of reading as a pro artifact:

- **Title / cartouche** — names the sheet; decorative for fantasy, plain header for
  real/technical maps.
- **Orientation** — compass rose or north arrow. *Omit* on schematic/transit
  diagrams where direction is not the point.
- **Scale** — a scale bar (never only "1 inch = 1 mile" text, which breaks on zoom/
  reprint). *Omit* on topology-first diagrams (subway) where scale is deliberately false.
- **Legend / key** — mandatory the moment color or symbol encodes data (political,
  thematic, topographic); optional when symbols are self-evident (parchment region).
- **Neatline / border / graticule** — the frame; a coordinate grid on real maps.
- **Attribution / credit** — provenance per [../credits/SKILL.md](../credits/SKILL.md).

The **type decides which furniture is required, optional, or forbidden.** A subway
diagram with a scale bar is as wrong as a portolan chart without a wind rose. Each
type below flags its non-negotiables.

---

## 1. World / Continent map

**Purpose.** Establish the whole known world at a glance — the shape of land and
sea, the major ranges and rivers, the realms and their capitals. It is the
frontispiece; it makes the *argument that this world is coherent and large*.

**Conventions / must-haves.**
- Coastline is the primary read; figure–ground must be unambiguous (land as figure,
  sea as ground) via coastal echo lines, a land tint, or a vignette (Law 4).
- Relief shown as **ranges on spines**, not scattered peaks; major rivers run from
  high ground to sea and never split downstream except deltas (Law 5).
- Restraint: at world scale most of the sheet is open — sea, plains, ice. Only
  world-tier features earn ink (Law 1). Label hierarchy tops out at **world/ocean**
  names, letterspaced very wide (Imhof).
- A compass rose, a scale bar, a title cartouche, and tasteful sea marginalia.

**Reference exemplar.** Tolkien's *Middle-earth* (the Baynes/Christopher lineage);
procedurally, **Azgaar's Fantasy Map Generator** for continent-scale tectonics,
climate, rivers, states, and burgs. Wonderdraft for the hand-inked look.

**Our recipe.** Parchment theme. Landmass + coastline → heightfield → watershed →
rivers → biomes (TERRAIN_AND_BIOMES) → ridgeline-walked ranges → sparse biome
symbols → realm capitals/roads → composite (pooled shadow, NW light, paper pass) →
world/region labels → cartouche + rose. **Roadmap** (parchment engine ships;
world-scale generation depth toward Azgaar is the growth edge).

---

## 2. Region / Kingdom map (parchment fantasy) — SHIPS

**Purpose.** The workhorse fantasy map: one kingdom or region at adventure scale —
the map a party actually travels across. Enough detail to place a quest, not so much
it becomes a battlemap.

**Conventions / must-haves.**
- The **aged-parchment** ground: paper fiber, warm sepia palette, edge vignette,
  the "drawn by one hand" symbol set (SYMBOLOGY_AND_STAMPS).
- Ranges, forests belting foothills, rivers to the sea, roads through valleys
  connecting towns; ruins, castles, bridges, mines as narrative anchors.
- Settlement size ramp (village → town → city → capital) with matching label tiers,
  names curved along features, collision-avoided (Law 8).
- Coastal echo hatching; a compass rose; a cartouche title; a border frame.

**Reference exemplar.** **Wonderdraft** — the hand-inked region-map benchmark: our
*floor* for cohesive symbols, coastal echo, believable ranges/forests, roads.
Inkarnate for symbol breadth.

**Our recipe.** This is the primary shipping path — parchment theme in
`mapStudio.ts` over the P9 sepia-ink stamp core in `mapStampAssets.ts`, the muted
`PARCHMENT` palette, labels via the [typography](../typography/SKILL.md) faces
(Cinzel / Uncial Antiqua). Follow the SKILL build pipeline end to end; grade against
CRITIQUE across ≥3 seeds vs Wonderdraft. **Ships today** (the flagship type).

---

## 3. City / Town map

**Purpose.** One settlement at street scale — districts, walls, gates, the river and
its bridges, the market, the keep. The map for urban adventures and "you arrive at
the city" set-pieces.

**Conventions / must-haves.**
- Street network reads as a *network* (organic medieval tangle or planned grid),
  not noise; blocks of buildings, not a texture of dots.
- City wall + gates + towers; a river/harbor with bridges; named districts;
  landmark buildings (temple, keep, market, guildhall).
- A coat of arms / cartouche; a scale appropriate to walking; a north arrow.

**Reference exemplar.** **Watabou's Medieval Fantasy City Generator** — the
benchmark for procedural medieval layouts: it grows a city of requested size with
optional walls/rivers, named districts, organic streets, a coat of arms, and PNG/SVG
export, and it interoperates with Azgaar (see
[Medieval Fantasy City Generator](https://watabou.itch.io/medieval-fantasy-city-generator)).
Inkarnate for hand-painted city maps.

**Our recipe.** Procedural district/street growth on the parchment ground; building
blocks stamped from a city-architecture symbol subset; walls/roads via the path
tool; heraldry from the décor family. **Roadmap** — high priority (it is the
narrative-VTT's "enter the city" companion to the region map).

---

## 4. VTT battlemap (Dungeondraft idiom) — SHIPS

**Purpose.** The tactical tabletop surface — a single encounter at figure scale,
gridded so minis move square by square. This is the VTT's play surface, not a
frontispiece.

**Conventions / must-haves.**
- A precise **grid** (square or hex) at a fixed pixel pitch, export-aligned so it
  drops into Foundry/Roll20 at grid scale.
- **Tiled/painted terrain** with blended textures (grass/dirt/sand/stone/water with
  edge foam), **walls** (that block movement and light), **objects/props**
  (furniture, clutter, scatter), and **dynamic lighting** (light sources casting
  shadows off walls).
- Export at the right resolution (px-per-grid) with wall/light data where the VTT
  consumes it.

**Reference exemplar.** **Dungeondraft** (by Megasploot, of Wonderdraft) — the VTT
battlemap benchmark: smart wall/lighting/scatter tools, multi-layer terrain
brushes, water with edge foam, and export to Foundry/Roll20/Universal VTT with wall
+ light data (see [Dungeondraft guide](https://groupfinder.eu/library/dungeondraft)).

**Our recipe.** The dedicated `battleMap.ts` renderer + `BattleMapEditor.tsx` — the
VTT tabletop layer, with grid overlay (square/hex per `GridStyle`), tiled terrain,
walls, objects, and lighting, exported at grid scale. **Ships today** (the VTT
play surface). Depth toward Dungeondraft's smart-wall/dynamic-lighting parity is the
active growth edge.

---

## 5. Dungeon map (classic blue-grid / Dyson hand-drawn)

**Purpose.** The interior crawl — rooms, corridors, doors, stairs, traps, secret
passages. A referee's diagram: legible structure over beauty, though the best are
both.

**Conventions / must-haves.**
- Two canonical idioms: **classic TSR blue-grid** (blue lines on grid, the "geomorph"
  look) and **Dyson Logos hand-drawn** — black ink, walls filled against with
  **cross-hatching** (the signature technique: three parallel lines thrown near the
  wall, more sets pushed against them avoiding 90° intersections — see
  [Dyson's crosshatching tutorial](https://dysonlogos.blog/2011/09/03/dungeon-doodles-a-crosshatching-tutorial/)).
- Room/corridor grid at 5-ft squares; door/stair/portcullis symbols; numbered keys;
  a north arrow and scale.
- Solid rock is the *ground*, carved space is the *figure* (inverse of an outdoor
  map's figure–ground).

**Reference exemplar.** **Dyson Logos** ("Dyson's Dodecahedron") for the hand-inked
crosshatch idiom; classic **TSR/Judges Guild** blue geomorphs for the retro grid.

**Our recipe.** A dungeon symbol subset (doors, stairs, traps, keys) + the
cross-hatch wall-fill idiom over the battlemap grid engine, or a blue-grid theme
skin. **Roadmap** (leverages the shipped battlemap grid; needs the ink idiom + room
generator).

---

## 6. Political / Borders map

**Purpose.** Show who holds what — realms, provinces, spheres of influence — as the
primary data, with physical geography demoted to context.

**Conventions / must-haves.**
- **Area fills** for polities from a **qualitative** (categorical) palette —
  distinct hues, no implied order (Brewer; see REAL_CARTOGRAPHY). Adjacent regions
  must differ (four-color logic).
- Crisp **borders** (often with a subtle "halo" band inside each territory);
  capitals marked distinctly; a legend keying colors to realms.
- Physical relief flattened to faint context so borders/fills dominate the hierarchy.

**Reference exemplar.** Historical atlas plates (e.g. *The Times Atlas*, Euratlas);
in-genre, **Azgaar's** states/provinces layer.

**Our recipe.** A political overlay on the region base — categorical fills + halo
borders + realm legend, driven by the same generation graph that seeds capitals and
routes. **Roadmap** (pairs naturally with the region map + Azgaar-style state sim).

---

## 7. Topographic map (contours / hypsometric — real-world)

**Purpose.** Represent the *shape of the land* quantitatively — elevation you can
read as numbers, for hikers, surveyors, and realistic worlds.

**Conventions / must-haves.**
- **Contour lines** at a stated **contour interval**, with darker **index contours**
  every fifth line labeled with elevation (see
  [contour line](https://en.wikipedia.org/wiki/Contour_line)).
- **Hypsometric tint** — graduated elevation bands (greens low → browns high →
  white peaks) and/or **shaded relief**; **hachures** (downhill tick marks) for
  cliffs/steep scarps (see [terrain cartography](https://en.wikipedia.org/wiki/Terrain_cartography)).
- A condensed-serif/sans type (not fantasy display faces), a scale bar, a grid/graticule.

**Reference exemplar.** **USGS** topographic quadrangles; **Ordnance Survey**;
**Swisstopo** (Imhof's illuminated relief is the gold standard, REAL_CARTOGRAPHY).

**Our recipe.** Derive contours from the same heightfield that feeds the parchment
relief, apply a hypsometric ramp + hachured scarps, index-contour labeling, real-map
typography. **Roadmap** (the heightfield already exists — this is a real-map skin of
it; note the P9 render *called* itself "topographical" but was a parchment relief,
not true contours — this type is the honest version).

---

## 8. Nautical / Portolan chart

**Purpose.** Navigate by sea — coastlines, ports, hazards, and bearings between
harbors. The historical sea-chart genre.

**Conventions / must-haves.**
- **Rhumb-line (windrose) network** radiating from **compass roses** at hub points,
  giving lines of constant bearing (the defining feature — see
  [portolan chart](https://en.wikipedia.org/wiki/Portolan_chart)).
- Dense **coastal place-names written perpendicular to the coast**, inland kept
  sparse; the Catalan **wind-rose colour code** (8 main winds black, 8 half green,
  16 quarter red); vellum ground; decorative frame, ships and sea-beasts.
- Depth soundings/hazards (reefs, shoals) for the working-chart flavor.

**Reference exemplar.** Medieval Mediterranean **portolan charts** (Beinecke / LoC
collections); the Catalan Atlas.

**Our recipe.** Parchment/vellum ground + generated rhumb-line network from placed
compass roses + coast-perpendicular labels + nautical marginalia (ships, krakens,
roses from the SYMBOLOGY nautical family). **Roadmap** (a distinctive style skin
over the coastline generator; strong marginalia payoff).

---

## 9. Star / Sector / Sci-fi map (the blueprint idiom) — SHIPS

**Purpose.** Chart space — star systems, jump routes, sector borders, stations. The
sci-fi analog of the region map, in a schematic/technical register.

**Conventions / must-haves.**
- The **blueprint idiom**: dark or cyan technical ground, thin glowing rules, a
  monospace/technical typeface, grid/graticule, callout boxes — engineering-drawing
  language, not parchment.
- Star nodes graduated by type/size; **jump/hyperlane routes** as clean connectors;
  sector borders; a legend + coordinate frame.

**Reference exemplar.** **Traveller** subsector hex maps; **FTL/Stellaris**-style
star charts; technical blueprint/schematic drafting.

**Our recipe.** The **blueprint theme** in `mapStudio.ts` (`MapTheme = "blueprint"`,
with the `BLUEPRINT_FONT` sci-fi type system) — schematic ground, glowing routes,
technical labels, hex/square grid. **Ships today** (the second shipping theme;
this is the parity target from the [tooling-parity bar](../../CLAUDE.md) — real
blueprint, no blocky placeholder).

---

## 10. Subway / Transit diagram (Beck / Vignelli)

**Purpose.** Get a rider from A to B — *topology over topography*. It deliberately
lies about geography to tell the truth about connections.

**Conventions / must-haves.**
- **Schematic geometry**: lines run only horizontal, vertical, and 45° (Beck's
  circuit-diagram insight); stations equidistant regardless of real distance; a
  station = a simple tick/dot, interchanges emphasized (see
  [Beck's Underground map](https://www.khoury.northeastern.edu/home/futrelle/diagrams/fig-pages/f00022.html)).
- Bright, distinct **line colors** on a neutral ground (Vignelli's modernist
  clarity — form follows function, nothing that doesn't convey information).
- No terrain, no scale, no compass — those would be *noise* here (the anti-pattern
  is dressing it in cartographic furniture it must not have).

**Reference exemplar.** **Harry Beck**, London Underground (1931); **Massimo
Vignelli**, NYC Subway (1972).

**Our recipe.** A pure schematic renderer — 45°-constrained routing, equidistant
station spacing, categorical line palette, dot/interchange glyphs, clean sans type.
**Roadmap** (a distinct schematic engine, not a skin of the terrain renderer;
useful for sci-fi station networks and dungeon "flow" diagrams too).

---

## 11. Thematic / Weather / Heat maps

**Purpose.** Map a *variable* over space — temperature, rainfall, population,
danger, faction control, resource density. Data-first cartography.

**Conventions / must-haves.**
- The right palette **class** for the data: **sequential** for ordered magnitude,
  **diverging** for a meaningful midpoint, **qualitative** for categories — never a
  rainbow ramp for ordered data (Brewer / ColorBrewer; see the map-color-theory
  section of [REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md)). Isopleths/heat gradients
  or choropleth fills.
- A clear **legend** binding color → value, the base geography demoted to faint
  reference, an honest classification (equal-interval vs quantile) stated.
- One variable per map — a thematic map that tries to show three variables shows none.

**Reference exemplar.** Weather-service temperature/precip maps; choropleth census
atlases; game-world "climate/danger/resource" overlays (Azgaar's cell-data heatmaps).

**Our recipe.** Overlay a sequential/diverging ramp over the region base from any
per-cell field the generator already computes (moisture, temperature, elevation,
danger), with a keyed legend. **Roadmap** (cheap once the cell data is exposed;
strong for the VTT's "fog/danger/climate" GM overlays).

---

## Quick reference

| # | Type | Exemplar | Idiom | Status |
|---|------|----------|-------|--------|
| 1 | World / continent | Tolkien · Azgaar | Parchment | Roadmap (engine ships) |
| 2 | Region / kingdom | **Wonderdraft** | Parchment | **Ships** (flagship) |
| 3 | City / town | **Watabou** | Parchment / painted | Roadmap (high) |
| 4 | VTT battlemap | **Dungeondraft** | Tiled + grid + lighting | **Ships** |
| 5 | Dungeon | **Dyson Logos** / TSR blue | Ink crosshatch / blue-grid | Roadmap |
| 6 | Political / borders | Times Atlas · Azgaar | Categorical fills | Roadmap |
| 7 | Topographic | USGS · Swisstopo (Imhof) | Contours + hypsometric | Roadmap |
| 8 | Nautical / portolan | Portolan charts | Rhumb lines + vellum | Roadmap |
| 9 | Star / sector | Traveller · Stellaris | **Blueprint** | **Ships** |
| 10 | Subway / transit | Beck · Vignelli | Schematic 45° | Roadmap |
| 11 | Thematic / heat | Weather / choropleth | Sequential/diverging ramp | Roadmap |

**Pick the type before the first stamp.** Type dictates conventions; conventions
dictate the symbol subset, the palette class, the typography, and the marginalia.
Then build per the [SKILL.md](SKILL.md) pipeline and clear the
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) side-by-side with the named exemplar
at the same scale.

---

*Siblings: [SKILL.md](SKILL.md) · [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) ·
[MAP_REFERENCE_GALLERY.md](MAP_REFERENCE_GALLERY.md) (exemplar-driven look/technique) ·
[BATTLEMAP_ASSETS.md](BATTLEMAP_ASSETS.md) (VTT battlemap/dungeon asset tree) ·
[VTT_TOOLING_GAPS.md](VTT_TOOLING_GAPS.md) ·
[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) ·
[REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md) ·
[TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md) ·
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) ·
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) ·
[../asset-reuse/SKILL.md](../asset-reuse/SKILL.md) ·
[../image-pipeline/SKILL.md](../image-pipeline/SKILL.md)*
