extends CanvasLayer
## res://scripts/run_summary.gd
## End-of-run summary shown when the player dies: kills (the score), wave
## reached, best-kills record. The tree is paused by main.gd before this
## opens (PROCESS_MODE_ALWAYS keeps the UI live); Enter or the Restart
## button reloads the run.

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


func show_result(kills: int, wave: int, best_kills: int) -> void:
	_title_label.text = "YOU DIED"
	_stats_label.text = "Kills: %d\nWave reached: %d\nBest kills: %d" % [
		kills, wave, best_kills,
	]
	visible = true


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
