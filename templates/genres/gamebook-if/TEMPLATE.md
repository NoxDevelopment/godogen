# Gamebook IF Template (playable computed if-engine gamebook)

The **playable** standard single-player gamebook, built on the computed **Nox
Loom if-engine** (`nox_if_engine`, spec P0–P2). This is the template that turns
the headless engine into an actual game: a data-driven text-RPG that plays
**100% without any AI or networking**. The engine is vendored in; this template
is the UI that drives it.

> **Computed core first, AI as an optional layer.** Every mechanic — passages,
> condition-gated choices, effects, dice resolution, endings, one-offs,
> campaigns, save/load — runs deterministically on the engine. The AI-DM seam
> (`AiDm`) ships **disabled and inert**; there is no LLM and no fake AI.

Scaffold with:

```bash
python templates/tools/scaffold.py gamebook-if <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No external addons are
cloned — the only addon is the **vendored** `nox_if_engine` (shipped inside the
skeleton, self-contained, MIT).

## What you get

- **The vendored engine** (`addons/nox_if_engine/`): the whole computed core,
  copied in verbatim (consume-only, **not modified**) — the seedable dice roller,
  the generic data-driven **resolver** (`compare` = roll-under / meet-or-beat /
  threshold-bands), the shared narrative-graph **scenario** model, **rulesets as
  data** (`ff-2d6`, `srd-d20`, `pbta`, `nox-2d10`), **modules**, **dual-tier
  characters**, the **one-off** and **campaign** runners, and two-half (short +
  long term) **save/load**. Its own probes (`if_probe`/`if_p1_probe`/
  `if_p2_probe`) still ship and still pass.
- **`PlaySession`** (`scripts/play_session.gd`, autoload): the **single bridge**
  between the UI and the engine — the if-engine analogue of ff-gamebook's
  `SessionState`. It owns the active runner (`IFOneOffRunner` **or**
  `IFCampaignRunner`), exposes `current_passage()`, `available_choices()` (already
  condition-gated by the engine), `sheet_view()` (built from the ruleset's
  `sheetTemplate`), `choose()` (returns a per-turn report with any dice rolls +
  the arrived passage + terminal/boundary status), and `save_game()`/
  `load_game()`. The scene talks only to this; it never touches a runner.
- **The play scene** (`scenes/play.tscn` + `scripts/play.gd`): the whole page —
  an **illustration plate** on top, the passage **title + text**, **choice
  buttons** built from the engine's gated choices (effects applied on choose),
  and an **adventure-sheet + inventory HUD** along the bottom. The **dice tray**
  (`scenes/dice_roll_popup.tscn`) rolls over the page for every resolved check,
  rendering the resolver's result **ruleset-agnostically** (2d6 roll-under, d20
  meet-or-beat, or PbtA threshold bands from the same fields).
- **One-off AND campaign** (both from the title screen): a **one-off** (the
  *Thornwood Crypt*, reusing the engine's `thornwood-crypt` scenario under
  `ff-2d6`) plays straight to an ending; a **campaign** (the *Crown of Embers*)
  runs linked modules with carried world state and **dual-tier characters** (a
  sheet knight, then a companion-derived artisan), with **save/resume between
  modules** via `IFSaveGame`.
- **AI OPTIONAL** (`scripts/ai_dm.gd`, autoload `AiDm`): the documented **inert**
  seam the future P4 AI-DM layer fills. `AiDm.enabled` is **false**; its hooks are
  pass-throughs; every `PlaySession` call site is guarded by `if AiDm.enabled`, so
  the computed game is **byte-identical with it off**. No LLM, no networking, no
  stub of a model call — just the seam, off.
- **Asset binding** (`assets.manifest.json` + `scripts/asset_binder.gd`, autoload
  `AssetBinder`): the same Studio-board contract as ff-gamebook. Passages need no
  manifest entry (the plate falls back to a **titled placeholder**); add an
  `illustration/<passageId>` slot only for passages you want illustrated.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `game_manager` +
  `persistent` groups (`GameManager` persists), `save_data()`/`load_data()`
  contracts, `scalable_text` labels, `pause` action.

## UI ↔ engine wiring (the part worth understanding)

The scene is a thin renderer over the engine. One turn:

```
render():  passage   = PlaySession.current_passage()       # {id,title,text,ending?}
           choices   = PlaySession.available_choices()     # engine-gated already
           sheet     = PlaySession.sheet_view()            # from ruleset sheetTemplate
           → draw the plate/title/text, a Button per choice, the sheet + inventory HUD

on a choice button:
           report = PlaySession.choose(choice_id)          # engine applies effects,
                                                            # auto-resolves entry checks,
                                                            # routes by outcome band
           for roll in report.rolls: await dice_tray(roll) # surface the resolver
           render()                                         # new passage / choices / sheet
           if report.ended → ending screen                 # one-off: title;
           elif report.between_modules → next-chapter       # campaign: advance module
