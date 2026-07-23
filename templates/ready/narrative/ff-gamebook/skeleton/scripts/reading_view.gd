extends Control
## res://scripts/reading_view.gd
## The Book-Reading View (WIREFRAMES 5.2, GDD §6.1 #4) — the heart, where ~80% of
## play happens. Phase-2 polish: a drop-cap + section heading, the illustration
## plate bound by STABLE ID through the AssetBinder (IFSection.illustration()),
## full-width choice buttons with target numbers HIDDEN (faithful mode) and
## conditional choices shown greyed with a reason, page-turn crossfade, "already
## read" dimming, and a compact persistent HUD (SKILL/STAMINA/LUCK + quick buttons
## to Sheet/Inventory/Map/Save + a bookmark). Events route honestly: Test-your-Luck
## /Skill through the animated Dice overlay, encounters into the Combat screen — and
## every outcome is applied by the ENGINE via Adventure.choose(outcome_id), so the
## rules core stays authoritative. Endings hand off to the Victory / Death screens.

const PAUSE_MENU := preload("res://addons/nox_ui/scenes/pause_menu.tscn")
const DICE_POPUP := preload("res://scenes/dice_roll_popup.tscn")
const COMBAT_VIEW := preload("res://scripts/screens/combat_view.tscn")
const ADVENTURE_SHEET := preload("res://scripts/screens/adventure_sheet.tscn")
const INVENTORY := preload("res://scripts/screens/inventory_view.tscn")
const MAP_VIEW := preload("res://scripts/screens/map_view.tscn")
const DEATH_SCREEN := "res://scripts/screens/death_screen.tscn"
const VICTORY_SCREEN := "res://scripts/screens/victory_screen.tscn"

var _hud_section: Label
var _hud_title: Label
var _bookmark_btn: Button
var _plate_slot_top: Control      # LARGE/MEDIUM plates live here (the page opens on the image)
var _plate_slot_bottom: Control   # SMALL plates tuck beneath the prose
var _plate_panel: Control
var _plate_tex: TextureRect
var _plate_caption: Label
var _plate_texture: Texture2D
var _prose: RichTextLabel
var _heading: Label
var _content: VBoxContainer
var _actions: VBoxContainer
var _toast_layer: Control
var _sheet_dock: Control
var _dock_stats: VBoxContainer

var _current_id := ""
var _event_resolved := false
var _combat_open := false
var _busy := false
var _pause: Node
var _last_gold := -1
var _last_inv := -1


var _page_bg: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_bg = FFUI.paper_ground()
	add_child(_page_bg)
	_build_ui()
	_pause = PAUSE_MENU.instantiate()
	add_child(_pause)

	Adventure.passage_changed.connect(_on_passage_changed)
	Adventure.sheet_changed.connect(_refresh_hud)
	Adventure.hero_died.connect(_on_hero_died)

	# Live reading preferences (Options → Reading/Accessibility): prose font size and
	# page theme react immediately to FFSettings.changed.
	var ff := get_node_or_null("/root/FFSettings")
	if ff != null:
		ff.changed.connect(_apply_reading_prefs)
	_apply_reading_prefs()

	if not Adventure.has_run():
		Adventure.new_adventure()
	_sync_to_current()
	_render()


## Apply the reading-comfort prefs live: scale the prose + heading to FFSettings.
## font_scale, switch the paper mode (Parchment/Sepia/Dark) and — on the Dark,
## lantern-lit page — flip the ink to parchment so the prose stays readable.
func _apply_reading_prefs() -> void:
	var ff := get_node_or_null("/root/FFSettings")
	if ff == null:
		return
	if _prose != null:
		_prose.add_theme_font_size_override(&"normal_font_size", int(round(19.0 * ff.font_scale)))
	if _heading != null:
		_heading.add_theme_font_size_override(&"font_size", int(round(24.0 * ff.font_scale)))
	var dark: bool = int(ff.reading_theme) == 2   # FFSettings.ReadingTheme.DARK
	if _page_bg != null and _page_bg.has_method("set_mode"):
		_page_bg.set_mode(int(ff.reading_theme))
	if _prose != null:
		_prose.add_theme_color_override(&"default_color", FFUI.PARCHMENT if dark else FFUI.PROSE_INK)
	if _heading != null:
		_heading.add_theme_color_override(&"font_color", FFUI.PARCHMENT if dark else FFUI.INK)
	# plate size preference re-seats the plate immediately
	if Adventure.has_run() and _plate_panel != null:
		_seat_plate()


