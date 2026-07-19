extends Control
## res://scripts/title.gd
## Title screen: Begin Adventure rolls a fresh adventure sheet and starts the
## book. Also emits the boot probe proving the core loop exists: keyed
## passages resolve (passage_1 and a jump target both yield lines), a 2d6
## stat test rolls against the sheet, and an item pickup lands in the
## inventory LIST.

const STORY_SCENE := "res://scenes/story.tscn"
const BOOK_DIALOGUE := "res://dialogue/book.dialogue"

@onready var _begin_button: Button = $Center/Rows/BeginButton
@onready var _quit_button: Button = $Center/Rows/QuitButton


func _ready() -> void:
	_begin_button.pressed.connect(_on_begin_pressed)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_begin_button.grab_focus()
	_emit_boot_probe.call_deferred()


func _on_begin_pressed() -> void:
	Sheet.roll_new_character()
	get_tree().change_scene_to_file(STORY_SCENE)


func _emit_boot_probe() -> void:
	Sheet.roll_new_character()
	var resource: DialogueResource = load(BOOK_DIALOGUE)
	# Keyed passages: the opening passage and a jump target both resolve.
	var first_line: DialogueLine = await resource.get_next_dialogue_line("passage_1")
	var jump_line: DialogueLine = await resource.get_next_dialogue_line("passage_7")
	var passage_jump := first_line != null and jump_line != null
	# Stat check: pure 2d6 roll-under against the sheet (no popup).
	var check := Dice.roll_test("skill")
	# Item pickup: into the inventory LIST and back out.
	Sheet.add_item("brass key")
	var item_pickup := Sheet.has_item("brass key")
	print("DEBUG: gamebook core loop ready — passage_jump=%s (1: \"%s\" / 7: \"%s\") skill_test(2d6=%d vs SKILL %d -> %s) item_pickup=%s sheet=[SKILL %d, STAMINA %d, LUCK %d] inventory=%s" % [
		passage_jump,
		first_line.text.substr(0, 24) if first_line else "?",
		jump_line.text.substr(0, 24) if jump_line else "?",
		check.total, check.target, check.success,
		item_pickup, Sheet.skill, Sheet.stamina, Sheet.luck, Sheet.inventory,
	])
	# Leave the real adventure untouched.
	Sheet.roll_new_character()
