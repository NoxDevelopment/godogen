# nox_if_engine — the computed interactive-fiction core (P0)

A pure, seedable, headless-tested Godot 4 engine that plays a **narrative graph**
(passages · choices · conditions · effects) over a **generic rule engine** where
a **ruleset is data, not code**. No LLM, no networking — this is the deterministic
foundation the rest of the gamebook expansion layers onto (spec
`Noxdev-Studio/docs/GAMEBOOK_ENGINE_SPEC_2026-07.md`, phase **P0**).

> **Status: implemented + headless-proven (Godot 4.6.1).** The engine plays the
> sample scenario `thornwood-crypt` end-to-end under the `ff-2d6` ruleset,
> deterministically, and the generic resolver additionally expresses the `srd-d20`
> (meet-or-beat) and `pbta` (threshold-band) families as pure data. Full builtins
> for those two + a Ruleset Builder land in **P2**; modules/persistence in **P1**.

## What's here

| File | Role |
|------|------|
| `if_dice.gd` | Seedable dice-expression roller (`NdM+K`). Returns individual faces + total (criticals inspect the faces). The system-agnostic lift of `dice.gd` / `skill_check.gd`. |
| `if_ruleset.gd` | Typed reader over a **ruleset dict** (attributes, resources, sheet template, dice defaults, resolution rules). Generates a fresh sheet from the `gen` expressions. |
| `if_state.gd` | **Runtime state** — the save-able heart. Extends ff-gamebook `SessionState` (passage flow + roll_log + `persistent` contract) + `Sheet` (attrs/resources) + the VN runtime-variables/inventory model (`vars`, `flags`, inventory as `item.*` vars). Hosts the condition + effect interpreters. |
| `if_resolver.gd` | **THE generic rule engine (§2.5).** Interprets a resolution rule → an outcome band. The `compare` mode + `bands` are what let one engine express every family. |
| `if_scenario.gd` | The **shared narrative-graph model** — passages/choices/checks/effects — that both authoring views (ink + node-graph) target. Structural `validate()`. |
| `if_runner.gd` | Deterministic **play orchestrator**: loads ruleset+scenario+seed, drives the state through the graph, resolves checks, routes by outcome. |
| `data/rulesets/*.json` | `ff-2d6` (proven builtin) + `srd-d20`, `pbta` (family fixtures). |
| `data/scenarios/thornwood-crypt.json` | Sample scenario exercising traversal, a check, an item gate, effects, endings. |
| `probe/if_probe.*` | Headless self-test → one `DEBUG: … => OK` line, quits. |

Every file is `class_name`-registered pure `RefCounted` — no scene-tree
dependency — so the engine is reusable from any script, test, or (later) the
multiplayer host.

## Data shapes

### Narrative graph (content) — `scenario` / `module.json`

```jsonc
{
  "id": "…", "name": "…", "ruleset": "ff-2d6", "start": "<passage id>",
  "sheet": { "SKILL": 9, "STAMINA": 20, "LUCK": 11 },   // fixed, or null => generate
  "init": { "vars": { "gold": 0 }, "items": {}, "flags": {} },
  "passages": [
    {
      "id": "…", "title": "…", "text": "…",
      "onEnter": [ <effect> ],              // applied on entry
      "check":   <check node>,              // auto-resolves on entry, routes by band
      "choices": [ <choice> ],
      "ending":  { "id": "…", "kind": "victory", "label": "…" }
    }
  ]
}
```

**Choice** `{ id, text, conditions:[<condition>], effects:[<effect>], check?, goto }`
— offered only when every condition holds; applies effects, optionally resolves an
inline check, then routes (a check outcome may override `goto`).

**Condition** (ANDed list; `any`/`all`/`not` nest):
`{ kind: "var"|"attr"|"resource"|"item"|"flag"|"checkResult"|"always", key, cmp, value }`
— `cmp ∈ {>=,<=,==,!=,>,<}`. `item` defaults to presence (`item.<key> >= 1`).

**Effect** (shared by choice effects, passage `onEnter`, and rule `postEffects`):
`{ kind: "var"|"item"|"attr"|"resource"|"flag"|"goto", key, op, value }`
— `var/attr/resource` op `set|add`; `item` op `grant|consume`; `flag` sets a value;
`goto` routes. Same op/cmp vocabulary as the VN engine, so ink authoring and the
node-graph view compile to exactly this.

