# TCG Duel Template (turn-based card game, 2D)

A collectible-card **duel** base: two players with mana curves, decks, hands, and
boards; play creatures and a damage spell; attack the enemy hero or trade with
their creatures; a greedy AI opponent takes its turn. The whole rules engine is
pure, headless-testable logic. Scaffold with:

```bash
python templates/tools/scaffold.py tcg-duel <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No third-party addons.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the duel engine as
  pure, seedable, headless-testable logic:
  - Two players (you = 0, opponent = 1), each with **life / mana / max-mana**, a
    shuffled **deck**, a **hand**, and a **board** of creatures.
  - A **data-driven card catalogue** (`CARDS`): creatures (Recruit 1/1 · Archer
    2/1 · Knight 2/3 · Golem 4/5) + a **spell** (Bolt, 3 damage) — add a card by
    adding an entry. `DECK_POOL` is the shared 20-card pool, Fisher-Yates
    shuffled by a **seedable RNG** (so tests + a fixed opening are deterministic).
  - Turn flow: `start_turn()` (mana +1 to 10, refill, draw, ready the board),
    `can_play()` / `play_card()` (creatures enter with summoning sickness; the
    spell hits the enemy hero or a chosen creature), `attack()` (hero or a trade,
    dead creatures cleared), `end_turn()`, `_check_winner()` (life ≤ 0), and a
    greedy `ai_take_turn()` for the opponent. Fatigue on an empty deck.
- **Duel view** (`scenes/main.tscn` + `scripts/duel.gd`) — both boards, your hand,
  life/mana readouts, an end-turn + new-duel button, all built in code and rebuilt
  on every state change. Click a hand card to play it, click a ready creature then
  a target (enemy hero or creature) to attack, end your turn and the AI answers.
  Esc pauses.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the
  whole duel — both players' life/mana/deck/hand/board — persists); a `pause`
  input action; `"scalable_text"` on the labels + card/creature buttons.

## The engine (the part worth understanding)

Every rule lives in `GameManager` and emits `changed`; the view only reads state
and forwards clicks, so the duel is fully playable and testable without any UI —
`setup(seed)` then `play_card()` / `attack()` / `end_turn()` / `ai_take_turn()`.
That separation is why the template ships with a headless probe that plays whole
turns and asserts mana costs, summoning sickness, face damage, trades, the spell,
win detection, and a save/load round-trip.

## How to extend

1. **Cards**: add to `CARDS` (+ into `DECK_POOL`). New keywords (taunt, heal,
   draw, buff) are a few lines in `play_card()` / `attack()`.
2. **Deck building**: replace the shared `DECK_POOL` with a per-player deck the
   player assembles in a pre-game screen; `_new_player()` already takes a list.
3. **Smarter AI**: `ai_take_turn()` is deliberately greedy — add trading, lethal
   detection, or a value heuristic.
4. **Art**: swap the creature/hand buttons for card scenes with real art (see the
   genre→workflow recipes: card frames + creature art via `zit-txt2img` /
   `qwen-icon`).
5. **Saving/menus**: godotsmith `save_system` / `menu_system` / `settings_system`
   drop in unchanged; the whole board state already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0, and a headless
probe: seats a deterministic duel, plays creatures (mana + summoning sickness
checked), swings at the hero and trades with a creature, casts the spell at a
target, drives the AI turn, and round-trips save/load — all green, zero script
errors; the live scene boots clean.
