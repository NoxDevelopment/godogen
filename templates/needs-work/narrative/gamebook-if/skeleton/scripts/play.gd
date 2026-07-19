extends Control
## res://scripts/play.gd
## THE play scene — the whole playable gamebook page, driven entirely by the
## PlaySession bridge over the computed nox_if_engine. It renders the current
## passage (illustration plate + title + text), builds CHOICE BUTTONS from the
## engine's condition-gated choices, surfaces the resolver's dice rolls in the
## tray, and shows a live adventure sheet + inventory HUD built from the ruleset's
## sheetTemplate. It never owns story state — it reads PlaySession and reacts.
##
## Works for BOTH flows unchanged: a one-off ends and returns to the title; a
## campaign ends a MODULE and offers to continue to the next chapter (or ends the
## campaign). No AI is involved — the AiDm seam is inert; this plays 100%
## computed. Run this scene directly (F5) and it starts the sample one-off.

const TITLE_SCENE := "res://scenes/title.tscn"
const DICE_POPUP := preload("res://scenes/dice_roll_popup.tscn")

@onready var _plate: PanelContainer = $Page/Margin/Rows/Plate
@onready var _title_label: Label = $Page/Margin/Rows/TitleLabel
@onready var _passage_text: RichTextLabel = $Page/Margin/Rows/PassageText
@onready var _choices: VBoxContainer = $Page/Margin/Rows/Choices
@onready var _interstitial: VBoxContainer = $Page/Margin/Rows/Interstitial
@onready var _interstitial_label: Label = $Page/Margin/Rows/Interstitial/InterstitialLabel
@onready var _interstitial_button: Button = $Page/Margin/Rows/Interstitial/InterstitialButton
@onready var _stats_label: Label = $SheetBar/Margin/Columns/StatsLabel
@onready var _inventory_label: Label = $SheetBar/Margin/Columns/InventoryLabel
@onready var _save_button: Button = $TopBar/SaveButton
@onready var _menu_button: Button = $TopBar/MenuButton
@onready var _toast: Label = $Toast

var _busy := false
## The handler currently wired to the interstitial button (so we can cleanly
## rebind it each time the interstitial is shown for a different transition).
var _interstitial_handler: Callable = Callable()

## AI-DM (slice 2) DISPLAY-ONLY narration. A separate label under the computed
## passage text that shows async LLM flavour prose ALONGSIDE (never instead of)
## `passage.text`. Built in code so the scene file and the computed render path
## are untouched; stays hidden/empty unless AiDm.enabled AND prose arrives. The
## id of the passage currently on screen, so a late/stale narration for a passage
## the player already left is discarded.
var _ai_narration: RichTextLabel
var _current_passage_id: String = ""


