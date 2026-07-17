# Rhythm Game Template (Guitar Hero / DDR / osu!mania-lite 4-lane note highway, 2D)

A Guitar-Hero / DDR / osu!-mania-lineage **rhythm game** run as a **deterministic
fixed-timestep sim** at 60 ticks/sec: a seeded **note chart** scrolls down four lanes
toward a hit line and the player taps each lane in time. It is OUR OWN engine with generic
content (no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py rhythm <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`RhythmEngine`** (`scripts/rhythm_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. The RNG only **builds the chart**; play is
  otherwise a pure function of the input stream, so a whole song replays **byte-identically**
  from a seed:
  - **Seeded chart generation** — BPM-derived beat spacing with **syncopation**, occasional
    **chords** (a second simultaneous note), and a no-repeat-lane bias.
  - **Judgment by timing window** — a tap judges against the nearest un-hit note in that
    lane: **Perfect** within ±2 ticks, **Good** within ±5, and a note that scrolls past the
    window unhit becomes a **Miss**.
  - **Combo + a tiered multiplier** (×1..×4) driving **score**; **accuracy** (%) and a
    letter **grade** (S / A / B / C / D); a proper song end with a final grade.
  - **`checksum()`** — an FNV-1a fold over the whole state — the cross-process determinism
    proof.
  - `save_data()` / `load_data()` snapshot the **entire** song including RNG state.
- **Deterministic auto-play seat** (`seat_input`) — a `"perfect"` policy taps every note
  exactly on time (full-combo of Perfects, grade S); a `"late<N>"` policy taps N ticks late
  so the Good/Miss tiers are exercised. `auto_step()` / `auto_play_to_end()` run a whole song.
- **`GameManager` autoload** — steps the sim in `_physics_process` (60Hz) with edge-triggered
  taps, plus the NoxDev save/load ABI and an `autoplay` attract toggle.
- **Play surface** (`scenes/rhythm_view.tscn` + `scripts/rhythm_view.gd`) — renders the
  4-lane highway (notes scrolling to the hit line), lane targets that **flash on press**, a
  **judgment flash**, a progress bar, and a score / combo / multiplier / accuracy / grade
  HUD. Tap **D/F/J/K** (or the arrow keys) · **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — chart generation, the timing-window judgment, combo/multiplier scoring,
accuracy + grade, and song flow — lives in `RhythmEngine` as pure data + functions stepped
by `tick({lanes:[...]})`. The view only samples taps and reads state, which is why the whole
song is playable and testable with **no UI**, and why it **drops in as the rhythm core of a
bigger game** (a music level, a hacking minigame): keep the engine, feed a `{lanes}` dict per
tick, read `score` / `combo` / `visible_notes()`.

**Ship a real song by binding audio to the chart.** `note.time` is in BPM-derived ticks, so
an authored beatmap maps straight onto it — replace `_gen_chart()` with a loaded map and start
the music at `START_OFFSET`. Because judgment is a pure function of tap-tick vs note-tick, the
same inputs always produce the same score, which is exactly what lets NoxQA smoke-run the
perfect seat headlessly and diff the checksum.

## How to extend

1. **Real music + authored charts**: swap the procedural generator for a loaded beatmap and
   sync playback to `START_OFFSET`; add per-lane hit sounds.
2. **Hold notes / sliders**: give a note a duration and judge the release; the note dict is
   ready for extra fields.
3. **Health / fail meter**: drain on Miss, restore on hits, and fail the song at 0 (osu-style).
4. **More lanes / difficulties**: `LANES` + the chart density are constants; add Easy/Normal/
   Hard chart variants.
5. **Modifiers**: mirror, faster scroll (`SCROLL_TICKS`), tighter windows (`PERFECT_W`/`GOOD_W`)
   for a hard mode.
6. **Leaderboards / replays**: a run is just a seed + the tap stream — store and replay it.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed played to completion twice yields an identical final
  `checksum()`; a **different seed produces a different chart**.
- **partial determinism** — 400 ticks of the same seed produce an identical mid-song checksum.
- **full combo** — the perfect seat hits **every note as a Perfect** (no misses), reaching a
  **full combo** and a **grade S**.
- **timing windows are enforced** — a **late seat scores strictly worse** than the perfect
  seat (proving the windows actually matter). Validated: perfect play full-combos an **80-note
  chart to grade-S 27500**, while a 4-tick-late seat scores **13750**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> total=80 score=27500 grade=S combo=80  late_score=13750 late_miss=0
# → PROBE PASS
```
