---
name: parity-build
description: Recreate a reference ("inspiration") game to full parity as a NoxDev template — research the real game + collect reference GDDs, author a full GDD + gameplay/UI-UX plan (exposed in the Studio) gated on Jesus's sign-off, then build every aspect by orchestrating agents that use our skills + asset library, supervised and compared against the inspiration, the plan, and the running result. Use whenever building or upgrading a game template to real parity (not a genre gesture).
---

# Parity Build — lead-designer orchestration for real games

**Definition of Done + the lead's verification discipline live in [`STANDARDS.md`](STANDARDS.md) (this dir) — read it; nothing ships until every applicable box is independently verified + Jesus signs off.** It covers gameplay, screens, art+LoRAs, **sound/music/credits**, production/shell, **testing**, and **Studio integration + live asset wiring** (in-game assets bound by stable IDs through a Studio manifest so Jesus can drop-in/replace assets live).

The failure mode this skill exists to kill: hand-rolling amateur placeholder UIs, "Kenney grabs," and genre gestures instead of dogfooding our own registry (`godogen/skills/*`), our 638-pack asset library, and the `godogen`/`godot-task` agent pipeline. Templates are DONE only when they recreate their inspiration game's look AND feel, at full depth, with real assets, real audio, real MP where the genre wants it, a professional studio shell, and screenshot proof vs the reference.

## Roles

- **You (Claude) = lead designer + orchestrator.** You research, plan, decide art/UX direction, dispatch agents, supervise, compare against the inspiration + plan + result, and iterate. You do NOT try to build every aspect yourself — you oversee agents who do, using the skills below.
- **Agents = the crew.** Each does one aspect (a research sweep, an asset pass, a `godot-task` build task) using the named skill, and reports back for your review.

## Phases (nail ONE game fully before starting another)

### 1. Research the inspiration (agents, parallel)
- Identify the reference game (from the registry `name`/`description` or Jesus's stated reference).
- Research its **screens, gameplay elements, and core loop**; digital adaptations and their UI/UX; SP vs MP (local + net) design.
- **Collect reference / similar real GDDs** for the genre (published GDDs, postmortems, dev talks, SRDs) — add them to the Studio design-docs collection (see Studio integration below) so the library compounds.
- Output: `docs/inspiration/<game>/INSPIRATION.md` (loop, systems, per-screen UI/UX, references) + reference-GDD entries in the collection.

### 2. Author the GDD + gameplay/UI-UX plan → Studio → SIGN-OFF GATE
- Write the **full GDD** and the **gameplay + UI/UX implementation plan** (per-screen, per-system, asset plan, MP plan, shell plan) → `docs/gdd/<game>/GDD.md` + `PLAN.md`.
- **Expose both in the Studio docs collection.**
- **Summarize for Jesus and STOP.** Do not build until he signs off. This gate is mandatory.

### 3. Reuse-first asset plan (asset-reuse ladder + our categorized library)
- Every planned asset records its rung (manifest → owned/CC0 kit → derive/restyle → generate LAST). Use the theme/style-categorized library (`pieces/asset-kits/_library/BY_THEME.md`), extract from NAS (`\\DXP4800PLUS-A79\NoxDev\game assets`). A plan that's all fresh-generation is a failed plan.

### 4. Build by orchestrating agents (godogen spine, supervised)
- Drive the `godogen` pipeline: visual-target → decompose (PLAN.md) → scaffold → per-task `godot-task` sub-agents. Wire the exact skills each aspect needs (`game-feel`, `world-layout`, `scene-art`, `ui-screens`/`ui-shell`, `save-system`, `audio-pipeline`, `netcode`, `input-handling`, `companion-npcs`, `rpg-systems`, `if-engine`, `narrative`).
- You supervise every task: read its VQA report + screenshots, **compare against INSPIRATION.md + PLAN.md + the actual result**, and replan/iterate on any gap. Never accept a fail verdict.

### 5. Prove parity before vetting
- `playtest` + `design-review` skills; screenshot menu + each gameplay screen and **compare side-by-side with the inspiration game**. Only then flag for Jesus's vet. Nothing is "done" until he signs off.

## Standard shell (every template)
Professional studio start menu (hero/Nox-goddess art, not the bland reused screen), fully fleshed options (video/audio/controls+rebind), working save/load, pause (resume/options/quit-to-menu), game-over/win screens. Built once in `nox_ui`, inherited by all.

## Studio integration (design-docs collection)
GDDs, plans, and collected reference GDDs are exposed in Nox Dev Studio's docs collection so the design library is browsable and compounds across games. (Integration point discovered per-run in `Noxdev-Studio/apps/web`; register each doc there.)

## Verification & self-critique — the lead trusts NOTHING (mandatory)

Agent self-reports ("fails=0", "looks good") are claims, not evidence. As lead you **independently verify** every phase — never rubber-stamp:
- **Re-run the probes/tests yourself** (or via a separate adversarial review agent), don't accept the building agent's own pass claim.
- **Look at it** — screenshot every screen and compare side-by-side with the reference game AND a real competitor; "boots clean" ≠ "looks/plays like the reference."
- **Adversarial review agent** per milestone: a reviewer whose job is to find where we fall short of the reference/competitor/GDD, not to confirm success. Fix everything it finds before advancing.
- Be hard on **our own GDDs/plans/tools** too: benchmark them against the real reference GDDs (Studio GDD Library) and competitor tools. If ours is thinner, it's not done.

## The bar: match, then EXCEED — do more, not less
We know what pros ship (features, screens, depth, polish) — **we cannot do less**. Meet full competitor feature depth, then add our differentiators (AI DM, dual storyteller, deeper systems). "It runs" and "it has the genre's basic loop" are failing grades. Count ≠ parity: 78 templates means nothing if only a few are real games — prefer several genuinely finished, competitor-beating templates per genre over a large shallow catalog.

## Create skills as needed
If an aspect recurs and has no skill, create one (e.g. `gdd-authoring`, `inspiration-research`, `adversarial-review`) rather than hand-doing it each time. Prefer extending an existing skill over duplicating.
