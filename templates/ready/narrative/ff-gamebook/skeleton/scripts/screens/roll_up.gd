extends Control
## res://scripts/screens/roll_up.gd
## Character Creation / Roll-Up (WIREFRAMES 5.7, GDD §6.1 #3, ADVENTURE_SHEET_SPEC §5).
## The engine has ALREADY rolled the ONE authoritative sheet inside
## Adventure.new_adventure() (SKILL 1d6+6, STAMINA 2d6+12, LUCK 1d6+6 from the ff-2d6
## ruleset); this screen DRAMATIZES that honest roll and WRITES IT ONTO THE SHEET BY
## HAND. Each stat is thrown through the shared 3D physics dice tray (Dice3DTray, its
## public `roll()` API) — honest + deterministic: the tray only performs the faces the
## seeded core already fixed — then the rolled number is *penned* into that stat's
## INITIAL and NOW boxes (a fade+scale "the pen writes it" reveal) in the handwriting
## face. The player names their hero, the granted starting kit is shown hand-written in
## the Equipment ledger, and one Potion is chosen. Begin enters §1; Reroll tears off a
## fresh sheet. NO dice are rolled in the UI.

const READING_VIEW := "res://scenes/reading_view.tscn"

const POTIONS := [
	{"id": "skill", "name": "Potion of Skill", "icon": "potion_skill", "blurb": "Restores SKILL to its Initial value."},
	{"id": "strength", "name": "Potion of Strength", "icon": "potion_strength", "blurb": "Restores STAMINA to its Initial value."},
	{"id": "fortune", "name": "Potion of Fortune", "icon": "potion_fortune", "blurb": "Restores LUCK, and raises Initial LUCK by 1."},
]

const STAT_META := [
	{"key": "skill", "name": "SKILL", "formula": "1d6 + 6", "dice": 1},
	{"key": "stamina", "name": "STAMINA", "formula": "2d6 + 12", "dice": 2},
	{"key": "luck", "name": "LUCK", "formula": "1d6 + 6", "dice": 1},
]


static func _accent(key: String) -> Color:
	match key:
		"skill": return FFUI.VERDIGRIS
		"stamina": return FFUI.ARREARS
		"luck": return FFUI.FLAME
		_: return FFUI.UMBER

var _tray: Dice3DTray
var _dice_area: HBoxContainer
var _init_holder := {}          # stat -> CenterContainer for the INITIAL value
var _now_holder := {}           # stat -> CenterContainer for the NOW value
var _quality := {}              # stat -> Label
var _equipment_box: VBoxContainer
var _name_edit: LineEdit
var _name_echo: Label
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
	col.custom_minimum_size = Vector2(620, 0)
	col.add_theme_constant_override(&"separation", 12)
	center.add_child(col)

	var head := FFUI.title("ROLL UP YOUR HERO", 34, FFUI.INK)
	col.add_child(head)
	col.add_child(FFUI.label("The last coach north has already gone. The Verge is waiting.", 15, FFUI.UMBER))

	# --- Name your hero (printed caption, handwriting on a write-line) ---------
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 10)
	var name_cap := FFUI.label("NAME", 15, FFUI.INK, false)
	name_cap.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	name_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(name_cap)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "write your hero's name…"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_override(&"font", FFUI.font_hand())
	_name_edit.add_theme_font_size_override(&"font_size", 24)
	_name_edit.add_theme_color_override(&"font_color", FFUI.INK_PEN)
	_name_edit.text = Adventure.sheet.hero_name if Adventure.has_run() else ""
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)
	col.add_child(name_row)
	_name_echo = FFUI.handwritten("", 22, FFUI.INK_PEN, "rollup_name")
	col.add_child(_name_echo)

	col.add_child(FFUI.divider_rule())

	# --- The shared 3D dice tray (honest physics performance) ------------------
	var tray_center := CenterContainer.new()
	tray_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray = Dice3DTray.new()
	_tray.visible = false
	tray_center.add_child(_tray)
	col.add_child(tray_center)
	# 2D honest-pips fallback dice (used when 3D is off / reduced-motion / headless)
	_dice_area = HBoxContainer.new()
	_dice_area.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_area.add_theme_constant_override(&"separation", 12)
	col.add_child(_dice_area)

	# --- Three INITIAL / NOW stat blocks (the sheet idiom) ---------------------
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override(&"separation", 12)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in STAT_META:
		stats.add_child(_stat_block(m))
	col.add_child(stats)

	col.add_child(FFUI.divider_rule())

	# --- Starting kit, hand-written into the Equipment ledger ------------------
	var eq_cap := FFUI.label("EQUIPMENT & JEWELS", 15, FFUI.VERDIGRIS, false)
	eq_cap.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	col.add_child(eq_cap)
	_equipment_box = VBoxContainer.new()
	_equipment_box.add_theme_constant_override(&"separation", 2)
	col.add_child(_equipment_box)
	_render_equipment()

	# --- Potion chooser --------------------------------------------------------
	col.add_child(FFUI.label("CHOOSE ONE POTION", 16, FFUI.INK, false))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override(&"separation", 12)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for p in POTIONS:
		cards.add_child(_potion_card(p))
	col.add_child(cards)

	# --- Actions ---------------------------------------------------------------
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 12)
	_reroll = FFUI.chip("↻ Tear off a fresh sheet  (reroll)")
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


