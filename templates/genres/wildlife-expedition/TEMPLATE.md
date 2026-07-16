# Wildlife Expedition Template (nature-exploration + wildlife-documentation board game, 2D)

A competitive **nature-exploration + wildlife-documentation** board game — a
National-Geographic-flavoured *original* genre engine (generic content, no
trademarks). It deliberately synthesises the **signature mechanics of three modern
classics** into one real depth engine, not a shallow generic loop:

- **the shared exploration TRAIL + resources + SEASONS** (the PARKS lineage),
- **a SPECIES-CARD TABLEAU engine with powers + season goals** (the Wingspan lineage),
- **BIODIVERSITY / set-variety end-game scoring** (the Cascadia lineage).

Scaffold with:

```bash
python templates/tools/scaffold.py wildlife-expedition <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`WildlifeEngine`** (`scripts/wildlife_engine.gd`) — the **whole rules engine** as
  a pure, seedable, headless-testable `RefCounted` `class_name`. No Godot node
  dependency, so the game **replays byte-identically from a seed** and can be driven
  with no UI at all. 2–5 players (1 human + heuristic AIs by default).
  - **Six tracked resources** (`sun`, `water`, `forest`, `mountain`, `sighting`,
    `film`) with a **strict conservation ledger** — `pool == start + produced − spent`,
    proven every turn (`verify_conservation()`); nothing appears or vanishes outside a
    named effect.
  - **The shared TRAIL** — 9 site tiles from a Start camp to the Trailhead. Each site
    has a **biome**, a **resource yield** and sometimes a small **action** (draw a
    species / restock gear). Pawns (2 each) advance **forward only**; good interior
    sites have limited **capacity**, so the trail is a race.
  - **Four SEASONS.** A season runs until every explorer reaches the Trailhead (or a
    round cap). At each boundary: **season income** (species + gear) fires, the active
    **season goal** scores, the **trail re-seeds** (its sites/bonuses shift) and pawns
    reset. After 4 seasons → final scoring.
  - **37 unique SPECIES** (×2 copies) — each a biome, a documentation **cost**, a
    **point** value, a **category** (mammal/bird/reptile/aquatic/insect/plant) and a
    real, varied **power**: gain resources now; chain a gain whenever you later document
    a matching category / any species; per-season income; draw-on-rest; or an end-game
    scoring hook. Documenting plays a species to your **field journal** (tableau) and
    **fires its power AND any chain powers already in your journal**.
  - **Observation gate** — you may only document a species whose biome one of your
    pawns is currently standing in; `sighting` resources are the observation currency
    (Binoculars gear discounts them).
  - **Four season GOALS** (one active per season) + **seven EXPEDITION contracts**
    (end-game bonus objectives).
  - **Set-variety scoring** — escalating tiers for **distinct categories** and
    **distinct biomes**, a **largest-single-category** bonus, per-species points, gear
    points, expeditions and accumulated goals. `final_scoring()` produces a per-player
    breakdown whose **components SUM to the total**, with a **single deterministic
    winner**.
  - **Gear / stations** — 6 developable gear cards (points + an ongoing perk:
    observation discount / film-on-document / biome bonus / season income).
  - A genuine **NON-LLM heuristic AI** (`ai_choose`) — enumerates every legal action
    and scores each by species value + power synergy + progress toward goals &
    expeditions + resource efficiency + diversity gain + trail-yield value; deterministic
    index tie-break; never illegal, never stalls.
  - Full **`to_dict()/from_dict()`** — banks + ledger + pawns + journals + hands + gear
    + trail + offer + gear shop + decks + season + goals + cursor + controllers + RNG
    state round-trip byte-identically.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `WildlifeEngine`,
  adds the NoxDev ABI (`save_data()/load_data()`), and is the **turn dispatcher** for
  the seat-controller matrix.
- **Board** (`scenes/board.tscn` + `scripts/board.gd`) — built in code: the trail
  (sites + biomes + yields + pawn markers), the shared species offer + your hand + the
  gear shop, per-player field journals + resources + live score + pawns, the
  season/goal/expedition track, a current-player indicator + a pass-the-device hand-off
  overlay, and a turn log. A human seat takes actions; AI seats auto-resolve into the log.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups; `pause` + `restart` input; `"scalable_text"`.

## Play modes — the seat-controller matrix

Every one of the 2–5 seats carries a `ControllerKind`:

- **`HUMAN_LOCAL`** — a local human; the dispatcher blocks for UI input.
- **`AI_HEURISTIC`** — the built-in weighted evaluator; auto-resolves.

Supported lineups: **all-AI** (`new_all_ai_game`, "watch the AI play"), **single-player
1-human-vs-AI** (the default `new_game`), and **LOCAL HOTSEAT** pass-and-play
(`new_hotseat_game`, 2+ humans on one machine) with a **"pass the device" hand-off**
before every human turn after the first.

- **`AI_LLM`** and **`REMOTE`** are **documented FUTURE seams** — present as enum values,
  **NOT wired and NOT stubbed**. `is_supported_kind()` is false for them and the
  dispatcher's default branch **fails loud** if one is ever assigned. Each drops in as
  **one dispatch `case` + one hook** (an LLM HTTP call / a network transport), exactly
  like the euro-engine-builder + cosmic-horror-coop templates carve them.

## The engine (the part worth understanding)

A turn is always **exactly one legal action** from `{MOVE, DOCUMENT, REST, DEVELOP}`;
`is_legal()` rejects out-of-turn / finished / move-backward / occupied-site / off-biome /
unaffordable / malformed actions, and `apply_action()` re-validates before mutating. Because
the engine is pure + seeded and every resource change goes through the `_gain`/`_spend`
ledger, the whole game is deterministic and conservation-provable. That is why it is fully
playable and testable **with no UI**, and why it **drops in as the board core of a larger
game**: keep the engine, drive it with `legal_actions()` + `apply_action()`, read the state.

Tuning is auditable constants at the top of the file: the resource set + values, the trail
length + site pool, the species/gear/goal/expedition databases, the scoring tiers, and the
AI weights.

## How to extend

1. **Real species art**: key card art by species id (37 across six categories) via
   `card-creature-art` / `zit-txt2img`; biome frames via `card-frame`; resource/goal icons
   via `qwen-icon`.
2. **More content**: add species to `SPECIES_DB` (new `power.kind`s drop into the two
   firing sites — `_do_document` for chains/immediate, `_end_season`/`score_powers` for
   ongoing), sites to `SITE_POOL`, contracts to `EXPEDITION_DB`, gear to `GEAR_DB`.
3. **Personas**: give each AI seat a `companion-npcs` persona + voice for table-talk; the
   same persona tags human seats on the hotseat hand-off banner.
4. **Wire a new seat kind**: implement `AI_LLM` or `REMOTE` by adding its `case` to
   `GameManager._advance_dispatch()` and flipping `is_supported_kind()` — the rest of the
   engine is untouched.

## Validation

Seven headless probes drove the engine to `fails=0` (deleted from the shipped skeleton):
a full 4-season all-AI game (single winner, components sum to totals, conservation every
turn, no illegal action, terminates); determinism (same seed → byte-identical, different
seed → different); rules/legality (rejections + species powers fire); scoring (a crafted
all-variety state hits an exact 173-point total); hotseat (mixed HUMAN/AI/HUMAN completes
with hand-offs); UI build (the board builds + a human action resolves); and save/load
(mid-game round-trips byte-identically).
