# Adult Puzzle Dating Template (HuniePop-style match-3 → dating meter — SYSTEMS ONLY, 2D)

A HuniePop-style **match-3 that feeds a dating meter**, run as a **deterministic sim**.

> **This template ships the PUZZLE + DATING SYSTEMS ONLY.** A real match-3 board whose cleared
> tokens convert to **affection** for the current date (weighted by that character's
> **preferences**), a **gift economy**, and route completion — plus a `mature_content` **gating flag
> that is OFF by default** and only calls **empty author hooks**. It contains **no explicit
> content**. An author who adds mature content is responsible for their own assets, an
> **age-verification gate**, and platform compliance. (Same clean-room approach as `dating-sim`,
> `adult-management`, and `adult-trainer`.)

Scaffold with:

```bash
python templates/tools/scaffold.py adult-puzzle-dating <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

## What you get

- **`PuzzleDateEngine`** (`scripts/puzzledate_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG fills + refills the board, so a whole
  date replays **byte-identically** from a seed:
  - **A full match-3 core** — a no-initial-match fill, adjacent-swap legality that *requires* a
    match, run-of-≥3 detection (horizontal + vertical), clear → gravity → RNG refill, and
    **cascades**.
  - **Affection conversion** — each cleared token adds `BASE × the current character's preference
    weight for that token type × the character's mood multiplier`, so matching what your date *likes*
    is what advances the route.
  - **A currency** earned from clears and a **gift economy** — buy gifts that add affection + raise
    the mood multiplier.
  - **Multiple dateable characters** each with a fixed preference vector, and **route completion** —
    reach an affection threshold to finish a character, then advance to the next; finishing all
    routes wins.
  - **A `mature_content` gate** (off) whose `_mature_hook()` is **intentionally empty** — the gated
    milestone (route completion) calls it and nothing happens; no content ships.
  - **`checksum()`** — an FNV-1a fold over the state — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A deterministic player auto-seat** — enumerates every legal swap and picks the one with the best
  preference-weighted immediate clear, buying the best affordable gift when flush.
  `auto_play_to_end()` plays a whole run.
- **`GameManager` autoload** — drives token swaps + gift buys, plus the NoxDev save/load ABI and an
  `autoplay` toggle.
- **Play surface** (`scenes/puzzledate_view.tscn` + `scripts/puzzledate_view.gd`) — the token board,
  the current date's affection bar + **preference legend**, the gift buttons, a currency/turn HUD, a
  route roster, and an **OFF-by-default mature-content gate toggle** with a SYSTEMS-ONLY notice.
  **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the match-3 (fill/legality/matches/gravity/cascade), the affection conversion, the
gift economy, and route completion — lives in `PuzzleDateEngine` as pure data + functions. The view
only draws the board and forwards clicks, which is why a whole date is testable with **no UI**.

The one idea that makes this its own genre (and not just the `match-three` template) is the
**coupling**: clears don't score points, they score *affection for a specific person*, filtered
through that person's **preference vector** and **mood multiplier**. So the optimal move changes with
*who* you're dating — and the deterministic seat proves it by scoring every candidate swap through
the current target's preferences. The mature layer is deliberately just a flag + an empty hook at
route completion: the puzzle→affection loop is the whole game.

## How to extend

1. **Character + preference design**: a bigger roster, richer preference vectors, tokens a date
   *dislikes* (negative weights), and per-date backdrops/portraits.
2. **Special tokens + power-ups**: broken hearts (penalties), passion bombs, a "sentiment" resource
   like HuniePop's, timed vs move-limited dates.
3. **A date structure**: a hub → pick-a-date → puzzle loop, a gift shop, a day/energy economy.
4. **Move hints + juice**: a valid-move hinter and match-preview highlight; the engine already
   exposes legality + cleared counts.
5. **Your gated layer (optional)**: if you ship a mature edition, wire `_mature_hook()` behind a real
   **age-verification** gate with **your own** assets and keep the default build gate-off.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed fills a different board**.
- **partial determinism** — 6 moves of the same seed produce an identical checksum across runs.
- **a real run** — the greedy player matches preference-weighted tokens, buys gifts, and completes
  character routes to a genuine terminal. Validated: it **completes all 3 character routes in 15
  turns** of a 40-turn budget — while the **`mature_content` gate stays OFF** for the whole run
  (asserted: SYSTEMS ONLY).

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> turns=15 routes=3 aff0=143 won=true mature=false
# → PROBE PASS
```
