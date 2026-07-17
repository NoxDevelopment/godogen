# Bubble Shooter Template (Puzzle Bobble / Bust-a-Move hex match, 2D)

A Puzzle-Bobble / Bust-a-Move-lineage **bubble shooter** run as a **deterministic sim**: a
hex-packed grid of coloured bubbles hangs from the ceiling; you **aim** a shooter at the bottom
and **fire** the current bubble, which flies, **bounces** off the side walls, and **sticks** where
it lands. Landing next to 2+ of its own colour **pops** the whole connected same-colour group; any
bubbles left dangling (no path to the ceiling) then **drop** for a bonus. Clear the board to
**win**; let the stack reach the bottom line and you **lose**. It is OUR OWN engine with generic
content (no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py bubble-shooter <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

## What you get

- **`BubbleEngine`** (`scripts/bubble_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. Every shot is resolved by a fixed-step **ray-march
  + a nearest-empty-cell hex snap**, so a whole match replays **byte-identically** from a seed:
  - **Real hex packing** — even/odd offset rows with the correct **6-neighbour adjacency** (the
    thing most bubble-shooter clones get wrong), so groups, drops and the wall geometry are all
    honest.
  - **Wall-bounce ray-march physics** — the fired bubble marches along its aim vector, reflects
    off the side walls, and snaps into the empty grid cell it first touches (or the ceiling).
  - **Same-colour flood pop** (a connected group of ≥3 of the landed colour clears) and a
    **ceiling-connectivity flood** that then **drops every floater** (anything with no path back to
    row 0) for bonus points.
  - **A next-colour queue** drawn from the colours *still on the board*, so you can always make
    progress, and a whole-field **descent** every N shots that deals a fresh seeded top row — the
    pressure that actually ends matches.
  - A **win** when the board is cleared, a **loss** when the stack reaches the bottom line.
  - **`checksum()`** — an FNV-1a fold over the quantized board — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** board including RNG state.
- **A deterministic aim auto-seat** — evaluates a fan of candidate angles **on the real board**
  (it floods a *virtual* landing cell rather than copying the board), maximises pops, and otherwise
  lands as high as possible. `auto_step()` / `auto_play_to_end()` play a whole match.
- **`GameManager` autoload** — sets the aim + requests a fire, plus the NoxDev save/load ABI and an
  `autoplay` toggle.
- **Play surface** (`scenes/bubble_view.tscn` + `scripts/bubble_view.gd`) — the hex board, the
  shooter with its aim line and current + on-deck bubbles, and a score / popped / dropped / shots
  HUD. **Mouse** aims · **click / Space** fires · **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the hex grid + neighbour math, the ray-march physics, the flood pop, the floater
drop, the next-colour queue, and the descent — lives in `BubbleEngine` as pure data + functions.
The view only renders state and forwards aim/fire, which is why the whole match is testable with
**no UI**.

The reason the AI and the physics stay perfectly in sync is that they share one function:
`fire(angle)` and the AI's per-angle evaluation both call the *same* `_march()`. The AI never
duplicates the board — it floods a hypothetical landing cell in place — which (together with a
front-of-stack scan skip and squared-distance collision) took a full auto-match from **92 s down
to under 2 s**, a worth-knowing lesson in keeping a deterministic search cheap.

## How to extend

1. **Touch aim + a trajectory preview**: drag-to-aim (the mobile default) and a dotted preview line
   that reflects off the walls — the engine already exposes the exact march.
2. **Special bubbles**: bomb (clears a radius), rainbow (matches any colour), stone (unpoppable) —
   add kinds alongside the colour in the board dict.
3. **Authored levels + a level map**: hand-place the starting board and set per-level palette size,
   descent cadence and a clear goal (extend `setup`).
4. **A swap / on-deck control**: let the player swap the current and next bubble (a classic option).
5. **Boosters + scoring flair**: aim guides, extra-row pushers, combo multipliers on chained drops.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed deals a different board**.
- **partial determinism** — 12 shots of the same seed produce an identical checksum across runs.
- **a real match** — the aim AI plays a genuine match, popping seeded groups and dropping floaters,
  to a real terminal (a board clear, or the stack reaching the bottom line). Validated: the seat
  **pops 173 bubbles + drops 56 floaters for score 2850 over 76 shots** before the descending stack
  finally overruns the line.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> score=2850 popped=173 dropped=56 shots=76 won=false
# → PROBE PASS
```
