extends Node
## NoxShell — the standard NoxDev game-flow autoload. Autoload as "NoxShell".
## Reads a per-game NoxShellConfig from res://nox_shell_config.tres (optional) and
## drives menu -> game -> menu. Templates set the config; the shell stays generic.

const CONFIG_PATH := "res://nox_shell_config.tres"
const MENU := "res://addons/nox_ui/scenes/main_menu.tscn"

var config: NoxShellConfig = null

func _ready() -> void:
	if ResourceLoader.exists(CONFIG_PATH):
		config = load(CONFIG_PATH)
	if config == null:
		config = NoxShellConfig.new()

func title() -> String:
	if config and config.game_title.strip_edges() != "":
		return config.game_title
	return str(ProjectSettings.get_setting("application/config/name", "NoxDev Game"))

func subtitle() -> String:
	return config.subtitle if config else ""

func credits() -> String:
	if config and config.credits.strip_edges() != "":
		return config.credits
	return "Made with the NoxDev Studio shell."

func has_continue() -> bool:
	return config != null and config.show_continue

func backdrop_path() -> String:
	return config.backdrop if config else ""

func new_game() -> void:
	if config and config.new_game_scene != "" and ResourceLoader.exists(config.new_game_scene):
		get_tree().paused = false
		get_tree().change_scene_to_file(config.new_game_scene)
	else:
		push_warning("NoxShell: no valid new_game_scene set in nox_shell_config.tres")

func to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU)

func quit_game() -> void:
	get_tree().quit()
