# Visual Novel Template (with dice checks)

Visual-novel base on **Dialogue Manager 3** (nathanhoad) plus our pen-and-paper
dice layer (the roadmap's "Veritas Tales" row). Scaffold with:

```bash
python templates/tools/scaffold.py visual-novel <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable) with Dialogue Manager
**v3.10.4** (pinned tag + commit; the DM 3.x line requires Godot 4.4+).

## What you get

- **Dialogue Manager wired end to end**: the `DialogueManager` autoload, the
  editor plugin (dialogue editor dock + `.dialogue` importer), and one story
  file — `dialogue/intro.dialogue` — with a choice branch, a flag mutation
  (`do GameManager.set_flag(...)`), a **skill-check gate**, and three endings.
- **Dice layer**:
  - `SkillCheck` autoload (`scripts/skill_check.gd`): character sheet
    (`stats` dict: body/mind/finesse/presence), `roll(stat, dc)` pure d20 +
    modifier logic (nat 1 auto-fails, nat 20 auto-succeeds), seedable RNG
    (`set_seed()`), `last_result`/`last_success` for dialogue conditions, and
    the awaited `skill_check(stat, dc)` UI flow.
  - **Dice-roll popup** (`scenes/dice_roll_popup.tscn`): screen dimmer, d20
    tumble that eases out onto the rolled face, breakdown line
    (`d20 14 + MIND 2 = 16 vs DC 12`), color-coded verdict with crit variants,
    Continue button.
- **VN textbox** (`scenes/textbox.tscn` + `scripts/textbox.gd`): bottom panel
  with name plate + DM's typewriter `DialogueLabel`, centered response menu
  (DM's `DialogueResponsesMenu`), click / `ui_accept` to advance, `ui_cancel`
  or click-while-typing to skip, auto-hides during long mutations (the dice
  popup), frees itself and signals `dialogue_finished` at story end.
- **Title scene** (Begin/Quit) and **story scene** (blockout stage: vault door,
  cipher wheel, portrait placeholder) that spawns the textbox and returns to
  the title when the story ends.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"game_manager"` +
  `"persistent"` on `GameManager`, `"persistent"` on `SkillCheck` (the
  character sheet persists), `save_data()/load_data()` on both, `pause` input
  action, `"scalable_text"` on all labels.

## The skill-check gate (the part worth understanding)

Dialogue Manager awaits coroutine mutations, so the whole dice flow is two
lines of dialogue:

```
- Work the cipher (Mind, DC 12)
	do SkillCheck.skill_check("mind", 12)
	if SkillCheck.last_success
		=> cracked
	else
		=> jammed
```

`skill_check()` rolls, shows the popup, and only returns when the player
confirms — the story pauses on the `do` line. The result lands in
`SkillCheck.last_success` / `last_result` for the `if` that follows.
Autoloads are addressable by name in dialogue (`GameManager.set_flag(...)`
works the same way); add autoload names to Dialogue Manager's *State Autoload
Shortcuts* project setting to drop the prefix.

## Play a Studio-authored VN (Immersion Engine)

Besides the hand-written `.dialogue` demo, this template ships a **JSON runtime**
that plays a visual novel exported from the NoxDev **Studio VN Maker**
(`/p/<slug>/vn-maker` → *Export Godot*, which writes `res://vn/story.vn.json`,
format `noxdev-vn`):

- `scripts/vn_runtime.gd` (`class_name VnRuntime`) — the pure Godot mirror of the
  Studio helpers: `canonical_emotion()`, `resolve_sprite()` (the emotion
  **portrait swap**: exact key → canonical emotion → neutral/default → first),
  and `voice_instruction()` (base voiceStyle + per-emotion delivery).
- `scenes/vn_player.tscn` + `scripts/vn_player.gd` — a self-contained runtime
  (UI built in code) that reads the exported story and drives background,
  portrait (swapped by each line's **expression**), dialogue, choices with flag
  gating (`sets`/`requires`), and fall-through `next`.
- **Voice (P2)**: each character carries `voice` / `voiceProvider` / `voiceStyle`;
  per line the runtime resolves the emotion delivery and hands it to `_speak()`
  (which logs `[VN voice] <name> | <provider>/<voice> | <instruction>` by
  default). Override `_speak()` to synthesize with your TTS of choice or play a
  pre-rendered clip — the fields are already parsed and resolved.
- **Wiring**: `story.gd` auto-detects `res://vn/story.vn.json`; when present it
  switches to `vn_player.tscn`, otherwise it runs the built-in dice demo. So a
  fresh scaffold shows the demo; a Studio export makes it play your story with
  zero code.

Headless-verified (Godot 4.6.1): the runtime parses a sample export, resolves
sprites/emotions/voice, renders the first line, gates + takes a flag-setting
choice, and navigates — all assertions green.

## How to extend

1. **Story**: add `.dialogue` files under `dialogue/` (DM's editor dock edits
   them); start any of them via `textbox.start(resource, "title")`. Chain
   scenes by swapping `story.gd`'s resource or reacting to flags.
2. **Stats and checks**: add entries to `SkillCheck.stats` — dialogue refers to
   stats by string, so `do SkillCheck.skill_check("lore", 14)` just works.
   Different dice systems live in `roll()` (2d6, percentile, advantage...).
3. **Portraits/backgrounds**: replace the Stage blockout polygons in
   `story.tscn`; pair with the `character-mime` skill for talking portraits.
   A portrait manager reacting to `dialogue_line.character` hooks cleanly into
   `textbox._apply_dialogue_line`.
4. **Textbox look**: everything is a plain Control tree — restyle with a
   `ui-theme` theme.tres. DM tags (`[wait]`, `[speed]`, `#tags`) already work.
5. **Saving/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged; story position saves as
   `{resource_path, title}` plus `GameManager.flags`.

## Validation status

`status: "validated"` — scaffolded (bootstrap import + deferred plugin
enable), `--headless --import` exit 0 with **zero errors and zero warnings**,
120-frame headless boot exit 0. Boot probe (compiled dialogue + live roll):

```
DEBUG: visual-novel core loop ready — first_line="Narrator: Rain hammers the archive district as you reach the sealed door of the Veritas Vault." skill_check(d20=13+2=15 vs DC 12 -> true)
```

The full gate was also driven headless (scratch harness): choosing "Work the
cipher" fired the mutation, the dice popup appeared and was awaited, and after
Continue the story took the matching branch — verified for **both** outcomes
(natural success run and a seeded failing roll landing on the alarm branch).
The only remaining log lines are engine shutdown accounting (ObjectDB /
resources-in-use notices from quitting while DM's dialogue cache holds
references; exit code 0, not script errors).

## Vendored addon notes

- License: MIT (`addons/dialogue_manager/LICENSE`, manifest in
  `addons/LICENSES.md`).
- Docs: https://github.com/nathanhoad/godot_dialogue_manager/tree/main/docs
  (syntax, conditions/mutations, custom balloons, C# usage).
- The `.dialogue` importer comes from the DM editor plugin — it is enabled by
  scaffold after the bootstrap import, so the first post-scaffold `--import`
  is what compiles `dialogue/intro.dialogue`.
- The plugin self-registers the `DialogueManager` autoload when enabled; the
  skeleton also bakes it into `project.godot` so headless runs work before the
  editor ever opens the project.
