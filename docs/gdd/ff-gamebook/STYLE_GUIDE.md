# STYLE GUIDE — `ff-gamebook`: *The Grey Tithe* — Art Direction & Audio Design

> **Companion to:** [`GDD.md`](GDD.md) · Closes benchmark **gap #8** (art bible + audio were sourcing plans, not *direction*).
> **Owner:** art lead + audio lead (lead supervises) · **Status:** DRAFT for Jesus sign-off.
> **Default art lane (locked, GDD §0):** **`veritas-gamebook`** — FF-era ink+watercolor book plates, ~90% Jesus-approved, ship-ready no-LoRA. **Variant to compare:** `sir-brante` (sepia engraving, COULD-tier). **Maps:** `sorcery-inkle` ink-wash.
> **Related canon:** world, cast, and the ledger motif in [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md); screens in [`WIREFRAMES.md`](WIREFRAMES.md); asset sourcing/reuse ladder in GDD §7; live asset wiring + credits in GDD §10a/§11.

This is a **style guide**, not a shopping list. GDD §7 already says *where assets come from* (the reuse ladder). This says *what they must look and sound like* so that a reused monster icon, a generated section plate, and a purchased UI frame all read as **one book**. The governing law is Planescape's rule: don't render the generic thing — render the world's version of it. In *The Grey Tithe* the world's version of everything is **an account being kept**: cold, ledgered, owed.

---

# PART 1 — ART DIRECTION (`veritas-gamebook`)

## 1.1 The look, in one paragraph

*The Grey Tithe* looks like a **water-damaged 1980s fantasy gamebook recovered from a flooded archive** — confident black pen linework over restrained, cold watercolor washes on aged paper, printed a little too dark. It is the classic illustrated-gamebook interior plate: a single arrested dramatic moment, high-contrast, black-and-white-*first* with color used sparingly and deliberately. The palette is bog-cold and ash-grey; the one recurring intrusion of an unnatural hue is the **grey ledger-script** — the verdigris-ash writing that crawls over the taken. The page itself is a character (INSPIRATION §3.4, "the page is sacred"): parchment ground, generous margins, the plate framed like a woodcut pressed into the paper.

## 1.2 Art pillars

