# Block Puzzle Template (Tetris-lite falling-block line-clearer, 2D)

A Tetris-lineage **falling-block puzzle**: stack the 7 tetrominoes in a 10×20 well and
clear full lines before the stack tops out. It is OUR OWN engine with generic content
(no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py block-puzzle <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`BlockEngine`** (`scripts/block_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. The RNG only drives the piece sequence, so a
  whole game replays **byte-identically** from a seed:
  - **A seeded 7-bag randomizer** (Fisher-Yates over the 7 types → each appears once per bag,
    the modern standard) — no droughts, and reproducible from the seed.
  - **All 7 tetrominoes** with their rotation states + real **collision**; **rotation with
    wall kicks** (tries x offsets 0, −1, +1, −2, +2).
  - **Gravity** on a level-scaled interval, plus **soft drop** + **hard drop** (with
    drop-distance points).
  - **Line clears** that shift the stack down with the classic single / double / triple /
    **Tetris** scoring (100 / 300 / 500 / 800 × level); **levels** that speed gravity every
    10 lines; a **next-piece** preview; and **top-out** game over.
  - **`checksum()`** — an FNV-1a fold over the board + piece + counters — the cross-process
    determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** game including the RNG + bag state.
- **A strong placement AI** (`ai_place`) — enumerates every rotation × column, drops the
  piece, and scores the resulting board with **Dellacherie-style weights** (aggregate
  height, holes, bumpiness, lines cleared), then executes the best placement.
  `auto_step()` / `auto_play_to_end()` drive a full game.
- **`GameManager` autoload** — steps gravity in `_physics_process`, plus the NoxDev save/load
  ABI and an `autoplay` attract toggle.
- **Play surface** (`scenes/block_view.tscn` + `scripts/block_view.gd`) — renders the well,
  the active piece with its **ghost** (landing preview), the **next-piece** box, and a
  score/lines/level HUD. **←/→** (or A/D) move with **DAS** auto-repeat · **↓** soft drop ·
  **Space** hard drop · **↑/X** rotate CW · **Z** rotate CCW · **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the 7-bag, collision, rotation + kicks, gravity, drops, line clears, scoring,
levels, and top-out — lives in `BlockEngine` as pure data + functions. The view only samples
input and reads state, which is why the whole game is playable and testable with **no UI**,
and why it **drops in as a minigame** anywhere (a hacking screen, a puzzle interlude): keep
the engine, feed a `{dx, rot, soft, hard}` dict per tick, read `board` / `piece` / `score`.

Because the only randomness is the **seeded bag**, `checksum()` after any number of pieces is
identical across two processes given the same seed and inputs — which lets NoxQA smoke-run
the placement AI headlessly and diff the checksum, and is the basis for **replays** and a
**versus** mode (same bag, two boards).

## How to extend

1. **Hold + swap**: add a hold slot (one buffered piece) and a swap key.
2. **SRS + T-spins**: replace the simple kick list with full SRS kick tables and detect
   T-spins for bonus scoring.
3. **Combo / back-to-back**: track consecutive clears + back-to-back Tetrises for the modern
   scoring bonuses.
4. **Marathon / sprint / ultra modes**: the engine already tracks lines + level + a piece
   count — gate win/lose on 40-lines, a time cap, or a score target.
5. **Versus / garbage**: run two engines on the same seed and send garbage rows on multi-line
   clears (deterministic → netcode-friendly).
6. **Tune the AI**: the Dellacherie weights are constants in `_eval_placement` — retune, or
   add lookahead using the next-piece.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed; the internal setter was named to avoid shadowing `Object._set`), a
**40-frame headless main-scene smoke** runs clean, and the headless **determinism +
playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed played out twice yields an identical final
  `checksum()`; a **different seed diverges** (different bag order).
- **partial determinism** — 40 placements of the same seed produce an identical mid-game
  checksum.
- **real play** — the placement AI clears **a lot of lines** and scores, proving collision,
  rotation, clears, and scoring all work. Validated: the AI clears **236 lines to level 24
  for score 339,790** over a 600-piece run **without ever topping out**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> pieces=601 lines=236 score=339790 level=24 over=false
# → PROBE PASS
```
