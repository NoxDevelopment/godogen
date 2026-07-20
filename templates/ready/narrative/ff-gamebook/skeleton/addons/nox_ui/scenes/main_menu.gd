extends Control
## FF-gamebook main menu (vendored nox_ui). Reads title/subtitle/backdrop/credits from
## NoxShell (per-game NoxShellConfig). Phase-7 shell wiring layered on the generic
## shell without forking its behaviour:
##   * Continue  → NoxShell.resume_last() (resumes the newest save; visible only when a
##                 save exists — the #25 bug fix, shared with the nox_ui SOURCE).
##   * Load      → the loading-continue slot picker (load_screen, LOAD mode) over the
##                 FF SaveManager.
##   * Options   → the fully-fleshed tabbed Options overlay.
##   * Credits   → the credits skill's scrolling credits.tscn (asset-heavy mode),
##                 replacing the overflow-prone inline text panel.
## These per-template routes live in this vendored copy; the shared SOURCE stays
## generic (see the re-vendoring note in the skeleton's phase report).

const OPTIONS_VIEW := preload("res://scripts/screens/options_view.gd")
const LOAD_SCREEN := preload("res://addons/loading/load_screen.tscn")
const CREDITS_SCENE := "res://credits.tscn"

@onready var _title: Label = $CenterBox/VBox/Title
@onready var _subtitle: Label = $CenterBox/VBox/Subtitle
@onready var _continue: Button = $CenterBox/VBox/Continue
@onready var _backdrop: TextureRect = $Backdrop

func _ready() -> void:
	_title.text = NoxShell.title()
	_subtitle.text = NoxShell.subtitle()
	_subtitle.visible = _subtitle.text.strip_edges() != ""
	_continue.visible = NoxShell.has_resumable()
	var bp := NoxShell.backdrop_path()
	if bp != "" and ResourceLoader.exists(bp):
		_backdrop.texture = load(bp)
		_backdrop.visible = true
	else:
		_backdrop.visible = false
	# Title / Main Menu bed — brooding invitation (STYLE_GUIDE §2.2). AudioDirector is a
	# project autoload; guard so the shell still runs where one isn't shipped. UI-click
	# SFX is auto-wired onto every Button.
	var _ad := get_node_or_null("/root/AudioDirector")
	if _ad != null:
		_ad.play_music("menu")
	_first_focus()

func _first_focus() -> void:
	$CenterBox/VBox/NewGame.grab_focus()

func _on_new_game_pressed() -> void: NoxShell.new_game()
func _on_continue_pressed() -> void: NoxShell.resume_last()

func _on_load_pressed() -> void:
	var ls := LOAD_SCREEN.instantiate()
	ls.mode = 0   # load_screen.Mode.LOAD
	add_child(ls)

func _on_options_pressed() -> void:
	add_child(OPTIONS_VIEW.new())

func _on_credits_pressed() -> void:
	if ResourceLoader.exists(CREDITS_SCENE):
		get_tree().change_scene_to_file(CREDITS_SCENE)
	else:
		push_warning("main_menu: credits scene missing at %s" % CREDITS_SCENE)

func _on_quit_pressed() -> void: NoxShell.quit_game()
