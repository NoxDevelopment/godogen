# Gacha Summon Template (collection / pity system, 2D)

The summon + collection core of a companion-collection game (Genshin / FGO
lineage) — the on-mission heart of a waifu/companion roster. Spend premium gems
to pull against published rates with a **fair pity system**, draw a character
from the banner, and build a collection. Scaffold with:

```bash
python templates/tools/scaffold.py gacha-summon <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the whole gacha as
  pure, seedable, headless-testable logic:
  - A **wallet** of premium `gems` and a `PULL_COST`; **single and 10-pulls**
    that spend per pull and **stop when the wallet runs dry**.
  - Published **rates** (3★ / 4★ / 5★) with a real **pity system**: the 5★ rate
    **ramps from soft pity (74)** and is **guaranteed at hard pity (90)**, and a
    **4★-or-better is guaranteed every 10** pulls. A 5★ resets both counters.
  - `pull(count)` returns per-pull results `{rarity, item, dupe, pity5_at}`;
    `current_five_chance()` exposes the live pity-adjusted odds so the screen can
    show them honestly.
  - A **collection** (`owned`) that tracks **dupes**, with `count_of()` /
    `unique_owned()` / `owned_of_rarity()` for the roster screen.
  - `save_data()/load_data()` of the wallet + pity + the whole collection.
  - A **data-driven `POOL`** (rarity → names) — swap it for your own roster; no
    other change.
- **Summon screen** (`scenes/gacha.tscn` + `scripts/gacha.gd`) — built in code:
  the wallet + pity + **next-5★ chance**, **Pull ×1 / Pull ×10** (disabled when
  you can't afford them), the last results (rarity-coloured, dupes marked), and
  the collection by rarity. A `+1600 gems` button for testing.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (wallet
  + pity + collection persist); `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

Every rule — rates, the soft/hard 5★ pity ramp, the 4★ guarantee, wallet limits,
dupe tracking — lives in `GameManager` and emits `gacha_changed`; the screen only
reads state and forwards pulls. That is why it is fully playable and testable
with **no UI**, and why it **drops in as the summon screen of a larger game**:
keep the engine, call `pull()`, read `owned`. Because rates + pity are explicit
constants at the top of the file, they are auditable and easy to tune to your
published rates.

## How to extend

1. **Real companions**: make the 5★/4★ `POOL` entries real characters — give each
   a `companion-npcs` persona + voice so a pulled unit joins the roster and can
   chat (this is the bridge to the VN / dating-sim side).
2. **Dupe conversion**: turn a `dupe` result into constellation/eidolon shards or
   a currency in `pull()` where the collection is updated.
3. **Multiple banners**: make `POOL` + the featured unit a Banner object and pick
   the active one; add a **rate-up / 50-50** featured mechanic in `_roll_rarity`.
4. **Art**: swap the text rows for character cards + rarity frames (recipes:
   character art via `card-creature-art`, rarity frames via `card-frame`,
   star/gem icons via `qwen-icon`, a banner splash via `zit-txt2img`).
5. **Economy**: wire `add_gems()` to dailies / rewards from your other game
   modes; the wallet already persists.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the account already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
script errors, and three headless probes:

- **Gacha-engine probe** (pure `GameManager`, `fails=0`): a fresh account starts
  with the wallet + clean pity; a pull spends exactly one pull's gems and banks
  one item; a **10-pull with one pull's gems yields exactly one and never
  overdraws**; a **5★ is guaranteed within hard pity** (and the counter resets
  after); a **4★-or-better appears within 10 pulls**; `current_five_chance()` is
  the base rate at 0 pity and **1.0 at hard pity**; pulls are **deterministic**
  under a seed; and the account round-trips through `save_data()/load_data()`.
- **Scene smoke** (`gacha.tscn`): boots with zero script errors.
- **UI-build probe** (`fails=0`): a 10-pull renders 10 rarity-coloured result
  rows and populates the collection — the screen↔engine wiring is live.
