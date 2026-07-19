# GDD — `ff-gamebook`: an illustrated Fighting-Fantasy gamebook RPG (SP + MP)

> **Status:** DRAFT for Jesus's sign-off. No building starts until approved (parity-build phase-2 gate).
> **Reference/inspiration:** Fighting Fantasy (Steve Jackson & Ian Livingstone) — full breakdown in [`docs/inspiration/ff-gamebook/INSPIRATION.md`](../../inspiration/ff-gamebook/INSPIRATION.md). Reference GDDs collected in [`REFERENCES.md`](../../inspiration/ff-gamebook/REFERENCES.md).
> **IP stance:** we reproduce the *mechanics + UX* of the branching-gamebook genre only. All world, art, monsters, text are original NoxDev content. No FF trademarks, text, or artwork ship.

> ## ✅ Decisions locked (Jesus sign-off, 2026-07-19)
> 1. **Art:** default = **`veritas-gamebook`** style (FF-era ink+watercolor book plates, ~90% Jesus-approved, ship-ready no-LoRA) — the validated gamebook/DM art pipeline. Also produce a **`sir-brante`** (sepia engraving) variant to compare; `sorcery-inkle` ink-wash for storybook maps. Update the master plan + samples page with the choice. (Supersedes the earlier `dark_fantasy_illustration` note below.)
> 2. **Multiplayer:** **all-in v1** — SP + hotseat + net co-op/LAN + **AI DM**.
> 3. **Dungeon Master = a DUAL, very rich system:** a **Structured Storytelling DM** (authored branching-narrative director — deterministic, primary) **+** an **AI DM** (LLM color + intent-routing) layered on top. See §9.
> 4. Default death/save mode = Bookmarks (all four modes ship). Content v1 = complete original adventure, vertical-slice (~150–250 sections) scalable to ~400.
> 5. Template consolidation: rebuild `ff-gamebook` on `nox_if_engine`.

---

