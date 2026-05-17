# Save System

Godot 4 save-system scaffold: typed `Resource` save model, multi-slot manager with thumbnails, version migration chain, autosave timer, and atomic write-with-fsync. Pure text — no ComfyUI / Tripo3D / model dependencies.

## TL;DR

```bash
python3 .claude/skills/save-system/tools/save_gen.py {model|manager|autosave|thumbnail|all|list} [opts]
```

## What this emits

| Subcommand | Files produced | Purpose |
|------------|---------------|---------|
| `model` | `save_data.gd` | Typed `Resource` class with versioned fields and a `migrate_from(old: Dictionary)` chain. |
| `manager` | `save_manager.gd` | Autoload singleton: list / load / save / delete slots, atomic writes, in-memory cache. |
| `autosave` | `autosave.gd` | `Timer`-driven autosave that snapshots only when game state actually changed. |
| `thumbnail` | `thumbnail.gd` | Viewport-capture helper that writes a 320×180 PNG next to each save. |
| `all` | all of the above | One-shot scaffold for a new project. |
| `list` | _(none)_ | Print available presets and their field sets. |

Every subcommand takes `--output <dir>` (default `res://save/`) and `--preset <name>` (controls which fields go in `save_data.gd`).

## Why this skill exists

Three repeating mistakes when agents wire up Godot save systems:

1. **Naive `save_game(path).save_to_file()` writes** — if the game crashes mid-write, the slot is corrupted. The emitted manager writes to `<slot>.tmp`, fsyncs (`flush()`), then renames.
2. **Schema-free `Dictionary` saves** — load a 6-month-old save into a new build, get type errors deep in gameplay code. The emitted `save_data.gd` is a `Resource` with explicit typed fields and a `version` int; a `migrate_from()` chain handles old data.
3. **Autosave-on-timer that always writes** — wears down user disks and creates pointless I/O. The emitted autosave checks `SaveManager.is_dirty()` (set by gameplay code on meaningful state changes) before writing.

## Subcommands

### model — Typed Resource save model

```bash
python3 .claude/skills/save-system/tools/save_gen.py model \
  --output res://save/ \
  --preset platformer
```

Presets define the field set baked into `save_data.gd`:

| Preset | Fields |
|--------|--------|
| `platformer` | `level_id`, `checkpoint_id`, `lives`, `coins`, `unlocked_levels`, `power_ups`, `play_time_seconds` |
| `topdown` | `scene_path`, `player_position`, `player_health`, `inventory`, `quest_flags`, `unlocked_areas`, `play_time_seconds` |
| `rpg` | `scene_path`, `player_position`, `party_members`, `inventory`, `gold`, `quest_log`, `world_flags`, `relationship_levels`, `play_time_seconds` |
| `puzzle` | `current_puzzle_id`, `solved_puzzles`, `hint_tokens`, `total_moves`, `best_times` |
| `racing` | `unlocked_tracks`, `track_records`, `cash`, `owned_vehicles`, `current_vehicle_id`, `total_distance_meters` |
| `minimal` | `version`, `play_time_seconds`, `data` (Dictionary catch-all) |

Each preset's fields are typed (`int`, `float`, `String`, `Array[String]`, `Dictionary`) — no `Variant` catch-alls except the `minimal` preset. The class starts at `const VERSION := 1` with an empty `migrate_from()` body. Future migrations add `if old_version == 1: …` branches.

### manager — Autoload save/load singleton

```bash
python3 .claude/skills/save-system/tools/save_gen.py manager \
  --output res://save/
```

Writes `save_manager.gd` — register as an Autoload named `SaveManager`. Exposes:

| Method | Purpose |
|--------|---------|
| `list_slots() -> Array[Dictionary]` | Returns `[{slot, exists, modified_time, thumbnail_path, summary}, …]`. |
| `save_to_slot(slot: int, data: SaveData) -> Error` | Atomic write to `user://saves/slot_N.tres` via `.tmp` + rename. |
| `load_from_slot(slot: int) -> SaveData` | Loads + runs migration chain. Returns `null` on failure (with `push_error`). |
| `delete_slot(slot: int) -> Error` | Removes save file + thumbnail. |
| `quick_save() / quick_load()` | Slot 0 shortcut. |
| `mark_dirty()` / `is_dirty() / clear_dirty()` | Signal whether the game state has changed since last save (used by autosave). |
| Signal: `save_completed(slot, success)` | Fires after every write attempt. |
| Signal: `load_completed(slot, success, data)` | Fires after every load attempt. |

