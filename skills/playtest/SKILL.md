# Playtest

Godot 4 headless runner + checkpoint autoload + markdown report generator. Drives `godot --headless` against a project, captures periodic screenshots and stdout/stderr, then collates everything into a bug-surface report the agent can read directly.

Pure-CLI; no ComfyUI / Tripo3D / model dependencies. Requires a Godot 4 binary on `PATH` or `$GODOT_BIN` set.

## TL;DR

```bash
python3 .claude/skills/playtest/tools/playtest.py {headless|checkpoint|report} [opts]
```

## Subcommands

### headless — Run Godot, capture screenshots + log

```bash
python3 .claude/skills/playtest/tools/playtest.py headless \
  --project /path/to/godot-project \
  --main-scene res://scenes/Main.tscn \
  --duration 30 --interval 5 \
  --output-dir playtest_runs/
```

Steps:
1. Drops a temp `_playtest_runner.gd` into the project (cleaned up after the run).
2. Launches `godot --headless --path PROJECT --script res://_playtest_runner.gd`.
3. The runner instances `--main-scene`, plays for `--duration` seconds, captures a PNG every `--interval` seconds, then quits.
4. Tees stdout/stderr to `<run_dir>/stdout.log`, moves screenshots to `<run_dir>/screenshots/`.
5. Sets `PLAYTEST_ACTIVE=1` env var (so `PlaytestCheckpoint` from the `checkpoint` subcommand activates).

Run dir layout:
```
playtest_runs/run_1715567890/
├── stdout.log
└── screenshots/
    ├── shot_000.png   (t=0s)
    ├── shot_001.png   (t=5s)
    └── shot_002.png   (t=10s)
```

Exit code = Godot's exit code. `--timeout-grace 10` adds 10s of slack before SIGKILL if Godot ignores the quit signal.

### checkpoint — Emit PlaytestCheckpoint.gd autoload

```bash
python3 .claude/skills/playtest/tools/playtest.py checkpoint \
  -o addons/playtest/PlaytestCheckpoint.gd
```

Drops a GDScript file the user wires up as an autoload in Project Settings. Once added, any scene script can call:

```gdscript
PlaytestCheckpoint.screenshot("level_1_loaded")
PlaytestCheckpoint.mark("boss_spawned", {"hp": boss.hp, "phase": "intro"})
```

Both methods are no-ops unless `OS.has_environment("PLAYTEST_ACTIVE")` returns true — so you can leave calls in production code at zero runtime cost.

Output goes to `user://playtest_checkpoints/`:
- Screenshots: `<unix_ts>_<event_name>.png`
- Event log: `events.log` (`unix_ts  event_name  json_data` per line)

### report — Collate a run dir into markdown

```bash
python3 .claude/skills/playtest/tools/playtest.py report \
  --run-dir playtest_runs/run_1715567890/ \
  -o playtest_runs/run_1715567890/report.md
```

Walks the run dir, parses `stdout.log` for errors / warnings / playtest events, embeds the screenshot timeline. Output is markdown with sections:

- Summary (counts)
- Errors (one bullet per matching line)
- Warnings
- Playtest events
- Screenshot timeline (`![shot_NNN.png](screenshots/shot_NNN.png)` — viewable in any markdown viewer)
- Verdict (`pass` / `warn` / `fail` based on whether errors were present)

Error / warning detection uses regex patterns tuned for Godot output (`ERROR:`, `SCRIPT ERROR:`, `WARNING:`, `Traceback`, `failed to ...`, etc.). The verdict is conservative: any single error → `fail`.

## Pipeline — agent-driven CI loop

```bash
# 1. After each code change the agent makes, run a headless playtest:
python3 .claude/skills/playtest/tools/playtest.py headless \
  --project . --main-scene res://scenes/Main.tscn --duration 20 \
  --output-dir .playtest/

# 2. Generate a report and read its verdict:
python3 .claude/skills/playtest/tools/playtest.py report \
  --run-dir .playtest/run_*/  # most recent

# 3. Agent reads report.md (errors/warnings sections), decides next fix.
```

For coverage at specific game beats, sprinkle `PlaytestCheckpoint.screenshot("X")` calls in scripts. The agent can then inspect those specific frames when diagnosing logic bugs.

## What NOT to do

- Don't run headless on a project with mandatory user input (login screen, splash screen requiring click) — it'll hang until `--timeout-grace` kicks in
- Don't expect the screenshot to capture overlay HUD if the HUD canvas isn't part of the Main scene tree the runner instances
- Don't add `PlaytestCheckpoint.screenshot()` inside hot loops — it's `get_image()` + `save_png` per call; cheap but not free at 60fps
- Don't run `headless` on a remote machine without a virtual framebuffer (Xvfb on Linux) — Godot's renderer still wants a display unless the project is configured for `--headless` rendering at the project-settings level

## Verification

JSON to stdout:
```json
{
  "ok": true, "subcommand": "headless",
  "run_id": "run_1715567890", "exit_code": 0,
  "elapsed_s": 20.34, "log": "...", "screenshots_dir": "...",
  "screenshot_count": 4, "godot_binary": "godot"
}
```

For `report`, the `verdict` field (`pass` / `warn` / `fail`) lets an outer script decide whether to continue iterating.
