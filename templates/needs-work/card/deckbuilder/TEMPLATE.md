# Deckbuilder Template (roguelike, Slay-the-Spire-like)

A full **roguelike deckbuilder**: card combat on **card-framework** (chun92)
wrapped in a **run** — a branching map of nodes you route through, with your HP,
gold, deck and relics persisting from fight to fight, up to a boss. Scaffold
with:

```bash
python templates/tools/scaffold.py deckbuilder <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable) with card-framework
**v1.4.0** (pinned tag + commit; upstream targets Godot 4.6+; script-only kit,
nothing to enable in `[editor_plugins]`).

## The roguelike run (the part worth understanding)

The game opens on the **map hub** (`scenes/map.tscn` + `scripts/map.gd`), not on
a combat. The whole run lives in **`GameManager`** as pure, seedable,
headless-testable logic — the hub and the combat scene only read it and forward
clicks (the same separation as the tcg-duel engine):

- **A generated node map** — `NUM_FLOORS` floors of `combat / elite / event /
  rest / boss` nodes, wired into a **connected DAG** (every node reachable from
  the prior floor, no dead ends before the single boss on the top floor). Seed
  it for a fixed showcase or `0` for a random run.
- **Persistent run state** — `hp` / `max_hp`, `gold`, a growing `deck`, and
  `relics`, all carried between fights. A **rest** node heals 30% max HP; an
  **event** node rolls gold / a relic / a small heal.
- **Combat feedback** — `enter_node()` hands combat/elite/boss nodes to the
  combat scene; `resolve_combat(win, hp_remaining)` feeds the result back: HP
  persists, gold + (on elites/boss) a **relic** are earned, the map advances,
  the **boss** ends the run. A win offers a **card reward** (`roll_rewards()` →
  pick 1 of 3 → `add_card()`).
- **Relics** are passive modifiers the combat scene queries each fight —
  `relic_bonus_energy()` (+1 energy/turn), `relic_start_block()` (+5 block at
  turn start), `relic_heal_on_kill()` (+3 HP on a kill); stacking relics grant
  more than once.
- **Persistence** — `save_data()/load_data()` round-trip the ENTIRE run (map,
  position, HP, gold, deck, relics), so godotsmith's `save_system` drop-in
  persists a run in progress with no extra wiring.

When **no run is active**, the combat scene (`scenes/main.tscn`) still plays
standalone against the default Cog-Golem — so the base combat loop and its boot
probe are unchanged, and you can iterate on combat in isolation.

## Kit decision (documented per roadmap)

The roadmap's deckbuilder row named **DesirePathGames/Slay-The-Robot** (MIT,
very active). Evaluated 2026-07-11: it is a **complete game** — game scenes,
autoloads, `data/` card definitions and mod support live at the repo root; there
is no addon payload to vendor, and vendoring a whole game contradicts the
skeleton model. Decision: vendor **chun92/card-framework** (the reusable card
engine: containers, drag-drop, JSON card factory) and build the combat loop
first-party; the **run/map layer above is now built first-party too** (Slay-The-
Robot remains an MIT *reference* for deeper mod/run structure).

## Kit decision (documented per roadmap)

The roadmap's deckbuilder row named **DesirePathGames/Slay-The-Robot** (MIT,
very active). Evaluated 2026-07-11: it is a **complete game** — game scenes,
autoloads, `data/` card definitions and mod support live at the repo root; there
is no addon payload to vendor, and vendoring a whole game contradicts the
skeleton model. Decision: vendor **chun92/card-framework** (the reusable card
engine: containers, drag-drop, JSON card factory) and build the combat loop
first-party; keep Slay-The-Robot as an MIT *reference* for meta-structure
(JSON card mods, run/map structure) when growing past one combat.

## What you get

- **card-framework wired end to end**: `CardManager` + a `JsonCardFactory`
  scene pointed at this project's `cards/` (`card_asset_dir = res://cards/art`,
  `card_info_dir = res://cards/data`), Piles for **Deck** (face-down, not
  draggable), **Discard**, a fanned **Hand**, and a **PlayArea** drop target.
- **5 JSON-defined cards** (`cards/data/*.json` + generated 150x210 blockout
  art): Strike (1⚡ deal 6), Cleave (2⚡ deal 9), Defend (1⚡ block 5), Insight
  (1⚡ draw 2), Surge (0⚡ gain 2⚡). The JSON schema is card-framework's
  (`name`/`front_image`) plus our game fields (`display_name`, `type`, `cost`,
  `amount`, `description`).
- **Readable card faces**: `scenes/game_card.tscn` extends the framework's
  `Card` with name/cost/description labels populated from `card_info`.
