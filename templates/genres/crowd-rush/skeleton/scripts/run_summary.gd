extends CanvasLayer
## res://scripts/run_summary.gd
## End-of-run summary shown after the finish-tower comparison or a crowd
## wipe: win/lose, surviving units (the score), tower count, distance,
## best-survivors record. The tree is paused by main.gd before this opens
## (PROCESS_MODE_ALWAYS keeps the UI live); Enter or the Restart button
## reloads the run.

@onready var _title_label: Label = $Panel/Rows/Title
@onready var _stats_label: Label = $Panel/Rows/StatsLabel
@onready var _restart_button: Button = $Panel/Rows/RestartButton


func _ready() -> void:
	visible = false
	_restart_button.pressed.connect(restart)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		restart()


func show_result(win: bool, survivors: int, boss_count: int, distance: float,
		best_survivors: int) -> void:
	_title_label.text = "THE TOWER FALLS" if win else "RUN OVER"
	_stats_label.text = "Crowd %d vs tower %d\nDistance: %d m\nBest crowd: %d" % [
		survivors, boss_count, int(distance), best_survivors,
	]
	visible = true


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
