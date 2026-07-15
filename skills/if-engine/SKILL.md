---
name: if-engine
description: |
  The computed interactive-fiction / gamebook engine core for Godot 4 (spec
  phase P0) — a pure, seedable, headless-tested engine that plays a data-driven
  narrative graph (passages/choices/conditions/effects) over a GENERIC rule
  engine where a ruleset is DATA, not code. Use when a template needs
  deterministic text-RPG / gamebook resolution with NO LLM and NO networking:
  attribute/dice checks, item gates, variable & flag effects, branching to
  endings. Ships the reusable `nox_if_engine` addon + the proven `ff-2d6`
  ruleset as data (2d6 roll-under SKILL/STAMINA/LUCK, reusing the ff-gamebook
  dice mechanic) + `srd-d20` and `pbta` family fixtures proving the same engine
  expresses d20-vs-DC and PbtA threshold bands. Extends ff-gamebook SessionState
  + the VN runtime-variables/inventory model. Full design:
  Noxdev-Studio/docs/GAMEBOOK_ENGINE_SPEC_2026-07.md (§2, §2.5, phase P0).
---

# if-engine — the computed IF / gamebook core (P0)

The deterministic foundation the whole gamebook expansion layers onto:
**computed-core first, AI as a layer.** Every mechanic runs without an LLM and
without networking — a classic text-RPG driven by branching narrative graphs,
rule tables, dice and condition/effect logic. AI (P4) and multiplayer (P5) are
enhancement layers *over* this core, never dependencies of it.

> **Status: implemented + headless-proven (Godot 4.6.1).** The `nox_if_engine`
> addon ships under `skills/if-engine/addon/nox_if_engine/`. It plays the sample
> scenario `thornwood-crypt` end-to-end under the `ff-2d6` ruleset,
> deterministically, and the generic resolver additionally expresses the
> `srd-d20` (meet-or-beat) and `pbta` (threshold-band) families as pure data.
> Validated headless: editor import clean (0 script errors), self-probe passes
> with `fails=0`. Modules + persistence (P1), full `srd-d20`/`pbta` builtins + a
> Ruleset Builder (P2), worldbuilder (P3), AI (P4), multiplayer (P5) follow.
> Authoritative design: `Noxdev-Studio/docs/GAMEBOOK_ENGINE_SPEC_2026-07.md`.

## TL;DR

```bash
GODOT="C:/godot/Godot_v4.6.1-stable_win64_console.exe"
PROJ="skills/if-engine/test_project"     # minimal project carrying the addon

# Editor import (parse check — 0 script errors):
"$GODOT" --headless --path "$PROJ" --import

# Headless self-test (plays the scenario, prints ONE DEBUG line, quits):
"$GODOT" --headless --path "$PROJ" res://addons/nox_if_engine/probe/if_probe.tscn
# => DEBUG: if-engine probe — ruleset=ff-2d6 scenario=thornwood-crypt … fails=0 … => OK
```

To reuse the engine, copy `addon/nox_if_engine/` into any Godot 4 project. No
autoloads are required — every piece is a `class_name`-registered pure
`RefCounted`.

## What the engine is (two data models + an interpreter)

The runtime is an **interpreter** over two data contracts. Both are DATA authored
in Studio (JSON here; ink and the node-graph view compile to the same shapes),
never hardcoded.

### 1. The narrative graph (CONTENT) — `if_scenario.gd`

The **shared** passage/choice model both authoring views target (spec §2, P0):

- **Passage** `{ id, title, text, onEnter[], check?, choices[], ending? }`
- **Choice** `{ id, text, conditions[], effects[], check?, goto }` — offered only
  when every condition holds; applies effects, optionally rolls an inline check,
  then routes.
- **Condition** `{ kind: var|attr|resource|item|flag|checkResult|always|any|all|not, key, cmp, value }`
  — `cmp ∈ {>=,<=,==,!=,>,<}`. `item` defaults to presence (`item.<key> >= 1`).