func _build_ui() -> void:
	# The reading column sits ON the paper page (LOOKFEEL: FFC's book) — inset from
	# the page edge, width-capped so the prose keeps a book measure on wide windows.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var hrow := HBoxContainer.new()
	margin.add_child(hrow)
	var lspace := Control.new()
	lspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(lspace)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	col.custom_minimum_size = Vector2(860, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hrow.add_child(col)
	var rspace := Control.new()
	rspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(rspace)

	col.add_child(_build_page_header())

	# scrolling page body — the sacred page. The ScrollContainer expands to claim all
	# vertical space left between the header and the choices.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	# THE PLATE — the page opens on the image (STYLE_GUIDE §1.5 default placement;
	# Veritas plate presentation): a large double-rule framed plate above the prose.
	# The Options→Display "Illustration plates" preference re-seats it (Small tucks
	# it beneath the prose at vignette size). Click to open the plate full-screen.
	_plate_slot_top = VBoxContainer.new()
	_content.add_child(_plate_slot_top)

	_heading = FFUI.title("", 24, FFUI.INK)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_heading)
	_prose = FFUI.rich(19, FFUI.PROSE_INK)
	_prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prose.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_prose)

	_plate_slot_bottom = VBoxContainer.new()
	_content.add_child(_plate_slot_bottom)

	# the framed plate itself (re-parented between the two slots by _seat_plate)
	var tex_btn := Button.new()
	tex_btn.flat = true
	tex_btn.focus_mode = Control.FOCUS_NONE
	tex_btn.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
	tex_btn.add_theme_stylebox_override(&"hover", StyleBoxEmpty.new())
	tex_btn.add_theme_stylebox_override(&"pressed", StyleBoxEmpty.new())
	tex_btn.tooltip_text = "View the plate"
	tex_btn.pressed.connect(_open_lightbox)
	_plate_tex = TextureRect.new()
	_plate_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plate_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_plate_tex.custom_minimum_size = Vector2(0, 320)
	_plate_tex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plate_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_btn.add_child(_plate_tex)
	# keep the texture rect sized to the button
	_plate_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_btn.custom_minimum_size = Vector2(0, 320)
	_plate_panel = FFUI.plate_frame(tex_btn, FFUI.VERDIGRIS)
	_plate_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plate_caption = FFUI.label("", 12, FFUI.FEN, false)
	_plate_caption.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	_plate_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate_slot_top.add_child(_plate_panel)
	_plate_slot_top.add_child(_plate_caption)

	# actions (choices / event chips)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override(&"separation", 8)
	col.add_child(_actions)

	col.add_child(_build_quickrow())

	# the sheet-at-hand dock (FFC): a tilted sheet card pinned at the page's right edge
	_build_sheet_dock()

	# toast layer
	_toast_layer = Control.new()
	_toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_layer)


## The page-top furniture: pause, the book's running title in small caps, the
## section folio (§ N) printed at the top-right of the page, and the bookmark.
func _build_page_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var pause := FFUI.chip("☰")
	pause.custom_minimum_size = Vector2(44, 36)
	pause.pressed.connect(_open_pause)
	row.add_child(pause)
	_hud_title = FFUI.label(Adventure.book_title().to_upper(), 13, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.9), false)
	_hud_title.add_theme_font_override(&"font", FFUI.font_display_tracked(3))
	_hud_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hud_title)
	_hud_section = FFUI.label("§ —", 19, FFUI.INK)
	_hud_section.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hud_section)
	_bookmark_btn = FFUI.chip("🔖")
	_bookmark_btn.custom_minimum_size = Vector2(44, 36)
	_bookmark_btn.pressed.connect(_toggle_bookmark)
	row.add_child(_bookmark_btn)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	v.add_child(row)
	v.add_child(FFUI.diamond_rule(FFUI.VERDIGRIS))
	return v


