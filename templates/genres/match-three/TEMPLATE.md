# Match Three Template (grid puzzle / minigame, 2D)

A match-3 grid puzzle (Bejeweled / Candy-Crush lineage) — the classic
dating-sim / gacha **minigame**, and a fine standalone puzzle. Swap two adjacent
gems; if that makes a line of 3+ it clears, gems fall in, new gems drop from the
top, and the cascades that chain from it score more. Scaffold with:

```bash
python templates/tools/scaffold.py match-three <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the whole board as
  pure, seedable, headless-testable logic:
  - An **8×8 grid** of gem type ids, generated with **no pre-made matches** and a
    **guaranteed legal move** (`new_board(seed)`; seed for a fixed opening).
  - **`try_swap(x1,y1,x2,y2)`** — the one entry point: only an **adjacent** swap
    that **makes a match** commits (otherwise the board is left exactly as it
    was), then it **resolves the full cascade** and returns
    `{legal, cleared, chains, gained}`.
  - **`find_matches()`** scans horizontal + vertical runs of 3+; the cascade loop
    clears them (**score = gems × 10 × the chain step**, so deeper cascades pay
    more), applies **gravity** (gems fall), **refills** from the top, and repeats
    until the board is stable.
  - **`has_legal_move()`** probes every adjacent swap; a **dead board
    auto-reshuffles** so play never stalls.
  - `score`, `moves`, and `save_data()/load_data()` of the exact board + score.
- **Board view** (`scenes/match3.tscn` + `scripts/match3.gd`) — the gem grid
  built in code (one button per cell, tinted by gem type), click a gem then an
  adjacent gem to swap, a score/moves HUD and a **chain banner** (`Chain x3! +180`).
  The scene stays a bare `Node2D` + script.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the
  exact board + score persist); `pause` + `restart` input; `"scalable_text"` on
  labels/buttons.

## The engine (the part worth understanding)

Every rule — no-match generation, swap validation, match detection, scoring,
gravity, refill, cascade chaining, dead-board reshuffle — lives in `GameManager`
and emits `board_changed`; the view only reads `gem_at()` and forwards
`try_swap()`. That is why the board is fully playable and testable with **no UI**,
and why it drops in as a **minigame** inside a larger game: instantiate the
autoload's logic, call `try_swap`, read `score`.

## How to extend

1. **Objectives / modes**: add a moves limit or a target score (a few fields +
   a check in `try_swap`); a timed mode; "collect N red gems" goals reading the
   `cleared` gems by type.
2. **Special gems**: a 4-match makes a line-clearer, a 5-match a color-bomb — add
   them in `_resolve_cascades()` where matches are cleared (check run length in
   `find_matches`).
3. **Feel**: hook `game-feel` onto swap/clear/cascade — pop/scale on clear,
   screen shake on big chains, particle bursts (the `chains` count is your
   intensity knob).
4. **Art**: swap the tinted buttons for real gem/candy sprites (recipes: 6 gem
   icons via `qwen-icon`, a board frame + backdrop via `zit-txt2img`); animate
   the fall/clear with tweens driven off `board_changed`.
5. **As a minigame**: keep `GameManager`'s engine, drive it from a sub-scene in
   your main game, and read `score` / `moves` back into the parent's economy.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the board already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
script errors, and three headless probes:

- **Board-engine probe** (pure `GameManager`, `fails=0`): a fresh board has 64
  valid gems, **no pre-made matches**, and a legal move; boards are
  **deterministic** under a seed; a **non-adjacent** swap and an **adjacent
  non-matching** swap are both rejected with the board left unchanged (and no
  move counted); a **matching swap** commits, clears ≥3, scores the chain,
  **settles with no leftover matches**, and leaves **no empty cells** after
  gravity + refill; and the board round-trips through `save_data()/load_data()`.
- **Scene smoke** (`match3.tscn`): boots with zero script errors.
- **UI-build probe** (`fails=0`): the view builds all **64 gem buttons** and
  handles selection/swap clicks without error.
