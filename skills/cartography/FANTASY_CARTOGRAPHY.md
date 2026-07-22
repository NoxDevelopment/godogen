# Fantasy Cartography — the hand-drawn idiom, and how to hit each competitor's bar then exceed it

This is the **look-and-feel** reference: the visual language of the hand-drawn
fantasy/game map, where it comes from, exactly what makes it read as *drawn by a
person on aged paper* rather than *rendered by a machine*, and the concrete style
recipes our pipeline ships. It is the aesthetic half of the craft; the physical
half — how mountains, rivers, coasts, and biomes actually form — lives in
[TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md), and the real-cartography canon
(projection, relief theory, typography, figure–ground) in
[REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md). Read the [SKILL.md](SKILL.md) Ten Laws
first — this doc assumes them.

> **Why the idiom matters.** A fantasy map is a *forgery of a document* — it must
> convince the eye it was inked by a court cartographer centuries ago and survived
> to reach you. Every decision below serves that forgery. The moment a viewer
> thinks "software made this," the illusion — and the map's value to a game — is
> dead. Our historic failure (the P9 render; see
> [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md)) was a machine tell: a wall-to-wall
> carpet of identical stamps. This doc is the antidote.

---

## PART 1 — THE LINEAGE & THE LOOK

### 1.1 Where the idiom comes from

The modern fantasy map is a specific historical stack. Know the ancestors so you
copy the *reasons*, not just the surface.

- **Real portolan & Renaissance sea-charts (14th–17th c.)** — the deep ancestor.
  Rhumb-line networks radiating from compass roses, richly illustrated cartouches,
  ships and sea-monsters filling the empty ocean, coastlines emphasized with ink,
  the whole thing on vellum. Fantasy cartography is a *pastiche of this era*, not
  of modern survey maps. When in doubt, look at a 1550 chart, not a 1950 atlas.
