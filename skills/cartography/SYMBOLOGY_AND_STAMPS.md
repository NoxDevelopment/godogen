# Symbology & Stamps — designing a map symbol library, not a pile of sprites

A map's symbol set is its *vocabulary*. Amateur maps fail here twice: the set is
**too thin** (a dozen bumps and a castle, so every map looks the same) and it is
**incoherent** (each stamp drawn by a different hand, in a different palette, lit
from a different direction — the P8 "brown-lump-vs-grey-peak" clash). A pro set is
**broad** (Inkarnate ships 700 assets free / 16,000+ paid / 23,700+ on Pro — see
[Inkarnate updates](https://inkarnate.com/updates)) **and** it reads as **one
hand**: one idiom, one line weight, one light, one palette, across every glyph.

This doc is the plan for that library: the full **category tree** with target
counts, the **consistency discipline** that separates pro from amateur, how to
**generate** the set through our pipeline (reuse-first, generate LAST), and how it
plugs into `mapStampAssets.ts`. Read [FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md)
for the idiom these symbols must speak, [TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md)
for *where* they get placed (symbols are placed by the biome/density model, never
scattered per-cell), and [RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) for how the
stamps composite into one sheet.

> Symbols in cartography are one of the four core visual variables of the discipline
> (Bertin's *variables visuelles*; see [REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md)).
> A stamp is not decoration — it is a **sign** with a fixed meaning that the reader
> must decode instantly. Design it as data, then make it beautiful.

---

## 0. Three symbol geometries — every glyph is point, line, or area

Before the category tree, the cartographic primitive: every symbol is one of three
geometries, and mixing up which a symbol is causes bad placement and bad scaling.

- **Point symbols** — a settlement, castle, tower, X-mark, camp, single tree. They
  mark a *location*; they have a fixed anchor (usually bottom-center for a
  standing form, so it "sits" on its coordinate) and scale with rank/importance,
  not with area. Most of the SETTLEMENTS, STRUCTURES, and POI families are points.
- **Line symbols** — walls, roads, borders, rivers, bridges-in-context, rhumb
  lines, coastlines. They are drawn as **paths** (a stroke stamped/tiled along a
  spline), so they need *tileable* end/middle segments, not a single fixed sprite.
  A wall or road that can't tile along an arbitrary path is mis-designed.
- **Area symbols** — forest, marsh, swamp, lava field, dunes, crops, hypsometric
  bands, political fills. They cover a *region* by repeated sparse stamping or fill,
  governed by the density model — **never a solid carpet** (Law 1). The unit is a
  clump/tuft designed to read well when scattered with scale/rotation variance.

The same real-world thing can appear in two geometries: a **forest** is an *area*
clump, a lone **tree** is a *point*; a **bridge** is a *point* landmark but a
**wall** is a *line*. Design and tag each accordingly in the manifest, because the
renderer places the three geometries by three different rules (see
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)).

Within a geometry, the classic cartographic **visual variables** (Bertin) are the
knobs you have to signal meaning: **size** (rank a capital over a village), **value/
tint** (snowcap vs bare peak), **shape** (temple vs tower silhouette), and
**orientation** (a symbol should generally *not* rotate if orientation carries no
meaning — a rotated castle reads as an error). Use size and shape to carry the
signal; hold orientation fixed for built forms so the NW light stays coherent.

---

## 1. The category tree — what a cartography tool actually needs

A region/world set at parity needs a **~120+ symbol core** organized into eight
families. Below each family lists the members and a **target count** (base variants
before size/rotation/palette derivatives). "Variants" means genuinely different
drawings, not the same PNG scaled — 3–5 hand-variants per kind is the minimum that
kills the "stamped from one rubber stamp" tell.

### RELIEF — the backbone of a land map (target ~30)
Mountains carry the eye; they need the most variants of anything.
- **Single peak** — one massif, snowline optional. 4–5 variants. *The workhorse.*
- **Range / massif** — a linked chain drawn as one raised mass (not N peaks pasted).
  4–6 variants at different lengths; this is what gets ridgeline-walked.
- **Snowcap peak** — white/pale wash cap over the sepia base, for high/cold belts. 3.
- **Volcano** — conical, crater notch, optional smoke plume / lava tongue. 2–3.
- **Mesa / butte / plateau** — flat-topped, banded cliff sides (badlands, canyons). 3.
- **Cliff / escarpment** — a linear scarp with hachure-style downhill ticks (the
  real-map hachure idiom; see topographic map, [MAP_TYPES.md](MAP_TYPES.md)). 2–3.
- **Hills / downs** — low rounded humps, the foothill/transition symbol. 4–5.
- **Dunes** — crescent/barchan sand ridges for deserts. 2–3.

### VEGETATION — the biome layer (target ~22)
Forests belt foothills and coasts; the *fill* differs by biome (see
TERRAIN_AND_BIOMES). Draw the canopy idiom, not individual botanical trees.
- **Broadleaf forest** — rounded deciduous clumps. 4–5.
- **Conifer forest** — spiky/triangular boreal clumps. 4–5.
- **Mixed forest** — a blended clump for temperate belts. 2–3.
- **Jungle / rainforest canopy** — dense, layered, darker wash. 3.
- **Scrub / chaparral** — sparse low brush for arid margins. 2.
- **Marsh reeds** — vertical reed tufts + water dashes (wetland edge). 2–3.
- **Grassland tufts** — light grass flecks for plains/steppe (used *sparsely*). 2–3.
- **Crops / farmland** — furrowed field hatching near settlements. 2.

Single trees also live here as a **point** symbol (a lone landmark tree, orchard
dot) distinct from the forest **area** clump — our `tree` kind vs `forest` kind.

### SETTLEMENTS — the graduated size ramp (target ~16)
The core of the POI hierarchy. Size and detail must scale with rank so the reader
reads importance at a glance (visual hierarchy, Law 3).
- **Hamlet / village** — a few roofs or a single icon. 3–4.
- **Town** — clustered roofs, maybe a wall stub. 3–4.
- **City** — dense cluster, towers, ring wall. 3–4.
- **Capital** — city + crown/star/double-ring marker. 2–3.
- **Ruins** — broken walls / toppled columns (dead settlement). 2–3.

### STRUCTURES — the built landmarks (target ~26)
The layer that turns terrain into a *place*. Each is a distinct silhouette.
- **Castle** — the flagship fortification (multi-tower, keep). 3–4.
- **Keep / fort** — a single strong tower + wall. 2–3.
- **Tower** — lone watchtower/wizard tower. 2–3.
- **Temple / shrine** — sacred building (pillared / domed). 2–3.
- **Monastery / abbey** — cloister silhouette. 2.
- **Bridge** — arched span across a river gorge. 2.
- **Wall / rampart** — a linear border fortification (drawn as a path). 2.
- **Gate** — a fortified pass/gatehouse. 2.
- **Windmill / watermill** — rural industry. 2.
- **Mine** — pick-and-shaft / adit mouth. 2.
- **Lighthouse** — coastal beacon tower. 2.
- **Port / docks** — piers, moored hulls (coast-anchored). 2.

### POI / MARKERS — the narrative pins (target ~18)
Small, high-contrast pins the DM/author drops to anchor story.
- **X-marks / treasure** — the classic buried-treasure X. 2.
- **Camp / tents** — wilderness encampment. 2.
- **Cave / cavern mouth** — dark arch in a hillside. 2.
- **Shrine / wayside cross** — small roadside sacred marker. 2.
- **Battlefield** — crossed swords / helm on a field. 2.
- **Gallows / gibbet** — grim wayside marker. 1–2.
- **Standing stones / henge** — a ring or trilithon. 2.
- **Crossroads / signpost** — a route junction marker. 1–2.

### HAZARDS — the danger fills (target ~10)
Area symbols that warn. Often overlap the biome layer.
- **Swamp / bog** — reed + open-water + tussock hatch (distinct from marsh edge). 2.
- **Lava field / flow** — cracked-crust hatch, warm tint. 2.
- **Chasm / rift** — a jagged parallel-line gorge. 2.
- **Whirlpool / maelstrom** — spiral sea hazard. 1–2.
- **Quicksand / tar** — stippled danger fill. 1.

### NAUTICAL / MARGINALIA — the sea and the frame (target ~16)
What fills the water and the borders — the difference between a landmass and a *map*.
- **Ships** — cog/galleon/longship silhouettes sailing the sea. 3–4.
- **Sea monsters / krakens** — the classic *hic sunt dracones* beasts. 3–4.
- **Compass rose / wind rose** — the orientation marker; on nautical charts the
  full 32-point wind rose (8 main winds black, 8 half-winds green, 16 quarter-winds
  red — the Catalan colour code, see [portolan chart](https://en.wikipedia.org/wiki/Portolan_chart)). 2–3.
- **Waves / sea hatch** — the water texture stroke (stippled coastal echo lines). 2–3.
- **Sea spouts / rocks / reefs** — coastal hazards + texture. 2.

### DÉCOR — the apparatus (target ~14)
The engraving-shop furniture that frames the argument.
- **Cartouche** — the decorative title frame/scroll. 3–4.
- **Border / frame** — corner pieces + edge rules (single/double/rope). 3–4.
- **Banners / ribbons** — for region and map titles. 2–3.
- **Heraldry / coats of arms** — shield blanks for kingdoms/houses. 2–3.
- **Scale bar / legend frame** — the metrology furniture. 2.

**Core total ≈ 120–150 base variants** across the eight families. That is the
*floor* — the parity line for a usable region/world tool. Beyond it, breadth scales
toward the thousands the way Inkarnate does: **multiply the core by style packs**
(parchment / blueprint / topographic / ink-noir), by **biome palette skins**, and
by **regional flavor** (Norse / desert / far-eastern architecture). 150 core × 4
styles × a few palette skins is already four-figure breadth without inventing new
*meanings* — the meanings stay fixed; the *rendering* multiplies.

---

## 2. Consistency discipline — the "drawn by one hand" test

This is the section that separates pro from amateur. A broad-but-incoherent set
looks worse than a small coherent one. Enforce all six, on every symbol, no
exceptions:

1. **One idiom.** Pick a drawing language — e.g. *sepia ink line + light wash
   relief* — and every glyph obeys it. No photo-real tree next to a cartoon castle.
   The idiom is defined in [FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md); a symbol
   that doesn't speak it is a defect, not a variant.
2. **One line weight.** The ink stroke is the same nominal width across the whole
   set (scaled with the symbol, not re-chosen per symbol). A range and a village
   share stroke DNA. Wildly different line weights are the fastest "two packs
   mashed together" tell.
3. **One palette.** A tight, muted, shared palette — the sepia/parchment family for
   fantasy, not saturated Civ-tile greens/blues. Every stamp draws from the *same*
   swatch list (the `PARCHMENT` palette in `mapStudio.ts` is the anchor). New
   symbols sample it; they don't introduce a new hue.
4. **One global light direction — NW / 315°.** Every raised form (peak, roof,
   tower, dune) is lit from the upper-left and shadows to the lower-right. This is
   the single most important physical-coherence rule: mixed light directions make a
   sheet read as pasted sprites instantly (CRITIQUE #9). NW is the cartographic
   convention (it dodges the "inverted relief" illusion; see relief depiction in
   [REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md)).
5. **Consistent scale relationships.** A city is bigger than a village; a range is
   bigger than a single peak; a tree-clump is smaller than a hill. Encode the
   *intended* on-map size ratio in the manifest so the renderer never draws a
   village larger than its capital. Scale is meaning here.
6. **Transparent backgrounds, flat framing.** Every stamp is a clean alpha PNG with
   no baked paper, no drop-shadow, no vignette, no ground disc. The sheet's shadow
   pooling and paper pass are applied *once, globally* at composite time
   (RENDERING_PIPELINE) — if each stamp bakes its own, they never fuse.

**The test:** lay the whole set on one neutral sheet at consistent scale. If a
stranger can't tell it was drawn by a single illustrator in a single sitting, it
fails. Cull or restyle the outliers before adding breadth.

---

## 3. Generation via our pipeline — reuse FIRST, generate LAST

Follow the [asset-reuse](../asset-reuse/SKILL.md) ladder **in order**. Generating
is the *last* rung, not the first reach:

1. **Stable-ID manifest** — is the symbol already in `map-stamps.manifest.json`?
   Reuse it; never regenerate a glyph we own.
2. **Owned / CC0 cartography kit** — check `pieces/asset-kits/_library/BY_THEME.md`
   for map/terrain/cartography kits and the NAS bundles (`\\DXP4800PLUS-A79\NoxDev`).
   We own large asset libraries; a coherent CC0 map-symbol pack beats anything we
   generate and comes license-clean. Record the license for [credits](../credits/SKILL.md).
3. **Derive / restyle an owned symbol** — recolor to the parchment palette, re-ink,
   re-light to NW, or trace an owned silhouette into our idiom. Cheaper and more
   coherent than a fresh generation.
4. **Generate LAST** — only for genuine gaps, via the [image-pipeline](../image-pipeline/SKILL.md).

### The transparent-scaffold generation approach
When you must generate (this is how the shipped P9 core set was made — ComfyUI +
**Z-Image-Turbo** with one style anchor), the prompt scaffolds the symbol so it
chops cleanly and matches the set:

- **Idiom lock:** "single sepia-ink cartography symbol, hand-drawn engraving style,
  light brown wash relief" — name the exact idiom every time so the batch coheres.
- **Light lock:** "lit from upper-left, soft shadow to lower-right" — bake the NW
  convention into the prompt, not just post.
- **Background lock:** "on a flat plain off-white background, no border, no frame,
  no paper texture, centered, full symbol in frame with margin" — a flat, uniform,
  high-contrast background is what makes the automatic chop reliable.
- **Isolation lock:** "one symbol only, no scene, no other objects, no text" — a
  scene can't be chopped into a stamp.
- **Batch the whole kind, not one:** generate the full 4–6 variants of *each* kind
  in one styled batch so they share the anchor. **Failure mode to avoid:**
  generating a handful of hero stamps, cherry-picking the best seed, and calling it
  "the set." A set is the whole tree in §1 at coherent quality across variants —
  not five lucky mountains. (This is the symbol-library sibling of the P9 one-seed
  trap in [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md).)

### Chop → alpha → budget → register
Each generated (or sourced) raster becomes a shippable stamp via:

1. **Border flood-fill → alpha.** Flood from the four corners across the uniform
   background and knock it to transparent; the isolated symbol survives. The flat
   background from the prompt is what makes this clean — a busy/gradient background
   leaves halos.
2. **Autocrop.** Trim to the symbol's alpha bounding box (+ a small transparent
   margin) so `w`/`h` in the manifest are the *intrinsic* symbol size and the
   renderer gets correct aspect.
3. **Downscale + quantize to the byte budget.** Stamps ship as base64 data URIs
   embedded in `mapStampAssets.ts`, so bytes are the constraint. Downscale to the
   max on-map size, quantize the palette (the muted set quantizes well), and
   PNG-crush. Keep each stamp lean — a stamp registry is loaded whole.
4. **Register by stable ID.** Add the `StampAsset` (`{ uri, w, h, id }`) under its
   `kind` in the `MAP_STAMPS` record in
   `apps/web/lib/actions/mapStampAssets.ts`, and record provenance + license for
   that `id` in `map-stamps.manifest.json`. The **id is the contract**
   (`map-stamp/<kind>/<n>`) — the [asset-manifest](../asset-manifest/SKILL.md)
   binding that lets Jesus swap the art live from the Studio without touching
   placement code.

### What ships today vs the gap
`mapStampAssets.ts` currently registers **11 kinds**: `mountain`, `hill`, `forest`,
`tree`, `marsh`, `village`, `town`, `city`, `castle`, `ruins`, `range` — the P9
cohesive sepia-ink/NW-light core that killed the P8 palette clash. That is a
*coherent seed*, not the full library. The §1 tree is the roadmap: the missing
families (volcano/mesa/dunes; conifer/jungle/scrub/crops; keep/tower/temple/bridge/
mine/lighthouse/port; the whole POI, hazard, nautical, and décor sets) are the work
between "a coherent 11" and "Inkarnate breadth." Add them **by family, coherently**,
never one-off.

---

## 4. Placement — symbols are placed by the model, not scattered

A symbol library is inert until something decides *where each glyph goes*. That is
**not** this doc's job and **not** a per-cell scatter. Placement is owned by the
**biome/density model** in [TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md):

- **Relief** is walked along **ridgelines** extracted from the massif mask — tallest
  peak on the crest, tapering to hills at the foothills — never one peak per cell.
- **Vegetation** is placed **sparsely within its biome belt** with scale/spacing
  variance, so the parchment shows through (Law 1: restraint). A uniform tree
  carpet is the #1 amateur failure and an automatic CRITIQUE #1 zero.
- **Settlements** snap to water / passes / coasts; **roads** connect them along
  valleys; **POIs** drop as narrative anchors.

So this doc supplies the *vocabulary* and the *coherence*; the biome model supplies
the *grammar* (where each word is allowed to appear); the
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) supplies the *typesetting* (one
light, pooled shadow, one paper pass). All three must hold or the map fails the
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md).

---

## 5. Breadth toward thousands — the multiplier math, not new drawings

Inkarnate's 700 → 16,000 → 23,700+ counts (see
[Inkarnate updates](https://inkarnate.com/updates)) are not 23,700 unique *meanings*
— they are a coherent core **multiplied** along orthogonal axes. You reach four-
and five-figure breadth without diluting coherence by multiplying, never by
one-off inventing:

- **× Style pack** — the same core rendered in each idiom: parchment ink, blueprint
  schematic, topographic real-map, ink-noir. One core of 150 × 4 styles = 600.
- **× Palette skin** — biome/season/faction recolors of an area/relief set (verdant
  vs autumnal forest; snow vs bare peak; six realm-color heraldry blanks). A handful
  of skins turns 600 into low thousands.
- **× Regional flavor** — architecture families for settlements/structures (Norse,
  desert-Levantine, far-eastern, gothic-European). The *meaning* ("city") is fixed;
  the silhouette flavors it.
- **× Hand-variant** — the 3–5 genuine variants per kind that already kill the
  rubber-stamp tell, counted per (kind × style × flavor).

The discipline: **the meaning set stays small and fixed; the rendering multiplies.**
Every multiplied glyph still passes the one-hand test *within its style pack*. This
is how you grow toward Inkarnate breadth without the incoherence that a
grab-bag-of-packs approach produces. Register each multiplied glyph under the same
`kind` with its style/skin/flavor encoded in the manifest so the Studio can filter
and swap by axis.

---

## 6. Checklist for a symbol set (before it counts as "a library")

- [ ] Every family in §1 has ≥ its target base count; no family is empty.
- [ ] Each kind has ≥3 genuine hand-variants (not one PNG rescaled).
- [ ] "Drawn by one hand" test passes: one idiom, one line weight, one palette.
- [ ] Global NW/315° light on every raised form; no mixed light directions.
- [ ] Scale ratios encoded and sane (capital > city > town > village; range > peak).
- [ ] Every stamp is clean transparent alpha, no baked paper/shadow/vignette.
- [ ] Each stamp autocropped; `w`/`h` are intrinsic; under byte budget; quantized.
- [ ] Every `id` registered in `mapStampAssets.ts` **and** provenance/license logged
      in `map-stamps.manifest.json`.
- [ ] Reuse ladder was climbed (manifest → owned kit → derive → generate) and the
      choice is recorded, not skipped straight to generation.
- [ ] The set was judged as a *set* on one sheet at scale — not one hero seed.

If any box is unchecked, it is a coherent *seed*, not a library. Ship coherence
first, then breadth — never breadth at the cost of the one-hand test.

---

*Siblings: [SKILL.md](SKILL.md) · [MAP_TYPES.md](MAP_TYPES.md) ·
[BATTLEMAP_ASSETS.md](BATTLEMAP_ASSETS.md) (tactical-scale asset library — the
top-down/VTT sibling of this region-scale symbol set) ·
[MAP_REFERENCE_GALLERY.md](MAP_REFERENCE_GALLERY.md) ·
[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) ·
[TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md) ·
[REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md) ·
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) ·
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) ·
[../asset-reuse/SKILL.md](../asset-reuse/SKILL.md) ·
[../image-pipeline/SKILL.md](../image-pipeline/SKILL.md)*
