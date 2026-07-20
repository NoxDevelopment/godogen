extends Control
## NoxDev standard main menu. Generic — reads title/subtitle/credits/backdrop from
## NoxShell (which loads the per-game NoxShellConfig). Never edited per-template.

@onready var _title: Label = $CenterBox/VBox/Title
@onready var _subtitle: Label = $CenterBox/VBox/Subtitle
@onready var _continue: Button = $CenterBox/VBox/Continue
@onready var _options: Panel = $OptionsPanel
@onready var _credits: Panel = $CreditsPanel
@onready var _backdrop: TextureRect = $Backdrop

func _ready() -> void:
	_title.text = NoxShell.title()
	_subtitle.text = NoxShell.subtitle()
	_subtitle.visible = _subtitle.text.strip_edges() != ""
	_continue.visible = NoxShell.has_resumable()
	_options.visible = false
	_credits.visible = false
	var bp := NoxShell.backdrop_path()
	if bp != "" and ResourceLoader.exists(bp):
		_backdrop.texture = load(bp)
		_backdrop.visible = true
	else:
		_backdrop.visible = false
	$OptionsPanel/VBox/Fullscreen.button_pressed = NoxSettings.fullscreen
	$OptionsPanel/VBox/Vsync.button_pressed = NoxSettings.vsync
	$OptionsPanel/VBox/Master/S.value = NoxSettings.master
	$OptionsPanel/VBox/Music/S.value = NoxSettings.music
	$OptionsPanel/VBox/SFX/S.value = NoxSettings.sfx
	_first_focus()

func _first_focus() -> void:
	$CenterBox/VBox/NewGame.grab_focus()

func _on_new_game_pressed() -> void: NoxShell.new_game()
func _on_continue_pressed() -> void: NoxShell.resume_last()
func _on_options_pressed() -> void:
	_options.visible = true
	$OptionsPanel/VBox/Back.grab_focus()
func _on_credits_pressed() -> void:
	$CreditsPanel/VBox/Text.text = NoxShell.credits()
	_credits.visible = true
	$CreditsPanel/VBox/Back.grab_focus()
func _on_quit_pressed() -> void: NoxShell.quit_game()
func _on_opt_back_pressed() -> void:
	_options.visible = false
	$CenterBox/VBox/Options.grab_focus()
func _on_cred_back_pressed() -> void:
	_credits.visible = false
	$CenterBox/VBox/Credits.grab_focus()
func _on_fullscreen_toggled(p: bool) -> void: NoxSettings.set_fullscreen(p)
func _on_vsync_toggled(p: bool) -> void: NoxSettings.set_vsync(p)
func _on_master_changed(v: float) -> void: NoxSettings.set_volume("master", v)
func _on_music_changed(v: float) -> void: NoxSettings.set_volume("music", v)
func _on_sfx_changed(v: float) -> void: NoxSettings.set_volume("sfx", v)