**Check node** (binds a system rule to story outcomes):
```jsonc
{
  "rule": "test", "args": { "attr": "SKILL" },
  "outcomes": {
    "success": { "effects": [ … ], "goto": "…" },
    "failure": { "effects": [ … ], "goto": "…" },
    "_default": { "goto": "…" }               // fallback band
  }
}
```

### Ruleset (system) — `ruleset.json`

```jsonc
{
  "id": "ff-2d6", "name": "…",
  "meta": { "family": "roll-under", "license": "…", "degreesOfSuccess": [ … ] },
  "dice": { "default": "2d6" },
  "attributes": [ { "key": "SKILL", "label": "…", "gen": "1d6+6", "min": 1, "max": 12 } ],
  "resources":  [ { "key": "STAMINA", "from": "STAMINA", "trackMax": true, "min": 0 },
                  { "key": "provisions", "default": 4, "min": 0 } ],
  "sheetTemplate": { "attributes": [ … ], "resources": [ … ], "inventory": true },
  "resolutionRules": [ <resolution rule> ]
}
```

**Resolution rule** — the §2.5 abstraction:
```jsonc
{
  "id": "test", "label": "…", "dice": "2d6",
  "operands": [ { "type": …, "ref": …, "role": "target"|"modifier", "transform": … } ],
  "compare": "roll-under" | "meet-or-beat" | "threshold-bands",
  "crit": { "mode": "doubles"|"natural"|"none", … },
  "bands": [ { "id": …, "when": "success"|"fail"|"critSuccess"|"critFail", "label": … }
             /* or range bands: */ { "id": …, "min": 7, "max": 9, "label": … } ],
  "postEffects": [ <effect> ]     // applied after every resolution (e.g. LUCK attrition)
}
```
Operand `type ∈ {attribute, attributeArg, resource, var, param, const}`,
`role ∈ {target, modifier}`, `transform ∈ {none, abilityMod, negate}`.

## How the three families are ONE engine

The `compare` mode + `bands` + `crit` are the only knobs that differ:

| Family | `dice` | operands | `compare` | `crit` | `bands` |
|--------|--------|----------|-----------|--------|---------|
| **ff-2d6** (proven) | `2d6` | attribute(SKILL/…) as **target** | `roll-under` (total ≤ target) | `doubles` (1-1 win, 6-6 fail) | `success` / `failure` |
| **srd-d20** (fixture) | `1d20` | ability-mod as **modifier** + DC as **target** (`param`) | `meet-or-beat` (total ≥ target) | `natural` (nat-1 fail, nat-20 win) | crit/plain success/failure |
| **pbta** (fixture) | `2d6` | stat as **modifier** (no target) | `threshold-bands` | — | `miss` (≤6) / `partial` (7–9) / `full` (≥10) |

Adding `srd-d20` and `pbta` as **full** builtins in P2 is therefore *pure data* —
no engine change. The Ruleset Builder is a form/JSON editor over exactly this
`ruleset.json` shape (clone a builtin, edit attributes/resolution/sheet, import a
user system and map it in).

## Validate (Godot 4.6.1)

```bash
GODOT="C:/godot/Godot_v4.6.1-stable_win64_console.exe"
PROJ="skills/if-engine/test_project"

# Editor import (parse check — 0 script errors):
"$GODOT" --headless --path "$PROJ" --import

# Headless self-test (plays the scenario, prints one DEBUG line, quits):
"$GODOT" --headless --path "$PROJ" res://addons/nox_if_engine/probe/if_probe.tscn
```

The probe proves, in one deterministic process: passage traversal, a resolved
check that branches to an ending both ways (a found victory seed + defeat seed),
effects (var/item/attr + the LUCK-attrition postEffect), the item gate (open with
the key, closed without), an ending reached, and the resolver expressing the
d20 + PbtA families — with a `fails=0` summary.

## Reusing the addon

`test_project/` is a minimal Godot project that carries a copy of this addon under
`addons/nox_if_engine/` and is the runnable proof. To use the engine elsewhere,
copy `addons/nox_if_engine/` into any Godot 4 project — no autoloads required (the
classes are `class_name`-registered). When wired into a live template, `IFState`
becomes the autoload seam a DM/multiplayer layer intercepts, exactly as
`SessionState` does for `nox_netcode`.
