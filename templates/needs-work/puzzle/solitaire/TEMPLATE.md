# Solitaire Template (Klondike patience, draw-1, 2D)

A Klondike **solitaire** (patience) game run as a **deterministic sim**: a seeded 52-card shuffle
deals the classic 7-column tableau (1..7 cards, only the top of each face-up), a 24-card stock, a
waste pile, and 4 foundations (build A→K by suit). You draw from stock, build alternating-colour
descending runs across the tableau, uncover face-down cards, and race all 52 cards home to the
foundations. It is OUR OWN engine (cards are plain ints 0..51) — a pure, seedable, deterministic
engine. Scaffold with:

```bash
python templates/tools/scaffold.py solitaire <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

## What you get

- **`SolitaireEngine`** (`scripts/solitaire_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. Cards are plain ints (`suit = card/13`,
  `rank = card%13`); the whole game is integer state driven by one seeded RNG, so it replays
  **byte-identically** from a seed:
  - **A Fisher-Yates seeded deal** into the 7-column tableau + stock.
  - **Draw-1 stock** with bounded recycling/redeals.
  - **Correct tableau legality** — an empty column accepts only a King; otherwise opposite-colour +
    rank-1 — and **multi-card run moves** (the maximal alternating descending face-up run is
    detected by `run_start` and moved as a unit).
  - **Auto-flip** of an exposed face-down card, **foundation build-up** by suit, and **win / stuck**
    detection.
  - **`checksum()`** — an FNV-1a fold over the full state — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** game including RNG state.
- **A deterministic greedy solver auto-seat** — plays real games with sensible priorities: **safe**
  foundation auto-play (a card is safe home only when both opposite-colour foundations are ≥
  rank-1), uncovering tableau moves, waste plays, King-to-empty, a draw/recycle loop, and a
  last-resort forced-home to break stalls — with stall detection so it always terminates.
  `auto_step()` / `auto_play_to_end()` play a whole game.
- **`GameManager` autoload** — drives interactive moves (draw / select-then-place / send-home), plus
  the NoxDev save/load ABI and an `autoplay` toggle.
- **Play surface** (`scenes/solitaire_view.tscn` + `scripts/solitaire_view.gd`) — foundations, stock,
  waste and the 7 tableau columns with face-down/up cards, and click-to-move. **Click stock** = draw ·
  **click a card then a column** to move · **right-click** = send home · **H** = one solver move ·
  **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the deal, draw/recycle, tableau legality, run detection + moves, auto-flip, foundation
build-up, and win/stuck — lives in `SolitaireEngine` as pure data + functions. The view only renders
piles and forwards clicks, which is why a whole game is testable with **no UI**.

The move set is the interesting part: a *movable run* is the maximal opposite-colour descending
face-up sequence ending at a column's bottom (`run_start`), which the engine relocates as a unit and
then auto-flips whatever it uncovered. Because that legality lives in one place, the greedy solver
and the human's clicks call the *same* `tableau_to_tableau` / `*_to_foundation` — they can't diverge.
A 400-seed sweep of the greedy seat solves ~5.5 % of deals outright and makes real progress on the
rest; **seed 10 is solved end-to-end**, which is exactly what the probe pins.

## How to extend

1. **Drag-and-drop + double-click-home**: swap click-to-select for dragging a run, and double-click a
   card to send it to its foundation; add an **auto-complete** button once the board is all face-up.
2. **Undo + scoring/timer**: snapshot with `save_data()` per move for undo; add a Vegas/standard
   scoring mode and a timer.
3. **Other patience variants**: the int-card model + pile structure generalise to Spider, FreeCell,
   Pyramid — new legality functions, same shell.
4. **Daily deals**: seed from the date and add a streak calendar.
5. **Card art + juice**: the engine exposes every move for slide tweens, flip-on-uncover, and a win
   cascade.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed deals a different game**.
- **partial determinism** — 40 solver steps of the same seed produce an identical checksum across
  runs.
- **a real game** — the greedy solver plays a genuine game to a terminal. On **seed 10** it **solves
  the deal outright — 52/52 cards home in 123 moves, 1 redeal** (proof the whole move set works
  end-to-end); a second deal terminates as a legitimate stall with real progress.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> ft=52/52 moves=123 redeals=1 won=true  |  seedB ft=13 stuck=true
# → PROBE PASS
```
