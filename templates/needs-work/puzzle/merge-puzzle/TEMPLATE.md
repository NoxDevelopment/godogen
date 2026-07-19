# Merge Puzzle Template (2048-lineage slide-and-merge, 2D)

A 2048-lineage **merge puzzle** — the merge mechanic distilled, and one of the top mobile
puzzle subgenres: slide the 4×4 board in a direction, equal tiles **merge** into the next
tier, a new tile spawns, and you climb toward the 2048 tile. It is OUR OWN engine with generic
content (no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py merge-puzzle <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`MergeEngine`** (`scripts/merge_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG drives the tile spawns, so a
  whole game replays **byte-identically** from a seed:
  - **The canonical 2048 slide-and-merge** — per row/column: compact toward the move
    direction, merge each equal adjacent pair **once**, accumulate the merged value into score
    — in all four directions.
  - **A seeded spawn** (a 2, or a 4 at 10%) at a random empty cell after any board-changing move.
  - **Win** detection at the 2048 tile (play-on allowed); **game-over** detection when the board
    is full with no adjacent equal pair; best-tile + move + score tracking.
  - **`checksum()`** — an FNV-1a fold over the grid + score — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** game including RNG state.
- **A deterministic corner-heuristic auto-seat** (try down, left, right, up in priority — the
  classic keep-the-big-tile-in-a-corner strategy). `auto_step()` / `auto_play_to_end()` run to
  the end.
- **`GameManager` autoload** — applies moves on swipe/keys, plus the NoxDev save/load ABI and an
  `autoplay` toggle.
- **Play surface** (`scenes/merge_view.tscn` + `scripts/merge_view.gd`) — the tile grid (coloured
  by value), the score/best/moves HUD, and a game-over overlay. **Arrow keys / WASD / swipe** to
  slide · **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the slide-and-merge, the seeded spawn, win/lose detection, and the corner-heuristic
seat — lives in `MergeEngine` as pure data + functions. The view only reads the grid and forwards
a direction, which is why the whole game is playable and testable with **no UI**.

The one subtlety worth knowing is the classic 2048 merge rule the engine implements exactly: on
each line, you compact non-empty values toward the direction, then merge each **equal adjacent
pair once** (so `4 4 4` → `8 4`, not `16`), scoring the merged value. Because only the spawns are
seeded, the same seed + inputs reproduce the game, which lets NoxQA smoke-run the solver headlessly
and diff the checksum, and is the base for **daily-challenge** seeds and **replays**.

## How to extend

1. **Slide/merge tweens**: animate each tile to its target cell + a merge bounce (the state is
   grid-based, so tween from the pre-move grid to the post-move grid).
2. **Themed icons instead of numbers**: swap the value palette for an evolving icon ladder
   (creatures/food/gems) — the engine is value-based, so any per-value art set drops in.
3. **Bigger boards / different win tiles / obstacles**: `N` and `WIN_TILE` are constants; add
   blocker cells for variants.
4. **Undo + power-ups**: keep a move-history stack; add a "remove a tile" / "swap" power-up.
5. **A Merge-2/3 item board (Gossip Harbor / Merge Dragons)**: the mobile money-maker generalises
   the same merge idea to a **free board** — items of tiers you drag onto a matching tier to make
   tier+1, fed by a **generator** you tap. Reuse the merge rule; add a 2-D item board + a generator
   + an energy/orders meta.
6. **Daily challenge**: a fixed daily seed + a leaderboard (the run is seed-reproducible).
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed played out twice yields an identical final `checksum()`;
  a **different seed spawns a different board**.
- **partial determinism** — 30 moves of the same seed produce an identical checksum across runs.
- **a real game** — the corner-heuristic seat plays a long game (**many merges, a high tile, a
  positive score**) to a genuine game over. Validated: the seat plays **138 moves**, merges up to
  the **128 tile** for **score 1332**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> moves=138 best_tile=128 score=1332 won=false
# → PROBE PASS
```
