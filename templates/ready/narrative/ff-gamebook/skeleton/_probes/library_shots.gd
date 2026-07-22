extends Node
## res://_probes/library_shots.gd
## Adventure-ecosystem drop-1 WINDOWED probe: boots the Library bookshelf and the
## new book's opening page into a real 1280x720 SubViewport, audits both for the
## unreachable/unwired-button bug class (same audit as qa_probe), and screenshots:
##   _probes/shots/qa_library.png    — the Library with both books + reading desk
##   _probes/shots/qa_adv2_open.png  — The Wrecker's Light, §w1, plate bound
## Run: godot --path <skeleton> res://_probes/library_shots.tscn   (windowed, NOT headless)

const OUT := "res://_probes/shots/"
const VP := Vector2(1280, 720)
const LIBRARY := preload("res://scripts/screens/library_view.tscn")
const READING := preload("res://scenes/reading_view.tscn")

var _vp: SubViewport
var issues: Array[String] = []
var notes: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	if FFSettings != null:
		FFSettings.set_reduced_motion(true)
		FFSettings.set_dice_animation(false)

	await _t(2)

	# ---- LIBRARY --------------------------------------------------------------
	var lib := LIBRARY.instantiate()
	_vp.add_child(lib)
	await _t(10)
	# both shipped books must be carded, with real cover art
	for want in ["grey-tithe", "wreckers-light"]:
		if not (lib._cards as Dictionary).has(want):
			issues.append("library: book card '%s' missing from the shelf" % want)
	# open the NEW book on the reading desk so the shot proves selection
	if (lib._cards as Dictionary).has("wreckers-light"):
		lib._select("wreckers-light")
	await _t(8)
	_audit("library", lib)
	await _shoot("qa_library")
	_clear()

	# ---- THE NEW BOOK'S FIRST PAGE -------------------------------------------
	if not Adventure.set_book("wreckers-light"):
		issues.append("adv2: set_book('wreckers-light') failed")
	Adventure.new_adventure(20260721)
	var rv := READING.instantiate()
	_vp.add_child(rv)
	await _t(10)
	if Adventure.runner.state.current_passage != "w1":
		issues.append("adv2: expected opening section w1, at %s" % Adventure.runner.state.current_passage)
	# the opening plate must be BOUND through the per-book overlay (real texture)
	if AssetBinder.get_texture("plate/wl_shore") == null:
		issues.append("adv2: opening plate 'plate/wl_shore' did not bind a texture")
	_audit("adv2_open", rv)
	await _shoot("qa_adv2_open")
	_clear()

	print("DEBUG: library_shots — %s" % " ".join(notes))
	if issues.is_empty():
		print("DEBUG: library_shots issues=0 — LIBRARY + ADV2 CLEAN")
	else:
		print("DEBUG: library_shots issues=%d" % issues.size())
		for i in issues:
			print("DEBUG:   ISSUE: %s" % i)
	get_tree().quit(0 if issues.is_empty() else 2)


# ---- audit (same bug-class checks as qa_probe) -------------------------------

func _audit(label: String, root: Node) -> void:
	var btns: Array[BaseButton] = []
	_gather_buttons(root, btns)
	var count := 0
	for b in btns:
		if not is_instance_valid(b) or not b.is_visible_in_tree():
			continue
		count += 1
		var gr: Rect2 = b.get_global_rect()
		var sc := _scroll_ancestor(b)
		if sc == null:
			var center := gr.get_center()
			if center.x < -8 or center.y < -8 or center.x > VP.x + 8 or center.y > VP.y + 8:
				issues.append("%s: button '%s' center %s OFF-SCREEN (no scroll ancestor)" % [
					label, _btext(b), str(center.round())])
		else:
			var sr: Rect2 = sc.get_global_rect()
			if sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED \
					and (gr.position.x < sr.position.x - 8 or gr.end.x > sr.end.x + 8):
				issues.append("%s: button '%s' clipped horizontally in a no-h-scroll container" % [label, _btext(b)])
		if not b.disabled and not _is_wired(b):
			issues.append("%s: button '%s' is UNWIRED" % [label, _btext(b)])
	notes.append("%s[btns=%d]" % [label, count])


func _gather_buttons(n: Node, out: Array[BaseButton]) -> void:
	if n is BaseButton:
		out.append(n)
	for c in n.get_children():
		_gather_buttons(c, out)


func _scroll_ancestor(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null


func _is_wired(b: BaseButton) -> bool:
	return b.pressed.get_connections().size() > 0 or b.toggled.get_connections().size() > 0


func _btext(b: BaseButton) -> String:
	if b is Button:
		var t := (b as Button).text
		return t if t.strip_edges() != "" else "<icon:%s>" % b.name
	return b.name


func _clear() -> void:
	for c in _vp.get_children():
		c.queue_free()


func _t(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shoot(name: String) -> void:
	for _i in 8:
		await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	notes.append("shot:%s" % name)
