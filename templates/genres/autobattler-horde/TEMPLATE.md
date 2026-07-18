# Autobattler Horde Template ("How Many Dudes?"-style army-scaler, 2D)

A **horde auto-battler** ("How Many Dudes?"-lineage army-scaler) run as a **deterministic sim**:
between waves you spend gold to **recruit** a horde (cheap **dudes** + tougher **brutes** + rare
**champions**), then your *whole* army **auto-battles** the wave's enemy army in a deterministic
focus-fire attrition sim where **both numbers and stats matter** — more units means more total DPS
*and* a deeper HP pool to grind through. Survivors persist + heal (a snowball); clear all waves to
**win**, get wiped to **lose**. It is OUR OWN engine with generic content — a pure, seedable,
deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py autobattler-horde <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no addons.

> **A distinct auto-battler flavor.** The `auto-battler` template is TFT-lite: a shop, a bench, unit
> synergies, trophies. **This** template is the *army-scaler* — spend, swell your headcount, and let
> the whole horde clash. If you want the shop/synergy flavor, use `auto-battler`; for the "how many
> dudes" fantasy, use this.

## What you get

- **`HordeEngine`** (`scripts/horde_engine.gd`) — a pure `RefCounted` engine with ZERO Godot-node
  dependency and ZERO `Time` calls. One seeded RNG builds the enemy waves and the combat itself is
  pure integer arithmetic, so a whole run replays **byte-identically** from a seed:
  - **A recruit economy** — three unit tiers (dude / brute / champion) with cost / hp / atk.
  - **A scaling enemy wave generator** — bigger + tougher each wave, brutes + champions entering as
    the wave climbs.
  - **A deterministic focus-fire attrition battle** — each tick the *sum* of a side's atk hits the
    *other* side's front unit; a downed front is removed and the next steps up. Victory therefore
    tracks whichever side has the higher **hp × atk product** — and because a swarm of dudes is
    gold-efficient on that product, "how many dudes" is a genuinely good strategy.
  - **Survivors persisting + healing** between waves, and a **clear reward + interest** economy tuned
    so a well-built horde **snowballs**.
  - **`checksum()`** — an FNV-1a fold over the state — the cross-process determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A deterministic commander auto-seat** — plays the "how many dudes" strategy (a champion anchor
  when flush, a modest brute front line, then pile the rest into dudes) and auto-battles each wave.
  `auto_play_to_end()` plays a whole run.
- **`GameManager` autoload** — recruits + fights, plus the NoxDev save/load ABI and an `autoplay`
  toggle.
- **Play surface** (`scenes/horde_view.tscn` + `scripts/horde_view.gd`) — the wave/gold HUD, the
  recruit + **FIGHT** buttons, the horde visualised as rows of tier-coloured blocks, and the last
  battle result. **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the recruit economy, the wave generator, the focus-fire battle, and the
survivors/reward snowball — lives in `HordeEngine` as pure data + functions. The view only draws
blocks and forwards clicks, which is why a whole run is testable with **no UI**.

The battle model is the thing to understand: it's **focus-fire attrition**, so a side's *entire*
attack pools onto the enemy's current front unit, and the number of ticks to wipe a side ≈
`total_enemy_hp / your_total_atk`. Work that through and victory reduces to *whoever has the larger
`total_hp × total_atk`* — which is why **more cheap dudes** (great product-per-gold) beats a handful
of expensive units, and why the snowball matters: survivors carry their product forward. The
deterministic seat and the human's clicks call the *same* `recruit` / `fight_wave`, so they can't
diverge.

## How to extend

1. **Unit variety + abilities**: ranged units, healers, tanks with taunt, on-death effects, tier
   synergies — the battle loop is one function to extend.
2. **Formations + positioning**: move from a single front line to lanes/rows so placement matters.
3. **Boss waves + modifiers**: elite enemies, wave modifiers, a shop of one-time upgrades.
4. **A juicier battle view**: animate the two armies marching + clashing with per-unit deaths rather
   than an instant resolve.
5. **Meta-progression**: persistent unlocks, a run currency, difficulty tiers.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **40-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes (`PROBE PASS`):

- **seed determinism** — the same seed run twice yields an identical final `checksum()`; a
  **different seed builds different enemy waves**.
- **partial determinism** — 6 rounds of the same seed produce an identical checksum across runs.
- **a real run** — the greedy commander recruits a growing horde and auto-battles scaling waves to a
  genuine terminal. Validated: the horde **snowballs from ~8 units to ~100 and clears all 12 waves**
  (final power 354).

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> wave=13 army=100 power=354 won=true
# → PROBE PASS
```
