extends Control
## res://scripts/screens/death_screen.gd
## Death Screen (WIREFRAMES 5.9, GDD §6.1 #12) — "your account is settled." Deaths
## are content, not a bare fail-state: a somber death plate (bound by ID, swappable),
## the how-you-died flavor from the terminal Section, run tallies from GameState, and
## Restart / Load / Menu. Reached when STAMINA hits 0 or an instant-death terminal
## fires. Low-key Old-Arrears-Red "PAID" motif per the style guide.

const ROLL_UP := "res://scripts/screens/roll_up.tscn"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(FFUI.page_background(true))
	add_child(FFUI.wash(FFUI.ARREARS, 0.10))
	AudioDirector.play_music("death")   # somber finality — the account is closed
	_build()


func _build() -> void:
	var ending: Dictionary = Adventure.ending()
	var section := Adventure.current_section()
	var st := Adventure.runner.state if Adventure.runner != null else null

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override(&"separation", 12)
	center.add_child(col)

	# death plate
	var plate_slot := str(ending.get("illustration", "plate/death"))
	col.add_child(_plate(plate_slot))

	var stamp := FFUI.title("YOUR ADVENTURE ENDS", 30, FFUI.ARREARS)
	stamp.add_theme_font_override(&"font", FFUI.font_runic())
	col.add_child(stamp)
	col.add_child(FFUI.title(str(ending.get("label", "The ledger closes")), 20, FFUI.VERDIGRIS_2))

	var flavor := FFUI.rich(18, FFUI.PARCHMENT)
	flavor.add_theme_color_override(&"default_color", Color(0.85, 0.80, 0.70))
	flavor.text = "[i]%s[/i]" % section.text()
	col.add_child(flavor)
	col.add_child(FFUI.divider_rule())

	# run stats
	var stats := FFUI.panel(Color("241f19"), FFUI.UMBER)
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override(&"separation", 4)
	stats.add_child(sc)
	sc.add_child(FFUI.label("── RUN STATS ──", 15, FFUI.VERDIGRIS, false))
	var sections_read := 0
	var foes := 0
	if st != null:
		var seen := {}
		for p in st.passage_history:
			seen[str(p)] = true
		sections_read = seen.size()
		foes = int(st.get_var("foes_defeated"))
	sc.add_child(_stat("Sections read", str(sections_read)))
	sc.add_child(_stat("Foes defeated", str(foes)))
	sc.add_child(_stat("Gold at death", "%d gp" % (Adventure.sheet.gold if Adventure.sheet else 0)))
	sc.add_child(_stat("Cause", str(ending.get("cause", "STAMINA 0"))))
	col.add_child(stats)

	# actions
	var restart := FFUI.choice_button("Restart  (roll a new hero)")
	restart.alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart.pressed.connect(_on_restart)
	col.add_child(restart)
	var load_b := FFUI.choice_button("Load / Bookmark")
	load_b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_b.pressed.connect(func() -> void: NoxShell.to_menu())
	col.add_child(load_b)
	var menu := FFUI.choice_button("Return to the menu")
	menu.alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.pressed.connect(func() -> void: NoxShell.to_menu())
	col.add_child(menu)
	restart.grab_focus()


func _plate(slot: String) -> Control:
	var panel := FFUI.tex_framed(FFUI.ARREARS)
	panel.custom_minimum_size = Vector2(0, 200)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(0, 168)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := FFUI.plate(slot)
	if tex != null:
		tr.texture = tex
	panel.add_child(tr)
	return panel


func _stat(k: String, v: String) -> Control:
	var row := HBoxContainer.new()
	var kl := FFUI.label(k, 15, FFUI.PARCHMENT)
	kl.add_theme_color_override(&"font_color", Color(0.80, 0.76, 0.66))
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kl)
	row.add_child(FFUI.label(v, 15, FFUI.PARCHMENT))
	return row


func _on_restart() -> void:
	Adventure.new_adventure()
	get_tree().change_scene_to_file(ROLL_UP)
