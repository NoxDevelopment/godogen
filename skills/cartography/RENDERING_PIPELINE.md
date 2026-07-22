# Rendering Pipeline — how Map Studio actually renders a map today

This is the **implementation** reference for the [cartography](SKILL.md) skill: what
the NoxDev Map Studio pipeline *really does* when it draws a map, mapped onto concrete
functions in `apps/web/lib/actions/`. Read it beside the craft docs
([REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md), [TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md),
[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md), [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md),
[MAP_TYPES.md](MAP_TYPES.md)) — those say what a good map *is*; this says which line of
code produces it, and where the current output falls short of the
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) bar.

**Framing: current state vs the bar.** The pipeline is genuinely strong on
*compositing* — the "sheet as one object" laws (Ten Laws #9) are implemented well
(pooled shadow, one light, global paper pass, geometry-snapped labels). It is genuinely
weak on *content* — biome variety and the POI layer (checklist #4, #5) are near-zero, and
that weakness is traceable to a handful of functions named below. The most valuable part
of this doc is the [Honest gap map](#honest-gap-map): it tells you which function to open
to fix each failing checklist dimension.

## Where the code lives

| File | Role |
|---|---|
| `apps/web/lib/actions/mapStudio.ts` (3272 lines) | Region/world engine: `generateProceduralMap()` + `renderMapCanvasSvg()` (parchment + blueprint) + zod `MapCanvasZ` |
| `apps/web/lib/actions/battleMap.ts` (~1180 lines) | VTT engine: `generateBattleMap()` + `renderBattleMapSvg()` (dungeon + blueprint) + `BattleMapZ` |
| `apps/web/lib/actions/mapStampAssets.ts` (787 KB, auto-generated) | `MAP_STAMPS` — base64 brush PNGs keyed by stamp kind |
| `apps/web/components/studio/map/MapStudioEditor.tsx` (1445 lines) | Live region-map editor |
| `apps/web/components/studio/map/BattleMapEditor.tsx` (942 lines) | Live battlemap editor |
| `apps/web/components/studio/map/mapEditorShared.tsx` (339 lines) | Shared editor shell + `useHistory` |
| `apps/web/scripts/bake-map-{sample,refined,p9}.mts` | SVG-first render → Inkscape PNG bake |
| `apps/web/test/{maps,map-studio,maps-canvas-roundtrip,battlemap}.test.ts` | vitest guardrails |

**The model** is `MapCanvas` (`mapStudio.ts:164`): a row-major `grid` of `Biome` cells
plus fractional-coord (0..1) `stamps`, `labels`, `regions`, `paths`, `gridOverlay`,
`furniture`, a `seed`, and a `theme` (`"parchment" | "blueprint"`). Everything the
renderer draws is data on this one object; the editor mutates the *same* model the
generator emits and the exporter serializes — there is no second representation.

---

## The parchment layer stack (render order)

`renderMapCanvasSvg()` (`mapStudio.ts:2152`) routes on theme; `renderParchment()`
(`mapStudio.ts:2163`) is the flagship. It emits one SVG string, bottom-to-top, so
z-order **is** array order. The stack, and why each layer sits where it does:

| # | Layer | Code | Why here |
|---|---|---|---|
| — | **defs**: sea/land/vignette gradients; `npx-fiber`/`npx-stain` paper filters; `npx-halo`/`npx-feather`/`npx-relief`/`npx-soft`; per-biome tonal gradients; land clip-path | 2175–2234 | filters/gradients referenced by later layers; land contour (`biomeLoops`, 2231) computed once and reused by clip, halo, ripples, fill, coast |
| 1 | **Sea** (`npx-sea` vertical teal gradient) + faint stain film | 2237–2240 | ground of the whole sheet; aged teal, never flat blue (figure–ground, Law #4) |
| 2 | **Sea-halo** — soft light-teal glow radiating from the coast (`npx-halo` blur) | 2244 | the coastal "echo" that lifts land off water |
| 3 | **Ripple rings** — 3 concentric coast strokes fading into the sea | 2248–2254 | Wonderdraft-style coastal echo lines |
| 4 | **Land base** (`npx-land` radial parchment) | 2256 | the paper the interior is drawn on |
| 5 | **Biome fills** — smoothed marching-squares contours, clipped to land, feathered (`npx-feather`), drawn low→high per `BIOME_DRAW_ORDER` (2318) | 2259–2271 | tonal washes over the parchment (ground shows through via opacity 0.72); coastal `beach` first as a shore ring |
| 5b | **Coast outline** — one crisp dark stroke on the land contour | 2274 | "the single biggest pro tell" (comment 2273) |
| 6 | **Regions** (political overlay) — smoothed polygons clipped to land | 2280–2290 | optional; above terrain, below relief |
| 7 | **Rivers** (tapered ribbons, cased) + **roads** (cased dashed strokes) | 2293–2311 | drawn on the ground, under relief that would overlap them |
| 8 | **Grid overlay** (square or hex) | 2314–2341 | subtle; battle-grid is a later concern |
| 9 | **Pooled base-shadow** — ALL relief casts as ONE group beneath the symbols | 2425 | *see [shadow pooling](#shadow-pooling--one-light) — the layer that makes a range read as one raised mass* |
| 9b | **Relief bodies** — z-sorted by footprint `y` (lower = in front) | 2417–2419, 2426 | overlapping peaks stack front-to-back |
| 9c | **Town base-shadows** then **town bodies** | 2427–2428 | settlements last of the symbols so a town is never buried under a peak (`SETTLEMENT_KINDS`, 2420) |
| 10 | **Global paper pass** — one warm sepia film (`#caa863` @0.11) + paper fibre (`npx-fiber`) | 2434–2435 | *above terrain/relief but BELOW labels* — the finishing unifier that fuses separately-generated ink stamps into one aged sheet (Law #9) |
| 11 | **Labels** — `renderLabels()` (2463) | 2437–2463 | above the paper film so type stays legible; labels get their own ink halo instead of the paper wash |
| 12 | **Finishing** — mottled stain + `npx-vign` vignette | 2467–2470 | over everything incl. labels, for aged tone + figure focus |
| 12b | **Neatline** — heavy outer + hairline inner rule + corner keystones | 2473–2493 | engraved plate margin |
| 13 | **Furniture** — compass / cartouche / scale / legend, drawn LAST | 2497 | apparatus stays crisp above the vignette (Law #10) |

The two placement decisions that matter most for craft: the **base-shadow pool sits at
#9 as a single group** (not one shadow per sprite), and the **global paper pass sits at
#10, between relief and labels** — both are deliberate (comments at 2364–2369 and
2430–2433).

---

## The ridgeline relief engine

This is the pipeline's best feature and the fix for the historic "wall of identical
peaks" failure (checklist #6). Instead of one glyph per high cell, `generateProceduralMap`
(2628) extracts the **spine of each massif** and walks peaks along it. The chain, in code:

1. **Massif mask** (2681–2691): every `mountains`/`snow` cell → `mtMask[i] = true`.
2. **Distance transform** — `maskDistanceTransform()` (2417): multi-source BFS giving each
   masked cell its step-distance to the nearest non-mask cell/border. The *ridge* of this
   field is the medial axis (centre-line) of the massif.
3. **Ridgeline extraction** — `extractRidgelines()` (2468): builds a per-cell `score =
   0.5·(medialDist/dMax) + 0.5·(elevNorm)` (2491) — spine-centre blended with true crest.
   Then a greedy **crest-walk**: seed at the highest-scoring unclaimed cell, `extend()`
   off *both* ends (2522–2558) stepping to the in-mask neighbour with the best
   `score + 0.4·directionContinuity` (2545–2546), and `claimCorridor()` (2500) a 1-cell
   band around each finished line so a near-parallel duplicate spine can't form. Purely
   deterministic — no RNG here.
4. **Resample** — `resampleCellPath()` (2569): arc-length resample of each jagged spine at
   `peakSpacing = 2.4` cells (2705) so peaks overlap ~40% front-to-back.
5. **Smooth** — `smooth1D()` (2596): 1-2-1 smoothing of the per-sample elevation series so
   neighbouring peaks share a scale band (declumps the tall/short jumble).
6. **Per-spine peak placement** (2708–2738): for each sample, compute an end-taper
   `endT = min(i, m-1-i)/half` (0 at ends → 1 mid-spine) and normalized height
   `eN = (sm[i]-0.66)/0.32`. Then:
   - a long spine (`m >= 4`) **ends in foothills** — `stamp("hill", …)` at index 0 and m-1
     (2730);
   - interior samples get `stamp("mountain", …)` with `scale = (1.0 + 0.6·eN)·taper·jitter`
     (2732–2734) — **tallest on the crest, tapering to the ends**.
7. **Global budget** — `peakBudget = max(10, round(sqrt(cols·rows)·1.15))` (2706), spent
   longest-ridge-first (2707), so even a very mountainous seed reads as legible ranges
   with lowland between (restraint, Law #1).

Vegetation and wetlands use sibling placers, not per-cell fills: **forests** via
`clumpScatter()` (2358) — well-spaced clump centres, then a few members tightly around
each → distinct copses with gaps; **hills** and **marsh** via `thinByDistance()` (2333) —
greedy Poisson-disk thinning weighted by elevation. All jitter comes from the seeded
`rand` (2692), so placement is deterministic.

Rivers (2808–2869) trace **steepest-descent** from moist highland sources to the sea;
roads (2873–2906) are a **minimum-spanning-tree** over settlements that skips any leg
crossing >25% open water. Both are Azgaar-class procedural derivations, not hand-drawn.

## Coastline & biome contouring (marching squares)

The pipeline retired the flat `crispEdges` `<rect>`-per-cell grid; land and each biome are
**contoured** into smooth organic polygons. `biomeLoops()` (1589) is the workhorse:

1. `contourField()` (1405) builds a 0/1 field for a cell predicate, pads it with a 1-cell
   water border (so contours close inside the rect), and runs `boxBlur()` (1375) N passes
   to soften the binary mask into a smooth scalar field.
2. `marchingSquares()` (1427) walks the field at `iso=0.5`, linearly interpolating segment
   endpoints on cell edges (sub-cell, organic), then stitches segments into closed loops
   by **direction-agnostic** shared-endpoint matching (both endpoints indexed, 1512–1547 —
   a directed walk mis-stitches and closes loops with a chord across the map).
3. `chaikinClosed()` (1554) corner-cuts each loop for the final organic curve.

The land loop is computed once (2231) and reused for the clip-path, sea-halo, ripples,
fill, and coast outline. Biome fills use `fill-rule:evenodd` so islands/holes render
correctly (`loopsToPath` 1605). Rivers are drawn as tapered ribbon *polygons*
(`riverRibbonPath` 1618, half-width grows 0.16→1.0 source→mouth); roads as smoothed cased
strokes (`polylinePath` 1645). All smoothing is `chaikinOpen`/`chaikinClosed` — no library.

## Label placement algorithm

`renderLabels()` (1848) implements the typography laws (checklist #8) with three modes,
all resolving a cartographic role via `labelStyleOf()` (1242) → `LABEL_SPEC` (1178),
which sets face/weight/tracking/fill/halo/scale per tier (title > region > city > town >
village; ocean sits back in sea-ink). Every label gets a **two-pass cream ink halo**
(a wide soft underlay + a tight dense pass, `emitText` 1853) so type survives over busy
terrain without a sticker outline.

- **Region labels** curve along the landmass **medial line** — `landMedialPathPx()` (1708)
  samples, for each column under the label, the mean row of land cells (the continent's
  vertical centre-line), then vertically shifts the run through the anchor. Real curvature,
  no synthetic arc.
- **Ocean/coast labels** hug the **actual coastline** — `coastFollowPathPx()` (1753) finds
  the nearest land-contour point, walks it both ways until the run spans the text, and
  translates it out to the anchor (the "Bay of…" set-along-shore idiom). It *rejects* a
  segment that reads badly (too steep, or outside a safe frame inset, 1815–1818) and falls
  back to a gentle arc.
- **Point labels** (settlements) try a ladder of 7 offsets (1938–1946) and take the first
  that clears already-placed rects + reserved furniture boxes — so a town never stacks on
  another or hides under the legend/compass/cartouche. Furniture footprints are reserved
  *before* labels run (2444–2462).

The realm and sea labels themselves are chosen in the generator: the realm name is placed
on **open** biome nearest the land centroid (924–961, avoids burying it under a range),
and the sea name at the water cell **farthest from land** by a distance transform
(962–1019) so it sits in genuine open sea.

---

## Shadow pooling & one light

Every relief symbol is split by `buildStamp()` (2370) into a **shadow** and a **body**:

- **Shadow**: a soft ground-contact ellipse (`npx-soft` blur), seated at the footprint
  line and pushed **SE** (`baseX/baseY`, 2402–2403). All relief shadows are emitted as one
  `<g>` at layer #9 (2425) *before* any body. Where a range's peaks overlap, their
  semi-transparent casts **pool into one continuous shade** beside the spine — the single
  change that makes a range read as one grounded mass instead of N boxed sprites
  (comment 2364–2369).
- **Body**: the brush sprite drawn through the `npx-relief` filter (2201–2214), which
  merges an SE edge-cast under an edge-feathered copy of the sprite, plus a faint
  ground-tint `haze` ellipse (2411–2413) so the base picks up the parchment palette
  instead of ending on a hard pixel line. Settlements skip the haze (crisp marks).

**One light direction** is enforced two ways: the brush art bakes its own NW highlight,
and every code-side cast is offset SE — so the whole sheet reads as lit from the NW
(Law #9). The **palette-unify** step is a `feColorMatrix saturate 0.78` on the sprite
branch of `npx-relief` (2213): it pulls clashing per-sprite palettes (the old
brown-lump vs grey-peak split, checklist #2) toward one muted register at the source,
reinforced by the global paper pass at #10.

The **paper/aging film** is three cooperating passes: the global sepia+fibre unifier
(#10, 2434–2435), the mottled `npx-stain` turbulence and radial `npx-vign` vignette
(#12, 2467–2470), and the paper-fibre/stain filters themselves (`npx-fiber` 2188,
`npx-stain` 2192) whose `feTurbulence seed` is derived from `canvas.seed` (2189, 2193) so
the grain is deterministic per map.

---

## Seed handling & determinism

- **PRNG**: `mulberry32()` (2196) — no `Math.random` anywhere in generation. Elevation and
  moisture are `makeNoise()` (2212) fractal value-noise (3 octaves) on a seeded 256×256
  lattice; the moisture field is decorrelated by `seed ^ 0x9e3779b9` (2636) and scatter
  RNG by `seed ^ 0x85ebca6b` (2637).
- **Stamp variant + jitter** are chosen by `hashStr()` (2606, FNV-1a) over the stamp *id*
  (2386, 2391–2395), so the editor and the exporter pick identical art and jitter for the
  same canvas — the preview is the export.
- **Guardrail**: `map-studio.test.ts` asserts *"generation is DETERMINISTIC — same seed →
  identical map"* (grid.cells + stamps + labels equal) and *"different seeds produce
  different worlds"*; the paths test re-runs a seed and asserts equal `paths`.
- Persistence is **resilient, not lossy**: `MapCanvasZ` (3138) is an all-`.catch()` zod
  schema — a corrupt field repairs to a default rather than throwing.
  `maps-canvas-roundtrip.test.ts` guards that `normalizeMapMeta` and serialize→parse
  preserve the canvas (this was the P4 regression: the canvas used to be dropped on save).

---

## SVG-first render, then bake

The pipeline is **SVG-native**; PNG is a downstream raster.

- **Render**: `renderMapCanvasSvg(canvas, { width, height, theme, fontCss })` returns a
  standalone SVG string. Fonts are injected as `@font-face` base64 into `<defs>` via
  `opts.fontCss` (2177) so a raster bake is self-contained; the family names must match
  `CARTO_FONT` / `BLUEPRINT_FONT` (1133, 1146).
- **Bake**: `bake-map-*.mts` generate one `MapCanvas` at a fixed config
  (`cols:60, rows:42, seaLevel:0.54, settlements:9`) and **seed 88** (default, CLI-
  overridable), call `buildFontCss()` to base64 the TTFs from
  `godogen/pieces/asset-kits/fonts`, render at `width:1600`, write the SVG, then
  `rasterize()` shells out to **Inkscape** (`spawnSync`, candidate binary paths) for
  SVG→PNG. Output lands in `docs/gdd/map-studio/shots`. `bake-map-sample` also bakes a
  flat-grid "before" and a blueprint render; `bake-map-p9` is `refined` with different
  output names.
- **Editor export** is fully client-side (no server bake): `exportSvg` calls
  `renderMapCanvasSvg(canvas, {width:1600, theme})`; `exportPng` renders at width 3200,
  paints the SVG into an offscreen `<canvas>`, and `toBlob`s a PNG.

**Stamp storage & binding**: `MAP_STAMPS` (`mapStampAssets.ts:20`) is
`Record<string, StampAsset[]>` where `StampAsset = { uri, w, h, id }` (9–17) — `uri` is a
transparent base64 PNG, `id` is a stable manifest id (provenance/license in
`map-stamps.manifest.json`). `buildStamp()` looks up `MAP_STAMPS[st.kind]`, picks a
variant by id-hash (2387), and draws it via `<image href="${asset.uri}">` at
`drawH × (asset.w/asset.h)` (2394). If a kind has no registered art, it falls back to the
legacy vector glyph `stampSvg()` (1654) — which the editor also reuses for its palette
icons, keeping preview and export in one visual language.

---

## The blueprint theme (second render path)

`renderBlueprint()` (2762) is a genuinely distinct schematic language over the *same*
`MapCanvas`, not a recolour. Its 15-layer stack (comments 2807–3081): field gradient +
cyanotype paper mottle → fine+coarse technical grid with A-1 gridref labels → faint land
tint → biome hatch patterns (`bp-h-forest/desert/swamp/rock`) → topographic contour lines
from biome elevation tiers → crisp double coastline → depth soundings in open water →
dashed-cyan region sectors → survey rivers/roads → schematic feature glyphs
(`blueprintSymbol()`, 2539) → wide-mono labels (`renderBlueprintLabels()`, 2610) →
dimension callouts → capital gridref tag → vignette + neatline → north mark + scale +
legend + **title block** ("NOXDEV CARTOGRAPHY DIV.", `titleBlockSvg()` 2640). Type is
Orbitron/Space-Mono (`BLUEPRINT_FONT`, 1146). Tests assert the two themes emit mutually
exclusive signatures (`bp-field` vs `npx-sea`).

---

## The battlemap renderer (VTT)

`battleMap.ts` is the Dungeondraft-lane sibling over a separate `BattleMap` model
(`class:"battle"`, `grid` of `Floor` cells, `walls`, `doors`, `tokens`, `theme:
"dungeon"|"blueprint"`; type at :102). `generateBattleMap()` (:220) carves **rooms +
corridors**, derives walls at floor/void boundaries, places doors at entrances, and drops
a creature encounter including a `boss` token. `renderBattleMapSvg()` (:448) routes on
theme; the **dungeon** stack (:566–:722) is: 1. void ground → 2. floor tiles with
bevelled smart edges → 3. grid overlay (square/hex, shared with the region grid helper) →
4. walls (lit top bevel + shadow, minus door gaps) → 5. doors → 6. tokens/props (props
first, creatures last so a token sits on top) → 7. vignette + title banner + legend +
scale note. `FLOORS` (8 kinds, :38) and `TOKEN_KINDS` (15 kinds incl. hero/monster/boss,
:45) drive palettes; `BattleMapZ` (:1117) is the same all-`.catch` persistence schema.
Unlike the region renderer this is **tile-and-token**, not contour-and-stamp — no
marching-squares, no ridgelines, no aged-paper unifier beyond the dungeon vignette.

---

## The live editor

`MapStudioEditor` (`MapStudioEditor.tsx:144`) is direct-manipulation over the `MapCanvas`
model, using the **exact same** `renderMapCanvasSvg` for its preview (injected via
`dangerouslySetInnerHTML`, 1042) with a transparent interactive `<svg>` overlay on top for
hit-testing, selection boxes, and scale/rotate handles. There is no separate preview
renderer — what you see is the export.

- **State**: the document lives in `useHistory<MapCanvas>` (shared hook,
  `mapEditorShared.tsx:47`; `MAX_HISTORY=80`) — `commit` (deep-clone push), `apply` (live,
  no push), `checkpoint`, `undo`/`redo`. Tool/UI state is `useState`: `tool`, `biome`,
  `stampKind`, `brush`, `labelStyle`/`labelCurve`, `snap`, `zoom`, selection, layer
  visibility, `seed`, `settlements`.
- **Tools** (`Tool = "select" | "terrain" | "stamp" | "label" | "erase"`): select
  (move/scale/rotate with handles), terrain (paint biomes in a brush square), stamp
  (drag-to-place; palette icons are `stampSvg()`), label (place + inline-edit), erase.
  Plus theme toggle, grid cycle, snap, zoom, undo/redo, seed shuffle, settlement count,
  Generate (client `generateProceduralMap` preview) / Generate+save (server action), SVG
  and PNG export, Save, and **Populate world** (turns named settlements into worldbuilder
  entities via `extractSettlements()`, `mapStudio.ts:3100`).
- **Note**: rivers/roads/regions/furniture exist in the model and generate, and are
  toggleable layers, but the editor exposes **no interactive tool to draw them** — they
  are generator output only.

`BattleMapEditor` (:87) mirrors this over `BattleMap` with tools
`select/floor/wall/door/token/erase`, sharing the same `useHistory`, chrome, and
`download` helper from `mapEditorShared.tsx`.

---

## Honest gap map

Cross-referencing [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) against the code. "Bar"
= the checklist dimension; each row says the honest status and the **exact function to
change**. This is the section to act on.

| # (checklist) | Dimension | Status | Where the fix lands |
|---|---|---|---|
| 6 | **Relief structure** | ✅ **Met.** Ridgeline-walked ranges, tallest on crest, tapering to foothills, budgeted. | `extractRidgelines` (2468) + peak loop (2708). The reference implementation. |
| 9 | **Sheet as one object** | ✅ **Met.** Pooled base-shadow (2425), one NW light, `saturate 0.78` palette-unify (2213), global paper pass (2434). | — |
| 8 | **Labels as typography** | ✅ **Mostly met.** Hierarchy via `LABEL_SPEC` (1178); curves snapped to REAL geometry (`landMedialPathPx` 1708 / `coastFollowPathPx` 1753); collision avoidance (1899–1957). | Gap: only settlement/realm/sea labels — no river/range/feature labels. Add in generator + `renderLabels`. |
| 10 | **Decorative apparatus** | ✅ **Mostly met.** Compass/cartouche/scale/legend/neatline. | Gap: no marginalia (sea-beasts/ships). Add furniture types + `renderFurniture` (2124). |
| 3 | **Believable geography** | ⚠️ **Partial.** Ranges on spines ✅, rivers high→sea ✅. But rivers just `break` at a local minimum (2855) — **no lakes are formed**, so interior basins vanish. | River loop (2824–2869): on local minimum, emit a lake region/water cell instead of dropping the river. |
| 7 | **Water & coast** | ⚠️ **Partial.** Coastal echo/halo/ripple ✅ (2244–2254). But **open water is a flat gradient** — no wave/hatch texture; no inland lakes rendered as water. | Sea section of `renderParchment` (2236) — add a wave-hatch `<pattern>`; couple to the lake fix above. |
| 1 | **Restraint / negative space** | ⚠️ **Partial.** Mountains are budgeted (`peakBudget` 2706); forests clump; hills/marsh thinned. But **each kind is budgeted independently** — a seed rich in every biome can still crowd. | `generateProceduralMap` scatter block (2678–2755): add a *global* feature-density ceiling across all kinds. |
| 11 | **Robustness across seeds** | ❌ **Untested/weak.** Determinism is tested, but not *quality* across seeds. Bakes pin **seed 88** (`bake-map-p9.mts:18`). Radial falloff (2650) forces an island-continent every seed → low macro-shape variety. | Sweep seeds in the bake scripts + judge; vary the falloff/continent model at `mapStudio.ts:650`. |
| 4 | **Biome variety** | ❌ **Broken in code.** `classify()` (1075): line **1083** is a no-op ternary `m<0.28 ? e>0.5?"desert":"desert"` (both branches desert), and line **1086** `if (e>0.75) return "tundra"` is **unreachable dead code** (every `e>0.58` already returned hills/mountains/snow above) — so **tundra is never generated**. Effective palette ≈9 biomes, one tan register under the bumps. | `classify()` (`mapStudio.ts:1075–1088`) — rebuild the moisture×elevation×latitude table; then tune `PARCHMENT_BIOME` (1288). **Single highest-leverage fix.** |
| 5 | **Landmark / POI layer** | ❌ **Absent.** The generator only emits `mountain/hill/forest/marsh/city/town/village` (stamp calls at 730,734,742,749,754,791). **`castle`, `ruins`, `tree` and `range` art is registered in `MAP_STAMPS` and drawable, but never placed.** `range` isn't even in `STAMP_KINDS` (54). A map with no POIs is a heightmap. | `generateProceduralMap` — add a POI pass after settlements (~804): castles at passes, ruins in wilds, ports on coasts. Art is ready; wire `range`/`tree` into `STAMP_KINDS` + placement. |
| 2 | **One coherent idiom** | ⚠️ **Managed, not solved.** `saturate 0.78` + paper pass force cohesion at composite time, but the underlying `MAP_STAMPS` set spans generations. | Regenerate the stamp set from one style anchor (`mapStampAssets.ts`) rather than relying on the desaturate crutch. |
| 12 | **Symbol-library depth** | ❌ **Shallow.** `MAP_STAMPS` has ~11 keys, 2–6 variants each; the bar is 120+ categorized. | `mapStampAssets.ts` regeneration (see [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md)) + wire new kinds into `STAMP_KINDS` and the generator. |

**The through-line:** compositing (the hard part) is done well; the gaps are almost all in
`generateProceduralMap` and `classify()` deciding *what* to place and *where* — content,
not rendering. Fixing `classify()` (biome variety) and adding a POI pass (both in
`mapStudio.ts`) would move the two heaviest-weighted zeros on the checklist without
touching the renderer. Grade every change against [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md)
across ≥3 seeds, in the live editor, side-by-side with the named competitor — not on
seed 88 with green tests.

---

## Generative-AI map architecture (future direction vs. our current compositing)

There is a second architecture for making a styled map that is worth understanding
because it attacks exactly the two laws our stamp compositor fights hardest. The
reference implementation is **claudaff/generative-ai-mapmaking** (GitHub), from the ACM
paper *"Generative AI in Map-Making: A Technical Exploration and Its Implications for
Cartographers"* ([dl.acm.org/doi/10.1145/3748636.3764154](https://dl.acm.org/doi/10.1145/3748636.3764154)).

**The method.** A **ControlNet fine-tuned on vector geodata** conditions **Stable
Diffusion 1.5** to generate 512px map tiles in a style chosen by a text prompt — i.e.
*vector layout + prompt → a whole cohesive styled sheet*, not scattered symbols. The repo
ships 4 pretrained ControlNet checkpoints on HuggingFace (Swisstopo modern, OldNational,
Siegfried historical, Combined multi-style); stack is Python/PyTorch/Diffusers, QGIS for
vector symbolization, **keras-ocr to mask out all text labels** (so the diffusion model
never renders gibberish lettering), and a Flask webapp. Trained at 1:5000; smaller scales
blur, and it needs pixel-perfect raster↔vector alignment.

**Honest architecture comparison.**

| Axis | Our pipeline (vector→SVG stamp compositing, `mapStudio.ts`) | Vector-conditioned diffusion (this repo) |
|---|---|---|
| How a sheet is made | assemble N discrete sprites + fills over parchment | generate the entire sheet in one pass from vector conditioning + a style prompt |
| Idiom coherence (Law #2) | **fights it** — mixed-provenance stamps clash; we paper over it with `saturate 0.78` + the global paper pass | **native** — one model, one idiom across the whole map; multi-style from one checkpoint |
| Restraint (Law #1) | manual budgets (`peakBudget`, thinning) | style/training-driven, not per-symbol |
| Determinism | **✅ exact** (mulberry32 + id-hash) — MP-safe, reproducible | **✗** stochastic per run |
| Editability | **✅ crisp, per-symbol, stable-ID swappable** | ✗ raster output; no per-symbol handles unless hybridized |
| Scale/size | resolution-independent SVG | 512px tiles → needs tiling + compose + upscale |
| Text | typographic vector labels with hierarchy | must be **masked out** and re-added as overlay |

So the two approaches are complementary, not rivals: our weakness (assembling many sprites
inherently strains idiom + restraint — the documented carpet/clash failure) is diffusion's
strength, and diffusion's weaknesses (non-determinism, tiling, no editability, no text) are
exactly what our deterministic vector pipeline already solves.

**The pragmatic hybrid for us.** Keep the deterministic pipeline as the **control signal** —
`generateProceduralMap` already computes precisely the vector layers these models condition
on (coastline contour, rivers, relief/massif mask, biome fields, settlements). Then,
optionally, run a fine-tuned ControlNet as a **stylization pass** over the composited (or
raw-vector) map for a cohesive painterly finish, and keep **labels + furniture as crisp
vector overlays composited on top** (masked during diffusion, exactly as the reference does
with keras-ocr). This preserves determinism and stable-ID editability for the parts that
need them while buying single-idiom cohesion for the terrain body. This is the DL-for-
cartography frontier that complements the deep-learning *generalization* work (Yan/Yang/Ai
2025) noted in [REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md).

**Caveats (non-negotiable).**
- **Clean-room + vet, don't blindly install.** Study the documented method and build our
  own version in the [image-pipeline](../image-pipeline/SKILL.md); do not pull a
  third-party repo into the stack (per the studio's vet-external / clean-room discipline).
- **Storage.** Any checkpoints/models are large binaries → **NAS-primary**
  (`\\DXP4800PLUS-A79\NoxDev`), never committed to the repo.
- **Base model.** SD 1.5 is dated; we would retrain the vector conditioning against a
  modern base (our Z-Image-Turbo stack, the same anchor the current `MAP_STAMPS` set was
  generated with) rather than shipping the paper's SD1.5 checkpoints as-is.
