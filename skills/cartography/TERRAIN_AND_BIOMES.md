# Terrain & Biomes — the geomorphology behind a believable map, and the placement model that kills the stamp carpet

> Part of the **[cartography](SKILL.md)** skill. Read **[SKILL.md](SKILL.md)** first — this doc is the concrete fix for the failure that skill names in its opening line: *"carpeting a landmass wall-to-wall with near-identical terrain stamps."* Siblings: **[REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md)** (the discipline, relief depiction, hierarchy) · **[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md)** (the hand-drawn idiom) · **[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md)** (the symbol library the placement model draws from) · **[MAP_TYPES.md](MAP_TYPES.md)** (which conventions apply per map type) · **[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)** (how the layer stack composites what this model decides) · **[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md)** (the gate every render must clear).

**The one-sentence thesis.** A believable map is not a canvas you fill; it is the *visible output of a physical process*. Mountains, rivers, forests, and towns sit where geology, water, and climate put them — and 70–90% of the sheet is **open ground** because that is what the real world looks like from above. When you place features by imitating the process instead of scattering sprites per-cell, restraint and coherence come for free. This document gives you (a) enough earth science to place landforms believably, and (b) a **seven-stage placement model** with density/restraint rules and pseudocode that replaces "stamp every land cell."

**Reading contract for the generator.** Every "🧭 so-what" callout is a directive for our Map Studio pipeline (`apps/web/lib/actions/mapStudio.ts`, `battleMap.ts`, `mapStampAssets.ts` — see [RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)). If your code violates a so-what, it is a bug regardless of what the render looks like on one seed.

---

## Part I — How landforms actually form (enough geology to place them right)

You do not need a geology degree; you need the *shapes* the processes produce and the *rules* those shapes obey, so your placement never contradicts them.

### 1. Plate tectonics — the source of nearly all big relief

Earth's crust is broken into rigid **plates** that move a few cm/year over the ductile mantle. Almost every large landform traces back to what happens at a plate **boundary**:

- **Convergent boundaries (collision / subduction)** → the world's great mountain ranges. Continent–continent collision crumples crust upward (Himalaya, Alps); ocean–continent subduction builds volcanic arcs along the coast (Andes, Cascades). **The defining trait: ranges are LINEAR.** They run in long arcs and belts *parallel to the boundary*, with a continuous **spine** (the main divide), foothills tapering off both flanks, and often a **parallel second range** (fore-arc / back-arc). They are never a random blob of scattered peaks.
- **Divergent boundaries (spreading / rifting)** → **rift valleys** (East African Rift, the Rhine Graben): a long, straight, steep-walled *depression* where crust is pulling apart, frequently strung with long narrow lakes and volcanoes along its length. On land a rift reads as a linear *lowland flanked by escarpments*, the inverse of a range.
- **Transform boundaries (sliding)** → **fault lines** (San Andreas): long, remarkably straight lineaments. Rivers and valleys often jog or offset along them; they rarely make tall relief by themselves but they *organize* drainage and can dam it into sag ponds.

**Young vs. old mountains — the single most useful distinction for drawing relief:**

| | Young / active | Old / eroded |
|---|---|---|
| Examples | Himalaya, Alps, Andes | Appalachians, Urals, Scottish Highlands |
| Profile | **Sharp**, jagged, high, glaciated horns & arêtes | **Rounded**, low, smooth, worn |
| Peaks | Tall, close-packed, snow/rock | Subdued ridges, soil & forest to the top |
| Valleys | Deep, steep, V- or U-shaped (glacial) | Broad, mature, gentle |
| Symbol idiom | Sharp grey/white peaks, hard shadow | Soft brown-green humps, gentle shading |

> 🧭 **so-what:** Pick young **or** old for a given range and commit — a range's peaks must share ONE idiom (Law #2). Mixing sharp glaciated horns with soft rounded lumps *in the same range* is the amateur "two styles fighting" tell called out in the skill. Age can vary *between* ranges on a world map (a young coastal cordillera + an old interior massif is realistic and adds variety — Law #6), but never *within* one massif.

### 2. Volcanism & hotspots

- **Arc volcanoes** sit in a line along subduction zones (the "Ring of Fire") — place them *on or just behind the range spine*, not randomly.
- **Hotspots** (Hawaii, Yellowstone) punch through the middle of a plate and, because the plate drifts over the fixed plume, leave a **chain of volcanoes/islands** that ages along its length (one active end, extinct + eroding toward the other). A lone volcano is fine; a *straight evenly-spaced island chain* is the hotspot signature and looks deliberate and real.
- A single stratovolcano is a near-perfect **cone with radial drainage** (see §5) and is a classic map landmark.

### 3. Plateaus, escarpments, mesas

A **plateau** is a large elevated area of *relatively flat top* bounded by steep edges (**escarpments**) — Colorado Plateau, Deccan, Ethiopian Highlands. It reads as a raised *table*, not peaks. Erosion dissects a plateau's edge into **mesas → buttes → spires** (badlands / canyon country). Rivers cut deep **canyons** into plateaus (the plateau is high but flat, so the river incises rather than meanders).

