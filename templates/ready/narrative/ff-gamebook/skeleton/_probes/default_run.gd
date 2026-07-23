extends Node
## res://_probes/default_run.gd
## WINDOWED "play it like a PLAYER" verification of the DEFAULT experience.
## Regression guard for the settings-poisoning defect: probes once persisted forced
## fallback prefs into the shared user://ff_settings.cfg, so a real player on defaults
## got 2D snap dice while probe screenshots showed the 3D tray. This run therefore:
##
##   * NEVER touches FFSettings — it ASSERTS the effective settings ARE the shipped
##     defaults (3D dice ON, animation ON, reduced motion OFF) and fails loudly if a
##     poisoned cfg is loaded;
##   * drives the REAL user flow through the REAL buttons + scene changes:
##     menu "NEW ADVENTURE" → Library (Grey Tithe → Begin) → roll-up (3D bone dice
##     roll the stats) → §1 → pay-in-blood LUCK test (3D) → Harrowfell → the
##     Adventure Sheet → rob Ferrant → COMBAT vs the Cutthroat (3D);
##   * captures what the player actually sees to _probes/shots/:
##     default_rollup.png / default_luck.png / default_sheet.png / default_combat.png,
##     asserting the 3D tray is VISIBLE in every dice moment.
##
##   C:\godot\Godot.exe --path <skeleton> res://_probes/default_run.tscn
##
## Exit 0 = default experience verified 3D; exit 2 = issues (printed).

const OUT_DIR := "res://_probes/shots/"

var _is_driver := false
var issues: Array[String] = []
var notes: Array[String] = []


func _ready() -> void:
	if not _is_driver:
		_bootstrap()


## The probe scene bootstraps: sanity-check the environment, then hand over to a
## driver node parked on /root (it must SURVIVE the real change_scene_to_file flow)
## and enter the game exactly where a player does — the main menu.
func _bootstrap() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("default_run MUST run windowed — it verifies the real default experience")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# --- THE defect check: the settings a real player boots with must BE the defaults.
	var ff := get_node_or_null("/root/FFSettings")
	if ff == null:
		push_error("default_run: FFSettings autoload missing")
		get_tree().quit(2)
		return
	if not (bool(ff.dice_3d) and bool(ff.dice_animation) and not bool(ff.reduced_motion)):
		push_error("default_run: user://ff_settings.cfg is POISONED (dice_3d=%s animation=%s reduced=%s) — a fresh player would NOT get the 3D dice. Delete the cfg / fix the writer." % [ff.dice_3d, ff.dice_animation, ff.reduced_motion])
		print("DEBUG: default_run issues=1 — POISONED SETTINGS, DEFAULT EXPERIENCE IS 2D")
		get_tree().quit(2)
		return

	var driver: Node = get_script().new()
	driver._is_driver = true
	driver.name = "DefaultRunDriver"
	get_tree().root.call_deferred("add_child", driver)
	# enter like a player: the shipped main scene
	get_tree().change_scene_to_file.call_deferred(str(ProjectSettings.get_setting("application/run/main_scene")))


func _enter_tree() -> void:
	if _is_driver:
		_journey.call_deferred()


# --- the journey (real buttons, real scene changes) --------------------------------


