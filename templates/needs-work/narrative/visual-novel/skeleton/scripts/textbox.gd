extends CanvasLayer
## res://scripts/textbox.gd
## VN textbox: bottom-anchored dialogue panel driving a Dialogue Manager
## resource — name plate, typed-out text (DialogueLabel), response menu,
## click / ui_accept to advance, ui_cancel (or click while typing) to skip.
## Hides itself while long mutations (like the dice popup) run.

signal dialogue_finished

## The action that advances dialogue.
@export var next_action: StringName = &"ui_accept"
## The action that skips the typewriter effect.
@export var skip_action: StringName = &"ui_cancel"

var dialogue_resource: DialogueResource
var temporary_game_states: Array = []
var is_waiting_for_input := false

var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			_apply_dialogue_line()
		else:
			dialogue_finished.emit()
			queue_free()
	get:
		return dialogue_line

@onready var _panel: Control = $Root/Panel
@onready var _character_label: Label = $Root/Panel/Margin/Rows/CharacterLabel
@onready var _dialogue_label: DialogueLabel = $Root/Panel/Margin/Rows/DialogueLabel
@onready var _responses_menu: DialogueResponsesMenu = $Root/Responses


func _ready() -> void:
	_panel.hide()
	_responses_menu.hide()
	DialogueManager.mutated.connect(_on_mutated)
	_responses_menu.response_selected.connect(_on_response_selected)
	if _responses_menu.next_action.is_empty():
		_responses_menu.next_action = next_action


## Start a dialogue at a title. The textbox frees itself when the story ends.
func start(resource: DialogueResource, title: String, extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	dialogue_resource = resource
	dialogue_line = await resource.get_next_dialogue_line(title, temporary_game_states)


func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


func _apply_dialogue_line() -> void:
	is_waiting_for_input = false

	_character_label.visible = not dialogue_line.character.is_empty()
	_character_label.text = tr(dialogue_line.character, &"dialogue")

	_dialogue_label.hide()
	_dialogue_label.dialogue_line = dialogue_line

	_responses_menu.hide()
	_responses_menu.responses = dialogue_line.responses

	_panel.show()
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


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(dialogue_line):
		return

	# Skip the typewriter effect.
	if _dialogue_label.is_typing:
		var clicked := event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		if clicked or event.is_action_pressed(skip_action):
			get_viewport().set_input_as_handled()
			_dialogue_label.skip_typing()
		return

	if not is_waiting_for_input or dialogue_line.responses.size() > 0:
		return

	if event is InputEventMouseButton and event.is_pressed() \
			and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action):
		get_viewport().set_input_as_handled()
		next(dialogue_line.next_id)


func _on_mutated(_mutation: Dictionary) -> void:
	# A long mutation (dice popup, animation) is running: get out of the way.
	is_waiting_for_input = false
	_panel.hide()
	_responses_menu.hide()


func _on_response_selected(response) -> void:
	next(response.next_id)
