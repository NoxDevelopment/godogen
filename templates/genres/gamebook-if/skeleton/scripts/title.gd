extends Control
## res://scripts/title.gd
## Title screen: pick a flow and open the play scene. Two DISTINCT flows over the
## same computed engine — a one-off (played straight to an ending) and a campaign
## (linked modules with carried state + save/resume between them) — plus Continue
## (load the last save). Every button hands off to PlaySession, which owns the
## engine; the title never touches a runner directly.

const PLAY_SCENE := "res://scenes/play.tscn"

@onready var _oneoff_button: Button = $Center/Rows/OneOffButton
@onready var _campaign_button: Button = $Center/Rows/CampaignButton
@onready var _continue_button: Button = $Center/Rows/ContinueButton
@onready var _quit_button: Button = $Center/Rows/QuitButton


func _ready() -> void:
	_oneoff_button.pressed.connect(_on_oneoff_pressed)
	_campaign_button.pressed.connect(_on_campaign_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_continue_button.disabled = not PlaySession.has_save()
	_oneoff_button.grab_focus()


func _on_oneoff_pressed() -> void:
	GameManager.launch_kind = "oneoff"
	# A fresh seed per new adventure so dice differ each play (the fixed sheet
	# override means only the dice vary). The boot probe pins the seed instead.
	PlaySession.begin_oneoff_scenario(PlaySession.SCENARIO_THORNWOOD, randi())
	get_tree().change_scene_to_file(PLAY_SCENE)


func _on_campaign_pressed() -> void:
	GameManager.launch_kind = "campaign"
	PlaySession.begin_campaign_file(PlaySession.CAMPAIGN_CROWN)
	get_tree().change_scene_to_file(PLAY_SCENE)


func _on_continue_pressed() -> void:
	if PlaySession.load_game():
		GameManager.launch_kind = "continue"
		get_tree().change_scene_to_file(PLAY_SCENE)
	else:
		_continue_button.disabled = true