> 🧭 **so-what:** A plateau biome is *high elevation + low local relief*. Do not stamp peaks on it. Draw a flat elevated fill with a hard escarpment edge (echo/cliff line) and canyon incisions. This is a distinct terrain from "mountains" and gives you cheap variety.

### 4. Erosion — the sculptor that makes everything look "settled"

Uplift builds relief; **erosion** (water, ice, wind, gravity) tears it down, and the *balance* of the two is what a landscape "looks like." The takeaways for placement:

- Water is the dominant agent: it carves valleys, moves sediment downhill, and deposits it in **floodplains, alluvial fans, and deltas**.
- Relief **decreases with age** (young = sharp, old = rounded — §1).
- **Everything drains.** There is no high ground without a valley leading water away from it. This is why per-cell random relief looks broken: real relief is *organized by drainage*.

---

## Part II — Ridgelines & drainage (the skeleton the whole map hangs on)

Get water right and the map instantly reads as real; get it wrong and no amount of pretty stamps saves it. This is the section our generator most often violates.

### 5. Watersheds, divides, and ridgelines

- A **drainage basin (watershed)** is all the land that drains to one outlet. **Drainage divides** are the high lines separating basins — and the continental-scale one is the **continental divide**.
- A **ridgeline** is a divide: the locus of *local maxima* connecting peaks. Peaks are the high points *along* a ridgeline; the ridge is the crest that links them and sheds water to both sides.
- **Relationship to peaks:** peaks sit ON the ridgeline like beads on a string; the tallest cluster near the main spine and taper toward the flanks. This is the geometric fact behind "walk relief along ridgelines, don't scatter it per-cell."

**Drainage patterns (the plan-view shape of a river network) — and what each reveals:**

| Pattern | Looks like | Forms where | Read as |
|---|---|---|---|
| **Dendritic** | Tree / branching veins, tributaries join at acute angles | Uniform, flat-lying, homogeneous rock (the *default* — most common) | Ordinary bedrock/sediment |
| **Trellis** | Ladder — long parallel main streams, short right-angle tributaries | Folded/tilted alternating hard-soft strata (ridge-and-valley) | Folded mountains |
| **Radial** | Spokes out from a center | Isolated peak / volcano / dome | A cone or dome |
| **Rectangular** | Right-angle bends | Jointed / faulted bedrock | Faulting/jointing |
| **Parallel** | Evenly-spaced sub-parallel streams | Steep uniform regional slope | A tilted plain/coastal ramp |
| **Centripetal / endorheic** | Streams flow INWARD to a low center | Closed interior basin | A basin with no sea outlet (→ salt lake/playa) |

> 🧭 **so-what:** Default to **dendritic** — it's the natural output of flow-accumulation on a noisy heightfield anyway. Use **radial** around any volcano/dome stamp and **centripetal** for endorheic basins. Trellis/rectangular are advanced flavor; only attempt them if your heightfield actually encodes fold/fault structure, otherwise they'll look arbitrary.

### 6. River laws (violate ANY of these and the map is broken)

These are non-negotiable physical constraints. They are also the checklist [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) uses to fail a river.

