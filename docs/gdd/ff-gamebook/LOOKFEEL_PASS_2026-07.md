# LOOK & FEEL PASS — ff-gamebook flagship (2026-07)

> **Why:** Jesus played the build and judged the presentation below the reference games:
> *"the character roll up is very shallow… the title boxes look bad, the actual pages should be
> something besides just a bland brown color, and the images are barely seen — the resolution
> doesn't even change or is adjustable… The roll your hero was odd and not very good, the combat
> page looks bad still, the section map is eh, ok… Even the FFC one has a better look and feel
> though with the book and pages and the ability to have your sheet there with you… no maps
> integrated like Sorcery."*
>
> **References studied** (real screenshots inspected, notes below): **Fighting Fantasy Classics**
> (Tin Man 2018), **inkle's Sorcery!** (2013-16), **Veritas Tales: Witch of the Dark Castle**
> (Nishimura 2026 — the source of our `veritas-gamebook` idiom), **The Life and Suffering of
> Sir Brante** (2021). Governing doc: `STYLE_GUIDE.md` (palette, plate rules, `sorcery-inkle`
> map lane) — this pass implements what it already mandates but the build wasn't delivering.

## What each reference actually does (visual summary)

| Reference | The signature move we take |
|---|---|
| **FF Classics** | The play space is a photographed open **book on a near-black desk**: warm aged parchment, edges vignetted to brown-black, section number top-right in big serif numerals. The **Adventure Sheet is a tilted paper card docked bottom-right**, sliding in over the page — sketched ink boxes, circled stats (current large, initial small below). Combat is a **pinned parchment card** with the two totals written big in red hand numerals, real dice on the page. The page dims for dark scenes while cards stay lit. |
| **Sorcery!** | The ground IS a hand-drawn ink+watercolor **travel map**; the hero is a **tabletop miniature** moving node-to-node; destinations are labelled flags; the traveled path is marked. **Stats hang as torn prayer-flags along the top edge** — the sheet-at-hand without a sheet. Story arrives on torn paper strips stitched together. |
| **Veritas Tales** | **Study-desk framing**: book on the left, the filled-in character sheet lying on wood to the right with pencil + dice as props. **Plates are LARGE** — a painting in a thin double-rule gold frame taking near half the page. Dice tumble **onto the page itself** and the math is printed beneath in book type ("4 + 2 (+8) = 14"). Mutable numbers are **pencil-handwritten**; printed chrome is engraved caps. |
| **Sir Brante** | Ruthless typographic discipline: one serif family, **letter-spaced caps headers over thin diamond-tipped rules** as the universal panel/section device; parchment + black ink + ONE accent color; chapter interstitials as composed spreads; consequence sheets as torn paper laid over the book. |

## Per-screen treatment mapping (what borrows what)

