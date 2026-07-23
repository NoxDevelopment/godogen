extends Control
## res://scripts/screens/options_view.gd
## The fully-fleshed Options screen (GDD §6.1 "Fully fleshed Options"; WIREFRAMES §14).
## A tabbed, book-styled overlay instanced over the menu or the pause layer:
##   Reading        — prose font size, page theme
##   Audio          — master / music / sfx volume, fullscreen, v-sync  (NoxSettings)
##   Combat         — Quick Combat
##   Dice           — animate tumble, animation speed
##   Accessibility  — global text/UI scale, reduced motion
##   Rules / Mode   — death/save mode (GDD §4: Bookmarks / Ironman / Rewind / Checkpoints)
##
## Video + volume live in the shared NoxSettings autoload; the gameplay-shaped prefs
## live in FFSettings. Everything is applied LIVE where feasible — text scale reflows
## the whole UI immediately (content-scale), audio/video apply on change, and the
## reading view listens to FFSettings.changed for prose size + page theme.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # usable while the tree is paused
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.03, 0.74)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := FFUI.framed_panel(FFUI.VERDIGRIS)
	panel.custom_minimum_size = Vector2(660, 580)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 12)
	panel.add_child(col)

	col.add_child(FFUI.engraved_header("OPTIONS", 30, FFUI.INK, FFUI.VERDIGRIS))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 420)
	tabs.add_theme_color_override(&"font_selected_color", FFUI.INK)
	tabs.add_theme_color_override(&"font_unselected_color", FFUI.UMBER)
	tabs.add_theme_color_override(&"font_hovered_color", FFUI.INK)
	# on-paper tab treatment: the body sits on the card's own parchment (no grey
	# slab), the selected tab reads as an inked entry with a verdigris stem
	var body_sb := StyleBoxFlat.new()
	body_sb.bg_color = Color(0, 0, 0, 0)
	body_sb.content_margin_top = 10
	tabs.add_theme_stylebox_override(&"panel", body_sb)
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = Color(0.13, 0.10, 0.06, 0.06)
	tab_sel.border_color = FFUI.VERDIGRIS
	tab_sel.border_width_bottom = 3
	tab_sel.content_margin_left = 14
	tab_sel.content_margin_right = 14
	tab_sel.content_margin_top = 6
	tab_sel.content_margin_bottom = 6
	var tab_un: StyleBoxFlat = tab_sel.duplicate()
	tab_un.bg_color = Color(0, 0, 0, 0)
	tab_un.border_color = Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.35)
	tab_un.border_width_bottom = 1
	var tab_hv: StyleBoxFlat = tab_un.duplicate()
	tab_hv.border_color = FFUI.VERDIGRIS_2
	tab_hv.border_width_bottom = 2
	tabs.add_theme_stylebox_override(&"tab_selected", tab_sel)
	tabs.add_theme_stylebox_override(&"tab_unselected", tab_un)
	tabs.add_theme_stylebox_override(&"tab_hovered", tab_hv)
	col.add_child(tabs)

	tabs.add_child(_reading_tab())
	tabs.add_child(_display_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_combat_tab())
	tabs.add_child(_dice_tab())
	tabs.add_child(_accessibility_tab())
	tabs.add_child(_rules_tab())

	var back := FFUI.choice_button("Back")
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.pressed.connect(_close)
	col.add_child(back)
	back.grab_focus()


# --- tabs ------------------------------------------------------------------------

func _reading_tab() -> Control:
	var t := _tab_body("Reading")
	t.add_child(_slider_row("Prose font size", 0.8, 1.6, 0.05, FFSettings.font_scale,
		func(v): FFSettings.set_font_scale(v), func(v): return "%d%%" % round(v * 100.0)))
	t.add_child(_option_row("Page theme", FFSettings.READING_THEME_NAMES, FFSettings.reading_theme,
		func(i): FFSettings.set_reading_theme(i)))
	t.add_child(_hint("The reading page updates live as you change these."))
	return t

## Display (LOOKFEEL_PASS_2026-07): window size + fullscreen actually APPLY (the
## critique: "the resolution doesn't even change or is adjustable"), and the
## reading-plate presentation is player-tunable (Large is the Veritas default).
func _display_tab() -> Control:
	var t := _tab_body("Display")
	t.add_child(_option_row("Window size", FFSettings.WINDOW_SIZE_NAMES, FFSettings.window_size,
		func(i): FFSettings.set_window_size(i)))
	t.add_child(_check_row("Fullscreen", NoxSettings.fullscreen, func(on):
		NoxSettings.set_fullscreen(on)
		if not on:
			FFSettings.apply_window_size()))
	t.add_child(_check_row("V-Sync", NoxSettings.vsync, func(on): NoxSettings.set_vsync(on)))
	t.add_child(_option_row("Illustration plates", FFSettings.PLATE_SIZE_NAMES, FFSettings.plate_size,
		func(i): FFSettings.set_plate_size(i)))
	t.add_child(_hint("Window size applies immediately when windowed; fullscreen ignores it. Illustration plates: Large opens the page on the image (Veritas-style), Small tucks it beneath the prose."))
	return t