1. **Water flows downhill, monotonically.** A river's elevation only ever decreases (or stays level in a lake) from source to mouth. Never route a river uphill or over a ridge.
2. **Tributaries JOIN going downstream.** Rivers **merge** as they descend — discharge only *grows* downstream. A river does **not** split/branch going downstream. The single exception is a **delta or distributary** at the mouth, where a river fans into multiple channels across its own sediment as it meets standing water. (Anastomosing/braided channels on a very flat aggrading floodplain are a niche exception — don't generate them unless deliberate.)
3. **Sources are in high ground.** Rivers start at springs/snowmelt/lakes high in the terrain (near ridgelines) and **grow** as they collect tributaries.
4. **Every river ends** at the **sea**, or at an **endorheic lake** (interior basin with no outlet — the water leaves only by evaporation, e.g. Caspian, Great Salt Lake, Dead Sea). A river that just *stops* in open terrain is a bug.
5. **Confluence angle points downstream.** Tributaries meet the main stem at an acute "Y" opening downstream, never a "T" or an upstream-pointing fork.
6. **Meanders & floodplains on low gradients.** Where the land flattens (lower course), a river stops cutting down and starts **meandering** — sinuous loops across a flat **floodplain**. Tight loops pinch off into **oxbow lakes**. Wider valley, sinuous single channel = mature river.
7. **Waterfalls & rapids at hard/soft rock boundaries** (a **nickpoint**): where a resistant band meets softer rock the softer rock erodes back, leaving a step. Falls also occur at glacial **hanging valleys** and plateau/escarpment edges. Good place for a landmark.
8. **Width scales with discharge (Strahler order).** A river is thin at its source and widest at its mouth. Render stroke width as a function of accumulated flow — a uniform-width river reads fake.

> 🧭 **so-what:** Do NOT author rivers by hand-drawing squiggles. **Derive** them from the heightfield via flow accumulation (Part V, stage 4). That single change makes laws 1–5 and 8 automatic. Then post-process: add meanders in low-gradient reaches (law 6), a nickpoint symbol where a river crosses a relief/rock boundary (law 7), and a delta fan where a large river meets the sea (law 2 exception).

---

## Part III — Coastlines

### 7. Why coasts are fractal, and why straight coasts look fake

Coastlines are **fractal** — statistically self-similar, crenellated at every scale (the "coastline paradox": measured length grows as your ruler shrinks). A coast is the *intersection of an irregular heightfield with sea level*, so it inherits the terrain's roughness. A smooth arc or a ruler-straight edge signals "no process generated this" — the single fastest way to make a landmass look fake.

**The vocabulary of a real coast (place these deliberately):**

- **Headlands & bays:** hard rock juts out as **headlands/capes/promontories**; soft rock erodes back into **bays/coves**. Alternating hard-soft coast → a scalloped rhythm. Erosion detail: sea cliffs, stacks, arches on the exposed headlands.
- **Fjords:** long, deep, steep-walled, *straight-ish* inlets — **drowned glacial valleys** (Norway, Chile, New Zealand). Only on formerly-glaciated (high-latitude or high-alt) coasts. A cluster of parallel fjords is gorgeous and reads instantly as "cold, mountainous coast."
- **Rias / estuaries:** **drowned river valleys** — a dendritic, branching, funnel-shaped tidal inlet at a river mouth (opposite feel from a fjord: branchy, gentle). Estuary = where river meets tide, brackish, often a port site.
- **Deltas:** where a sediment-laden river meets the sea and *builds land seaward* — a fan of **distributary** channels (§6 law 2 exception). Nile (arcuate), Mississippi (bird's-foot), etc. Great river-mouth landmark and settlement site.
- **Barrier islands & lagoons:** long thin sand islands parallel to a low, sandy coast, enclosing a shallow **lagoon** (Outer Banks, Venetian lagoon). A low-energy sedimentary coastline signature.
- **Spits, tombolos, sandbars:** longshore drift builds thin sand fingers across bay mouths.

> 🧭 **so-what:** Generate the coast as the `elevation == sea_level` contour of the noisy heightfield, then **do not smooth it flat.** Add fractal detail (domain-warped noise on the coast band). Place named coastal features by *matching terrain to type*: fjords where steep glaciated relief meets sea; estuary/delta at every major river mouth; bays in low soft embayments; barrier islands off low flat coasts. See [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md) for the coastal-echo line that gives figure-ground (Law #4).

---

## Part IV — Lakes

### 8. Where lakes sit, and the outflow rule

A lake is a **basin that fills with water to its lowest rim, then overflows**. Types and where they belong:

- **Tectonic basins:** rift lakes (long, deep, straight — Baikal, Tanganyika) strung along a rift valley (§1); sag ponds along faults.
- **Glacial:** **tarns** (small, round, high in cirques below peaks), **kettle lakes**, **ribbon/finger lakes** in scoured valleys (Great Lakes, Finger Lakes, English Lake District). High-latitude/high-alt terrain is *dotted* with these.
- **Fluvial:** **oxbow lakes** on floodplains (§6 law 6); delta/floodplain ponds.
- **Volcanic:** **crater/caldera lakes** filling a volcanic vent (Crater Lake) — round, in a cone.
- **Endorheic / playa:** the terminal lake of an interior basin with **no outlet** — salty, level fluctuates, may dry to a **salt flat/playa** (§6 law 4).

**The outflow rule (a river law for lakes):**

- An **open (exorheic) lake** has ONE outlet river leaving at its lowest rim, carrying the accumulated inflow onward downhill. Many tributaries can flow *in*; one river flows *out* (occasionally more, but default to one).
- An **endorheic lake** has inflows but **no outlet** — it is a *sink*; water leaves only by evaporation, so it's salty/mineral.
- A lake sitting on a slope with no outlet and no closed basin is a **bug** — water would just drain away.

> 🧭 **so-what:** In flow routing (stage 4), when accumulated water hits a **local depression (pit/sink)**, either (a) **fill** it to its spill point and continue the outlet river downhill (open lake), or (b) if the basin is large and the climate dry, mark it **endorheic** and terminate the drainage there (salt lake/playa biome). Never emit a lake with inflow but neither an outlet nor a closed basin.

---

## Part V — Biomes & climate (what covers the ground, and why)

Relief is the skeleton; **biomes are the skin.** A world is not one tan fill (Law #6). Biome = a function of **temperature × moisture**, modulated by **latitude, altitude, and continentality**.

### 9. The Whittaker model (temperature × precipitation → biome)

Robert Whittaker's classic diagram plots **mean annual temperature** (cold→hot) against **mean annual precipitation** (dry→wet) and partitions that space into ~9 biomes. It is the single most useful mental model for map biome placement because it's *two axes you already have* (a temperature map from latitude+altitude, a moisture map from Part V §12).

Approximate Whittaker layout (T across, P up):

```
 wet │  tundra        boreal/taiga     temperate rainforest   tropical rainforest
     │  (cold+any)    (cold, moist)    (mild, very wet)       (hot, very wet)
     │                temperate forest / seasonal forest      tropical seasonal forest / savanna
     │  tundra        woodland / shrubland                    savanna
 dry │  tundra        temperate grassland / steppe            subtropical desert
     └────────────────────────────────────────────────────────────────────────
        cold ───────────────── mean annual temperature ───────────────── hot
```

Reading it: **cold** → tundra regardless of moisture. **Hot + wet** → rainforest. **Hot + dry** → desert. **Mild + moderate** → temperate forest/grassland. Precipitation decides forest vs. grassland vs. desert at a given temperature; temperature decides tundra vs. taiga vs. temperate vs. tropical at a given moisture.

> 🧭 **so-what:** This is our `biome = f(temperature, moisture)` lookup — a 2D table. Stage 6 samples temperature (from latitude+elevation) and moisture (stage 5) per region and looks up the biome.

**Köppen vs. Whittaker — when to use which.** Whittaker gives you the *vegetation/biome fill and symbol set* from two axes you already compute — that is what our placement model needs, so it is the default. **Köppen–Geiger** is the more granular real-world *climate* classification (letter codes: **A** tropical, **B** arid, **C** temperate, **D** continental, **E** polar; second/third letters add rainfall seasonality and temperature, e.g. **Af** tropical rainforest, **Aw** savanna, **BWh** hot desert, **BSk** cold steppe, **Cfb** oceanic, **Csa** Mediterranean, **Dfc** subarctic, **ET** tundra, **EF** ice cap). Reach for Köppen names only when a **topographic or thematic climate map** needs zones *labeled* ([MAP_TYPES.md](MAP_TYPES.md)); for choosing the fill/stamp, Whittaker is faster and sufficient. The two are consistent — a `BWh` cell is a Whittaker "subtropical desert," a `Dfc` cell is "taiga."

### 10. Latitude bands (the first-order temperature control)

Temperature and prevailing rainfall follow latitude in a predictable banding, driven by atmospheric circulation cells:

- **0° Equator** — hot, wet, rising air → **tropical rainforest**.
- **~15–30° (horse latitudes, descending dry air)** — the **great desert belt** (Sahara, Arabian, Kalahari, Australian, Atacama, Sonoran). *This is why most big deserts sit ~20–30° N/S, not at the equator.*
- **~30–50° temperate** — westerlies, seasonal, **temperate forest & grassland**.
- **~50–70° boreal (subpolar)** — cold, **taiga/boreal forest**.
- **70–90° polar** — **tundra** then ice.

> 🧭 **so-what:** Build the base **temperature map from latitude** (hot at the map's tropical band, cold toward its poles) *before* elevation is applied. On a small region map with no meaningful latitude spread, temperature is dominated by **altitude** instead (§11). Put deserts preferentially in the ~20–30° band AND in rain shadows (§12) — the two reinforce.

### 11. Altitude zonation (biomes stack with height like latitude)

Climbing a mountain is climatically like walking toward the pole: temperature drops **~6.5 °C per 1000 m** (the environmental lapse rate). So biomes **stack in bands with elevation**:

```
   snow / ice / rock  (nival)              ← peaks, above snowline
   alpine tundra                            ← above treeline
   ─────────── TREELINE ───────────
   subalpine conifer / krummholz
   montane forest
   foothill / submontane woodland
   valley grassland / the surrounding biome ← base
```

The **treeline** (no trees above it) is the most visually important boundary: above it, bare alpine tundra and rock; below, forest. Treeline is *lower* at higher latitudes (sea-level at the poles, ~4000 m in the tropics).

> 🧭 **so-what:** Do not fill mountains with forest to the summit. Apply elevation bands: forest belts the **foothills and lower flanks**, thins to subalpine, stops at the treeline, and the crest is **bare rock/snow**. This alone makes ranges read as real relief instead of "green bumpy blob." It also enforces Law #1: high peaks are *open* (rock/snow), not stamped with trees.

### 12. Rain shadow & orographic precipitation (the desert-maker)

When moist wind hits a mountain range it is forced up; rising air cools, condenses, and **dumps rain on the windward (upwind) side** — **orographic precipitation** (why windward coasts and slopes are the wettest places on earth, e.g. the Pacific Northwest, western Ghats). Having lost its moisture, the air descends the **leeward (downwind) side** warm and dry — the **rain shadow**, where deserts and steppe form (the Great Basin behind the Sierra/Cascades; Patagonian desert behind the Andes; the Tibetan Plateau behind the Himalaya).

```
   moist ocean wind →→→→   [ RANGE ]   →→→→ dry descending air
   WINDWARD: heavy rain,     /\/\/\      LEEWARD: rain shadow,
   lush forest              /      \     desert / steppe
   ~~~~ sea ~~~~           /  spine \    ▓▓▓ dry ▓▓▓
```

**Continentality (coastal vs. continental):** oceans buffer temperature and supply moisture, so **coasts are milder and wetter**; deep continental interiors are **drier and more extreme** (hot summers, cold winters) — which is why the world's grasslands/steppes (Great Plains, Eurasian steppe, Pampas) sit in continental interiors far from the sea, and deserts deepen inland.

> 🧭 **so-what:** Build the **moisture map** as: `moisture = base_from_latitude + proximity_to_water_bonus − rain_shadow_penalty`. Compute rain shadow by taking the **prevailing wind direction**, tracing across each range, and subtracting moisture on the lee side (and *adding* it on the windward side). This is what puts the desert in the right place instead of a random tan patch. Coasts and river valleys get a moisture bonus → that's where forests and settlements belt.

### 13. Where each biome belts (the placement crib sheet)

| Biome | Sits where | Fill / symbol idiom |
|---|---|---|
| **Ocean / sea** | Below sea level | Water tint + coastal echo, wave hatching offshore |
| **Coast / beach** | The land–sea band | Sand/dune stipple, cliffs on headlands |
| **Wetland / marsh / swamp** | Flat low ground, river deltas, lake margins, poorly-drained basins | Tussock/reed marks, blue-green, water glyphs |
| **Grassland / plains / prairie** | Continental interiors, moderate-dry, low relief — **the default open fill** | Sparse grass tufts, mostly *open* |
| **Steppe / shrubland** | Semi-arid, rain-shadow fringe, desert margins | Sparse scrub dots |
| **Temperate forest** | Mild + moist: foothills, coasts, river valleys, windward slopes | Rounded broadleaf clumps |
| **Boreal forest / taiga** | Cold subpolar, high montane | Pointed conifers |
| **Tropical rainforest / jungle** | Hot + very wet: equatorial, windward tropics | Dense dark canopy, palms |
| **Savanna** | Hot + seasonal-dry (between rainforest & desert) | Scattered lone trees on grass |
| **Desert** | ~20–30° belt + rain shadows + deep interior | Dune/rock/cracked-earth fill, near-empty |
| **Badlands / mesa** | Dissected arid plateau edges | Butte/spire stamps, striated rock |
| **Tundra** | Polar & above treeline | Mottled low fill, no trees |
| **Ice / glacier / snow** | Poles, above snowline on peaks | White, crevasse hatching |

> 🧭 **so-what:** Forests do **not** cover the world. They **belt** the moist places — foothills, coasts, river valleys, windward slopes — and *thin out* toward interiors, rain shadows, and above the treeline. Grassland/plains is the **default open fill** between features, and desert/tundra is *emptier still*. This biome differentiation (Law #6) plus the belting (not carpeting) is half the cure for the jumble.

---

## Part VI — THE PLACEMENT MODEL (the practical payoff)

This is the section that replaces "stamp every land cell." It is a **seven-stage generate-then-place pipeline**. Stages 1–6 build a *substrate* (the physical facts of the world); stage 7 places *symbols on top of that substrate, sparsely, by rule.* The stamp carpet dies because features are placed as the visible output of the substrate, not sprayed across cells.

### The anti-patterns this model exists to kill

| ❌ Anti-pattern | Why it's wrong | ✅ The fix (stage) |
|---|---|---|
| **Uniform stamp carpet** — every land cell gets a stamp | Real land is mostly open; density ≠ detail (Law #1) | Density budget + Poisson spacing; open ground is default (stage 7) |
| **Per-cell scatter** — iterate the grid, roll a die per cell, stamp | Ignores structure; produces uniform noise, not geography | Place by *structure*: relief on ridgelines, veg in belts (stages 3–7) |
| **One-tan-fill** — whole landmass a single flat color + bumps | No biome variety (Law #6) | Biome map drives fill + symbol set per region (stage 6) |
| **Peaks scattered like confetti** | Mountains form linear ranges with a spine (§1) | Walk peaks along extracted ridgelines (stage 3) |
| **Rivers as hand-drawn squiggles that split/stop/climb** | Violates river laws (§6) | Derive rivers from flow accumulation (stage 4) |
| **Grid-aligned / evenly-spaced features** | Nature isn't on a lattice; reads mechanical | Jitter + Poisson-disk spacing + scale variance (stage 7) |
| **Forest to the summit; desert as a random patch** | Ignores altitude zonation & rain shadow (§11–12) | Elevation bands + moisture-driven biomes (stages 5–6) |

### Stage 1 — Landmass + coastline

Establish where land is. Options: layered/domain-warped **value or Perlin/Simplex noise** thresholded at sea level; or plate-inspired blobs; or hand-authored mask for a fixed world. Then make the coast **fractal** (§7): warp the sea-level contour with additional octaves so it crenellates; do not leave straight edges.

```
elevation0 = fbm(x, y, octaves=6, warp=true)      # base heightfield, 0..1
sea_level  = percentile(elevation0, LAND_FRACTION)  # e.g. keep top 40% as land
land_mask  = elevation0 > sea_level
coastline  = boundary(land_mask)                    # keep it fractal — do NOT smooth
```

> 🧭 **so-what:** `LAND_FRACTION` is a restraint knob — lots of sea/void *is* open ground (Law #1). Add offshore islands sparsely, and an occasional **hotspot island chain** (§2) for a deliberate touch.

### Stage 2 — Elevation heightfield (with structure)

Turn the raw noise into believable relief by *imposing tectonic structure*, not just leaving isotropic bumps:

- Define one or more **mountain-belt spines** as *curves* (splines) — these are your convergent boundaries (§1). Raise elevation along each spine with a ridge falloff so it forms a **linear range with foothills**, tallest on the crest.
- Use **ridged multifractal noise** near spines for sharp young peaks; smooth/rounded noise for old massifs.
- Optionally carve a **rift valley** (a linear depression) or set a **plateau** (raise a region to a flat high value with a hard escarpment edge, §3).

```
for spine in mountain_belts:
    dist = distance_to_curve(x, y, spine)
    ridge = ridged_fbm(x, y) * exp(-dist / belt_width)   # linear, spined, tapering
    elevation += ridge * spine.uplift
# result: ranges are LINEAR with a spine + foothills, not scattered peaks
```

> 🧭 **so-what:** This is the difference between "a range" and "confetti peaks." The spine curve guarantees §1's linearity; the falloff guarantees foothills and open valleys between ranges.

### Stage 3 — Derive slope, ridgelines, watersheds (read the terrain you built)

From the heightfield, compute the derived layers the rest of the model needs — do not author these by hand:

- **Slope** = magnitude of the elevation gradient. Steep = relief/cliff; flat = plain/floodplain candidate.
- **Ridgelines** = crest lines: cells that are local maxima along the gradient / high curvature. These are your **divides** and the string your peaks hang on (§5).
- **Watersheds** = label each cell by which outlet it drains to (flood-fill from minima / D8 basins).

```
slope     = gradient_magnitude(elevation)
flow_dir  = D8_steepest_descent(elevation)     # each cell → its lowest neighbor
ridges    = local_maxima_along(elevation, curvature) # crest network
basins    = label_watersheds(flow_dir)
```

> 🧭 **so-what:** Relief symbols get walked along `ridges` (stage 7), not placed per-cell. `slope` gates where cliffs/escarpments draw and where floodplains/marsh can exist. `basins` tell you drainage divides so ranges separate river systems believably.

### Stage 4 — Flow accumulation → rivers → lakes

The heart of believable water. Use the standard hydrology approach (**D8 flow direction → flow accumulation → threshold**):

1. **Fill or breach pits** so water can escape local depressions (or intentionally keep large pits as lake basins — §8).
2. **Flow direction (D8):** each cell points to its steepest-descent neighbor.
3. **Flow accumulation:** for each cell, count how many upstream cells drain through it (proxy for discharge).
4. **Threshold:** cells with `accumulation > CHANNEL_THRESHOLD` are **river channels**. Higher threshold → fewer, bigger rivers (restraint knob).
5. **Trace** each channel downstream along `flow_dir`; tributaries naturally **merge** (law 2), width scales with accumulation (law 8), every channel ends at sea or a sink.
6. **Lakes:** a filled pit becomes an **open lake** with one outlet at its spill point, or an **endorheic lake/playa** if it's a large closed basin in a dry region (§8).

```
elevation  = fill_or_breach_pits(elevation, keep_basins=large_dry_pits)
flow_dir   = D8(elevation)
flow_acc   = accumulate(flow_dir)                      # upstream cell count
rivers     = trace_downstream(cells where flow_acc > CHANNEL_THRESHOLD)
for r in rivers:
    r.width = f(flow_acc_at_mouth)                     # thin source → wide mouth
    if low_gradient(r): add_meanders(r); maybe add_oxbow(r)   # law 6
    if crosses_relief_boundary(r): mark_nickpoint(r)          # waterfall — law 7
    if enters_sea(r) and r.width large: build_delta(r)        # law 2 exception
lakes = fill_basins_to_spillpoint(elevation)           # outlet or endorheic — §8
```

> 🧭 **so-what:** This one stage makes rivers obey *all* of §6 automatically — they flow downhill, merge (never split), start high, end at sea/lake, widen downstream. **Never** replace this with hand-drawn river curves; that's how split/uphill/dead-end rivers get shipped. `CHANNEL_THRESHOLD` is the restraint knob for river density.

### Stage 5 — Moisture map (distance-to-water + rain shadow)

Build the moisture field that (with temperature) decides biomes:

```
temperature = base_from_latitude(y) − LAPSE_RATE * elevation     # §10 + §11
moisture    = base_from_latitude(y)                              # wet tropics/temperate, dry ~25°
moisture   += proximity_bonus(distance_to(sea, rivers, lakes))    # §12 continentality
moisture   -= rain_shadow(prevailing_wind, ranges, elevation)     # §12: lee side dries
moisture   += orographic_bonus(prevailing_wind, windward_slopes)  # §12: windward wets
```

> 🧭 **so-what:** Rain shadow is computed by marching along the prevailing-wind direction: windward slopes gain moisture, everything downwind of a crest loses it. This is what places deserts *correctly* (lee of ranges + the ~25° belt) instead of as arbitrary tan blobs, and what makes forests belt the wet coasts/valleys/windward flanks.

### Stage 6 — Biome = f(elevation, moisture, latitude)

Sample temperature and moisture per region and look up the biome via the **Whittaker table** (§9), then override with the **altitude bands** (§11):

```
for region in regions:
    T = temperature[region]      # from latitude − lapse*elevation
    M = moisture[region]
    biome = whittaker_lookup(T, M)                 # §9 2D table
    if elevation[region] > snowline:  biome = ICE_ROCK
    elif elevation[region] > treeline: biome = ALPINE_TUNDRA
    elif high_montane(region):         biome = downgrade_forest_to_conifer(biome)
    if is_endorheic_sink(region):      biome = SALT_FLAT
    region.biome = biome
```

Each biome carries a **fill color/texture**, a **symbol set** (which vegetation/relief stamps are legal here), and a **base density** (see stage 7). Result: a differentiated world (Law #6) where every fill, texture, and symbol set matches the physics.

> 🧭 **so-what:** Biome is the *gatekeeper* for stage 7: it decides *which* symbols may appear and *how densely*. A desert region's density is near-zero; a rainforest's is high-but-still-clumped. No region gets "all symbols."

### Stage 7 — Place features sparsely, by structure, with restraint

Now — and only now — place stamps. Iterate features **by category and structure**, never per-cell, each governed by a **density budget** and **Poisson-disk spacing** (blue-noise: no two points closer than a min distance → the irregular-but-even spacing of real tree canopies, not a grid, not clumped noise).

**7a. Relief — walk the ridgelines (never per-cell):**
```
for range in ranges:
    ridge = range.ridgeline                       # from stage 3
    peaks = sample_along(ridge, spacing=poisson(min_dist), jitter=true)
    sort peaks by elevation
    place tallest/sharpest peak symbols on the CREST;
    taper to smaller foothill symbols down the flanks;
    keep valleys and passes OPEN
    # young range → sharp grey peaks; old range → soft brown humps (ONE idiom, §1)
```

**7b. Vegetation — belt it, don't carpet it:**
```
for region where biome in FORESTED:
    n = area * biome.base_density * restraint_factor   # << full coverage
    points = poisson_disk(region, min_dist = f(biome))  # blue-noise spacing
    for p in points:
        stamp tree_of(biome) with random scale (0.7..1.4) and slight rotation
    # denser toward moist valleys/coasts, thinning to edges & uphill to treeline
```

**7c. Settlements — where people actually live:**
```
score(cell) = w1*near_fresh_water(rivers,lakes,coast)   # ports, river towns
            + w2*at_confluence(rivers)                   # trade
            + w3*at_mountain_pass / valley_route
            + w4*arable_biome(grassland,temperate_forest) # farmland
            − w5*hostile_biome(desert,ice,high_alt,marsh)
capitals/cities = top-scoring cells, Poisson-spaced so they don't cluster
towns/villages  = lower threshold, more of them, still spaced
```

**7d. Roads — follow the valleys between settlements:**
```
for each pair of connected settlements:
    path = least_cost(from, to, cost = f(slope, river_crossings, biome))
    # roads hug valleys & low passes, avoid ridges/marsh, ford/bridge at narrow rivers
    draw road along path; place bridge symbol at river crossings
```

**7e. POIs — narrative anchors, deliberately few:** ruins, towers, mines, temples, battlefields, shrines — placed *sparingly* at meaningful spots (a ruin on a lone hill, a mine in the foothills, a lighthouse on a headland, a bridge at a ford). These carry the story (Law #7); a handful beats a scatter.

### The density / restraint rules (the crux — pin these to the wall)

1. **Open ground is the DEFAULT.** Start from an empty sheet and *add* features against a budget; never start full and subtract. Target **70–90% open** (parchment/plains/sea visible). If you can't see the paper, you failed (Law #1).
2. **Density is per-biome and low.** Each biome has a `base_density` << full coverage. Desert/tundra ≈ near-empty; grassland sparse tufts; forest clumped-but-gapped. Never a global uniform density.
3. **Poisson-disk / blue-noise spacing, never a grid, never pure random.** Minimum-distance spacing gives the "irregular but even" look of nature; a lattice reads mechanical, pure per-cell random reads clumpy/noisy.
4. **Scale + rotation + palette variance** on every stamp (e.g. ±30–40% scale, small rotation, subtle hue jitter) so repeats don't read as tiling.
5. **Cluster with intent, gap with intent.** Vegetation clumps in moist pockets and thins at edges (a *gradient* of density), leaving glades and open valleys — not an even spray.
6. **Structure over scatter.** Relief follows ridgelines; forests follow biome belts; rivers follow flow; roads follow valleys; towns follow water/passes. Every feature class is placed along the *structure* that generates it in the real world.
7. **Hierarchy of prominence.** A few big/important features (a capital, the main range, a great river) dominate; everything else recedes (Law #3). Don't make everything the same size/weight.
8. **Budget then place.** Compute a feature *count* from area × density × restraint_factor first, then distribute that fixed budget by Poisson spacing — this makes "sparse" a guarantee, not a hope.

> 🧭 **so-what:** In `mapStampAssets.ts` / `mapStudio.ts`, the placement loop must be **feature-category-driven with a Poisson sampler and a per-biome budget**, not `for each cell: maybe stamp`. If the code path is "iterate cells and roll per cell," that is the stamp-carpet bug — rewrite it to the stage-7 structure. Verify against [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) across ≥3 seeds; check the open-ground fraction and that ranges/rivers/biomes read as real.

### The whole model in one block (the master recipe)

```
# ── SUBSTRATE (physical facts — build once, per seed) ─────────────────────────
1  elevation  = heightfield_with_spines(fbm, mountain_belts, plateaus, rifts)  # §V.1–2
   land_mask  = elevation > sea_level;  coastline = fractal_boundary(land_mask) # §7
2  slope, ridges, basins, flow_dir = derive_terrain(elevation)                 # §V.3
3  elevation = fill_or_breach_pits(elevation, keep=large_dry_basins)
   flow_acc  = accumulate(flow_dir)
   rivers    = trace(flow_acc > CHANNEL_THRESHOLD)  # merge-only, high→sea/sink # §6
   lakes     = fill_to_spillpoint(...)              # outlet OR endorheic       # §8
4  temperature = base_lat(y) − LAPSE*elevation                                 # §10–11
   moisture    = base_lat(y) + water_proximity − rain_shadow + orographic      # §12
5  biome[region] = whittaker(temperature, moisture)                            # §9
                   then override by altitude bands + endorheic sinks           # §11
# ── PLACEMENT (symbols on top — sparse, structured, budgeted) ─────────────────
6  for range:  walk peaks along ridges (tall on crest → foothills; ONE idiom)  # 7a
   for biome:  budget = area*base_density*RESTRAINT;  poisson_disk(budget)     # 7b
               stamp with scale/rotation/hue variance; denser in moist pockets
   settlements = top score(water, confluence, pass, arable) − hostile;  spaced # 7c
   roads       = least_cost(valleys, low passes, bridges at fords)             # 7d
   pois        = a deliberate FEW (ruin, tower, mine, port, shrine)            # 7e
7  ASSERT open_ground_fraction >= 0.70   # else you built a carpet — Law #1
```

**Restraint knobs, in one place:** `LAND_FRACTION` (how much sea/void), `CHANNEL_THRESHOLD` (river density), `biome.base_density` (per-biome fullness), `RESTRAINT` (global feature multiplier, keep <1), Poisson `min_dist` (spacing), and the settlement score thresholds (how many towns). Tuning these — not adding more stamp types — is how you dial a map from "empty" to "busy" while *staying believable*.

---

## Part VII — Quick reference: the believability checklist for terrain

Before a render counts as "clears the bar" (full gate in [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md)):

- [ ] **Open ground dominates** — 70–90% of the sheet is parchment/plains/sea; the paper is visible. (Law #1)
- [ ] **Mountains are linear ranges** with a continuous spine + foothills, tallest on the crest — not scattered peaks. (§1, stage 7a)
- [ ] **One relief idiom per range** — young sharp OR old rounded, not mixed. (§1, Law #2)
- [ ] **Peaks are bare** above the treeline; forest belts foothills/valleys/coasts and thins uphill. (§11, §13)
- [ ] **Rivers obey all laws** — flow downhill, merge (never split except deltas), start high, end at sea/lake, widen downstream, meander on flats. (§6, stage 4)
- [ ] **Lakes have correct outflow** — one outlet, or endorheic sink; none stranded on a slope. (§8)
- [ ] **Coastline is fractal** — headlands/bays/fjords/estuaries/deltas as terrain warrants; no straight or over-smooth edges. (§7)
- [ ] **Biome variety** — plains/forest/marsh/desert/tundra differentiated by fill+texture+symbol set; not one tan fill. (§13, Law #6)
- [ ] **Deserts in the right place** — ~20–30° belt and/or rain shadow (lee of ranges), not random patches. (§12)
- [ ] **Features Poisson-spaced with scale/rotation variance** — no grid, no uniform carpet, no per-cell scatter. (stage 7)
- [ ] **Settlements near water/passes/confluences; roads follow valleys.** (stage 7c/7d)
- [ ] **Proven across ≥3 seeds** and side-by-side with the competitor at the same scale. (Law #10)

---

### See also
- **[SKILL.md](SKILL.md)** — the Ten Laws and the build pipeline this doc plugs into.
- **[REAL_CARTOGRAPHY.md](REAL_CARTOGRAPHY.md)** — relief *depiction* (hachures, contours, hypsometric tint, shaded relief) once you know *where* the relief goes.
- **[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md)** — the hand-drawn idiom to render this substrate in.
- **[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md)** — the symbol library stage 7 draws from (single idiom, light discipline).
- **[MAP_TYPES.md](MAP_TYPES.md)** — which of this applies per map type (world vs. region vs. battlemap vs. topographic).
- **[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)** — how the layer stack composites these placement decisions into one aged sheet.
- **[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md)** — the acceptance gate.
