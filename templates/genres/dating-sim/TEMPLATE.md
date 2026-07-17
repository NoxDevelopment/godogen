# Dating Sim Template (stat-raiser + affection routes + calendar, 2D)

A Persona-social-link / stat-raiser-lineage **dating sim**: raise player **stats** through
daily activities, spend a **calendar** pursuing romanceable **characters** via **dates** +
**gifts** matched to their seeded **preferences**, cross **affection** thresholds to unlock
milestone events, and **confess** to complete a route. Scaffold with:

```bash
python templates/tools/scaffold.py dating-sim <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

> **This is a SYSTEMS template.** It models the dating-sim **mechanics** and exposes a
> `mature_content` **gating flag that defaults OFF** and unlocks only **empty author hooks**.
> It ships **no explicit content** — the "adult-capable" part is the plumbing (a clearly
> labelled gate + gated event slots), not a payload. Any mature scene an author adds sits
> behind that gate and is their responsibility to write and rate.

## What you get

- **`DatingEngine`** (`scripts/dating_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG rolls the characters + their
  preferences + a small daily mood variance, so a whole playthrough replays **byte-identically**
  from a seed:
  - **3 player stats** (charm / wit / fitness) raised by training; a **money** economy (work
    for gift money).
  - **3 romanceable characters**, each with a seeded **liked-stat**, **liked-gift**, and
    **preferred-date**.
  - **A semester calendar** where every action costs a day.
  - **Dates** whose affection gain scales with matching their **preferred date type** AND
    meeting their valued stat at a bar that **rises with the current affection** (you must
    keep improving to keep courting).
  - **Gifts** that cost money and pay big when they match the liked gift.
  - **Affection milestones** (30 / 60 / 90) that fire relationship events (the 90 milestone
    exposes a **gated, empty** mature hook); a **confession** at 90 that completes a route +
    ends the semester with a partner (or no confession → the bittersweet ending).
  - **`checksum()`** — an FNV-1a fold over stats + affection + route state — the cross-process
    determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A pursue-a-partner auto-seat** — raise the target's liked stat to the date bar, buy their
  liked gift, take them on their favourite date, and confess at 90. `auto_step()` /
  `auto_play_to_end()` run a whole semester.
- **`GameManager` autoload** — drives the calendar (menu-based, one day per action), plus the
  NoxDev save/load ABI and an `autoplay` toggle.
- **Play surface** (`scenes/dating_view.tscn` + `scripts/dating_view.gd`) — the player stats +
  money + day, the 3 character cards (affection bar + revealed preferences + milestones), an
  action panel (train / work / date / gift / confess), an event log, and a clearly-labelled
  **mature-content gate toggle** that stays OFF by default.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — stat-raising, the money economy, character preferences, the calendar, date +
gift affection maths, milestones, the gate, and confession/endings — lives in `DatingEngine`
as pure data + functions. The view only reads state and calls a day-action, so the whole
playthrough is testable with **no UI**, and it **pairs with the visual-novel template** (route
scenes) and the companion/**Immersion-Engine persona** systems (living romanceable NPCs).

The content seam is explicit: the romanceable cast, their preferences, the milestone events,
and the endings are all **data** — author them (or let an AI writer theme a cast) — and any
mature scene MUST sit behind the `mature_content` gate. Because the cast + rolls are seeded,
every run is reproducible, which lets NoxQA smoke-run the pursue-a-partner AI headlessly and
diff the checksum.

## How to extend

1. **A written cast + route scenes**: give each character a portrait/expression set and branch
   dialogue at each milestone (wire the VN template in for the scenes).
2. **More stats / activities / a map**: add locations you travel to, part-time jobs, and clubs.
3. **Jealousy + scheduling**: characters appear at certain places/times; two-timing has
   consequences.
4. **Multiple endings + a gallery**: good/best/friend endings per character + an unlockable
   CG/memory gallery.
5. **Difficulty / time pressure**: a stricter calendar, limited energy, or rival suitors.
6. **Mature content (gated)**: if you build an 18+ version, put every mature scene behind the
   `mature_content` gate, add an age-gate on launch, and rate/label appropriately — the
   template gives you the switch, not the scenes.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the whole run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed yields an identical final `checksum()`; a **different
  seed rolls different characters/preferences**.
- **partial determinism** — 8 days of the same seed produce an identical checksum across runs.
- **a route completes** — the pursue-a-partner AI **raises stats**, gives liked gifts, dates on
  preferences, crosses the milestones, and **confesses** to complete a route with a partner;
  the `mature_content` gate **defaults OFF**. Validated: the seat completes a route with a
  partner by **day 12**, maxing affection to **100**, gate **OFF**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> route=true partner=Nova day=12 max_aff=100 max_stat=78 mature_gate=false
# → PROBE PASS
```