func _build_quickrow() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in [["🎒  Inventory", "_open_inventory"], ["🗺  Map", "_open_map"], ["💾  Save", "_quick_save"]]:
		var b := FFUI.chip(spec[0])
		b.custom_minimum_size = Vector2(150, 40)
		b.pressed.connect(Callable(self, spec[1]))
		row.add_child(b)
	return row


# --- the sheet-at-hand dock (LOOKFEEL item 7 — FFC's docked sheet card) ------


## A slim, slightly-tilted Adventure-Sheet card pinned to the right edge of the
## page while reading: SK / ST / LK in the player's hand (current large, initial
## small beneath — the FFC circled-stat read), gold + provisions under a rule.
## Clicking it opens the full Adventure Sheet.
func _build_sheet_dock() -> void:
	var dock := Button.new()
	dock.name = "SheetDock"
	dock.tooltip_text = "Open the Adventure Sheet"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("e2d8bc")
	sb.border_color = Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.85)
	sb.set_border_width_all(1)
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	dock.add_theme_stylebox_override(&"normal", sb)
	var hb := sb.duplicate()
	hb.bg_color = Color("e9dfc6")
	hb.border_color = FFUI.VERDIGRIS
	dock.add_theme_stylebox_override(&"hover", hb)
	dock.add_theme_stylebox_override(&"pressed", sb)
	dock.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	dock.pressed.connect(_open_sheet)

	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := FFUI.label("SHEET", 11, FFUI.UMBER, false)
	cap.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	v.add_child(FFUI.diamond_rule(FFUI.VERDIGRIS))
	_dock_stats = VBoxContainer.new()
	_dock_stats.add_theme_constant_override(&"separation", 2)
	v.add_child(_dock_stats)
	dock.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		v.set("offset_" + s, v.get("offset_" + s) + (10 if s in ["left", "top"] else -10))

	dock.custom_minimum_size = Vector2(108, 0)
	dock.anchor_left = 1.0
	dock.anchor_right = 1.0
	dock.anchor_top = 0.5
	dock.anchor_bottom = 0.5
	dock.offset_left = -128.0
	dock.offset_right = -14.0
	dock.offset_top = -150.0
	dock.offset_bottom = 150.0
	dock.rotation_degrees = 1.6
	dock.pivot_offset = Vector2(57, 150)
	_sheet_dock = dock
	add_child(dock)


