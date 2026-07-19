# Classic Roguelike Template (Rogue/NetHack-lineage turn-based dungeon crawl, 2D)

A Rogue/NetHack-lineage **classic roguelike**: descend a procedurally generated,
multi-level dungeon one **turn** at a time — fight monsters with bump-combat, grab
gold and potions, level up, and try to reach the bottom before **permadeath** ends
the run. It is OUR OWN engine with generic content (no trademarks) — a PURE,
seedable, deterministic dungeon engine, the ideal fit for the NoxDev pure-engine
pattern. Scaffold with:

```bash
python templates/tools/scaffold.py classic-roguelike <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`RogueEngine`** (`scripts/rogue_engine.gd`) — a pure `RefCounted` engine with
  ZERO Godot-node dependency and ZERO `Time` calls (a single private RNG drives
  world-gen AND play), so an entire run replays **byte-identically** from a seed
  and can be driven with no UI at all:
  - **Seeded dungeon generation** — a 40×22 grid of non-overlapping rooms joined by
    L-shaped corridors, **guaranteed connected** (each new room tunnels back to the
    previous one's centre), with a **down-stairs** placed on each floor. The same
    seed regenerates the identical map.
  - **Turn-based bump-combat** — move into a monster to attack it; every monster
    then takes its turn (greedy step toward the player when in range, else idle).
    Damage = attacker `atk` mitigated by defender, with the message log narrating
    each blow.
  - A **4-tier monster table** (rat → kobold → orc → wraith) that **deepens with
    depth**: tougher monsters and more of them the further you descend.
  - **Fog-of-war exploration** — a `seen[]` byte grid records explored tiles so the
    view only reveals what the player has walked into.
  - **Items** — gold (raises score) and **healing potions** (`Q` to quaff; heal
    scales with level), scattered by the generator each floor.
  - **8-floor descent** with escalating danger; **XP + level-up** (each level raises
    max HP and attack); and **PERMADEATH** — death, or descending past the final
    floor (a WIN), ends the run. Both outcomes are genuinely reachable.
  - `checksum()` — an **FNV-1a fold over the entire state** (the full grid + player
    + every monster + every item), the cross-process proof that two runs of the same
    seed are byte-identical.
  - A deterministic **BFS-pathfinding auto-play seat** (`auto_step()` /
    `auto_play_to_end("greedy")`) that clears reachable monsters (bump-attacking the
    last step onto them), then routes around walls to the stairs and descends — it
    plays a **real run to a genuine win/death**, not a stalled loop. (Validated: a
    seeded run reaches **depth 5** and dies at **turn 303**.)
  - `save_data()` / `load_data()` snapshot the **entire** run (grid, player,
    monsters, items, log, seed) for the NoxDev save/load ABI.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `RogueEngine`,
  reseeds a fresh run (`new_run()`), and adds the NoxDev ABI
  (`save_data()`/`load_save()`, run seed).
- **Play surface** (`scenes/dungeon.tscn` + `scripts/dungeon.gd`) — drawn in code:
  fog-lit terrain tiles, the **@** player, monsters, gold/potion pips, a live **HUD**
  (depth / HP / ATK / level / gold / potions), and the latest **message-log** line,
  with **arrow / WASD** movement, **Space** wait, **Q** quaff, **>** descend, and
  **R** for a fresh seeded run. Game-over prints WIN/DIED and waits for `R`.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses (`default_bus_layout.tres`);
  the engine is node-free so it slots into any scene tree.

## The engine (the part worth understanding)

Every rule — dungeon generation, connectivity, monster placement + AI, bump-combat,
fog of war, item pickup, descent, XP/level-up, permadeath, and the auto-play seat —
lives in `RogueEngine` as pure data + functions driven by one `RandomNumberGenerator`
seeded in `setup(seed)`. The scene only reads state and forwards a key, which is why
the whole game is playable and testable with **no UI**, and why it **drops in as the
dungeon core of a larger RPG**: keep the engine, call `step(action)`, read
`player` / `monsters` / `grid`.

Determinism is the load-bearing property: because nothing calls `Time` or an unseeded
RNG, `checksum()` after any number of steps is identical across two separate processes
given the same seed and the same actions — which is exactly what the determinism probe
asserts, and what lets NoxQA smoke-run a full auto-play headlessly in CI.

## How to extend

1. **More monsters**: add an entry to `MONSTER_TABLE` and let `_populate_level()`
   weight it by depth — combat, AI, and save/load pick it up with no other change.
2. **More items**: extend the item kinds in `_populate_level()` + the pickup branch
   in `step()` (scrolls, weapons, armour) — `items[]` already serialises.
3. **Deeper generation**: swap `_gen_level()`'s rooms-and-corridors for BSP,
   cellular-automata caves, or vaults — the rest of the engine only needs a
   connected grid with a `STAIRS` tile.
4. **Smarter AI / an AI seat**: the `greedy` policy is one branch in `auto_step()`;
   add policies (cautious, greedy-for-gold) for training data or a spectator demo.
5. **Art**: swap the `draw_rect` tiles + entities for a real 16×16 tileset and
   monster sprites (wall/floor/stairs via tileset recipes, rat/kobold/orc/wraith +
   `@` via `character-sprite`); the engine already exposes `tile()` / `monsters` /
   `items` / `player` for a sprite layer.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the whole run already serialises via `save_data()`.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script
errors (all vars typed), and the headless **determinism probe**
(`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed played to completion twice produces an
  identical final `checksum()`; a **different seed diverges** (different map + run).
- **partial determinism** — 40 steps of the same seed produce an identical
  mid-run checksum across runs.
- **seeded world-gen** — two seeds produce **different initial states** (the map is
  actually a function of the seed, not a fixed layout).
- **real termination** — `auto_play_to_end("greedy")` reaches a genuine `game_over`
  by playing (descended to depth 5, died at turn 303), not by hitting the safety
  cap — the BFS seat navigates around walls and makes real progress.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> depth=5 turn=303 won=false
# → PROBE PASS
```
