# Real Cartography — the discipline our map pipeline dogfoods

> The knowledge base for the [`cartography`](SKILL.md) skill. Read [SKILL.md](SKILL.md)
> first for framing and the **Ten Laws**; this doc is the *why* behind them. Every
> section ends with a **→ So-what for our maps** callout that ties the principle to a
> Law and to the [CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md) dimension it defends.
>
> Cartography is a real profession with real theory. A fantasy map that ignores it
> looks fake for reasons the viewer can't name — the eye is trained by two centuries
> of published maps. To *fake* a good map convincingly, you must know what a *real*
> one does. This is that grounding. Siblings: [TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md)
> (geomorphology), [FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) (the hand-drawn
> idiom), [SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md), [MAP_TYPES.md](MAP_TYPES.md),
> [RENDERING_PIPELINE.md](RENDERING_PIPELINE.md), and the general
> [visual-judge](../visual-judge/SKILL.md) gate.

A map is not a picture of a place. It is a **scaled, projected, generalized, symbolized
argument** about a place — four transformations, each with its own craft and its own
failure modes. Miss any one and the sheet reads as amateur. This document walks all
four plus the two that bind them: **design** (hierarchy/color) and **type**.

---

## 1. Projections & distortion

### 1.1 What a projection actually is
A map projection is a **systematic mathematical transformation** from positions on a
curved surface (a sphere or, more precisely, an oblate ellipsoid) to positions on a
flat plane. The sphere is a *non-developable* surface: it cannot be flattened without
tearing, stretching, or shearing. This is not an engineering limitation — it is a
theorem. **Carl Friedrich Gauss's *Theorema Egregium*** (1827) proves that Gaussian
curvature is intrinsic, so any map from a curved surface to a plane *must* distort.
There is no perfect map. Every projection is a chosen compromise about *which* truth
to keep and *which* to sacrifice.

The four properties a projection can preserve — and never all at once:
- **Area (equivalence / equal-area):** a coin laid anywhere on the map covers the same
  amount of real ground. Preserving area forces angles/shapes to distort.
- **Shape locally (conformality):** angles are correct *at every point*, so small
  shapes look right and graticule lines cross at 90°. Preserving conformality forces
  areas to blow up away from the standard line (Greenland vs. Africa on Mercator).