- **Effect** `{ kind: var|item|attr|resource|flag|goto, key, op, value }` —
  `var/attr/resource` op `set|add`; `item` op `grant|consume`; `flag` sets;
  `goto` routes. **Same op/cmp vocabulary as the VN engine** (`vn_runtime.gd`
  `apply_var_ops`/`var_conditions_met`) so ink + node-graph authoring converge.
- **Check node** `{ rule, args, outcomes: { <band>: {effects[], goto}, _default } }`
  — binds a *system* rule to *story* outcomes. This is the content↔ruleset seam.

### 2. The ruleset (SYSTEM) — `if_ruleset.gd` + the generic resolver §2.5

**A ruleset is data, not code.** `if_resolver.gd` interprets it. Swapping the
`ruleset.json` reskins ALL resolution.

```
ruleset = { id, name, meta, dice, attributes[], resources[], sheetTemplate, resolutionRules[] }
resolutionRule = {
  id, dice, operands[], compare, crit?, bands[], postEffects?
}
```

The **`compare` mode + `bands` + `crit`** are the only knobs that make one engine
express every family — see the table below. Operand `type ∈
{attribute, attributeArg, resource, var, param, const}`, `role ∈
{target, modifier}`, `transform ∈ {none, abilityMod, negate}`.

## How ff-2d6 is expressed as data (the proven builtin)

`data/rulesets/ff-2d6.json` reuses the ff-gamebook mechanic (`dice.gd`: 2d6 ≤
stat; double-1 always succeeds, double-6 always fails) as pure data:

```jsonc
"attributes": [ {SKILL, gen:"1d6+6", 1..12}, {STAMINA, gen:"2d6+12", 0..24}, {LUCK, gen:"1d6+6", 0..12} ],
"resources":  [ {STAMINA, from:"STAMINA", trackMax}, {provisions, default:4} ],
"resolutionRules": [
  { "id":"test", "dice":"2d6",
    "operands":[ {type:"attributeArg", ref:"attr", role:"target"} ],   // attr picked at the call site
    "compare":"roll-under",                                             // total <= target
    "crit":{mode:"doubles", lowValue:1, lowResult:"success", highValue:6, highResult:"fail"},
    "bands":[ {id:"success", when:"success"}, {id:"failure", when:"fail"} ] },
  { "id":"test-luck", "dice":"2d6",
    "operands":[ {type:"attribute", ref:"LUCK", role:"target"} ],
    "compare":"roll-under", "crit":{…same…},
    "bands":[ … ],
    "postEffects":[ {kind:"attr", key:"LUCK", op:"add", value:-1} ] }   // "testing your luck erodes it"
]
```