| Screen | Treatment | Borrowed from |
|---|---|---|
| **All screens — ground** | Real paper: an aged-parchment texture asset (`assets/ui/paper_page.png`, bound as `ui/paper_page`) with fibre grain, foxing and toasted ragged edges, laid as a **page sheet on a near-black desk** with a stacked page-edge + soft shadow so it reads as a physical book page, not a flat fill. Dark reading theme = Drowned-Vellum-tinted paper, never flat color. | FFC (book-on-desk, vignetted paper), Veritas (desk frame) |
| **All screens — panels/titles** | The flat rounded brown boxes are replaced by the **engraved treatment**: letter-spaced small-caps display type over **thin double rules with a center diamond ornament**; framed cards get a double-ruled border with corner ticks (the Adventure Sheet's own `_Boxed`/`_TitleRule` idiom promoted into FFUI and used everywhere: dice card, options, map, combat, popups). One accent per panel, from the STYLE_GUIDE named set. | Brante (diamond-tipped rules, spaced caps), Veritas (double-rule frames), our own sheet |
| **Main menu** | Cover plate full-bleed behind a dark vignette; title in tracked engraved caps with rule+diamond under; menu entries as parchment plate-buttons (engraved rule border, not default grey), the amber web-app accent bar deleted. | FFC shelf mood, Brante typography |
| **Reading view** | The page opens on the image (STYLE_GUIDE §1.5): **plate LARGE above the prose** in a thin double-rule frame on a paper mat, ~full column width, click-to-expand lightbox; prose in the illuminated-cap manuscript setting below; section number as a printed **folio** top-right of the page. Choices as ruled parchment entries. | Veritas (large framed plate), FFC (folio numeral, page feel) |
| **Sheet-at-hand** | A **docked, slightly tilted sheet-card tab** pinned at the right edge of the reading page: SK / ST / LK written in the player's hand (current large, initial small — FFC's circled-stat read), gold + provisions beneath; clicking it slides out the full Adventure Sheet. Always visible while reading. | FFC (docked tilted sheet card), Sorcery! (stats always worn on the edge of the view) |
| **Roll-up** | A **ritual, not a form**: the blank Adventure Sheet card lies on the desk; each stat is thrown **one at a time** through the 3D tray with a printed stage line ("The dice will write your SKILL…"), the value **penned into the sheet's INITIAL/NOW boxes** in handwriting with the quality read; the starting kit is laid out as an illustrated row (icon + handwritten ledger line); the potion is an **in-fiction choice** — a paragraph of flavor prose and three labelled flasks. Begin gates on the ritual completing. | Veritas (pencil-into-printed-sheet fantasy, dice on the page), FFC (auto-filled sheet), Brante (staged chapter framing) |
| **Combat** | **The fight is a page of the book**, not a dark modal: paper ground stays; foe presented as a **portrait plate in the engraved frame with a name banner**; both combatants get **sheet-strips** (the printed INITIAL/NOW box idiom, foe STAMINA scratch-down); the **3D dice tray is inline on the page** with the round's math printed beneath it in book type; the round log is a **ruled ledger written in handwriting**. The dice popup remains only for Luck tests. | FFC (combat card pinned to the page, page stays visible), Veritas (dice on the page + printed math), our sheet (scratch numbers) |
| **Map** | **Sorcery-style journey map**: a hand-drawn ink+watercolor map surface (per-book plate via manifest slot `plate/map`, else a parchment auto-chart in the `sorcery-inkle` lane), the adventure's sections as ink landmarks with their **titles** hand-lettered, the traveled path drawn as a dashed ink route, the party as a **red wax marker** at the current section, unvisited branches as faint sketch marks, deaths as ink crosses. Full-screen page, list alternative retained. | Sorcery! (the living travel map, path + marker), Brante (engraved cartography + banner labels) |
| **Options** | Engraved card with Brante-style section rules; adds a **Display tab**: window size **1280×720 / 1920×1080 / 2560×1440** + fullscreen + v-sync (all actually applied via DisplayServer), and **Illustration plates: Large / Medium / Small** (reading-view plate height). | Brante (typography), the critique (resolution + plate size must be adjustable) |
| **Dice overlay** | The luck/skill-test card becomes a **pinned parchment card** (engraved frame, corner ticks) instead of a grey rounded box; math printed beneath the tray in book type. | FFC (pinned combat card), Veritas (printed math) |

## Rules kept intact (non-negotiables)
- ff-2d6 rules core stays authoritative; the UI never rolls its own dice (3D tray performs the seeded result — the 165954b default-experience fix is preserved and re-verified by `_probes/default_run`).
- All probe-driven button texts unchanged: NEW ADVENTURE, Grey Tithe, Begin this adventure, Potion of Fortune, Begin the descent, Test your Luck, Tap to continue, Attack, Sheet, ✕, etc.
- Asset binding stays STABLE-ID through AssetBinder (`ui/paper_page`, `plate/map`, …) so the Studio can hot-swap every surface.

## New assets (reuse-first ledger)
| Asset | Source | Rung |
|---|---|---|
| `assets/ui/paper_page.png` | Derived deterministic parchment (fbm grain + fibre + foxing + toasted ragged edge, on-palette Tallow/Umber) — ZIT txt2img attempts produced unusable flat-texture output; derivation script kept in repo docs | derive |
| `assets/plates/generated/map.png` (grey-tithe `plate/map`) | ZIT (z-image-turbo) ink-and-wash journey map, `sorcery-inkle` lane prompt, no LoRA | generate |
| Ornaments (rules, diamonds, corner ticks, wax marker) | Drawn in-code from the sheet's `_Boxed`/`_TitleRule` idiom (already shipped) | reuse |
| Frames/fonts/icons/portraits | Existing reused kit (Kenney frames, OFL fonts, 496 RPG icons, owned portrait packs) | reuse |

## Verification
Windowed default run (player-shaped): capture `_probes/shots/lookfeel_menu.png`,
`lookfeel_reading.png` (large plate + sheet dock), `lookfeel_rollup.png`, `lookfeel_combat.png`,
`lookfeel_map.png`, `lookfeel_sheet.png` — judged against the four reference screenshot sets.
`default_run` (3D-dice default guard) + qa/flow/rules/library probes must stay green.
