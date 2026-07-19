# Martial Arts Brawler Template (Jade-Empire-lineage 2D beat-'em-up RPG)

A **JADE EMPIRE**-lineage 2D **beat-'em-up martial-arts RPG**: you learn
**martial-arts STYLES** from masters of different cultures, **switch styles
mid-fight** to exploit a rock-paper-scissors matchup triangle, and grow a
martial-artist through a bounded **campaign** of escalating encounters ending in a
final duel. Clear the final duel to **WIN**; burn all your continues to **LOSE**.
Our OWN engine, generic content (no trademarks).

## KEY DESIGN DECISION — deterministic CUSTOM combat (not CharacterBody2D)

Godot's physics + the frame scheduler are **not** guaranteed bit-identical across
runs / builds / platforms, which would break byte-identical replays + the
determinism probe. So `BrawlerEngine` (a pure `extends RefCounted`, **no**
Godot-node dependency) is our OWN fixed-timestep 1-D-stage combat sim:

- Each fighter is a **point on a horizontal stage** — `x`, `x` velocity, `facing`,
  `HP`, `CHI` (stamina), a current **STYLE**, and an **action state**
  (`idle` / `attacking` / `block` / `blockstun` / `hitstun`).
- Each fixed step (**DT = 1/60**): resolve each side's **input** (a human's queued
  action or the fighter's AI policy) → possibly start an **ACTION** with real
  **startup / active / recovery frame data**; advance actions; during the **ACTIVE**
  frames a move projects a **HITBOX interval** in front of the fighter (a melee
  reach, or a **travelling chi projectile**); a hitbox overlapping the foe's
  **HURTBOX** applies damage — scaled by the move, the attacker's **attributes**, a
  **STYLE MATCHUP** multiplier, and **technique upgrades** — plus knockback and
  hitstun; **blocking** converts the hit to chip + blockstun. Then integrate
  knockback/walk motion, keep bodies from overlapping, regen chi, and re-face.
- The **combat has zero randomness**. The only RNG is one seeded generator used for
  optional **AI decision jitter** (`config.ai_jitter`, default `0.0` → perfectly
  canned) and it is part of save/load. **MAX_STEPS** bounds every fight → a
  timeout, never an infinite spar.

Given `(seed, config, input/AI script)` a fight is 100% reproducible and
**byte-identical across separate processes** (the determinism probe prints a
`CANON=` checksum the harness compares across two runs).

## Styles + techniques (the Jade-Empire heart)

**Six martial-arts styles** from distinct cultures / archetypes, each with base
stat modifiers and a **three-move set** (light / heavy / special) of genuine frame
data (startup, active, recovery, damage, reach, chi cost, knockback, hitstun, and
properties like armor / launcher / projectile / throw / counter):

| Style | Culture | Archetype | Feel |
|-------|---------|-----------|------|
| Drunken Fist | Southern Chinese | **fast** | quick light hits, low commitment |
| Iron Ox | Mongolian Steppe | **power** | slow, armored, huge damage |
| Willow Guard | Japanese Aiki | **defensive** | high guard, counters |
| Ghost Palm | Tibetan Highland | **ranged** | travelling chi projectiles |
| Steel Crane | Korean Staff | **weapon** | long reach, spacing |
| Coiling Serpent | Thai Clinch | **grappling** | close throws, big knockback |

**STYLE MATCHUP triangle** — a *real* advantage relation, not cosmetic: it scales
damage (`MATCHUP_ADV = 1.40` when your archetype beats theirs, `MATCHUP_DIS = 0.70`
when it loses). The core triangle holds exactly — **fast beats power, power beats
defensive, defensive beats fast** — with three consistent extra spokes
(ranged / weapon / grappling) and **no mutual contradictions** (verified in the
styles probe). Switching to the right counter measurably wins faster; the styles
probe asserts a countering style leaves the foe with strictly less HP than a
disadvantaged one, all else equal.

**Learning + technique upgrades**: you start knowing **two** styles; each master in
the campaign **teaches one more** (learning unlocks its moves). Spending a
**technique point** on a known style raises every one of its moves' damage by
`+10%` per point — a light per-style upgrade tree.

**Style-switching mid-fight** (the Jade-Empire move): between actions the player can
switch the active style, which changes the available move set **and** the matchup
vs the current foe. In the UI this is a row of style buttons (or the `Q` key to
cycle).

## RPG progression + campaign

- **Three attributes** — **Body** (HP + physical damage), **Mind** (incoming-damage
  guard), **Spirit** (chi pool + chi/special damage) — à la Jade Empire.
