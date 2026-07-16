# Peg Roguelike Template (Peglin-style pachinko roguelike, 2D)

A Peglin-lineage **pachinko roguelike**: aim + fire ORBS that bounce down a PEG
board under a **deterministic custom physics sim**, accumulate damage from every
peg they touch, dump that damage onto an enemy, and — between fights — run a
roguelike map of combat / elite / shop / event / rest / boss nodes with RELICS,
gold, and orb upgrades. OUR OWN engine, generic content (no trademarks). Scaffold
with:

```bash
python templates/tools/scaffold.py peg-roguelike <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## The key design decision — deterministic CUSTOM physics (not RigidBody2D)

Godot's physics solver is **not** guaranteed identical across runs/builds, which
would break byte-identical replays + probes. So the ball-vs-peg physics is our
OWN fixed-timestep circle sim: a ball is just a circle `(position, velocity)`
advanced at a **fixed `DT`** under gravity, colliding with circular PEGS and the
four WALLS by pure geometry — circle-circle / circle-wall overlap → push out of
penetration + **reflect the velocity about the contact normal** with a
`RESTITUTION` factor — until it exits the bottom or hits `MAX_STEPS`. Given
`(aim angle, board layout, seed)` the trajectory + accumulated damage are 100%
reproducible. The **only** randomness in the whole engine (board gen, map gen,
deck shuffle, shop rolls, enemy stats, events) comes from ONE seeded RNG whose
state is part of save/load; **the physics has zero randomness**, and a `MAX_STEPS`
cap bounds every shot so no ball loops forever. This mirrors the falling-sand
template's deterministic-step discipline.

## What you get

- **`PegEngine`** (`scripts/peg_engine.gd`) — a pure `RefCounted class_name`, no
  Godot-node dependency, so a whole run replays **byte-identically** and drives
  headlessly with no UI. Layers:
  - **Physics** — `_simulate_ball()` / `_simulate_orb()`: the pure circle sim →
    a resolution `{trajectory, pegs hit, wall bounces, checksum, exited}`.
  - **Pegs** (4 types): `NORMAL` (damage), `CRIT` (bonus damage), `BOMB`
    (AoE-detonates nearby pegs), `REFRESH` (bonus scaled by pegs already hit).
    Hitting **all** pegs in a shot is flagged for a Peglin-style bonus.
  - **Orbs — a DECK of 14 distinct** (`ORB_DB`): each has a base peg-damage +
    an EFFECT (`crit_boost`, `multiball`, `poison`, `remaining`,
    per-wall-bounce `momentum`, `echo` x2, `bomb_boost`, `pierce`, `heal`,
    `gold`, `refresh_syn`, plain). Draw an orb, aim, fire; its accumulated
    damage hits the enemy, the orb goes to the discard, and the discard
    reshuffles when the draw pile empties.
  - **Combat** — an enemy with HP + a **cycling attack pattern** that damages
    you when your turn ends; status effects (poison ticks + decays). Clear the
    enemy to win the fight; your HP to 0 loses the run.
  - **Run** — a seeded, fully-connected **node MAP** (combat / elite / shop /
    event / rest / boss), **10 RELICS** (`RELIC_DB`, passive modifiers), gold,
    post-combat orb rewards, a shop (orbs / relics / heal / orb-upgrade), and
    generic events.
  - **Damage** — `_compute_shot()`: resolution + orb effect + relics → damage,
    poison, heal, gold, component by component (auditable, testable to the
    number).
  - **Legality** — `is_legal()` rejects firing with no orb, buying without gold,
    out-of-phase / invalid-node travel.
  - **Auto-play** — `best_aim()` (the best-damage angle, found by dry-simulating
    `AIM_SAMPLES` angles) + `auto_take_turn()` drive a whole run headlessly.
  - **Save/load** — `to_dict()` / `from_dict()` round-trip the WHOLE run incl.
    the peg board, deck/draw/discard, map, enemy, and RNG state.
- **Board screen** (`scenes/board.tscn` + `scripts/board.gd`) — built in code: the
  peg board + the ball's bounce path + an aim indicator (via `_draw`), your HP +
  the enemy HP, the current orb + deck/discard counts, gold + relics, an
  aim slider + Fire (and Auto-Aim), and swappable MAP / SHOP / REWARD / EVENT /
  REST panels, plus an Auto-Step demo.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()`;
  `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

Every rule — the physics constants, the peg/orb/relic tables, the map + combat +
economy — lives in `PegEngine` and `GameManager` emits `changed`; the screen only
reads state and forwards the chosen action. That is why it is fully playable and
testable with **no UI**, and why it **drops in as the combat core of a larger
game**: keep the engine, call `fire()`, read the run state. Because the physics is
our own explicit sim (constants at the top of the file), the trajectories are
auditable and the whole run is deterministic under a seed.

## How to extend

1. **Real orbs/relics**: swap `ORB_DB` / `RELIC_DB` for your own; each effect is a
   branch in `_compute_shot` (or `_simulate_orb` for physics-changing ones like
   `multiball` / `pierce`).
2. **More peg types**: add to the `PEG_*` consts + `_roll_peg_type` + the
   per-type branch in `_compute_shot` (e.g. a chain-lightning peg).
3. **Boss mechanics**: give the boss a richer `moves` pattern or a shielded phase
   in `_enemy_turn`.
4. **Art**: swap the flat peg/ball circles for sprites + a board backdrop
   (recipes: peg/orb icons via `qwen-icon`, enemy art via `card-creature-art`, a
   board splash via `zit-txt2img`).
5. **Companions**: make enemies or shopkeepers real `companion-npcs` personas for
   the roguelike framing.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with
zero script errors (all vars typed), and six headless probes each `fails=0`:

- **Physics** — a ball fired at a known aim on a known seeded board bounces
  (hits ≥1 peg), stays IN BOUNDS the whole flight, exits the bottom within the
  step cap, and reproduces the EXACT same trajectory checksum + damage on a
  repeat (a different aim diverges).
- **Determinism** — same seed + the same scripted shot sequence give a
  **byte-identical** run-state checksum at every step (and across separate
  processes); a different aim or seed diverges.
- **Combat** — a shot reduces enemy HP by exactly its accumulated damage, the
  enemy attacks back, the deck draw/discard/reshuffle invariant holds, and a
  poison status ticks + decays.
- **Orbs/relics** — on a crafted shot, 8 distinct orb effects hit their exact
  expected damage/status and 4 relics apply their modifier.
- **Full-run** — the deterministic auto-play reaches a **WIN** (clears the boss
  on an easy config) AND a **LOSS** (HP to 0 on a hard one), with zero illegal
  attempts, terminating within a step budget.
- **Rules/UI/save** — illegal actions are rejected; `board.tscn` boots with the
  board + HP + orb HUD + map panel and a fire resolves; and a mid-run
  save→mutate→load restores the exact run checksum.
