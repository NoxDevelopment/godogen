# Word Puzzle Template (Wordle-style letter deduction + marathon, 2D)

A Wordle-lineage **word puzzle** run as a **deterministic sim**: each **round** hides a seeded
target word; you **guess** words and each guess is scored **per-letter** — **hit** (right letter,
right spot) / **present** (right letter, wrong spot) / **absent** — using the exact Wordle
duplicate-letter rule. Solve inside `MAX_GUESSES` to bank a **streak** + score; play a whole
**marathon** of rounds for a run. It is OUR OWN engine with a generic embedded word list (authors
swap in a full dictionary) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py word-puzzle <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

## What you get

- **`WordEngine`** (`scripts/word_engine.gd`) — a pure `RefCounted` engine with ZERO Godot-node
  dependency and ZERO `Time` calls. One seeded RNG picks the target sequence, so a whole marathon
  replays **byte-identically** from a seed:
  - **Correct per-letter feedback** — the exact Wordle algorithm: greens (hits) consume the
    answer's letter counts first, then presents are handed out from the *leftover* counts, so
    duplicate letters score honestly (the part naive clones get wrong).
  - **Guess validation** against the word list, and a **fewer-guesses-more-points + streak**
    scoring model.
  - **A marathon** of `ROUNDS` distinct rounds (no repeated targets) — a self-contained run with a
    banked score and a best-streak.
  - **`checksum()`** — an FNV-1a fold over the state — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** marathon including RNG state.
- **A deterministic solver auto-seat** — filters the word list to those still **consistent with
  every (guess, feedback)** so far, then greedily picks the next guess by positional letter
  frequency across the survivors (with a distinct-letter information bonus). `auto_step()` /
  `auto_play_to_end()` play a whole marathon.
- **`GameManager` autoload** — collects the typed guess and submits it, plus the NoxDev save/load
  ABI and an `autoplay` toggle.
- **Play surface** (`scenes/word_view.tscn` + `scripts/word_view.gd`) — the guess grid with
  HIT/PRESENT/ABSENT colouring, an on-screen keyboard coloured by known letters, and a
  round / streak / score HUD. **Type A-Z** · **Backspace** · **Enter** submits · **T** autoplay ·
  **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the per-letter scoring with correct duplicate handling, guess validation, streak
scoring, and the marathon of rounds — lives in `WordEngine` as pure data + functions. The view
only renders the grid/keyboard and forwards typing, which is why the whole marathon is testable
with **no UI**.

The solver is the piece worth studying: it never "knows" the answer. It re-derives the candidate
set every turn by asking, for each dictionary word, *"if this were the answer, would my past
guesses have scored exactly the way they did?"* — that single `score_word(guess, candidate) ==
feedback` consistency test (the same function used to score the real guess) is the whole solver,
and it's why the AI and the rules can never drift apart.

## How to extend

1. **A real dictionary**: replace the embedded starter `WORDS` with a full answer list + a larger
   valid-guess list (the engine already separates *scoring* from *validity*).
2. **Daily word + share card**: seed the target from the date and export the emoji-grid recap.
3. **Difficulty + variants**: hard mode (must reuse revealed hints), longer words, more/fewer
   guesses, a timed blitz — all are `WordEngine` consts.
4. **A clickable keyboard + hints**: wire the on-screen keys to input and add a reveal-a-letter
   hint economy.
5. **Tile-flip juice**: the per-letter feedback is already exposed — drive a staggered flip reveal
   and a keyboard recolour.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed picks a different target sequence**.
- **partial determinism** — 10 solver steps of the same seed produce an identical checksum across
  runs.
- **a real marathon** — the filtering solver deduces the seeded targets from per-letter feedback and
  banks a streak to the end of the rounds. Validated: the solver **cracks 8/8 words for a perfect
  streak-8 run** (score 396).

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> score=396 solved=8/8 best_streak=8
# → PROBE PASS
```
