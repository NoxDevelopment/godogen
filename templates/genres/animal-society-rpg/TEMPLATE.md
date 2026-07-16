# Animal Society RPG Template (survival + migration, 2D)

A mature ANIMAL-SOCIETY survival RPG in the **WATERSHIP DOWN / SECRET OF NIMH /
AMERICAN TAIL** lineage. You lead a small band of **named animals** (rabbits / mice)
with distinct **social roles** across a dangerous seeded landscape to found and grow
a **thriving warren** — surviving predators, seasons, hunger, and the band's own
morale. A deterministic day/tick society + survival sim, sibling to ant-colony,
god-game, and cosmic-horror-coop. Scaffold with:

```bash
python templates/tools/scaffold.py animal-society-rpg <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`WarrenEngine` engine** (`scripts/warren_engine.gd`) — the whole game as pure,
  seedable, headless-testable `RefCounted` logic (no scene deps):
  - **The band / warren** — a colony of NAMED animals, each with a **social role**
    (Chief / Scout / Seer / Forager / Fighter / Storyteller / Kit), a sex, an age,
    traits (courage / wisdom / speed) + health, needs (hunger / fatigue), and a
    **bond** to the band. Roles confer **real, measurable abilities**:
    - a **Forager** gathers strictly more food,
    - a **Scout** lowers the ambush rate (spots predators earlier),
    - a **Seer** gives an early-warning (a cleaner escape → less loss in a raid),
    - a **Fighter** raises the band's defence,
    - a **Storyteller** lifts morale on rest,
    - a **Chief** (leader) steadies morale + reduces dissent,
    - a **Kit** cannot yet work but is the warren's future (matures into an adult).
  - **Survival sim** — **seasons** cycle over a year and modulate food + danger
    (lean, dangerous winter vs rich, calm summer). Each day the band takes ONE
    decision; the day then RESOLVES: everyone eats (starvation harms/kills), fatigue
    + illness accrue, a hazard may strike, morale drifts, and — once settled — a
    **breeding pair reproduces** up to a population cap.
  - **Predators + hazards** — four threats (**Fox / Hawk / Cat / the "Man"** and his
    road & machines) hunt on a deterministic model. A Scout/Seer warning + the
    band's fighters/speed decide **escape vs loss**; a raid can **kill a named
    member** — real stakes.
  - **Social layer** (the Watership heart) — **morale / cohesion** is driven by
    leadership, storytelling, losses, and success; low morale → dissent → a member
    may **desert** (the band splinters).
  - **Migration quest** — the band travels a seeded chain of **stops** (from the old
    Sandleford warren toward Watership Down). Each leg costs days + risks a predator
    encounter. You must arrive with a **viable founding group** (enough survivors +
    a breeding pair), then **grow** the warren to a target size.
  - **Win/loss** genuinely reachable both ways under a deterministic auto-play
    policy: **WIN** = found the new warren AND grow it to the target (a thriving
    society); **LOSS** = the band is wiped out, falls below a viable founding size,
    or fails to reach the site before the deadline. `MAX_DAYS` guarantees every run
    terminates.
  - `to_dict()` / `from_dict()` round-trip the ENTIRE run — the band (roles, sexes,
    ages, traits, needs, bonds), morale, food, the journey + stops, every counter,
    and RNG state — so a reload replays byte-for-byte. `checksum()` (FNV-1a over the
    whole state) proves determinism, within a process AND across processes.
- **The warren screen** (`scenes/warren.tscn` + `scripts/warren.gd`) — built in
  code: a top-down **journey view** drawn via `_draw` (the chain of stops, the
  band's position, danger shaded, the goal marked, the band's role-coloured token),
  a HUD (season / year / day / food / morale / population / phase / cohesion), a
  **decision bar** (Forage / Scout / Rest / Move On / Shelter / Assign Role), and a
  **members panel** listing every named animal with its role + needs. Esc pauses, R
  restarts.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (the whole
  run + RNG persist); `pause` + `restart` input; `"scalable_text"`.

## The engine (the part worth understanding)

Every rule — the band + roles, the day survival economy, seasons, predators, the
social morale/cohesion layer, migration, win/loss — lives in `WarrenEngine` and is a
**pure function of (state, day, seeded RNG)**. `take_action()` applies one decision
then advances the day via `_end_day()` (a MOVE_ON runs one `_end_day` per travel-day
of the leg). `_end_day()` runs a fixed pipeline: **eat → fatigue/illness → hazard →
morale drift → reproduction → aging/maturation → desertion → compact the fallen →
judge**. No step does an unbounded rescan, so every run terminates under `MAX_DAYS`,
and because every stochastic choice draws from the seeded RNG whose state is saved,
**the same seed + the same decisions produce a byte-identical run** — the determinism
the tests rely on, and what makes replays / netcode / undo tractable.

The forage yield, the encounter chance, and the rest-morale gain are exposed as
**pure preview helpers** (`forage_yield_preview()`, `encounter_chance_preview()`,
`rest_morale_gain()`) so the role abilities are directly, measurably testable — a
Forager always out-gathers the same band without one, a Scout always turns the
ambush chance down, a Storyteller always lifts a rest's morale.

Both outcomes are genuinely reachable from the same rules via `auto_play_to_end()`:
the **balanced** policy plays to survive + thrive (forage when lean, rest for morale,
scout a dangerous leg, then move on; in growth it keeps a surplus so the pair
breeds), the **reckless** policy charges on with no scouting or foraging and gets the
band killed — nothing about the outcome is hardcoded (across 60 seeds balanced won
54 / lost 6, reckless lost all 60).

## How it plugs into the factory

- **Roles / voices**: give each named animal (and each predator) a persona via
  `companion-npcs` + Dialogue Manager for encounter flavour and campfire table-talk
  between band members; the role/name tags the members panel and the raid log.
- **Art**: swap the drawn journey strip + role dots for real creature portraits, a
  parchment migration map, season backdrops, and predator art (recipes:
  `card-creature-art` / `zit-txt2img` for the animals + predators, `qwen-icon` for
  role / need / decision icons, `zit-txt2img` for the map mat + season skies).
- **Systems**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
  unchanged; the run already serialises (band + morale + journey + RNG).

## How to extend

1. **More roles**: add a `Digger` (deepens the burrow faster) or `Healer` (tends the
   ill) to the role enum + an ability hook; the ability-preview pattern generalises.
2. **Richer relationships**: replace the per-member `bond` scalar with a pairwise
   bond matrix for feuds / mates / mentors that shift morale and desertion.
3. **Deeper warren**: brood chambers, food stores, and a warren-defence stat once
   settled, so the growth phase has its own build-out.
4. **Smarter predators**: give the Man snares that persist on a stop, or a territory
   predator that follows the band between legs.
5. **Branching migration**: turn the linear stop chain into a small graph with
   fork choices (a safe long road vs a fast dangerous one) via BFS-style routing.
6. **Weather / disease**: seasonal storms that flood a stop, or an epidemic that
   spreads along the bond graph.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exit 0 with zero
script errors (all vars explicitly typed), the main scene boots clean headless, and
five headless probes report `fails=0`:

- **(a) society** — a Forager gathers more (22 vs 18), a Scout halves the ambush
  chance (0.16 vs 0.33), a Storyteller lifts rest-morale (14 vs 5); a food deficit
  starves the band (7 deaths), and a fed band with a breeding pair grows to the cap
  (16).
- **(b) determinism** — same seed ⇒ identical FNV-1a checksum full-run and mid-run,
  AND identical across two separate processes; a different seed diverges; world-gen
  is seeded.
- **(c) predators + survival** — a raid kills named members (120 losses across a
  harsh sweep, e.g. "Hazel is lost to the Cat"); a Scout/Seer/Fighter band survives
  measurably better (75 vs 120 losses); seasons modulate food (summer 27 vs winter
  10) and danger (winter 0.24 vs summer 0.14).
- **(d) migration + reachability** — balanced auto-play REACHES Watership Down and
  GROWS to the target (WIN, day 83, pop 12); reckless loses the band (LOSS); a
  60-seed sweep shows both outcomes (balanced 54 win / 6 loss, reckless 60 loss); no
  run exceeds MAX_DAYS.
- **(e) rules + ui** — illegal decisions rejected (assign to a fallen/out-of-range
  member, assign a kit, assign the Kit role, any decision after the band is lost,
  move on at the goal); the main scene builds its UI (6 decision buttons + 7
  labels); a scripted decision through the view mutates state; and save/load
  round-trips the full state through JSON byte-identically, then replays in
  lock-step.
