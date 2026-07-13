# FF Gamebook Template (illustrated Fighting-Fantasy book)

Illustrated Fighting-Fantasy gamebook — the **gamebook** template's
presentation evolution (Veritas Tales / classic FF book-plate look). Same
foundations underneath (Dialogue Manager 3 keyed passages, the adventure
sheet, the 2d6 roll-under dice layer), but every passage is now an
**illustrated page**: large illustration plate on top, passage text beneath
it, "turn to N" choice buttons under the text, the adventure-sheet bar along
the bottom, and the dice tray rolling over the page for tests. Two NEW core
systems ride on top: the **asset-binding manifest** (`assets.manifest.json` —
the contract with the Studio asset board) and the **SessionState** autoload
(single-player core, multiplayer-ready architecture). Scaffold with:

```bash
python templates/tools/scaffold.py ff-gamebook <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable).
Kit pin: `nathanhoad/godot_dialogue_manager` **v3.10.4 @ `5487c524`** (MIT) —
the same pin as the gamebook and visual-novel templates, so all three track
DM together.

## What you get

- **The illustrated page** (`scenes/book.tscn` + `scripts/book.gd`): one
  scene IS the whole book. A page panel (its background art is the
  `ui/page_frame` manifest slot) stacks the illustration plate, a name plate,
  the typewriter DialogueLabel, and the response buttons in the page flow —
  no bottom textbox overlay. The sheet bar (SKILL/STAMINA/LUCK/provisions +
  inventory, signal-driven) runs along the bottom; a page-turn SFX plays on
  passage entry once the `audio/page_turn` slot is filled.
- **The illustration plate** (`scenes/illustration_plate.tscn`):
  `bind_passage("passage_N")` binds the manifest slot
  `illustration/passage_N` — real art when the slot's `file` is set, else a
  deterministic ColorRect placeholder tint + a caption naming the slot and
  its style pack. The page rebinds it on every `SessionState.passage_changed`.
- **Asset binding** (`assets.manifest.json` + `scripts/asset_binder.gd`,
  autoload `AssetBinder`): scene code never hardcodes asset paths — it asks
  the binder by slot id. Ships 9 slots: one per passage plate (6), UI chrome
  (`ui/page_frame`, `ui/dice_tray`) and `audio/page_turn`. Schema below.
- **SessionState** (`scripts/session_state.gd`, autoload): the single routing
  point for passage flow, choices and dice — `advance_passage()` (the first
  mutation of every passage), `choose()` (the response buttons' route),
  `roll()`/`roll_luck()` (awaits the dice layer, records into `roll_log`),
  plus `passage_history`, signals for every transition, and the DM-seat
  no-op hooks. Documented as the future ENet sync point (below).
- **Keyed passages** (`dialogue/book.dialogue`): DM titles as numbered
  passages, choices written the gamebook way ("turn to N"). The 6-passage
  starter *The Toll Bridge* demonstrates every mechanic: a passage jump, an
  item-gated choice, a SKILL test with STAMINA damage and a bounce-back
  passage on failure, and a LUCK test. Every passage opens with
  `do SessionState.advance_passage("passage_N")` — that line is what drives
  the plate, the history and (later) the network.
- **Adventure sheet** (`scripts/character_sheet.gd`, autoload `Sheet`) and
  **dice layer** (`scripts/dice.gd`, autoload `Dice`): unchanged FF rules
  from the gamebook template — SKILL 1d6+6 / STAMINA 2d6+12 / LUCK 1d6+6 per
  run, inventory LIST, 2d6 roll-under (snake eyes always succeed, double six
  always fails), LUCK attrition, seedable RNG. New: `Dice.show_popup`
  resolves tests without the tray (probe/headless, later the replay path),
  and dialogue now routes tests as `do SessionState.roll("skill")`.
- **The dice tray** (`scenes/dice_roll_popup.tscn`): the 2d6 tumble/verdict
  popup, restyled as a tray whose panel art is the `ui/dice_tray` slot.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"game_manager"` +
  `"persistent"` groups (GameManager, Sheet, Dice and SessionState all
  persist), `save_data()/load_data()` contracts, `"scalable_text"` labels,
  `pause` action declared.

## Asset binding (the part worth understanding)

`assets.manifest.json` (project root) is the contract between the game and
the Studio asset board. Every art/audio surface is a named **slot**; the
manifest records per slot HOW it gets filled and WHAT currently fills it.
The game only ever reads it (via `AssetBinder`); the board owns writing it.

Top level: `{ "schemaVersion": 1, "stylePack": "veritas-ink", "slots": [...] }`

Each slot:

| Field | Meaning |
|-------|---------|
| `slotId` | Stable id, namespaced by surface: `illustration/passage_N`, `ui/page_frame`, `ui/dice_tray`, `audio/page_turn`. |
| `kind` | `"illustration"` \| `"ui"` \| `"audio"`. |
| `policy` | `"rule"` = prompt templated from passage content at generation time (the plates); `"generated"` = one-off generation from a fixed prompt (UI chrome); `"static"` = hand-authored, the board never regenerates it (page-turn SFX). |
| `workflowId` | Generation workflow to run, e.g. `"zit-txt2img"`. `null` for static slots. |
| `stylePack` | Style pack for generation (`"veritas-ink"`: hand-drawn traditional ink linework + muted watercolor, 1980s FF book plates). Falls back to the manifest root value. |
| `promptTemplate` | The generation prompt. Rule slots template it: `{passage_summary}` is filled from the slot's `source.summary` (or re-derived from the passage text). |
| `source` | Rule slots only: where the content lives — `{dialogue, passage, summary}` — so the board can re-derive prompts when passages change. |
| `file` | Current asset path (`res://...`). **`null` = not generated yet** → callers show the slot's ColorRect placeholder. |
| `provenance` | `{seed, params, generatedAt}` — written by the board with the file, so every plate is reproducible. |
| `placeholderColor` | Optional `#rrggbb` placeholder tint; slots without it get a deterministic muted tone hashed from the slot id. |