## One dock stat: printed caption, the current value written large in the
## player's ink with the Initial small beneath it (never exceeded — the rule).
func _dock_stat(cap: String, cur: int, initial: int, accent: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	var c := FFUI.label(cap, 10, FFUI.FEN, false)
	c.add_theme_font_override(&"font", FFUI.font_display_tracked(1))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var holder := CenterContainer.new()
	holder.add_child(FFUI.handwritten(str(cur), 26, FFUI.INK_PEN, "dock_%s_%d" % [cap, cur]))
	v.add_child(holder)
	var init_l := FFUI.label("of %d" % initial, 10, accent, false)
	init_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(init_l)
	return v


# --- passage lifecycle ------------------------------------------------------


func _on_passage_changed(_pid: String) -> void:
	_sync_to_current()
	_render()
	_page_turn()


func _sync_to_current() -> void:
	var pid := ""
	if Adventure.runner != null:
		pid = Adventure.runner.state.current_passage
	if pid != _current_id:
		_current_id = pid
		_event_resolved = false
		_combat_open = false


func _page_turn() -> void:
	AudioDirector.play_sfx("page_turn")   # diegetic paper — the primary transition sound
	_content.modulate = Color(1, 1, 1, 0.0)
	var tw := create_tween()
	tw.tween_property(_content, "modulate", Color(1, 1, 1, 1.0), 0.22)


## Resolve the reading bed for a section: its optional "music" mood flag, else the
## default cold explore bed. Kept here so writers/Studio drive mood from the data.
func _update_music(section: IFSection) -> void:
	var mood := str(section.raw().get("music", "")).strip_edges()
	if mood == "" or not AudioDirector.MUSIC_SLOTS.has(mood):
		mood = "explore"
	AudioDirector.play_music(mood)


func _render() -> void:
	_refresh_hud()
	_clear(_actions)

	# terminal handoffs first
	if Adventure.is_ended():
		var kind := str(Adventure.ending().get("kind", ""))
		call_deferred("_goto_end", kind)
		return
	if Adventure.sheet != null and Adventure.sheet.is_dead():
		call_deferred("_goto_end", "death")
		return

	var section := Adventure.current_section()
	_bind_plate(section)

	# heading + drop-cap prose
	_heading.text = section.title()
	_prose.text = _drop_cap(section.text())

	# events
	if section.has_event("combat") and not _event_resolved:
		_enter_combat(section)   # combat_view drives combat/boss music
		return

	# adaptive reading music (STYLE_GUIDE §2.2): a passage may flag its mood via a
	# "music" field (e.g. "tension" when the Assessor is near); default is the cold
	# explore bed. Crossfades on change; a no-op if already on that bed.
	_update_music(section)

	if section.has_event("luck_test") and not _event_resolved:
		_render_test("luck", section)
		return
	if (section.has_event("skill_test") or section.has_event("stamina_test")) and not _event_resolved:
		var stat := "skill" if section.has_event("skill_test") else "stamina"
		_render_test(stat, section)
		return

	_render_choices(section)
	_render_inline_chips()


func _bind_plate(section: IFSection) -> void:
	var slot := section.illustration()
	if slot == "":
		_plate_texture = null
		_plate_panel.visible = false
		_plate_caption.visible = false
		return
	_plate_panel.visible = true
	var tex := FFUI.plate(slot)
	_plate_texture = tex
	if tex != null:
		_plate_tex.texture = tex
		_plate_caption.visible = true
		_plate_caption.text = "· %s ·" % section.title().to_upper()
	else:
		_plate_tex.texture = null
		_plate_caption.visible = true
		_plate_caption.text = "[ %s — veritas-gamebook plate, awaiting generation ]" % slot
	_seat_plate()


## Seat the framed plate per Options→Display: Large/Medium open the page ON the
## image above the prose (Veritas); Small tucks a vignette beneath it. The frame
## hugs the plate's own aspect so the art never floats in side-mats.
func _seat_plate() -> void:
	var ff := get_node_or_null("/root/FFSettings")
	var mode: int = ff.plate_size if ff != null else 0
	var heights := [300.0, 220.0, 160.0]
	var h: float = heights[clampi(mode, 0, 2)]
	var w := 0.0
	if _plate_texture != null:
		var ts := _plate_texture.get_size()
		if ts.y > 0.0:
			w = minf(h * ts.x / ts.y, 800.0)
	var btn: Control = _plate_tex.get_parent()
	btn.custom_minimum_size = Vector2(w, h)
	_plate_tex.custom_minimum_size = Vector2(w, h)
	_plate_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var want_parent: Control = _plate_slot_bottom if mode == 2 else _plate_slot_top
	if _plate_panel.get_parent() != want_parent:
		_plate_panel.get_parent().remove_child(_plate_panel)
		_plate_caption.get_parent().remove_child(_plate_caption)
		want_parent.add_child(_plate_panel)
		want_parent.add_child(_plate_caption)


## Tap-to-expand (STYLE_GUIDE §1.5): the plate fills the screen over a dimmed
## desk, caption beneath; click / Esc closes.
func _open_lightbox() -> void:
	if _plate_texture == null:
		return
	var lb := Button.new()
	lb.name = "PlateLightbox"
	lb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.015, 0.01, 0.92)
	lb.add_theme_stylebox_override(&"normal", sb)
	lb.add_theme_stylebox_override(&"hover", sb)
	lb.add_theme_stylebox_override(&"pressed", sb)
	lb.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	var tr := TextureRect.new()
	tr.texture = _plate_texture
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var vs := get_viewport_rect().size
	tr.custom_minimum_size = Vector2(vs.x * 0.86, vs.y * 0.82)
	v.add_child(FFUI.plate_frame(tr, FFUI.VERDIGRIS))
	var cap := FFUI.label(_plate_caption.text, 13, FFUI.PARCHMENT_2, false)
	cap.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	center.add_child(v)
	lb.add_child(center)
	lb.pressed.connect(lb.queue_free)
	add_child(lb)


