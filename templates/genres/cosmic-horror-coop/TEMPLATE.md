# Cosmic-Horror Co-op Template (investigation + doom, 2D board game)

A **co-operative** cosmic-horror investigation board game — the Eldritch Horror /
Arkham Horror lineage, but **our own generic genre engine** (no trademarked
content). 1-4 **investigators** play as ONE team and race to solve **Mysteries**
before **Doom** consumes the world. The whole rules engine is a pure, seedable,
headless-testable `RefCounted` class; the AI teammates are a genuine heuristic, not
random. Scaffold with:

```bash
python templates/tools/scaffold.py cosmic-horror-coop <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`CosmicEngine`** (`scripts/cosmic_engine.gd`) — the entire co-op game as pure,
  seedable data + rules (no Node dependency), so it replays **byte-identically**
  from a seed and is fully testable with no UI:
  - **Investigators** — 8 archetypes (Scholar / Detective / Soldier / Occultist /
    Doctor / Reporter / Drifter / Priest), each with 5 **skills**
    (lore / influence / observation / strength / will), **health** + **sanity**
    pools (either at 0 → that investigator is **defeated**), a **clue** + **asset**
    inventory, and a **location**.
  - **World map** — a graph of **9** named locations (safe towns / clue sites /
    gate spots) with a fixed connection layout; investigators move along edges;
    BFS distance drives autopilot movement.
  - **Global tracks** — **DOOM** (ticks down on ominous mythos; **lost at 0**) and
    **MYSTERY** progress (solve **3** to **win**). A **14-card mythos deck** drives
    the antagonist automatically each round.
  - **Round structure** — (1) **Action** phase: each investigator takes **2**
    actions from `{move, rest, acquire, prepare, trade, spend_clue}`; (2)
    **Encounter** phase: each resolves a location encounter → a **skill check**;
    (3) **Mythos** phase (automated): advance doom, open gates + spawn monsters,
    apply a global effect, then every monster hunts the nearest investigator.
  - **Skill checks (the core mechanic)** — roll a dice pool of size = tested skill
    (+ asset / focus bonuses); each die is a success on **5-6**; passes at
    ≥ required successes; **clues** may be spent to **reroll** failed dice. The
    reusable resolver is `resolve_from_rolls()` (pure, boundary-tested) wrapped by
    `perform_check()` (rolls via the seeded RNG, clamps clue spend to what you
    hold).
  - **Monsters** — 6 types (Cultist / Deep One / Shambler / Nightgaunt / Maniac /
    Spawn of the Outer Dark) with distinct toughness / damage / horror / check
    skill / speed; spawn from gates, move toward investigators, force combat;
    defeating one yields clues.
  - **Mysteries** — 6 cards across 4 concrete kinds: **research** / **ritual**
    (invest K clues then pass a finalize check), **seal** (close X gates), **hunt**
    (slay a spawned quarry). Solve 3 to win.
  - **Loss** — Doom 0, **all** investigators defeated, or **too many gates open**
    (difficulty gate limit), or the round cap.
- **Co-op seat controllers** — all investigators are ONE team; every seat carries a
  `ControllerKind`:
  - **`HUMAN_LOCAL`** — a local human; the dispatcher blocks for UI input.
  - **`AI_AUTOPILOT`** — the built-in co-op heuristic `ai_choose()`: it enumerates
    every legal action and scores each toward the **shared objective** — rest when
    a pool is critically low (and safe), invest clues into the active clue-mystery
    (huge when the clue would **complete** it), move toward the mystery goal (clue
    sites / open gates / the quarry), grab assets at a safe stop, bank focus before
    a looming encounter, hand a clue to a teammate about to finalize, and stay to
    fight a monster on it. **Deterministic** (index tie-break); never illegal;
    never stalls. This is the "AI co-op buddies" mode.
  - **`AI_LLM`** / **`REMOTE`** — documented **future seams**: present as enum
    values, **not** wired, **not** stubbed. Using one **fails loud**
    (`is_supported_kind()` is false; the dispatcher's default branch asserts). Each
    drops in as ONE dispatch case + one hook.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns the engine, is the
  co-op turn **dispatcher** (auto-resolves autopilot seats, blocks on humans, with
  a "pass the device" hand-off for hotseat), and adds the NoxDev ABI +
  `save_data()/load_data()`.
- **Board scene** (`scenes/board.tscn` + `scripts/board.gd`) — a code-built view: a
  drawn **map** (locations + connections + investigator / monster tokens), a
  **panel per investigator** (skills / HP / SAN / clues / assets / location), the
  **DOOM + MYSTERY + gate** tracks, the active mystery, an action bar for the human
  seat, and a chronicle log. Reads the engine and forwards clicks only.
- **NoxDev template ABI** — `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups; `pause` + `restart` input;
  `"scalable_text"` on every label/button.

