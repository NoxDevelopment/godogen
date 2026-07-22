# VTT Tooling Gaps — what d20/Fantasy Grounds/Roll20/Foundry ship vs what our Studio has

Jesus's note: *"d20 — a ton of tooling we don't have but should."* This doc is the
scan. Our north star is a **slick AI-powered narrative Virtual Tabletop** (Roll20
feature-parity + illustrated-gamebook RPGs — see MEMORY "vtt-narrative-northstar").
That means the map work in this skill ([BATTLEMAP_ASSETS.md](BATTLEMAP_ASSETS.md),
[MAP_REFERENCE_GALLERY.md](MAP_REFERENCE_GALLERY.md)) is *one component* of a larger
tabletop product — so we need to know the whole tooling surface a serious VTT ships,
and honestly flag where we're missing it.

**The four benchmarks:**
- **Foundry VTT** — the modern feature ceiling (best perception/lighting engine,
  deepest JS scripting, ~5,700 modules). The bar for depth.
- **Fantasy Grounds (Unity)** — the automation king (deepest 5E/PF2 effects engine +
  best combat tracker); went **free Nov 2025**. The bar for rules automation.
- **Roll20** — mass-market browser SaaS; strong licensed content, automation
  intentionally thin (Pro-only API). The bar for zero-install accessibility.
- **d20PRO** — legacy Java app, historic strength in **auto-combat + auto-initiative**;
  reads maintenance-mode now. The cautionary tale (great engine, dead ecosystem).

> **Read this as a checklist, not a mandate.** A *narrative-first* VTT can de-emphasize
> the tactical grid — but "narrative" does not excuse missing table-stakes (a combat
> tracker, dice engine, journals, tokens). Parity on A–F below is the floor; our EDGE
> (G) is where we win.

---

## The capability matrix — bar vs Nox Loom / Studio

Legend: **✅ have** · **◐ partial / planning-only / not-live** · **✗ gap**.
"Have" is judged against the live Studio (`apps/web`) as of 2026-07.

### A. Map & spatial layer
| # | Capability | Bar (who) | Nox Loom status |
|---|---|---|---|
| A1 | **Dynamic lighting** — walls w/ independent light/sight/sound, one-way walls, terrain walls | Foundry | ◐ `battleMap.ts` models walls/doors as geometry; **no runtime light/LoS engine** |
| A2 | **Interactive doors** — open/close/lock/secret, animated | Foundry, Roll20 | ◐ doors exist as data (`door`/`portcullis`/`secret`); not openable at a live table |
| A3 | **Per-token vision / detection modes** — darkvision, tremorsense, truesight | Foundry | ✗ |
| A4 | **Fog of war** — manual brush + auto vision reveal + persistent exploration | Foundry | ✗ |
| A5 | GM-only layer / hidden objects | all | ◐ blueprint/GM styling exists; no live GM-only reveal |
| A6 | **Measurement** — ruler, waypoints, elevation/movement-cost aware | Foundry v13 | ✗ (grid coords only) |
| A7 | **AoE templates** — cone/circle/line/rect, grid-snap, rotate | all | ✗ |
| A8 | **Grid** — square + hex (+ iso), snapping | all | ✅ square **and** hex overlays w/ battle coords (`battleMap.ts`) |
| A9 | Global illumination / magical darkness / light color+animation | Foundry | ✗ |

### B. Combat & rules
| # | Capability | Bar | Nox Loom status |
|---|---|---|---|
| B10 | **Initiative / turn tracker** — order, round count, defeated toggle | d20PRO/FG | ✗ **(the headline gap Jesus flagged)** |
| B11 | **Combat tracker** — HP/temp/wounds cols, drag-on conditions | FG | ✗ |
| B12 | Auto-initiative roll + turn notifications | d20PRO/FG | ✗ |
| B13 | **Effects/automation engine** — auto dmg w/ resist/vuln, saves, concentration, condition apply+expiry | FG + Foundry-PF2e | ◐ ruleset builder (`rulesets.ts`) defines rules; **no live effects resolver** |
| B14 | Targeting (attacker→target linkage) | FG | ✗ |
| B15 | Status/condition markers w/ real rules behavior | FG | ✗ |

