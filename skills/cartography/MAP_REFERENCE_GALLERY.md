# Map Reference Gallery — the specific things pro maps do, and how to make our renderer do them

This doc is **grounded reference**: real, named exemplars (Tolkien / Baynes / Fonstad,
the classic RPG atlases) and the *exact technique* each teaches — line weight,
side-view relief, hachures, coastline echo, tapered rivers, book-plate framing,
disciplined lettering — each followed by a **"so-what for our renderer"** spec that
names the code it touches in `apps/web/lib/actions/mapStudio.ts`
(`renderParchment`, `buildStamp`, `riverRibbonPath`, `landMedialPathPx`,
`coastFollowPathPx`, `LABEL_SPEC`/`labelStyleOf`, the `npx-relief` filter — see
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) for line numbers). It exists to fix
the four complaints we keep hitting: **text scattered everywhere, flat/weak relief,
crude rivers, and a map that reads as a background instead of a plate.**

Read alongside [FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) (the idiom),
[REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md) (Imhof relief + Imhof lettering canon —
this gallery is the *applied, exemplar-driven* companion to that theory),
[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) (the glyphs), and
[BATTLEMAP_ASSETS.md](BATTLEMAP_ASSETS.md) (the tactical-scale sibling of finding 1's
region-scale relief). Grade every change against
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md).

> **How to use each entry:** the *reference* describes what the master did precisely
> enough to reproduce; the **⇒ renderer** block is the drop-in spec. If you can't
> point at the code an entry changes, you haven't finished reading it.

---

## 1. Famous fantasy maps — what makes them read *professional*