func _journey() -> void:
	await _sleep(1.5)

	# 1) MAIN MENU → NEW ADVENTURE
	await _press("NEW ADVENTURE", 15.0)

	# 2) LIBRARY → pick the flagship book, begin
	await _press("Grey Tithe", 15.0)
	await _sleep(0.4)
	await _press("Begin this adventure", 10.0)

	# 3) ROLL-UP — the engine dramatizes the rolled stats through the 3D tray NOW
	await _sleep(1.6)                                   # mid first 3D throw
	_assert_tray("roll-up")
	await _capture("default_rollup.png")
	# let all three stats finish rolling, then finish creation like a player
	await _sleep(9.0)
	await _press("Potion of Fortune", 10.0)
	await _press_enabled("Begin the descent", 20.0)

	# 4) §1 → causeway → toll-bridge → pay in blood → TEST YOUR LUCK (3D)
	await _press("plank causeway", 15.0)
	await _press("Pay in blood", 10.0)
	await _press("Test your Luck", 10.0)
	await _sleep(1.6)                                   # mid 3D luck throw
	_assert_tray("luck test")
	await _capture("default_luck.png")
	await _press_enabled("Tap to continue", 15.0)

	# 5) The Drowned Gate → the Square → open the ADVENTURE SHEET
	await _press("Mother Grissel Thorne sent", 10.0)
	await _sleep(0.6)
	await _press("Sheet", 10.0)
	await _sleep(0.8)
	await _capture("default_sheet.png")
	await _press("✕", 10.0)

	# 6) Ferrant's stall → rob him → COMBAT vs the Cutthroat (3D dice)
	await _press("Cross to Ferrant", 10.0)
	await _press("Try to rob him", 10.0)
	await _sleep(0.8)
	await _press("Attack", 10.0)
	await _sleep(1.6)                                   # mid 3D combat throw
	_assert_tray("combat")
	await _capture("default_combat.png")
	await _press_enabled("Tap to continue", 15.0)

	# 7) play the fight out (decline luck offers; the shots are already taken)
	for _round in 12:
		await _sleep(0.5)
		if _find_button("Yes — Test Luck") != null:
			await _press("No", 5.0)
			continue
		var atk := _find_button("Attack")
		if atk == null:
			break                                       # combat resolved (or death/victory)
		atk.pressed.emit()
		await _press_enabled("Tap to continue", 15.0)

	# --- verdict -----------------------------------------------------------------
	print("DEBUG: default_run WINDOWED — %s" % " · ".join(notes))
	if issues.is_empty():
		print("DEBUG: default_run issues=0 — DEFAULT EXPERIENCE IS THE 3D DICE")
	else:
		print("DEBUG: default_run issues=%d" % issues.size())
		for i in issues:
			print("DEBUG:   ISSUE: %s" % i)
	get_tree().quit(0 if issues.is_empty() else 2)


# --- helpers -----------------------------------------------------------------------


func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## Find a visible, enabled button whose own text OR any descendant Label's text
## contains `needle` (the way a player reads it). Searches the whole window so
## overlays (dice popup CanvasLayer, sheet, combat) are included.
func _find_button(needle: String, require_enabled: bool = true) -> BaseButton:
	return _scan(get_tree().root, needle.to_lower(), require_enabled)


func _scan(node: Node, needle: String, require_enabled: bool) -> BaseButton:
	if node is BaseButton and node.is_visible_in_tree():
		if not (require_enabled and node.disabled):
			if _btn_text(node).to_lower().contains(needle):
				return node
	for c in node.get_children():
		var hit := _scan(c, needle, require_enabled)
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


## Wait for the button to exist + be pressable, then press it (the same signal path a
## real click takes). Records an issue on timeout so the run fails loudly, not silently.
func _press(needle: String, timeout: float) -> void:
	var b := await _wait_button(needle, timeout)
	if b != null:
		b.pressed.emit()


func _press_enabled(needle: String, timeout: float) -> void:
	await _press(needle, timeout)


func _wait_button(needle: String, timeout: float) -> BaseButton:
	var waited := 0.0
	while waited < timeout:
		var b := _find_button(needle)
		if b != null:
			notes.append("pressed '%s'" % needle)
			return b
		await _sleep(0.25)
		waited += 0.25
	issues.append("button '%s' never appeared (%.0fs)" % [needle, timeout])
	return null


## The dice moment MUST be the 3D tray for a defaults player: some visible
## Dice3DTray (SubViewportContainer with a live SubViewport) on screen.
func _assert_tray(where: String) -> void:
	if _find_tray(get_tree().root):
		notes.append("3D tray visible in %s" % where)
	else:
		issues.append("%s: 3D dice tray NOT visible — default experience degraded to 2D" % where)


func _find_tray(node: Node) -> bool:
	if node is SubViewportContainer and node.is_visible_in_tree():
		for c in node.get_children():
			if c is SubViewport:
				return true
	for c in node.get_children():
		if _find_tray(c):
			return true
	return false


func _capture(file_name: String) -> void:
	for _i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + file_name))
	print("DEBUG: default_run wrote %s" % (OUT_DIR + file_name))
