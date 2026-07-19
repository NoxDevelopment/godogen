We develop agents and skills here. They are then used in another folder for Godot game development with Claude Code.

## Layout

Source code lives at the repo root:
- `skills/` — skill definitions (`SKILL.md`) and their tool scripts
- `teleforge.md` — CLAUDE.md in game folder (with Telegram connection)
- `publish.sh` — create ready-to-develop game folder

## Skills

- godogen — orchestrator + scaffold + decomposer + asset planning + asset generation + visual target (main thread)
- godot-task — task execution + GDScript docs + screenshot capture + visual QA (context: fork)

When writing skills: don't give obvious guidance. The agent is a highly capable LLM — handholding only pollutes the context.

## Parity builds — MANDATORY for any game template or Studio tool

Building or upgrading a game template (or a Studio tool) means running the **`parity-build`** skill (`skills/parity-build/SKILL.md`) against its **Definition of Done** (`skills/parity-build/STANDARDS.md`). Non-negotiable:

- **Recreate the reference to full parity, then EXCEED it.** "It runs" / "has the basic loop" is a failing grade. Match what pros ship (screens, depth, polish), then add our differentiators.
- **Dogfood our own artifacts — never hand-roll placeholders or Kenney grabs:** the skills registry (`skills/*`), the theme/style-categorized **asset library** (`pieces/asset-kits/_library/BY_THEME.md`, `FF_SHORTLIST`-style shortlists), our **LoRAs / style packs** (`Noxdev-Studio/docs/STYLE_BENCHMARKS_2026-07.md`), the **GDD Library + templates** in the Studio, and the `godogen`/`godot-task` agent pipeline.
- **Lead trusts nothing:** independently verify agent output (re-run probes, screenshot vs the reference AND a competitor), adversarial-review each milestone, and **scope every `godot --import` with `--path`** + post-phase `git status` scope-check (an unscoped import silently strips other templates' `[audio]` ABI).
- **Include the whole surface:** sound/music/**credits**, testing, accessibility, the pro `nox_ui` shell, MP where the genre wants it, and **Studio asset-wiring** (assets bound by stable ID so Jesus can drop-in/replace them live).
- **Nail ONE fully before the next.** Nothing is "done" until Jesus signs off.

Cross-session context for this work lives in the auto-loaded memory (`MEMORY.md`) — check it first.
