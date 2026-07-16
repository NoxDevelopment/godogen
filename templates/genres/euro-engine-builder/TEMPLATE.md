# Euro Engine-Builder Template (competitive resource→production→VP engine, 2D)

A competitive **Euro-style engine-builder** board game in the Scythe / Wingspan /
Wyrmspan lineage: every player grows a **resource → production → victory-point
engine**, and the **best engine wins**. 2–5 seats, each driven by a
**seat controller** — a local human or a heuristic AI — so the same build plays
**single-player (1 human vs heuristic AI)**, **all-AI**, or **local hotseat
(pass-and-play, 2+ humans on one machine)**. A shared action board, a
development-card deck, objective tokens, end-game majorities, and a hard end
trigger — the entire rules engine is **pure, seedable, headless-testable
GDScript** that replays byte-identically from a seed. Scaffold with:

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
- **Seat controllers + the play-mode matrix (STAGE 1)** — every seat carries a
  `ControllerKind` (`EuroEngine.ControllerKind`): **`HUMAN_LOCAL`** (the turn
  dispatcher blocks for local UI input) or **`AI_HEURISTIC`** (auto-resolves via
  `ai_choose()`). `configure_seats(kinds, names)` assigns them; the default preset
  is unchanged (seat 0 human, the rest AI). This changes only **who** produces a
  seat's action — the rules, RNG, and AI determinism are untouched, because a turn
  is always *"produce one legal action; `apply_action()` validates it."* Seat
  controllers + names round-trip through `to_dict()/from_dict()`.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `EuroEngine`,
  adds the NoxDev template ABI (`"game_manager"` + `"persistent"` groups,
  `save_data()/load_data()`), and is the **turn dispatcher**: `_advance_dispatch()`
  walks the cursor, auto-resolving AI seats and **blocking** on human seats.
  `submit_action()` applies the active human seat's action then resolves following
  seats to the next human (or game end); `human_action()` is kept as the legacy
  1-human alias.
- **Local hotseat (pass-and-play)** — when more than one seat is `HUMAN_LOCAL`,
  the dispatcher raises a **`handoff_requested`** signal before **every human turn
  after the first**; `board.gd` shows a *"pass the device — &lt;name&gt;'s turn"*
  overlay with a **Ready** button (`acknowledge_handoff()`), then reveals/accepts
  that human's input. AI turns in between auto-resolve into the log with no banner.
  One machine, one input — no networking. Presets: `new_game()` (1 human vs AI),
  `new_hotseat_game(humans, ais)`, or `configure_game(kinds, names)`.
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
5. **More play modes (LLM-assist / networked-remote)**: the seat-controller
   dispatch is an **open seam**. Add a value to `EuroEngine.ControllerKind` and a
   matching `case` in `GameManager._advance_dispatch()`, then one hook:
   **`AI_LLM`** → call an LLM provider (e.g. `companion_ai_ml`) that picks from
   `legal_actions()`, validated by `is_legal()/apply_action()` like any action;
   **`REMOTE`** → `await` a transport that delivers the seat's chosen action, then
   `apply_action()`. These are deliberately **not present** in Stage 1 (no stubs);
   the dispatcher's default branch asserts a clear error on any unwired kind, so a
   half-added mode fails loud instead of silently passing.
7. **Art**: swap the card buttons for real card art + a board mat (recipes below).
8. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the whole game already serialises.

## Play modes

| Mode | Setup call | Seats | Turn flow |
|------|-----------|-------|-----------|
| **Single-player** (default) | `new_game()` | seat 0 human, rest `AI_HEURISTIC` | human acts, AIs auto-resolve back to the human |
| **All-AI** | `configure_game([AI, AI, …])` | every seat `AI_HEURISTIC` | the whole game auto-plays |
| **Local hotseat** | `new_hotseat_game(humans, ais)` or `configure_game([HUMAN, HUMAN, …])` | 2+ `HUMAN_LOCAL` | pass-and-play: a "pass the device" hand-off banner before every human turn after the first |

**Extension point (Stage 2+):** `AI_LLM` (LLM-assisted seat) and `REMOTE`
(networked seat) slot into the same dispatch as one new `ControllerKind` value +
one `case` in `GameManager._advance_dispatch()` + a provider/network hook — they
are **not present** in Stage 1 and the dispatcher asserts a clear error on any
unwired kind (never silently passes). See *How to extend #5*.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with
zero script errors, and headless probes (all `fails=0`) covering both the core
engine and the play-mode matrix (seat controllers + local hotseat):

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
- **Hotseat probe (mixed)**: a 4-seat `HUMAN, AI, HUMAN, AI` game played in full
  via the real dispatcher — the correct controller resolved each seat (humans via
  scripted legal input, AIs via `ai_choose`, proven by equality with an
  independent oracle replay), a legal winner, conservation held, no illegal action.
- **All-human hotseat probe**: a 2-seat all-human game completes with a legal
  winner and a hand-off is signalled before **every** human turn after the first.
- **Play-mode determinism probe**: fixed human inputs + a fixed seed replay
  byte-identically (mixed hotseat, all-human, all-AI); a different seed diverges.
- **Regression probe**: the pre-existing all-AI game and the default
  1-human-vs-AI game still complete with all core invariants intact and the AI-seat
  behaviour unchanged (dispatcher output equals an `ai_choose` oracle).
- **Play-mode UI-build probe**: `board.tscn` builds, a `HUMAN_LOCAL` legal action
  resolves through the new dispatch and updates state, and the hand-off banner
  appears for a hotseat config then clears on Ready.
