extends CanvasLayer
## NoxDev drop-in pause overlay. Add as a child of any gameplay scene; it toggles
## on the "ui_cancel" action (Esc) and pauses the tree. Resume / Main Menu / Quit.

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Dim.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	var showing := not $Dim.visible
	$Dim.visible = showing
	get_tree().paused = showing
	if showing:
		$Dim/Panel/VBox/Resume.grab_focus()

func _on_resume_pressed() -> void: toggle()
func _on_menu_pressed() -> void: NoxShell.to_menu()
func _on_quit_pressed() -> void: NoxShell.quit_game()
