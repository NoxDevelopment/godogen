extends Node
## res://_probes/shot_gen.gd
## Phase-7 screenshot tool (windowed): renders the fleshed Options overlay and the
## scrolling Credits scene into _probes/shots/ so the shell can be screenshot-proven.
##   12_options.png  — the tabbed Options (Reading/Audio/Combat/Dice/Accessibility/Rules)
##   11_credits.png  — the credits skill's auto-scrolling credits.tscn (asset-heavy mode)
## Uses an offscreen SubViewport (needs a rendering context) exactly like plate_gen.
## Run:  godot --path <skeleton> res://_probes/shot_gen.tscn   (windowed, not headless)

const OUT_DIR := "res://_probes/shots/"
const OPTIONS_VIEW := preload("res://scripts/screens/options_view.gd")
const CREDITS_SCENE := preload("res://credits.tscn")

var _vp: SubViewport


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_vp = SubViewport.new()
	_vp.transparent_bg = false
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	# a dark shell backdrop so the Options overlay reads as sitting over the menu
	await _shoot_options()
	await _shoot_credits()
	get_tree().quit(0)


func _clear_vp() -> void:
	for c in _vp.get_children():
		c.queue_free()
	await get_tree().process_frame


func _capture(name: String) -> void:
	# let layout + a little animation settle
	for _i in 24:
		await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	var path := OUT_DIR + name
	img.save_png(ProjectSettings.globalize_path(path))
	print("DEBUG: shot_gen wrote %s" % path)


func _shoot_options() -> void:
	await _clear_vp()
	# a menu-like backdrop behind the modal so it reads in context
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.06, 0.09, 1)
	_vp.add_child(bg)
	_vp.add_child(OPTIONS_VIEW.new())
	await _capture("12_options.png")


func _shoot_credits() -> void:
	await _clear_vp()
	_vp.add_child(CREDITS_SCENE.instantiate())
	# hold longer so the crawl has visibly advanced past the top
	for _i in 40:
		await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "11_credits.png"))
	print("DEBUG: shot_gen wrote %s11_credits.png" % OUT_DIR)