## A roll-up stat block styled like the Adventure Sheet's INITIAL / NOW box.
func _stat_block(m: Dictionary) -> Control:
	var accent: Color = _accent(str(m.key))
	var panel := FFUI.panel(FFUI.PARCHMENT_2, accent)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	panel.add_child(v)
	var hdr := FFUI.label(str(m.name), 16, FFUI.INK, false)
	hdr.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hdr)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override(&"separation", 8)
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cells.add_child(_stat_cell("INITIAL", m.key, _init_holder))
	cells.add_child(_stat_cell("NOW", m.key + "_now", _now_holder))
	v.add_child(cells)
	var formula := FFUI.label("= " + str(m.formula), 12, FFUI.FEN)
	formula.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(formula)
	var q := FFUI.label("", 14, FFUI.UMBER)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quality[m.key] = q
	v.add_child(q)
	return panel


func _stat_cell(caption: String, holder_key: String, holder_map: Dictionary) -> Control:
	var box := FFUI.panel(Color("ded0ac"), Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.6))
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	var cap := FFUI.label(caption, 11, FFUI.FEN, false)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(46, 40)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder_map[holder_key] = holder
	v.add_child(holder)
	box.add_child(v)
	return box


func _render_equipment() -> void:
	for c in _equipment_box.get_children():
		c.queue_free()
	if not Adventure.has_run():
		return
	for item in Adventure.sheet.equipment:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)
		var lbl := FFUI.handwritten("— " + _pretty(item), 20, FFUI.INK_PEN, "rollup_eq_%s" % item)
		row.add_child(lbl)
		_equipment_box.add_child(row)
	# provisions + gold, also hand-written into the ledger
	var pr := FFUI.handwritten("— %d Provisions" % Adventure.sheet.provisions, 20, FFUI.INK_PEN, "rollup_prov")
	_equipment_box.add_child(pr)
	var gd := FFUI.handwritten("— %d Gold pieces" % Adventure.sheet.gold, 20, FFUI.INK_PEN, "rollup_gold")
	_equipment_box.add_child(gd)


func _pretty(item: String) -> String:
	return item.replace("_", " ").capitalize()


func _potion_card(p: Dictionary) -> Control:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(180, 150)
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
	if not _rolling:
		_begin.disabled = false
	var hint := find_child("Hint", false, false)
	if hint: hint.queue_free()


func _on_name_changed(txt: String) -> void:
	if Adventure.has_run():
		Adventure.sheet.hero_name = txt.strip_edges()
	_name_echo.text = txt.strip_edges()


# --- Roll + hand-write onto the sheet ---------------------------------------


## Roll each stat through the dice tray, then WRITE its rolled value into the INITIAL
## and NOW boxes by hand. Faithful: the values come from Adventure.sheet (already
## rolled by the engine); the dice only perform them.
func _reveal_roll(_reroll_flag: bool) -> void:
	_rolling = true
	_begin.disabled = true
	# clear any previously-penned values
	for k in _init_holder:
		for c in _init_holder[k].get_children():
			c.queue_free()
	for k in _now_holder:
		for c in _now_holder[k].get_children():
			c.queue_free()
	for m in STAT_META:
		var key: String = m.key
		var value := Adventure.sheet.cur(key)
		var faces := _faces_for(key, value)
		await _throw(faces)
		await _pen_score(key, value)
	_rolling = false
	_render_equipment()
	if _chosen_potion != "":
		_begin.disabled = false


