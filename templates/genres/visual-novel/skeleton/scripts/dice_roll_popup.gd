extends CanvasLayer
## res://scripts/dice_roll_popup.gd
## Dice-roll popup: dims the screen, tumbles a d20, settles on the rolled
## face, shows the breakdown (die + modifier vs DC) and the verdict, then
## waits for the player to confirm. Driven by SkillCheck.skill_check().

signal finished

const TUMBLE_TIME := 0.9
const TUMBLE_TICK := 0.05
const COLOR_SUCCESS := Color(0.42, 0.78, 0.44)
const COLOR_FAILURE := Color(0.85, 0.38, 0.38)
const COLOR_CRIT := Color(0.98, 0.83, 0.37)

@onready var _title_label: Label = $Center/Panel/Margin/Rows/TitleLabel
@onready var _die_label: Label = $Center/Panel/Margin/Rows/DieLabel
@onready var _breakdown_label: Label = $Center/Panel/Margin/Rows/BreakdownLabel
@onready var _result_label: Label = $Center/Panel/Margin/Rows/ResultLabel
@onready var _continue_button: Button = $Center/Panel/Margin/Rows/ContinueButton


## Play the whole popup flow for a prepared roll result. Await this.
func run(stat: String, dc: int, result: Dictionary) -> void:
	_title_label.text = "%s CHECK — DC %d" % [stat.to_upper(), dc]
	_breakdown_label.visible = false
	_result_label.visible = false
	_continue_button.visible = false

	await _tumble(result.die)
	_show_outcome(result)

	_continue_button.grab_focus()
	await _continue_button.pressed
	finished.emit()


func _tumble(final_die: int) -> void:
	var elapsed := 0.0
	while elapsed < TUMBLE_TIME:
		# Show random faces, never the same face twice in a row.
		var face := randi_range(1, 20)
		while str(face) == _die_label.text:
			face = randi_range(1, 20)
		_die_label.text = str(face)
		# Ease out: ticks get longer as the die settles.
		var tick := TUMBLE_TICK * (1.0 + 3.0 * elapsed / TUMBLE_TIME)
		await get_tree().create_timer(tick).timeout
		elapsed += tick
	_die_label.text = str(final_die)


func _show_outcome(result: Dictionary) -> void:
	var sign_str := "+" if result.modifier >= 0 else "-"
	_breakdown_label.text = "d20 %d %s %s %d  =  %d  vs  DC %d" % [
		result.die, sign_str, result.stat.to_upper(), absi(result.modifier),
		result.total, result.dc,
	]
	_breakdown_label.visible = true

	if result.crit_success:
		_result_label.text = "CRITICAL SUCCESS!"
		_result_label.add_theme_color_override(&"font_color", COLOR_CRIT)
		_die_label.add_theme_color_override(&"font_color", COLOR_CRIT)
	elif result.crit_fail:
		_result_label.text = "CRITICAL FAILURE!"
		_result_label.add_theme_color_override(&"font_color", COLOR_FAILURE)
		_die_label.add_theme_color_override(&"font_color", COLOR_FAILURE)
	elif result.success:
		_result_label.text = "SUCCESS"
		_result_label.add_theme_color_override(&"font_color", COLOR_SUCCESS)
		_die_label.add_theme_color_override(&"font_color", COLOR_SUCCESS)
	else:
		_result_label.text = "FAILURE"
		_result_label.add_theme_color_override(&"font_color", COLOR_FAILURE)
		_die_label.add_theme_color_override(&"font_color", COLOR_FAILURE)
	_result_label.visible = true
	_continue_button.visible = true