## Open the section with an ORNAMENTED illuminated drop-cap: a large Uncial versal in
## Ledger Verdigris, inked + shadowed so it sits pressed/gilded into the page, followed
## by the opening word in engraved small-caps, then the flowing body prose. The whole
## look lives in FFUI.illuminated_cap so every book screen reads as one manuscript.
## The section number stays hidden in faithful mode.
func _drop_cap(text: String) -> String:
	return FFUI.illuminated_cap(text)


func _render_choices(section: IFSection) -> void:
	var raw := section.choices()
	var player_choices := []
	for ch in raw:
		if not str(ch.get("id", "")).begins_with("_"):
			player_choices.append(ch)

	if player_choices.is_empty():
		var b := FFUI.choice_button("Return to the menu")
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func() -> void: NoxShell.to_menu())
		_actions.add_child(b)
		b.grab_focus()
		return

	# forced continue: a single unconditional choice reads "Turn the page"
	if player_choices.size() == 1 and (player_choices[0].get("conditions", null) == null):
		var only: Dictionary = player_choices[0]
		var cont := FFUI.choice_button(str(only.get("text", "Turn the page")) + "   ►")
		cont.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var cid := str(only.get("id"))
		cont.pressed.connect(func() -> void: _take(cid))
		_actions.add_child(cont)
		cont.grab_focus()
		return

	var visited := _visited_set()
	var first := true
	for ch in player_choices:
		var cid := str(ch.get("id", ""))
		var conds: Variant = ch.get("conditions", null)
		var met := Adventure.runner.state.conditions_met(conds)
		var b: Button
		if met:
			b = FFUI.choice_button(str(ch.get("text", cid)))
			b.pressed.connect(func() -> void: _take(cid))
			# already-read dimming: dim a choice whose destination was visited
			if visited.has(str(ch.get("goto", ""))):
				b.modulate = Color(1, 1, 1, 0.6)
			if first:
				b.grab_focus()
				first = false
		else:
			b = FFUI.choice_button(str(ch.get("text", cid)), true, _reason(conds))
		_actions.add_child(b)


func _render_inline_chips() -> void:
	# contextual action chips (WIREFRAMES 5.2): Eat is available whenever the hero
	# carries Provisions and isn't mid-encounter.
	if Adventure.sheet != null and Adventure.sheet.provisions > 0:
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override(&"separation", 8)
		var eat := FFUI.chip("🍖  Eat a Provision (+4 STAMINA)")
		eat.pressed.connect(_on_eat)
		chips.add_child(eat)
		_actions.add_child(chips)


# --- events -----------------------------------------------------------------


func _render_test(stat: String, section: IFSection) -> void:
	var prompt := str(section.raw().get("test_prompt", "Test your %s" % stat.capitalize()))
	var chip := FFUI.choice_button("🎲  Test your %s — %s" % [stat.capitalize(), prompt])
	chip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.pressed.connect(func() -> void: _do_test(stat))
	_actions.add_child(chip)
	chip.grab_focus()


func _do_test(stat: String) -> void:
	if _busy:
		return
	_busy = true
	var outcome := ""
	if stat == "luck":
		var lr := Adventure.test_luck()
		await _show_dice_test(lr, "TEST YOUR LUCK", "≤ LUCK %d" % int(lr.target),
			"LUCKY!" if lr.lucky else "UNLUCKY", FFUI.VERDIGRIS if lr.lucky else FFUI.ARREARS,
			"LUCK %d → %d  (−1)" % [int(lr.luck_before), int(lr.luck_after)])
		outcome = "_onlucky" if lr.lucky else "_onunlucky"
	else:
		var r := Adventure.test_attribute(stat)
		await _show_dice_test(r, "TEST YOUR %s" % stat.to_upper(), "≤ %s %d" % [stat.to_upper(), int(r.target)],
			"SUCCESS" if r.success else "FAILURE", FFUI.VERDIGRIS if r.success else FFUI.ARREARS, "")
		outcome = "_onsuccess" if r.success else "_onfailure"
	_event_resolved = true
	_busy = false
	_take(outcome)