```

`choose()` compares the state's `roll_log` length before/after the engine call to
surface the **0..N** checks that resolved that turn (a passage-entry check like the
crypt's dart-trap or guardian auto-resolves inside the engine). Gating is the
engine's: `available_choices()` returns only choices whose `conditions` hold, so
the iron-door `unlock` choice appears **only** while `item.iron_key >= 1`. The
sheet HUD is ruleset-agnostic: it walks `ruleset.sheetTemplate.attributes` +
`.resources` and the `item.*` inventory, so it renders an `ff-2d6` sheet, a
`srd-d20` sheet or a `pbta` sheet unchanged.

## One-off vs campaign + save/load

| | **One-off** | **Campaign** |
|---|---|---|
| Runner | `IFOneOffRunner` | `IFCampaignRunner` |
| Started by | title → `PlaySession.begin_oneoff_scenario(...)` | title → `PlaySession.begin_campaign_file(...)` |
| Content | one scenario (Thornwood Crypt, wrapped into a one-off in code — the shipped `thornwood-crypt.json` is reused, not copied) | linked modules + a carried roster (Crown of Embers) |
| Ends | an ending → return to title | a **module** ends → *continue to next chapter*; last module → campaign complete |
| Save | short-term session snapshot only | short-term **and** long-term store |

**Save/load** goes through `IFSaveGame`. `PlaySession.save_game()` writes the
engine save (long-term campaign store + short-term session snapshot) plus a small
**content descriptor** (which scenario/campaign it was taken against — content is
not stored in the engine save) to `user://`. `load_game()` rebuilds the content
from the descriptor and restores the engine state: a campaign `resume()`s both
halves; a one-off restores the inner runner **byte-for-byte** from its snapshot
(`IFRunner.restore()`), so a resumed run reaches the identical ending. All of this
uses only the engine's **public API** — the addon source is not modified.

## The AI-optional seam

`AiDm` is where a future AI Dungeon Master plugs in **without the computed core
depending on it**. As shipped:

- `AiDm.enabled == false` and stays false.
- `narrate_passage()` / `gloss_roll()` return `""`; `review_choices()` returns the
  choices unchanged; `dm_intervene()` returns `false`. All inert.
- Every `PlaySession` use is behind `if AiDm.enabled`, so with it off the flow is
  the pure computed engine — the boot probe plays the whole adventure to an ending
  with `AiDm` doing nothing.

There is deliberately **no LLM call and no fake AI** here. A real P4 layer would
implement these hooks to author flavour prose or gloss a roll, but it would still
route every mechanic (choices, conditions, effects, dice) through the computed
engine — the AI enhances, it never resolves.

## How to extend

1. **New adventures**: author scenarios (passages / choices / conditions /
   effects / check nodes) and modules/one-offs/campaigns as JSON in the engine's
   data shapes (see `addons/nox_if_engine/README.md` and the `if-engine` skill).
   Point `PlaySession.begin_oneoff_file()` / `begin_campaign_file()` at them.
2. **New system**: drop a `ruleset.json` (validate it with `IFRulesetValidator`)
   and the resolver, sheet HUD and dice tray reskin with zero code changes.
3. **Illustrated pages**: add an `illustration/<passageId>` slot to
   `assets.manifest.json`; the plate binds real art automatically.
4. **Saves/menus**: godotsmith `save_system` / `menu_system` / `settings_system`
   drop in unchanged — `GameManager` is already in the `persistent` group and the
   adventure save is a first-class `IFSaveGame` file.
5. **AI later**: implement the `AiDm` hooks and flip `enabled` — the seam is the
   only place that changes; the computed core is untouched.

## Validation status

`status: "validated"` — `--headless --import` exits 0 with **zero script errors**;
the main scene (`title.tscn`) boots clean; and the headless **boot probe**
(`res://scenes/boot_probe.tscn`) plays the sample one-off to its victory ending
through the engine, deterministically (byte-identical across runs), and also
exercises the campaign flow, save/load, the inert AI seam, and a clean boot of the
real play scene. Run it:

```bash
Godot --headless --path <project> res://scenes/boot_probe.tscn
```

Verbatim probe line (seed found deterministically; `win_seed=1`):

```
DEBUG: gamebook-if playable core — flow=oneoff+campaign scenario=thornwood-crypt ruleset=ff-2d6 win_seed=1 passage_render=true gated_choice=unlock@iron_door(open_with_key,closed_keyless) dice_check=(test 2d6=7.0 vs SKILL 9.0 -> true band=success) effect=(gold 0->15, torch granted, iron_key consumed) ending=treasure(victory) save_load=true campaign=crown-of-embers(complete) ai=disabled+inert play_scene=boots rolls=2 fails=0 victory_seed=ok passage_render=ok sheet_from_template=ok gated_choice=ok dice_check_resolved=ok effect_applied=ok ending_reached=ok save_load=ok campaign=ok ai_disabled=ok ai_inert=ok play_scene_boots=ok => OK
```

That single run proves, on the computed engine: the start **passage renders**
(both via `PlaySession` and in the real play scene, which boots and builds choice
buttons); the sheet HUD is built from the ruleset `sheetTemplate`; the iron-door
`unlock` **choice is gated** (offered with the key, proven closed on a keyless
state); a **dice check resolves** (the guardian SKILL test, `2d6=7 vs 9 → success`)
and surfaces as a tray roll; **effects apply** (gold 0→15, a torch granted, the
iron key consumed); the **victory ending** is reached; a mid-adventure
**save/load round-trips** to the identical ending; and the **campaign** plays
module 1 → boundary → module 2 → complete via `IFCampaignRunner` — all with the
**AI seam disabled and inert**.
