# PLAN — `ff-gamebook` build (post-sign-off)

> Executed via the `parity-build` pipeline: I (lead designer) orchestrate; each phase runs as `godot-task` sub-agents using the named skill; I supervise every task's VQA against the GDD + INSPIRATION.md + the running result, and iterate. **No phase starts before Jesus signs off the GDD.**
> Reuse-first: every asset records its ladder rung; only bespoke section plates are generated. Nothing ships with placeholder ColorRects.

## Milestones
- **M1 — Playable faithful SP core** (P0–P4): roll-up → read → choose → dice → combat → death/victory, real data, auto Adventure Sheet.
- **M2 — Real production skin** (P5–P7): LoRA/reused art, audio, pro shell + options + save modes. This is the "looks/feels like a real illustrated FF" bar.
- **M3 — Content + social** (P8–P10): one complete original adventure; hotseat → net co-op/LAN; AI DM.
- **M4 — Parity proof** (P11): playtest + design-review + screenshot vs reference → Jesus vet.

---

## Phase 0 — Foundation & architecture
- **Skills:** `if-engine`, `ui-theme`, `input-handling`.
- **Do:** scaffold/refit `ff-gamebook` on **`nox_if_engine`**; adopt **`ff-2d6.json`** ruleset; NoxDev ABI (Master/Music/SFX buses, groups, save contract, input set); parchment `ui-theme`; project.godot pinned to the template engine (4.7-stable). Central `apply_delta()` enforcing the never-exceed-Initial + death-at-0 invariant; seeded RNG.
- **Verify:** headless import + boot clean; unit-check rule invariants (stat caps, Luck −1 per test, 2d6+SKILL wounding).

## Phase 1 — Rules engine, data model & authoring/validation
- **Skills:** `if-engine`, `narrative`.
- **Do:** Section/Encounter/AdventureSheet/GameState data types (§5 GDD); flags/codewords store; combat resolver (ties, Luck-in-combat, escape, multi-enemy hooks); tests (Luck/Skill/Stamina); Potions/Provisions/Gold. **Authoring tooling:** section markup + link/reachability/dead-end/unwinnable validation + jump-to-section debug play + hot-reload.
- **Verify:** ruleset unit tests vs canonical values; validator flags a deliberately broken sample.

## Phase 2 — Book-Reading View + Choice UI + Dice overlay
- **Skills:** `ui-screens`, `ui-elements`, `game-feel`.
- **Do:** the heart screen (prose + illustration slot + choice buttons + persistent HUD + bookmark), page-turn/crossfade transitions, "already read" dimming, inline action buttons; conditional-choice locking with reasons; animated 3D d6 dice overlay (tap/shake, honest pips, Quick/auto). Faithful mode hides target numbers.
- **Verify:** screenshot vs INSPIRATION §3.1(4)(6); readability/scalable-text check.

## Phase 3 — Combat screen
- **Skills:** `ui-screens`, `game-feel`, `audio-pipeline` (hooks).
- **Do:** enemy/player panels, round resolution (both rolls+totals+log), action buttons (Attack/Test Luck/Escape/Use/Eat), Quick Combat toggle, multi-enemy layout; win/lose transitions.
- **Verify:** fight a scripted encounter to a win and a death; Luck-in-combat math correct; screenshot vs §3.1(7).

## Phase 4 — Adventure Sheet, Inventory, Map/Progress
- **Skills:** `ui-screens`, `ui-elements`.
- **Do:** parchment auto-maintained sheet (Initial+Current, consumables, equipment, codewords, encounter boxes); inventory/equip/potions with context-gated use; passage-graph **auto-map** (default) + optional Sorcery!-style travel-map mode.
- **Verify:** sheet mutates correctly through a run; map reflects visited sections.

## Phase 5 — Art (reuse-first + LoRA)
- **Skills:** `asset-reuse`, `image-pipeline`, `style-anchor`, `scene-art`, `asset-manifest`.
- **Do:** extract icons/monsters/portraits/parchment-UI/fonts from the NAS shortlist (§7 GDD); generate section illustration plates + cover/death/victory key art with **`dark_fantasy_illustration`** (+ `nxdv_knight` hero); register all in asset-manifest; promote reusable plates.
- **Verify:** zero ColorRect placeholders in shipped screens; style-anchor consistency across plates; asset-plan shows ≥50% rungs 1–5.

## Phase 6 — Audio
- **Skills:** `audio-pipeline`.
- **Do:** menu/explore/combat/victory music + dice/hit/UI/page-turn SFX from the library, routed to Music/SFX buses, respecting NoxSettings volumes.
- **Verify:** audio plays in menu + gameplay; volumes obey settings.

## Phase 7 — Professional shell, Options, Save modes
- **Skills:** `ui-shell`, `ui-screens`, `save-system`, `accessibility`.
- **Do:** studio start menu with LoRA key art (Nox-goddess/fantasy), full Options (Reading/Audio/Combat/Dice/Accessibility/Rules-Mode/Language/Data), pause (resume/options/quit-to-menu), Death/Victory screens; Save/Load + **Ironman/Bookmarks/Rewind/Checkpoints** modes; TTS + dyslexia font + high-contrast + reduced motion. **Built in `nox_ui` so every template inherits it.**
- **Verify:** save→quit→continue restores state; each death/save mode behaves per spec; options live-apply.

## Phase 8 — Content: one complete original adventure
- **Skills:** `narrative`, `if-engine`.
- **Do:** author a complete original NoxDev adventure (vertical slice ~150–250 sections, scalable to ~400) — no FF IP; full validation pass (no dangling links, reachable victory, consistent codewords).
- **Verify:** playable start→victory and start→a death; validator green.

## Phase 9 — Multiplayer
- **Skills:** `netcode`.
- **Do:** hotseat pass-and-play first (turn rotation + pass-device screen); then authoritative-host **net co-op** + **LAN discovery** on the serializable GameState; co-op house rules (choice arbitration + party combat + loot split); disconnect/rejoin.
- **Verify:** 2-client co-op session completes an encounter; LAN join works; host authority holds (client can't desync the sheet).

## Phase 10 — AI Dungeon Master
- **Skills:** `companion-npcs` (+ companion/ML stack).
- **Do:** color + intent-routing DM — enriches prose, voices monsters, maps free-text intent onto legal choices; **engine authoritative on all dice/state** (DM proposes, never mutates). Guardrails constrain output to legal actions.
- **Verify:** free-text intent routes to a legal choice; DM cannot change STAMINA/LUCK or fabricate items; graceful fallback if LLM unavailable.

## Phase 11 — Prove parity
- **Skills:** `playtest`, `design-review`.
- **Do:** full playtest (roll-up→victory, and a death, in SP + hotseat; a co-op session; an AI-DM turn); design-review pass; screenshot menu + every gameplay screen; side-by-side vs reference.
- **Verify:** parity checklist (GDD §11) all green → flag for Jesus's vet.

---

## Orchestration notes
- Phases gate as M1→M4; within a milestone, independent screens/systems fan out to parallel `godot-task` agents; I supervise each VQA report and replan on any fail (never accept a fail verdict).
- Reuse `nox_if_engine` + `ff-2d6.json` + `nox_ui` + the categorized asset library throughout — build tools, not placeholders.
- The `nox_ui` shell + save-modes + accessibility work (P7) is shared infrastructure that upgrades **every** template, not just this one.