- **Distance (equidistance):** true scale is held along *specific* lines only (never
  everywhere — that's impossible).
- **Direction (azimuthality):** true bearings from *one central point* to all others.

A projection can be equal-area **or** conformal but **never both** (they are
mathematically exclusive). Most preserve one property, approximate another, and let
the rest go. A **compromise projection** preserves *none* exactly but keeps all
distortions moderate — chosen for looks, not measurement.

### 1.2 Tissot's indicatrix — how to *see* distortion
**Nicolas Auguste Tissot** (1859–1881) gave cartography its distortion microscope.
Imagine an infinitesimally small circle on the globe. Under any projection it maps to
an **ellipse** — the *indicatrix*. Reading a field of these ellipses across a map tells
you everything:
- **Equal-area projection:** every indicatrix has the same *area* (though ellipses may
  be squashed to different shapes) → shapes shear but sizes stay honest.
- **Conformal projection:** every indicatrix stays a *circle* (angles preserved) but
  its *radius grows* with distance from the standard line → shapes right, sizes lie.
- **Compromise:** ellipses vary in both size and shape, but all mildly.

The two semi-axes of the ellipse (conventionally *a* and *b*) are the scale factors
along the principal directions; their product is the areal scale, their ratio the
angular (shape) distortion. This is the rigorous language behind "the map lies here."

### 1.3 The major families
Projections are grouped by the **developable surface** they conceptually project onto —
a cylinder, cone, or plane — which controls *where* distortion is minimal.

**Cylindrical** — project onto a cylinder wrapped around the globe; distortion is
minimal along the line(s) of tangency (usually the equator) and grows toward the poles.
Graticule is a rectangular grid.
- **Mercator (Gerardus Mercator, 1569):** *conformal* cylindrical. Its defining virtue
  is that **rhumb lines (loxodromes) — constant-compass-bearing courses — plot as
  straight lines**, which is why it dominated marine navigation for centuries. Its
  defining vice is catastrophic areal exaggeration toward the poles (Greenland looks
  larger than Africa though Africa is ~14× bigger). **Web Mercator** (EPSG:3857) is the
  slippery-map standard behind Google/OSM tiles — chosen for math simplicity, not
  honesty. *Never* use Mercator to compare sizes.
- **Transverse Mercator / UTM:** the cylinder turned 90° so the tangent line is a
  meridian; the basis for large-scale topographic mapping in narrow N–S zones.
- **Gall–Peters, Lambert cylindrical, Behrmann:** *equal-area* cylindricals — honest
  areas, brutally sheared shapes at the poles.

**Conic** — project onto a cone seated on the globe; minimal distortion along one or
two **standard parallels**. Ideal for **mid-latitude regions wider than they are tall**
(the continental USA, Europe). Graticule: meridians radiate as straight lines, parallels
are concentric arcs.
- **Lambert Conformal Conic (LCC):** conformal; aeronautical charts, US state plane.
- **Albers Equal-Area Conic:** equal-area; USGS national thematic maps.

**Azimuthal / planar** — project onto a plane tangent at one point; preserves true
direction *from that center* and shows distance/scale symmetrically around it. Best for
**polar regions or a single-hub view**.
- **Stereographic** (conformal), **Lambert Azimuthal Equal-Area**, **Orthographic**
  (the "globe-from-space" look, extreme edge compression), **Azimuthal Equidistant**
  (true distance from center — the UN emblem, radio range-rings).

**Pseudocylindrical & compromise (world maps)** — built to show the *whole* world with
balanced distortion:
- **Robinson (Arthur H. Robinson, 1963):** a *compromise* — neither equal-area nor
  conformal, tuned purely by eye for a pleasing, "looks-right" globe. National
  Geographic's world map 1988–1998.
- **Winkel Tripel (Oswald Winkel, 1921):** compromise minimizing the *triple* of area,
  distance, and angle error simultaneously — hence *Tripel*. Adopted by National
  Geographic in 1998 as its standard world map; widely considered the best all-round
  world compromise.
- **Mollweide** (equal-area ellipse), **Sinusoidal**, **Goode Homolosine** (equal-area,
  *interrupted* — lobed with cuts through the oceans to cut shape error), **Eckert IV/VI**.

**Rule of thumb:** whole world → compromise (Winkel Tripel/Robinson) or interrupted
equal-area; a mid-latitude country → conic; a pole or single hub → azimuthal; navigation
→ Mercator; a thematic map comparing quantities by area → *always* equal-area.

### → So-what for our maps
Our fantasy maps are almost always **flat region/continent sheets at a scale where
projection distortion is negligible** — treat them as a plane and don't fake a
graticule that implies a projection you didn't compute. But the moment we draw a
**whole-world / hemisphere map** (MAP_TYPES → world), the choice becomes visible and
judged: a rectangular lat/long grid silently commits you to the *worst* look
(Plate Carrée stretching), whereas a curved Winkel-Tripel-style graticule with an
elliptical or lens-shaped frame instantly reads "real globe unrolled." If we draw
graticule lines, they must **curve** on a world map and be **straight/rectangular**
only on a small region. A visible, correct graticule is a decorative-apparatus and
believability win (CRITIQUE_CHECKLIST #3, #10); a mismatched one is a tell. See
[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md) for hemisphere-frame styling.

---

## 2. Scale & generalization — the craft of leaving things out

### 2.1 Representative fraction and scale
**Scale** is the ratio of map distance to ground distance, stated three ways:
- **Representative fraction (RF):** a unitless ratio, e.g. `1:24,000` — one unit on the
  map is 24,000 of the same unit on the ground. Unitless means it's valid in any
  measurement system.
- **Verbal statement:** "one inch to the mile."
- **Bar scale (graphic):** a ruler drawn on the map — the *only* form that stays correct
  after the image is resized or reprojected (see §7 furniture).

**"Large scale" vs "small scale" is the eternal confusion:** it's the *fraction's value*.
`1:1,000` is a **large** scale (the fraction 1/1,000 is a large number) → small area,
high detail (a city block). `1:10,000,000` is a **small** scale → huge area, low detail
(a continent). Large scale = big detail of a small place; small scale = small detail of
a big place.

### 2.2 Scale-dependent detail — the fundamental constraint
The core truth of cartography: **at any given scale, the ground contains vastly more
information than the sheet can legibly hold.** A coastline has effectively infinite
length as you zoom in (Mandelbrot's coastline paradox); a `1:1,000,000` map physically
cannot draw every cove. Detail is not free — it costs ink, space, and legibility. So the
cartographer's central act is **choosing what to omit and how to abstract what remains.**
This is *generalization*, and it is where craft lives. A map that tries to show
everything at every scale becomes an illegible clot — which is precisely our historic
carpet-of-stamps failure, restated in professional terms.

### 2.3 The generalization operators
The canonical taxonomy is **McMaster & Shea (1989, *"Cartographic generalization in a
digital environment: when and how to generalize"*)**, which lists ~10–12 operators
(simplification, smoothing, aggregation, amalgamation, merging, collapse, refinement,
typification, exaggeration, enhancement, displacement, classification). The **six that
matter most for building maps by hand or by generator**:

1. **Selection (elimination):** decide which features appear *at all*. The first and
   most important operator — show the county seats, drop the hamlets; show the range,
   drop the individual knolls. *Nothing else can rescue a map that selected badly.*
2. **Simplification:** reduce a feature's geometry — fewer vertices in a coastline, a
   straighter river — while keeping its recognizable character (Douglas–Peucker is the
   classic line-simplification algorithm).
3. **Smoothing:** soften jagged digitizing/sampling artifacts into aesthetically clean
   curves *without* removing points wholesale — the plastic, flowing coast of a
   published map vs. the stair-stepped raster edge.
4. **Aggregation (amalgamation / typification):** merge many small like features into
   one representative form — a scatter of tiny islands becomes an archipelago symbol;
   fifty trees become one "forest" region; a cluster of buildings becomes a town dot.
5. **Displacement:** nudge features apart so they stay distinct when their symbols would
   otherwise collide at scale — a road, river, and railway squeezed through the same
   valley are separated slightly so all three read. Symbols are drawn *wider than true
   scale*, so at small scales they inevitably overlap unless displaced.
6. **Exaggeration (enhancement):** enlarge or emphasize an important feature that would
   vanish at true scale — a strategically vital but narrow strait, a landmark peak, a
   thin but critical river. Its *symbol* grows; its *meaning* is preserved.

Two more operators complete the working set (they appear in every professional
generalization engine):

7. **Collapse (dimensional reduction):** shrink a feature to a lower-dimensional symbol
   when its true extent falls below the resolvable minimum — a city drawn as a filled
   footprint at large scale *collapses* to a single dot at small scale; a river's two
   banks collapse to one line; a lake to a point.
8. **Typification:** replace many similar features with a *smaller representative set that
   preserves the pattern* — a dense grid of 200 buildings becomes ~30 buildings that keep
   the block's shape and density feel; a stand of forty peaks becomes a handful that keep
   the range's silhouette. (Distinct from aggregation, which *merges into one*;
   typification *thins while preserving the Gestalt*.)

Crucially, **generalization is symbolic, not deceptive** — Shea & McMaster stress that
these operators change *representation* to preserve *legibility and meaning*, they are
not license to invent geography.

### 2.4 Model generalization vs. cartographic generalization
Professional practice separates two stages, and conflating them is a common error:
- **Model (database) generalization** operates on the *data model* — reducing resolution,
  merging classes, dropping attributes to derive a smaller-scale *dataset* from a larger
  one. It is about **data**, is measurement-preserving where possible, and produces no
  symbols. (Analog for us: deriving a coarse region heightfield/biome mask from a fine
  one before we draw anything.)
- **Cartographic generalization** operates on the *graphic* — applying the §2.3 operators
  so the *symbolized map* stays legible at the target scale. It is about **display**, is
  perceptually driven, and is where selection/simplification/typification/displacement/
  exaggeration/collapse actually happen. (Analog for us: choosing which peaks, forests,
  and towns to *draw* and how large, given the sheet size.)

Both are governed by **scale-dependent detail** (§2.2): the target scale sets a *minimum
resolvable dimension* (features below it must be selected out, collapsed, or typified) and
a *minimum separation* (features closer than the eye can distinguish must be displaced or
aggregated). Generalize the model first (get the data to roughly the right resolution),
then generalize cartographically (make the drawing legible). Doing only the second on
full-resolution data is exactly how you get an unreadable clot.

### 2.5 Can this be automated? — the 2025 deep-learning survey
Generalization is the hardest cartographic process to automate because it is a
*holistic, context-dependent judgment* ("which of these thousand things matters here, at
this scale, for this reader?"), not a per-feature rule. The current state of the art is
surveyed in:

> **Yan, X., Yang, M. & Ai, T. (2025). "Deep learning in automatic map generalization:
> achievements and challenges." *Geo-spatial Information Science*, 28(6), 2905–2926.**
> DOI [10.1080/10095020.2025.2480815](https://doi.org/10.1080/10095020.2025.2480815).
> Open Access (CC-BY), Wuhan University / Tongji University.

What the survey reports (from its abstract and the DL-for-generalization literature; the
CC-BY full text is worth reading when reachable — Taylor & Francis and ResearchGate both
403'd at time of writing):

- **Achievements — where DL now helps.** Unlike hand-tuned rule/constraint systems, deep
  networks **learn generalization behavior directly from paired multi-scale map data**
  (raw pixels or raw vertex/point coordinates), reducing reliance on manually engineered
  rules. Concrete wins reported: **graph convolutional networks (GCNNs)** for **building-
  pattern recognition and classification** (a prerequisite for typification/aggregation);
  **encoder-decoder / GAN and CNN raster models** for **building simplification and
  coastline/contour smoothing**; **sequence and graph models** for **road-network
  selection**; and learned models for **river/stroke selection**. DL is strongest at the
  *representation* task — abstracting and encoding a feature's essential shape/pattern into
  a form a downstream operator can act on.
- **Challenges — where it still can't be trusted.** The survey (consistent with the wider
  GeoAI literature) flags: **scarce, inconsistent multi-scale training data** (paired
  "before/after" generalization datasets are rare and cartographer-specific);
  **poor cross-scale and cross-region transfer** (a model trained at one scale/place
  degrades elsewhere); **weak handling of hard operators** — especially **displacement**
  (holistic spatial conflict resolution) and **holistic, whole-map context** (models act
  locally and miss global balance/hierarchy); **interpretability** (a black box can't
  explain *why* it kept a feature — hence the parallel push for *explainable* DL
  generalization); and **no guarantee of topological/geometric integrity** (a network may
  break connectivity a rule engine would preserve). Net: DL **assists** specific operators
  today; it does **not** yet perform trustworthy end-to-end, whole-map generalization.

### → So-what for our maps and our generator
**Generalization is the formal discipline behind our #1 craft law — Restraint, "knowing
what to leave out."** Our documented failure mode (the P9 render) was *zero
generalization*: wall-to-wall feature carpet that selected nothing, aggregated nothing,
typified nothing — every cell stamped. Named against the operators, the fix is exact:
- **Selection** — draw the county seats and the range, drop the hamlets and the knolls.
- **Aggregation / typification** — turn a field of forest cells into forest *regions*, then
  draw a *representative thinned set* of tree symbols along their belts (typification),
  never one-stamp-per-cell.
- **Collapse** — a distant town is a dot, not a rendered footprint, at region scale.
- **Displacement** — nudge a road/river/label apart when their symbols would collide,
  rather than overlapping them (CRITIQUE #8).
- **Exaggeration** — draw the capital's castle a touch larger than true scale for
  hierarchy — meaning preserved, not error.

Our generator must run **model generalization first** (§2.4 — derive a coarse
heightfield/biome/settlement set at the sheet's scale) **then cartographic generalization**
(select/typify/displace what actually gets drawn). The practical implementation of this is
the **density / restraint placement model in
[TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md)** — spacing rules, per-belt symbol budgets,
and ridgeline-walked relief that *are* selection + typification made concrete; treat that
doc as our applied generalization engine. Per §2.5, **DL can assist individual operators
(pattern recognition, simplification, selection) but cannot yet be trusted for whole-map
generalization** — so our pipeline keeps generalization *rule-driven and legible*, using
learned components only as scoped helpers, and always judged by eye. Open ground is the
*result* of correct generalization, not laziness: if our generator can't state *what it
left out and why*, it isn't generalizing — it's carpeting. Weight this heaviest
(CRITIQUE #1).

---

## 3. Relief depiction — showing the third dimension on a flat sheet

Representing terrain height on paper is the deepest, oldest sub-craft of cartography and
the one that most separates a "real" map from a doodle. The canonical reference is
**Eduard Imhof's *Cartographic Relief Presentation*** (*Kartographische Geländedarstellung*,
1965; ESRI Press English edition 2007) — Imhof (1895–1986) was professor of cartography
at ETH Zürich and the defining figure of the **Swiss school** of relief. Everything
below traces to him or to the tradition he codified. There are six main techniques,
often layered.

### 3.1 Hachures
Short lines drawn **down the direction of steepest slope**. The governing system is
**Johann Georg Lehmann's** *Böschungsschraffen* (slope hachures, 1799): the **steeper
the slope, the thicker and denser (darker) the hachures; flat ground is left white.**
Read as a field, hachures make ridges and valleys leap out — steep faces go nearly
black, gentle slopes go grey, plains stay blank. Their weakness: they carry *slope* but
not *absolute elevation* (you can't read a height off them), they choke fine detail in
rugged country, and they're laborious. The characteristic "furry caterpillar" mountain
ranges of 18th–19th-century military maps are hachured. A modern *"hachure look"* is a
strong fantasy idiom (see [FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md)).

### 3.2 Contour lines (isohypses)
Lines connecting points of **equal elevation**. The single most information-rich relief
method: exact height is readable, and the *pattern* encodes form —
- **close together = steep; far apart = gentle;**
- Vs pointing **upstream/uphill** = a valley or stream; Vs or bulges pointing
  **downhill** = a ridge/spur;
- concentric closed loops = a summit (or, with hachure ticks pointing inward,
  a depression);
- the **contour interval** (vertical distance between lines) is fixed per map and set by
  scale + terrain ruggedness. **Index contours** (every 5th line, drawn heavier and
  labeled) aid reading.

Contours are geometrically honest but can be hard for lay readers to "see" as 3D — which
is why they're almost always combined with shaded relief or tint.

### 3.3 Spot heights & bench marks
Discrete labeled points giving **exact elevation** at a specific spot — summits, passes,
lake surfaces, road junctions. A **triangulation/bench mark** is a surveyed control
point. Spot heights supply the precise numbers that contours and shading only imply, and
they double as visual accents on peaks and passes. Cheap, precise, and always in style.

### 3.4 Hypsometric tinting (elevation / layer tinting)
Fill the **bands between chosen contours with color** so elevation reads at a glance as a
color ramp. The **conventional altitude palette** — greens for lowlands rising through
yellows and tans to **browns for highlands and white/purple for the highest peaks** —
descends directly from this. But Imhof warned against the naïve version (bright green
lowlands imply "fertile," misleading for a desert basin). His refinement is the
**aerial-perspective hypsometric scheme** (§3.6, §5).

### 3.5 Shaded relief (hill-shading) and the NW light convention
Simulate how a **3D terrain surface would be lit by an oblique light**, shading slopes
facing away from the light darker and slopes facing it lighter. This is the technique
that makes terrain look *sculpted*. Two conventions are near-universal:
- **Illumination from the upper-left / northwest, azimuth ≈ 315°, altitude ≈ 45°.**
- **Why NW and not the physically-plausible south?** Because of the **relief-inversion
  (pseudoscopic / terrain-reversal) effect**: the human visual system assumes light
  comes *from above*, so if a map is lit from the bottom, the brain flips the shape —
  ridges read as valleys and craters as domes. Lighting from the top (and by convention
  the top-*left*) keeps mountains reading as mountains. This is a *perceptual* fact, not
  an aesthetic whim. (Empirical work — Biland & Çöltekin, 2017 — found **NNW, ~337.5°,
  even better than 315°** for landform-identification accuracy; and **multidirectional
  hill-shading**, blending azimuths ~225/270/315/360°, reveals features hidden in
  single-source shadow — useful for gentle terrain.)

Analytical hill-shading is computed from a heightfield (a DEM) via the surface normal's
angle to the light vector — the same Lambert cosine law our shader pipeline already
speaks (see [shader-craft](../shader-craft/SKILL.md), [RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)).

### 3.6 Illuminated / Swiss-style relief and Imhof's principles
The masterwork combination — the "Swiss style" — layers shaded relief + hypsometric tint
+ contours + rock drawing + careful color into a single plastic, naturalistic surface.
Imhof's governing principles:
- **Oblique light + aerial perspective together:** don't just shade; also **lighten and
  desaturate distant/low ground and heighten contrast on high peaks** so the terrain
  gains depth as in a real hazy vista (§5).
- **Rock drawing (*Felszeichnung*):** high, bare rock is rendered with fine
  **skeletal/hachure-like lines following the geological structure and fall-lines**, not
  smooth shading — the technique that gives Swiss alpine maps their crystalline peaks.
- **Color coordination & restraint:** relief color must stay muted and cool enough that
  **line work and labels stay legible on top** — the relief is the stage, not the actor.
- **Local adjustment:** a purely mechanical hill-shade is lifeless; the master lightens
  shadowed valleys slightly so detail survives and locally strengthens key ridgelines —
  a *cartographic* rendering, not a physics render.

### → So-what for our maps
Relief is CRITIQUE #6 (**relief structure**) and half of #9 (**sheet as one object**).
The non-negotiables that fall out of Imhof: **(a) one light direction across every
single relief symbol and shadow — upper-left/NW — no exceptions**, because mixed light
is the fastest "N pasted sprites" tell (Law #9); **(b) a pooled ground-shadow** so a
range grounds as one raised mass rather than a row of stamps (this is hand-drawn shaded
relief, done with stamps); **(c) tallest peaks on the ridge crest tapering to
foothills**, mimicking how contours/shading concentrate on the spine (Law #5,
[TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md)); and **(d) if we ever tint by elevation,
use the conventional green→brown→white ramp, muted, so labels survive on top.** A
hachure or Swiss idiom is a legitimate high-parity style to *choose* — but choose one
(Law #2) and light it consistently.

---

## 4. Map design canon — the visual-communication theory

Cartographic design is a specialized branch of information design. Four bodies of work
form its canon; know the names, they're load-bearing.

### 4.1 Bertin — the visual variables
**Jacques Bertin**, *Sémiologie graphique* (1967; *Semiology of Graphics*, 1983), gave
graphics its grammar. Every mark on a map varies along a small set of **visual
variables** (the "retinal variables"). The classic **seven**:

1. **Position** (location in the plane) — the strongest, most precise variable.
2. **Size** — larger = more; the natural encoder of *quantity/ordered* data.
3. **Shape** — endless nominal categories; encodes *what kind*, not *how much*.
4. **Value** (lightness↔darkness) — the natural encoder of *ordered* data; the backbone
   of hierarchy and of sequential color.
5. **Colour (hue)** — excellent for *nominal categories*; poor for order (there's no
   innate rank to red vs. green).
6. **Orientation** (angle/direction) — a limited nominal/rotational channel.
7. **Texture** (grain/pattern) — pattern density; ordered or nominal.

Bertin also classified each variable by the **perceptual level of organization** it
supports — *selective* (can you instantly pick out all of one category?), *associative*
(can you group them?), *ordered* (do they read as a rank?), *quantitative* (can you read
a ratio?). The practical payoff: **match the variable to the data type.** Use *value/size*
for amounts, *hue/shape* for categories. Encoding categories with value, or amounts with
hue, is a design error that makes a map "feel wrong."

### 4.2 Figure–ground, visual hierarchy, balance
- **Figure–ground:** the perceptual separation of a dominant *figure* from a recessive
  *ground* (Gestalt psychology). On a map, **land must read as figure against
  water/void as ground.** Achieved with a land tint, coastal echo/vignette lines, closed
  contrast, and clean edges. Ambiguous figure–ground = the map looks broken (Law #4,
  CRITIQUE #7).
- **Visual hierarchy (intellectual hierarchy made visual):** the reader's eye should
  land on the most important thing first and descend in order: **title/subject → major
  landmarks → ranges/coasts → minor features → texture/graticule.** Built from
  *contrast* in Bertin variables — size, value, and above all **negative space** — not
  from making everything loud. If everything shouts, nothing is heard (Law #3,
  CRITIQUE #8).
- **Balance & visual center:** the composition should feel weighted, not lopsided;
  the *optical center* sits slightly above the geometric center, where the eye rests.
  Margin elements (legend, scale, cartouche) are placed to balance the main body's mass.

### 4.3 Tufte — data density and honest ink
**Edward Tufte** (*The Visual Display of Quantitative Information*, 1983; *Envisioning
Information*, 1990) supplies the discipline of *reduction*:
- **Data-ink ratio:** maximize the share of ink that carries information; **erase
  non-data ink and redundant data-ink.** Every gratuitous rule, box, drop-shadow, and
  gradient competes with content.
- **Chartjunk:** decorative clutter that adds no information and degrades reading — the
  named enemy. (Note: *style-appropriate* fantasy marginalia is not chartjunk when it
  carries the sheet's *idiom* and story — but a gratuitous bevel on a legend box is.)
- **Layering & separation:** distinguish overlapping information layers by subtle,
  consistent contrast so each reads without the others fighting — the engine behind
  visual hierarchy.
- **Small multiples:** repeat a small map many times with one variable changing (time,
  theme) so comparison is instant — the right tool for change-over-time or thematic sets.
- **Graphical integrity:** don't let the graphic lie — e.g. the "**lie factor**"
  (visual effect size ÷ data effect size should ≈ 1). For us: don't exaggerate distortion
  or imply precision we didn't compute.

### 4.4 MacEachren & Brewer — how maps are read and colored
- **Alan MacEachren**, *How Maps Work* (1995), reframes maps as **representation +
  cognition**: a map is a sign-system the reader *actively constructs meaning from*, not
  a passive picture. His **cartography³ cube** frames map *use* along three axes —
  private↔public audience, revealing-unknowns↔presenting-knowns, high↔low interaction —
  which tells you a *reference* map (public, presenting, low-interaction) and an
  *exploratory* map need different designs.
- **Cynthia Brewer** operationalized color for maps and built **ColorBrewer**, the
  standard tool of vetted map color schemes. Her core distinction (next section) — and
  her guidance that schemes be **colorblind-safe, print-safe, and photocopy-safe** — is
  the practical color law of modern cartography (see [accessibility](../accessibility/SKILL.md)).

### → So-what for our maps
This is the theory under Laws #3 (hierarchy) and #4 (figure–ground) and CRITIQUE #7, #8.
Concretely: **(1)** encode map data by the *right* Bertin variable — settlement
*importance* by dot **size/value**, terrain *type* by **hue/shape/texture**; never rank
categories by hue. **(2)** Guarantee figure–ground with a land tint + coastal echo +
vignette so land pops off the sea (Law #4). **(3)** Enforce a real hierarchy with size,
value, and negative space — the title and capital must win, the graticule must recede.
**(4)** Apply Tufte's razor to our décor: keep the *idiom-carrying* marginalia (compass,
cartouche, sea-beasts), cut the *idiom-empty* junk (drop-shadows on legend boxes, noisy
gradients). Judge all of it with your own eyes via [visual-judge](../visual-judge/SKILL.md).

---

## 5. Map color theory

Color on a map is *encoded meaning*, not decoration. Brewer's three **scheme types**
(the ColorBrewer taxonomy) are the foundation — pick the type by the *data type*:

- **Sequential** — light→dark progression of a single (or blended) hue for **ordered,
  one-directional** data (elevation, population density, rainfall). **Light = low, dark =
  high** by convention; the *value* progression (Bertin) does the ordering work, hue just
  flavors it.
- **Diverging** — two sequential ramps meeting at a **meaningful midpoint** (a neutral
  light color) for data with a critical middle or two directions (temperature anomaly
  above/below normal, elevation above/below sea level, gain/loss). Never use diverging
  where there's no real midpoint.
- **Qualitative** — distinct **hues of similar value** for **nominal categories** with no
  order (land-use classes, political states, biome types). Vary *hue*, hold *value*
  roughly constant so no category looks "more important."

**Value & contrast drive hierarchy:** because the eye reads *value* (lightness) as order
and importance, the most important marks get the strongest value contrast against their
surround; background/context stays low-contrast. This is how color *serves* the visual
hierarchy of §4.2 rather than fighting it.

**Conventional (mimetic) colors** — a map earns instant legibility by honoring learned
associations: **blue = water**, **green = vegetated lowland**, **tan/yellow = arid /
plain**, **brown = highland / mountain**, **white = snow/ice/peak**, dark green = dense
forest, grey = rock/urban. Violating conventions (red rivers) costs the reader a
double-take for no gain.

**Aerial perspective in color (Imhof):** real distant landscape desaturates and shifts
cool/pale through atmospheric haze. Imhof's aerial-perspective hypsometric ramp encodes
this vertically: **grey-blue lowlands → blue-green → green → yellow-green hills → yellow
and pale-yellow mountains → white peaks**, with **higher, "nearer-to-the-viewer" terrain
getting stronger warm contrast and lower ground going hazier, cooler, flatter.** Applied
horizontally on our sheets, the same principle says **desaturate and lighten features
toward the map's edges / toward "distant" terrain** to build depth.

**Colorblind & reproduction safety (Brewer):** ~8% of men have red–green color
deficiency; a scheme that relies on red-vs-green alone fails them. Prefer ColorBrewer
colorblind-safe schemes, and back color with a **redundant channel** (value, texture,
shape, or a label) so meaning survives in grayscale/photocopy — a direct application of
[accessibility](../accessibility/SKILL.md).

### → So-what for our maps
Color feeds CRITIQUE #4 (biome variety), #6/#7 (relief & water), and the hierarchy
of #8. **Rules: (a)** biomes are a *qualitative* scheme — distinct hues at similar value, so
"one tan fill" (the P9 failure) becomes differentiated plains/forest/marsh/desert/tundra
(Law #6). **(b)** Elevation, if tinted, is *sequential/aerial-perspective* green→brown→
white (Law #5). **(c)** Keep conventional colors — blue seas, green lowlands — so the
sheet reads without a legend. **(d)** Use aerial perspective (desaturate/lighten with
distance) to add depth and to keep the *global paper pass* fusing everything into one
aged sheet (Law #9). **(e)** Keep relief/tint muted so labels survive on top (§3.6, §6).

---

## 6. Map typography — lettering is a designed layer

Type is not "adding text"; it is a design layer with its own centuries-old rulebook,
codified by **Imhof's classic essay "Positioning Names on Maps" (1975)** and by Eduard
Imhof's practice generally. Good label placement is *the* thing amateur maps get wrong
and pro maps get invisibly right.

### 6.1 The point-feature placement priority
For a **point** (city, peak, spot feature), label positions are ranked. The near-universal
priority, top to bottom:
1. **Upper-right** of the point — the default, best position.
2. Lower-right.
3. Upper-left.
4. Lower-left.
5. Directly right / left, then above / below (centered) as last resorts.

The label sits **close enough to be unambiguously owned by its point, far enough not to
touch the symbol**, and never straddles a coastline/border so it reads as belonging to
one side.

### 6.2 Linear and area features
- **Linear features (rivers, roads, ranges):** the name **curves along the feature**,
  following its bend, letters riding the line — placed to be read *without rotating the
  map* (letters upright-ish, running left→right; on near-vertical features, reading
  bottom→top). Rivers are labeled *along and within their bends*, repeated on long rivers.
- **Area features (regions, seas, forests, kingdoms):** the name is **letterspaced
  (tracked) wide and often gently arced to span the feature's extent**, telling the reader
  *how far the region reaches* — Bertin's "assist the reader in appreciating spatial
  extent." Set in a larger, lighter, often all-caps face; never boxed.

### 6.3 Imhof's lettering principles (paraphrased)
1. **Legibility first** — names must be effortless to read; type must never fight the
   base map (keep relief/tint muted beneath, §3.6/§5).
2. **Names locate features precisely** — placement must make it unambiguous *which*
   feature a name belongs to; a misplaced label is worse than none.
3. **Type differentiation reflects classification & rank** — a **type hierarchy** encodes
   feature importance: nation/region names largest and letterspaced, cities graduated by
   size, minor features smallest. Face, size, weight, case, and color all carry rank.
4. **Even, uncrowded distribution** — names should be neither bunched into clots nor
   sprinkled mechanically; distribute for balance and let the map breathe (a typographic
   restatement of Law #1).
5. **Avoid overlap and interference** — labels must not overlap each other or bury
   important symbols/lines; this is a *collision-avoidance* problem (see below).
6. **Convention: water in *italic*** — hydrographic features (rivers, lakes, seas,
   oceans) are traditionally set in **italic/oblique**, usually blue, instantly separating
   the water layer from land labels.

### 6.4 What a good label-placement algorithm encodes
Automated label placement is a classic **NP-hard combinatorial optimization** (the
map-labeling problem). A competent solver encodes exactly Imhof's rules as constraints
and costs:
- **candidate positions** per feature (the point-priority list; sampled points along
  lines/areas),
- **penalties** for overlap (label–label, label–symbol, label–coastline), for
  non-preferred positions, for ambiguous ownership, and for crossing important features,
- **hierarchy weighting** so high-rank labels win conflicts and get placed first,
- a **search** (greedy, simulated annealing, or gradient) minimizing total penalty,
- **curved baselines** for linear/area names and **letterspacing** for area names.

### → So-what for our maps
This is Law #8 and CRITIQUE #8 in full. Our placement step must: **(1)** run a real
collision-avoided solver, not paste text at feature centroids (overlapping labels =
instant amateur tell); **(2)** default point labels to **upper-right**, offset off the
symbol; **(3)** **curve** settlement/region/river names along their features; **(4)**
**letterspace region names wide** to show extent; **(5)** enforce a **type hierarchy**
(world > region > city > feature) in size/weight/case; **(6)** set **water labels in
italic**, conventionally blue; **(7)** keep relief/color muted beneath type so it stays
legible. And per [SKILL.md](SKILL.md) reuse-first, labels use real [typography](../typography/SKILL.md)
faces (Cinzel / Uncial Antiqua for fantasy, a condensed serif for topographic) —
**never the engine default font**. Hand-lettered *look* comes from smart snapping + good
faces, not literal handwriting.

---

## 7. Standard map furniture (marginalia)

The apparatus around and within the map body that lets it function as a document. Each
has a purpose and a placement logic; missing or generic furniture is CRITIQUE #10.

- **Title / cartouche:** states the map's *subject, place, and (if thematic) theme* — the
  top of the visual hierarchy. On decorative/fantasy maps this becomes an ornamented
  **cartouche** (a framed panel), traditionally set in an unobtrusive corner or a sea. It
  should answer "what am I looking at?" before anything else.
- **Legend / key:** decodes every symbol, color, and line style that isn't
  self-evident — the map's dictionary. Order it by importance/hierarchy; **omit the
  self-explanatory** (don't legend a blue sea). Placed in a balancing corner, boxed or
  inset to separate it from the body.
- **Scale bar (graphic scale):** the *resize-proof* statement of scale (§2.1) — a labeled
  ruler in ground units. Always prefer a **bar** over a bare RF on any image that may be
  zoomed/reprinted. Place near the legend or a lower corner, unobtrusive.
- **North arrow / compass rose:** orients the reader. A simple arrow suffices on
  reference maps; a **compass rose** is the fantasy idiom's showpiece. **Omit it if north
  is up and a graticule already shows orientation** — a gratuitous compass on an obvious
  north-up map is chartjunk. On non-north-up or projected maps it's mandatory.
- **Graticule / grid:** the reference network — **graticule** = lines of latitude/longitude
  (geographic); **grid** = a projected/arbitrary coordinate mesh (e.g. UTM, or a fantasy
  "A1–H8" battlemap grid). Carries orientation and location; must be *subordinate* (thin,
  low-value) so it never competes with content. On a world map it **curves** (§1.4).
- **Inset map(s):** a secondary frame — either a **locator** (small-scale "where in the
  world is this") or a **detail enlargement** (large-scale blow-up of a dense area, e.g. a
  capital city). Clearly bounded and keyed to the main body.
- **Source / credits / date / authorship:** provenance — data sources, projection/datum,
  production date, cartographer. For us this is where **asset/font/data credits** live per
  the [credits](../credits/SKILL.md) skill; every generated symbol and licensed font is
  recorded. Set small, in a lower margin.

**Placement logic overall:** furniture fills the "dead" corners and balances the body's
visual mass (§4.2 balance), stays subordinate in the hierarchy (nothing in the margin
should out-shout the map), and adopts the sheet's *idiom* — a parchment map gets an inked
cartouche and rose; a topographic sheet gets a clean legend box and bar scale.

### → So-what for our maps
Furniture is CRITIQUE #10 (**decorative apparatus**) and part of #8's hierarchy. Ship
maps with a **style-appropriate cartouche/title, a legend when symbols aren't obvious, a
graphic scale bar, a compass/north indicator, a subordinate graticule/grid where the type
calls for it, an inset for dense areas, and a credits line** wiring in
[credits](../credits/SKILL.md). Match every piece to the chosen idiom (Law #2) — an inked
compass rose on a parchment region map, a clean bar+legend on a topographic sheet. Bind
each furniture asset by stable ID through the [asset-manifest](../asset-manifest/SKILL.md)
so Jesus can swap it live ([SKILL.md](SKILL.md) integration).

---

## 8. How this chains into the rest of the skill

Real cartography is the *theory*; the sibling docs are the *practice* that applies it:

- **[TERRAIN_AND_BIOMES.md](TERRAIN_AND_BIOMES.md)** — turns §2 generalization + §3
  relief + §5 color into a concrete geomorphology + density/restraint placement model
  (ranges on a spine, rivers high→sea, biome belts). The fix for the stamp carpet.
- **[FANTASY_CARTOGRAPHY.md](FANTASY_CARTOGRAPHY.md)** — applies §3 (hachure/relief
  idiom), §5 (aged palette, aerial perspective), §6 (hand-lettered look), and §7
  (cartouche/rose) in the Tolkien/Baynes/Wonderdraft/Inkarnate hand-drawn language.
- **[SYMBOLOGY_AND_STAMPS.md](SYMBOLOGY_AND_STAMPS.md)** — §4 (one coherent idiom, Bertin
  variables per symbol) and §3.5 (one light direction) at the symbol-library level.
- **[MAP_TYPES.md](MAP_TYPES.md)** — §1 (projection per type), §2 (scale per type), §7
  (which furniture each type requires).
- **[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)** — where §3.5 hill-shading, §6 label
  placement, and §7 furniture become the actual Map Studio layer stack and code.
- **[CRITIQUE_CHECKLIST.md](CRITIQUE_CHECKLIST.md)** + **[visual-judge](../visual-judge/SKILL.md)**
  — the acceptance gate that scores whether we actually honored any of this. Every
  section above maps to a numbered rubric dimension. **Prove it, don't claim it** (Law #10).

---

### Selected references (verify before citing further)
- Eduard Imhof, *Cartographic Relief Presentation* (1965; ESRI Press, 2007) — relief,
  color/aerial perspective, and (via "Positioning Names on Maps," 1975) lettering.
- Jacques Bertin, *Sémiologie graphique / Semiology of Graphics* (1967/1983) — visual
  variables.
- Edward R. Tufte, *The Visual Display of Quantitative Information* (1983) — data-ink,
  chartjunk, integrity; *Envisioning Information* (1990) — layering, small multiples.
- Alan M. MacEachren, *How Maps Work* (1995) — representation & cognition.
- Cynthia A. Brewer — ColorBrewer and *Designing Better Maps*; sequential/diverging/
  qualitative schemes, colorblind safety.
- Robert McMaster & K. Stuart Shea, *Generalization in Digital Cartography* (1992) and
  Shea & McMaster (1989) — the generalization operators.
- Yan, X., Yang, M. & Ai, T. (2025), "Deep learning in automatic map generalization:
  achievements and challenges," *Geo-spatial Information Science*, 28(6), 2905–2926,
  DOI [10.1080/10095020.2025.2480815](https://doi.org/10.1080/10095020.2025.2480815)
  (Open Access, CC-BY) — state of the art in automating generalization.
- N. A. Tissot — the indicatrix. J. G. Lehmann — slope hachures. Gerardus Mercator,
  Arthur Robinson, Oswald Winkel — the named projections.
- Biland & Çöltekin (2017), *CaGIS* — empirical light-direction / relief-inversion study.