## Companion design docs (read alongside this GDD)
These five child docs close the benchmark gaps and carry the depth this GDD only summarizes. All are set in the original NoxDev world *The Grey Tithe* (no FF IP).
- [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md) — world/theme/cast/factions, the starter adventure, the branch spine & endings; the canon the dual DM (§9) is authoritative over. *(gap #3)*
- [`CONTENT_SAMPLE.md`](CONTENT_SAMPLE.md) — 12 fully-written playable sections, a branch map, 3 monster stat blocks, and the First-Toll encounter spec. *(gap #2)*
- [`BALANCE.md`](BALANCE.md) — enemy roster/tiers, the Gold/Provisions economy, the difficulty model, and a verified probability sanity-check (win-rate + LUCK-depletion). *(gap #4)*
- [`WIREFRAMES.md`](WIREFRAMES.md) — ASCII wireframes, per-screen states, and a screen-flow map for all §6 screens. *(gap #5)*
- [`STYLE_GUIDE.md`](STYLE_GUIDE.md) — `veritas-gamebook` art direction (+ `sir-brante` variant) and the audio-design spec. *(gap #8)*

---

## 1. Vision & pillars

A gorgeous, faithful, **illustrated** solo-adventure gamebook — the classic "you are the hero, 2d6 + SKILL, Test your Luck, ~400 numbered sections" experience — that also does what paper never could: **automate the bookkeeping, dramatize the dice, and let friends play together** (hotseat, online co-op, or with an AI Dungeon Master).

**Design pillars**
1. **The page is sacred** — typography, atmosphere, and evocative per-section illustration plates carry 80% of play.
2. **Automate bookkeeping, dramatize the dice** — the Adventure Sheet maintains itself; every roll is a visible, honest, tactile moment.
3. **Faithful soul, modern conveniences** — canonical FF rules exactly; auto-map, bookmarks, Quick Combat, scalable/accessible text layered on top.
4. **Data-driven, not hardcoded** — sections, rules, and encounters are content; per-book variants and alt modes are config.
5. **Solo-first, social-capable** — SP is first-class and offline; hotseat, net co-op, and an engine-authoritative AI DM extend it.

**What "done" means (parity bar):** plays like a real illustrated FF gamebook end to end — menu → roll-up → read/choose/fight/test → death/victory — with real art (LoRA + reused fantasy assets), real audio, working save modes, a professional shell, and at least one complete original adventure; SP + hotseat shipping, net co-op + AI DM demonstrated; screenshot-proven against the reference.

---

## 2. Architecture decision — build on our own tools (reuse, don't reinvent)

We have three gamebook templates today: `gamebook` (Dialogue-Manager solo), `ff-gamebook` (illustrated FF presentation, Dialogue Manager), and `gamebook-if` (computed **`nox_if_engine`**, no AI/net). **Recommendation:** make **`ff-gamebook`** the flagship by giving it the **`nox_if_engine`** computed rules/branching backbone (which already ships an **`ff-2d6.json`** ruleset) instead of the lighter Dialogue-Manager approach, then layer illustrated presentation + netcode + AI DM on top. This consolidates the best of all three into the "FF pen-and-paper RPG" Jesus asked for.

| Concern | Reused NoxDev tool | Notes |
|---|---|---|
| Rules + branching graph | **`nox_if_engine`** + **`ff-2d6.json`** ruleset (`skills/if-engine`) | Data-driven sections, flags/codewords, 2d6 rules already modeled |
| Art (illustration plates, portraits, backgrounds) | **`veritas-gamebook`** style (default) + **`sir-brante`** variant; optional **`nxdv_knight`** hero; `image-pipeline`, `style-anchor`, `scene-art` | See §7 + `STYLE_GUIDE.md`. Locked to `veritas-gamebook` (Jesus-approved gamebook art pipeline). |
| UI kit / screens / shell | `ui-screens`, `ui-elements`, `ui-theme`, `ui-shell` (`nox_ui`) | Parchment theme; the pro studio shell (§6.1) |
| Save/load + modes | `save-system` | Ironman / Bookmarks / Rewind / Checkpoints |
| Audio | `audio-pipeline` | Fantasy/orchestral music + dice/combat/UI SFX from the library |
| Multiplayer | `netcode` | Authoritative host, tiny serializable state (§8) |
| AI Dungeon Master | `companion-npcs` + companion/ML stack | Color + intent-routing only; engine-authoritative math (§9) |
| Reusable assets | `asset-reuse` ladder + categorized library (`BY_THEME.md`, `FF_SHORTLIST.md`) | 325 fantasy packs; see §7 asset plan |
| Content authoring | `narrative`, `if-engine` authoring format | Section markup + link/flag/reachability validation (§10) |

---

## 3. Core loop & rules (faithful FF — exact values)

**Atomic beat:** READ numbered section (prose + illustration) → PRESENT choices/events → RESOLVE (dice / stat change / item / death check) → TURN TO the next section. The ~400-section graph *is* the world; state = current section + Adventure Sheet + codewords.

**Character creation (roll-up):** SKILL = 1d6+6 (7–12) · STAMINA = 2d6+12 (14–24) · LUCK = 1d6+6 (7–12). Rolled value is both Initial and Current. Starting kit: sword, leather armour, lantern, **10 Provisions**, and **one Potion** (Skill / Strength / Fortune). Faithful default: roll-once-commit, with a settings-gated reroll for accessibility.

**The invariant (enforce centrally):** *Current* SKILL/STAMINA/LUCK may fall but **never exceed Initial** — except explicit magical exceptions (Potion of Fortune raises Initial LUCK by 1).

**Combat (per attack round, 1 enemy at a time):** Your Attack Strength = 2d6 + current SKILL; enemy = 2d6 + enemy SKILL; higher wounds the loser for **2 STAMINA**; tie = no damage. Repeat until a STAMINA hits 0. Optional **Luck in combat**: after wounding, Test Luck → Lucky deals +2 (total 4) / Unlucky deals 1; after being wounded, Lucky reduces to 1 / Unlucky raises to 3. **Escape** (only when offered) costs 2 STAMINA. Multi-enemy "gang" rounds + per-enemy modifier hooks (SKILL debuffs, immunities, regen, fear tests) supported via the data-driven rules layer.

**Testing your Luck:** roll 2d6; ≤ current LUCK = Lucky, else Unlucky; **always −1 LUCK** (pass or fail). LUCK is a depleting resource — the core tension.

**Other tests:** Test your Skill / Stamina (2d6 ≤ current; not consumed). Generic "named attribute + 2d6 ≤ current" so per-book extra attributes (FEAR, FAITH, HONOUR, MAGIC) are config.

**Consumables/state:** Provisions (+4 STAMINA, not in combat), Gold, Equipment/quest items, Potions (2 doses, restore-to-Initial), and **codewords/flags** (key-value store queried by section logic — essential for the "true path").

---

## 4. Game modes

- **Solo (baseline, offline).** One hero, one Adventure Sheet, the loop above.
- **Hotseat pass-and-play.** Shared hero/party on one device; turn-rotation + "pass the device" screen. (Also competitive/vote variants.)
- **Net hotseat (turn-based).** Tiny state syncs trivially; async-friendly play-by-post.
- **Shared-party co-op (net/LAN).** 2–6 heroes, own sheets, shared encounters; choice arbitration (rotating leader / vote / host) + co-op combat house-rules (§8).
- **Shared-screen GM + phones.** TV shows the page/art; phones are controllers.
- **AI Dungeon Master.** Narrates + routes free-text intent onto legal choices; engine stays authoritative (§9). Works solo or co-op.

**Death / save modes (explicit setting):** **Ironman** (restart-on-death, no reload) · **Bookmarks** (Tin Man — unlimited revisit points) · **Rewind** (inkle — story remembers, revise a past choice) · **Checkpoints**. Default = Bookmarks (approachable) with Ironman available for purists.

---

## 5. Systems detail → data model

- **AdventureSheet**: {skill{init,cur}, stamina{init,cur}, luck{init,cur}, provisions, gold, potion{type,doses}, equipment[], codewords:set, notes[]}. All mutations funnel through one `apply_delta()` that enforces the never-exceed-Initial invariant and death-at-0.
- **Section**: {id, text, illustration?, choices[{label, target, condition?, effects?}], events[] (combat/luck/skill/item/forced), onEnter effects}. Authored data; validated (§10).
- **Encounter**: {enemies[{name, skill, stamina, portrait, modifiers[]}], escapeTarget?, gangRules}.
- **RNG**: seeded per run (enables MP sync + replay/verify); dice surfaced honestly.
- **GameState (serializable, tiny):** {sectionId, sheets{playerId→AdventureSheet}, codewords, rngSeed, turn} — the unit of save + net sync.

---

## 6. Screens & UI/UX (all 17)

Reading view is mobile-portrait-native; combat/map/sheet reflow to landscape/desktop. Parchment/paper/sepia/dark themes; scalable dyslexia-friendly type; TTS.

### 6.1 The professional NoxDev shell (built in `nox_ui`, inherited by all templates)
Studio-grade start menu — **hero art (Nox-goddess / painterly fantasy key art via the LoRA)**, styled title + buttons (New Adventure / Continue / Library / Options / Credits / Quit), ambient loop + page-turn sting. **Fully fleshed Options** (Reading, Audio, Combat, Dice, Accessibility, Rules/Mode, Language, Data). Working **Save/Load**, **Pause** (Resume/Options/Quit-to-menu), and **Death/Victory** screens. This replaces the bland reused menu across every template.

1. **Title / Main Menu** — key art + menu; Continue jumps to last section; MP entry (Host/Join/Hotseat).
2. **Library / Bookshelf** — shelf/grid of adventures (covers/spines), zoom → Read / illustration gallery / blurb / completion%. Also the adventure-select in single-book builds.
3. **Character Creation / Roll-Up** — three stat panels with animated dice; starting-kit summary; 3-card Potion chooser; Roll/Begin (+ settings-gated Reroll); color-coded roll quality.
4. **Book-Reading View (the heart)** — numbered section prose (serif, drop-cap/section number), illustration plate (inline/tap-expand), choice list as full-width buttons (target numbers hidden in faithful mode), persistent compact HUD (SKILL/STAMINA/LUCK + quick buttons to Sheet/Inventory/Map/Menu + bookmark). Inline action buttons ([Test your Luck]/[Eat Provisions]/[Attack]). Page-turn/crossfade transitions; "already read" dimming.
5. **Choice / Branch UI** — stacked action buttons; conditional choices hidden or shown locked with reason (item/gold/codeword/stat).
6. **Dice-Roll Overlay** — animated 3D d6 tray, modifier + total ("2d6=7, +SKILL 9 = 16"), context label, outcome banner (LUCKY!/wounded). Tap or shake to roll; Quick/auto mode; honest pips.
7. **Combat Screen** — enemy panel(s) (name/portrait/SKILL/STAMINA bar), player panel, round-resolution area (both rolls + totals + log line), action buttons (Attack / Test Luck / Escape / Use Item / Eat), combat log. Quick Combat toggle auto-runs rounds.
8. **Adventure Sheet** — parchment rendering of the printed sheet (Initial+Current stats, Provisions/Gold/Potions, Equipment, codewords/notes, encounter boxes). Read-only in faithful mode; some items tap-to-use.
9. **Inventory / Equipment / Potions** — item grid with icons/desc/qty, equipped slots, potion doses; tap → Use/Equip/Read/Drop (context-gated).
10. **Map / Progress** — default faithful **passage-graph auto-map** (visited sections, current, branches); optional **Sorcery!-style travel map** (map *is* movement) as a mode.
11. **Save / Load / Bookmarks** — slots (thumbnail/section/timestamp/stat snapshot), unlimited bookmarks, autosave, mode selector.
12. **Death Screen** — atmospheric death art + how-you-died flavor + run stats + Restart/Load/Menu; deaths-gallery hook.
13. **Victory Screen** — triumphant art + closing narrative + final score/unlocks + New/Library/Share/Menu.
14. **Settings** — as §6.1 Options.
15. **Gallery / Illustrations** — unlocked interior plates.
16. **Multiplayer Lobby / Session** — Host/Join, party roster, per-player or shared roll-up, turn/vote indicator, chat/emotes, connection status.
17. **Pause** — Resume / Options / Save / Quit-to-menu (PROCESS_MODE_ALWAYS).

---

## 7. Art direction & reuse-first asset plan

**Look:** classic illustrated FF interior plates via the **`veritas-gamebook`** style (default — FF-era ink+watercolor book plates, Jesus-approved ~90%, ship-ready) for section illustrations, portraits, and cover/death/victory key art; optionally stack **`nxdv_knight`** for a recurring hero. **`sir-brante`** (sepia engraving) is the COULD-tier variant; `sorcery-inkle` ink-wash for storybook maps. Full palette / technique / on-model rules in `STYLE_GUIDE.md`. UI = parchment/scroll/wood fantasy.

**Reuse ladder (generate LAST).** Draw from the categorized library (`FF_SHORTLIST.md`), extract from NAS:

| Asset need | Rung | Source (NAS zip) |
|---|---|---|
| Item/weapon/armour/potion icons | 3 (owned kit) | `rpggame1700plusicons.zip`, `fantasyiconsmegapack_windows.zip`, `7soulsrpggraphics_iconpack_windows.zip`, `spellbookmegapack_windows.zip` |
| Monster/enemy portraits | 3 | `cursedkingdomsmonsterpack.zip`, `fantasyenemycreatures_windows.zip`, `luizmelo_monsters-creatures-fantasy`, `rpgbattlers_*` |
| Hero/NPC portraits | 3 + 5 (restyle to LoRA) | `medievalfantasycharacters.zip`, `16-bitfantasyspriteset.zip`, `segel2dcharactersbundle.zip` |
| Parchment / scroll / book UI | 3 | `spellbookmegapack_windows.zip`, `scrolliconspack.zip`, `medievalgameguipack.zip`, `woodenguiset.zip` |
| Fantasy fonts | 3 (CC0) | `ark_pixel_ofl`, `pixel_operator_cc0`, + fantasy display fonts |
| Music (menu/explore/combat/victory) | 3 | `fantasy_rpgmusicpack.zip`, `arcaneechoesorchestralchiptunemusiccollection.zip`, `shadowwardarkfantasyorchestralmusiccollection.zip` |
| SFX (dice, hit, UI, page-turn) | 3 | `combatsoundsbundlecollection.zip`, `interfacesfxvol2.zip` |
| Per-section illustration plates | 6 (generate, `veritas-gamebook`) | `veritas-gamebook` style (+ optional `nxdv_knight` hero) per `STYLE_GUIDE.md`; register in asset-manifest, promote reusable ones |

A plan that's all rung-6 is a failed plan — icons/UI/audio/monsters come from the library; only bespoke section plates are generated (and even those seeded by reused compositions where possible).

---

## 8. Multiplayer architecture (`netcode`)

**Authoritative host** owns the canonical `GameState` (section id, all sheets, codewords, RNG seed). Clients render and **submit** choices/rolls; host validates against the rules engine and broadcasts. State is tiny + serializable → same object powers save, net hotseat, and co-op. Transport: Godot high-level multiplayer (ENet) for LAN + a relay/WebRTC path for internet NAT traversal. LAN discovery for the couch/event case. Disconnect/rejoin: clients rehydrate from host state.

**Co-op house rules (FF has none — we define + playtest):** choice arbitration = rotating leader (default) / vote / host; combat = each hero assigned a foe *or* combined party rolls vs a boss; loot/gold split rules. Ship SP + hotseat guaranteed; net co-op behind the same state model.

---

## 9. The Dungeon Master — a dual, rich system (`if-engine`, `narrative`, `companion-npcs` + ML stack)

Two DM layers, both engine-authoritative on all dice/state (never mutate STAMINA/LUCK or fabricate items directly — everything routes through `apply_delta()`):

**9a. Structured Storytelling DM (primary, deterministic).** An authored branching-narrative *director* on `nox_if_engine`: beyond static "turn to N," it runs a rich rules-driven story layer — **pacing beats** (alternate explore/risk/consequence per §1.3), **dynamic encounter/event selection** (weighted decks, table rolls, state-gated set-pieces), **codeword/flag-driven storylets** (Emily-Short-style: eligible content chosen by current state), **NPC memory & reactivity**, **tension/threat pacing**, and **arbitration** for co-op (whose turn, vote, consequences). This is the "very rich system" — a data-driven story engine, fully playable with **no AI/LLM at all** (matches `gamebook-if`'s no-network promise for the SP core), and the substrate the AI DM sits on.

**9b. AI DM (LLM color + intent-routing, layered).** The companion/ML stack (i) enriches the structured DM's chosen beats with dynamic prose + monster voices, and (ii) maps free-text player intent ("I try to bribe the guard") onto the **legal choices/storylets the structured DM exposes**. The LLM proposes; the structured DM + rules engine dispose. Optional experimental generative sections flagged high-risk, off by default. Graceful fallback to pure structured DM if the LLM is unavailable.

Design intent: the **structured storyteller** gives authored, reliable, richly reactive direction; the **AI DM** adds improvisational color and handles the unanticipated — together a co-op/solo DM that feels alive without ever breaking the math or the win condition.

---

## 10. Content & authoring

~400 interlinked sections is a large graph → **author-first tooling** on the if-engine format: structured section markup, **link validation** (no dangling "turn to N"), **reachability + dead-end/unwinnable detection**, flag/codeword consistency, combat/stat scripting, and **jump-to-any-section debug play** with hot-reload preview. Ship **one complete original adventure** (~150–250 sections for a vertical slice, scalable to ~400) as the reference content, authored in NoxDev's own world (no FF IP).

---

## 10a. Studio integration & live asset wiring (required)

Every in-game asset slot (portraits, monster art, section plates, item/UI icons, parchment frames, music, SFX) is **bound by a stable asset ID through a Studio-managed manifest**, never a hardcoded path. The game resolves the *currently bound* asset per slot at load (hot-reload where feasible), and every asset is registered in `asset-manifest` with provenance (source pack / LoRA / style / license) and surfaced in the Studio. Result: **Jesus can drop in or replace any asset from the Studio and see it in-game with no code edits**, as real assets are produced — scaffolding art is just the current binding, swapped later. **Audio + a Credits screen** (attribution for assets/audio/LoRAs/tools, licenses honored) are first-class, not afterthoughts.

## 11. Success criteria / parity checklist
> Full Definition of Done: `godogen/skills/parity-build/STANDARDS.md`. FF-specific:

- [ ] Roll-up → play → death/victory loop complete and faithful (exact dice values; Luck decrements; stat-cap invariant).
- [ ] All 17 screens implemented with the specified UX; reading view beautiful + accessible.
- [ ] Combat (incl. Luck-in-combat, escape, multi-enemy) + Quick Combat.
- [ ] Real art (LoRA plates + reused fantasy icons/UI/monsters), real music + SFX — zero placeholder ColorRects.
- [ ] Professional shell + full Options + Save/Load with all four death/save modes.
- [ ] Data-driven rules (ff-2d6) + authoring validation; one complete original adventure.
- [ ] SP + hotseat shipping; net co-op + LAN demonstrated; AI DM (color+routing) demonstrated, engine-authoritative.
- [ ] **Sound + music + credits:** menu/explore/combat/victory music + dice/hit/UI/page-turn SFX (buses, volume-respecting); a Credits screen with full attribution (assets/audio/style packs/tools, licenses honored).
- [ ] **Testing:** headless boot clean; rules/invariant probes + full-flow probe (win + a death); playtest + design-review pass; cold-clone integrity probe green.
- [ ] **Studio integration + live asset wiring:** all asset slots bound by ID through the Studio manifest (drop-in/replace from the Studio, no code edits); every asset registered with provenance; GDD/plan exposed in the Studio GDD Library.
- [ ] Screenshot-proven vs the reference **and a competitor** (menu + reading + combat + sheet + map + death/victory); lead's independent verification recorded.
- [ ] Jesus sign-off.

---

## 12. Open decisions for sign-off
1. **Art lane:** painterly VGA `dark_fantasy_illustration` (recommended, matches illustrated FF) vs flatter `gamebook-illustration-zit` storybook.
2. **Template consolidation:** rebuild `ff-gamebook` on `nox_if_engine` (recommended) vs keep Dialogue-Manager + only add MP/AI.
3. **MP scope for v1:** SP + hotseat + net co-op + AI DM all in v1, or SP + hotseat first with net/AI as fast-follow.
4. **Default death/save mode:** Bookmarks (recommended) vs Ironman.
5. **Content size for the shipped adventure:** vertical slice (~150–250 sections) vs full (~400).

---

## 13. Production spine, scope & cut-line (lead)
Closes benchmark gap #1. All-in v1 is the target, but scope has an explicit cut-line so quality is never sacrificed to cram features.

**MoSCoW for v1**
- **MUST (ship-blocking, never cut):** faithful SP core (roll-up→read→choose→dice→combat→luck→death/victory); real `veritas-gamebook` art + audio + **credits**; pro shell + full options + save modes; **one complete original adventure**; **hotseat**; Studio asset-wiring (drop-in replace); testing (probes+playtest+design-review+cold-clone); screenshot parity vs reference+competitor.
- **SHOULD (v1 target):** net co-op/LAN; AI DM (color+intent-routing); the Structured Storytelling DM depth (weighted decks, storylets, NPC memory).
- **COULD:** Sorcery!-style travel-map mode; illustration gallery; `sir-brante` art mode.
- **WON'T (v1):** multi-book store; cross-book campaign imports; generative-DM new-section synthesis.
- **Cut-line rule:** if schedule slips, net co-op + AI DM slip to a v1.1 fast-follow — **production quality/parity of the MUST tier is never cut** to keep features.

**Milestones (owner = lead supervises; build via `godot-task` agents):** M1 faithful SP core → M2 real skin (art/audio/credits/shell/save) = the "looks/feels real" gate → M3 content + MP + dual DM → M4 parity proof. Each phase closes only on lead-verified STANDARDS.md boxes.

## 14. Risk register (lead)
Closes gap #6.

| Risk | Sev | Mitigation |
|---|---|---|
| Over-scope (all-in v1) misses the quality bar | High | MoSCoW cut-line (§13); MUST tier is SP+hotseat at full polish |
| AI DM corrupts state / breaks win condition | High | Engine authoritative; DM proposes only, all math via `apply_delta`; output constrained to legal actions; fallback to structured DM |
| Content scale (~400 sections) rots / dead-ends | High | Vertical slice first; authoring validator (link/reachability/dead-end/codeword) is ship-blocking |
| Art inconsistency across plates | Med | `style-anchor` + locked `veritas-gamebook` lane; batch-review |
| MP desync / disconnect | Med | Authoritative host + seeded RNG + tiny serializable state; rejoin rehydrates |
| Digital-dice distrust | Med | Visible honest pips; seeded per-run RNG enables replay/verify; any fudge is explicit opt-in |
| Two-state-store drift (IFState↔sheet) | Med | Phase 1 unification (single source of truth) — tracked |

## 15. Positioning & competitive comparison (lead)
Closes gap #7.

| | inkle *Sorcery!* | Tin Man *FF Classics* | **NoxDev ff-gamebook** |
|---|---|---|---|
| Rules fidelity | reimagined (no 2d6/Luck-drain) | faithful | **faithful** (ff-2d6, Luck-drain) |
| Automated sheet | yes | yes | **yes** |
| Honest visible dice | n/a (slider combat) | yes | **yes, seeded/replayable** |
| Art | hand-drawn premium | book plates | **veritas-gamebook (premium plates)** |
| Multiplayer | none | none | **hotseat + net co-op/LAN** ← our edge |
| AI / dynamic DM | none | none | **dual DM (structured + AI)** ← our edge |
| Accessibility-first | partial | partial | **first-class** |
| Live asset swap from a studio | n/a | n/a | **yes (Studio-bound assets)** ← our edge |

**Thesis:** Tin Man's faithfulness + Sorcery!'s art polish, *plus* three things neither ships — real multiplayer, a dual (authored+AI) DM, and Studio-bound live-swappable assets.

> **Now closed (companion docs, linked at top):** narrative bible ([`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md), gap #3), sample content + branch map + monster stat blocks + encounter ([`CONTENT_SAMPLE.md`](CONTENT_SAMPLE.md), gap #2), full balance model ([`BALANCE.md`](BALANCE.md), gap #4), screen wireframes/states/flow-map ([`WIREFRAMES.md`](WIREFRAMES.md), gap #5), and the art+audio style guide ([`STYLE_GUIDE.md`](STYLE_GUIDE.md), gap #8).
