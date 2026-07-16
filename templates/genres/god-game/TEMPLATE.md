# God Game Template (top-down deity strategy sim, 2D)

A top-down DEITY strategy sim in the **Populous / Black & White** lineage — shape
the terrain and wield divine powers to grow your tribe of autonomous followers
and outgrow (or convert / drown) a rival god's tribe. Scaffold with:

```bash
python templates/tools/scaffold.py god-game <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`GodWorld` engine** (`scripts/god_world.gd`) — the whole deity sim as pure,
  seedable, headless-testable `RefCounted` logic (no scene deps):
  - A **64×64 terrain grid** of packed HEIGHTS (water below sea level, walkable /
    buildable land above) + a per-cell resource flag (forest → wood, food source
    → food). Terrain is generated deterministically from the seed (noise → box-
    blur hills → scattered resources) with two founding settlements.
  - Two **TRIBES** (you + a rival), each with villagers, huts, a **belief/mana**
    pool, and a **wood** pool. Belief accrues each tick from congregation size.
  - A real **autonomous populace AI** (deterministic): followers seek the nearest
    resource, fell forests for wood + forage food back to the hut, **huts breed**
    new followers when fed, the tribe **builds new huts** on free buildable land
    near resources (funded expansion — it gathers wood first, then raises one hut
    at a time), and followers **flee flooded cells** (and drown if stranded).
  - **5 divine POWERS**, each a real effect: **Raise Land** (water → buildable
    land / land-bridges), **Lower Land** (flood land, drown/scatter followers,
    wash away huts), **Grow Food** (bless food sources + a bounty to your hut →
    attracts + breeds your tribe), **Inspire** (boost your followers' gather →
    faster building + breeding), **Miracle** (convert nearby rival followers to
    your tribe). Each **costs belief**; `is_legal()` rejects a cast with no belief
    or on an invalid target.
  - A **rival god AI** (deterministic heuristic, non-LLM): it accrues belief and
    spends it on a fixed priority ladder — convert a stray follower of yours,
    grow its own tribe with food, then flood your nearest settlement — every
    target chosen by nearest distance with a deterministic tie-break.
  - **Win/loss** that is genuinely reachable both ways: WIN by hitting the
    population goal while leading, or by eliminating the rival; LOSE by being
    wiped out or letting the rival hit the goal first; the tick cap awards the
    larger tribe.
  - `snapshot()` / `restore()` round-trip the ENTIRE world — terrain, both
    tribes, belief/wood, the pending-power queue, and RNG state — so a reload
    replays byte-for-byte. `checksum()` proves determinism.
- **Deity map** (`scenes/main.tscn` + `scripts/main.gd`) — built in code: a top-
  down terrain render (height → colour, water, forests/food, per-tribe villager +
  hut markers, inspired followers glow), a **power palette** (pick a power, click
  the map to cast it on a cell), a **belief + wood meter**, both tribes'
  populations, a tick counter + a log. Esc pauses, R restarts.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the
  whole world + RNG persist); `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

Every rule — terrain gen, the populace state machine (idle → gather → return →
build → flee), breeding, expansion, each power's effect, the rival heuristic,
belief economy, win/loss — lives in `GodWorld` and is a **pure function of
(state, tick, seeded RNG)**. `tick_world()` runs a fixed pipeline: accrue belief
→ apply queued player powers → the rival god decides + casts → advance every
villager one cell in index order → advance huts (flood + breed) → compact the
dead → judge the game. No step does an unbounded rescan (followers search for
resources only inside a bounded radius, only when idle), so a tick is
`O(V·R² + W·H)` with small constants and always terminates. Because every
stochastic choice draws from the seeded RNG whose state is saved, **the same seed
+ the same scripted divine commands produce a byte-identical world after N
ticks** — the determinism the tests rely on, and what makes replays / netcode /
undo tractable.

## How to extend

1. **More powers**: add to the `P_*` enum + `POWER_COST`/`POWER_NAME` and a
   `_apply_*` (e.g. a lightning smite, a forest bloom, a shield). `is_legal()` is
   the one place to gate it.
2. **Deeper terrain**: swap the box-blur generator for diamond-square / real
   noise; add rivers, cliffs (impassable), or biomes that change gather rates.
3. **Richer followers**: give villagers hunger / age / faith, or roles (farmer,
   forester, builder, soldier) — the state machine is the hook.
4. **Combat**: add a `flee`→`fight` branch so bordering tribes skirmish, or a
   power that raises warriors.
5. **Art**: swap the flat cell colours for a terrain tileset + villager/hut
   sprites (recipes: tiles via `pixel-perfect`, unit sprites via `qwen-icon`, a
   sky/vignette via `zit-txt2img`).
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the world already serialises (terrain + tribes + RNG).

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with
zero script errors (all vars typed), and seven headless probes (`fails=0`):

- **(a) Populace** — from a seeded start with NO player input, followers gather,
  huts breed (population grows 8 → 38), and the tribe autonomously expands
  (2 → 11 huts); every follower stays on a legal cell; the run terminates.
- **(b) Powers** — each power's real effect verified (Raise Land makes water
  buildable; Lower Land floods a cell and flees/drowns the follower on it; Grow
  Food causally out-grows a control tribe; Inspire sets a follower's boost;
  Miracle converts a rival follower); belief is spent; illegal casts (no belief /
  bad target) are rejected.
- **(c) Full game** — a scripted active god WINS (single legal winner == you,
  before the tick cap, no illegal action) AND a passive god LOSES to the belief-
  fuelled rival — proving both outcomes are truly reachable.
- **(d) Determinism** — same seed + same scripted commands ⇒ identical checksums
  AND snapshots after 250 ticks; a different seed diverges.
- **(e) Rules/legality** — illegal casts leave the world byte-unchanged; belief /
  wood / population / on-land invariants hold across a full game with a single
  legal winner.
- **(f) UI-build** — the map scene builds (palette with one button per power +
  the belief/population HUD), and a scripted cast changes the world and refreshes
  the view.
- **(g) Save/load** — a mid-game snapshot, then mutate, then restore equals the
  snapshot exactly (checksum + snapshot), and replays from the restored state
  stay in lock-step.
