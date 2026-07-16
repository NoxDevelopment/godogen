# Poker Roguelike Template (Balatro-style deck-scoring roguelike, 2D)

A Balatro-lineage **poker-scoring roguelike**: draw a hand, play a 1-5 card poker
hand to beat an escalating score **target**, and warp the math with **jokers** +
planet-style **hand-level upgrades** bought in a shop between blinds. It is OUR
OWN engine with generic content (no trademarks) — a PURE, seedable, deterministic
scoring engine, the ideal fit for the NoxDev pure-engine pattern. Scaffold with:

```bash
python templates/tools/scaffold.py poker-roguelike <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`PokerEngine`** (`scripts/poker_engine.gd`) — a pure `RefCounted` engine with
  ZERO Godot-node dependency, so an entire run replays **byte-identically** from a
  seed and can be driven with no UI at all:
  - A **52-card deck** (rank 2..14, suit 0..3); cards can carry an **enhancement**
    (bonus / mult / glass / wild). Draw `HAND_SIZE` (8); the player selects 1-5.
  - **Real poker hand detection** for all **12 types** — high-card through
    straight-flush PLUS the enhanced hands (five-of-a-kind, flush-house,
    flush-five) — correct on the **wheel** (A-2-3-4-5) and **ace-high** straights,
    and on flush vs straight-flush / full-house vs two-pair edge cases.
  - **EXACT deterministic scoring**: `score = (base_chips[type][level] +
    scored-card chips) × (base_mult[type][level] + card mult)`, then every joker
    applies **in slot order** (+chips / +mult / ×mult, conditionally), then
    `chips × mult` rounded half-up. `score_breakdown()` returns **every
    component** so the math is auditable and testable to the number.
  - **25 jokers** with genuinely varied, functional effects — flat +mult/+chips,
    ×mult, conditional (fires only if the hand contains a pair/flush/straight/…),
    per-held-card, per-discard, per-joker, per-money, retrigger-the-first-card,
    and **scaling jokers** that grow as the run progresses. Up to 5 held, applied
    in order.
  - **Planet-style hand levels**: a shop upgrade permanently raises a hand type's
    base chips + mult.
  - **Run structure**: antes **1..8**, each = small / big / boss blind with an
    escalating **target**; N hands + M discards per blind; a **shop** between
    blinds sells jokers + hand upgrades for **money** (blind reward + interest).
    **WIN** = clear the final ante's boss; **LOSE** = fail a blind's target within
    your hands. Both genuinely reachable.
  - A deterministic **auto-play** heuristic (`best_play()` / `auto_take_turn()`)
    that enumerates every legal 1-5 card play, keeps the highest-scoring, discards
    weak cards when it helps, and buys sensible shop items — it drives a whole run
    headlessly (it is NOT an opponent; poker-roguelike is solo).
  - `is_legal()` rejects illegal plays (0 or >5 cards, discarding with none left,
    buying with no money / a full joker board), and `to_dict()/from_dict()` save
    and restore the **entire** run including RNG state.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `PokerEngine`,
  adds the NoxDev ABI (`game_manager` + `persistent` groups,
  `save_data()/load_data()`), forwards a human's chosen action, and emits
  `changed` so the view redraws.
- **Play surface** (`scenes/table.tscn` + `scripts/table.gd`) — built in code: the
  ante / blind / target + running score, money + hands/discards left, the hand as
  **selectable** card buttons (capped at 5), the joker slots, **Play / Discard**
  buttons, a simple **shop** panel between blinds, an **Auto Step** button that
  demos the deterministic auto-play, and a log.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `pause` + `restart`
  input; `"scalable_text"` group on every label/button.

## The engine (the part worth understanding)

Every rule — hand detection, the exact scoring pipeline, all 25 joker effects,
hand-level ramps, the ante/blind/target schedule, the shop economy, and the
auto-play heuristic — lives in `PokerEngine` as pure data + functions. The table
only reads state and forwards a click, which is why the whole game is playable and
testable with **no UI**, and why it **drops in as the scoring core of a larger
game**: keep the engine, call `play()`, read `round_score`. Because the tuning
tables (`HAND_BASE`, `JOKER_DB`, `ANTE_BASE`) are explicit constants at the top of
the file, they are auditable and easy to rebalance.

The scoring pipeline in one line: **base (chips, mult) for the hand type at its
current level → add each scored card's chips + its enhancement → apply every joker
in slot order → multiply chips × mult, rounded half-up.**

## How to extend

1. **More jokers**: add an entry to `JOKER_DB` and a branch in `_apply_joker()` —
   the shop, save/load, and UI pick it up with no other change.
2. **Card enhancements / editions**: extend `ENHANCEMENTS` and the per-card block
   in `score_breakdown()` (steel, stone, foil/holo/polychrome editions).
3. **Boss-blind debuffs**: give the boss blind a modifier (e.g. "clubs score 0",
   "only 3 hands") in `_begin_blind()` — the engine already isolates each blind.
4. **Consumables / tarot**: add a shop item kind alongside `joker` / `planet` in
   `_roll_shop()` + `buy()`.
5. **Art**: swap the text card buttons for real card faces + joker art (recipes:
   card faces via `card-frame`, joker art via `card-creature-art`, chip/coin icons
   via `qwen-icon`).
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the whole run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with
zero script errors (all vars typed), and **seven** headless probes all `fails=0`:

- **hand-eval** — every one of the 12 poker hand types is detected correctly on
  crafted hands, including the wheel + ace-high straights, flush vs straight-flush,
  full-house vs two-pair, and a wild card completing a flush; scored-index
  selection is correct.
- **scoring** (the most important) — crafted hands + specific jokers produce
  EXACT totals, asserted component-by-component (base chips, card chips, mult, each
  joker's effect in slot order, final rounded score).
- **jokers** — a sample of distinct jokers each produce their expected score delta;
  conditional jokers fire ONLY when their condition holds (e.g. Crafty is silent
  without a flush, Mystic Summit only at 0 discards).
- **full-run** — an auto-play run WINS on an easy config (clears all 8 antes) and
  LOSES on a hard one (misses a blind); legal states throughout, zero illegal
  actions, terminates within a step cap. Both a win and a loss are reachable.
- **determinism** — same seed → byte-identical run (deck order, shop, every step's
  full state, final result); a different seed diverges.
- **shop/economy** — buy a joker (money spent, joker slotted), sell it (money
  returned, slot freed), level a hand (base chips rise); illegal buys rejected.
- **ui-build + save/load** — the scene builds (hand + jokers + blind + shop panels
  present), a play resolves + updates the score, and a mid-run save → mutate →
  load equals the snapshot (both `PokerEngine` and the `GameManager` ABI).
