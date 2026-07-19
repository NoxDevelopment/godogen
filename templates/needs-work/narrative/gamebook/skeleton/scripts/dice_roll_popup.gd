extends CanvasLayer
## res://scripts/dice_roll_popup.gd
## Dice-test popup: dims the screen, tumbles 2d6, settles on the rolled pair,
## shows the breakdown (2d6 total vs the tested stat — gamebook roll-under)
## and the verdict, then waits for the player to confirm. Driven by
## Dice.test().

signal finished

const TUMBLE_TIME := 0.9
const TUMBLE_TICK := 0.05
const COLOR_SUCCESS := Color(0.42, 0.78, 0.44)
const COLOR_FAILURE := Color(0.85, 0.38, 0.38)
const COLOR_CRIT := Color(0.98, 0.83, 0.37)

@onready var _title_label: Label = $Center/Panel/Margin/Rows/TitleLabel
@onready var _dice_label: Label = $Center/Panel/Margin/Rows/DiceLabel
@onready var _breakdown_label: Label = $Center/Panel/Margin/Rows/BreakdownLabel
@onready var _result_label: Label = $Center/Panel/Margin/Rows/ResultLabel
@onready var _continue_button: Button = $Center/Panel/Margin/Rows/ContinueButton


## Play the whole popup flow for a prepared roll result. Await this.
func run(result: Dictionary) -> void:
	_title_label.text = "TEST YOUR %s — %d or less" % [
		str(result.stat).to_upper(), result.target,
	]
	_breakdown_label.visible = false
	_result_label.visible = false
	_continue_button.visible = false

	await _tumble(result.die_a, result.die_b)
	_show_outcome(result)

	_continue_button.grab_focus()
	await _continue_button.pressed
	finished.emit()


func _tumble(final_a: int, final_b: int) -> void:
	var elapsed := 0.0
	while elapsed < TUMBLE_TIME:
		# Show random faces, never the same pair twice in a row.
		var faces := "%d  %d" % [randi_range(1, 6), randi_range(1, 6)]
		while faces == _dice_label.text:
			faces = "%d  %d" % [randi_range(1, 6), randi_range(1, 6)]
		_dice_label.text = faces
		# Ease out: ticks get longer as the dice settle.
		var tick := TUMBLE_TICK * (1.0 + 3.0 * elapsed / TUMBLE_TIME)
		await get_tree().create_timer(tick).timeout
		elapsed += tick
	_dice_label.text = "%d  %d" % [final_a, final_b]


func _show_outcome(result: Dictionary) -> void:
	_breakdown_label.text = "2d6:  %d + %d  =  %d  vs  %s %d" % [
		result.die_a, result.die_b, result.total,
		str(result.stat).to_upper(), result.target,
	]
	_breakdown_label.visible = true

	if result.crit_success:
		_result_label.text = "SNAKE EYES — AUTOMATIC SUCCESS!"
		_result_label.add_theme_color_override(&"font_color", COLOR_CRIT)
		_dice_label.add_theme_color_override(&"font_color", COLOR_CRIT)
	elif result.crit_fail:
		_result_label.text = "DOUBLE SIX — AUTOMATIC FAILURE!"
		_result_label.add_theme_color_override(&"font_color", COLOR_FAILURE)
		_dice_label.add_theme_color_override(&"font_color", COLOR_FAILURE)
	elif result.success:
		_result_label.text = "SUCCESS"
		_result_label.add_theme_color_override(&"font_color", COLOR_SUCCESS)
		_dice_label.add_theme_color_override(&"font_color", COLOR_SUCCESS)
	else:
		_result_label.text = "FAILURE"
		_result_label.add_theme_color_override(&"font_color", COLOR_FAILURE)
		_dice_label.add_theme_color_override(&"font_color", COLOR_FAILURE)
	_result_label.visible = true
	_continue_button.visible = true