## Derive plausible honest die faces that sum to the authoritative rolled value (the
## same honest derivation the old dramatised roll used).
func _faces_for(key: String, value: int) -> Array:
	if key == "stamina":
		var sum := value - 12
		var a := clampi(sum - 6, 1, 6)
		var b := clampi(sum - a, 1, 6)
		return [a, b]
	return [clampi(value - 6, 1, 6)]


## Throw the dice for drama. Uses the 3D physics tray when available (its public
## roll() API), else honest-pips 2D FFDice. Reduced-motion / headless snap instantly.
func _throw(faces: Array) -> void:
	for c in _dice_area.get_children():
		c.queue_free()
	if _reduced():
		_tray.visible = false
		return
	if _use_3d():
		_tray.visible = true
		var tints: Array = []
		for _i in faces.size():
			tints.append(Dice3DTray.BONE)
		await _tray.roll(faces, tints)
		return
	# 2D fallback: real FFDie faces, a short tumble settling on the rolled values.
	_tray.visible = false
	var dice: Array[FFDie] = []
	for _i in faces.size():
		var d := FFDie.new()
		d.custom_minimum_size = Vector2(64, 64)
		_dice_area.add_child(d)
		dice.append(d)
	var t := 0.0
	while t < 0.6:
		for d in dice:
			d.value = randi_range(1, 6)
		await get_tree().create_timer(0.06).timeout
		t += 0.09
	for i in dice.size():
		dice[i].value = int(faces[i])
	await get_tree().create_timer(0.15).timeout


## Write a rolled value into the INITIAL and NOW boxes with a "the pen writes it"
## reveal (fade + slight scale). Reduced-motion snaps it in.
func _pen_score(key: String, value: int) -> void:
	var q: Dictionary = FFUI.roll_quality(key, value)
	if _quality.has(key):
		_quality[key].text = "●  " + str(q.tag)
		_quality[key].add_theme_color_override(&"font_color", q.color)
	for pair in [[_init_holder.get(key), "%s_init_%d" % [key, value]], [_now_holder.get(key + "_now"), "%s_now_%d" % [key, value]]]:
		var holder: CenterContainer = pair[0]
		if holder == null:
			continue
		for c in holder.get_children():
			c.queue_free()
		var lbl := FFUI.handwritten(str(value), 30, FFUI.INK_PEN, str(pair[1]))
		holder.add_child(lbl)
		if _reduced():
			continue
		lbl.modulate = Color(1, 1, 1, 0)
		lbl.scale = Vector2(1.35, 1.35)
		lbl.pivot_offset = Vector2(20, 20)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(lbl, "modulate:a", 1.0, 0.32)
		tw.tween_property(lbl, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await tw.finished
	await get_tree().create_timer(0.06).timeout


# --- Dice preference guards (mirror the dice overlay) -----------------------


func _reduced() -> bool:
	var ff := get_node_or_null("/root/FFSettings")
	return ff != null and (ff.reduced_motion or not ff.dice_animation)


func _use_3d() -> bool:
	if _reduced():
		return false
	if DisplayServer.get_name() == "headless":
		return false
	var ff := get_node_or_null("/root/FFSettings")
	return ff != null and bool(ff.dice_3d)


# --- Actions ----------------------------------------------------------------


func _on_reroll() -> void:
	if _rolling:
		return
	var kept_name := Adventure.sheet.hero_name if Adventure.has_run() else ""
	Adventure.new_adventure()
	# a fresh sheet keeps the hero's name the player already wrote
	if kept_name != "":
		Adventure.sheet.hero_name = kept_name
	await _reveal_roll(true)


func _on_begin() -> void:
	if _chosen_potion == "" or _rolling:
		return
	Adventure.sheet.hero_name = _name_edit.text.strip_edges()
	Adventure.sheet.potion = {"type": _chosen_potion, "doses": 2}
	Adventure.notify_sheet_changed()
	get_tree().change_scene_to_file(READING_VIEW)