## The doom / mystery / skill-check model (the part worth understanding)

**Skill checks** are the spine: `perform_check(inv, skill, required, bonus,
max_clue_spend)` rolls `pool = effective_skill + bonus + focus` d6, counts 5-6 as
successes, and — if short — spends clues to reroll failing dice one at a time until
it passes or the (clamped) budget runs out. Encounters, combat, gate-closing and
mystery finalization all route through this one resolver, so tuning difficulty is
mostly tuning `required` and the dice pools.

**Doom vs mysteries** is the whole tension: the mythos phase ticks Doom **down**
every round (scaled by the difficulty **threat** multiplier) and keeps opening
gates + spawning monsters, while the team converts **clue income** (investigate
encounters, defeated monsters, sealed gates, clue-surge mythos) into **mystery
progress**. Win = 3 mysteries before Doom hits 0; lose = Doom 0 / party wiped /
gates overflow. Both outcomes are genuinely reachable from the same rules — only
the `DIFFICULTY` preset (doom start, gate limit, threat, starting vitals) changes:
across 60 seeds, `normal` won 47 and lost 13 on **autopilot alone**, while `harsh`
lost all 60 (Doom-0), and normal seeds 2/12 show party-wipe losses — nothing is
hardcoded.

**The autopilot** is a real weighted evaluator (see `ai_choose` / `_score_action`):
it computes each investigator's **goal location** from the active mystery kind
(nearest clue site / open gate / quarry), then scores moves by BFS-distance
reduction, rest by how low its worst pool is, clue investment by whether it would
finish the mystery (holding a combat reserve otherwise), and so on — the same
heuristic that reaches the wins above.

## How to extend

1. **New content is data**: add archetypes (`ARCHETYPES`), locations
   (`LOCATIONS` + `MAP_EDGES` + a `NODE_POS` entry in `board.gd`), monsters
   (`MONSTER_DB`), assets (`ASSET_DB`), mythos cards (`MYTHOS_DECK`), or mysteries
   (`MYSTERY_DB` + `MYSTERY_ORDER`). The engine and view adapt with no structural
   change.
2. **Difficulty**: tune the `DIFFICULTY` presets (doom start / gate limit / threat
   / starting-vitals mods), or add a new preset — the rules stay identical.
3. **Interrogations / flavor**: give each archetype (and monster) a
   `companion-npcs` persona + Dialogue Manager and open a talk scene from an
   encounter.
4. **Real scenes**: swap the code map/panels for location backdrops + investigator
   portraits + monster art (see the asset-plan hints in the registry entry).
5. **More seats**: wire `AI_LLM` (a local LLM picks from `legal_actions()`,
   re-validated via `is_legal`/`apply_action`) or `REMOTE` (a networked action) —
   each is one dispatch case in `GameManager._advance_dispatch()`; the seam is
   already carved and fails loud until filled.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the whole mid-game (incl. RNG) already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor` import exits with **zero
script errors**, and **seven** headless probes each report `fails=0`:

- **(a) WIN** — an all-autopilot game on a favorable seed reaches a WIN (3
  mysteries before Doom), with **no illegal actions**, invariants held throughout,
  and termination within the round cap.
- **(b) LOSS** — a harsh seed/config reaches a LOSS justified by a real condition
  (Doom 0 / party wiped / gate overflow) with a non-empty reason.
- **(c) skill-check** — dice-pool success counting is correct at the boundaries
  (0 successes, exactly the required threshold, a clue reroll **adds** a success);
  over-spend is rejected (never past budget, never once passed; `perform_check`
  never drives clues negative).
- **(d) determinism** — same seed → byte-identical final state **and** log;
  different seed → a different trace.
- **(e) rules/legality** — non-adjacent moves, out-of-turn / defeated-investigator
  actions, spending clues you lack, and malformed actions are all rejected with
  game state unchanged and counted; doom / gate / monster / vitals / mystery
  invariants hold across a full autopilot game (0 illegal).
- **(f) UI-build** — the board scene builds its map (35 children), 4 investigator
  panels, and the DOOM/MYSTERY tracks, and a scripted **human** action resolves and
  advances state.
- **(g) save/load** — a mid-game snapshot → mutate → load equals the snapshot
  exactly, and two continuations from the same snapshot stay identical (RNG state
  round-trips).
