extends Node
## ContinueService — autoload. Resume-last ("Continue"): jump back into the newest
## save without the slot picker. Depends on SaveManager (save-system) for slot data
## and SceneLoader for the transition. Autoload as "ContinueService".
##
## Wire the nox_ui menu (main_menu.gd) — by default its Continue button starts a
## NEW game, which is wrong. Replace those two lines with:
##   _continue.visible = ContinueService.has_resumable()
##   func _on_continue_pressed() -> void: ContinueService.resume_last()

func has_resumable() -> bool:
	if get_node_or_null("/root/SaveManager") == null:
		return false
	for s in SaveManager.list_slots():
		if s.get("exists", false):
			return true
	return false

func latest_slot() -> int:
	var best := -1
	var best_time := -1.0
	for s in SaveManager.list_slots():
		if not s.get("exists", false):
			continue
		var t: float = float(s.get("modified_time", 0))
		if t > best_time:
			best_time = t
			best = int(s.get("slot", -1))
	return best

func resume_last() -> void:
	var slot := latest_slot()
	if slot < 0:
		push_warning("ContinueService: nothing to resume")
		return
	var data = SaveManager.load_from_slot(slot)
	if data == null:
		push_error("ContinueService: failed to load slot %d" % slot)
		return
	# SaveData carries the scene to return to (topdown/rpg presets: scene_path).
	var target: String = data.scene_path if "scene_path" in data else ""
	if target == "" or not ResourceLoader.exists(target):
		push_error("ContinueService: save has no valid scene_path")
		return
	if get_node_or_null("/root/SceneLoader") != null:
		SceneLoader.change_scene(target)
	else:
		get_tree().change_scene_to_file(target)
	# Gameplay scene reads SaveManager's loaded data on _ready to restore state.
