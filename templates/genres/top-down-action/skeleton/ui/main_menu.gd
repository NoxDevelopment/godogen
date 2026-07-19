extends Control
## Title screen: start a scored wave run, play the story level, tweak options, quit.

@onready var _best: Label = $CenterBox/VBox/Best
@onready var _options: Panel = $OptionsPanel

func _ready() -> void:
	$CenterBox/VBox/NewGame.grab_focus()
	_options.visible = false
	_refresh_best()

func _refresh_best() -> void:
	if GameFlow.best_score > 0:
		_best.text = "BEST  %d   ·   %s" % [GameFlow.best_score, GameFlow.format_time(GameFlow.best_time)]
	else:
		_best.text = "No run recorded yet"

func _on_new_game_pressed() -> void:
	GameFlow.new_game()

func _on_story_pressed() -> void:
	GameFlow.play_story()

func _on_options_pressed() -> void:
	_options.visible = true
	$OptionsPanel/VBox/Back.grab_focus()

func _on_back_pressed() -> void:
	_options.visible = false
	$CenterBox/VBox/Options.grab_focus()

func _on_fullscreen_toggled(pressed: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	)

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(value, 0.0001, 1.0)))

func _on_quit_pressed() -> void:
	get_tree().quit()
