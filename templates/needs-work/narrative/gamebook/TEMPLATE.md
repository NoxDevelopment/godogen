# Gamebook Template

Solo pen-and-paper RPG base (Fighting-Fantasy-like) on **Dialogue Manager 3**
plus a 2d6 dice layer and an adventure sheet. Scaffold with:

```bash
python templates/tools/scaffold.py gamebook <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable).
Kit pin: `nathanhoad/godot_dialogue_manager` **v3.10.4 @ `5487c524`** (MIT) —
the same pin as the visual-novel template, so both templates track DM
together.

## What you get

- **Keyed passages** (`dialogue/book.dialogue`): Dialogue Manager titles as
  numbered passages (`~ passage_1` ... `~ passage_7`), choices written the
  gamebook way ("turn to N" → `=> passage_N`). The 6-passage starter
  adventure *The Toll Bridge* demonstrates every mechanic: a passage jump, an
  **item-gated choice** (`[if Sheet.has_item("brass key")]`), a **SKILL test**
  with STAMINA damage and a bounce-back passage on failure, and a **LUCK
  test**.
- **Adventure sheet** (`scripts/character_sheet.gd`, autoload `Sheet`):
  SKILL 1d6+6, STAMINA 2d6+12, LUCK 1d6+6 rolled per run
  (`roll_new_character()`, seedable), provisions (eat = +4 STAMINA), and an
  **inventory LIST** (`add_item`/`has_item`/`remove_item`) mutated directly
  from dialogue. `died` fires when STAMINA hits 0 — gamebook rules are
  unforgiving; the story scene returns to the title.
- **Dice layer** (`scripts/dice.gd`, autoload `Dice`): 2d6 **roll-under**
  tests (`total <= stat`; snake eyes always succeed, double six always
  fails), `Dice.test("skill")` awaited as a DM mutation with the tumbling
  dice popup, `Dice.test_luck()` with the classic LUCK attrition (−1 LUCK per
  test, win or lose), `roll_test()` for popup-free logic, seedable RNG. Same
  architecture as the visual-novel SkillCheck, re-rules'd from
  d20+modifier-vs-DC to 2d6 roll-under.
- **Scenes**: title screen (Begin rolls a fresh sheet), story scene with a
  live sheet panel (stats + inventory, signal-driven) and a blockout stage
  (river/bridge/troll placeholders), the reusable VN textbox (name plate,
  typewriter, response menu), and the 2d6 dice popup.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"game_manager"` +
  `"persistent"` groups (GameManager, Sheet, and Dice all persist),
  `save_data()/load_data()` contracts, `"scalable_text"` labels, `pause`
  action declared.

## Passage conventions (the part worth understanding)

One DM title = one numbered passage; the number leads the narration line
("1 — The Toll Bridge...") so play reads like the book. All state lives in
`Sheet` (stats/inventory) and `GameManager.flags` (world events) — never in
the dialogue file — so saves capture everything via the `persistent` group.
Choices that require an item use DM's conditional responses; consequences use
mutations (`do Sheet.take_damage(2)`). Failed tests bounce to a retry passage
rather than dead-ending, the standard FF loop.

## How to extend

1. **Write passages**: append `~ passage_N` titles to `book.dialogue`. Keep
   the "turn to N" flavor in choice text; DM handles the actual jump.
2. **Combat**: FF battle rounds are two opposed 2d6+SKILL rolls — add
   `Dice.battle_round(enemy_skill)` next to `test()` and loop it from a
   passage mutation.
3. **More stats**: add fields to `character_sheet.gd` and cases to
   `get_stat()` — dialogue tests them by name with zero further code.
4. **Illustrations**: per-passage art replaces the Stage polygons; swap on
   passage entry by listening to `DialogueManager.got_dialogue`.
5. **Saves/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged.

## Validation status

`status: "validated"` — scaffolded (DM vendored at the pin, plugin enabled
after bootstrap import), `--headless --import` exit 0 with zero errors,
120-frame headless boot exit 0 with zero script errors. Boot probe:

```
DEBUG: gamebook core loop ready — passage_jump=true (1: "1 — The Toll Bridge. A r" / 7: "7 — The east bank. Behin") skill_test(2d6=2 vs SKILL 9 -> true) item_pickup=true sheet=[SKILL 9, STAMINA 19, LUCK 7] inventory=["brass key"]
```

(passage_1 and the jump target both compiled and yielded lines; the 2d6
roll-under test rolled against the sheet; the item pickup landed in the
inventory LIST. LUCK reads 7 because the probe's rolls landed a 7 for that
character.) The only exit-time log lines are the same benign
ObjectDB/resource shutdown notices the validated visual-novel template
produces — a Dialogue Manager teardown artifact on instant-quit runs, not a
script error.
