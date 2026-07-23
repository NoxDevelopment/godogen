extends Node
## res://_probes/dice3d_probe.gd
## Phase-7 screenshot tool (WINDOWED) for the rebuilt 3D dice tray (DICE_3D_SPEC).
## Renders the honest 3D dice — settled on the felt-and-wood tray under the warm
## WorldEnvironment — into _probes/shots/ so the look/feel can be visual-judged vs
## real bone d6 / Dice So Nice references. 3D PBR + SSAO need a real render context,
## so this MUST run windowed (not --headless):
##
##   C:\godot\Godot.exe --path <skeleton> _probes/dice3d_probe.tscn
##
## Shots:
##   qa_dice_single.png   — one d6 (SKILL/LUCK roll), settled + read
##   qa_dice_v2.png       — two dice (2d6 Test/STAMINA), settled + read
##   qa_dice_combat.png   — combat two-tint (you-bone vs foe-grey)
##   qa_dice_midroll.png  — mid-tumble (dice in flight)

const OUT_DIR := "res://_probes/shots/"
const POPUP := preload("res://scenes/dice_roll_popup.tscn")

var _page: CanvasLayer


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# force the 3D dice on (the tray only runs when enabled + not headless + not reduced)
	var ff := get_node_or_null("/root/FFSettings")
	if ff != null:
		ff.dice_3d = true
		ff.dice_animation = true
		ff.reduced_motion = false
		ff.dice_speed = 1.0

	# a parchment page backdrop so the composite reads in context (tray overlays 2D)
	_page = CanvasLayer.new()
	_page.layer = 0
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("e7dcc2")
	_page.add_child(bg)
	add_child(_page)

	await _shoot_single()
	await _shoot_2d6()
	await _shoot_combat()
	await _shoot_midroll()
	# honest-mapping verification: the settled TOP faces must equal the requested set.
	await _shoot_verify("qa_dice_verify_a.png", [1, 2, 3])
	await _shoot_verify("qa_dice_verify_b.png", [4, 5, 6])
	get_tree().quit(0)


func _fresh_popup() -> Node:
	var p := POPUP.instantiate()
	add_child(p)
	return p


func _capture(name: String) -> void:
	# let the window present a few frames so PBR/SSAO/glow are resolved
	for _i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name
	img.save_png(ProjectSettings.globalize_path(path))
	print("DEBUG: dice3d_probe wrote %s" % path)


func _shoot_single() -> void:
	var p := _fresh_popup()
	# fire the roll without awaiting so we can screenshot while it holds on "continue"
	p.run_test({
		"context": "TEST YOUR SKILL", "faces": [5], "total": 5,
		"compare_label": "", "banner": "", "banner_color": Color("6e8f7a"),
	})
	await get_tree().create_timer(3.6).timeout
	await _capture("qa_dice_single.png")
	p.queue_free()
	await get_tree().process_frame


func _shoot_2d6() -> void:
	var p := _fresh_popup()
	p.run_test({
		"context": "TEST YOUR LUCK", "faces": [5, 3], "total": 8,
		"compare_label": "≤ LUCK 9", "banner": "LUCKY!", "banner_color": Color("6e8f7a"),
	})
	await get_tree().create_timer(3.6).timeout
	await _capture("qa_dice_v2.png")
	p.queue_free()
	await get_tree().process_frame


func _shoot_combat() -> void:
	var p := _fresh_popup()
	p.run_combat({
		"context": "COMBAT",
		"you": {"faces": [6, 4], "total": 19, "label": "+SKILL 9"},
		"enemy": {"name": "Bog Wight", "faces": [2, 5], "total": 15, "label": "+SKILL 8"},
		"banner": "YOU STRIKE!", "banner_color": Color("6e8f7a"),
	})
	await get_tree().create_timer(3.6).timeout
	await _capture("qa_dice_combat.png")
	p.queue_free()
	await get_tree().process_frame


func _shoot_verify(name: String, faces: Array) -> void:
	# Drive the tray directly with known faces and screenshot the settled result so the
	# top faces can be counted vs `faces` (rubric #8 — honesty preserved).
	var p := _fresh_popup()
	var total := 0
	for f in faces:
		total += int(f)
	p.run_test({
		"context": "FACE CHECK %s" % str(faces), "faces": faces, "total": total,
		"compare_label": "", "banner": "", "banner_color": Color("6e8f7a"),
	})
	await get_tree().create_timer(3.6).timeout
	await _capture(name)
	p.queue_free()
	await get_tree().process_frame


func _shoot_midroll() -> void:
	var p := _fresh_popup()
	p.run_test({
		"context": "TEST YOUR LUCK", "faces": [4, 6], "total": 10,
		"compare_label": "", "banner": "", "banner_color": Color("6e8f7a"),
	})
	await get_tree().create_timer(0.55).timeout    # catch the dice mid-tumble
	await _capture("qa_dice_midroll.png")
	p.queue_free()
	await get_tree().process_frame
