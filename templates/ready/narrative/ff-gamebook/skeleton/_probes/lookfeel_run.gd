extends Node
## res://_probes/lookfeel_run.gd
## WINDOWED look-and-feel capture (LOOKFEEL_PASS_2026-07 §verification): plays the
## real default flow like a player and captures the judged surfaces to
## _probes/shots/lookfeel_*.png — menu, roll-up ritual (mid 3D throw), reading
## page (large plate + sheet dock), the journey map, the full Adventure Sheet,
## and the combat page. Non-invasive: real buttons, real scene changes, never
## touches FFSettings. Run:
##   C:\godot\Godot.exe --path <skeleton> res://_probes/lookfeel_run.tscn
## Exit 0 = all captured; exit 2 = a step failed (printed).

const OUT_DIR := "res://_probes/shots/"

var _is_driver := false
var issues: Array[String] = []


func _ready() -> void:
	if not _is_driver:
		_bootstrap()


func _bootstrap() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("lookfeel_run MUST run windowed — it captures the real presentation")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var driver: Node = get_script().new()
	driver._is_driver = true
	driver.name = "LookfeelRunDriver"
	get_tree().root.call_deferred("add_child", driver)
	get_tree().change_scene_to_file.call_deferred(str(ProjectSettings.get_setting("application/run/main_scene")))


func _enter_tree() -> void:
	if _is_driver:
		_journey.call_deferred()


func _journey() -> void:
	await _sleep(1.6)
	await _capture("lookfeel_menu.png")

	# library → the flagship → roll-up ritual (capture mid first 3D throw)
	await _press("NEW ADVENTURE", 15.0)
	await _press("Grey Tithe", 15.0)
	await _sleep(0.4)
	await _press("Begin this adventure", 10.0)
	await _sleep(1.6)
	await _capture("lookfeel_rollup.png")
	await _sleep(9.0)
	await _capture("lookfeel_rollup_done.png")
	await _press("Potion of Fortune", 10.0)
	await _press("Begin the descent", 20.0)

	# §1 reading page — the large plate + the sheet dock
	await _sleep(1.0)
	await _capture("lookfeel_reading.png")

	# the journey map (walk two sections first so a route is inked)
	await _press("plank causeway", 15.0)
	await _sleep(0.6)
	await _press("Map", 10.0)
	await _sleep(0.8)
	await _capture("lookfeel_map.png")
	await _press("✕", 10.0)

	# the full Adventure Sheet
	await _press("Sheet", 10.0)
	await _sleep(0.8)
	await _capture("lookfeel_sheet.png")
	await _press("✕", 10.0)

	# on to the toll-bridge fight: pay in blood → luck test → onward to combat
	await _press("Pay in blood", 10.0)
	await _press("Test your Luck", 10.0)
	await _sleep(1.4)
	await _capture("lookfeel_dice.png")
	await _press_enabled("Tap to continue", 15.0)
	await _press("Mother Grissel Thorne sent", 10.0)
	await _press("Cross to Ferrant", 10.0)
	await _press("Try to rob him", 10.0)
	await _sleep(0.8)
	await _press("Attack", 10.0)
	await _sleep(2.9)                       # after the throw — math + banner printed
	await _capture("lookfeel_combat.png")

	print("DEBUG: lookfeel_run issues=%d" % issues.size())
	for i in issues:
		print("DEBUG:   ISSUE: %s" % i)
	get_tree().quit(0 if issues.is_empty() else 2)


# --- helpers (the default_run vocabulary) -----------------------------------


func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _find_button(needle: String) -> BaseButton:
	return _scan(get_tree().root, needle.to_lower())


func _scan(node: Node, needle: String) -> BaseButton:
	if node is BaseButton and node.is_visible_in_tree() and not node.disabled:
		if _btn_text(node).to_lower().contains(needle):
			return node
	for c in node.get_children():
		var hit := _scan(c, needle)
		if hit != null:
			return hit
	return null


func _btn_text(b: BaseButton) -> String:
	var out: String = (b as Button).text if b is Button else ""
	var stack: Array[Node] = [b]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out += " " + n.text
		for c in n.get_children():
			stack.push_back(c)
	return out


func _press(needle: String, timeout: float) -> void:
	var waited := 0.0
	while waited < timeout:
		var b := _find_button(needle)
		if b != null:
			b.pressed.emit()
			return
		await _sleep(0.25)
		waited += 0.25
	issues.append("button '%s' never appeared (%.0fs)" % [needle, timeout])


func _press_enabled(needle: String, timeout: float) -> void:
	await _press(needle, timeout)


func _capture(file_name: String) -> void:
	for _i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + file_name))
	print("DEBUG: lookfeel_run wrote %s" % (OUT_DIR + file_name))
