# Ant Colony Template (colony ecosystem sim, 2D)

A SimAnt-style COLONY ECOSYSTEM sim — grow an ant colony via **pheromone-trail
foraging**, tunnel out a nest, raise castes, and war with a rival colony while
dodging a predator. A deterministic tick-sim, a direct sibling to falling-sand and
god-game. Scaffold with:

```bash
python templates/tools/scaffold.py ant-colony <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`AntWorld` engine** (`scripts/ant_world.gd`) — the whole colony sim as pure,
  seedable, headless-testable `RefCounted` logic (no scene deps):
  - A **56×40 grid**: an open SURFACE band over diggable SOIL, with bedrock veins
    (undiggable), food sources on the ground line, and two nests carved just below
    the surface. Terrain is generated deterministically from the seed.
  - **Twin PHEROMONE fields per colony** — the signature mechanic. A **HOME**
    trail is emitted by the nest core each tick (and laid weakly by outbound
    searchers) and a **FOOD** trail is laid by food-carriers all the way back to
    the nest. Both **evaporate** (×0.94) and **diffuse** through connected passable
    cells every tick, so an unused trail fades and a used one is reinforced — a
    stable nest→food trail **emerges** with no scripting. Searchers ascend the
    food trail to reach food; carriers ascend the home trail to get home.
  - **Castes**: a **QUEEN** (lays eggs, consumes food, never moves — kill her to
    win), **WORKERS** (forage + dig, follow/lay pheromones), **SOLDIERS** (fight
    rival ants + the predator). Ants are a deterministic state machine
    (search → return → dig, or guard → fight).
  - **Colony economy**: foraged food banks into a stock; the queen turns food into
    eggs → new ants (every 5 ticks, one egg costs 5 food, capped at 70), castes by
    a fixed ~1-in-3 soldier ratio; upkeep drains food and a persistently empty
    larder starves (and eventually kills) the queen.
  - **Tunnelling**: idle workers excavate SOIL → TUNNEL at the frontier nearest the
    nest (or your Dig zone), expanding the nest over time (self-limited, ≤3 diggers
    at once).
  - A **rival colony** run by the same ant AI plus an aggressive heuristic — its
    soldiers relentlessly march on **your** queen, so a passive player is overrun.
  - A **spider predator** that stalks the surface, bites lone workers, is damaged
    by adjacent soldiers, and is **driven off** at zero hp (respawning later).
  - **Player influence** (indirect, SimAnt-style): designate **Dig / Forage /
    Attack** zones that bias the colony's behaviour; `is_legal_designation()`
    rejects out-of-bounds / bad-kind designations.
  - **Win/loss** genuinely reachable both ways: WIN by killing the rival queen
    (or wiping their ants, or leading at the pop goal); LOSE if your queen dies or
    your colony hits zero ants; the tick cap awards the larger colony.
  - `snapshot()` / `restore()` round-trip the ENTIRE world — terrain, food, both
    colonies' ants + pools, **both pheromone fields**, zones, and RNG state — so a
    reload replays byte-for-byte. `checksum()` proves determinism.
- **Colony map** (`scenes/main.tscn` + `scripts/main.gd`) — built in code: a
  top-down render of surface/soil/tunnels/chambers, food, both nests, every ant
  (coloured by colony + caste, queen large, carriers haloed), the spider, and an
  optional **food-pheromone heat overlay**; a **zone palette** (pick Dig/Forage/
  Attack, click the map to designate), and a HUD of your pop by caste, food,
  foraged total, tunnels, the rival pop, and the tick. Esc pauses, R restarts.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the
  whole world + RNG persist); `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

Every rule — terrain gen, the twin-pheromone routing, the ant state machine, caste
births, tunnelling, the rival heuristic, combat, the predator, win/loss — lives in
`AntWorld` and is a **pure function of (state, tick, seeded RNG)**. `tick_world()`
runs a fixed pipeline: evaporate + diffuse pheromones → nests emit home scent →
economy (upkeep, starvation, births) → assign a digger → advance every ant one
cell in index order → advance predators → compact the dead → judge. No step does
an unbounded rescan (enemy/dig/food searches are bounded-radius or single linear
passes), so a tick is `O(A + W·H)` with small constants and always terminates.
Because every stochastic choice draws from the seeded RNG whose state is saved,
**the same seed + the same player designations produce a byte-identical world
after N ticks** — the determinism the tests rely on, and what makes replays /
netcode / undo tractable.

## How to extend

1. **More castes**: add a `NURSE`/`SCOUT`/`ALATE` to the caste enum + a state
   branch in `_update_ant`; the birth ratio in `_economy` is the one place to tune
   composition.
2. **Richer pheromones**: add an ALARM field (soldiers rally to it) or a colony-id
   trail so rival trails repel; the diffuse/evaporate helper generalises.
3. **Deeper nest**: brood chambers, food stores, or fungus gardens as new terrain
   kinds with their own rules; tunnelling already carves them.
4. **Smarter rival**: give the rival heuristic Dig/Forage/Attack "zones" of its own
   for asymmetric personalities.
5. **Predators/weather**: more spiders, anteaters, rain that floods tunnels — the
   predator array + terrain are the hooks.
6. **Art**: swap the flat cell colours for a soil/tunnel tileset + ant/spider
   sprites (recipes: tiles via `pixel-perfect`, unit sprites via `qwen-icon`, a
   surface backdrop via `zit-txt2img`).
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the world already serialises (terrain + colonies + pheromones
   + RNG).

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with
zero script errors (all vars typed), and six headless probes (`fails=0`):

- **(a) Pheromone/foraging** — from a seeded start with NO input, a food trail
  FORMS (peak scent 0 → 3.3), ants collect food (8 foraged), and the colony grows
  (births + population 9 → 12). Emergent foraging works.
- **(b) Mechanics** — tunnelling digs soil → tunnel (37 digs, open cells 46 → 83);
  egg→ant birth REQUIRES food (starved colony births 0, fed colony births 6); a
  soldier defeats a lone enemy worker; soldiers drive off a lone predator;
  pheromone EVAPORATES without reinforcement (100 → 2.5).
- **(c) Full run** — an active player (attack the rival queen + a fuelled economy)
  WINS by eliminating the rival queen (tick 108); a passive player LOSES to the
  fuelled, aggressive rival (tick 86). Both outcomes truly reachable.
- **(d) Determinism** — same seed + same designations ⇒ identical checksum AND
  snapshot after 250 ticks; a different seed diverges.
- **(e) Rules/legality** — out-of-bounds / bad-kind designations rejected; across a
  full game to a single legal winner, invariants hold (food ≥ 0, every ant in
  bounds on a passable cell, predators in bounds).
- **(f) UI-build + save/load** — the map scene builds (zone palette with one button
  per zone + the HUD), a scripted designation resolves and refreshes the view; a
  mid-game save → mutate → load returns the exact snapshot (checksum), and two
  restores replay in lock-step (including the pheromone grids).
