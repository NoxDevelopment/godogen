extends Control
## res://scripts/screens/roll_up.gd
## Character Creation / Roll-Up (WIREFRAMES 5.7, GDD §6.1 #3, ADVENTURE_SHEET_SPEC
## §5; LOOKFEEL_PASS_2026-07 §roll-up — "a ritual, not a form"). The engine has
## ALREADY rolled the ONE authoritative sheet inside Adventure.new_adventure()
## (SKILL 1d6+6, STAMINA 2d6+12, LUCK 1d6+6 from the ff-2d6 ruleset); this screen
## DRAMATIZES that honest roll the way FFC/Veritas stage it:
##
##   * a blank Adventure-Sheet CARD lies on the page;
##   * each stat is thrown ONE AT A TIME through the 3D bone-dice tray with a
##     printed stage line ("The dice will write your SKILL…") and a beat;
##   * the rolled value is PENNED into that stat's INITIAL and NOW boxes in the
##     player's handwriting (fade + settle), with the quality read beneath;
##   * the starting kit is laid out visually — icon + hand-written ledger line;
##   * the Potion is an IN-FICTION choice: a paragraph of flavor prose and three
##     labelled flasks (the apothecary's offer), not a settings radio.
##
## Faithful: values come from Adventure.sheet; the dice only perform them.
## Begin enters §1; Reroll tears off a fresh sheet. NO dice are rolled in the UI.

const READING_VIEW := "res://scenes/reading_view.tscn"

const POTIONS := [
	{"id": "skill", "name": "Potion of Skill", "icon": "potion_skill", "blurb": "Restores SKILL to its Initial value."},
	{"id": "strength", "name": "Potion of Strength", "icon": "potion_strength", "blurb": "Restores STAMINA to its Initial value."},
	{"id": "fortune", "name": "Potion of Fortune", "icon": "potion_fortune", "blurb": "Restores LUCK, and raises Initial LUCK by 1."},
]

const POTION_PROSE := "Before the coach departs, the apothecary at the toll-road's end unwraps three stoppered flasks from oilcloth and sets them on the counter. \"One,\" she says, \"and one only. The road north does not sell second chances.\""

const STAT_META := [
	{"key": "skill", "name": "SKILL", "formula": "1d6 + 6", "dice": 1,
		"stage": "First, the dice will write your SKILL — your craft with blade, tongue and wit."},
	{"key": "stamina", "name": "STAMINA", "formula": "2d6 + 12", "dice": 2,
		"stage": "Now your STAMINA — the flesh's stubborn refusal to be collected."},
	{"key": "luck", "name": "LUCK", "formula": "1d6 + 6", "dice": 1,
		"stage": "Last, your LUCK — whatever the Grey Ledger has not yet counted against you."},
]


static func _accent(key: String) -> Color:
	match key:
		"skill": return FFUI.VERDIGRIS
		"stamina": return FFUI.ARREARS
		"luck": return FFUI.FLAME
		_: return FFUI.UMBER