- **XP → level up**: winning a fight grants XP; levels grant attribute + technique
  points (auto-invested for headless auto-play, spendable in the UI).
- **Campaign**: a finite ladder of six encounters (`BrawlerEngine.CAMPAIGN`) that
  **ramps in difficulty** (per-encounter `hp_scale` / `dmg_scale`) — a weakling
  opener up to the **Lotus Tyrant final duel**. Win a fight → earn XP + learn the
  master's style + advance; lose → burn a **continue**; out of continues → campaign
  **LOSS**. Clearing the final duel → campaign **WIN**. The campaign always
  terminates (finite encounters × finite continues × step-capped fights).
- **Both outcomes are reachable by deterministic auto-play**: `run_campaign()` on
  the `normal` difficulty **wins** the whole ladder with a counter-and-guard
  policy; on the `buffed` difficulty (foes ×2.2 HP / ×2.05 damage, player ×0.72
  damage) the same policy is overwhelmed and **loses** — both proven by the
  progression probe.

## What you get

- **`scripts/brawler_engine.gd`** — the pure `BrawlerEngine` (~1100 lines): the
  fixed-timestep combat sim, the six styles + move sets, the matchup triangle,
  hitbox/hurtbox resolution (melee + projectile), block/chip, knockback + hitstun,
  RPG attributes / XP / levels / learning / technique upgrades, the campaign
  driver, deterministic AI policies, FNV-1a checksums (`fight_checksum` /
  `run_checksum`), and full JSON-safe save/load.
- **`scripts/game_manager.gd`** — the `GameManager` autoload owning one engine, in
  the `game_manager` + `persistent` groups with `save_data()/load_data()` (the
  whole run — learned styles, upgrades, attributes/level, campaign progress, the
  live fight + RNG — persists).
- **`scripts/arena.gd` + `scenes/arena.tscn`** — the play surface built entirely in
  code: the stage + two fighters (markers with HP + chi bars + the active hitbox)
  drawn via `_draw()`, a fixed-timestep combat accumulator, the human input
  (light/heavy/special/guard/walk + a mid-fight style switch), a style/level HUD, a
  combat log, and a **learn / technique** mastery panel.
- **`_probes/`** — five headless probes, each prints one `DEBUG: … fails=N => OK`
  and quits:
  - `combat_probe` — a reaching active hit deals damage + hitstun + knockback; a
    whiff deals none; blocking reduces to chip; a full fight KOs and is bounded.
  - `determinism_probe` — same seed + same script → identical checksum (mid-fight,
    full campaign, and cross-process via `CANON=`); a different script diverges;
    AI jitter diverges across seeds.
  - `styles_probe` — every style has its 3-move frame data; the matchup triangle is
    consistent; the matchup multiplier measurably changes a controlled duel;
    switching changes the move set.
  - `progression_probe` — learning unlocks a style; a technique upgrade raises move
    damage; XP raises attributes; auto-play WINS on base and LOSES on buffed, and
    the campaign terminates.
  - `rules_ui_probe` — illegal actions are rejected + counted; the main scene builds
    its UI; the whole run save/load round-trips (styles + progression + RNG).

## Controls

`J` light · `K` heavy · `L` special · `Space` guard (hold) · `A` / `D` step
back/forward · `Q` cycle style · `Esc` pause · `Backspace` restart. Buttons mirror
every action; **Auto-Fight** hands side 0 to the AI, **Auto Campaign** plays the
whole ladder.

## Run the probes / the import gate

```bash
GODOT="C:/godot/Godot_v4.6.1-stable_win64_console.exe"
DIR="templates/needs-work/action/martial-arts-brawler/skeleton"
# import gate (must exit 0, no parse/type errors):
"$GODOT" --headless --editor --path "$DIR" --quit
# each probe (expects fails=0):
for p in combat determinism styles progression rules_ui; do
  "$GODOT" --headless --path "$DIR" "res://_probes/${p}_probe.tscn" --quit-after 12000
done
```

## How it plugs into the factory

Scaffolds standalone or as the **combat core** of a larger action-RPG. The pure,
node-free `BrawlerEngine` means the whole campaign replays byte-identically + drives
headlessly (auto-play + probes need no UI). Suggested primitive skills: give each
master / rival a persona + pre-fight taunt via **companion-npcs** + Dialogue
Manager; swap the flat fighter markers for real sprites + a stage backdrop via
**pixel-perfect** (fighter/style icons via `qwen-icon`, stage splash via
`zit-txt2img`). Asset-plan hints: fighter + style-icon sprites, a dojo/stage
backdrop, master/rival portraits, and hit / block / whoosh / KO / win-lose SFX.
