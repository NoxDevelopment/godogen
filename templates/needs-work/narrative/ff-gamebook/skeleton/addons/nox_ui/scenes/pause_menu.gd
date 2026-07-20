extends CanvasLayer
## NoxDev drop-in pause overlay (FF-gamebook vendored copy). Add as a child of any
## gameplay scene; it toggles on the "ui_cancel" action (Esc) and pauses the tree.
## Phase-7 polish (GDD §6.1 #17): Resume / Options / Save / Quit-to-menu / Quit.
## Options and Save open overlays that process while the tree is paused.

const OPTIONS_VIEW := preload("res://scripts/screens/options_view.gd")
const LOAD_SCREEN := preload("res://addons/loading/load_screen.tscn")

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Dim.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	var showing: bool = not $Dim.visible
	$Dim.visible = showing
	get_tree().paused = showing
	if showing:
		$Dim/Panel/VBox/Resume.grab_focus()

func _on_resume_pressed() -> void: toggle()

func _on_options_pressed() -> void:
	add_child(OPTIONS_VIEW.new())

func _on_save_pressed() -> void:
	var ls := LOAD_SCREEN.instantiate()
	ls.mode = 1   # load_screen.Mode.SAVE
	add_child(ls)

func _on_menu_pressed() -> void: NoxShell.to_menu()
func _on_quit_pressed() -> void: NoxShell.quit_game()