### 1a. J.R.R. Tolkien's own maps + Christopher Tolkien's 1954 *LotR* map
**Source:** [Tolkien's maps — Wikipedia](https://en.wikipedia.org/wiki/Tolkien%27s_maps),
[A Map of Middle-earth — Wikipedia](https://en.wikipedia.org/wiki/A_Map_of_Middle-earth),
[Tolkien Gateway: Karen Wynn Fonstad](https://tolkiengateway.net/wiki/Karen_Wynn_Fonstad).

What makes them read pro, concretely:

- **Side-view (profile) relief, not plan-view symbols.** Mountains are drawn "as if
  seen in three dimensions" — little **elevational profiles** (you see the *face* of
  the peak, lit from one side) chained along a spine, tallest on the crest tapering
  to lower hills at the ends. This is the single biggest "reads as a fantasy map"
  cue. Ranges are one continuous drawn mass, not N discrete peak-stamps.
- **Multiple coastline waterlines ("echo lines").** Coasts get 2–4 progressively
  fainter lines paralleling the shore out into the sea. This is what lifts land off
  water (figure–ground) without a color fill.
- **Restraint / honest blank space.** Tolkien deliberately left **blank space
  between features** — he cited it as an "18th-century innovation" meaning *what is
  drawn is reliable*. Empty parchment is a statement of confidence, not laziness.
  (This is our Law 1, sourced to the master himself.)
- **Forests as massed, varied symbol fields** — Mirkwood is "closely packed tree
  symbols" mixed with hills/lakes/spiders; the canopy idiom, drawn by hand with
  variation, never a uniform tiled fill.
- **Hand-lettered names, one weight, following an "archaic air"** — "a culture
  without printing presses," graceful but functional (Arts-and-Crafts, not medieval
  pastiche). Place-names sometimes overprinted in red for a second ink.

**⇒ renderer:** Our `npx-relief` body pass already does side-view brushes on a
pooled shadow — good. Push it harder toward *profile* stamps (visible lit face +
cast shadow) and make the **range** kind a genuinely continuous drawn mass along the
ridgeline walk, not repeated single peaks (see [RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)
"ridgeline relief engine"). The coastal echo already exists (sea-halo + 3 ripple
rings, layers 2–3) — that IS the Tolkien multi-waterline; keep it and consider a 4th
fainter ring on world scale. Enforce blank space via the density model
([TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md)) — if <40% parchment is visible, the
seed fails CRITIQUE #1. Optional "second ink": a `#a03a2a` red-overprint variant for
capital labels, echoing Tolkien's red place-names.

### 1b. Pauline Baynes' 1970 poster map
**Source:** [A Map of Middle-earth — Wikipedia](https://en.wikipedia.org/wiki/A_Map_of_Middle-earth),
[paulinebaynes.com](https://www.paulinebaynes.com/?what=artifacts&image_id=461&cat=79).

Baynes (who drew Admiralty **nautical charts** in WWII before illustrating Tolkien &
Lewis) added on top of Christopher's linework: **decorative marginalia** — figures,
vignette scenes, and a **framing border of illustrations** around the geographic
plate. The map is presented as an *illustrated plate*, not just terrain: the border
carries characters/heraldry and the corners are ornamented.

**⇒ renderer:** This is the argument for a real **frame/marginalia layer** above the
neatline (finding 5). Reserve a border band; drop corner cartouche + a few
sea-marginalia stamps (ship, sea-beast) from the NAUTICAL family in
[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md). Keep them sparse — Baynes framed,
she didn't clutter the geography.

### 1c. Karen Wynn Fonstad — *The Atlas of Middle-earth*
**Source:** [The Atlas of Middle-earth — Wikipedia](https://en.wikipedia.org/wiki/The_Atlas_of_Middle-earth),
[WPR profile](https://www.wpr.org/news/wisconsin-cartographer-karen-wynn-fonstad-mapped-tolkien-fantasy-world-oshkosh).

Fonstad was a **trained academic cartographer** (MA Geography, cartography;
ex-Director of Cartographic Services, UW-Oshkosh). Her atlas is the gold standard
for *disciplined* fantasy cartography and teaches:

- **Clean B&W line + stipple/tonal relief** instead of painterly wash — relief read
  through **line technique** (stipple density, fine hachure-like slope ticks),
  because the atlas prints in monochrome. This is the "relief through lines" idiom
  our renderer is starting to do.
- **A family of coordinated map TYPES for one world:** regional maps *by historical
  period*, **thematic** maps (landforms, climate, vegetation, population,
  languages), **battle** maps (troop movement arrows, phase overlays), **city**
  maps and **building floor plans** (Minas Tirith: perspective view + circular plan
  inset + citadel plan + labelled White-Tower cutaway).
- **Real-atlas rigor:** she reasoned about geology (Emyn Muil vs real formations),
  reconciled contradictions, and derived terrain from history — geography is
  *argued*, not scattered.

**⇒ renderer:** Fonstad validates our multi-type catalog ([MAP_TYPES.md](MAP_TYPES.md))
and the blueprint/topographic style variants. Her B&W stipple-relief is a *style
pack* we should ship: an "atlas ink" mode = no sepia film, black hairline coast,
stipple/hachure relief, small-caps serif labels. Her thematic maps map onto our
`regions` overlay (climate/vegetation/political as swappable tint layers). Her
inset-heavy city plates → our inset-map support (locator + detail plate).

### 1d. Forgotten Realms / classic TSR & RPG atlases
**Source:** general RPG-cartography lineage (Fonstad also drew the official atlases
for the Forgotten Realms, DragonLance, and Shannara — [Tolkien Gateway: Fonstad](https://tolkiengateway.net/wiki/Karen_Wynn_Fonstad)).

Classic RPG maps add **playability furniture** on top of the illustrative base:
a **hex or square overlay** at a stated scale (e.g. "1 hex = 30 miles"), a **legend
key**, numbered/keyed locations tying the map to gazetteer text, and clear
**political borders** (dashed/dotted lines, sometimes tinted province fills).

**⇒ renderer:** Our `gridOverlay` already models this; expose hex *and* square at a
labelled scale (A-1 gridref already exists in the blueprint mode). Add a **legend/key
frame** to the décor layer and a **keyed-marker** label style (numbered pins that
cross-reference a gazetteer panel) — this is also the bridge to the VTT
([VTT_TOOLING_GAPS.md](VTT_TOOLING_GAPS.md): handouts/compendium).

**The through-line (why all four read professional):** *side-view relief chained on a
spine · coastline echo lines · disciplined single-hand line weight · honest blank
space · lettering as a designed layer · decorative frame kept OFF the geography.*
Density is never the tell; **restraint + hierarchy + one hand** is.

---

## 2. Label / lettering technique — the fix for "text all over the place"

This is Jesus's specific note and the most common amateur tell. The competitor look
comes from a small set of **hard rules**, all mechanizable.
**Sources:** [Axis Maps — Labeling & text hierarchy](https://www.axismaps.com/guide/labeling),
[Typography (cartography) — Wikipedia](https://en.wikipedia.org/wiki/Typography_(cartography)),
[Inksorcery — Naming & Typography](https://inksorcery.com/fantasy-map-tutorial-part-iii-naming-and-typography/),
plus Imhof "Positioning Names on Maps" (see [REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md) §6).

### 2a. Point labels (settlements) — deterministic offset ladder
Axis Maps' canonical priority order, **in this exact sequence**, take the first
placement with no collision:
1. **above-right** (the preferred default), 2. **below-right**, 3. **above-left**,
4. **below-left**. (Straight above/below/beside are lower priority — used only if
all four diagonals collide.) The label sits on a **horizontal baseline** offset a
consistent small gap from the symbol anchor — *not* touching it, *never* overlapping
another symbol.

### 2b. Area labels (regions, seas, kingdoms, ranges) — letterspaced along the shape
- **UPPERCASE**, **wide letter-spacing (tracking)** so the word *spans and describes
  the extent* of the area. Bigger area → wider tracking. This is the "letterspacing
  demotes a point label but *defines* an area label" rule.
- **Visually centered** in the polygon, on a **gently curved baseline following the
  area's long axis** (medial line), not a flat horizontal string.

### 2c. Linear labels (rivers, roads, ranges) — curve along the feature
Name **curves along the feature** on a spline baseline, letters riding the curve,
reading left→right (flip so text is never upside-down; for near-vertical features
read bottom→top). Long rivers **repeat the label** along their length.

### 2d. The size hierarchy (world > region > settlement) + the small-caps / drop-cap idiom
- **Three tiers, three sizes, ≤3 typefaces total** (hard cap). World/continent
  largest + widest tracking; region mid; settlement smallest. Rank drives size &
  weight; muted grey *demotes* minor labels, black/red/bold *promotes* major ones.
- **Small caps** are the settlement idiom (initial cap + smaller capital letters);
  **ALL CAPS** reserved for the largest area/capital names.
- **The "Lis-Ki (Ruiner)" drop-first-letter treatment Jesus flagged** = *small-caps
  rendered as large-initial + small-capital body per word*: the first glyph of each
  word is set ~130–150% of the small-cap body height. Implement it as a per-word
  run: `firstGlyph @ 1.0em` + `restOfWord @ ~0.72em, uppercase`. A parenthetical
  epithet ("(Ruiner)") is set smaller still (~0.6em) on the same baseline. This one
  treatment is most of the "pro lettering" feel.

### 2e. Water in italic (the oldest convention)
All hydrography — rivers, lakes, seas, bays — is **italic** (and, on color maps,
tinted blue/blue-grey). Land features stay upright. This alone signals "cartographer
knows the rules." (Imhof; Axis Maps.)

### 2f. Legibility: halo / knockout + collision
- **Halo/knockout:** every label gets a soft **cream/paper-colored outline halo**
  (or a knockout mask that erases texture behind the glyphs) so type stays legible
  over busy terrain. Halo width ≈ 10–15% of cap height, feathered.
- **Collision:** labels never overlap **each other** or **symbols**; on conflict,
  demote (try next offset in the 2a ladder), nudge (displace along the baseline), or
  drop the lower-priority label. Minimum size floors: **~9–10pt on screen** — below
  that, drop rather than render mud.

**⇒ renderer:** We are already most of the way here — `labelStyleOf()` → `LABEL_SPEC`
gives the hierarchy, `landMedialPathPx()` curves region names on the medial line,
`coastFollowPathPx()` hugs coastlines, point labels try a **7-offset ladder** with
collision avoidance, and every label gets a **two-pass cream ink halo**
([RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) label section). The concrete upgrades
this finding demands:
1. **Reorder the point-offset ladder to Axis's exact priority** (above-right first),
   so placement matches the competitor idiom instead of an arbitrary order.
2. **Add the drop-first-letter small-caps run (2d)** to `LABEL_SPEC` as the
   settlement/region style — this is the specific fix for "letters look amateur."
   Render per-word: large initial + small-cap body + smaller parenthetical.
3. **Enforce italic for ALL water labels** (rivers/lakes/seas), not just ocean — tie
   to the hydro feature type in the generator.
4. **Add river/range/feature labels** (currently only settlement/realm/sea exist —
   flagged as the gap in RENDERING_PIPELINE): curve river names along
   `riverRibbonPath`, repeat on long rivers; letterspace range names along the
   ridgeline spline.
5. **Tracking scales with area extent** for area labels (wider word = wider region).
6. Keep the halo; make its width a function of cap height (10–15%).

---

## 3. River rendering — smooth, tapered, meandering + water echo lines

**Sources:** [Map Effects — How to Draw Rivers](https://www.mapeffects.co/tutorials/rivers),
[Azgaar — Polygonal rivers](https://azgaar.wordpress.com/2018/02/12/polygonal-rivers/),
[H.M. Turnbull — Rivers](https://hmturnbull.com/writing/fantasy/map-making/rivers/).

### 3a. The shape rules (geographic truth = believable look)
- **Source high, mouth low.** Rivers start at mountains/high ground and run to
  sea/lake. **Water never splits going downstream** — tributaries only *join* (the
  sole exception is a **delta/marsh** at the mouth). A river forking downhill is the
  #1 river error and an instant amateur tell.
- **Meander, don't ruler-line it.** Rivers weave along the path of least resistance
  between relief. Add intermediate control points and smooth.

### 3b. The polygon-with-taper technique (Azgaar's exact method — implementable)
Draw the river as a **filled polygon of variable width**, not a constant stroke:
1. Collect ordered points source→mouth; **densify** them and interpolate with a
   smooth curve (D3 `curveCatmullRom`/basis) for meander.
2. For each sample point, compute the **flow angle** from neighbors
   `atan2(from.y−to.y, from.x−to.x)`; the **normal** is perpendicular.
3. **Width grows with distance/flux:** `offset = atan(l / widening)` where `l` =
   accumulated length and `widening` ≈ 200 (tune to scale) — thin at source, wider
   downstream. At each **confluence**, add extra width proportional to the joining
   river's volume.
4. Offset each point ±`offset` along the normal to get **left-bank** and
   **right-bank** point arrays; curve-interpolate each bank separately; join
   left-forward + right-reversed into one closed polygon; always include the mouth
   endpoint.

Simpler stroke fallback (Map Effects): a single **pressure-tapered stroke**, thin at
source, thickening downstream, with equal ease-in/ease-out on the taper — cheaper,
reads fine at region scale.

### 3c. Coastline & lake **echo lines** (parallel water lines)
The multi-waterline look (Tolkien 1a, portolan charts): draw **2–4 lines paralleling
the shore**, each **offset progressively outward** into the water and **fading**
(lower opacity / thinner) with distance. Same treatment rings the inside of lakes.
This is a pure **inward/outward buffer-offset of the coastline path**, stroked N
times at increasing offset and decreasing alpha.

**⇒ renderer:** We already ship the taper (`riverRibbonPath`, half-width grows
0.16→1.0 source→mouth) and the coastal echo (sea-halo + 3 ripple rings). The
upgrades:
1. **Move to the polygon-with-normal-offset model** (3b) so width is driven by
   accumulated flux and **confluences visibly widen** the river — our current linear
   0.16→1.0 ramp ignores tributary volume.
2. **Densify + Catmull-Rom** the river control points for real meander (avoid
   straight segments between nodes).
3. **Form lakes at interior minima** instead of `break`-ing the river at a local
   minimum (the known bug in RENDERING_PIPELINE §"believable geography") — then ring
   the lake with the same echo lines.
4. **Curve the river label along the ribbon** and set it **italic** (finding 2c/2e).

---

## 4. Relief / terrain depth lines — hachures, cross-hatching, slope ticks

**Sources:** [Andy Woodruff — Hachures and sketchy relief maps](https://andywoodruff.com/blog/hachures-and-sketchy-relief-maps/),
[Hachure map — Wikipedia](https://en.wikipedia.org/wiki/Hachure_map),
[Terrain cartography — Wikipedia](https://en.wikipedia.org/wiki/Terrain_cartography),
Lehmann's *Böschungsschraffen* / Imhof (see [REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md) §3).

### 4a. The hachure law (Lehmann, 1799 — still the rule)
Hachures are **short strokes drawn down the line of steepest slope (downhill,
following aspect).** The law: **steeper slope → thicker + denser + darker strokes;
flat ground → left white.** Read as a field, ridges and valleys "leap out." Great for
rolling hills and low relief where cast-shadow relief is weak.

### 4b. Andy Woodruff's sketchy-relief algorithm (directly implementable)
Over an elevation grid, at each cell:
1. Draw a **short stroke** whose **rotation = slope aspect** (downhill direction) and
   **width = steepness** (slope magnitude), **length ≈ slightly > cell size** so
   neighbors blend.
2. **Randomize for the hand-drawn look:** jitter stroke position off the grid, add a
   slight **curve** to each stroke, vary parameters per stroke.
3. **Multi-pass accumulation:** redraw the whole field several times at **low
   opacity**, each pass with the **sun angle varied a bit** — this builds tonal depth
   and the sketchy character.
4. **Shadow hachuring (Imhof shade):** modulate stroke **weight/darkness by
   illumination** (NW light) as well as slope — dark on shadowed SE faces, light on
   lit NW faces.
Key parameters to expose: grid cell size, stroke length ratio, opacity/pass count,
sun-angle jitter, position jitter, curve amount.

### 4c. Cross-hatching & contour cousins
- **Cross-hatching** (two crossed stroke sets) deepens shadow on the steepest,
  most-shadowed faces — reserve for cliffs/escarpments and the dark side of ranges.
- **Contour-line hint:** concentric closed loops = a summit; hachure ticks pointing
  *inward* = a depression/crater. A few contour rings around a peak base add "height"
  cheaply. Even **lowland/grass** gets faint, sparse slope ticks so it isn't dead flat
  ("the thing our renderer is starting to do").

**⇒ renderer:** Today relief is side-view **brush stamps** through `npx-relief` on a
pooled shadow (good for the Baynes/Wonderdraft idiom). Add a **hachure/atlas relief
mode** as a style variant (pairs with Fonstad 1c and the topographic type):
1. From the heightfield, compute per-cell **aspect + slope** (we already have the
   massif mask / ridgelines).
2. Emit Woodruff-style strokes (4b): downhill aspect, width∝slope, length>cell,
   jittered + curved, **multi-pass low-opacity**, weighted by NW illumination.
3. **Cross-hatch cliff/escarpment stamps** (the CLIFF kind in
   [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md)) with inward-pointing scarp
   ticks.
4. Add **faint sparse slope ticks on lowland/hills** so plains read as gently
   modeled, not blank fill — but keep it *under* the restraint budget (Law 1).
5. Hold **one light direction (NW/315°)** across brush relief AND hachures — mixing
   is the instant-amateur tell (CRITIQUE #9).

---

## 5. Map presentation / framing — a BOOK PLATE, not a background

**Sources:** [Fantastic Maps — Creating an aged paper handout](http://www.fantasticmaps.com/2016/01/creating-an-aged-paper-handout/),
[Map Effects — Aged paper textures](https://www.mapeffects.co/blog/paper-textures-photoshop),
[Figma — Fantasy Parchment / Rune Frame template](https://www.figma.com/community/file/1595134702661551358/fantasy-parchment-template-rune-frame-middle-earth-inspired),
Baynes' illustrated border (1b).

The difference between "a terrain image" and "a *map*" is that a map is presented as
a **single aged object on a framed plate**. The layered recipe:
1. **One global paper pass** over the whole composite: a warm sepia film (multiply,
   low opacity ~0.10–0.15) + a **paper-fibre/grain texture** (overlay). Applied
   *once, globally*, so every separately-drawn stamp fuses into one sheet (Law 9) —
   not per-stamp.
2. **Edge darkening / vignette:** a soft dark vignette + mottled **stain** blotches
   pull focus inward and age the sheet.
3. **Torn / burnt / deckle edges** (for a handout look) or a **clean neatline plate
   margin** (for an atlas look): heavy outer rule + hairline inner rule + corner
   keystones = an engraved plate.
4. **Decorative frame / border band** above the neatline: cartouche title panel,
   compass rose, scale bar, legend key, and **restrained marginalia** (a ship, a
   sea-beast, corner ornaments — Baynes 1b). The frame carries ornament so the
   **geography stays clean**.
5. **Book-spread mock** (for GDD/showcase presentation): place the plate on a
   two-page aged spread with a **center gutter shadow**, optional facing-page text,
   as a *presentation* wrapper — matches how atlases (Fonstad) and novels ship maps.

**⇒ renderer:** We already do #1 (global sepia film `#caa863` @0.11 + `npx-fiber`),
#2 (mottled stain + `npx-vign` vignette), and #3-atlas (neatline: heavy outer +
hairline inner + corner keystones). The gaps to close:
1. **Ship the décor/frame band (#4)** as a real layer above the neatline — cartouche
   + compass + scale bar + legend, sourced from the DÉCOR/NAUTICAL families in
   [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md). This is currently the thinnest
   part of our output.
2. **Add a torn/burnt-edge variant** (alpha-masked deckle edge) for the "handout"
   preset, distinct from the clean neatline "atlas" preset.
3. **Add a book-spread presentation wrapper** for the GDD Library / samples page:
   render the plate onto a two-page spread with gutter shadow, so maps show as
   *plates in a book*, not raw PNGs — dovetails with the Studio's
   [gdd-library](../../../Noxdev-Studio/apps/web/app/(studio)/gdd-library/) and
   `docs/samples.html`.

---

## Actionable summary (the five fixes, ranked)

1. **Lettering (finding 2):** reorder point-offset ladder to above-right-first; add
   the **drop-first-letter small-caps** run ("Lis-Ki (Ruiner)"); force **italic on
   all water**; add **river/range labels**; scale tracking with area extent. Kills
   "text all over the place."
2. **Relief (finding 4):** add a **hachure/atlas mode** (Woodruff strokes:
   downhill-aspect, width∝slope, multi-pass low-opacity, NW-weighted) + cross-hatch
   cliffs + faint lowland ticks; one NW light everywhere.
3. **Rivers (finding 3):** move to the **polygon normal-offset taper** with
   **confluence widening**, Catmull-Rom meander, and **lakes at interior minima**;
   label italic along the ribbon.
4. **Presentation (finding 5):** ship the **décor/frame band** (cartouche + compass +
   scale + legend), a **torn-edge handout variant**, and a **book-spread wrapper**.
5. **Relief idiom (finding 1):** make the **range** a continuous side-view drawn mass
   on the ridgeline; keep coastal echo lines; enforce **≥40% visible parchment**.

---

*Siblings: [SKILL.md](SKILL.md) · [REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md) ·
[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) ·
[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) ·
[BATTLEMAP_ASSETS.md](BATTLEMAP_ASSETS.md) · [MAP_TYPES.md](MAP_TYPES.md) ·
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) ·
[VTT_TOOLING_GAPS.md](VTT_TOOLING_GAPS.md) ·
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md)*