- **The combat loop** (`scripts/main.gd`): 10-card starting deck, draw to 5,
  3 energy per turn, **drag a card onto the play area** (or call
  `main.play_card(card)`) to resolve it, played cards go to the discard, the
  discard **reshuffles into the deck** when it runs dry, End Turn discards your
  hand and the Cog-Golem (30 HP, attacks 8 through your block) acts.
  Victory/defeat banners with a New Combat button.
- **PlayArea hook** (`scripts/play_area.gd`, extends `Pile`): validates drops
  through a `can_play` Callable (energy check) and emits `card_played` when a
  card finishes arriving — the single seam where game rules meet the framework.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"game_manager"` +
  `"persistent"` on `GameManager` (`cards_played` / `battles_won` flags),
  `save_data()/load_data()`, `pause` action, `"scalable_text"` on labels.

## How the pieces fit (the part worth understanding)

card-framework cards are **Controls owned by containers**; all movement goes
through `container.move_cards(cards)` which validates via the target's
`_card_can_be_added()` and animates the card over. Drag-and-drop is the same
path — so the PlayArea's two overrides (`_card_can_be_added` = cost check,
`on_card_move_done` = resolve effect) cover mouse play and programmatic play
identically. `CardManager` must stay above every container in the scene and
keeps drag/undo history; system moves (draw, discard, reshuffle) pass
`with_history = false` so player-undo never rewinds game rules.

## How to extend

1. **New cards**: drop a JSON in `cards/data/` + art in `cards/art/` — the
   factory preloads the whole directory; add the name to `STARTING_DECK` (or a
   run-time deck list). New effect types = one `match` arm in
   `main._on_card_played`.
2. **Targeting/multiple enemies**: emit the card and a target from a drop zone
   per enemy (duplicate PlayArea with an `enemy_index`), or add a targeting
   cursor after `card_played`.
3. **Enemy AI/intents**: `end_turn()` is the enemy's slot — swap the fixed
   attack for an intent list (attack/defend/buff) shown in the IntentLabel.
4. **Run structure** (built): the map/rewards/relics/persistence live in
   `GameManager` — extend the run by adding node types (a shop that spends
   `gold`; an event with a choice) in `map._on_node` + `GameManager.enter_node`,
   new relics in the `RELICS` catalogue (+ a query method combat reads), or
   rarer reward cards (a JSON in `cards/` + an id in `REWARD_POOL`). Tune
   `NUM_FLOORS`, encounter scaling in `current_encounter()`, and gold/heal
   amounts at the top of `GameManager`.
5. **Art/theming**: replace `cards/art/*.png` (150x210, filenames referenced
   from the JSONs) via `image-pipeline`; theme the HUD with `ui-theme`;
   `game-feel` hooks onto `play_area.card_played` for hit shake/flash.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` /
   `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
script errors; both scenes boot clean; and the roguelike run engine passes a
headless probe.

- **Combat standalone smoke** (`scenes/main.tscn`, no run) still fires its boot
  probe unchanged — the base loop is preserved:

  ```
  DEBUG: deckbuilder core loop ready — deck=5 hand=5 discard=0 energy=3/3 enemy_hp=30 turn=1 run=false
  ```

- **Map hub smoke** (`scenes/map.tscn`, the entry scene) boots with zero script
  errors and builds the node map.
- **Run-engine probe** (pure `GameManager`, `fails=0`): a fresh run has the
  right shape (50 HP, 13-card deck, `NUM_FLOORS` floors, single boss on top);
  the map is a connected DAG (no orphans, no non-boss dead ends); a win persists
  HP + gold + the `battles_won` flag and advances the map; `roll_rewards()`
  offers 3 and `add_card()` grows the deck; the relic query API returns the
  right bonuses; a loss ends the run; an **always-win playthrough reaches the
  boss and wins the run**; and `save_data()/load_data()` round-trips the whole
  run (HP/gold/deck/map/position).
- **Combat integration probe** (`fails=0`): with a run active, the combat scene
  pulls its player max HP (50), the node's scaled encounter HP, and its energy
  (base + relic bonus) from the run — proving the run→combat seam.

## Vendored addon notes

- License: MIT (`addons/card-framework/LICENSE.md` — upstream ships the
  license inside the addon; manifest in `addons/LICENSES.md`).
- Docs: https://github.com/chun92/card-framework (README + `docs/`; the
  repo's `example1` and full FreeCell game show framework idioms).
- One pinned patch silences upstream's per-card "Preloaded card data" print
  (one line per card on every boot).
