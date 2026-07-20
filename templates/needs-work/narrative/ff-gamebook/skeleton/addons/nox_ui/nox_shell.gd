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

# --- Resume ("Continue") — resume the newest save, never start a fresh game ------
## The shell historically shipped Continue wired to new_game() (issue #25: the
## "Continue" button silently started a NEW game). The shell now resolves a resume
## path generically, in priority order, so no template inherits that bug again:
##   1) a resume provider the game registers via set_resume_provider() — any object
##      exposing has_resumable()/resume_last() (for a bespoke save format);
##   2) a ContinueService autoload (the loading-continue skill) over a SaveManager;
##   3) the legacy config `show_continue` flag as a last resort (best-effort; resume
##      only falls back to a fresh game when nothing better is wired, and warns).
## Templates should wire (1) or (2). Continue visibility is gated on has_resumable().

var _resume_provider: Object = null

## Register a bespoke resume provider (an object with has_resumable()/resume_last()).
## Call from an autoload's _ready() (e.g. a game's SaveManager/controller).
func set_resume_provider(p: Object) -> void:
	_resume_provider = p

## True when there is a save the player can resume — gates the Continue button.
func has_resumable() -> bool:
	if _resume_provider != null and is_instance_valid(_resume_provider) and _resume_provider.has_method("has_resumable"):
		return bool(_resume_provider.has_resumable())
	var cs := get_node_or_null("/root/ContinueService")
	if cs != null and cs.has_method("has_resumable"):
		return bool(cs.has_resumable())
	return has_continue()

## Resume the newest save (the Continue button). Delegates to the resume provider or
## ContinueService; only starts a new game if neither is wired (and warns).
func resume_last() -> void:
	if _resume_provider != null and is_instance_valid(_resume_provider) and _resume_provider.has_method("resume_last"):
		_resume_provider.resume_last()
		return
	var cs := get_node_or_null("/root/ContinueService")
	if cs != null and cs.has_method("resume_last"):
		cs.resume_last()
		return
	push_warning("NoxShell.resume_last(): no resume provider or ContinueService wired — starting a new game")
	new_game()

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
