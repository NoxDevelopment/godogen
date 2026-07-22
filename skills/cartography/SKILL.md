---
name: cartography
description: The complete craft of making maps — real-world cartography (projection, relief, generalization, map-design, color, map typography) AND fantasy/game map-making (parchment region maps, world maps, city maps, VTT battlemaps, dungeon maps, nautical/star/subway maps) at Wonderdraft/Inkarnate/Dungeondraft/Azgaar/Tolkien parity and beyond. Use whenever building or upgrading Map Studio, generating any map, placing terrain/symbols/labels, or judging a map's quality. This is the knowledge the map pipeline must dogfood BEFORE placing a single stamp.
---

# Cartography — a map is a designed argument about a place, not a scatter of sprites

**The failure mode this skill exists to kill:** carpeting a landmass wall-to-wall with near-identical terrain stamps, calling the result a "map," judging it on one lucky seed, and letting the generator's own write-up stand in for craft. Real maps — and the tools that make them (Wonderdraft, Inkarnate, Dungeondraft, Azgaar, and the hand-inked Tolkien/Baynes lineage) — win on **restraint, hierarchy, coherent idiom, biome logic, a deep symbol library, and honest label placement.** Density is not detail. Open ground is a feature.

If you are placing features on a map and you have not internalized the **Ten Laws** below and the relevant reference doc, stop and read first. Then build.

