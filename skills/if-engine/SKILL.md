---
name: if-engine
description: |
  The computed interactive-fiction / gamebook engine core for Godot 4 (spec
  phases P0 + P1) — a pure, seedable, headless-tested engine that plays a
  data-driven narrative graph (passages/choices/conditions/effects) over a
  GENERIC rule engine where a ruleset is DATA, not code. Use when a template
  needs deterministic text-RPG / gamebook resolution with NO LLM and NO
  networking: attribute/dice checks, item gates, variable & flag effects,
  branching to endings — and now (P1) reusable MODULES, one-off AND campaign
  adventures, save/load with separated short-term (session) + long-term
  (campaign/world/character) stores, and DUAL-TIER characters (a lightweight
  persistent sheet OR a consume-only binding to a full companion_ai_core entity).
  Ships the reusable `nox_if_engine` addon + the proven `ff-2d6` ruleset as data
  (2d6 roll-under SKILL/STAMINA/LUCK, reusing the ff-gamebook dice mechanic) +
  `srd-d20` and `pbta` family fixtures proving the same engine expresses d20-vs-DC
  and PbtA threshold bands. Extends ff-gamebook SessionState + the VN
  runtime-variables/inventory model + the companion-interchange projection. Full
  design: Noxdev-Studio/docs/GAMEBOOK_ENGINE_SPEC_2026-07.md (§2, §2.5, P0+P1).
---

# if-engine — the computed IF / gamebook core (P0)

The deterministic foundation the whole gamebook expansion layers onto:
**computed-core first, AI as a layer.** Every mechanic runs without an LLM and
without networking — a classic text-RPG driven by branching narrative graphs,
rule tables, dice and condition/effect logic. AI (P4) and multiplayer (P5) are
enhancement layers *over* this core, never dependencies of it.

> **Status: P0 + P1 implemented + headless-proven (Godot 4.6.1).** The
> `nox_if_engine` addon ships under `skills/if-engine/addon/nox_if_engine/`.
> **P0:** plays the sample scenario `thornwood-crypt` end-to-end under the
> `ff-2d6` ruleset, deterministically; the generic resolver also expresses the
> `srd-d20` (meet-or-beat) and `pbta` (threshold-band) families as pure data.
> **P1:** adds reusable **modules**, **one-off** and **campaign** adventures
> (separate flows, shared engine), save/load with separated **short-term**
> (session) and **long-term** (campaign/world/character) stores, and **dual-tier
> characters** (a lightweight persistent sheet, or a consume-only binding to a
> full `companion_ai_core` entity via its interchange projection). Validated
> headless: editor import clean (0 script errors), P0 self-probe `fails=0`, P1
> self-probe `fails=0` and byte-identical across runs. Full `srd-d20`/`pbta`
> builtins + a Ruleset Builder (P2), worldbuilder (P3), AI (P4), multiplayer
> (P5) follow. Design: `Noxdev-Studio/docs/GAMEBOOK_ENGINE_SPEC_2026-07.md`.

## TL;DR

