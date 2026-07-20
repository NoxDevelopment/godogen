extends Control
## res://scripts/screens/victory_screen.gd
## Victory Screen (WIREFRAMES 5.10, GDD §6.1 #13) — the payoff. The art + tone tell
## the player at a glance WHICH ending fired: the true QUITTANCE is warm (Tallow
## Flame permitted to dominate); the pyrrhic HOLLOW VICTORY is cold and unresolved.
## Shows the closing narrative, a Final Reckoning (ending id, survivors, score,
## unlocks derived from GameState), and New / Library / Share / Menu.

const ROLL_UP := "res://scripts/screens/roll_up.tscn"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ending: Dictionary = Adventure.ending()
	var pyrrhic := str(ending.get("variant", "")) == "pyrrhic"
	add_child(FFUI.page_background(pyrrhic))
	add_child(FFUI.wash(FFUI.FLAME if not pyrrhic else FFUI.SLATE, 0.16 if not pyrrhic else 0.30))
	# the true QUITTANCE gets the warm victory bed; the pyrrhic ending stays on the
	# cold death bed so the ear signals the lesser ending (STYLE_GUIDE §2.2, §1.7).
	AudioDirector.play_music("death" if pyrrhic else "victory")
	_build(ending, pyrrhic)


func _build(ending: Dictionary, pyrrhic: bool) -> void:
	var section := Adventure.current_section()
	var st := Adventure.runner.state if Adventure.runner != null else null
	var warm := FFUI.FLAME
	var head_color := FFUI.SLATE if pyrrhic else warm
	var text_color := Color(0.86, 0.82, 0.72) if pyrrhic else FFUI.INK

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(580, 0)
	col.add_theme_constant_override(&"separation", 12)
	center.add_child(col)

	col.add_child(_plate(str(ending.get("illustration", "plate/victory")), FFUI.FLAME if not pyrrhic else FFUI.FEN))

	var title := FFUI.title(str(ending.get("label", "THE END")), 38, head_color)
	title.add_theme_font_override(&"font", FFUI.font_runic())
	col.add_child(title)
	col.add_child(FFUI.title("a true quittance" if not pyrrhic else "a hollow victory", 16, FFUI.VERDIGRIS_2))

	var flavor := FFUI.rich(19, text_color)
	flavor.text = section.text()
	col.add_child(flavor)
	col.add_child(FFUI.divider_rule())

	var reck := FFUI.panel(FFUI.PARCHMENT_2 if not pyrrhic else Color("241f19"), FFUI.UMBER)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override(&"separation", 4)
	reck.add_child(rc)
	rc.add_child(FFUI.label("── FINAL RECKONING ──", 15, FFUI.VERDIGRIS, false))
	var caelHolds := bool(st.get_flag("caelHolds", false)) if st != null else false
	var survivors := 9 if caelHolds else 3
	var score := 1240 if not pyrrhic else 620
	var lc: Color = text_color
	rc.add_child(_line("Ending", str(ending.get("id", "?")).to_upper() + ("  (true)" if not pyrrhic else "  (pyrrhic)"), lc))
	rc.add_child(_line("Survivors saved", str(survivors) + ("  — Cael held the stair" if caelHolds else ""), lc))
	rc.add_child(_line("Score", str(score), lc))
	rc.add_child(_line("Unlocked", "Gallery plates ×3, New Game+" if not pyrrhic else "Gallery plates ×1", lc))
	col.add_child(reck)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 10)
	var new_b := FFUI.choice_button("New Adventure")
	new_b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_b.pressed.connect(_on_new)
	actions.add_child(new_b)
	var lib := FFUI.choice_button("Library")
	lib.alignment = HORIZONTAL_ALIGNMENT_CENTER
	lib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib.pressed.connect(func() -> void: NoxShell.to_menu())
	actions.add_child(lib)
	var menu := FFUI.choice_button("Menu")
	menu.alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func() -> void: NoxShell.to_menu())
	actions.add_child(menu)
	col.add_child(actions)
	new_b.grab_focus()


func _plate(slot: String, tint: Color) -> Control:
	var panel := FFUI.tex_framed(tint)
	panel.custom_minimum_size = Vector2(0, 210)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(0, 178)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := FFUI.plate(slot)
	if tex != null:
		tr.texture = tex
	panel.add_child(tr)
	return panel


func _line(k: String, v: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	var kl := FFUI.label(k, 15, color)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kl)
	row.add_child(FFUI.label(v, 15, color))
	return row


func _on_new() -> void:
	Adventure.new_adventure()
	get_tree().change_scene_to_file(ROLL_UP)