func _enter_combat(section: IFSection) -> void:
	if _combat_open:
		return
	_combat_open = true
	var enc := FFEncounter.from_passage(section.raw())
	var outcomes := {
		"win": _outcome_id(section, "_onwin"),
		"death": _outcome_id(section, "_ondeath"),
		"escape": _outcome_id(section, "_onescape"),
	}
	var cv := COMBAT_VIEW.instantiate()
	cv.setup(enc, outcomes, _current_id)
	cv.resolved.connect(_on_combat_resolved)
	add_child(cv)


func _on_combat_resolved(outcome_id: String) -> void:
	# tally a defeated foe for the run-stats screens
	if outcome_id.begins_with("_onwin") and Adventure.runner != null:
		Adventure.runner.state.add_var("foes_defeated", 1)
	_event_resolved = true
	_free_children_of_type("combat")
	_take(outcome_id)


func _outcome_id(section: IFSection, wanted: String) -> String:
	for ch in section.choices():
		if str(ch.get("id", "")) == wanted:
			return wanted
	return wanted


func _take(choice_id: String) -> void:
	# free any lingering combat overlay
	for c in get_children():
		if c is Control and c.has_method("setup") and c.has_signal("resolved"):
			c.queue_free()
	Adventure.choose(choice_id)


# --- overlays / quick-row ---------------------------------------------------


func _open_sheet() -> void:
	add_child(ADVENTURE_SHEET.instantiate())


func _open_inventory() -> void:
	add_child(INVENTORY.instantiate())


func _open_map() -> void:
	add_child(MAP_VIEW.instantiate())


func _open_pause() -> void:
	if _pause != null and _pause.has_method("toggle"):
		_pause.toggle()


func _quick_save() -> void:
	# Route through the SaveManager (atomic slot write, GDD §5 FFGameState) so the HUD
	# Quick-Save, Continue and the Save/Load picker all share one save layer.
	var err := SaveManager.quick_save()
	_toast(("Progress saved  ·  §%s" % _current_id) if err == OK else "Save failed")


func _toggle_bookmark() -> void:
	var key := "bookmark_" + _current_id
	var on := not bool(GameManager.get_flag(key, false))
	GameManager.set_flag(key, on)
	_bookmark_btn.modulate = FFUI.FLAME if on else Color.WHITE
	_toast("Bookmark set" if on else "Bookmark removed")


func _on_eat() -> void:
	if Adventure.sheet.eat_provision():
		AudioDirector.play_sfx("eat")
		Adventure.notify_sheet_changed()
		_toast("+4 STAMINA")
		_render()


func _on_hero_died() -> void:
	# combat routes death through an ending passage; a test that zeroes STAMINA with
	# no ending falls through to here.
	if not Adventure.is_ended():
		call_deferred("_goto_end", "death")


func _goto_end(kind: String) -> void:
	if kind == "victory":
		get_tree().change_scene_to_file(VICTORY_SCREEN)
	else:
		# Ironman is restart-on-death with no reload — wipe the run's save (GDD §4).
		var sm := get_node_or_null("/root/SaveManager")
		if sm != null:
			sm.on_death()
		get_tree().change_scene_to_file(DEATH_SCREEN)


# --- dice overlay -----------------------------------------------------------


func _show_dice_test(res: Dictionary, context: String, compare_label: String, banner: String, banner_color: Color, depletion: String) -> void:
	var pop := DICE_POPUP.instantiate()
	add_child(pop)
	var ff := get_node_or_null("/root/FFSettings")
	# Reduced-motion OR animation-off both snap the dice; speed scales the tumble.
	var reduced: bool = ff != null and (ff.reduced_motion or not ff.dice_animation)
	var speed: float = ff.dice_speed if ff != null else 1.0
	await pop.run_test({
		"context": context,
		"faces": res.faces, "total": int(res.total),
		"compare_label": compare_label,
		"banner": banner, "banner_color": banner_color,
		"depletion": depletion,
		"reduced_motion": reduced,
		"speed": speed,
	})
	pop.queue_free()


# --- HUD --------------------------------------------------------------------


