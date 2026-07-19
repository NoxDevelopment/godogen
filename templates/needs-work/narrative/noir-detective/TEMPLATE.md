# Noir Detective Template (investigation + deduction, 2D)

A film-noir detective game where the play **is deduction** — the Lacuna /
Snatcher lineage, not twitch. Investigate locations to turn up clues, combine
the right clues into deductions, and only once the chain is complete may you name
the killer. Scaffold with:

```bash
python templates/tools/scaffold.py noir-detective <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the whole CASE as
  pure, headless-testable logic and a **data-driven catalogue** you edit to
  author a new mystery:
  - **`SUSPECTS`** (id → name/role) and a `CULPRIT`.
  - **`LOCATIONS`** you can investigate.
  - **`CLUES`** (id → name/**location**/desc) — each clue is *staged* at a
    location and surfaces when you examine it.
  - **`DEDUCTIONS`** (id → name/**requires** clue ids/desc) — a deduction unlocks
    only when all its clues are found.
  - Progress + rules: `examine(location)` (reveals that room's clues,
    idempotent), `can_form()/form_deduction()/available_deductions()`,
    `can_accuse()` (**fair play — blocked until the whole chain is formed**), and
    `accuse(suspect)` (closes the case; *solved* iff the chain is complete **and**
    the suspect is the real culprit).
  - Ships a complete sample case, **"The Neon Alibi"** — 3 suspects, 4 locations,
    7 clues, 3 deductions (motive / means / opportunity).
- **Investigation screen** (`scenes/noir.tscn` + `scripts/noir.gd`) — a
  three-column casebook built entirely in code in a noir palette: **Investigate**
  (a button per location + its clue count), **Casebook** (every clue you've
  found), and **Deductions + Accuse** (form unlocked deductions; the suspect
  buttons enable only when you may accuse). It only reads the engine and forwards
  clicks; the scene stays a bare `Control` + script.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()` (an
  in-progress case — clues found, deductions made — persists); `pause` +
  `restart` input; `"scalable_text"` on every label/button.

## The engine (the part worth understanding)

Every rule lives in `GameManager` and emits `case_changed`; the view rebuilds
from state. That is why the whole game is playable and testable with **no UI** —
`begin_case()` then `examine()` / `form_deduction()` / `accuse()`. The
clue→deduction→accusation gating is the entire mystery, and it is data: to write
a new case you only rewrite the five consts (`SUSPECTS` / `LOCATIONS` / `CLUES` /
`DEDUCTIONS` / `CULPRIT`) — the investigation screen adapts with zero changes.

## How to extend

1. **A new case**: rewrite the catalogue consts. Add a red herring by staging a
   clue that no deduction requires; add difficulty by requiring more clues per
   deduction or more deductions before `can_accuse()`.
2. **Interrogations**: give each suspect a `companion-npcs` persona + Dialogue
   Manager and open a talk scene from an "Accuse" or "Question" button — a wrong
   deduction can gate what they'll admit.
3. **Real scenes**: swap the code columns for location backdrops + suspect
   portraits (recipes: a noir scene preset + a noir portrait preset over
   `zit-txt2img`; clue icons via `qwen-icon`).
4. **Multiple cases / progression**: keep a solved-case count in
   `GameManager.flags` (already tracks `cases_solved`) and load the next
   catalogue on solve.
5. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the in-progress case already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
script errors, and two headless probes:

- **Case-engine probe** (pure `GameManager`, `fails=0`): investigation reveals a
  room's clues (and is idempotent on re-examine), deductions gate on their exact
  clue sets, accusing is **refused until the chain is complete** (and a refusal
  doesn't close the case), a wrong suspect closes it *unsolved* while the real
  culprit closes it *solved* (+ the `cases_solved` flag), and an in-progress case
  round-trips through `save_data()/load_data()`.
- **UI-build probe** (`fails=0`): the investigation scene builds its columns
  (4 location buttons, 3 deduction rows, 3 suspect buttons) and the **casebook
  populates after an examine** — the view↔engine wiring is live.