Runtime flow: `AssetBinder` parses the manifest at boot (`reload()` re-reads
it after the board rewrites it); `get_texture(slot_id)` returns the bound
texture or `null` while unfilled (with a load-from-disk fallback for files
dropped in after the last editor import); `placeholder_color(slot_id)` tints
the placeholder. The plate, the page frame and the dice tray all follow the
same pattern — **to adopt generated art there are zero code changes**: the
board writes the file + provenance into the slot and the next boot binds it.
When you add a passage, add its `illustration/passage_N` slot with a
`source.summary`; when you export, make sure `assets.manifest.json` ships
(add `*.manifest.json` to the export include filters if you change presets).

## Multiplayer (opt-in — the netcode drop-in now exists)

All passage state, dice results and party flow route through **one**
autoload with a clean interface: `SessionState.advance_passage()`,
`choose()`, `roll()`/`roll_luck()`. Scenes react to its signals
(`passage_changed`, `choice_made`, `roll_resolved`) and never own story
state. That makes SessionState the sync point, and the **`netcode` godogen
skill** (`skills/netcode`, profile `authority-turn`) turns it into real
multiplayer **without touching a single scene**:

```bash
python skills/netcode/tools/netcode_gen.py inject \
    --project <this-project> --profile authority-turn --transport enet
```

This copies the reusable **`nox_netcode`** addon into `addons/`, registers
the `Net` (session/lobby/transport/authority) and `NetBridge`
(SessionState bridge + DM seat) autoloads, writes a `[nox_netcode]` settings
block, and applies a **pinned guard patch** to `scripts/session_state.gd`:
`advance_passage`/`choose`/`roll` route through the **host** (host validates +
broadcasts; clients render off the same three signals), and the two DM-seat
no-op hooks flip from `return false` to **real host-side implementations** —
`dm_push_passage(id)` (force the party's book, `require_dm`) and
`dm_override_roll(result)` (fudge a roll, `require_dm`). The host rolls with a
broadcast shared seed so dice replay identically on every peer; party choices
resolve via `leader` / `vote` / `dm-confirm` arbitration.

Everything is **opt-in and non-destructive**: the guard is inert when
`Net.active` is false, so single-player play is byte-identical (the boot probe
above is unchanged after injection). Transport is **ENet for LAN** by default;
switch `--transport websocket` for one desktop **and** web code path (spec
Phase 3), or see the addon README for the WebRTC-for-web note (Phase 5). Play
together by running `res://addons/nox_netcode/lobby.tscn` in two instances —
host in one, join `127.0.0.1` in the other (`addons/nox_netcode/README.md` has
the full two-instance and LAN/web steps). Full design:
`Noxdev-Studio/docs/specs/MULTIPLAYER_TEMPLATE_SPEC.md`.

## How to extend

1. **Write passages**: append `~ passage_N` titles to `book.dialogue`,
   starting each with `do SessionState.advance_passage("passage_N")`, and
   add the matching `illustration/passage_N` manifest slot (+ summary).
2. **Combat**: FF battle rounds are two opposed 2d6+SKILL rolls — add
   `battle_round(enemy_skill)` to `dice.gd`, wrap it in a
   `SessionState.battle()` that logs to `roll_log`, and loop it from a
   passage mutation.
3. **More stats**: add fields to `character_sheet.gd` and cases to
   `get_stat()` — dialogue tests them by name with zero further code.
4. **More art surfaces**: new slot in the manifest + a `bind_slot()` /
   `get_texture()` call at the surface — never a hardcoded path.
5. **Saves/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged — everything stateful is already in
   the `persistent` group.

## Validation status

`status: "validated"` — scaffolded twice (DM vendored at the pin, plugin
enabled after bootstrap import), `--headless --import` exit 0 with zero
errors, 120-frame headless boot exit 0 with zero script errors, probe
byte-identical across 5 boots on the 2 fresh scaffolds (the probe seeds the
sheet and dice, so its line is fully deterministic; play re-randomizes
afterwards). The real-art path was validated both ways: a PNG bound via
`file` resolves through the load-from-disk fallback before an editor import
and through ResourceLoader after one (`plate=illustration/passage_1(art)`).
Boot probe:

```
DEBUG: ff-gamebook core loop ready — manifest=9 slots (illustration=6 ui=2 audio=1) page_render=true plate=illustration/passage_1(placeholder) choice=passage_1->passage_2 skill_pass=(2d6=5 vs 7 -> true => passage_7) skill_fail=(2d6=9 vs 7 -> false, STAMINA 19->17 => passage_3) session=[passages=7 rolls=2 dm_noop=true]
```

(`manifest` = AssetBinder parsed all 9 slots with the right kind split;
`page_render`/`plate` = the real book scene opened passage 1, its opening
mutation routed through SessionState, and the plate bound its manifest slot
as a placeholder; `choice` = `SessionState.choose()` on passage 1's first
response advanced the session to passage 2; `skill_pass`/`skill_fail` = the
passage-5 SKILL test ran through the real dialogue mutation twice on scanned
seeds — the pass branch ghosted across to passage 7, the fail branch cost 2
STAMINA and bounced back to passage 3; `session` = the trail and roll log
recorded 7 passages / 2 rolls and both DM-seat hooks answered as documented
no-ops.) The only exit-time log lines are the same benign ObjectDB/resource
shutdown notices the validated gamebook and visual-novel templates produce —
a Dialogue Manager teardown artifact on instant-quit runs, not a script
error.
