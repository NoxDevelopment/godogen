# Euro Engine-Builder Template (competitive resource→production→VP engine, 2D)

A competitive **Euro-style engine-builder** board game in the Scythe / Wingspan /
Wyrmspan lineage: every player grows a **resource → production → victory-point
engine**, and the **best engine wins**. 1 human + up to 4 heuristic-AI opponents,
a shared action board, a development-card deck, objective tokens, end-game
majorities, and a hard end trigger — the entire rules engine is **pure, seedable,
headless-testable GDScript** that replays byte-identically from a seed. Scaffold
with:

```bash
python templates/tools/scaffold.py euro-engine-builder <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`EuroEngine`** (`scripts/euro_engine.gd`) — the whole game as a pure
  `RefCounted` class with **no node dependency**, so it is fully playable and
  testable with no UI:
  - **5 tracked resources** (wood, grain, metal, coin, energy) with a strict
    **conservation ledger** — every unit is produced or spent by a named effect
    (`_gain`/`_spend`), and `verify_conservation()` proves `pool == start +
    produced − spent` for every player, every resource, every turn.
  - A **25-card development deck** (5 categories × 5 cards, 3 copies each = a
    75-card shared deck) shuffled by the seeded RNG. Each card has a resource
    **cost**, a per-PRODUCE **output**, a **category**, and a **VP** value.
  - A **shared action board of 5 action types** — **PRODUCE / BUILD / TRADE /
    RESEARCH / DEPLOY**. On a turn a player takes exactly **one legal action**;
    `legal_actions()` enumerates them and `is_legal()` rejects anything illegal
    (out of turn, unaffordable, malformed).
  - **Objective tokens (3 distinct types)** claimed first-come during play —
    *industrialist* (build 3 mining cards), *self-sufficient* (reach 3 stars),
    *trade-baron* (bank 12 coin) — plus **end-game majorities** (most stars, most
    cards, most coin), plus VP from built cards and goal-stars.
  - **End trigger**: first player to **6 goal-stars** (planted via DEPLOY) ends
    the game at the round boundary, else the game ends after **18 rounds** →
    `final_scoring()` with a **single deterministic winner** (tie-break: total →
    stars → cards → seat).
  - A **non-LLM heuristic AI** (`ai_choose()`): enumerates **every legal action**
    and scores each with a **weighted evaluation** — immediate VP + resource-
    efficiency (cost valued by `RESOURCE_VALUE`) + engine growth (the per-turn
    production a build adds, credited across a light lookahead horizon) +
    progress-to-goal (DEPLOY scales up **quadratically** as stars near the goal) +
    option value (RESEARCH) / conversion value (TRADE). Picks the best,
    **deterministic index tie-break**. It never picks an illegal action and never
    stalls (PRODUCE is always available).
  - `to_dict()`/`from_dict()` round-trip the **entire game** (banks, tableaus,
    hands, stars, deck, objectives, cursor, RNG state) — JSON-safe.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `EuroEngine`
  and adds the NoxDev template ABI: `"game_manager"` + `"persistent"` groups,
  `save_data()/load_data()` (the whole game persists), and `human_action()` which
  applies the human's seat-0 action then auto-runs every AI seat back to the human.
- **Board screen** (`scenes/board.tscn` + `scripts/board.gd`) — built in code:
  the shared action board, your hand as **BUILD** buttons, a per-player panel
  (resources, VP, stars, production summary, tableau), the objective tokens, a
  current-player indicator, and a turn log. Legal actions are the only enabled
  ones; AI turns auto-resolve into the log.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `pause` + `restart`
  input; `"scalable_text"` labels; ColorRect/Label placeholders (no art
  dependency — recipes below).

## The engine (the part worth understanding)

Every rule — the resource ledger, card costs/outputs, the five actions, objective
tokens, majorities, the star end-trigger, and the AI — lives in `EuroEngine` and
is pure data + math. `GameManager` only persists it and drives the AI seats;
`board.gd` only reads state and forwards one click. That is why the game is fully
playable and testable **with no UI**, why it **replays byte-identically from a
seed**, and why it **drops into a larger game**: keep the engine, call
`apply_action()`, read `final_scores`. The AI is a genuine weighted evaluator
(not random) whose weights are auditable constants at the top of the file.

## How to extend

1. **More cards**: add entries to `CARD_DB` (id → name/category/cost/output/vp) —
   the deck, UI, objectives and AI all pick them up with no other change.
2. **Scythe-style combos**: let BUILD also trigger a mini-PRODUCE (a "top+bottom"
   action) by chaining two effects in `apply_action`.
3. **Player asymmetry**: give each seat a starting bonus card or a resource
   discount in `_new_player` for faction variety.
4. **Harder AI**: extend `ai_choose` with a true 1-ply lookahead (clone via
   `to_dict()`/`from_dict()`, apply each action, evaluate the resulting position).
5. **Art**: swap the card buttons for real card art + a board mat (recipes below).
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the whole game already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with
zero script errors, and five headless probes (all `fails=0`):

- **Full-game engine probe**: plays a COMPLETE all-AI game from a fixed seed to
  the end trigger — a single legal winner, every VP total equals the sum of its
  sources, resource conservation held every turn, no illegal action ever taken,
  terminated within the round cap.
- **Determinism probe**: the same seed twice → byte-identical final snapshot
  (winner, all VP, all pools); a different seed → a different game trace.
- **Rules/legality probe**: seven illegal actions (out of turn, unaffordable
  build/deploy, underfunded/self trade, unknown type, bad index) each rejected
  with game state unchanged; a full all-AI game emits only legal actions.
- **UI-build probe**: the board scene builds headless (action board + 4 player
  panels + resource labels), and a scripted human BUILD then PRODUCE resolves and
  updates the tableau / resources.
- **Save/load probe**: mid-game save → mutate → JSON round-trip → load → restored
  state equals the saved snapshot, and the loaded game resumes to completion.
