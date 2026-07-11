extends Control
## res://scripts/title.gd
## Title screen: Begin starts the story scene. Also emits the boot probe
## proving the core loop exists: the compiled dialogue resource yields its
## first line and the dice layer rolls.

const STORY_SCENE := "res://scenes/story.tscn"
const INTRO_DIALOGUE := "res://dialogue/intro.dialogue"

@onready var _begin_button: Button = $Center/Rows/BeginButton
@onready var _quit_button: Button = $Center/Rows/QuitButton


func _ready() -> void:
	_begin_button.pressed.connect(_on_begin_pressed)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_begin_button.grab_focus()
	_emit_boot_probe.call_deferred()


func _on_begin_pressed() -> void:
	get_tree().change_scene_to_file(STORY_SCENE)


func _emit_boot_probe() -> void:
	var resource: DialogueResource = load(INTRO_DIALOGUE)
	var first_line: DialogueLine = await resource.get_next_dialogue_line("start")
	var check := SkillCheck.roll("mind", 12)
	print("DEBUG: visual-novel core loop ready — first_line=\"%s: %s\" skill_check(d20=%d%+d=%d vs DC %d -> %s)" % [
		first_line.character, first_line.text,
		check.die, check.modifier, check.total, check.dc, check.success,
	])
