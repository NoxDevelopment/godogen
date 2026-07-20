extends Control
## res://scripts/screens/roll_up.gd
## Character Creation / Roll-Up (WIREFRAMES 5.7, GDD §6.1 #3). The engine has
## already rolled the ONE authoritative sheet inside Adventure.new_adventure()
## (SKILL 1d6+6, STAMINA 2d6+12, LUCK 1d6+6 from the ff-2d6 ruleset); this screen
## DRAMATIZES that honest roll — animated per-stat dice settling on the rolled
## value, colour-coded roll quality (never punitive), the starting-kit summary, and
## a 3-card Potion chooser. Begin writes the chosen Potion onto the sheet and enters
## §1; Reroll re-rolls (a settings-gated accessibility aid). No dice are rolled here.

const READING_VIEW := "res://scenes/reading_view.tscn"

const POTIONS := [
	{"id": "skill", "name": "Potion of Skill", "icon": "potion_skill", "blurb": "Restores SKILL to its Initial value."},
	{"id": "strength", "name": "Potion of Strength", "icon": "potion_strength", "blurb": "Restores STAMINA to its Initial value."},
	{"id": "fortune", "name": "Potion of Fortune", "icon": "potion_fortune", "blurb": "Restores LUCK, and raises Initial LUCK by 1."},
]

var _stat_dice := {"skill": [], "stamina": [], "luck": []}
var _stat_value_labels := {}
var _stat_quality_labels := {}
var _potion_cards := {}
var _chosen_potion := ""
var _begin: Button
var _reroll: Button
var _rolling := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(FFUI.page_background())
	add_child(FFUI.wash(FFUI.FEN, 0.10))
	_build()
	if not Adventure.has_run():
		Adventure.new_adventure()
	await _reveal_roll(false)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 24)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(600, 0)
	col.add_theme_constant_override(&"separation", 14)
	center.add_child(col)

	var head := FFUI.title("ROLL UP YOUR HERO", 34, FFUI.INK)
	head.add_theme_font_override(&"font", FFUI.font_runic())
	col.add_child(head)
	col.add_child(FFUI.label("The last coach north has already gone. The Verge is waiting.", 15, FFUI.UMBER))
	col.add_child(FFUI.divider_rule())

	_add_stat_row(col, "skill", "SKILL", "1d6 + 6", 1)
	_add_stat_row(col, "stamina", "STAMINA", "2d6 + 12", 2)
	_add_stat_row(col, "luck", "LUCK", "1d6 + 6", 1)

	col.add_child(FFUI.divider_rule())

	# Starting kit
	var kit_panel := FFUI.panel()
	var kit := VBoxContainer.new()
	kit.add_theme_constant_override(&"separation", 8)
	kit_panel.add_child(kit)
	kit.add_child(FFUI.label("STARTING KIT", 15, FFUI.VERDIGRIS, false))
	var kit_row := HBoxContainer.new()
	kit_row.add_theme_constant_override(&"separation", 18)
	for item in [["sword", "Sword"], ["leather_armour", "Leather armour"], ["lantern", "Lantern"], ["provisions", "10 Provisions"], ["gold", "12 Gold"]]:
		kit_row.add_child(_icon_chip(item[0], item[1]))
	kit.add_child(kit_row)
	col.add_child(kit_panel)

	# Potion chooser
	col.add_child(FFUI.label("CHOOSE ONE POTION", 16, FFUI.INK, false))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override(&"separation", 12)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for p in POTIONS:
		cards.add_child(_potion_card(p))
	col.add_child(cards)

	# Actions
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 12)
	_reroll = FFUI.chip("↻ Reroll  (accessibility)")
	_reroll.custom_minimum_size = Vector2(0, 56)
	_reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reroll.pressed.connect(_on_reroll)
	actions.add_child(_reroll)
	_begin = FFUI.choice_button("Begin the descent  ▸")
	_begin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_begin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_begin.disabled = true
	_begin.pressed.connect(_on_begin)
	actions.add_child(_begin)
	col.add_child(actions)
	var hint := FFUI.label("Choose a potion to begin.", 14, FFUI.UMBER)
	hint.name = "Hint"
	col.add_child(hint)


