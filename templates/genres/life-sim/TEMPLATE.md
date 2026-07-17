# Life Sim Template (The Sims-lite — needs / job / relationships / aspiration, 2D)

A The-Sims-lineage **life sim** run as a **deterministic fixed-timestep sim**: a character
with six decaying **needs** (hunger / energy / hygiene / fun / social / bladder) does timed
**actions** to meet them, holds a **job** (earning money on a daily schedule, paid by mood),
builds **relationships** with NPCs, and works toward an **aspiration** goal — over a
day/clock cycle with seeded daily **events**. It is OUR OWN engine with generic content
(no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py life-sim <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`LifeEngine`** (`scripts/life_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG only drives the start jitter +
  the daily events, so a whole life replays **byte-identically** from a seed:
  - **Six needs** that decay at per-need rates (tuned so each drains ~1–2 refills per
    240-tick day) and, if energy hits 0, force an exhaustion **collapse-sleep**.
  - **Timed actions** (toilet / eat / shower / sleep / relax / socialize) that restore their
    need over a duration (sleep also pauses most decay).
  - **A job** with a 9–17 work window, a ~4.5h shift paid **wage × mood** and draining
    energy/hygiene/bladder/fun, one shift/day; a **mood** = the average of needs that scales
    pay.
  - **Relationships** with 3 NPCs where **socialize** deepens your best friendship; a
    day/**clock** cycle (10 ticks/hour) with seeded daily **events** (a bill, a nice chat,
    waking up inspired).
  - **An aspiration goal** (reach a money + best-friend milestone).
  - **`checksum()`** — an FNV-1a fold over quantized needs + state — the cross-process
    determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** life including RNG state.
- **A heuristic routine auto-seat** — urgent needs first, go to work on schedule when rested,
  top up social + fun in free time, sleep at night. `auto_step()` / `auto_play_days(n)` run
  whole weeks.
- **`GameManager` autoload** — steps the sim in real time (speed-adjustable) applying the
  player's chosen action, plus the NoxDev save/load ABI and an `autoplay` toggle.
- **Play surface** (`scenes/life_view.tscn` + `scripts/life_view.gd`) — the six need bars
  (red when low), the clock + money + mood, a relationship panel, the current action, an
  aspiration bar, an action-button row, and an event log. Click an action or press **1-7** ·
  **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — need decay, the timed actions, the job + pay-by-mood, relationships, the clock,
daily events, and the aspiration — lives in `LifeEngine` as pure data + functions stepped by
`tick(input)`. The view only reads state and forwards an action choice, which is why the whole
life is playable and testable with **no UI**, and why it **drops in as a life/needs layer**
in a bigger game (a companion's daily routine, a survival needs system): keep the engine,
call `start_action` / `tick`, read `needs` / `money` / `rel`.

The design tuning that matters most is the **decay-vs-day-length balance**: needs are tuned to
drain ~1–2 refills per day so the character has time to *also* work and socialize (too-fast
decay traps the AI in an endless eat/shower loop with no money — a lesson baked into the
constants). Because only the daily events are seeded, the same seed reproduces the exact life,
which lets NoxQA smoke-run the routine AI over weeks headlessly and diff the checksum.

## How to extend

1. **A house + objects**: place a top-down home where clickable objects (fridge/bed/shower/TV)
   map to actions; the action set is already the vocabulary.
2. **Careers + skills**: give the job levels + a skill that raises pay, and add skill-building
   actions (read/exercise).
3. **More sims / a household**: run several `LifeEngine`s and let them socialize with each
   other for a full household.
4. **Build/buy + bills**: spend money on objects that speed need refills; the daily-events
   branch already models bills.
5. **Multiple aspirations / life stages**: add aspiration tracks and age the character over
   many days.
6. **Emotions / traits**: modulate decay + action effects by traits (neat, gluttonous, loner).
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the whole life already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed lived out twice yields an identical final `checksum()`;
  a **different seed diverges** (start jitter + daily events).
- **partial determinism** — 5 days of the same seed produce an identical checksum across runs.
- **a functional life** — over several weeks the routine AI **earns money from the job**,
  **builds a best-friend relationship**, keeps needs stable (**rare/zero collapses**), and
  **reaches the aspiration goal**. Validated: over **26 days** the routine earns **$2779**,
  builds a best friend to **100**, keeps mood **~75 with zero collapses**, and **reaches the
  aspiration**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> day=27 money=2779 best_friend=100 aspire=true collapses=0 mood=75
# → PROBE PASS
```
