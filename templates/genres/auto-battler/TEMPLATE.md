# Auto Battler Template (Super Auto Pets / "How Many Dudes" team-shop roguelite, 2D)

A Super-Auto-Pets / "How Many Dudes"-lineage **auto-battler** roguelite: draft a roster of
"Dudes" from a rolling **gold shop**, build **ability + synergy** combos, then watch the team
**auto-resolve** combat (no per-unit input) against **escalating** enemy waves — win trophies,
lose lives, and either win the run or run out of lives. It is OUR OWN engine with generic
content (no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py auto-battler <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`AutoBattlerEngine`** (`scripts/autobattler_engine.gd`) — a pure `RefCounted` engine with
  ZERO Godot-node dependency and ZERO `Time` calls. One seeded RNG drives the shop + the enemy
  waves, so a whole run replays **byte-identically** from a seed:
  - **A 9-unit pool** of Dudes with atk / hp / tier / tag + **abilities** — **zap**
    (start-of-battle: damage the enemy front), **rage** (on-hurt: +atk), **vengeance**
    (on-faint: buff the ally behind), **mend** (each tick: heal the weakest ally), **coin**
    (on-buy: +gold).
  - **A rolling shop** (buy / sell / **roll** / **freeze**, tier-gated by round) with a gold
    economy; a **team** (front→back order) capped at 5.
  - **Team synergies** (3+ melee → +atk, 2+ support → +hp, 2+ magic → extra zap) recomputed on
    every buy/sell.
  - **Escalating enemy waves** that add more + tougher units each round.
  - **A fully deterministic auto-combat** — fires start-of-battle abilities, then trades
    front-unit blows tick-by-tick with on-hurt / on-faint / mend triggers until one side is
    wiped — win a **trophy** or lose a **life**; hit the trophy target to **win** or 0 lives to
    **lose**.
  - **`checksum()`** — an FNV-1a fold over the team + shop + run state — the cross-process
    determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A heuristic shop AI** — drafts the strongest affordable board (buy best value, replace the
  weakest, roll for upgrades). `auto_step()` / `auto_play_to_end()` run a whole run.
- **`GameManager` autoload** — drives the shop phase then auto-resolves the round, plus the
  NoxDev save/load ABI and an `autoplay` toggle.
- **Play surface** (`scenes/autobattler_view.tscn` + `scripts/autobattler_view.gd`) — the shop
  cards, your team (front→back), the round/gold/lives/trophies HUD, a live **synergy readout**,
  Roll + End-Round buttons, and the last combat result. **Left-click** buy · **right-click**
  freeze · click a team unit to **sell** · **T** autoplay · **N** new run.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the unit pool + abilities, the shop economy, synergies, wave scaling, and the
deterministic combat resolution — lives in `AutoBattlerEngine` as pure data + functions. The
view only drives the shop and reads state, which is why the whole run is playable and testable
with **no UI**, and why it **drops in as the battle core** of a bigger roguelite: keep the
engine, call `buy` / `sell` / `roll` / `end_shop`, read `team` / `shop` / `trophies`.

The key property: `simulate(...)` is a **deterministic** function of the two teams (+ the
seed), so you can **replay the exact fight** to drive a combat *animation* on the view side —
compute the result instantly for the sim, and re-run it visually. That determinism is also what
lets NoxQA smoke-run the shop-AI through a whole run headlessly and diff the checksum, and is
the base a **PvP auto-battler** (share seeds/teams, not state) is built on.

## How to extend

1. **Bigger roster + rule-warping relics**: add units to `POOL` and a "How Many Dudes"-style
   relic set that rewrites combat rules (extra front attackers, revive-on-faint, etc.).
2. **Unit leveling / combine**: buy 3 of a kind → level up (Super-Auto-Pets style); the team is
   already a list you can merge.
3. **Positioning matters more**: reward front/back placement (tanks front, glass cannons back)
   and add reach/AoE abilities.
4. **A real combat playback**: `simulate` yields the deterministic result — record the event
   log and animate it (lunges, sparks, faints).
5. **PvP / async ladder**: match seeds + saved teams for asynchronous multiplayer.
6. **More synergies + a synergy panel**: class/tribe bonuses at multiple breakpoints.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the whole run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run to a terminal twice yields an identical final
  `checksum()`; a **different seed rolls a different shop + waves**.
- **partial determinism** — 4 rounds of the same seed produce an identical checksum across runs.
- **a real run** — the shop AI **drafts teams and auto-battles**, **winning trophies** against
  the escalating waves, reaching a genuine terminal (a win at the trophy target or a loss when
  out of lives). Validated: the AI reaches **round 10 with 3 trophies** before elimination.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> won=false round=10 trophies=3 lives=0 team=5
# → PROBE PASS
```
