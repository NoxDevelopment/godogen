# NoxDev Parity Standards — Definition of Done (games AND tools)

The authoritative bar for `parity-build`. Nothing is "done" until every applicable box is checked **and independently verified by the lead** (not the building agent's self-report) **and** Jesus signs off. Applies to game templates *and* Studio tools. This will keep being refined — treat it as living.

## The lead's discipline (trust nothing)
- **Verify, don't accept.** Re-run probes/tests yourself or via an adversarial review agent; never take "fails=0" on faith.
- **Look at it.** Screenshot every screen; compare side-by-side with the reference game AND a real competitor. "Boots clean" ≠ "looks/plays right."
- **Adversarial review per milestone** — a reviewer paid to find shortfalls vs reference/competitor/GDD. Fix all findings before advancing.
- **Benchmark our own docs/tools** against the real reference GDDs (Studio GDD Library) and competitor tools. Thinner than a pro = not done.
- **Match, then EXCEED.** Full competitor feature depth is the floor; our differentiators (AI DM, dual storyteller, deeper systems) are the "more." Count ≠ parity.

## Definition of Done — checklist

### Gameplay & systems
- [ ] Core loop + systems faithful to the reference, at full depth (exact rules/values).
- [ ] Meets or beats competitor feature set; our differentiators added.
- [ ] All modes/edge-cases handled (no "happy path only").

### Screens & UX
- [ ] Every screen the genre needs, at competitor-parity layout/polish.
- [ ] Game feel: transitions, feedback, juice; snappy, not static.
- [ ] Accessibility: scalable/dyslexia text, high-contrast, reduced-motion, TTS where text-heavy.

### Art & assets
- [ ] Real assets via the reuse ladder (library → derive → restyle → generate LAST); **use our LoRAs/style packs**. Zero placeholder ColorRects/blocky stand-ins.
- [ ] Consistent art direction (style-anchor) matching the chosen look.

### Sound, music, credits  ← required, not optional
- [ ] Music (menu + gameplay states) on the Music bus; SFX on the SFX bus; ambience where apt.
- [ ] Audio respects settings volumes; mixing sane.
- [ ] **Credits screen/system** — attribution for assets/audio/LoRAs/tools (licenses honored).

### Production & shell
- [ ] Professional NoxDev shell (hero/Nox-goddess art, full options, pause, quit-to-menu, game-over/win) inherited from `nox_ui`.
- [ ] Working save/load with the genre-appropriate modes.
- [ ] Multiplayer where the genre wants it — local + net, authoritative-host.

### Testing  ← required
- [ ] Headless import + boot clean (no script errors) on the pinned engine.
- [ ] Automated probes/unit tests for rules/invariants + a full-flow probe (start→win + a fail state).
- [ ] Playtest pass (the `playtest` skill) + design-review pass.
- [ ] Cold-clone / integrity probe green (no broken-on-clone refs).

### Studio integration & live asset wiring  ← required
- [ ] In-game assets are **bound through a Studio-managed manifest by stable asset IDs**, not hardcoded paths — so Jesus can **drop in / replace an asset from the Studio and see it in-game** without code edits, as real assets are created.
- [ ] Every generated/reused asset registered in `asset-manifest` with provenance (source, LoRA/style, license) and surfaced in the Studio for swap.
- [ ] The game reads the current bound asset for each slot at load (and ideally hot-reload), so replacement is drop-in.
- [ ] Docs (GDD/plan/inspiration) exposed in the Studio GDD Library.

### Proof & sign-off
- [ ] Screenshot parity proof vs reference + a competitor, for every screen.
- [ ] Lead's independent verification recorded.
- [ ] Jesus sign-off.

## Build hygiene (learned the hard way, 2026-07-19)
- **Scope every Godot run.** Build agents MUST pass `--path <this template skeleton>` to every `godot --import`/`--headless` run. An **unscoped** import scans the whole tree and silently rewrites OTHER templates' `project.godot` (downgrades the engine + strips the `[audio]` bus ABI) — it already damaged two READY templates. Never run an unscoped import.
- **Post-phase scope-check (lead).** After every phase, run `git status` and confirm **nothing changed outside the target template** (except intended shared files). Revert any stray collateral immediately.
- **Deletions:** teardown of superseded paths is allowed only when the plan names it, it's git-recoverable (committed at HEAD), and scoped to the target; verify boot still clean afterward. Never delete to hide an error.

## Tools (Map Studio etc.)
Same bar: real output at competitor parity (e.g. Map Studio → hand-drawn fantasy parchment maps + sci-fi blueprints, Inkarnate/Wonderdraft/Dungeondraft/Azgaar-grade), real/generated-chopped assets, tested, integrated into the Studio. No blocky placeholder.