- **J.R.R. Tolkien's working maps.** Drawn for years on squared paper — each 2 cm
  square = 100 miles — layered with pencil annotations and inks added over decades.
  The look is *utilitarian ink*: firm coastlines, side-view "molehill" mountain
  ranges walked along spines, hatched forests, sparse hand-lettered labels, vast
  open interior. Restraint is baked in because he was drawing a *working reference*,
  not decoration. ([Tolkien's maps — Wikipedia](https://en.wikipedia.org/wiki/Tolkien%27s_maps))
- **Christopher Tolkien's redrafts.** Turned his father's drafts into the
  publishable *LOTR* maps. His cartography is "hugely influential" — it set the
  genre norm that *epic fantasy comes with a map*. This is the topographical,
  authoritative, black-ink-on-cream register. ([A Map of Middle-earth — Wikipedia](https://en.wikipedia.org/wiki/A_Map_of_Middle-earth))
- **Pauline Baynes's 1970 poster map.** Commissioned by Allen & Unwin; Tolkien
  annotated her copy of Christopher's map. Baynes added the *illustrated marginalia*
  register — colored vignettes, decorative borders, figures and beasts framing the
  sheet. This is where "map as painted artifact" (vs. line-only reference) enters
  the canon. ([Pauline Baynes map](https://www.paulinebaynes.com/?what=artifacts&image_id=461&cat=79))
- **A cautionary tell:** HarperCollins's later redrafting made the maps look
  "bland, modern, professional," *losing the hand-drawn feeling*. That sentence is
  the whole failure mode in miniature. Clean vector precision is the enemy;
  controlled imperfection is the goal.
- **Forgotten Realms / classic TSR RPG maps (Greenwood/TSR, 1980s–90s).** The other
  great lineage: hex-friendly regional maps with a dense but *legible* symbol
  vocabulary (walled cities, keeps, ruins, forests, marshes), strong political
  labeling, a workmanlike ink-and-flat-wash palette. This is the "campaign setting"
  register — information-rich, gazetteer-adjacent.
- **Modern hand-drawn cartographers & the Wonderdraft/CartographyAssets scene
  (2018–now).** Megasploot's Wonderdraft codified the *inked region map* as a
  repeatable software idiom (coastal echo, symbol brushes, theme palettes), and the
  CartographyAssets / Fantasy Map Assets community produced thousands of matched
  symbol packs. This is the *contemporary* bar and the palette most players now
  read as "fantasy map." ([Wonderdraft](https://www.wonderdraft.net/),
  [Fantasy Map Assets](https://fantasymapassets.com/wonderdraft-assets/))

### 1.2 The seven tells that make a map read as *hand-drawn*

These are the levers. Every one is something a naïve renderer gets wrong and a
person gets right. Grade our output against them (they map directly onto
CRITIQUE_CHECKLIST dimensions 1, 2, 6, 9).

1. **Line-weight variation.** A human's pen swells and thins. Coastlines are heavier
   than rivers; a river tapers from mouth (thick) to source (hairline); a mountain's
   lit edge is a whisper and its shadowed edge is bold. *Uniform 1-px strokes are the
   single loudest machine tell.* Vary weight by feature class AND along each stroke.
2. **Imperfect repetition.** Ten trees in a forest are ten *slightly different*
   drawings, jittered in scale (±15–25%), rotation (±8°), and baseline. A grid of
   identical clones is instantly synthetic. Design symbols in small *families* (3–6
   variants each) and jitter placement. (See [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md).)
3. **Aerial-perspective relief (mountains).** Fantasy mountains are drawn in
   *oblique/side-view* — little pictographic peaks seen from a low angle — not as
   top-down shaded relief. They obey Imhof's aerial perspective: peaks nearest the
   crest are largest, darkest, most detailed; they *shrink, pale, and simplify* down
   the flanks toward the plains. This is what makes a range read as a raised mass
   receding into distance rather than a scatter of bumps.
4. **Side-view / pictographic symbols generally.** Not just mountains — trees,
   castles, towers, ships are drawn *as if seen from an oblique angle*, tiny
   elevations planted on a top-down base. This deliberate mixed-projection ("plan for
   the ground, elevation for the objects") is a *defining convention* of the idiom.
   Consistency of the fake light and fake horizon across all of them is what fuses
   the sheet (Law 9).
5. **Restrained palette.** Three to six inks/washes, not a rainbow. Sepia/umber line,
   a warm parchment ground, one or two muted terrain washes (sage green, dun,
   slate-blue water), maybe a single accent (vermilion for capitals/borders). Broad
   saturated fills scream "digital." (Full palettes in Part 4.)
6. **Coastal echo / emphasis lines.** Concentric parallel lines hugging the coast,
   fading seaward (2–5 echoes, each lighter and more widely spaced). Purely
   decorative, purely diagnostic: no feature signals "old sea-chart" faster. Also
   used as a figure-ground device — it makes land pop as figure.
7. **Honest empty space.** The interior *breathes*. Historic maps leave plains, seas,
   and unknown regions largely open (filled only with a label, a rhumb line, or a
   lone beast). Amateurs fear emptiness and carpet it; masters use it as hierarchy.
   **This is our #1 historic failure and the heaviest-weighted critique dimension.**

If a render nails these seven, it reads as drawn. If it misses even two or three, no
amount of "detail" rescues it — the detail is the problem.

---

## PART 2 — INK-AND-WASH TECHNIQUE FOR MAPS

The dominant fantasy idiom is **ink line + light watercolor wash on aged parchment.**
Here is how to reproduce each layer so the composite reads as one physical sheet.
Where this touches our layer stack, see [RENDERING_PIPELINE.md](RENDERING_PIPELINE.md).

### 2.1 The parchment base (the paper is a character, not a backdrop)

Parchment is *warm off-white*, never pure `#FFFFFF` and never flat. Build it:

- **Base tone:** warm cream `#EAD9B0`–`#F0E4C8` (aged) or paler `#F5ECD7` (fresh
  vellum). Never grey-white; the warmth sells "old."
- **Fibre & mottle:** a low-contrast paper/fibre texture (subtle noise + long fibre
  streaks) multiplied over the base at 8–15% so it's felt, not seen.
- **Stains & foxing:** irregular tea-colored blotches (`#C9A876` at 10–20% opacity),
  concentrated toward edges and corners, a few random interior spots. Uneven = real.
- **Edge burn / vignette:** darkened, slightly desaturated margins (radial or
  four-corner), simulating age and handling. A gentle inner vignette also focuses
  the eye (figure-ground).
- **Torn / burnt / deckled edge (optional, style-dependent):** ragged rather than
  crisp rectangular border for the "recovered artifact" look; or a clean ruled
  neatline for the "official survey" register. Choose per style — don't mix.

**Tell:** if the "parchment" is a uniform gradient, it's wallpaper, not paper. Real
aging is *blotchy and directional* (worse at edges, at folds).

### 2.2 Ink linework

- **Color:** sepia/warm brown `#5A3E28`–`#3E2C1C` for the classic look, or near-black
  `#2A2118` for the authoritative topographic register. Pure black `#000000` is too
  cold and modern — pull it warm.
- **Weight hierarchy (heaviest → lightest):** coastline ▸ major political border ▸
  mountain shadow edges ▸ river mouth ▸ forest/settlement outlines ▸ river source ▸
  hachures/texture. Assign a weight *band* to each class and vary within it.
- **Line quality:** slightly irregular, with subtle pressure variation and occasional
  overshoot at corners/junctions. Perfectly smooth Béziers read as vector. If
  generating symbols, request "traditional pen-and-ink, varied line weight, slight
  imperfection," never "clean vector."
- **Coastal echo:** the signature ink move — see Part 1, tell #6.

### 2.3 The wash (color)

- **Application:** *light and directional*, applied inside the ink shapes but allowed
  to be uneven — pooling darker at edges (the "watercolor edge-darkening" effect),
  paler in centers. Flat 100%-opacity fills are the anti-pattern.
- **Terrain washes:** muted, desaturated. Sage/olive greens for forest and lowland
  (`#8A9A5B`, `#6B7A4A`), dun/tan for plains and steppe (`#C8B27E`), pale ochre for
  desert (`#D8C088`), grey-violet for high mountains (`#8B8390`), white-blue for ice
  (`#DCE6EA`), slate/teal for water (`#7FA0A8`→`#5C8088`, deeper offshore).
- **Directional light on relief:** shade one consistent side of every mountain/hill
  (pick a light direction — typically upper-left, NW — and NEVER vary it). The wash
  darkens the anti-light flank; a thin highlight or bare parchment marks the lit
  flank. This single rule does most of the work of making relief read as 3-D and of
  fusing the sheet (Law 9).
- **Aerial recession in wash:** distant/high terrain slightly bluer and paler
  (atmospheric perspective), foreground/low terrain warmer and stronger.

### 2.4 Shading textures: stippling, hatching, hachures

- **Stippling** (dots): for sandy desert, rough ground, subtle tonal gradients. Dot
  density = darkness. Hand-random spacing, never a regular grid.
- **Hatching / cross-hatching** (parallel line sets): for shadowed slopes, cliffs,
  forest mass shadow, marsh. Follows the form; denser = darker.
- **Hachures** (short lines pointing downslope, thick-at-top): the classic *relief*
  texture for ridges and escarpments — steeper slope = longer/denser hachures. A
  more topographic register than pictorial mountains; can combine with them.
- **Water texture:** fine parallel *coastal echo* lines near shore; open sea left
  mostly bare or carrying faint horizontal "sea lines," stylized waves, or a
  wandering current line. Do NOT flat-fill the ocean a solid blue — that's a video-
  game minimap tell.

### 2.5 The unifying global pass (make it ONE sheet)

After all layers composite, run a **single global aging/paper pass** over the whole
image so ink, wash, symbols, and labels share the same paper grain, the same edge
burn, the same slight overall color cast and contrast knock-down. This is the step
that converts "N pasted sprites on a background" into "one aged document." Details
and the exact layer order in [RENDERING_PIPELINE.md](RENDERING_PIPELINE.md).

---

## PART 3 — DECORATIVE APPARATUS & MARGINALIA

The furniture around and within the map is 30% of the "expensive fantasy map" read.
Amateur maps are bare or use one generic compass clip-art; pro maps have a *coherent
decorative program* in the same idiom as the linework. Every element below binds by
stable ID through the Studio manifest (see [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md)).

- **Cartouche / title frame.** An ornamental panel carrying the map's title (and
  often subtitle, author, date). Ranges from a simple ruled box with corner flourishes
  to a full illustrated scroll/banner/heraldic frame. Place it in a *quiet* area
  (open sea, empty corner) — never over important geography. Type inside uses the
  display face (Cinzel / Uncial for fantasy — see [typography](../typography/SKILL.md)).
- **Compass rose / wind rose.** North indicator, from a plain fleur-de-lis-tipped
  star to an elaborate 8/16/32-point rose with cardinal lettering. On sea-chart
  styles, add **rhumb lines** (thin straight lines radiating from the rose across the
  map) for authentic portolan flavor. One rose, well-placed; not three.
- **Scale bar.** A ruled bar in fantasy units ("leagues," "miles") — earns realism
  cheaply and signals "this is a real place with real distances." Style it to match
  (ornate end-caps for fancy sheets, plain ticks for topographic).
- **Legend / key.** A boxed table of symbol meanings (● city, ⌂ ruin, ⚔ battle,
  ⚓ port). Essential for information-dense campaign/political maps; optional for
  decorative art maps. Keep it in the same panel idiom as the cartouche.
- **Border / neatline.** The frame that contains the sheet. Options: a simple double
  ruled line; a Greek-key / vine / rope / chain decorative band; a graticule border
  with tick marks and coordinate labels (more "official"); or no hard border with a
  torn/deckled edge (more "artifact"). The border sets the register — choose to match
  the style, and keep line weight consistent with the interior ink.
- **Marginalia — the storytelling furniture:**
  - **Sea monsters, krakens, serpents** breaching in open ocean — the single most
    iconic empty-sea filler ("here be monsters").
  - **Ships** — cogs, galleons, longships — sailing the seas along trade routes;
    they also imply the map's era and cultures.
  - **"Here be dragons" / cartouche captions** — hand-lettered warnings in
    unexplored regions; a dragon or beast vignette over terra incognita.
  - **Heraldry / banners / shields** marking the seat of each realm or region;
    color-codes political geography and adds authenticity.
  - **Vignettes** — a small castle drawing by the capital, a tiny ship by a port,
    figures in Baynes's illustrated-border tradition.
- **Distance-fade / terra incognita.** Toward the map's edges or unexplored zones,
  *reduce* detail and saturation — fade to bare parchment, sketchier line, "unknown"
  labels. This both frames the known world and provides believable negative space. It
  is a compositional *feature*, not a lack of content.

**Discipline:** the decorative program must share the map's *one idiom* (Law 2). A
crisp vector compass on a loose ink-wash map, or a photo-real dragon on a flat
symbolic map, breaks the forgery instantly.

---

## PART 4 — COMPETITOR HOUSE STYLES: STUDY, PARITY BAR, EXCEED

Parity is the **floor**. For each competitor: what they nail, then the specific bar
our output must clear side-by-side at the same scale (per CRITIQUE_CHECKLIST). Study
the linked examples with your own eyes before judging ours.

### 4.1 Wonderdraft (Megasploot) — *our floor for region/world maps*

**What they do well.** The definitive *hand-inked region map* idiom in software:
tasteful theme/palette system for a cohesive aged look; **symbol brushes** that paint
matched mountains/trees/settlements from a single coherent set; automatic **coastal
shadow/echo**; layered structure (water, land, paths, symbols, regions, labels,
overlay); easy landmass generation (continent/archipelago templates) plus path tools
for roads, borders, trade routes; biome theming (desert/tundra/grassland/forest
textures). The output reads *drawn*, *restrained*, and *cohesive* — the whole
CartographyAssets ecosystem exists to feed it. ([Wonderdraft](https://www.wonderdraft.net/),
[map-making software review](https://www.legendkeeper.com/map-making-software/))

**Our parity bar.** A region/world render must match Wonderdraft on: single coherent
symbol idiom, automatic coastal echo, believable ranges walked along spines, forests
belting foothills/coasts, roads following valleys, sparse landmarks, and *visible open
parchment*. If ours looks busier or more uniform than a good Wonderdraft map, we've
failed the floor.

**How we exceed.** Generated + restylable symbol sets (not a fixed library), Font
Studio faces for labels, one-click stable-ID theme swap that re-skins the whole map
live, AI-assisted placement that respects biome logic, and direct VTT hand-off.

### 4.2 Inkarnate — *our bar for library depth + style range*

**What they do well.** *Breadth.* Thousands of categorized stamps and multiple
distinct styles under one roof — Fantasy Regional (65+ high-impact effect stamps),
Watercolor Cities, Fantasy Battlemaps (2,200+ asset revisions across Castle/Dungeon/
Camp/Tavern packs), plus world, regional, and city registers. One tool spans
world→region→city→battlemap. The sheer categorized symbol vocabulary is the benchmark.
([Inkarnate updates](https://inkarnate.com/updates), [Inkarnate PRO review](https://dungeongoblin.com/blog/inkarnate-pro-review-2021))

**Our parity bar.** A *deep, categorized* symbol library (our stated target: 120+
core, growing toward Inkarnate breadth — CRITIQUE_CHECKLIST #12) AND **more than one
credible style** (see Part 5 recipes). A dozen stamps in one style is not parity.

**How we exceed.** We *generate and quantize* new symbols on demand via the
[image-pipeline](../image-pipeline/SKILL.md) against a transparent scaffold, so the
library isn't a fixed catalog — it grows to the map's needs while staying in one
idiom. Every symbol is stable-ID bound and license-tracked ([credits](../credits/SKILL.md)).

### 4.3 Dungeondraft (Megasploot) — *our bar for battlemaps*

**What they do well.** Purpose-built **VTT battlemap** detail: multi-layered terrain
brushes that blend textures (sand/dirt/grass), water tools, walls, an object/scatter
tool (randomized rotation+scale clutter), path tool (roads/rivers/fences with smooth
curves), and **dynamic lighting** — colored, flickering light sources that interact
with walls to cast shadows. Crucially, it **exports wall + light data** straight to
Foundry/Roll20/Fantasy Grounds at grid scale. ([Dungeondraft guide](https://groupfinder.eu/library/dungeondraft),
[Dungeondraft basics](https://encounterlibrary.com/dungeondraft-basics/))

**Our parity bar.** Battlemaps (handled in [MAP_TYPES.md](MAP_TYPES.md) + the
`battleMap.ts` renderer) must deliver: tiled/blended terrain, walls + objects + a
scatter/clutter tool, per-grid export, and lighting with wall-aware shadows —
importantly with **exportable wall/light metadata** for VTT play, not just a flat
image.

**How we exceed.** Native integration into *our own* narrative VTT (no export round-
trip), AI-assisted room/dungeon authoring, and stable-ID assets shared with region
maps so a "castle" symbol and its battlemap interior come from one manifest.

### 4.4 Azgaar's Fantasy Map Generator — *our bar for generation + simulation depth*

**What they do well.** Procedural *world simulation*: heightmap/tectonics → precip/
temperature/climate → rivers by flux+elevation → biomes → **cultures, states,
provinces, burgs (settlements w/ population & economy), religions, routes, military,
markers, emblems/heraldry** — all fully editable, all internally consistent, exportable
(SVG/PNG/JSON/GeoJSON). It's the depth benchmark: the world *makes sense* because it's
simulated, not scattered. ([Azgaar's FMG](https://azgaar.github.io/Fantasy-Map-Generator/),
[Quick Start](https://github.com/Azgaar/Fantasy-Map-Generator/wiki/Quick-Start-Tutorial))

**Our parity bar.** Generation must be *causal*, not decorative: elevation → watersheds
→ rivers (high→sea, never splitting downhill) → moisture/latitude biomes → settlements
at water/passes → roads connecting them. That pipeline (our TERRAIN_AND_BIOMES model)
is what earns believable geography. Azgaar's editability (regenerate any layer) is the
interaction bar.

**How we exceed.** Azgaar's *renders* are functional/schematic; ours pair its
simulation depth with the **hand-drawn ink-and-wash finish** above — the causal world
AND the beautiful sheet, which no single competitor delivers together. Plus AI-authored
lore/names bound to the same entities.

### 4.5 Others worth knowing (scan, borrow, don't reinvent)

- **Watabou (procedural generators)** — Medieval Fantasy City Generator, Village,
  One Page Dungeon, Neighborhood. Instant plausible *city/village/dungeon plans* with
  a clean stylized line look; great for the *layout* substrate under a city map. Study
  for street-network realism.
- **Campaign Cartographer / CC3+ (ProFantasy)** — the veteran CAD-style mapper; deep,
  powerful, steep learning curve; huge symbol catalogs and annuals. The "old pro"
  reference for symbol breadth and map types.
- **MapForge (Battlebards/Lord Zsezse)** — battlemap-focused stamp compositor;
  reference for pre-drawn map-tile assembly.
- **Worldographer (formerly Hexographer)** — hex/atlas-style world+region+battlemap
  with a distinctive old-school hex aesthetic; reference for the **hex campaign map**
  register and TSR-lineage look.
- **Take from each:** Watabou's layout logic, CC3+'s symbol taxonomy, Worldographer's
  hex register. None of them combine simulation + hand-drawn finish + live asset swap
  + AI authoring + native VTT — that combination is our lane.

---

## PART 5 — STYLE RECIPES WE SHIP

Concrete, pipeline-ready. Each names a palette, line treatment, symbol set, furniture,
and the **pro-vs-amateur tells**. Symbols come from [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md);
placement logic from [TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md); compositing from
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md). Sci-fi/star and modern/transit styles
are catalogued in [MAP_TYPES.md](MAP_TYPES.md).

### Recipe 1 — Parchment Fantasy Region (the Wonderdraft/Tolkien idiom) — DEFAULT

The house default and our floor. Warm, inked, restrained, cohesive.

- **Palette:** parchment ground `#EAD9B0`; sepia ink `#4A3423`; forest wash `#8A9A5B`;
  plains dun `#C8B27E`; mountain grey-violet `#8B8390`; water teal `#6E93A0` (deeper
  offshore); vermilion accent `#A4342B` for capitals/borders. 5–6 colors total.
- **Line treatment:** variable-weight sepia; heavy coastline with **3–4 coastal echo
  lines** fading seaward; tapering rivers (thick mouth → hairline source); light-from-
  NW shading on all relief.
- **Symbol set:** side-view pictorial mountains (aerial-perspective range), coniferous/
  deciduous tree clusters in belts, walled-town / keep / village settlement tiers,
  ruins/tower/bridge/port POIs; 3–6 variants each, jittered.
- **Furniture:** ornamental cartouche in an open sea corner; 16-point compass rose;
  league scale bar; decorative ruled+vine border; 1–2 sea monsters and a ship in the
  open ocean; region heraldry optional.
- **Pro tells:** open parchment interior; ranges on spines with foothill taper; forests
  belting coasts/foothills; sparse intentional POIs; one light direction; global paper
  pass. **Amateur tells to kill:** stamp carpet; identical clones in a grid; flat blue
  ocean; two mountain styles fighting; label overlap; pure-black ink; flat-gradient
  "parchment."

### Recipe 2 — Cartographer's Blueprint / Ink Line

Line-only, no color wash — the "working reference" / engraving / draftsman register.
Doubles as a sci-fi *technical* base (see MAP_TYPES) when recolored cyan-on-navy.

- **Palette (fantasy engraving):** cream/ivory ground `#F2E8D0`; single dark sepia or
  near-black warm ink `#33281B`; NO color washes — tone comes entirely from line
  density. (Sci-fi variant: `#0B1E33` ground, `#7FC7E8` cyan line, thin white grid.)
- **Line treatment:** disciplined, engraving-like; tone built from **hatching,
  cross-hatching, stippling, and hachures** rather than wash; consistent hachure
  direction downslope; fine graticule/grid optional.
- **Symbol set:** finely-lined pictorial relief (hachured ranges), stippled deserts,
  hatched forests as texture masses, precise settlement glyphs, thin uniform roads.
- **Furniture:** ruled neatline with coordinate ticks; plain-but-precise compass;
  scale bar with fine ticks; a restrained engraved cartouche; minimal marginalia (the
  austerity IS the style).
- **Pro tells:** tonal control through line density alone; even, confident hatching;
  crisp hierarchy without color. **Amateur tells:** muddy/uneven hatching; using a grey
  fill instead of actual line texture; inconsistent hachure direction; over-decoration
  (this style is austere).

### Recipe 3 — LotR Topographical (Christopher Tolkien register)

The authoritative black-ink-on-cream book-plate look; slightly cooler and cleaner than
Recipe 1, minimal color, maximal legibility. The "epic fantasy frontispiece."

- **Palette:** cool cream `#EDE6D2`; near-black warm ink `#241E17`; *very* restrained
  washes — pale green forest, faint grey mountains, muted blue-grey water; no bright
  accents. Almost monochrome.
- **Line treatment:** firm confident coastline; molehill/side-view mountain ranges
  walked along spines (the Misty-Mountains look); hatched or short-stroke forests;
  rivers as clean tapering lines; sparse coastal echo.
- **Symbol set:** the classic minimal vocabulary — pictorial mountain ranges, forest
  stipple/stroke clusters, dot+name settlements, a few named landmarks. Deliberately
  *small* symbol set; power comes from restraint and labeling.
- **Furniture:** understated titled cartouche; simple compass; scale in leagues; clean
  ruled border; hand-lettered *look* labels (curved along ranges/rivers, wide-spaced
  region names). Little-to-no monster marginalia — dignity over decoration.
- **Pro tells:** enormous legible open space; authoritative label typography carrying
  the map; ranges reading as continuous walked masses. **Amateur tells:** clutter
  (this register lives on emptiness); modern/vector cleanliness that kills the
  hand-drawn warmth (the HarperCollins mistake); over-saturated washes.

### Style-selection note

Type + audience picks the recipe: art/lore world map → Recipe 1; technical/sci-fi or
"survey" → Recipe 2; epic-fantasy book frontispiece → Recipe 3; VTT play surface →
battlemap (MAP_TYPES); procedural depth → drive any recipe with the Azgaar-grade
causal pipeline. Never mix two recipes on one sheet (Law 2).

---

## PART 6 — PARITY-THEN-EXCEED: OUR EDGE

Matching the competitors on their own turf is the *floor*, enforced by
[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) (side-by-side, same scale, ≥3 seeds,
own eyes). What we add *on top* — the reasons Map Studio is more than a Wonderdraft
clone:

1. **Programmed-game polish.** Real compositing discipline — pooled base-shadows, one
   global paper pass, consistent light, collision-avoided labels — so every render is
   a finished *sheet*, not an editor screenshot. (RENDERING_PIPELINE.)
2. **Generated art + fonts.** Symbols and textures generated/restyled on demand via
   the [image-pipeline](../image-pipeline/SKILL.md), and labels set in bespoke
   [Font Studio](../typography/SKILL.md) faces — the library and the type grow to the
   map instead of being a fixed catalog.
3. **Stable-ID live swap.** Every symbol, texture, and font binds by stable ID through
   the [asset-manifest](../asset-manifest/SKILL.md); Jesus can drop-in/replace any of
   them once and every map + template updates. No competitor offers this.
4. **AI-assisted authoring.** Names, lore, region descriptions, and placement
   suggestions generated *consistently with the simulated world* and bound to the same
   entities — Azgaar depth with narrative on top.
5. **Native VTT integration.** Maps and battlemaps flow straight into our narrative
   Virtual Tabletop (the north star) with wall/light/entity metadata — no export round-
   trip, symbols shared between the region map and the battlemap interior.

**The mandate (per SKILL.md + STUDIO CLAUDE.md):** hit each competitor's bar *first*,
prove it with the critique gate, *then* layer our edge. Parity is not the goal — it's
the price of admission. A render that only matches Wonderdraft but skips our polish,
generation, and integration hasn't exceeded anything; a render that claims to exceed
while failing restraint or coherent-idiom parity is the P9 mistake again.

---

## See also
- [SKILL.md](SKILL.md) — the Ten Laws and the build pipeline (read first).
- [REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md) — projection, relief theory, figure-ground,
  map typography (the discipline behind the idiom).
- [TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md) — where features physically belong
  (the restraint/placement model).
- [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) — designing the symbol library the
  recipes draw from.
- [MAP_TYPES.md](MAP_TYPES.md) — per-type conventions incl. sci-fi/star, nautical,
  subway/transit, battlemap.
- [RENDERING_PIPELINE.md](RENDERING_PIPELINE.md) — layer stack, base-shadow pooling,
  global paper pass, label placement, seeds.
- [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) — the acceptance gate every render
  must pass.
