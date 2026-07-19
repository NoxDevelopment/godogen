---
name: ui-shell
description: The standard NoxDev house shell — drop-in menu / start / options / pause / credits scenes (the `nox_ui` addon) so every template ships a consistent, professional studio UI instead of a hand-rolled or missing menu. Use when scaffolding a template's shell, wiring the start menu / pause / options / credits, or satisfying the STANDARDS "Production & shell" box.
---

# UI Shell — the standard NoxDev shell (`nox_ui`)

The reusable house shell every NoxDev template inherits. Themed with real **Kenney
CC0** 9-slice buttons + **Montserrat**; generic scenes driven by one per-game
config resource, never edited per-template.

> **This is the anti-placeholder exemplar and it satisfies the shell Definition of
> Done.** It IS `skills/parity-build/STANDARDS.md` → "Production & shell" (professional
> studio menu, full options, pause, quit-to-menu, game-over/win) and demonstrates
> `skills/asset-reuse` rung 3 (owned/CC0 kit — Kenney UI, not generated). Inherit it;
> do **not** hand-roll a menu or ship the bland default screen. When a game needs
> custom shell art (hero/Nox-goddess backdrop), source it reuse-first and bind it
> through `asset-manifest`, then **screenshot the running menu** to verify.

The addon lives at [`addon/nox_ui/`](addon/nox_ui/); full component reference and
license notes are in [`addon/nox_ui/README.md`](addon/nox_ui/README.md).

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
config resource changes.

## Verify
Boot the shell scoped (`godot --headless --path . --import` then run) and
**screenshot the menu, options, pause, and credits** — confirm config-driven
title/subtitle/Continue, zero import errors, and that any custom backdrop is real
art (not a bare `ColorRect`). License: art is Kenney CC0 (see
`addon/nox_ui/theme/kenney/LICENSE.txt`); honor attribution in the credits screen.