## Reference docs (progressive disclosure — read the one you need)
- **[MAP_REFERENCE_GALLERY.md](MAP_REFERENCE_GALLERY.md)** — grounded exemplars + implementable specs: Tolkien/Baynes/Christopher Tolkien, Fonstad's *Atlas of Middle-earth*, classic RPG atlases; the exact **label/lettering** rules (offset ladder, drop-first-letter small-caps, italic water, hierarchy, halo/collision — the fix for "text all over the place"), **river** taper/meander/echo-line technique, **hachure/relief** depth lines, and **book-plate presentation/framing**. Each with a "so-what for our renderer" spec. Start here when overhauling how the map *looks*.
- **[BATTLEMAP_ASSETS.md](BATTLEMAP_ASSETS.md)** — tactical-scale asset library: the Dungeondraft/Inkarnate/Fantasy Grounds/Roll20 battlemap stamp system, top-down architectural drawing conventions (wall poché, door swing arcs, window breaks, stairs), and the full battlemap asset category tree with counts (terrain/floors, walls/structure, furniture, dungeon dressing, nature, effects/overlays).
- **[VTT_TOOLING_GAPS.md](VTT_TOOLING_GAPS.md)** — d20/VTT tooling scan: what d20PRO, Fantasy Grounds, Roll20, and Foundry ship (dynamic lighting/LoS, fog of war, initiative/combat tracker, sheet automation, dice/macros, compendium, measurement/templates, decks/handouts, audio) vs what our Studio has — the gap list for the narrative VTT.
- **[REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md)** — the actual discipline: projections & distortion, scale & generalization, relief depiction (hachures, contours, hypsometric tint, shaded relief, illuminated relief), the visual hierarchy / figure-ground / map-design canon (Bertin, Tufte, Brewer, MacEachren, Imhof), map color theory, and map typography (label placement rules, Imhof's lettering principles).
- **[TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md)** — geomorphology for believable worlds: how mountains, ridgelines, watersheds, rivers, lakes, coastlines, and biomes actually form, and the **density/restraint + biome placement model** that replaces "stamp every cell." This is the fix for our jumble.
- **[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md)** — the hand-drawn idiom: the Tolkien/Pauline Baynes lineage, the Wonderdraft/Inkarnate/Dungeondraft/Azgaar house styles, ink-and-wash technique, the "aged sheet" look, decorative apparatus (cartouche, compass rose, sea monsters, ships, borders), and how to hit each competitor's bar then exceed it.
- **[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md)** — designing a real symbol library: the full category tree (relief, vegetation, settlements, structures, POIs, hazards, décor, nautical), the ~120+ core set and beyond, single-idiom consistency, light-direction discipline, transparent-scaffold generation via our image pipeline, chopping/quantizing.
- **[MAP_TYPES.md](MAP_TYPES.md)** — the catalog: world/continent, region/kingdom, city/town, VTT battlemap, dungeon, political, topographic, nautical/portolan, star/sector, subway/transit, weather/thematic — each with purpose, conventions, must-haves, and reference exemplars.
- **[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)** — our implementation: the Map Studio layer stack, base-shadow pooling, global paper pass, label-placement algorithm, seed handling, and how the pieces map onto `apps/web/lib/actions/mapStudio.ts` / `battleMap.ts` / `mapStampAssets.ts`.
- **[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md)** — the acceptance gate. No map render earns "clears the bar," ships to the showcase, or gets swapped into a template until it passes this rubric across multiple seeds, side-by-side with the competitor at the same scale.

## The Ten Laws of map craft (memorize these)

1. **Restraint beats density.** Most of a good map is open ground — parchment, plains, sea. Features are placed *sparingly and intentionally*. Wall-to-wall stamps is the #1 amateur tell. If you can't see the paper, you've failed.
2. **One coherent idiom.** Every relief symbol, every tree, every settlement is drawn in the *same* visual language, palette, and line weight. Mixing soft-brown lumps with sharp-grey peaks (two styles fighting) is instantly amateur. Pick one; apply it everywhere.
3. **Visual hierarchy.** The eye must know what matters: title > major landmarks > ranges/coasts > minor features > texture. Achieve it with size, weight, contrast, and *negative space* — not by making everything loud.
4. **Figure–ground.** Land must read cleanly as figure against water/void as ground (coastal echo lines, a subtle land tint, a vignette). Ambiguity here reads as broken.
5. **Geography must be believable.** Mountains form ranges along a spine; rivers flow downhill from high ground to the sea and never split going downstream (except deltas); forests belt the foothills and coasts; deserts sit in rain shadows. Placement follows physical logic (see TERRAIN_AND_BIOMES). Random scatter looks random.
6. **Biome variety, not one fill.** Plains, forest, marsh, desert, tundra, badlands — differentiated by fill, texture, and symbol set. A single tan landmass covered in bumps is not a world.
7. **Landmarks carry the story.** Castles, towers, ruins, ports, bridges, ships, sea-beasts, mines, temples, battlefields — the POI layer is what turns terrain into a *place people care about*. A map with no POIs is a heightmap.
8. **Labels are typography, placed by rules.** Curve settlement/region names along features, never overlap them with symbols, use a type hierarchy (world > region > city > feature), letterspace region names wide, and follow Imhof's lettering principles (see REAL_CARTOGRAPHY). Hand-lettered *look* is achieved by smart snapping + good faces, not literal handwriting.
9. **The sheet is one object.** Consistent light direction across every symbol, a pooled ground-shadow so a range grounds as one raised mass, and a global paper/aging pass that fuses all layers into a single aged sheet — not N pasted sprites.
10. **Prove it, don't claim it.** Judge across multiple seeds, in the live editor, at a user's zoom, side-by-side with the competitor at the same scale, with your own eyes. Green tests and a generator's self-report are not evidence of quality (CRITIQUE_CHECKLIST).

## Reuse-first (STANDARDS — same ladder as every asset)
Before generating any map symbol or texture, climb the [asset-reuse](../asset-reuse/SKILL.md) ladder: **stable-ID manifest → owned/CC0 cartography kit → derive/restyle an owned symbol → generate LAST** via the [image-pipeline](../image-pipeline/SKILL.md). We own large asset bundles (NAS `\\DXP4800PLUS-A79\NoxDev`) and font packs — check `pieces/asset-kits/_library/BY_THEME.md` for map/cartography/terrain kits first. Record every symbol's license for [credits](../credits/SKILL.md). Bind every symbol/texture by **stable ID** through the Studio manifest ([asset-manifest](../asset-manifest/SKILL.md)) so Jesus can drop-in/replace it live. Map labels use [typography](../typography/SKILL.md) faces (Cinzel/UncialAntiqua for fantasy, condensed serif for topographic) — never the engine default.

## The build pipeline (how to actually make a map)
1. **Choose the map TYPE and STYLE** (MAP_TYPES + FANTASY_CARTOGRAPHY / a real style). Type dictates conventions; style dictates idiom.
2. **Generate/lay the base geography** — landmass + coastline, then the **elevation/heightfield**, then derive watersheds → rivers → lakes, then **biomes from elevation+moisture+latitude** (TERRAIN_AND_BIOMES). This produces *where features belong and where the map breathes*.
3. **Place relief by structure, not per-cell** — extract ridgelines from the massif mask, walk peaks along the spine (tallest on crest, tapering to foothills), leave valleys and plains open.
4. **Place vegetation/biome symbols sparsely** in their belts with scale/spacing variance (never a uniform carpet).
5. **Place settlements + roads + POIs** — settlements near water/passes, roads connecting them along valleys, POIs as narrative anchors.
6. **Composite the sheet** — layer order, pooled base-shadow, one light direction, global paper pass (RENDERING_PIPELINE).
7. **Label** — hierarchy, curved on features, collision-avoided (REAL_CARTOGRAPHY label rules).
8. **Decorate** — cartouche, compass rose, scale bar, legend, border, and tasteful marginalia (sea-beasts/ships) appropriate to the style.
9. **Grade against CRITIQUE_CHECKLIST across ≥3 seeds + a competitor side-by-side** before it counts as done.

## Competitor bar (what "parity then exceed" means)
- **Wonderdraft** — the hand-inked region-map benchmark: restraint, cohesive symbols, coastal echo, believable ranges/forests, landmarks, roads. *Our floor for region/world maps.*
- **Inkarnate** — breadth: thousands of categorized symbols, multiple styles, city + battlemap + region in one tool. *Our bar for library depth.*
- **Dungeondraft** — VTT battlemap detail: tiled terrain, walls, objects, lighting, export at grid scale. *Our bar for battlemaps.*
- **Azgaar's Fantasy Map Generator** — procedural world depth: tectonics, climate, rivers, cultures, states, burgs, routes, religions, markers — all editable. *Our bar for generation + simulation depth.*
- **DungeonFog** — battlemap *editor workflow*: room-vector drawing with auto walls/corridors, multi-level floors, per-room GM notes → PDF, VTT/Foundry export. *Our bar for the battlemap editor loop + interop.*
- **Worldborn** (fantasymapassets.com) — the *interactive explorable map* class: clickable lore zones, sounds, map-in-map overlays, read-only web publishing. *Deferred bar (per Jesus) — reached via Worldbuilder map pins + the publish spine, not built now.*
- **Our EDGE:** programmed-game polish, generated art/fonts (image + Font Studio), stable-ID live asset swap, AI-assisted authoring, and integration into the narrative VTT. Parity is the floor, not the goal.

## Integration (this is a Studio system, per centralization)
Map Studio is the centralized cartography area; games/templates and the VTT consume its output and symbols by **stable ID** (swap once → updates everywhere). The battlemap renderer is the VTT tabletop layer. Keep this skill and its reference docs the single source of map-craft truth that the Map Studio pipeline and every map-generating agent dogfood.
