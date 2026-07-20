---
name: loading-continue
description: The presentation layer between the menu and gameplay — async loading screens (progress + rotating tips, no one-frame flash), a working "Continue" (resume the newest save, not start-a-new-game), and a save-slot picker (thumbnail + summary + timestamp) for Load and Save. Fills the gap where save-system stores slots but nothing shows them, and where the nox_ui Continue button silently starts a fresh game. Use when a template needs loading transitions, Continue, or a load/save screen.
---

# Loading & Continue — the menu→gameplay presentation layer

Async loading screens, a working Continue (resume newest save), and a save-slot
picker for Load/Save — the presentation layer between menu and gameplay. Two silent
parity holes this closes:

1. **`save-system` writes slots, but nothing presents them.** No load screen, no
   Continue, no visible loading transition. (Its own SKILL notes the slot-picker is
   "not provided by this skill yet.")
2. **The `ui-shell` Continue button is a stub in spirit** — `_on_continue_pressed()`
   calls `NoxShell.new_game()`, so "Continue" *starts a new game*. This skill makes
   it resume the newest save.

Depends on the [`save-system`](../save-system/SKILL.md) `SaveManager` autoload for
slot data and integrates with [`ui-shell`](../ui-shell/SKILL.md) `NoxShell`.

## TL;DR

```bash
python3 .claude/skills/loading-continue/tools/loading_gen.py all \
  --output addons/loading/ --theme res://assets/ui/theme.tres
```

| Subcommand | Emits | Purpose |
|---|---|---|
| `loader` | `scene_loader.gd` (autoload) + `loading_screen.tscn/.gd` | Threaded async scene change with progress bar, rotating tips, min-display-time. |
| `continue` | `continue_service.gd` (autoload) | Resume-last: find the newest slot and jump back in. |
| `loadscreen` | `load_screen.tscn/.gd` | Save-slot picker (thumbnail+summary+timestamp); one scene serves Load and Save. |
| `all` | all of the above | New-project one-shot. |

## Wiring

1. Autoload `SceneLoader` and (if using Continue) `ContinueService` in `project.godot`.
2. **Route scene changes through the loader** instead of `change_scene_to_file` —
   `NoxShell.new_game()` and gameplay transitions call `SceneLoader.change_scene(path)`.
3. **Fix the Continue button.** In `main_menu.gd` (nox_ui), replace the two default
   lines so Continue resumes instead of restarting:
   ```gdscript
   _continue.visible = ContinueService.has_resumable()      # not NoxShell.has_continue()
   func _on_continue_pressed() -> void: ContinueService.resume_last()
   ```
   `resume_last()` loads the newest slot's `SaveData` and changes to its `scene_path`;
   the gameplay scene restores state from `SaveManager` on `_ready` (as with any load).
4. Point the menu's Load button (or a new one) at `load_screen.tscn` (Mode.LOAD); in
   the pause menu, instance it with `mode = Mode.SAVE` for the Save picker.

## Loading screen: the three things people get wrong

- **Threaded, not blocking.** Uses `ResourceLoader.load_threaded_request` +
  `..._get_status` with a real progress value — the frame stays responsive.
- **Minimum display time.** `MIN_DISPLAY_SEC` (default 0.8s) prevents a one-frame
  flash on fast loads; also prevents a jarring instant swap.
- **Tips + backdrop are content, sourced reuse-first.** Fill `TIPS` from the game's
  help/lore strings (localizable) and assign a real backdrop to `$Backdrop` from the
  library/manifest — not placeholder art (`skills/asset-reuse`, `skills/parity-build/STANDARDS.md`).

## Reuse-first, typography-aware, accessible

- **Reuse-first:** loading backdrop + any slot-card frame come from the library and
  are registered in `asset-manifest`; nothing generated before the ladder is checked.
- **Typography deferred:** every emitted scene applies `theme.tres` (pass `--theme`)
  — tip text, slot labels, and the "Load Game" title inherit the display/body faces
  from [`typography`](../typography/SKILL.md). No hardcoded fonts.
- **Accessible:** progress is shown as a bar **and** the tip text (not color alone);
  labels respect the UI-scale from `theme.tres`; timestamps are absolute and
  readable (see [`accessibility`](../accessibility/SKILL.md)).

## Cardinal rules

- **Continue ≠ New Game.** If a template ships a Continue button that starts fresh,
  that's a bug — wire `ContinueService.resume_last()`.
- **Never block the main thread to load.** Always go through `SceneLoader`.
- **The slot picker reads live `SaveManager.list_slots()`** — thumbnails and
  summaries come from save-system's `thumbnail`/`summary`; don't duplicate that data.
- **Empty slots are visible and labelled** ("Empty"), and in Save mode are writable.

## Verify

Boot scoped (`--path .`); **screenshot the loading screen mid-load** (bar moving,
tip shown), then **Continue from the menu** and confirm it drops into the newest
save's scene (not a new game), and open the load screen to confirm each slot shows
thumbnail + summary + timestamp. See `parity-build/STANDARDS.md`.

## Files

- `tools/loading_gen.py` — the CLI (single file, stdlib only).
- `SKILL.md` — this file.

## Composition

- **save-system** — `SaveManager` supplies slot list, thumbnails, summaries, load/delete.
- **ui-shell** — `NoxShell.new_game()` routes through `SceneLoader`; Continue button rewired to `ContinueService`.
- **ui-theme / typography** — `theme.tres` styles all three scenes.
- **asset-reuse / asset-manifest** — loading backdrop + card art sourced and tracked.
