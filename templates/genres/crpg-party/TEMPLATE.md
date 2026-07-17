# Party CRPG Template (Baldur's-Gate-lite — D&D-5e-lite adventure + initiative combat, 2D)

A Baldur's-Gate / Gold-Box-lineage **party CRPG** on a **D&D-5e-lite** ruleset: a
4-hero party (fighter / wizard / cleric / rogue) runs an **adventure path** of encounters
— initiative-order combats, skill-check **events**, and rests — leveling up until it
beats the boss or is wiped. It is OUR OWN engine with generic content (no trademarks) —
a pure, seedable, deterministic CRPG engine. Scaffold with:

```bash
python templates/tools/scaffold.py crpg-party <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`CrpgEngine`** (`scripts/crpg_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One private RNG seeds the party rolls, the
  encounter path, **and every d20 attack / save / damage roll**, so a whole adventure —
  crits, misses and all — replays **byte-identically** from a seed. It is a **real d20
  kernel**:
  - **Six ability scores** per hero with 5e modifiers + proficiency; class profiles
    (hit die, armor, casting stat, extra attacks) → **HP** = HD + CON + level, **AC** =
    10 + DEX + armor.
  - **Initiative** (d20 + DEX) turn order; **d20 attack rolls** vs AC with **nat-20
    crits** (double damage dice), STR/DEX damage mods, rogue **sneak attack**, and fighter
    **extra attack** at level 5.
  - **Spells** off limited **slots** — wizard **magic missile** (auto-hit) + **fireball**
    (an AoE **DEX save** for half); cleric **cure wounds** + **bless** (party +1 to hit) —
    with a **save DC** of 8 + prof + casting mod; plus **saving throws**.
  - **XP + level-up** (more HP, more slots, extra attack) awarded on victory.
  - **The adventure path** is a seeded mix of **combat / skill-check event / rest** nodes
    ending in a **boss dragon**. **Events** are real d20 ability checks (STR/DEX/INT/WIS/CHA
    vs a DC) resolved by the best-suited hero, branching to a **reward** (gold / heal / xp /
    slot) or a **penalty** (trap / curse / ambush — an ambush even injects a surprise
    fight). **Rests** restore HP + slots.
  - **Win** = clear the boss; **lose** = a TPK.
  - **`checksum()`** — an FNV-1a fold over the whole state — the cross-process determinism
    proof, meaningful precisely because the rolls are seeded.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **Weighted-heuristic party + enemy AI** — clerics heal the badly hurt then bless,
  wizards fireball a crowd else magic-missile, martials focus the lowest-HP foe; enemies
  focus the weakest hero. `auto_step()` / `auto_play_to_end()` run the **whole adventure**
  headlessly, **balanced to a real challenge** (~30% auto-win, reliably reaching the boss).
- **`GameManager` autoload** — runs the party's combat turns while the engine AI resolves
  enemy turns; plus the NoxDev save/load ABI and a `party_auto` toggle.
- **Play surface** (`scenes/crpg_view.tscn` + `scripts/crpg_view.gd`) — renders party +
  enemy stat blocks (HP, level, slots, the **active initiative actor**), the combat log,
  and encounter progress in code. **Click an enemy** to attack (wizard auto-picks fireball
  vs a crowd) · **H** heal · **F** fireball · **B** bless · **D** defend · **Space** resolve
  an event · **A** full-auto · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — the d20 combat kernel, spells + slots + saves, initiative, XP/leveling, the
adventure path, the skill-check events, and the AI — lives in `CrpgEngine` as pure data +
functions. The view only reads state and issues commands, so the whole adventure is
playable and testable with **no UI**, and it **drops in as the RPG core of a larger game**
(town hub, quests, inventory): keep the engine, call `act_attack` / `act_spell` /
`resolve_event`, read `party` / `enemies` / `phase`.

The randomness is **real** (attacks miss, dice crit, saves succeed) yet the run is still
byte-identical across processes because the *same seeded RNG* produces the *same rolls in
the same order* — which is what lets NoxQA smoke-run a whole self-playing adventure
headlessly and diff the checksum, and what a **deterministic co-op CRPG** would need.

## How to extend

1. **More classes / spells**: add to `CLASSES` and the `_cast` match (paladin smite,
   ranger volley, more slots/levels); combat, AI, and save/load pick it up.
2. **Richer adventure**: author `EVENTS` + the `_gen_path` node mix (shops, moral choices,
   branching paths, multiple bosses) — an AI-DM can emit new nodes at runtime.
3. **Inventory + gear**: give heroes weapons/armor that modify atk/AC/damage and a town
   hub between adventures.
4. **Positioning**: bolt the tactics-srpg grid onto combat for BG3-style tactical fights
   (the two engines share the d20 idiom).
5. **Combat forecast / logs UI**: the roll functions are pure — surface hit%, expected
   damage, and a scrolling combat log.
6. **Deterministic co-op**: because the run is command-driven + seeded, exchange the party
   commands per turn (nox_netcode) for a shared-party multiplayer CRPG.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the whole run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed), a **30-frame headless main-scene smoke** runs clean, and the headless
**determinism + playability probe** (`_probes/determinism_probe.tscn`) passes
(`PROBE PASS`):

- **seed determinism (with rolls)** — the same seed played to completion twice yields an
  identical final `checksum()` **even though attacks/saves/damage are rolled**; a
  **different seed diverges**.
- **partial determinism** — 12 steps of the same seed produce an identical mid-run
  checksum across runs.
- **seeded party + path** — two seeds produce **different initial states**.
- **real adventure** — the run reaches a genuine terminal (`phase == "done"`), advances
  through multiple encounters, and the party **levels up** from combat XP.
- **balance** — a 40-seed sweep reaches the boss on average (avg end-node ~8.4) and wins
  ~30% of the time. Validated: **seed 20260720 clears all 9 nodes to VICTORY at party
  level 4** (74 gold banked).

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> encounter=9 won=true max_level=4 gold=74
# → PROBE PASS
```