### C. Character & content
| # | Capability | Bar | Nox Loom status |
|---|---|---|---|
| C16 | **Per-ruleset character sheets** — auto-calc, roll-from-sheet | all | ◐ Ruleset Builder + `RulesetEditor` define sheets/rules; no live roll-from-sheet table |
| C17 | Guided character builder (Charactermancer/Wizard) | Roll20/FG | ◐ NPC gateway / npc-bake generate characters; no player-facing build wizard |
| C18 | **Compendium** — searchable licensed rulebooks, SRD | FG (3,000+ titles) | ◐ Knowledge Base + GDD Library + rulesetPresets; not a runtime stat-block compendium |
| C19 | Drag-drop stat block → token + linked sheet | all | ✗ |
| C20 | Import bridges (Hero Lab, PCGen, D&D Beyond) | d20PRO | ✗ |
| C21 | Official licensed content pipeline (WotC/Paizo) | Roll20/FG | ✗ (we generate original IP instead — deliberate) |

### D. Dice, scripting, extensibility
| # | Capability | Bar | Nox Loom status |
|---|---|---|---|
| D22 | **Dice notation** — inline, keep/drop/explode, roll queries | all | ◐ ruleset engine has dice rules; **no live chat dice roller** |
| D23 | 3D physics dice w/ theming | Dice So Nice | ✗ |
| D24 | Macros — chat + full scripting (JS/Lua), permissioned | Foundry/Roll20/FG | ◐ agent pipeline is our automation model; no player macro layer |
| D25 | Roll templates / styled output | Roll20/FG | ✗ |
| D26 | Full programmatic API + hooks for modules | Foundry | ✗ (we have server actions, not a public module API) |
| D27 | Rules-modding / house-rule editor | d20PRO/FG | ✅ **Ruleset Builder** (`rulesets.ts` + presets + validator) — a genuine strength |

### E. Narrative, presentation & assets
| # | Capability | Bar | Nox Loom status |
|---|---|---|---|
| E28 | **Journals/wikis** — multi-page, cross-link, permissions | Foundry | ◐ Worldbuilder / KB / campaigns hold lore; not a live shared journal w/ reveal |
| E29 | **Handouts + "Show Players" reveal-on-cue** | all | ✗ (live reveal); content authoring ✅ |
| E30 | Story/campaign log | all | ◐ `campaigns.ts` |
| E31 | Card decks / hands / piles | Foundry/Roll20 | ✗ |
| E32 | Rollable tables | Roll20/Foundry | ✗ |
| E33 | Map notes / scene pins | all | ◐ annotations exist; not keyed VTT scene pins |
| E34 | **Tokens** — bars, auras, status rings, wildcard art, disposition | all | ◐ `battleMap.ts` tokens (hero/monster/boss w/ base ring); no live bars/auras/status |
| E35 | **Audio** — jukebox + **positional/spatial ambient** + SFX cues | Foundry (positional) | ◐ Audio Studio / MusicGen generate audio; no in-table jukebox or positional sound |

### F. Platform
| # | Capability | Bar | Nox Loom status |
|---|---|---|---|
| F36 | Networking — browser clients; ideally persistent cloud | Roll20 | ◐ multiplayer is **planned** (`multiplayerPlan.ts`) + netcode pieces; no live shared table yet |
| F37 | Voice/video | Roll20 (native) | ✗ |
| F38 | Marketplace / module ecosystem | all | ◐ community/marketplace scaffolding; asset ecosystem via our kits |
| F39 | Hosting options (self-host/VPS/partner) | Foundry | n/a (SaaS model) |

### G. Differentiators / whitespace — where WE win (2025-2026)
| # | Capability | Market status | Nox Loom status |
|---|---|---|---|
| G40 | **First-party AI** — AI-DM/narration, AI images, TTS voices, **AI map generation**, lore-aware storytelling | **None of the four majors ship it** (Foundry even ships a "Contains Zero AI" filter). Only AI-native entrants (Friends & Fables) do. **Biggest single opening.** | ✅ **Our core edge:** godogen/godot-task agent pipeline, AI-DM (ff-gamebook), image-pipeline, TTS (ml-workbench/Kokoro/Orpheus), **AI cartography (this skill)** |
| G41 | **Cinematic / narrative presentation** — full-screen scene art, VN-style dialogue boxes, cutscene fade/dissolve transitions, GM narration overlays | Alchemy/Sorcery! gesture at it; **true VN dialogue + cutscene transitions were NOT found shipping** — a documented gap | ✅ **VN Maker + cutscenes** (`vnMaker.helpers.ts`, VnPlayer) — we already build exactly this |
| G42 | Generated, swappable assets/fonts bound by stable ID | none | ✅ Map Studio + Font Studio + asset-manifest live swap |
| G43 | Native positional audio (not outsourced to Syrinscape) | Foundry only; FG/d20PRO outsource = opening | ◐ we generate audio; wiring positional playback is open |

---

## The read — our gaps, ranked (what to build for VTT parity)

