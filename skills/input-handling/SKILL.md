# Input Handling

Godot 4 `InputMap` action emission, runtime rebinding-UI scaffolds, and conflict / dead-zone diagnostics. Pure text — no ComfyUI / Tripo3D / model dependencies.

Two output flavors:

- **Resource emission** — `project.godot` `[input]` block patches, plus optional sidecar `.gd` constants module so your gameplay code refers to actions as `Actions.MOVE_LEFT` instead of stringly-typed `"move_left"`.
- **Rebinding UI** — a self-contained Control-tree `.tscn` + `.gd` that lists every action, lets the player press a new key/button to remap, persists to `user://input_map.cfg`, and reloads on game launch.

## TL;DR

```bash
python3 .claude/skills/input-handling/tools/input_gen.py {actions|rebind|template|lint|list} [opts]
```

## Why this skill exists

Three problems agents repeatedly hit when wiring input:

1. **Stringly-typed actions.** `Input.is_action_pressed("move_left")` typos compile fine and silently do nothing. Emit a constants module and import it.
2. **Wrong `[input]` block format.** The `project.godot` syntax for input actions is finicky (`deadzone`, `events=[ ... ]` array of `InputEvent…` resource literals). Wrong format = silent no-op or editor reset.
3. **Rebinding UI is always rewritten from scratch.** Every project needs the same four pieces: list actions, capture next event, validate it doesn't collide, persist. Ship the scaffold.

## Subcommands

### actions — Emit `[input]` block + optional constants module

```bash
# Default platformer action set → write into project.godot's [input] block
python3 .claude/skills/input-handling/tools/input_gen.py actions \
  --template platformer \
  --project-godot ./project.godot \
  --constants ./scripts/actions.gd
```

Templates: `platformer`, `topdown`, `fps`, `rts`, `puzzle`, `fighting`, `racing`, `none` (empty scaffold).

`--project-godot` is patched **in place** (`[input]` block replaced; rest of file untouched). If the file has no `[input]` section, one is appended. A `.bak` is written next to the file before the rewrite — restore with `mv project.godot.bak project.godot`.

`--constants` (optional) writes a `class_name Actions extends RefCounted` module with `const MOVE_LEFT := &"move_left"` lines (StringName literals — zero-allocation comparisons). Drop it as an autoload or `preload()` it where you need actions.

To preview without writing, omit both flags — the resulting `[input]` block prints to stdout.

### rebind — Emit rebinding UI scaffold

```bash
python3 .claude/skills/input-handling/tools/input_gen.py rebind \
  --output ui/rebind/
```

Writes three files into the output dir:

- `rebind_screen.tscn` — scrollable list of all `InputMap` actions, each row with `Label` + `Button` (current binding) + `Button` (Reset). A bottom bar has `Save & Close` / `Restore Defaults`.
- `rebind_screen.gd` — populates the list from `InputMap.get_actions()`, filters internal `ui_*` actions by default (toggle with `--include-ui`), captures the next `InputEventKey` / `InputEventMouseButton` / `InputEventJoypadButton`, detects collisions across actions, writes `user://input_map.cfg` on Save.
- `input_persistence.gd` — autoload that loads `user://input_map.cfg` at startup and re-applies overrides on top of the project-default `InputMap`. Add to Project Settings → Autoload as `InputPersistence`.

The scaffold uses **only built-in Godot 4 nodes** — no GDScript class dependencies, no plugins, no Theme overrides. Style with your project's existing Theme.

### template — Print one action template's actions to stdout

```bash
python3 .claude/skills/input-handling/tools/input_gen.py template platformer
```

JSON to stdout: each action's name, default bindings (keyboard + gamepad), dead-zone, and one-line description. Handy for previewing before `actions` overwrites anything.

### lint — Check a `project.godot` for input-map foot-guns

```bash
python3 .claude/skills/input-handling/tools/input_gen.py lint --project-godot ./project.godot
```

Reports:

- Actions that have **only keyboard** bindings (no gamepad) — fine for desktop-only games, flag-worthy otherwise.
- Actions whose **dead-zone is 0.0** but bind to a joystick axis (chatter risk; recommend ≥ 0.2).
- **Duplicate physical keys** across actions (one keypress fires both).
- Built-in `ui_*` actions overwritten with custom bindings (usually a mistake — `ui_*` drives Godot's focus navigation).
- Actions referenced by `Input.is_action_*` in `*.gd` files but **not declared** in `project.godot`.

Exits non-zero if any *error*-class finding is present (duplicates, undeclared). Warnings (no-gamepad, dead-zone) don't fail.

### list — Enumerate available action templates

```bash
python3 .claude/skills/input-handling/tools/input_gen.py list
```

## Action templates

Each template ships with sensible defaults — keyboard for WASD-style movement and arrow keys, plus gamepad bindings (Xbox/PlayStation/Switch layouts auto-cover via Godot's standard mapping).

| Template | Actions |
|----------|---------|
| `platformer` | `move_left`, `move_right`, `jump`, `crouch`, `attack`, `interact`, `pause` |
| `topdown` | `move_up`, `move_down`, `move_left`, `move_right`, `attack`, `dash`, `interact`, `inventory`, `pause` |
| `fps` | `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `crouch`, `sprint`, `fire`, `aim`, `reload`, `interact`, `pause` |
| `rts` | `select`, `multi_select`, `command`, `cancel`, `camera_up`, `camera_down`, `camera_left`, `camera_right`, `pause` |
| `puzzle` | `select`, `cancel`, `undo`, `redo`, `hint`, `restart`, `pause` |
| `fighting` | `move_left`, `move_right`, `crouch`, `jump`, `light_punch`, `heavy_punch`, `light_kick`, `heavy_kick`, `block`, `pause` |
| `racing` | `accelerate`, `brake`, `steer_left`, `steer_right`, `handbrake`, `look_back`, `pause` |
| `none` | _(empty — for projects that prefer to author actions by hand)_ |

All templates include `pause` bound to **Escape + Start button** — a near-universal expectation that's annoying to add later.

## Cardinal rules

- **Action names are StringNames.** Always use the `&"action_name"` literal or the emitted constants module. Plain `"action_name"` strings allocate on every comparison.
- **Never overwrite `ui_*` actions.** Godot uses these for focus navigation in Control trees. If you need WASD in menus, add `menu_up` / `menu_down` etc. as parallel actions.
- **Dead-zone ≥ 0.2 on joystick axes.** Below that, controller drift triggers ghost inputs.
- **Persist to `user://`, never `res://`.** The latter is read-only at runtime in exported builds.

## Files

- `tools/input_gen.py` — the CLI (single file).
- `SKILL.md` — this file.

## Composition

- **godot-task** — once the rebind UI is emitted, ask godot-task to wire `InputPersistence` into the autoload list and attach `rebind_screen.tscn` to the options menu.
- **ui-screens** — the `menu` scaffold has a placeholder Options button; point it at this skill's `rebind_screen.tscn`.
- **save-system** — input remappings persist independently from save slots (they're a per-user preference, not per-save). Don't bundle them into save data.