func _ready() -> void:
	_save_button.pressed.connect(_on_save_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_toast.hide()
	_interstitial.hide()
	_build_ai_narration_label()
	AiDm.narration_ready.connect(_on_narration_ready)
	# Run-scene-directly convenience: if nothing launched us, start the sample.
	if PlaySession.mode == "":
		PlaySession.begin_oneoff_scenario(PlaySession.SCENARIO_THORNWOOD, 20260715)
	render()


# --- rendering --------------------------------------------------------------


func render() -> void:
	var passage := PlaySession.current_passage()
	if passage.is_empty():
		# A loaded between-modules campaign save: no live passage — offer to
		# start the next chapter.
		_reset_ai_narration("")
		_show_body("Chapter Complete", "The next chapter of your campaign awaits.")
		_plate.bind_passage("_boundary", "Next Chapter")
		_refresh_sheet()
		if PlaySession.is_between_modules():
			_show_interstitial("Continue to the next chapter.", _on_continue_campaign)
		else:
			_show_interstitial("Return to the title.", _on_return_title)
		return

	_show_body(str(passage.get("title", "")), str(passage.get("text", "")))
	_plate.bind_passage(str(passage.get("id", "")), str(passage.get("title", "")))
	_refresh_sheet()
	# AI-DM (slice 2): DISPLAY-ONLY. The computed passage above is already fully
	# rendered; if the optional AI layer is enabled, ask for async flavour prose to
	# append underneath (arrives later via `narration_ready`). Off by default => no
	# request, no network, byte-identical render.
	_reset_ai_narration(str(passage.get("id", "")))
	if AiDm.enabled:
		AiDm.request_narration(passage, PlaySession.active_state())

	if PlaySession.is_ended():
		# Terminal: render the ending prose, then a return button.
		_end_line_for(passage)
		_show_interstitial("Return to the title.", _on_return_title)
	elif passage.has("ending"):
		# A module ending inside a campaign that continues.
		_end_line_for(passage)
		_show_interstitial("Continue to the next chapter.", _on_continue_campaign)
	else:
		_show_choices()


func _show_body(title: String, text: String) -> void:
	_title_label.text = title
	_title_label.visible = not title.is_empty()
	_passage_text.text = text


# --- AI-DM narration (slice 2, DISPLAY-ONLY) --------------------------------


## Build the AI flavour label in code, directly under the computed PassageText, so
## the scene file and the computed render path are never edited. Starts hidden.
func _build_ai_narration_label() -> void:
	_ai_narration = RichTextLabel.new()
	_ai_narration.name = "AiNarration"
	_ai_narration.bbcode_enabled = true
	_ai_narration.fit_content = true
	_ai_narration.scroll_active = false
	_ai_narration.add_to_group(&"scalable_text")
	_ai_narration.hide()
	var rows := $Page/Margin/Rows
	rows.add_child(_ai_narration)
	rows.move_child(_ai_narration, _passage_text.get_index() + 1)


## Clear + hide the AI prose and record which passage is on screen now, so a stale
## async narration for a passage the player already left is discarded on arrival.
func _reset_ai_narration(passage_id: String) -> void:
	_current_passage_id = passage_id
	if _ai_narration != null:
		_ai_narration.text = ""
		_ai_narration.hide()


## Async arrival of AI flavour prose. Purely additive: append it UNDER the computed
## passage text, clearly marked as AI flavour. Ignore empty prose (the inert /
## failure result) and any narration whose passage the player already left.
func _on_narration_ready(passage_id: String, text: String) -> void:
	if _ai_narration == null or not AiDm.enabled:
		return
	if text.is_empty() or passage_id != _current_passage_id:
		return
	_ai_narration.text = "[i][color=#9a8f7a]%s[/color][/i]" % text
	_ai_narration.show()


func _end_line_for(passage: Dictionary) -> void:
	var ending: Dictionary = passage.get("ending", {})
	var label := str(ending.get("label", ""))
	var kind := str(ending.get("kind", ""))
	if label != "":
		_title_label.text = "%s — %s" % [str(passage.get("title", "")), label]
	if kind != "":
		_passage_text.text += "\n\n[ %s ]" % kind.to_upper()


func _show_choices() -> void:
	_interstitial.hide()
	_clear_choices()
	_choices.show()
	for ch in PlaySession.available_choices():
		var btn := Button.new()
		btn.text = str(ch.get("text", ch.get("id", "…")))
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_to_group(&"scalable_text")
		var cid := str(ch.get("id", ""))
		btn.pressed.connect(func() -> void: _on_choice(cid))
		_choices.add_child(btn)
	if _choices.get_child_count() > 0:
		(_choices.get_child(0) as Button).grab_focus()


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()


func _show_interstitial(button_text: String, handler: Callable) -> void:
	_clear_choices()
	_choices.hide()
	_interstitial.show()
	_interstitial_label.text = "The adventure reaches a resolution."
	_interstitial_button.text = button_text
	# Rebind the single button to the given handler (drop the previous one).
	if _interstitial_handler.is_valid() and _interstitial_button.pressed.is_connected(_interstitial_handler):
		_interstitial_button.pressed.disconnect(_interstitial_handler)
	_interstitial_handler = handler
	_interstitial_button.pressed.connect(handler)
	_interstitial_button.grab_focus()


func _refresh_sheet() -> void:
	var view := PlaySession.sheet_view()
	var parts: Array = []
	for a in view.get("attributes", []):
		parts.append("%s %d" % [str(a.get("label")), int(a.get("value"))])
	for r in view.get("resources", []):
		if r.get("max") != null:
			parts.append("%s %d/%d" % [str(r.get("label")), int(r.get("value")), int(r.get("max"))])
		else:
			parts.append("%s %d" % [str(r.get("label")), int(r.get("value"))])
	_stats_label.text = "   ".join(parts)

	var inv: Dictionary = view.get("inventory", {})
	if inv.is_empty():
		_inventory_label.text = "Inventory: (empty)"
	else:
		var items: Array = []
		for name in inv.keys():
			var count := int(inv[name])
			items.append(str(name) if count == 1 else "%s x%d" % [str(name), count])
		_inventory_label.text = "Inventory: %s" % ", ".join(items)


# --- taking a choice --------------------------------------------------------


func _on_choice(choice_id: String) -> void:
	if _busy:
		return
	_busy = true
	_set_choices_enabled(false)
	var report := PlaySession.choose(choice_id)
	# Surface each dice check resolved during this turn, in the tray, in order.
	for roll in report.get("rolls", []):
		await _show_dice_tray(roll)
	render()
	_busy = false


func _show_dice_tray(result: Dictionary) -> void:
	var popup := DICE_POPUP.instantiate()
	get_tree().root.add_child(popup)
	await popup.run(result)
	popup.queue_free()


func _set_choices_enabled(enabled: bool) -> void:
	for c in _choices.get_children():
		if c is Button:
			(c as Button).disabled = not enabled


# --- interstitial / navigation ----------------------------------------------


func _on_continue_campaign() -> void:
	PlaySession.advance_campaign_module()
	render()


func _on_return_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _on_save_pressed() -> void:
	var ok := PlaySession.save_game()
	_flash_toast("Saved." if ok else "Save failed.")


func _flash_toast(text: String) -> void:
	_toast.text = text
	_toast.show()
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(_toast):
		_toast.hide()
