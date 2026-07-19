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
var _hud_stats: HBoxContainer
var _bookmark_btn: Button
var _plate_panel: Control
var _plate_divider: Control
var _plate_tex: TextureRect
var _plate_caption: Label
var _prose: RichTextLabel
var _heading: Label
var _content: VBoxContainer
var _actions: VBoxContainer
var _toast_layer: Control

var _current_id := ""
var _event_resolved := false
var _combat_open := false
var _busy := false
var _pause: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(FFUI.page_background())
	add_child(FFUI.wash(FFUI.FEN, 0.06))
	_build_ui()
	_pause = PAUSE_MENU.instantiate()
	add_child(_pause)

	Adventure.passage_changed.connect(_on_passage_changed)
	Adventure.sheet_changed.connect(_refresh_hud)
	Adventure.hero_died.connect(_on_hero_died)

	if not Adventure.has_run():
		Adventure.new_adventure()
	_sync_to_current()
	_render()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 18)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	margin.add_child(col)

	col.add_child(_build_hud())

	# scrolling page body — the sacred page. The ScrollContainer expands to claim all
	# vertical space left between the HUD and the choices, so the prose renders in full.
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

	# heading + drop-cap prose FIRST — "the page is sacred" (STYLE_GUIDE pillar #1).
	# The prose is the centerpiece: it must open at the top of the page and be visible
	# in full above the choices, never shouldered off-screen by the illustration.
	_heading = FFUI.title("", 24, FFUI.INK)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_heading)
	_prose = FFUI.rich(19, FFUI.INK)
	_prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prose.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_prose)

	# illustration plate — a modest accompanying vignette set BELOW the prose behind a
	# ruled divider, bound by STABLE ID through the AssetBinder (IFSection.illustration).
	# Sized so it never dominates the viewport nor pushes the prose out of view; a
	# centred, height-capped frame reads as an inset woodcut, not a banner.
	_plate_divider = FFUI.divider_rule()
	_content.add_child(_plate_divider)
	_plate_panel = FFUI.tex_framed(FFUI.VERDIGRIS)
	_plate_panel.custom_minimum_size = Vector2(0, 168)
	_plate_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_plate_tex = TextureRect.new()
	_plate_tex.custom_minimum_size = Vector2(440, 146)
	_plate_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plate_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_plate_panel.add_child(_plate_tex)
	_plate_caption = FFUI.label("", 12, FFUI.FEN)
	_plate_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_plate_panel)
	_content.add_child(_plate_caption)

	# actions (choices / event chips)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override(&"separation", 8)
	col.add_child(_actions)

	col.add_child(_build_quickrow())

	# toast layer
	_toast_layer = Control.new()
	_toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_layer)


func _build_hud() -> Control:
	var panel := FFUI.panel(Color("ded0ac"), Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	panel.add_child(row)
	var pause := FFUI.chip("☰")
	pause.pressed.connect(_open_pause)
	row.add_child(pause)
	_hud_section = FFUI.label("§ —", 15, FFUI.UMBER)
	_hud_section.custom_minimum_size = Vector2(64, 0)
	row.add_child(_hud_section)
	_hud_stats = HBoxContainer.new()
	_hud_stats.add_theme_constant_override(&"separation", 6)
	_hud_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hud_stats)
	_bookmark_btn = FFUI.chip("🔖")
	_bookmark_btn.pressed.connect(_toggle_bookmark)
	row.add_child(_bookmark_btn)
	return panel


func _build_quickrow() -> Control:
	var panel := FFUI.panel(Color("d8c9a6"), Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.5))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	panel.add_child(row)
	for spec in [["📜  Sheet", "_open_sheet"], ["🎒  Inventory", "_open_inventory"], ["🗺  Map", "_open_map"], ["💾  Save", "_quick_save"]]:
		var b := FFUI.chip(spec[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(Callable(self, spec[1]))
		row.add_child(b)
	return panel


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
	_content.modulate = Color(1, 1, 1, 0.0)
	var tw := create_tween()
	tw.tween_property(_content, "modulate", Color(1, 1, 1, 1.0), 0.22)


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
		_enter_combat(section)
		return
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
		_plate_panel.visible = false
		_plate_caption.visible = false
		_plate_divider.visible = false
		return
	_plate_panel.visible = true
	_plate_divider.visible = true
	var tex := FFUI.plate(slot)
	if tex != null:
		_plate_tex.texture = tex
		_plate_caption.visible = false
	else:
		_plate_tex.texture = null
		_plate_caption.visible = true
		_plate_caption.text = "[ %s — veritas-gamebook plate, awaiting generation ]" % slot


## Enlarge the first character (drop-cap feel) via inline bbcode; keeps the rest of
## the serif prose flowing. The section number stays hidden in faithful mode.
func _drop_cap(text: String) -> String:
	if text.strip_edges() == "":
		return text
	var first := text.substr(0, 1)
	var rest := text.substr(1)
	return "[color=#6e8f7a][font_size=52]%s[/font_size][/color]%s" % [first, rest]


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
	var data := Adventure.save_data()
	var f := FileAccess.open("user://ff_quicksave.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()
	_toast("Progress saved  ·  §%s" % _current_id)


func _toggle_bookmark() -> void:
	var key := "bookmark_" + _current_id
	var on := not bool(GameManager.get_flag(key, false))
	GameManager.set_flag(key, on)
	_bookmark_btn.modulate = FFUI.FLAME if on else Color.WHITE
	_toast("Bookmark set" if on else "Bookmark removed")


func _on_eat() -> void:
	if Adventure.sheet.eat_provision():
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
		get_tree().change_scene_to_file(DEATH_SCREEN)


# --- dice overlay -----------------------------------------------------------


func _show_dice_test(res: Dictionary, context: String, compare_label: String, banner: String, banner_color: Color, depletion: String) -> void:
	var pop := DICE_POPUP.instantiate()
	add_child(pop)
	await pop.run_test({
		"context": context,
		"faces": res.faces, "total": int(res.total),
		"compare_label": compare_label,
		"banner": banner, "banner_color": banner_color,
		"depletion": depletion,
	})
	pop.queue_free()


# --- HUD --------------------------------------------------------------------


func _refresh_hud() -> void:
	_hud_section.text = "§ %s" % _current_id
	var s := Adventure.sheet
	_clear(_hud_stats)
	if s == null:
		return
	_hud_stats.add_child(FFUI.stat_pill("SK", str(s.cur("skill")), FFUI.VERDIGRIS))
	_hud_stats.add_child(FFUI.stat_pill("ST", "%d/%d" % [s.cur("stamina"), s.init_of("stamina")], FFUI.ARREARS))
	_hud_stats.add_child(FFUI.stat_pill("LK", "%d/%d" % [s.cur("luck"), s.init_of("luck")], FFUI.FLAME))
	_hud_stats.add_child(FFUI.stat_pill("Gold", str(s.gold), FFUI.INK))
	_hud_stats.add_child(FFUI.stat_pill("Prov", str(s.provisions), FFUI.INK))


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
