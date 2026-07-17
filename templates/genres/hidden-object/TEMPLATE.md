# Hidden Object Template (seek-and-find with decoys, hints + timer, 2D)

A seek-and-find **hidden-object** casual game: a cluttered scene of seeded item
placements, a **find list** to locate by clicking, **decoy** items that punish misclicks,
a limited **hint** system, a per-round **timer**, combo + time-bonus scoring, and escalating
rounds. It is OUR OWN engine with generic content (no trademarks) — a pure, seedable,
deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py hidden-object <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`HiddenEngine`** (`scripts/hidden_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG lays out the objects
  (rejection-sampled with a minimum separation) **and** picks the find list, so a whole game —
  the exact scene layout every round — replays **byte-identically** from a seed:
  - **Per-round scene generation** — (5 + round) **target** items among (8 + round×2)
    **decoys**, placed with min-spacing over the play area.
  - **Click hit-testing** (nearest object within a click radius) that scores a **find**,
    penalizes a **decoy**, and penalizes an empty-area **misclick** (breaking the combo).
  - **A combo** that grows the per-find score; a **hint** system (3/round) that reveals +
    pulses the next unfound target for 2.5s at a score cost.
  - **A per-round countdown timer** (running out = lose) with a **time bonus** on clearing;
    a live per-round **find checklist** for the UI; escalating **rounds** to a win.
  - **`checksum()`** — an FNV-1a fold over quantized positions + state — the cross-process
    determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** game including RNG state.
- **A deterministic solver auto-seat** — clicks each unfound target's exact position (it can
  see the scene) and uses one hint per round for coverage. `auto_step()` /
  `auto_play_to_end()` clear a whole game.
- **`GameManager` autoload** — runs the timer in `_physics_process`, plus the NoxDev save/load
  ABI and an `autoplay` toggle.
- **Play surface** (`scenes/hidden_view.tscn` + `scripts/hidden_view.gd`) — the play area, the
  objects (coloured **labelled placeholders** for real scene art + item sprites), a find-list
  checklist, a timer bar, the score/hints/misses HUD, and a **pulsing hint** highlight. Click
  objects to find them · **H** hint · **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — scene generation, click hit-testing, decoys, combo scoring, the hint system, the
timer, and round progression — lives in `HiddenEngine` as pure data + functions. The view only
translates a click into a scene-space position and reads state, which is why the whole game is
playable and testable with **no UI**.

Hidden-object games are an **art-first** genre: the engine here handles all the *logic*
(placement, hit-testing, scoring, hints, timer), and the real game is made by swapping the
coloured placeholder circles for a **painted background scene** with item sprites tucked into
it — the engine already stores each object's name, position, and target/decoy flag, so a
hand-authored layout drops straight in. Because placement is seeded, every run is reproducible,
which is what lets NoxQA smoke-run the solver headlessly and diff the checksum.

## How to extend

1. **Painted scenes + hand-placed hotspots**: replace `_start_round`/`_place` with authored
   scene data (a background + a list of `{name, pos, is_target}`); keep the rest of the engine.
2. **Item variety**: silhouette-match mode, "find 3 of a kind", or word-clue targets (the
   object dict is ready for extra fields).
3. **Zoom / magnifier + pan**: add a camera the view controls; the engine is resolution-free
   (positions are in area space).
4. **Anti-cheat click cooldown**: penalize rapid random clicking (a classic HO defence).
5. **Story mode**: chain scenes with a light narrative + collectibles between rounds.
6. **Difficulty modes**: tune `ROUND_TIME`, decoy count, `OBJ_R`, and hints at the top of the
   file, or make them per-scene.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed yields an identical final `checksum()` **and the same
  object placements**; a **different seed lays out a different scene**.
- **partial determinism** — 6 steps of the same seed produce an identical mid-game checksum.
- **real play** — the solver **finds every item across all rounds to a win**, scoring positive,
  with **zero misclicks** (proving placement, hit-testing, the find list, scoring, and round
  progression). Validated: a solver run **clears all 4 rounds (win), score 5720, 0 misclicks**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> won=true round=5 score=5720 misclicks=0
# → PROBE PASS
```
