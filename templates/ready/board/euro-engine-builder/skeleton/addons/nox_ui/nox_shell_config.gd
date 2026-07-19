extends Resource
class_name NoxShellConfig
## Per-game configuration for the NoxDev shell. A template ships ONE of these at
## res://nox_shell_config.tres and the shell reads it — the shell scenes/scripts
## stay generic and are never edited per-template.

## Big title on the main menu (falls back to the project name).
@export var game_title: String = ""
## One-line tagline under the title.
@export var subtitle: String = ""
## Scene the "New Game" button loads (res:// path to the actual gameplay scene).
@export_file("*.tscn") var new_game_scene: String = ""
## Show a "Continue" button (only meaningful if the game writes a save).
@export var show_continue: bool = false
## Credits text (multi-line). Shown on the Credits screen.
@export_multiline var credits: String = ""
## Optional darkened backdrop image behind the menu (a gameplay beauty shot).
@export_file("*.png", "*.jpg", "*.webp") var backdrop: String = ""