func _refresh_hud() -> void:
	_hud_section.text = "§ %s" % _current_id
	var s := Adventure.sheet
	if _dock_stats == null:
		return
	_clear(_dock_stats)
	if s == null:
		return
	_check_economy_sfx(s)
	_dock_stats.add_child(_dock_stat("SKILL", s.cur("skill"), s.init_of("skill"), FFUI.VERDIGRIS))
	_dock_stats.add_child(_dock_stat("STAMINA", s.cur("stamina"), s.init_of("stamina"), FFUI.ARREARS))
	_dock_stats.add_child(_dock_stat("LUCK", s.cur("luck"), s.init_of("luck"), FFUI.FLAME))
	var rule := FFUI.diamond_rule(FFUI.UMBER)
	rule.custom_minimum_size = Vector2(0, 10)
	_dock_stats.add_child(rule)
	var purse := HBoxContainer.new()
	purse.alignment = BoxContainer.ALIGNMENT_CENTER
	purse.add_theme_constant_override(&"separation", 6)
	purse.add_child(FFUI.handwritten("%dg" % s.gold, 16, FFUI.INK_PEN, "dock_gold_%d" % s.gold))
	purse.add_child(FFUI.handwritten("×%d🍖" % s.provisions, 16, FFUI.INK_PEN, "dock_prov_%d" % s.provisions))
	_dock_stats.add_child(purse)


## A quiet gold-clink when the purse grows and a pack-rustle when an item is added
## (STYLE_GUIDE §2.3 — the coin reinforces the economy motif). Diffs against the
## last HUD refresh so it only fires on a genuine gain, never on first paint.
func _check_economy_sfx(s: Object) -> void:
	var gold := int(s.gold)
	var inv_ct: int = s.state.inventory().size() if s.state != null else 0
	if _last_gold >= 0 and gold > _last_gold:
		AudioDirector.play_sfx("coin")
	elif _last_inv >= 0 and inv_ct > _last_inv:
		AudioDirector.play_sfx("pickup")
	_last_gold = gold
	_last_inv = inv_ct


# --- helpers ----------------------------------------------------------------


func _visited_set() -> Dictionary:
	var out := {}
	if Adventure.runner != null:
		for p in Adventure.runner.state.passage_history:
			out[str(p)] = true
	return out


func _reason(conds: Variant) -> String:
	var parts: Array[String] = []
	_reason_walk(conds, parts)
	if parts.is_empty():
		return "locked"
	return "Needs: " + ", ".join(parts)


func _reason_walk(conds: Variant, parts: Array[String]) -> void:
	if conds == null:
		return
	if conds is Array:
		for c in conds:
			_reason_walk(c, parts)
		return
	if not (conds is Dictionary):
		return
	var c: Dictionary = conds
	match str(c.get("kind", "var")):
		"all", "any":
			for sub in c.get("of", []):
				_reason_walk(sub, parts)
		"not":
			pass   # an absence gate (e.g. already have the Seal) — not shown as a need
		"item":
			parts.append(_pretty(str(c.get("key", "item"))))
		"var":
			if str(c.get("key")) == "gold":
				parts.append("%d Gold" % int(c.get("value", 0)))
			else:
				parts.append("%s %d" % [str(c.get("key")), int(c.get("value", 0))])
		"resource":
			parts.append("%d %s" % [int(c.get("value", 0)), _pretty(str(c.get("key", "")))])
		"codeword":
			parts.append(str(c.get("key", "")))
		"flag":
			parts.append(_pretty(str(c.get("key", ""))))


func _pretty(s: String) -> String:
	return s.replace("_", " ").capitalize()


func _toast(msg: String) -> void:
	var panel := FFUI.panel(Color("2a2119"), FFUI.VERDIGRIS)
	panel.add_child(FFUI.label(msg, 15, FFUI.PARCHMENT))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position.y -= 96
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(panel)
	var tw := create_tween()
	tw.tween_interval(1.3)
	tw.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.5)
	tw.tween_callback(panel.queue_free)


func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


func _free_children_of_type(_kind: String) -> void:
	for c in get_children():
		if c is Control and c.has_method("setup") and c.has_signal("resolved"):
			c.queue_free()


func _esc_event() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	return e