We are **strong exactly where the market is weak** (G: AI + cinematic narrative +
generated assets + rules-modding) and **weak exactly where the market is table-stakes**
(a *live, shared, real-time tabletop runtime*). Everything we have is largely an
**authoring/generation** surface; the missing piece is the **play runtime**. Ranked:

1. **A live shared table + real-time sync** (F36) — the substrate everything else needs.
   `multiplayerPlan.ts` + netcode pieces exist as *plans*; the live session is the gap.
2. **Initiative / combat tracker** (B10–B12) — the specific "d20 tooling we don't have"
   Jesus flagged. Highest-value single tactical feature; d20PRO/FG prove it's the
   backbone of running combat.
3. **Dynamic lighting + LoS + fog of war** (A1–A4) — the battlemap payoff. We already
   model walls/doors in `battleMap.ts` and know the Roll20 barrier taxonomy + `.dd2vtt`
   export ([BATTLEMAP_ASSETS.md](BATTLEMAP_ASSETS.md) §3) — turn the geometry into a
   runtime light/vision engine, or **export `.dd2vtt` and let a partner VTT do it**.
4. **Live dice engine + roll-from-sheet** (D22, C16) — our Ruleset Builder already
   defines the rules (D27 ✅); wire a runtime roller + sheet that consumes them.
5. **Effects/automation engine** (B13, B15) — the FG differentiator; the natural payoff
   of the ruleset engine. Roll20's weakness here is our opening.
6. **Handouts / journals / reveal-on-cue + rollable tables + decks** (E29, E31–E32) —
   cheap narrative wins that lean on content we already author.
7. **Measurement + AoE templates** (A6–A7) — needed for tactical credibility.
8. **In-table jukebox + positional audio** (E35, G43) — we generate the audio; playback
   wiring is the gap, and native positional beats FG/d20PRO's Syrinscape outsourcing.

**Strategic framing:** don't chase Foundry's module depth or Roll20's licensed-content
catalog head-on. Ship **table-stakes parity on A–F** (led by items 1–4 above) so we're
taken seriously, then let **G (AI + VN cinematic presentation + generated assets)** —
which none of the majors have — be the reason to switch. The narrative-first inversion
(scene/story primary, map optional) is our lane; the illustrated-gamebook RPGs
(Veritas/Sorcery/Brante/KoPnP) + AI-DM are the product, and this cartography skill is
the map component that feeds it.

---

## Sources
See the per-platform source lists compiled during research (Foundry VTT docs
foundryvtt.com/article/*; Fantasy Grounds Unity wiki fantasygroundsunity.atlassian.net;
Roll20 help/wiki help.roll20.net + wiki.roll20.net; d20PRO d20pro.com/features;
narrative VTTs: alchemyrpg.com, shardtabletop.com, lets-role.com, owlbear.rodeo,
inklestudios.com/sorcery, fables.gg; Wikipedia "Virtual tabletop"). Key anchors:
- Foundry lighting/walls/perception: https://foundryvtt.com/article/lighting/ · https://foundryvtt.com/article/walls/
- Foundry combat/active-effects/journal/cards/playlists: https://foundryvtt.com/article/combat/ · https://foundryvtt.com/article/active-effects/ · https://foundryvtt.com/article/journal/ · https://foundryvtt.com/article/cards/ · https://foundryvtt.com/article/playlists/
- Fantasy Grounds combat tracker + effects: https://fantasygroundsunity.atlassian.net/wiki/spaces/FGCP/pages/996641984/5E+Combat+Tracker · https://fantasygroundsunity.atlassian.net/wiki/spaces/FGCP/pages/996641187/Reference+-+Effects
- Roll20 dynamic lighting / turn tracker / decks / jukebox: https://help.roll20.net/hc/en-us/articles/360051768974-Creating-Light-Windows-and-Barriers · https://wiki.roll20.net/Turn_Tracker · https://wiki.roll20.net/Decks · https://wiki.roll20.net/Jukebox
- d20PRO features (auto-combat/initiative): https://d20pro.com/features/
- Narrative VTT concept: https://en.wikipedia.org/wiki/Virtual_tabletop · https://alchemyrpg.com/ · https://www.fables.gg/

---

*Siblings: [SKILL.md](SKILL.md) · [BATTLEMAP_ASSETS.md](BATTLEMAP_ASSETS.md) ·
[MAP_REFERENCE_GALLERY.md](MAP_REFERENCE_GALLERY.md) · [MAP_TYPES.md](MAP_TYPES.md) ·
[RENDERING_PIPELINE.md](RENDERING_PIPELINE.md)*
