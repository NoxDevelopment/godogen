# nox_ui — the standard NoxDev shell

Drop-in, reusable **menu / start / options / pause / credits** shell so every NoxDev
template ships a consistent house UI instead of a hand-rolled (or missing) menu.
Themed with real **Kenney CC0** 9-slice buttons + **Montserrat**; generic scenes
driven by one per-game config file.

## What's inside
- `theme/nox_theme.tres` — textured button/panel theme (Kenney UI RPG Expansion, CC0) + Montserrat.
- `nox_shell_config.gd` — `NoxShellConfig` resource: `game_title`, `subtitle`, `new_game_scene`, `show_continue`, `credits`, `backdrop`.
- `game_settings.gd` — **NoxSettings** autoload: fullscreen / vsync / master-music-sfx volume, persisted to `user://nox_settings.cfg`, applied on boot.
- `nox_shell.gd` — **NoxShell** autoload: game flow (`new_game()`, `to_menu()`, `quit_game()`), reads the config.
- `scenes/main_menu.tscn` — title screen (New Game / Continue / Options / Credits / Quit + inline options & credits panels + optional darkened backdrop).
- `scenes/pause_menu.tscn` — drop-in pause overlay (Esc → Resume / Main Menu / Quit), pauses the tree.

## Use it in a template
1. Copy `addons/nox_ui/` into the project (vendored — not gitignored).
2. Register autoloads in `project.godot`:
   ```
   [autoload]
   NoxSettings="*res://addons/nox_ui/game_settings.gd"
   NoxShell="*res://addons/nox_ui/nox_shell.gd"
   ```
3. Set `run/main_scene="res://addons/nox_ui/scenes/main_menu.tscn"`.
4. Ship a `res://nox_shell_config.tres` (a `NoxShellConfig`) with the game's title,
   subtitle, credits, and `new_game_scene` pointing at the actual gameplay scene.
5. In the gameplay scene, add `scenes/pause_menu.tscn` as a child for pause.

The menu, options, and pause scenes are **never edited per-template** — only the
config resource changes. Verified: renders clean (config-driven title/subtitle/
Continue), zero import errors. License: art is Kenney CC0 (see `theme/kenney/LICENSE.txt`).