The scenario's check node supplies the story meaning: `{"rule":"test",
"args":{"attr":"SKILL"}, "outcomes":{"success":{…goto…}, "failure":{…goto…}}}`.

## How srd-d20 and pbta slot in as DATA (no engine change)

Both ship as fixtures (`data/rulesets/srd-d20.json`, `pbta.json`) and the same
resolver runs them — proven in the probe. Making them *full* P2 builtins is pure
data authoring:

| Family | `dice` | operands | `compare` | `crit` | `bands` |
|--------|--------|----------|-----------|--------|---------|
| **ff-2d6** (proven) | `2d6` | attribute as **target** | `roll-under` | `doubles` (1-1 win / 6-6 fail) | success / failure |
| **srd-d20** (fixture) | `1d20` | ability-mod as **modifier** (`transform:abilityMod`) + DC as **target** (`param`) | `meet-or-beat` | `natural` (nat-1 fail / nat-20 win) | crit/plain success/failure |
| **pbta** (fixture) | `2d6` | stat as **modifier** (no target) | `threshold-bands` | — | miss (≤6) / partial (7–9) / full (≥10) |

The **Ruleset Builder** (P2) is a form/JSON editor over exactly this
`ruleset.json` shape: clone a builtin, edit attributes/resolution/sheet, or import
a user system and map it in. The engine never hardcodes a system.

## State model (what a play tracks)

`if_state.gd` is the save-able runtime state, extending three existing
conventions into one object:

- ff-gamebook `SessionState` — `current_passage`, `passage_history`, `roll_log`,
  `last_check`, and the `persistent` `save_data()/load_data()` contract.
- ff-gamebook `Sheet` — but system-defined: `attributes` + `resources` (with
  `resource_max` for trackMax pools) come from the ruleset.
- VN runtime-variables/inventory — numeric `vars`, `flags`, and **inventory as
  vars under the `item.` prefix** (`grant a key` = `item.key += 1`, `needs a key`
  = `item.key >= 1`).

It holds no randomness and no rules — the Runner drives it, the Resolver
reads/writes it, conditions/effects are interpreted against it. It is the single
seam a future DM/multiplayer layer intercepts (the role `SessionState` plays for
`nox_netcode`).

## Files

| File | Role |
|------|------|
| `addon/nox_if_engine/if_dice.gd` | Seedable `NdM+K` roller — faces + total. |
| `addon/nox_if_engine/if_ruleset.gd` | Typed ruleset reader + sheet generation. |
| `addon/nox_if_engine/if_state.gd` | Runtime state + condition/effect interpreters + `persistent` save. |
| `addon/nox_if_engine/if_resolver.gd` | **The generic rule engine (§2.5).** |
| `addon/nox_if_engine/if_scenario.gd` | Shared narrative-graph model + `validate()`. |
| `addon/nox_if_engine/if_runner.gd` | Deterministic play orchestrator. |
| `addon/nox_if_engine/data/rulesets/*.json` | `ff-2d6` (proven) + `srd-d20`, `pbta` (fixtures). |
| `addon/nox_if_engine/data/scenarios/thornwood-crypt.json` | Sample scenario. |
| `addon/nox_if_engine/probe/if_probe.*` | Headless self-test. |
| `test_project/` | Minimal Godot project carrying the addon — the runnable proof. |

## Validation

Two gates, both headless + CI-friendly:

1. **Import clean** — `Godot --headless --path <test_project> --import`: zero parse
   / script errors across the addon.
2. **Self-probe** — `res://addons/nox_if_engine/probe/if_probe.tscn`: one
   deterministic process plays the sample scenario to a victory ending under
   `ff-2d6` and prints one line, e.g.
   `DEBUG: if-engine probe — ruleset=ff-2d6 scenario=thornwood-crypt win_seed=1 lose_seed=7 rolls=2 fails=0 … => OK`.
   It proves, in that one run: **passage traversal** (the history trail equals the
   authored path), a **resolved check** (dice vs attribute → outcome band) that
   **branches to an ending both ways** (a deterministically-found victory seed and
   defeat seed), **effects applied** (a var add, an item grant, an item consume,
   an attribute change, the LUCK-attrition rule postEffect), an **item gate**
   (open with the key, proven closed on a keyless state), an **ending reached**,
   and the resolver expressing the **d20** and **PbtA** families as data.

Determinism: a fixed seed replays byte-for-byte (the roller owns one seeded RNG;
the sheet is either a fixed scenario override or generated from seeded `gen`
expressions). The probe's seed scan is fixed-order, so the reported seeds are
stable across runs.

## Do not

- Do **not** add an LLM or networking to this layer — P0 is pure computed core.
  AI (P4) and multiplayer (P5) compose *over* the Runner/State; they never bypass
  the rule engine.
- Do **not** hardcode a resolution family in the engine — express it as a
  `ruleset.json` resolution rule (`compare` + `bands` + `crit`).
- Do **not** invent a second effect/condition vocabulary — reuse the shared
  op/cmp set (`set/add`, `>=,<=,==,!=,>,<`) and the `item.` inventory prefix so
  ink authoring, the node-graph view, and the VN engine all converge on one model.
- Do **not** put story routing inside a ruleset rule — rules are pure/reusable;
  the scenario's check-node `outcomes` map bands → routes + effects (content).