Storage: `user://saves/slot_<N>.tres` (Godot's text resource format — diffable, inspectable in any text editor for debugging).

### autosave — Smart autosave timer

```bash
python3 .claude/skills/save-system/tools/save_gen.py autosave \
  --output res://save/ \
  --interval 120 \
  --slot 9
```

Writes `autosave.gd` (attach to a `Timer` node, or instance as a child of the player). On each tick:

1. Skip if `SaveManager.is_dirty()` is false (no state change since last write).
2. Snapshot current `SaveData` via the project-provided callback.
3. Write to `--slot` (default 9 — keeps it visually distinct from manual slots 0–8).
4. Clear the dirty flag.

`--interval` is seconds between checks. Default 120 is conservative; drop to 30 for roguelikes.

The script emits a `# CUSTOMIZE_HERE` comment block where your project provides a `_snapshot_state() -> SaveData` callback — the skill cannot know what your gameplay state is.

### thumbnail — Save-slot thumbnail capture

```bash
python3 .claude/skills/save-system/tools/save_gen.py thumbnail \
  --output res://save/ \
  --size 320x180
```

Writes `thumbnail.gd` with one method: `capture(slot: int) -> Error`. Pulls the current viewport image, resizes to `--size` (default `320x180`), writes a PNG next to the save file. Call this **after** `save_to_slot()`.

### all — Emit everything for a new project

```bash
python3 .claude/skills/save-system/tools/save_gen.py all \
  --output res://save/ \
  --preset rpg
```

Writes all four scripts. Recommended for any project that doesn't already have a save system.

### list — Print presets

```bash
python3 .claude/skills/save-system/tools/save_gen.py list
```

## Migration chain pattern

The emitted `save_data.gd` includes a `static func migrate_from(old: Dictionary) -> SaveData` that handles all historical schemas. When you add a field in version N+1, add **one branch** for `if old["version"] == N` that defaults the new field — never delete existing branches. Old saves walk the chain step-by-step (1 → 2 → 3 → current).

```gdscript
static func migrate_from(old: Dictionary) -> SaveData:
    var data := SaveData.new()
    var old_version: int = old.get("version", 1)
    # v1 -> v2: added 'play_time_seconds'
    if old_version == 1:
        old["play_time_seconds"] = 0.0
        old_version = 2
    # v2 -> v3: renamed 'gold' to 'currency'
    if old_version == 2:
        old["currency"] = old.get("gold", 0)
        old.erase("gold")
        old_version = 3
    # …current version assignment…
    for key in old:
        if key in data:
            data.set(key, old[key])
    return data
```

## Cardinal rules

- **Never overwrite a save file directly.** Always write `<path>.tmp` first, `file.flush()`, then `DirAccess.rename_absolute()`. The emitted manager does this.
- **Bump `VERSION` whenever you add/rename/remove a field.** Then add a migration branch. Saves from old builds will silently lose data otherwise.
- **Saves go to `user://`, never `res://`.** `res://` is read-only at runtime in exported builds. (The `--output` flag here writes the *scripts* to your project tree — the actual save data goes to `user://saves/`.)
- **Mark dirty deliberately.** Only call `SaveManager.mark_dirty()` on meaningful state changes (room entry, inventory pickup, dialogue completion). Movement deltas don't count.
- **Save data is a `Resource`, not a `Dictionary`.** Typed fields catch schema errors at load time instead of three rooms later when you `.set_health()` on a string.

## Files

- `tools/save_gen.py` — the CLI (single file).
- `SKILL.md` — this file.

## Composition

- **godot-task** — once the scripts are emitted, ask godot-task to register `SaveManager` as an autoload and wire `Autosave` to the player scene.
- **ui-screens** — the `menu` scaffold's "Save" / "Load" buttons should call `SaveManager.save_to_slot()` / `load_from_slot()` and switch to a slot-picker screen (not provided by this skill yet; use the row layout from `rebind_screen.tscn` as a starting point).
- **input-handling** — input remappings are a **per-user preference**, not save data. Don't bundle them into `SaveData`; they live in `user://input_map.cfg` (see input-handling's `InputPersistence` autoload).
- **playtest** — when authoring playtest checkpoints, the checkpoint hook can call `SaveManager.save_to_slot(99, …)` for a determinism-friendly save point.
