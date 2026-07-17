# Educational Quiz Template (adaptive timed multiple-choice with a report card, 2D)

A learning-game **educational quiz**: a timed, **adaptive** multiple-choice quiz that
generates arithmetic questions on the fly, mixes in a factual trivia bank, scales
difficulty to the player's streak, scores with time + streak bonuses, and produces a
per-**category** report card + a letter grade. It is OUR OWN engine with generic content
(no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py educational-quiz <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`QuizEngine`** (`scripts/quiz_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG generates the questions **and**
  shuffles the choices, so a whole quiz — the exact questions, options, and their order —
  replays **byte-identically** from a seed:
  - **On-the-fly question generation** — seeded arithmetic across +/−/× whose operand
    magnitude scales with difficulty, with unique near-miss **distractors** placed at a seeded
    slot — blended ~55/45 with a **12-entry trivia bank** (science / geography / math) whose
    choices are seeded-shuffled with the correct index tracked.
  - **Adaptive difficulty** (1–5) that rises on a streak and falls on a miss.
  - **A per-question timer** where running out counts as wrong.
  - **Scoring** = base + difficulty bonus + streak bonus + a fast-answer time bonus.
  - **A per-category report card** (correct / total) and a letter **grade** (A–F) with a pass
    mark.
  - **`checksum()`** — an FNV-1a fold over the state — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** quiz including RNG state.
- **A deterministic auto-seat** — a `"perfect"` policy reads the key and aces the quiz; a
  `"guess"` policy (a fixed no-RNG pattern) lands right only occasionally. `auto_step()` /
  `auto_play_to_end()` run a whole quiz.
- **`GameManager` autoload** — runs the countdown in `_physics_process`, plus the NoxDev
  save/load ABI and an `autoplay` toggle.
- **Play surface** (`scenes/quiz_view.tscn` + `scripts/quiz_view.gd`) — the question, four
  answer buttons, a timer bar, a live score / streak / difficulty HUD, a right/wrong flash,
  and an **end-screen report card + grade**. Click an answer or press **1-4** · **T** autoplay
  · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — question generation, choice shuffling, adaptive difficulty, the timer, scoring,
the report card, and grading — lives in `QuizEngine` as pure data + functions. The view only
reads state and reports an answer, which is why the whole quiz is playable and testable with
**no UI**, and why it **drops in as a study mode / minigame** anywhere: keep the engine, call
`answer(choice)` / `tick()`, read `question` / `score` / `report_card()`.

The content seam is deliberately simple: swap the built-in generator + trivia bank for an
authored (or AI-generated) question set and you have a subject-specific quiz — while the
seeded generation keeps every run reproducible, which is what lets NoxQA smoke-run the perfect
seat headlessly and diff the checksum.

## How to extend

1. **Author a real bank**: replace `TRIVIA` (and/or `_make_arithmetic`) with a curriculum JSON;
   an AI writer can generate a themed, grade-levelled set.
2. **More question types**: true/false, multi-select, fill-in-the-blank, image questions — each
   is a new `_make_*` returning the same `{prompt, choices, correct, cat, diff}` shape.
3. **Spaced repetition**: track per-question history and re-surface missed items (the report
   card already tracks per-category performance).
4. **Lives / streak rewards**: add a lives system or unlockables on streak milestones.
5. **Multiplayer buzzer**: run one engine and race two players to answer (deterministic → fair).
6. **Difficulty curves**: tune `TIME_LIMIT`, the point weights, and the adapt step at the top of
   the file, or make them per-subject.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed yields an identical final `checksum()` **and the same
  generated questions**; a **different seed produces a different quiz**.
- **partial determinism** — 8 questions of the same seed produce an identical mid-quiz checksum.
- **scoring is real** — the **perfect** seat **aces the quiz (grade A)** and a per-category
  **report card** is produced, while a **guess** seat scores **strictly worse** (proving the
  scoring + grading respond to answers). Validated: perfect = **20/20, grade A, score 9450,
  streak 20, 3 categories**; guess = **5/20, score 850**.

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> correct=20/20 score=9450 grade=A streak=20 cats=3  guess_correct=5 guess_score=850
# → PROBE PASS
```