func _add_stat_row(parent: Node, key: String, name: String, formula: String, dice_count: int) -> void:
	var panel := FFUI.panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	panel.add_child(row)
	var dice_box := HBoxContainer.new()
	dice_box.add_theme_constant_override(&"separation", 8)
	var dice := []
	for _i in dice_count:
		var d := FFDie.new()
		d.custom_minimum_size = Vector2(60, 60)
		dice_box.add_child(d)
		dice.append(d)
	_stat_dice[key] = dice
	row.add_child(dice_box)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	var nm := FFUI.label(name, 20, FFUI.INK, false)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	top.add_child(FFUI.label("= " + formula, 15, FFUI.UMBER))
	info.add_child(top)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 10)
	var val := FFUI.label("—", 30, FFUI.INK)
	val.add_theme_font_override(&"font", FFUI.font_display())
	_stat_value_labels[key] = val
	bottom.add_child(val)
	var qual := FFUI.label("", 16, FFUI.UMBER)
	_stat_quality_labels[key] = qual
	bottom.add_child(qual)
	info.add_child(bottom)
	row.add_child(info)
	parent.add_child(panel)


func _icon_chip(icon_name: String, text: String) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(40, 40)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := FFUI.icon(icon_name)
	if tex != null:
		tr.texture = tex
	box.add_child(tr)
	var l := FFUI.label(text, 13, FFUI.UMBER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


func _potion_card(p: Dictionary) -> Control:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(170, 150)
	b.add_theme_stylebox_override(&"normal", FFUI.panel_box(FFUI.PARCHMENT_2, FFUI.UMBER, 2, 6))
	b.add_theme_stylebox_override(&"hover", FFUI.panel_box(Color("e2d4b2"), FFUI.VERDIGRIS, 2, 6))
	b.add_theme_stylebox_override(&"pressed", FFUI.panel_box(Color("cfe0d4"), FFUI.VERDIGRIS, 3, 6))
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override(&"separation", 4)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(52, 52)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tex := FFUI.icon(str(p.icon))
	if tex != null: tr.texture = tex
	content.add_child(tr)
	var nm := FFUI.label(str(p.name), 15, FFUI.INK, false)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(nm)
	var bl := FFUI.label(str(p.blurb), 12, FFUI.UMBER)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(bl)
	b.add_child(content)
	b.pressed.connect(func() -> void: _select_potion(str(p.id)))
	_potion_cards[str(p.id)] = b
	return b


func _select_potion(id: String) -> void:
	_chosen_potion = id
	for pid in _potion_cards:
		_potion_cards[pid].button_pressed = (pid == id)
	_begin.disabled = false
	var hint := find_child("Hint", false, false)
	if hint: hint.queue_free()


func _reveal_roll(reroll: bool) -> void:
	_rolling = true
	_begin.disabled = true
	# tumble all stat dice, then settle on the engine's rolled values
	var all_dice: Array[FFDie] = []
	for k in _stat_dice:
		for d in _stat_dice[k]:
			all_dice.append(d)
	var t := 0.0
	while t < 0.7:
		for d in all_dice:
			d.value = randi_range(1, 6)
		await get_tree().create_timer(0.06).timeout
		t += 0.09
	_apply_stat("skill")
	_apply_stat("stamina")
	_apply_stat("luck")
	_rolling = false
	if _chosen_potion != "":
		_begin.disabled = false


func _apply_stat(key: String) -> void:
	var value := Adventure.sheet.cur(key)
	var dice: Array = _stat_dice[key]
	# derive plausible honest faces that sum to the rolled value
	if dice.size() == 1:
		dice[0].value = clampi(value - 6, 1, 6)
	else:
		var sum := value - 12
		var a := clampi(sum - 6, 1, 6)
		if a < 1: a = 1
		var b := clampi(sum - a, 1, 6)
		dice[0].value = a
		dice[1].value = b
	_stat_value_labels[key].text = str(value)
	var q := FFUI.roll_quality(key, value)
	_stat_quality_labels[key].text = "●  " + str(q.tag)
	_stat_quality_labels[key].add_theme_color_override(&"font_color", q.color)
	_stat_value_labels[key].add_theme_color_override(&"font_color", q.color)


func _on_reroll() -> void:
	if _rolling:
		return
	Adventure.new_adventure()
	await _reveal_roll(true)


func _on_begin() -> void:
	if _chosen_potion == "" or _rolling:
		return
	Adventure.sheet.potion = {"type": _chosen_potion, "doses": 2}
	Adventure.notify_sheet_changed()
	get_tree().change_scene_to_file(READING_VIEW)
