# Tactics SRPG Template (Fire Emblem / XCOM grid tactics with a weapon triangle, 2D)

A Fire-Emblem / XCOM-lineage **tactics SRPG**: two armies fight on a grid in
alternating **team phases** — each unit **moves** (Dijkstra move-range over per-terrain
cost) then **acts** once (attack / heal / wait). It is OUR OWN engine with generic
content (no trademarks) — a pure, seedable, deterministic tactics engine. Scaffold with:

```bash
python templates/tools/scaffold.py tactics-srpg <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`SrpgEngine`** (`scripts/srpg_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One private RNG seeds the map **and every
  hit/crit roll**, so a whole battle — misses and crits included — replays
  **byte-identically** from a seed. It is a **real SRPG combat kernel**:
  - **5 classes** — soldier (sword), fighter (axe), knight (lance), archer (bow, range 2),
    healer (staff) — each with distinct hp / atk / def / spd / move / range / hit / crit.
  - **Weapon triangle** — sword > axe > lance > sword (bow + staff neutral) — shifting
    **both** hit% and damage.
  - **Hit %** from base accuracy + speed + terrain **avoid** + triangle; **crits** (×3
    damage) from a speed-scaled chance; **counterattacks** when the defender survives and
    the attacker is in its range; **double attacks** on a ≥4 speed lead.
  - **Terrain** — plain / forest / hill / fort / wall — adds move cost, **avoid**,
    **defense**, and **fort healing** at the start of the owner's phase.
  - **Healers** mend the most-wounded ally in range instead of attacking.
  - **Movement** is a true **Dijkstra reachability** over terrain move-cost, blocked by
    enemies, ending only on empty tiles (`reachable()` / `stand_tiles()`).
  - **Victory** — wipe out the enemy's **combat** units (a lone healer can't win); a unit
    count fallback resolves the turn cap.
  - **`checksum()`** — an FNV-1a fold over the whole state — the cross-process determinism
    proof, meaningful precisely because the rolls are seeded.
  - `save_data()` / `load_data()` snapshot the **entire** battle including RNG state.
- **Weighted-heuristic macro AI** (`ai_take_phase(team)`) that drives **either** team: for
  each unit it finds the best **(stand-tile, target)** pair — favouring kills, damage,
  accuracy, and hitting healers — advances when nothing is in reach, and lets healers
  patch the wounded. `auto_step()` / `auto_play_to_end()` drive **both** teams.
- **`GameManager` autoload** — runs the player phase, then hands the AI its whole phase
  (`ai_take_phase`), plus the NoxDev save/load ABI and a `player_auto` toggle.
- **Play surface** (`scenes/srpg_view.tscn` + `scripts/srpg_view.gd`) — renders terrain,
  units + HP, and the selected unit's **move-range** (blue) + **attackable enemies** (red
  ring) in code. Classic **2-click flow**: select → move onto a lit tile → click an
  in-range enemy to **attack** (or an ally to **heal**). **W** wait · **Enter** end phase ·
  **A** auto · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — map-gen, Dijkstra movement, the full combat exchange (hit → crit → counter →
double), the weapon triangle, terrain avoid/defense/healing, victory, and the macro AI —
lives in `SrpgEngine` as pure data + functions. The view only reads state and issues
commands, so the whole battle is playable and testable with **no UI**, and it **drops in
as the tactics core of a larger SRPG** (campaign, unit growth, permadeath): keep the
engine, call `move_unit` / `attack` / `heal` / `end_phase`, read `units`.

The interesting determinism note: **the randomness is real** (misses and crits happen),
yet the battle is still byte-identical across processes because the *same seeded RNG*
produces the *same rolls in the same order*. That is what lets NoxQA smoke-run a whole
AI-vs-AI battle headlessly and diff the checksum.

## How to extend

1. **More classes / weapons**: add to `CLASSES` (+ a triangle entry if it's a new melee
   weapon); combat, AI, and save/load pick it up.
2. **Unit growth / campaign**: add XP + level-ups on kills and carry `units` between
   battles for a Fire-Emblem-style roster (with optional permadeath — units already erase
   on death).
3. **Objectives beyond rout**: add seize-the-throne / survive-N-turns / escort win
   conditions alongside `_check_victory`.
4. **Combat forecast UI**: `_hit_chance` / `_damage` / `_crit_chance` are pure — call them
   to show the attacker-vs-defender forecast before committing.
5. **Fog / vision**: add a per-team seen grid (the 4X template's fog is a reference) for
   XCOM-style scouting.
6. **Smarter AI**: `ai_take_phase` is one heuristic; add focus-fire coordination, terrain
   preference, and healer-guarding — or wire an LLM-assist tactician that emits commands.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the whole battle already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **20-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes
(`PROBE PASS`):

- **seed determinism (with rolls)** — the same seed played to completion twice yields an
  identical final `checksum()` **even though hits/crits are rolled**; a **different seed
  diverges**.
- **partial determinism** — 3 phases of the same seed produce an identical mid-battle
  checksum across runs.
- **seeded map** — two seeds produce **different initial states**.
- **combat resolves** — units actually **died** (start units > end units).
- **real decision** — `auto_play_to_end` reaches a genuine **winner** (an army wiped out),
  not a stalled cap draw. Validated: a seeded 5-v-5 battle ends at **round 20**, 10 units
  down to **1**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> end_round=20 winner=0 start_units=10 end_units=1
# → PROBE PASS
```