1. **Ink first, wash second.** The drawing must survive in pure black-and-white. Color is seasoning, never the meal — a plate that only works *because* of color is off-model.
2. **One moment per plate.** Each illustration freezes a single, legible dramatic beat (the toll demanded, the door opening, the blow landing) — not a busy scene. Silhouette reads at thumbnail size.
3. **Cold, owed, kept.** Every image should feel *accounted for* — damp, grey, counted. Warmth is rare and therefore meaningful (a lantern, a hearth, Vessel's eyes).
4. **The plate belongs to the page.** Art is composed for the reading column, framed as a book plate, never bleeding edge-to-edge like a splash-screen. Chrome never covers prose (WIREFRAMES §Reading View).
5. **Consistency over spectacle.** A slightly plainer plate that is *on-model* beats a gorgeous one that breaks the book. Style-anchor discipline (GDD §14 "art inconsistency across plates").

## 1.3 Palette

Color is a **restricted, named** set. Artists pick washes from this list; they do not free-pick. All values approximate — the wash is transparent, so on-paper appearance shifts cooler/greyer.

| Role | Name | Approx hex | Use |
|---|---|---|---|
| Ground (default) | **Tallow Parchment** | `#E7DCC2` | Aged paper ground for plates & reading view |
| Ground (dark theme) | **Drowned Vellum** | `#171A18` | Dark-mode page; plates invert to warm-grey line on near-black |
| Line / ink | **Bog Ink** | `#14110D` | Primary linework — near-black, warm, never pure `#000` |
| Shadow wash | **Peat Umber** | `#4A3F2E` | Transparent shadow / cross-hatch reinforcement |
| Cold neutral | **Fen Grey** | `#7C8683` | The dominant world tone — fog, stone, water, dead sky |
| Cold deep | **Slate Drown** | `#3A464A` | Deep water, night interiors, the Cathedra dark |
| **Signature accent** | **Ledger Verdigris** | `#6E8F7A` → ash `#9AA69B` | **RESERVED** for the grey ledger-script, the Tithe-taken's marks, the Assessor's glow. The one unnatural hue. Never used decoratively. |
| Rare warm | **Tallow Flame** | `#C88A3E` | Lanternlight, hearth, Vessel's eyes, victory — used *sparingly* as the emotional counterpoint |
| Blood / danger | **Old Arrears Red** | `#8A2E24` | Dried-blood red for wounds, seals, the "paid in blood" toll — desaturated, never comic-book crimson |

**Discipline:** a plate uses **Bog Ink + Fen Grey + at most two other washes**. Ledger Verdigris and Tallow Flame are *events*, not defaults. If a plate needs three warm colors to work, it's the wrong plate.

**UI themes (GDD §6):** the reading view ships four grounds — **Parchment** (Tallow Parchment, default), **Paper** (cleaner cream, higher contrast for accessibility), **Sepia** (leans toward the `sir-brante` warmth), **Dark** (Drowned Vellum). Plates must remain legible on all four; deliver plate art with a transparent/knockout background variant so it composites over any ground, and verify the line reads on Dark (invert to warm-grey, don't just place black-on-black).

## 1.4 Linework & wash (the technique spec)

What makes a plate **veritas-gamebook** and not generic fantasy art:

- **Line weight:** confident, variable-weight pen line — heavy on contact shadows and silhouette edges, tapering to fine on interior detail. A single consistent "nib" feel across the book. No airbrushed soft edges; no digital lens-flare/bloom.
- **Shadow = hatching, not fill.** Shadow is built with **cross-hatching and parallel line** in Bog Ink, optionally reinforced with a Peat Umber wash — *not* solid black fills or soft gradients. This is the single strongest "old gamebook" tell. Deepest darks may go solid, but the transition is hatched.
- **Wash = limited & transparent.** Watercolor is thin, cold, and pooled in a few zones (sky, water, a robe), leaving paper showing through as highlight. Never fully opaque; never covering the line. Think 2–4 wash passes, edges allowed to bleed slightly into the paper.
- **Texture:** the plate carries **paper grain and light foxing/water-stain** at the edges — it's a recovered book. Subtle; never so heavy it fights legibility.
- **Anti-tells (off-model):** smooth cel-shading, anime eyes, neon/saturated color, photobashed realism, symmetrical AI "melty" hands, glossy rendering, lens effects. Any of these = reject.

## 1.5 Composition

- **One focal beat.** Frame the single moment the section is *about*. If the reader can't name the drama from the silhouette alone, recompose.
- **Silhouette-first.** Design the black shape before detail; it must read at 1 inch (thumbnail in the Gallery / map nodes).
- **High contrast, low key.** The Grey Tithe is a dark book — most plates sit in the lower value range with one bright relief (lantern, pale face, ledger glow). Value contrast, not color contrast, carries the read.
- **Negative space & the frame.** Leave breathing room; the plate is inset in the parchment page with a thin ruled or hand-drawn border (a faint ledger-rule motif is on-brand). Do not bleed to the screen edge — it's a *book plate*.
- **Plate placement in the column (WIREFRAMES §Reading View):** default = full-width plate **above** the section prose (the "page opens on the image" beat), tap-to-expand to full screen. Inline vignettes may sit within/after prose for minor beats.
- **Full-plate vs vignette:**
  - **Full plate** (≈20–30 across the adventure) — the memorable set-pieces: BN1 toll, each tithe-gate, Isolde, the Reckoner, deaths. These carry the book.
  - **Vignette** (smaller spot illustration, line-only or one wash) — item finds, minor NPCs, atmosphere. Cheaper, faster, and *most* sections get one of these or none, exactly like the classic B&W tradition (INSPIRATION §3.2).

## 1.6 On-model rules (character/monster consistency)

The load-bearing risk (GDD §14) is plates drifting apart. Every recurring subject gets a **style-anchor sheet** (canonical reference held by `style-anchor`); every new plate of that subject is checked against it before it enters the manifest. On-model rules below are **binding**.

**The grey ledger-script (the world's signature motif — get this right everywhere it appears):** angular, cramped **columnar writing** — numbers, tally-marks, and a debased liturgical script — rendered in **Ledger Verdigris**, always reading *top-to-bottom in columns* like an account page, never as decorative runes or magic-circle glyphs. It crawls *along* forms (following a limb, a jaw, a doorframe) as if the surface were being audited. Drawn with a **finer nib** than the subject's outline so it reads as "written on" not "part of." Consistency rule: ledger-script density = corruption depth (a lightly-marked survivor vs. Isolde, nearly covered).

| Subject | On-model anchor (silhouette / costume / tell) | Never |
|---|---|---|
| **The Hero (recurring)** | Traveler's silhouette: hooded oilcloth cloak, a satchel/ledger-case at the hip (the sin-eater's kit), practical boots. Face kept partial/shadowed so the *player* projects onto it. Consistent cloak-hem shape is the anchor. Uses `nxdv_knight` subject discipline where a defined hero is shown. | Fixed detailed face; ornate hero-fantasy armor; heroic power-pose |
| **The Reckoner (Ambrose Vael)** | Tall, stooped, **High Ledgerkeeper's robe** hung with account-tags and a hanging brass balance; a stamp/seal at the belt; face gaunt, courteous, *tired*. Read as a grieving clerk, never a demon-lord (NARRATIVE_BIBLE cultural-risk note). Silhouette anchor: the hanging balance + tag-fringed hem. | Horns, glowing red eyes, muscular lich; anything that mocks his grief |
| **Isolde, "the Unpaid"** | A girl of twelve in a decade-old funeral shift; **ledger-script densest of anyone**, crawling over half her skin; posture wrong (too still, or hovering-slack). Emotional core — pitiable, not gory. Anchor: the shift + the script-coverage ratio. | Zombie-child horror clichés; excessive gore; making her scary-first instead of sad-first |
| **The Grey Assessor** | Faceless, robed toll-wraith — **no visible face inside the hood**, robe hem dissolving into ledger-script and fog; carries a tally-stave. Manifests, not stands. Glows faint Ledger Verdigris. Recurs 3× escalating (more solid each time). Anchor: the empty hood + tally-stave. | A defined face; a scythe (not Death, an *auditor*) |
| **The Tithe-taken (risen dead)** | Ordinary Verge folk (fisher, miller, child) killed by the Tithe, marked with ledger-script, moving *purposefully* (they're collecting, not shambling-hungry). Grief in the pose. Individual enough to read as *people*. Anchor: everyday dress + marks + the "counting" gesture. | Generic rotting-zombie horde; interchangeable ghouls |
| **Vessel (the ledger-hound)** | Big grey mastiff, lightly ledger-marked but eyes warm **Tallow Flame** — the one debt kept by love. Loyal, wary posture. Anchor: the warm eyes against grey coat = the whole game's thesis in one image. | Hellhound / demon-dog; snarling menace |

**Reused & library assets are held to the same anchors (GDD §7 reuse ladder, §10a wiring):** an icon or monster from the purchased packs must be **restyled to the anchor** before shipping — recolored to the palette, line-unified toward Bog Ink hatching, ledger-script added where lore demands (rung-3 asset, rung-5 restyle). A raw, off-palette pack asset does not ship. Every plate/vignette/icon — reused, restyled, or generated — is **registered in the `asset-manifest` with provenance** (source pack / LoRA / style / license) and bound by stable slot ID so Jesus can hot-swap from the Studio with no code edits (GDD §10a). The on-model check is a gate *before* manifest entry.

## 1.7 Cover / death / victory treatment (the special plates)

- **Cover / title key art (WIREFRAMES §Title):** the one plate allowed the most color depth — a wide, brooding establishing image: Harrowfell under fog, the drowned Cathedra spire, or the Grey Assessor at the toll-bridge, hero small against it. Painterly wash over ink, Ledger Verdigris used once as the eye-hook. Must carry the studio title lockup + the NoxDev shell (GDD §6.1). Delivered with a still + a subtly-animated (drifting fog / lantern flicker) variant for the menu background.
- **Death plates ("your account is closed"):** deaths are *content*, not fail-states (INSPIRATION §3.2, NARRATIVE_BIBLE B6#5). Each major death gets its own somber vignette; the shared Death Screen frame uses **Old Arrears Red** sparingly (a stamped "PAID" seal motif over the scene) and the deepest low-key value range. Evocative, never cheap or comic.
- **Victory plate (QUITTANCE true ending):** the book's one moment of genuine warmth — Tallow Flame permitted to dominate for the only time (dawn over the Verge, Isolde at rest, Vessel at the hero's side if befriended). The pyrrhic/dark endings (B6 #2/#3) get *cold* victory plates — technically "won," visually unresolved (grey, one guttering flame). The art must **tell the player which ending they got** at a glance.

## 1.8 Variant lanes

- **`sir-brante` variant (COULD-tier, GDD §13):** a **sepia line-engraving** treatment — heavier cross-hatch, monochrome sepia (lean on Peat Umber / Tallow), no watercolor wash, an antique broadsheet/woodcut feel. Produced as a **compare set on 3–5 key plates** (cover, Isolde, the Reckoner) so Jesus can A/B against veritas-gamebook. Not a full second art pass unless promoted from COULD → SHOULD. Ships as a selectable art-mode toggle if approved.
- **`sorcery-inkle` ink-wash maps (Map/Progress screen, WIREFRAMES §Map):** the **map lane only** — looser, hand-drawn ink-and-wash cartography (the Sorcery! travel-map feel) for the optional travel-map mode and the parchment auto-map styling. Warmer, sketchier line than the plates; reads as "the hero's own drawn map" (INSPIRATION §3.1(10)). Keep the plate lane and the map lane visually distinct on purpose.

---

# PART 2 — AUDIO DESIGN

## 2.1 Audio pillars

1. **Diegetic where possible.** Prefer sounds that live in the world — a real page turning, dice on wood, a lantern's hiss, water dripping in the Cathedra — over abstract UI blips. (INSPIRATION §3.4 "diegetic beats generic menus.")
2. **The honest-dice sound is sacred.** The dice roll is the game's tactile ritual and its promise of fairness (GDD §3, §14 "digital-dice distrust"). It gets bespoke, satisfying, *unfaked* audio and always plays on a real seeded roll — no silent fudging. This is the one sound we never cut for performance.
3. **Silence is an instrument.** A grief-and-dread book earns its scares with restraint. Reading is mostly ambience + near-silence; music arrives to *mean* something.
4. **The page is sacred, and quiet.** Audio never fights the prose. Music under reading is low, slow, and duckable; TTS narration always wins the mix.
5. **Volume-respecting & accessible (GDD §11).** Every cue routes through a labeled bus with a user volume slider; reduced-motion/reduced-audio settings honored; nothing is audio-only critical (dice results are shown, not just heard).

## 2.2 Music cues per state

Sourced from the fantasy/orchestral library (GDD §7: `fantasy_rpgmusicpack`, `arcaneechoesorchestralchiptunemusiccollection`, `shadowwardarkfantasyorchestralmusiccollection`), selected/edited to the cold-gothic tone. All transitions **crossfade** unless a **stinger** is specified.

| State / screen | Intent (mood) | Instrumentation (from library) | Adaptive / transition rule |
|---|---|---|---|
| **Title / Main Menu** | Brooding invitation; the Verge waits | Low sustained strings, distant solo cello, a far bell; fog ambience bed under | Loops; page-turn sting on menu nav; ducks under button SFX |
| **Roll-Up (character creation)** | Hushed anticipation, fate not yet cast | Sparse harp/celeste over a held drone | Rises subtly per stat rolled; small hopeful/rough sting keyed to roll quality (color-coded, GDD §6.3) |
| **Explore / Reading (default)** | Cold dread, kept quiet; the page breathes | Very low drone + Harrowfell ambience (see below); minimal melody | Near-silent bed; music is mostly *ambience*. Rises to Tension on state flags |
| **Tension** (Assessor near, threat flagged) | Something is counting you | Rising bowed-bass swell, ticking/tally percussion (the ledger motif), breath | Layer *on top of* explore bed (vertical stacking); resolves to combat or back down |
| **Combat** | Grim, measured violence — not heroic | Driving low strings + taut percussion; restrained brass | **Stinger on combat start**; loops per round; ducks hard under each dice resolution (§2.4) |
| **Boss — the Reckoner** | Tragic grandeur, not evil-overlord | The main "ledger" theme, full but mournful; a lone treble line = Isolde's motif woven in | Own track; a recurring **Isolde motif** (a simple, sad music-box/celeste phrase) threads title→Isolde→finale as the emotional throughline |
| **Death ("account closed")** | Somber finality; deaths are content | Low tolling bell + falling string; brief | **Death sting** on trigger, then a short low pad under the Death Screen. Never comedic |
| **Victory — QUITTANCE (true)** | The one warm release; grief settled | Strings resolve to a *major* for the only time; the Isolde music-box plays *whole* and at rest | **Victory sting**; the sole warm cue in the game (mirrors the warm victory plate §1.7) |
| **Victory — pyrrhic/dark endings** | Hollow, unresolved | Cold ending pad, the Isolde motif *unfinished* / detuned | No triumph; visually + sonically signals the lesser ending |
| **Harrowfell / town ambience** | A dying settlement at dusk | Wind, distant water, a single struggling hearth-crackle, far crows | Ambience bed under any town storylet; Ferrant's stall adds a low market murmur |
| **The Cathedra (Act III ambience)** | Drowned, vast, counted | Dripping water reverb-tail, deep sub-drone, faint choral breath | Replaces town ambience on descent (BN2); the ledger-script whisper (§2.3) rises near the taken |

## 2.3 SFX list / families

All SFX from the library packs (GDD §7: `combatsoundsbundlecollection`, `interfacesfxvol2`) plus a few bespoke signature sounds. Bus in **[brackets]**.

| Family | Cues | Notes |
|---|---|---|
| **Dice (sacred)** `[SFX]` | dice shaken in hand, tumble, **physical pips landing on wood**, settle | Bespoke, layered, *satisfying*; always on a real roll; supports shake-to-roll (GDD §6.6). The one sound we never fake or cut. Quick/auto mode plays a shortened version, never a silent skip |
| **Page / navigation** `[UI]` | page-turn (forward/back), bookmark set, section-arrive whoosh | Diegetic paper; page-turn is the primary transition sound (crossfade companion) |
| **Combat** `[SFX]` | sword hit (flesh/armor variants), parry/clash (tie = no damage → distinct "parried" ring), wound-taken thud, enemy-defeated, escape (a parting blow) | Round resolution maps 1:1 to audio: higher total → hit sound on the loser; tie → parry ring |
| **Luck / test** `[SFX]` | Test-your-Luck chime → **Lucky** (rising) / **Unlucky** (falling) resolution; skill/stamina test tick | Distinct from combat dice so the ear learns the ritual |
| **The Grey Assessor (signature)** `[SFX]` | toll-manifestation (a cold reverse-swell + a single struck tally), "assessment" drone, dispersal | Recurs 3× (§NARRATIVE_BIBLE B2); grows more solid/present each manifestation |
| **Ledger-script whisper (signature)** `[Ambience]` | a dry, overlapping whisper of numbers/tallies, near the Tithe-taken & Isolde | Low, uncanny; densities track the visual ledger-script density; never intelligible |
| **Consumables / sheet** `[UI]` | eat Provisions (+STAMINA), drink potion (restore chime), item pickup, equip, gold clink, codeword-gained (a quiet "noted in the ledger" stamp) | The gold-clink & stamp reinforce the economy motif |
| **Stings** `[SFX]` | combat-start, death, victory (true vs. hollow variants) | Short, keyed to state transitions (§2.2) |
| **Ambience beds** `[Ambience]` | bog wind, dripping Cathedra, hearth, crows, market murmur | Looping, per-location (§2.2) |

## 2.4 Mixing

**Bus structure:** `Master → { Music, SFX, Ambience, UI, VO }`. Each bus has an independent user volume slider in Options → Audio (GDD §6.1); settings persist and are respected everywhere (GDD §11 "volume-respecting").

**Ducking rules:**
- **Music ducks under dice & combat resolution** — when a roll animates/resolves, Music (and Ambience) drop ~6–10 dB so the dice and hit/parry SFX read cleanly, then recover. The roll is the moment; nothing competes with it.
- **VO/TTS ducks Music, Ambience, and non-essential SFX** whenever narration is speaking (accessibility priority, §2.5). Dice SFX still punch through at reduced level so the ritual isn't lost.
- **Stingers** are exempt from ducking (they *are* the transition).
- **Ambience** sits low and constant; it never masks prose or TTS.

**Targets:** normalize music/ambience to a quiet integrated loudness (reading is a low-key experience); keep stings and dice with enough transient headroom to feel tactile without clipping. Reduced-audio accessibility setting attenuates stingers/ambience and can disable the ledger-whisper for sensory-sensitive players.

## 2.5 VO / TTS

- **Accessibility TTS narration (GDD §6, first-class):** every section's prose, every choice label, and combat/roll outcomes can be read aloud by TTS, driven from the same content the reader sees. Respects the reading settings (it reads what's on the page, in order: section number → prose → illustration alt-text → choices). Routed to the **VO bus**; ducks the mix (§2.4).
- **Never blocks input.** TTS is asynchronous — the player can choose, roll, or advance at any time; starting an action **interrupts/stops** current narration cleanly. No modal "wait for the voice." This is a hard rule (respects the speedrunner and the screen-reader user alike, INSPIRATION §3.4).
- **Alt-text for plates:** every illustration ships with a short descriptive alt line (also used by external screen readers) — on-model, spoiler-safe.
- **Optional monster-voice / AI-DM color (GDD §9b):** the dual DM may add spoken color (the Reckoner's courteous murmur, the Assessor's plural toll, Isolde's layered child-then-account voice per NARRATIVE_BIBLE A4). **Engine-authoritative:** VO/AI voice is *flavor only* — it never announces or alters dice, STAMINA, LUCK, or state (those come from `apply_delta`, GDD §3/§9). Off by default; falls back silently to text/TTS if the LLM/voice stack is unavailable.

## 2.6 Credits & attribution (required — GDD §10a, §11)

A **Credits screen** (reachable from Title and Pause) is first-class, not an afterthought, and is a Definition-of-Done checkbox (GDD §11). It must credit **everything not wholly original**, with licenses honored:

| Category | What to credit | Format |
|---|---|---|
| **Visual asset packs** | Every purchased/CC pack drawn from (icons, monsters, UI, fonts — GDD §7) | Pack name · creator/studio · license (e.g. CC0, commercial) · link where required |
| **Generated art / LoRAs** | `veritas-gamebook` pipeline, any subject LoRA (`nxdv_knight`), base model | Style/LoRA name · that it is NoxDev-generated · base model + its license |
| **Music** | Every track/pack used per state (§2.2) | Track/pack · composer/creator · license |
| **SFX** | SFX packs & any bespoke signature sounds (§2.3) | Pack · creator · license |
| **Fonts** | Body serif, display, dyslexia-friendly option | Font name · foundry · license (OFL/CC0 preferred) |
| **Tools** | Godot, `nox_if_engine`, `nox_ui`, audio/image pipelines, TTS engine | Tool · attribution where license requires |

**Rules:** the credits list is **generated from the `asset-manifest` provenance** (GDD §10a) — since every slot is registered with source/license, the Credits screen is populated from that manifest so it can never drift out of date as assets are swapped from the Studio. No asset ships without a manifest entry; therefore no asset ships uncredited. Any license requiring specific wording or a link renders exactly as required.

---

## Cross-references

- **Canon it depicts:** [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md) (world, cast, ledger-script motif).
- **Screens the art/audio live in:** [`WIREFRAMES.md`](WIREFRAMES.md).
- **Sourcing & reuse ladder / live wiring:** [`GDD.md`](GDD.md) §7, §10a.
- **DoD (art/audio/credits checkboxes):** [`GDD.md`](GDD.md) §11.
