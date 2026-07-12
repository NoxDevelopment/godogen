extends Control
## res://scripts/book.gd
## The illustrated page — classic Fighting Fantasy presentation: the passage's
## illustration plate on top, the passage text beneath it, "turn to N" choice
## buttons under the text, the adventure-sheet bar along the bottom, and the
## dice tray rolling over everything when a test comes up. One scene IS the
## whole book: Dialogue Manager walks dialogue/book.dialogue, every passage's
## opening mutation routes through SessionState.advance_passage() (the
## multiplayer sync point), and the page reacts to SessionState signals only —
## it never owns story state itself.

const TITLE_SCENE := "res://scenes/title.tscn"
const BOOK_DIALOGUE := preload("res://dialogue/book.dialogue")

## The action that advances a finished line.
@export var next_action: StringName = &"ui_accept"
## The action that skips the typewriter effect.
@export var skip_action: StringName = &"ui_cancel"

var dialogue_resource: DialogueResource
var is_waiting_for_input := false

var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			_apply_dialogue_line()
		else:
			_on_book_finished()
	get:
		return dialogue_line

@onready var _page: PanelContainer = $Page
@onready var _plate = $Page/Margin/Rows/Plate
@onready var _character_label: Label = $Page/Margin/Rows/CharacterLabel
@onready var _dialogue_label: DialogueLabel = $Page/Margin/Rows/DialogueLabel
@onready var _responses_menu: DialogueResponsesMenu = $Page/Margin/Rows/Responses
@onready var _stats_label: Label = $SheetBar/Margin/Columns/StatsLabel
@onready var _inventory_label: Label = $SheetBar/Margin/Columns/InventoryLabel
@onready var _page_turn: AudioStreamPlayer = $PageTurnPlayer


func _ready() -> void:
	Sheet.stats_changed.connect(_refresh_sheet)
	Sheet.inventory_changed.connect(func(_items: Array) -> void: _refresh_sheet())
	Sheet.died.connect(_on_died)
	SessionState.passage_changed.connect(_on_passage_changed)
	DialogueManager.mutated.connect(_on_mutated)
	_responses_menu.response_selected.connect(_on_response_selected)
	if _responses_menu.next_action.is_empty():
		_responses_menu.next_action = next_action
	_page_turn.stream = AssetBinder.get_stream("audio/page_turn")
	_apply_page_chrome()
	_refresh_sheet()
	_character_label.hide()
	_responses_menu.hide()
	_start_book.call_deferred()


func _start_book() -> void:
	dialogue_resource = BOOK_DIALOGUE
	dialogue_line = await dialogue_resource.get_next_dialogue_line("passage_1")


func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id)


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(dialogue_line):
		return

	# Skip the typewriter effect.
	if _dialogue_label.is_typing:
		var clicked: bool = event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		if clicked or event.is_action_pressed(skip_action):
			get_viewport().set_input_as_handled()
			_dialogue_label.skip_typing()
		return

	if not is_waiting_for_input or dialogue_line.responses.size() > 0:
		return

	if (event is InputEventMouseButton and event.is_pressed()
			and event.button_index == MOUSE_BUTTON_LEFT) \
			or event.is_action_pressed(next_action):
		get_viewport().set_input_as_handled()
		is_waiting_for_input = false
		next(dialogue_line.next_id)


func _apply_dialogue_line() -> void:
	is_waiting_for_input = false

	_character_label.visible = not dialogue_line.character.is_empty()
	_character_label.text = tr(dialogue_line.character, &"dialogue")

	_dialogue_label.hide()
	_dialogue_label.dialogue_line = dialogue_line

	_responses_menu.hide()
	_responses_menu.responses = dialogue_line.responses

	_dialogue_label.show()
	if not dialogue_line.text.is_empty():
		_dialogue_label.type_out()
		await _dialogue_label.finished_typing

	if dialogue_line.responses.size() > 0:
		_responses_menu.show()
	elif dialogue_line.time != "":
		var time := dialogue_line.text.length() * 0.02 \
				if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true


## Bind the "ui/page_frame" manifest slot: generated page art when it exists,
## otherwise the slot's placeholder parchment tint on the page panel.
func _apply_page_chrome() -> void:
	var art := AssetBinder.get_texture("ui/page_frame")
	if art != null:
		var rect := TextureRect.new()
		rect.texture = art
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(rect)
		_page.move_child(rect, 0)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = AssetBinder.placeholder_color("ui/page_frame")
		style.set_corner_radius_all(6)
		style.set_border_width_all(2)
		style.border_color = Color(0.62, 0.55, 0.42, 0.5)
		_page.add_theme_stylebox_override(&"panel", style)


func _refresh_sheet() -> void:
	_stats_label.text = "SKILL %d/%d   STAMINA %d/%d   LUCK %d/%d   Provisions %d" % [
		Sheet.skill, Sheet.max_skill,
		Sheet.stamina, Sheet.max_stamina,
		Sheet.luck, Sheet.max_luck,
		Sheet.provisions,
	]
	_inventory_label.text = "Inventory: %s" % (
		", ".join(Sheet.inventory) if not Sheet.inventory.is_empty() else "(empty)"
	)


func _on_passage_changed(passage_id: String) -> void:
	_plate.bind_passage(passage_id)
	if _page_turn.stream != null:
		_page_turn.play()


func _on_mutated(_mutation: Dictionary) -> void:
	# A long mutation (the dice tray) is running — stop accepting advances
	# until the next line lands.
	is_waiting_for_input = false


func _on_response_selected(response) -> void:
	# Choices route through SessionState — the future host-arbitration point.
	next(SessionState.choose(response.next_id, response.text))


func _on_died() -> void:
	# STAMINA hit zero — the adventure is over (gamebook rules are unforgiving).
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)


func _on_book_finished() -> void:
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
