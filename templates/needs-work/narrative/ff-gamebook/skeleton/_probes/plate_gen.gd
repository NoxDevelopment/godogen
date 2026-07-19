extends Node
## res://_probes/plate_gen.gd
## Build tool (windowed): renders the clearly-labelled veritas-gamebook PLACEHOLDER
## section plates into res://assets/plates/placeholder/*.png. These are REAL asset
## files (not placeholder UI) bound by stable ID in assets.manifest.json, so the
## Studio can drop generated veritas plates over them in Phase 5 with no code edits.
## Parchment ground + ledger-verdigris ruled frame + faint ledger-column motif + the
## plate's title, slot id, and a "placeholder" tag. Quits when done.
## Run:  godot --path <skeleton> res://_probes/plate_gen.tscn  (windowed, not headless)

const OUT_DIR := "res://assets/plates/placeholder/"

const PLATES := [
	{"slot": "s1", "title": "The Last Coach North", "tone": "cold"},
	{"slot": "s2", "title": "The Toll-Bridge in the Fog", "tone": "cold"},
	{"slot": "s3", "title": "Paid in Coin", "tone": "cold"},
	{"slot": "s4", "title": "The Ledger-Stone", "tone": "cold"},
	{"slot": "s5", "title": "Paid in Kind", "tone": "cold"},
	{"slot": "s6", "title": "Paid in Blood", "tone": "blood"},
	{"slot": "s7", "title": "Refusal", "tone": "blood"},
	{"slot": "s8", "title": "The Drowned Gate", "tone": "cold"},
	{"slot": "s9", "title": "The Square", "tone": "cold"},
	{"slot": "s10", "title": "Mother Grissel's Fever-House", "tone": "warm"},
	{"slot": "s11", "title": "Ferrant Coinwright's Stall", "tone": "warm"},
	{"slot": "s12", "title": "The Reeds", "tone": "blood"},
	{"slot": "descent", "title": "The Descent", "tone": "deep"},
	{"slot": "isolde", "title": "Isolde, the Unpaid", "tone": "verdigris"},
	{"slot": "reckoner", "title": "The Reckoner", "tone": "verdigris"},
	{"slot": "death", "title": "Your Account Is Settled", "tone": "death"},
	{"slot": "victory", "title": "Quittance", "tone": "warm"},
	{"slot": "cover", "title": "THE GREY TITHE", "tone": "cover"},
]

var _vp: SubViewport


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_vp = SubViewport.new()
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	await _run()
	get_tree().quit(0)


func _run() -> void:
	for p in PLATES:
		var is_cover: bool = p.slot == "cover"
		var w := 1200 if is_cover else 820
		var h := 660 if is_cover else 470
		_vp.size = Vector2i(w, h)
		for c in _vp.get_children():
			c.queue_free()
		_vp.add_child(_make_plate(p, w, h))
		await get_tree().process_frame
		await get_tree().process_frame
		var img := _vp.get_texture().get_image()
		var path := OUT_DIR + str(p.slot) + ".png"
		img.save_png(ProjectSettings.globalize_path(path))
		print("DEBUG: plate_gen wrote %s (%dx%d)" % [path, w, h])


func _make_plate(p: Dictionary, w: int, h: int) -> Control:
	var tone := str(p.tone)
	var ground := FFUI.PARCHMENT
	var accent := FFUI.VERDIGRIS
	var title_color := FFUI.INK
	match tone:
		"warm": ground = Color("ecdcb8"); accent = FFUI.FLAME
		"blood": ground = Color("d9c9a6"); accent = FFUI.ARREARS
		"deep": ground = FFUI.SLATE; title_color = FFUI.PARCHMENT; accent = FFUI.VERDIGRIS
		"death": ground = Color("1a1512"); title_color = Color("c9b79a"); accent = FFUI.ARREARS
		"verdigris": ground = Color("cfd6cb"); accent = FFUI.VERDIGRIS
		"cover": ground = FFUI.SLATE; title_color = FFUI.PARCHMENT; accent = FFUI.VERDIGRIS

	var root := Control.new()
	root.custom_minimum_size = Vector2(w, h)
	root.size = Vector2(w, h)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = ground
	root.add_child(bg)

	# vignette wash for depth
	var wash := ColorRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.10 if tone != "death" and tone != "cover" and tone != "deep" else 0.28)
	root.add_child(wash)

	# faint ledger-script columns (the world's signature motif)
	var cols := HBoxContainer.new()
	cols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cols.alignment = BoxContainer.ALIGNMENT_END
	cols.add_theme_constant_override(&"separation", 18)
	for i in 4:
		var ledger := Label.new()
		ledger.text = _ledger_column()
		ledger.add_theme_font_override(&"font", FFUI.font_body())
		ledger.add_theme_font_size_override(&"font_size", 15)
		ledger.add_theme_color_override(&"font_color", Color(accent.r, accent.g, accent.b, 0.16))
		ledger.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		cols.add_child(ledger)
	var col_margin := MarginContainer.new()
	col_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["top", "right", "bottom"]:
		col_margin.add_theme_constant_override("margin_" + s, 20)
	col_margin.add_child(cols)
	root.add_child(col_margin)

	# ruled frame
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 16; frame.offset_top = 16; frame.offset_right = -16; frame.offset_bottom = -16
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0, 0)
	fs.set_border_width_all(3)
	fs.border_color = accent
	fs.set_corner_radius_all(2)
	frame.add_theme_stylebox_override(&"panel", fs)
	root.add_child(frame)

	# centered text block
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override(&"separation", 10)
	center.add_child(vb)

	var glyph := Label.new()
	glyph.text = "☰ ✝ ☰"
	glyph.add_theme_font_override(&"font", FFUI.font_runic())
	glyph.add_theme_font_size_override(&"font_size", 34)
	glyph.add_theme_color_override(&"font_color", Color(accent.r, accent.g, accent.b, 0.8))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(glyph)

	var title := Label.new()
	title.text = str(p.title)
	title.add_theme_font_override(&"font", FFUI.font_runic() if p.slot == "cover" else FFUI.font_display())
	title.add_theme_font_size_override(&"font_size", 64 if p.slot == "cover" else 40)
	title.add_theme_color_override(&"font_color", title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(w - 140, 0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(title)

	var tag := Label.new()
	tag.text = "veritas-gamebook  ·  placeholder plate  ·  slot: plate/%s" % str(p.slot)
	tag.add_theme_font_override(&"font", FFUI.font_body())
	tag.add_theme_font_size_override(&"font_size", 16)
	tag.add_theme_color_override(&"font_color", Color(title_color.r, title_color.g, title_color.b, 0.7))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tag)

	return root


func _ledger_column() -> String:
	var s := ""
	for i in 14:
		s += "%d  %d\n" % [randi_range(1, 9), randi_range(10, 99)]
	return s
