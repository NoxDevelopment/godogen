extends CanvasLayer
## res://scripts/run_summary.gd
## End-of-run summary shown when the whole party falls: kills, whether the
## secret room was found, best-kills record. The tree is paused by main.gd
## before this opens (PROCESS_MODE_ALWAYS keeps the UI live); Enter or the
## Restart button reloads the dungeon — opened doors and taken pickups
## persist through GameManager flags.

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


func show_result(kills: int, best_kills: int, secret_found: bool) -> void:
	_title_label.text = "THE PARTY HAS FALLEN"
	_stats_label.text = "Kills: %d\nBest kills: %d\nSecret found: %s" % [
		kills, best_kills, "yes" if secret_found else "no",
	]
	visible = true


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