```bash
GODOT="C:/godot/Godot_v4.6.1-stable_win64_console.exe"
PROJ="skills/if-engine/test_project"     # minimal project carrying the addon

# Editor import (parse check — 0 script errors):
"$GODOT" --headless --path "$PROJ" --import

# P0 self-test (plays the scenario, prints ONE DEBUG line, quits):
"$GODOT" --headless --path "$PROJ" res://addons/nox_if_engine/probe/if_probe.tscn
# => DEBUG: if-engine probe — ruleset=ff-2d6 scenario=thornwood-crypt … fails=0 … => OK

# P1 self-test (one-off + campaign + save/resume + dual-tier characters):
"$GODOT" --headless --path "$PROJ" res://addons/nox_if_engine/probe/if_p1_probe.tscn
# => DEBUG: if-engine-p1 — oneoff=victory campaign=crown-of-embers modules=2 … fails=0 … => OK
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

## P1 — modules, adventures, persistence, dual-tier characters

P1 layers four things ONTO the P0 engine (it does not fork it): a **module**
format, **separate** one-off vs campaign adventures, **short/long-term
persistence**, and **dual-tier characters**. Everything stays deterministic,
headless, NO LLM, NO networking.

### Module — `module.json` (`if_module.gd`)

A module is the reusable content unit: a P0 narrative graph PLUS an entry/exit
contract that lets modules compose. A P0 scenario is a single module's content.

```jsonc
{
  "id", "name", "version", "kind":"module", "ruleset":"ff-2d6",
  "slots": [ { "id":"knight", "role":"protagonist", "tier":"sheet", "required":true } ],
  "entry": { "start":"<passage>", "onEntry":[<effect>], "requires":[<condition>] },
  "exit":  { "endings": { "<endingId|kind>": <exitRule> }, "default": <exitRule> },
  "scenario": { <IFScenario shape: passages/choices/checks/… > }
}
// exitRule = { "outcome":"complete"|"fail", "effects":[<effect>], "goto":"<moduleId>" }
```

- **entry** — how it begins: `start` passage (overrides the scenario's), optional
  `onEntry` effects applied to the seeded session, and `requires` conditions
  checked against the **carried long-term state** (a campaign gate — "only if
  `world.vault_opened >= 1`").
- **exit** — how it ends: maps the reached ending (by ending id, then kind, then
  `default`) to a campaign OUTCOME + effects on the carried state + an optional
  `goto` to the next module. This is the seam that links modules; the narrative
  graph itself never knows about "next module".

### Adventures — SEPARATE one-off vs campaign (Jesus's resolved decision)

Two **distinct object shapes + distinct runner entry points**, sharing the P0
engine underneath. The up-front split keeps the quick front door and the
long-running surface from entangling.

| | **one-off** (`if_oneoff.gd` + `IFOneOffRunner`) | **campaign** (`if_campaign.gd` + `IFCampaignRunner`) |
|---|---|---|
| Shape | `adventure.json` `type:"oneoff"` | `campaign.json` `type:"campaign"` |
| Content | ONE module + a seed + one optional character | ORDERED, linked modules + a carried roster |
| State | none beyond the session | a long-term store (world vars/flags + roster + progress) |
| Progression | play to an ending, done | finish module 1 → module 2 → … (per `next.onComplete`/order) |
| Persistence | short-term only | short-term **and** long-term (save/resume) |

```jsonc
// one-off:  { id, name, type:"oneoff", ruleset, seed, moduleRef|module, characterRef|character? }
// campaign: { id, name, type:"campaign", ruleset, seed,
//             campaignVars:{ "world.embers":0 }, campaignFlags:{},
//             roster:[ { slot, characterRef|character } ],
//             start:"<moduleId>",
//             modules:[ { moduleId, order, protagonist:"<slot>", moduleRef|module, next:{onComplete} } ] }
```

### Persistence — short-term vs long-term (`if_savegame.gd`, `if_campaign_store.gd`)

The save contract has **two clearly-labelled halves** so scene state can never
silently leak into the durable record:

```jsonc
// campaign_save.json
{
  "saveVersion":1, "saveKind":"campaign"|"oneoff", "savedAt":"",
  "longTerm":  { <IFCampaignStore.save_data(): progress, campaignVars/Flags, roster[], masterSeed> } | null,
  "shortTerm": { "moduleId", "seed", "dice_state", "state":{ <IFState.save_data()> } } | null
}
```

- **short-term** = the live play session (current passage, session vars/items/
  flags, sheet, dice position) — the P0 `runner.snapshot()`. Present only while a
  module is in progress (a mid-module save); **null between modules**.
- **long-term** = campaign progress + world/campaign vars & flags + the carried
  roster (each character's persistent sheet, inventory, history).

**Namespace convention (the mechanism):** during a module the world vars are
layered onto the session as `world.*`, the protagonist's carried vars as `char.*`
and inventory as `item.*`, so the ordinary condition/effect vocabulary reads and
writes them. At module end **only** those namespaced keys are captured back
(`world.*` → campaign store, `char.*`/`item.*` + the sheet → the character);
every other session var was **scene-scoped short-term** and is dropped. `save()`
serialises both halves; `resume(save, campaign, ruleset)` restores long-term
always and, if a session was live, rehydrates it **byte-for-byte** via the new
`IFRunner.restore()`. Content (modules/scenarios/rulesets) is NOT in the save —
resume is handed the campaign definition again.

### Dual-tier characters — `character.json` (`if_character.gd`)

One interface, two tiers. Either way the engine treats it as "a character in a
slot": `to_slot_sheet()` yields the `{attributes,resources,resource_max}` the
runner injects; `capture_from()` reads the played state back into the character's
long-term record so it carries into the next module.

```jsonc
{
  "id", "name", "tier":"sheet"|"companion", "ruleset":"ff-2d6",
  // persistent long-term state (BOTH tiers, mutated across modules):
  "sheet": { "attributes":{…}, "resources":{…}, "resource_max":{…} },
  "vars":  { "char.valor":2 }, "items": { "oath_ring":1 }, "flags":{}, "history":[],
  // tier "companion" ONLY — the immutable, consume-only binding:
  "companion": {
    "ref":"cmp_9f3ab2e07d41",                        // stable companion id (interchange identity.id)
    "interchange": { <companion-interchange v1 doc> }, // read-only projection
    "derive": { "attributes":{ "<ATTR>": { base, terms:[{path,weight,map?}], round, min, max } },
                "resources":{ "<RES>": {"from":"<ATTR>"}|{"const":n} } }
  }
}
```

- **tier "sheet"** — a lightweight persistent PC/NPC: its own ruleset sheet +
  carried vars/inventory + cross-module history. Hand-authored or rolled.
- **tier "companion"** — a character that IS a full `companion_ai_core` entity,
  bound **consume-only** by a stable id + a **companion-interchange v1**
  projection (see `skills/companion-npcs`). On first slot use its ruleset sheet
  is DERIVED from the interchange by the declared `derive` formula
  (`if_companion_projection.gd`: a deterministic path-resolver over the
  interchange with array aggregates `#max:`/`#avg:`/… and categorical `map`s);
  thereafter it persists its mutated sheet exactly like a sheet character. The
  engine **never imports or edits `companion_ai_core`** — it reads the projection
  data only, honouring the golden rules.