var _tray: Dice3DTray
var _dice_area: HBoxContainer
var _stage_line: Label
var _init_holder := {}          # stat -> CenterContainer for the INITIAL value
var _now_holder := {}           # stat -> CenterContainer for the NOW value
var _quality := {}              # stat -> Label
var _stat_panels := {}          # stat -> the block panel (highlighted while rolling)
var _equipment_box: VBoxContainer
var _name_edit: LineEdit
var _potion_cards := {}
var _chosen_potion := ""
var _begin: Button
var _reroll: Button
var _hint: Label
var _rolling := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(FFUI.paper_ground())
	_build()
	if not Adventure.has_run():
		Adventure.new_adventure()
	await _reveal_roll(false)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(880, 0)
	col.add_theme_constant_override(&"separation", 10)
	center.add_child(col)

	col.add_child(FFUI.engraved_header("ROLL UP YOUR HERO", 32, FFUI.INK, FFUI.VERDIGRIS))
	# the roll-up belongs to the ACTIVE book from the Library shelf
	var book: Dictionary = Adventure.book()
	var tagline := "The book is open. The first section is waiting."
	if not book.is_empty():
		tagline = "%s  ·  by %s" % [str(book.get("title", "?")), str(book.get("author", "?"))]
	var tag := FFUI.label(tagline, 14, FFUI.UMBER)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)

	# --- the ritual stage: the printed stage line + the shared 3D dice tray ----
	_stage_line = FFUI.label("The dice are waiting.", 17, FFUI.INK)
	_stage_line.add_theme_font_override(&"font", FFUI.font_body())
	_stage_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_stage_line)
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

	# --- THE SHEET CARD — the paper the ritual writes onto ---------------------
	var card := FFUI.framed_panel(FFUI.UMBER)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sheet := VBoxContainer.new()
	sheet.add_theme_constant_override(&"separation", 8)
	card.add_child(sheet)

	var mast := FFUI.label("ADVENTURE SHEET", 15, FFUI.INK, false)
	mast.add_theme_font_override(&"font", FFUI.font_display_tracked(3))
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.add_child(mast)

	# name on a write-line (the first proof a person filled this in)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 10)
	var name_cap := FFUI.label("NAME", 13, FFUI.INK, false)
	name_cap.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	name_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(name_cap)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "write your hero's name…"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_override(&"font", FFUI.font_hand())
	_name_edit.add_theme_font_size_override(&"font_size", 24)
	_name_edit.add_theme_color_override(&"font_color", FFUI.INK_PEN)
	var le_sb := StyleBoxFlat.new()
	le_sb.bg_color = Color(0, 0, 0, 0)
	le_sb.border_color = Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.6)
	le_sb.border_width_bottom = 1
	le_sb.content_margin_left = 6
	le_sb.content_margin_top = 2
	le_sb.content_margin_bottom = 2
	_name_edit.add_theme_stylebox_override(&"normal", le_sb)
	_name_edit.add_theme_stylebox_override(&"focus", le_sb)
	_name_edit.text = Adventure.sheet.hero_name if Adventure.has_run() else ""
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)
	sheet.add_child(name_row)

	# the three INITIAL / NOW stat blocks (the sheet idiom)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override(&"separation", 12)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in STAT_META:
		stats.add_child(_stat_block(m))
	sheet.add_child(stats)

	# starting kit, laid out visually: icon + hand-written ledger line
	var eq_cap := FFUI.label("EQUIPMENT & JEWELS", 13, FFUI.VERDIGRIS, false)
	eq_cap.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	sheet.add_child(eq_cap)
	_equipment_box = VBoxContainer.new()
	_equipment_box.add_theme_constant_override(&"separation", 2)
	sheet.add_child(_equipment_box)
	col.add_child(card)

	# --- the apothecary's offer (the potion, in fiction) -----------------------
	var offer := FFUI.rich(16)
	offer.text = "[i]%s[/i]" % POTION_PROSE
	offer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(offer)
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
	_reroll.custom_minimum_size = Vector2(0, 52)
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
	_hint = FFUI.label("Take a flask to begin.", 13, FFUI.UMBER)
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)


## A roll-up stat block styled like the Adventure Sheet's INITIAL / NOW box.
func _stat_block(m: Dictionary) -> Control:
	var accent: Color = _accent(str(m.key))
	var panel := FFUI.panel(Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.35), accent)
	_stat_panels[str(m.key)] = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	panel.add_child(v)
	var hdr := FFUI.label(str(m.name), 15, FFUI.INK, false)
	hdr.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hdr)
	var rule := FFUI.diamond_rule(accent)
	rule.custom_minimum_size = Vector2(0, 8)
	v.add_child(rule)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override(&"separation", 8)
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cells.add_child(_stat_cell("INITIAL", m.key, _init_holder))
	cells.add_child(_stat_cell("NOW", m.key + "_now", _now_holder))
	v.add_child(cells)
	var formula := FFUI.label("= " + str(m.formula), 11, FFUI.FEN)
	formula.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(formula)
	var q := FFUI.label("", 13, FFUI.UMBER)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quality[m.key] = q
	v.add_child(q)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return panel


