extends Control
## Victory screen shown after the final wave is cleared. Reports this run's score
## and time, plus the persisted best, then routes back into play or to the menu.

func _ready() -> void:
	$CenterBox/VBox/Score.text = "SCORE  %d" % GameFlow.score()
	$CenterBox/VBox/Time.text = "TIME  " + GameFlow.format_time(GameFlow.run_time)
	$CenterBox/VBox/Best.text = "BEST  %d   ·   %s" % [GameFlow.best_score, GameFlow.format_time(GameFlow.best_time)]
	$CenterBox/VBox/PlayAgain.grab_focus()

func _on_play_again_pressed() -> void:
	GameFlow.new_game()

func _on_menu_pressed() -> void:
	GameFlow.to_menu()