func _audio_tab() -> Control:
	var t := _tab_body("Audio")
	t.add_child(_slider_row("Master volume", 0.0, 1.0, 0.01, NoxSettings.master,
		func(v): NoxSettings.set_volume("master", v), func(v): return "%d%%" % round(v * 100.0)))
	t.add_child(_slider_row("Music volume", 0.0, 1.0, 0.01, NoxSettings.music,
		func(v): NoxSettings.set_volume("music", v), func(v): return "%d%%" % round(v * 100.0)))
	t.add_child(_slider_row("SFX volume", 0.0, 1.0, 0.01, NoxSettings.sfx,
		func(v): NoxSettings.set_volume("sfx", v), func(v): return "%d%%" % round(v * 100.0)))
	return t

func _combat_tab() -> Control:
	var t := _tab_body("Combat")
	t.add_child(_check_row("Quick Combat (auto-run rounds)", FFSettings.quick_combat,
		func(on): FFSettings.set_quick_combat(on)))
	t.add_child(_hint("Quick Combat resolves each round instantly instead of tapping through the dice."))
	return t

func _dice_tab() -> Control:
	var t := _tab_body("Dice")
	t.add_child(_check_row("3D physics dice (bone d6 tumbling in a tray)", FFSettings.dice_3d,
		func(on): FFSettings.set_dice_3d(on)))
	t.add_child(_check_row("Animate the dice (bone-clatter tumble)", FFSettings.dice_animation,
		func(on): FFSettings.set_dice_animation(on)))
	t.add_child(_slider_row("Animation speed", 0.5, 2.0, 0.05, FFSettings.dice_speed,
		func(v): FFSettings.set_dice_speed(v), func(v): return "%.2f×" % v))
	t.add_child(_hint("3D dice roll real bone-dice in a physics tray, then settle on the same seeded result the rules already decided (honest — the throw never changes the number). Turn 3D off for the flat honest-pips dice. Speed scales the tumble length; turn animation off to snap straight to the result."))
	return t

func _accessibility_tab() -> Control:
	var t := _tab_body("Accessibility")
	t.add_child(_slider_row("Text / UI scale", 0.8, 2.0, 0.05, FFSettings.text_scale,
		func(v): FFSettings.set_text_scale(v), func(v): return "%d%%" % round(v * 100.0)))
	t.add_child(_check_row("Reduced motion", FFSettings.reduced_motion,
		func(on): FFSettings.set_reduced_motion(on)))
	t.add_child(_hint("Text scale reflows the entire interface immediately. Reduced motion snaps the dice and pauses the credits crawl."))
	return t

func _rules_tab() -> Control:
	var t := _tab_body("Rules / Mode")
	t.add_child(_option_row("Death / save mode", FFSettings.SAVE_MODE_NAMES, FFSettings.save_mode,
		func(i): FFSettings.set_save_mode(i)))
	t.add_child(_hint("Bookmarks (default): unlimited revisit points, save anywhere.\nIronman: one rolling autosave, wiped on death — no reload.\nRewind / Checkpoints: preview modes (v1.1 follow-up)."))
	return t


# --- widgets ---------------------------------------------------------------------

## A tab body. TabContainer reads the tab title from the direct child's `name`, so the
## returned VBox carries the tab name and callers add rows straight onto it.
func _tab_body(tab_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = tab_name
	box.add_theme_constant_override(&"separation", 14)
	for s in ["left", "top", "right", "bottom"]:
		box.add_theme_constant_override("margin_" + s, 16)
	return box

func _slider_row(text: String, mn: float, mx: float, step: float, value: float, on_change: Callable, fmt: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var l := FFUI.label(text, 17, FFUI.INK)
	l.custom_minimum_size = Vector2(240, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(220, 0)
	row.add_child(s)
	var val := FFUI.label(str(fmt.call(value)), 16, FFUI.VERDIGRIS)
	val.custom_minimum_size = Vector2(70, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	s.value_changed.connect(func(v):
		on_change.call(v)
		val.text = str(fmt.call(v)))
	return row

func _check_row(text: String, value: bool, on_toggle: Callable) -> Control:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = value
	cb.add_theme_color_override(&"font_color", FFUI.INK)
	cb.add_theme_font_override(&"font", FFUI.font_body())
	cb.add_theme_font_size_override(&"font_size", 17)
	cb.toggled.connect(func(on): on_toggle.call(on))
	return cb

func _option_row(text: String, items: Array, selected: int, on_select: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var l := FFUI.label(text, 17, FFUI.INK)
	l.custom_minimum_size = Vector2(240, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in items.size():
		ob.add_item(str(items[i]), i)
	ob.selected = clampi(selected, 0, items.size() - 1)
	ob.item_selected.connect(func(i): on_select.call(i))
	row.add_child(ob)
	return row

func _hint(text: String) -> Control:
	var l := FFUI.label(text, 14, FFUI.UMBER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


# --- lifecycle -------------------------------------------------------------------

func _close() -> void:
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		accept_event()
		_close()
