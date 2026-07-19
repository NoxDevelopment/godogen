extends CanvasLayer
## res://scripts/dice_roll_popup.gd
## The dice tray: dims the page, tumbles the dice, settles on the resolver's
## rolled faces, shows the breakdown and the outcome BAND, then waits for the
## player to confirm. Driven by a single nox_if_engine resolution result (an
## entry from IFState.roll_log) so it is ruleset-AGNOSTIC — it renders a
## roll-under 2d6 test, a d20 meet-or-beat check, or a PbtA threshold-band move
## from the same fields. The tray panel is a bound UI slot ("ui/dice_tray"):
## a placeholder leather tint until the Studio asset board generates tray art.
##
## Result shape (see if_resolver.gd): { label, dice, faces:[...], sum, modifier,
## total, target (or null), compare, success (bool|null), crit, band, band_label }

signal finished

const TUMBLE_TIME := 0.7
const TUMBLE_TICK := 0.05
const COLOR_SUCCESS := Color(0.42, 0.78, 0.44)
const COLOR_FAILURE := Color(0.85, 0.38, 0.38)
const COLOR_PARTIAL := Color(0.95, 0.74, 0.36)
const COLOR_CRIT := Color(0.98, 0.83, 0.37)

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title_label: Label = $Center/Panel/Margin/Rows/TitleLabel
@onready var _dice_label: Label = $Center/Panel/Margin/Rows/DiceLabel
@onready var _breakdown_label: Label = $Center/Panel/Margin/Rows/BreakdownLabel
@onready var _result_label: Label = $Center/Panel/Margin/Rows/ResultLabel
@onready var _continue_button: Button = $Center/Panel/Margin/Rows/ContinueButton


func _ready() -> void:
	_apply_tray_chrome()


## Play the whole tray flow for one resolution result. Await this.
func run(result: Dictionary) -> void:
	var faces := _faces(result)
	_title_label.text = str(result.get("label", "Test")).to_upper()
	_breakdown_label.visible = false
	_result_label.visible = false
	_continue_button.visible = false

	await _tumble(faces)
	_show_outcome(result, faces)

	_continue_button.grab_focus()
	await _continue_button.pressed
	finished.emit()


## Bind the "ui/dice_tray" manifest slot: generated tray art when it exists,
## otherwise the slot's placeholder tint on the panel.
func _apply_tray_chrome() -> void:
	var art := AssetBinder.get_texture("ui/dice_tray")
	if art != null:
		var rect := TextureRect.new()
		rect.texture = art
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(rect)
		_panel.move_child(rect, 0)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = AssetBinder.placeholder_color("ui/dice_tray")
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = Color(0.75, 0.68, 0.5, 0.55)
		_panel.add_theme_stylebox_override(&"panel", style)


func _faces(result: Dictionary) -> Array:
	var out: Array = []
	for f in result.get("faces", []):
		out.append(int(f))
	if out.is_empty():
		out.append(int(result.get("sum", result.get("total", 0))))
	return out


func _faces_text(faces: Array) -> String:
	var parts: Array = []
	for f in faces:
		parts.append(str(int(f)))
	return "  ".join(parts)


func _tumble(final_faces: Array) -> void:
	var n := final_faces.size()
	var elapsed := 0.0
	while elapsed < TUMBLE_TIME:
		var rolling: Array = []
		for i in range(n):
			rolling.append(randi_range(1, 6))
		var text := _faces_text(rolling)
		if text != _dice_label.text:
			_dice_label.text = text
		var tick := TUMBLE_TICK * (1.0 + 3.0 * elapsed / TUMBLE_TIME)
		await get_tree().create_timer(tick).timeout
		elapsed += tick
	_dice_label.text = _faces_text(final_faces)


func _show_outcome(result: Dictionary, faces: Array) -> void:
	var total := int(result.get("total", result.get("sum", 0)))
	var modifier := int(result.get("modifier", 0))
	var compare := str(result.get("compare", ""))
	var target: Variant = result.get("target", null)

	var line := "%s" % _faces_text(faces)
	if modifier != 0:
		line += "  %s%d" % ["+" if modifier > 0 else "-", abs(modifier)]
	line += "  =  %d" % total
	match compare:
		"roll-under":
			line += "   vs  %s (roll under)" % _target_text(target)
		"meet-or-beat":
			line += "   vs  %s (meet or beat)" % _target_text(target)
		"threshold-bands":
			line += "   →  bands"
		_:
			if target != null:
				line += "   vs  %s" % _target_text(target)
	_breakdown_label.text = line
	_breakdown_label.visible = true

	var verdict := str(result.get("band_label", result.get("band", "")))
	var crit := str(result.get("crit", ""))
	if crit == "success":
		verdict = "CRITICAL — " + verdict
	elif crit == "fail":
		verdict = "FUMBLE — " + verdict
	_result_label.text = verdict.to_upper()
	_result_label.add_theme_color_override(&"font_color", _band_color(result))
	_dice_label.add_theme_color_override(&"font_color", _band_color(result))
	_result_label.visible = true
	_continue_button.visible = true


func _target_text(target: Variant) -> String:
	if target == null:
		return "?"
	return str(int(round(float(target))))


func _band_color(result: Dictionary) -> Color:
	var crit := str(result.get("crit", ""))
	if crit == "success":
		return COLOR_CRIT
	if crit == "fail":
		return COLOR_FAILURE
	var band := str(result.get("band", "")).to_lower()
	if band.contains("partial"):
		return COLOR_PARTIAL
	var success: Variant = result.get("success", null)
	if success == true:
		return COLOR_SUCCESS
	if success == false:
		return COLOR_FAILURE
	# threshold-bands (success == null): colour by band name.
	if band.contains("full") or band.contains("success") or band.contains("won"):
		return COLOR_SUCCESS
	if band.contains("miss") or band.contains("fail"):
		return COLOR_FAILURE
	return COLOR_PARTIAL