## Files

| File | Role |
|------|------|
| `addon/nox_if_engine/if_dice.gd` | Seedable `NdM+K` roller — faces + total. |
| `addon/nox_if_engine/if_ruleset.gd` | Typed ruleset reader + sheet generation. |
| `addon/nox_if_engine/if_state.gd` | Runtime state + condition/effect interpreters + `persistent` save. |
| `addon/nox_if_engine/if_resolver.gd` | **The generic rule engine (§2.5).** |
| `addon/nox_if_engine/if_scenario.gd` | Shared narrative-graph model + `validate()`. |
| `addon/nox_if_engine/if_runner.gd` | Deterministic play orchestrator (P1: `+sheet_in` inject, `+restore()`). |
| `addon/nox_if_engine/if_module.gd` | **P1** module reader — scenario + entry/exit contract. |
| `addon/nox_if_engine/if_character.gd` | **P1** dual-tier character (sheet ∥ companion-bound). |
| `addon/nox_if_engine/if_companion_projection.gd` | **P1** consume-only interchange → ruleset-sheet projection. |
| `addon/nox_if_engine/if_oneoff.gd` | **P1** one-off adventure object. |
| `addon/nox_if_engine/if_oneoff_runner.gd` | **P1** one-off entry point (thin). |
| `addon/nox_if_engine/if_campaign.gd` | **P1** campaign object — ordered/linked modules + roster. |
| `addon/nox_if_engine/if_campaign_store.gd` | **P1** long-term store (progress, world vars/flags, roster). |
| `addon/nox_if_engine/if_campaign_runner.gd` | **P1** campaign entry point — start/play/capture/advance + save/resume. |
| `addon/nox_if_engine/if_savegame.gd` | **P1** save contract (short+long halves) + canonical JSON + SHA-256. |
| `addon/nox_if_engine/data/rulesets/*.json` | `ff-2d6` (proven) + `srd-d20`, `pbta` (fixtures). |
| `addon/nox_if_engine/data/scenarios/thornwood-crypt.json` | Sample P0 scenario. |
| `addon/nox_if_engine/data/modules/*.json` | **P1** sample modules (`whispering-vault`, `sunken-market`, `goblin-toll`). |
| `addon/nox_if_engine/data/characters/*.json` | **P1** `sir-alden` (sheet) + `naomi-companion` (companion-bound). |
| `addon/nox_if_engine/data/campaigns/*.json` | **P1** `crown-of-embers` sample campaign. |
| `addon/nox_if_engine/data/adventures/*.json` | **P1** `goblin-toll` sample one-off. |
| `addon/nox_if_engine/probe/if_probe.*` | P0 headless self-test. |
| `addon/nox_if_engine/probe/if_p1_probe.*` | **P1** headless self-test. |
| `test_project/` | Minimal Godot project carrying the addon — the runnable proof. |

## Validation

Two gates, both headless + CI-friendly:

1. **Import clean** — `Godot --headless --path <test_project> --import`: zero parse
   / script errors across the addon.
2. **P0 self-probe** — `res://addons/nox_if_engine/probe/if_probe.tscn`: one
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

3. **P1 self-probe** — `res://addons/nox_if_engine/probe/if_p1_probe.tscn`: one
   deterministic process prints one line, e.g.
   `DEBUG: if-engine-p1 — oneoff=victory campaign=crown-of-embers modules=2 save_sha=8ab4b42c43fc2b87 … fails=0 … => OK`.
   It proves: **(a)** a **one-off** module played straight to an ending; **(b)** a
   **campaign** — begin, play module 1 on a **sheet** character, **save between
   modules** (short-term null, long-term populated), **resume** from that save,
   and carry BOTH tiers into module 2 — the sheet character's mutated STAMINA /
   inventory / history persist in the roster, and the **companion-bound**
   character's ff-2d6 sheet is **derived** from its interchange (`SKILL 11 /
   STAMINA 19 / LUCK 7`) and drives module 2 behind a `requires` gate on carried
   `world.*` state; **(c)** **short vs long separation** — a scene-scoped session
   var (`vault_torch_lit`) is dropped on capture and never reaches long-term or
   the next module; **(d)** **byte-identical determinism** — a mid-module save
   resumed into a fresh runner reaches a SHA-256-identical long-term save as the
   uninterrupted run.

Determinism: a fixed seed replays byte-for-byte (the roller owns one seeded RNG;
a resumed session restores the exact RNG position via `IFRunner.restore()`; the
sheet is a fixed override, an injected character sheet, or seeded `gen`). P1 saves
serialise as canonical sort-keyed JSON and hash with SHA-256, so the whole
campaign save is provably identical across runs (verified: two runs print the same
`save_sha`).

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