func _stat_cell(caption: String, holder_key: String, holder_map: Dictionary) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.35)
	sb.border_color = Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.65)
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override(&"panel", sb)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	var cap := FFUI.label(caption, 10, FFUI.FEN, false)
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
	var rows: Array = []
	for item in Adventure.sheet.equipment:
		rows.append({"icon": _item_icon(item), "text": _pretty(item)})
	rows.append({"icon": "provisions", "text": "%d Provisions" % Adventure.sheet.provisions})
	rows.append({"icon": "gold", "text": "%d Gold pieces" % Adventure.sheet.gold})
	for r in rows:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 30)
		row.add_theme_constant_override(&"separation", 8)
		var tex := FFUI.icon(str(r.icon))
		if tex != null:
			var tr := TextureRect.new()
			tr.custom_minimum_size = Vector2(24, 24)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tr.texture = tex
			row.add_child(tr)
		var lbl := FFUI.handwritten(str(r.text), 20, FFUI.INK_PEN, "rollup_eq_%s" % r.text)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lbl)
		_equipment_box.add_child(row)


func _item_icon(item: String) -> String:
	match item:
		"sword": return "sword"
		"leather armour", "leather_armour": return "leather_armour"
		"lantern": return "lantern"
		_: return "ledger"


func _pretty(item: String) -> String:
	return item.replace("_", " ").capitalize()


## A flask on the apothecary's counter: icon, engraved name, the printed effect.
func _potion_card(p: Dictionary) -> Control:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(200, 150)
	b.add_theme_stylebox_override(&"normal", FFUI.panel_box(Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.4), Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.7), 1, 3))
	b.add_theme_stylebox_override(&"hover", FFUI.panel_box(Color("ece2c6"), FFUI.VERDIGRIS, 1, 3))
	b.add_theme_stylebox_override(&"pressed", FFUI.panel_box(Color("dfe7dd"), FFUI.VERDIGRIS, 2, 3))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
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
	var nm := FFUI.label(str(p.name), 14, FFUI.INK, false)
	nm.add_theme_font_override(&"font", FFUI.font_display_tracked(1))
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
	_update_begin()
	if _hint != null and is_instance_valid(_hint):
		_hint.queue_free()
		_hint = null


## Begin is enabled the moment BOTH gates are true (fixes the "Begin still
## disabled after choosing a potion + roll settled" race — one evaluator, called
## from both paths).
func _update_begin() -> void:
	if _begin != null:
		_begin.disabled = _rolling or _chosen_potion == ""


func _on_name_changed(txt: String) -> void:
	if Adventure.has_run():
		Adventure.sheet.hero_name = txt.strip_edges()


# --- Roll + hand-write onto the sheet ---------------------------------------


## The ritual: for each stat — stage line, highlight its block, throw its dice
## through the tray, pen the value into INITIAL and NOW, a beat — then lay out
## the kit. Faithful: values come from Adventure.sheet (already rolled by the
## engine); the dice only perform them.
func _reveal_roll(_reroll_flag: bool) -> void:
	_rolling = true
	_update_begin()
	# clear any previously-penned values
	for k in _init_holder:
		for c in _init_holder[k].get_children():
			c.queue_free()
	for k in _now_holder:
		for c in _now_holder[k].get_children():
			c.queue_free()
	for m in STAT_META:
		var key: String = m.key
		if _stage_line != null:
			_stage_line.text = str(m.get("stage", ""))
		_highlight_block(key, true)
		var value := Adventure.sheet.cur(key)
		var faces := _faces_for(key, value)
		await _throw(faces)
		await _pen_score(key, value)
		_highlight_block(key, false)
	if _stage_line != null:
		_stage_line.text = "The sheet is written. What is rolled cannot be unrolled."
	_rolling = false
	_render_equipment()
	_update_begin()


func _highlight_block(key: String, on: bool) -> void:
	var panel: Control = _stat_panels.get(key)
	if panel == null:
		return
	panel.modulate = Color(1.08, 1.06, 1.0) if on else Color.WHITE


## Derive plausible honest die faces that sum to the authoritative rolled value.
func _faces_for(key: String, value: int) -> Array:
	if key == "stamina":
		var sum := value - 12
		var a := clampi(sum - 6, 1, 6)
		var b := clampi(sum - a, 1, 6)
		return [a, b]
	return [clampi(value - 6, 1, 6)]


## Throw the dice for drama. Uses the 3D physics tray when available (its public
## roll() API), else honest-pips 2D FFDie. Reduced-motion / headless snap instantly.
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
