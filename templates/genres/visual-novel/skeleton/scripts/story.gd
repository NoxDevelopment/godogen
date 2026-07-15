extends Node2D
## res://scripts/story.gd
## Story scene: spawns the textbox, starts the intro dialogue, and returns to
## the title screen when the story ends. Backgrounds/portraits go here — the
## textbox purposely stays a separate, reusable scene.

const TITLE_SCENE := "res://scenes/title.tscn"
const TEXTBOX_SCENE := preload("res://scenes/textbox.tscn")
const INTRO_DIALOGUE := preload("res://dialogue/intro.dialogue")


func _ready() -> void:
	# If a VN was exported from the Studio VN Maker (Immersion Engine), play that
	# JSON story instead of the built-in Dialogue Manager demo.
	if FileAccess.file_exists("res://vn/story.vn.json"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/vn_player.tscn")
		return
	_start_story.call_deferred()


func _start_story() -> void:
	var textbox := TEXTBOX_SCENE.instantiate()
	add_child(textbox)
	textbox.dialogue_finished.connect(_on_dialogue_finished)
	textbox.start(INTRO_DIALOGUE, "start")


func _on_dialogue_finished() -> void:
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
