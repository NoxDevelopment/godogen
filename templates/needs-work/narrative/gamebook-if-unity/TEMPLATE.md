# Nox Loom Gamebook (Unity)

The Unity port of the **Nox Loom computed gamebook** — a Fighting-Fantasy-style
interactive-fiction reader whose rules are **data, not code**. It is a faithful C#
port of the Godot `gamebook-if` template's engine (`nox_if_engine`, spec phase
**P0**): a pure, seedable, deterministic engine that plays a narrative graph
(passages · choices · checks · effects) over a **generic rule engine** where a
ruleset is a JSON document. No LLM, no networking — the deterministic core the
rest of the gamebook expansion layers onto.

## What you get

- **The computed engine, in C#** under `Assets/Scripts/Engine/` — pure classes,
  no `MonoBehaviour`, so it is reusable from any script, test, or the play scene:
  - `IFDice` — seedable dice-expression roller (`NdM+K`) returning individual
    faces + total (over the deterministic `IfRng`, not Godot's RNG).
  - `IFRuleset` — typed reader over a ruleset JSON (attributes, resources, sheet
    template, dice defaults, resolution rules); generates a sheet from `gen` exprs.
  - `IFResolver` — **the generic rule engine (§2.5)**: interprets a resolution
    rule → an outcome band. Its `compare` mode + `bands` express every family.
  - `IFPortableCheck` — the P2 portability layer: compiles a system-agnostic
    portable check into a concrete resolver call, so one scenario runs under any
    system that declares a `portability` block.
  - `IFScenario` — the shared narrative-graph model (passages/choices/checks/
    effects) both authoring views target; structural `Validate()`.
  - `IFState` — the saveable runtime state (sheet + vars + flags + `item.*`
    inventory + roll log) with the condition + effect interpreters.
  - `IFRunner` — the deterministic play orchestrator (load → traverse → resolve
    → route, with a cycle guard), plus `Snapshot()`/`Restore()` for save/load.
- **The engine data**, copied verbatim from the Godot engine, under
  `Assets/StreamingAssets/nox_if_engine/data/` — the `ff-2d6`, `srd-d20`, `pbta`
  and `nox-2d10` rulesets and the `thornwood-crypt` + `portable-trial` scenarios.
  The C# engine reads the SAME JSON the Godot engine does.
- **A playable reader scene** — `Assets/Scripts/GamebookPlay.cs` drives the runner
  and renders each passage (title + body + a live SKILL/STAMINA/LUCK/GOLD HUD),
  building one button per available choice. Check passages auto-chain inside the
  engine, so the player only ever sees passages-with-choices or an ending.
- **A code-built scene** — `Assets/Editor/NoxBootstrap.cs` builds `Main.unity`
  from code (no hand-authored `.unity`), same discipline as the other Unity
  templates. `Assets/Scripts/GameManager.cs` is the NoxDev ABI singleton
  (world flags + JSON save via `ISaveable`, mirroring the Godot `save_data()`).

## Rules are data, not code

The whole point: `IFResolver` runs one generic algorithm; a **ruleset** decides
the maths. `ff-2d6` is roll-UNDER a stat; `srd-d20` is d20+mod MEET-OR-BEAT a DC;
`pbta` is 2d6+stat into miss/partial/full BANDS. A portable scenario names a
*semantic* + a *canonical attribute*, and each ruleset's `portability` block
compiles that into its own resolution rule — so the same story runs under any of
them (`portable-trial.json` is the fixture).

## How validation runs

Two headless batchmode passes (no editor UI):

```bash
# 1) compile everything + build the play scene (the registry validateMethod):
"<Unity.exe>" -batchmode -quit -nographics -projectPath . \
    -executeMethod NoxDev.Editor.NoxBootstrap.BuildDemoScene -logFile build.log

# 2) prove the engine plays correctly + deterministically:
"<Unity.exe>" -batchmode -quit -nographics -projectPath . \
    -executeMethod NoxDev.Editor.GamebookProbe.Run -logFile probe.log
```

`GamebookProbe` plays `thornwood-crypt` under `ff-2d6` end-to-end and asserts the
same invariants the Godot boot_probe does — passage render, effect application
(gold + item grant/consume), an item-gated choice **open AND closed**, dice-check
resolution, a victory ending, a save/restore round-trip, and **determinism** (same
seed → byte-identical run) — then prints one `DEBUG: gamebook-if-unity … fails=N …
=> OK` line and exits `0` (or `1` on any failure).

## ABI mapping (Godot template ABI → Unity)

| Godot | Unity |
|------|-------|
| `game_manager` autoload | `GameManager` singleton (`DontDestroyOnLoad`) |
| `save_data()` contract | `ISaveable.SaveData()/LoadData()` → one JSON blob |
| `SessionState` / `IFState` | `IFState` (engine) + `IFRunner.Snapshot()/Restore()` |
| `nox_if_engine` addon | `Assets/Scripts/Engine/*.cs` (pure C#) |
| ruleset/scenario `.json` | same files under `StreamingAssets/nox_if_engine/data` |

## Parity status

This is **P0 parity** with the Godot `gamebook-if` (the computed core: play a
scenario under a data-driven ruleset to an ending, deterministically, with
save/load). The **P1** campaign/module container, **P2** Ruleset Builder round-trip
against this engine, and the optional **P4 AI-DM** seam (narration/adjudication
that never changes the computed outcome) are the documented follow-on parity work;
they layer onto this same computed core, exactly as in the Godot lane.

Engine pin: Unity 6000.0 LTS. Requires `com.unity.nuget.newtonsoft-json` (in the
manifest) for the JSON ruleset/scenario reading.
