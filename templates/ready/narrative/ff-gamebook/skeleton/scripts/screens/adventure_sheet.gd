extends CanvasLayer
## res://scripts/screens/adventure_sheet.gd
## THE Adventure Sheet (WIREFRAMES 5.5, GDD §6.1 #8, ADVENTURE_SHEET_SPEC) — rendered
## to read as a REAL filled-in printed Fighting-Fantasy pen-and-paper form: a ruled,
## boxed monochrome form on aged, grained parchment with a double-ruled frame, corner
## ornaments and foxing, the classic INITIAL / NOW stat boxes, boxed Provisions / Gold
## / Potion, a ruled Equipment ledger, a Codewords & Notes panel, and the iconic dense
## MONSTER ENCOUNTER BOXES grid.
##
## TWO TYPOGRAPHIC LAYERS, never mixed (the core fix, spec §2/§3):
##   * PRINTED FORM — the engraved display face (Cinzel), tracked small-caps, in INK/FEN:
##     every caption/label/rule/masthead. These never move or look hand-drawn.
##   * HAND-ENTERED — the handwriting face (Caveat, OFL) in the player's own ink
##     (INK_PEN biro-blue for scores/name/kit, GRAPHITE pencil for encounter scratchings)
##     with a small SEEDED per-glyph jitter. Everything a person "wrote" onto the paper.
##
## The signature FF tell — a current score CROSSED OUT and re-written as it changes —
## is drawn by `_ScratchNumber` from the sheet's real value history. STAMINA is struck
## through when dead. The encounter grid AUTO-FILLS from the live FFCombat (via
## FFAdventureSheet.sync_encounters) and its STAMINA scratches down as foes are wounded.
##
## It stays a thin VIEW over the ONE shared FFAdventureSheet / IFState. Free-text fields
## (hero name, notes, blank encounter boxes) are lightly editable with a pencil ✎; but
## NUMBERS only ever change through the rules (apply_delta / drink_potion), so the
## never-exceed-Initial invariant is owned by the engine clamp and the view never writes
## a raw number. Esc / ✕ close.

signal closed

var _body: VBoxContainer
var _name_line: HBoxContainer
## The free-text field currently swapped into edit mode ("" = none). Only ONE at a
## time: "hero_name", "note_new", or "enc_new". Numbers are NEVER in this set.
var _editing: String = ""
## Sandbox/GM mode (default OFF = faithful): when ON a NOW score shows ± steppers that
## route through apply_delta, so the engine clamp STILL enforces never-exceed-Initial —
## the view never writes a raw number even in sandbox.
var _sandbox: bool = false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_render()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.03, 0.6)
	add_child(dim)

	# The sheet "page" is anchored to the viewport with fixed margins (not a fixed
	# height) so on a tall/desktop viewport the whole printed form is visible while a
	# short phone viewport scrolls it — the paper stays one continuous page either way.
	var ground := _Ground.new()
	ground.anchor_left = 0.5
	ground.anchor_right = 0.5
	ground.offset_left = -352.0
	ground.offset_right = 352.0
	ground.anchor_top = 0.0
	ground.anchor_bottom = 1.0
	ground.offset_top = 30.0
	ground.offset_bottom = -30.0
	add_child(ground)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 4)
	ground.add_child(outer)

	# --- Masthead (printed display face) + edit/close chrome ---------------
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	var t := FFUI.title("ADVENTURE SHEET", 30, FFUI.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var gm := FFUI.chip("✎ GM")
	gm.tooltip_text = "Sandbox mode: step scores (still clamped to Initial by the rules)."
	gm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gm.pressed.connect(func() -> void: _sandbox = not _sandbox; _render())
	head.add_child(gm)
	var x := FFUI.chip("✕")
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.pressed.connect(_close)
	head.add_child(x)
	outer.add_child(head)

	# --- Hero name line (handwriting on a write-line — first proof a person filled it in)
	_name_line = HBoxContainer.new()
	_name_line.add_theme_constant_override(&"separation", 8)
	outer.add_child(_name_line)

	var sub := FFUI.label("The Grey Tithe  ·  being a true & current account", 13, FFUI.UMBER, false)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(sub)
	outer.add_child(_TitleRule.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


func _render() -> void:
	var s := Adventure.sheet
	_render_name_line(s)
	for c in _body.get_children():
		c.queue_free()
	if s == null:
		return

	# --- STATS: the classic INITIAL / NOW boxes, NOW crossed-out-and-rewritten -
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override(&"separation", 10)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(_stat_field("skill", "SKILL", s.cur("skill"), s.init_of("skill"), FFUI.VERDIGRIS, false))
	stats.add_child(_stat_field("stamina", "STAMINA", s.cur("stamina"), s.init_of("stamina"), FFUI.ARREARS, true))
	stats.add_child(_stat_field("luck", "LUCK", s.cur("luck"), s.init_of("luck"), FFUI.FLAME, false))
	_body.add_child(stats)
	var caveat := FFUI.label("Current may fall in play but may never rise above its Initial value.", 12, FFUI.FEN, false)
	caveat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(caveat)

	# --- PROVISIONS / GOLD / POTION ---------------------------------------
	var cons := HBoxContainer.new()
	cons.add_theme_constant_override(&"separation", 10)
	cons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cons.add_child(_provisions_field(s.provisions))
	cons.add_child(_gold_field(s.gold))
	cons.add_child(_potion_field(s.potion))
	_body.add_child(cons)

	# --- EQUIPMENT (ruled ledger, hand-written) ---------------------------
	var eq_rows: Array = []
	for item in s.equipment:
		eq_rows.append({"icon": _item_icon(item), "text": _pretty(item), "hand": true, "color": FFUI.INK_PEN})
	_body.add_child(_titled_box("EQUIPMENT & JEWELS", FFUI.UMBER, _ruled_list(eq_rows, 5, "Your pack is empty.")))

	# --- CODEWORDS & NOTES (notes hand-written + tap-to-add) ---------------
	_body.add_child(_titled_box("CODEWORDS & NOTES", FFUI.VERDIGRIS, _codewords_notes(s), _pencil("note_new")))

	# --- MONSTER ENCOUNTER BOXES (the iconic dense FF grid) ---------------
	_body.add_child(_titled_box("MONSTER ENCOUNTER BOXES", FFUI.INK, _encounter_grid(s), _pencil("enc_new")))

	# --- THE GREY LEDGER (world's signature bookkeeping) ------------------
	var debt := int(Adventure.runner.state.get_var("tithe_debt")) if Adventure.runner != null else 0
	var led_row := HBoxContainer.new()
	led_row.add_theme_constant_override(&"separation", 8)
	led_row.add_child(FFUI.label("Tithe-debt owed to the Grey Ledger:", 15, FFUI.VERDIGRIS_2, false))
	led_row.add_child(_handwritten(str(debt), 20, FFUI.INK_PEN, "tithe_%d" % debt))
	_body.add_child(_titled_box("THE GREY LEDGER", FFUI.VERDIGRIS, led_row))


# --- Masthead hero-name line ------------------------------------------------


func _render_name_line(s: FFAdventureSheet) -> void:
	for c in _name_line.get_children():
		c.queue_free()
	var cap := _field_header("NAME", FFUI.INK, HORIZONTAL_ALIGNMENT_LEFT)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_line.add_child(cap)
	var name_text := s.hero_name if s != null else ""
	if _editing == "hero_name":
		var le := _line_edit(name_text, "write your hero's name…", func(txt: String) -> void:
			if s != null:
				s.hero_name = txt.strip_edges()
			_editing = ""
			Adventure.notify_sheet_changed()
			_render())
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name_line.add_child(le)
		le.call_deferred(&"grab_focus")
	else:
		var line := _WriteLine.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.custom_minimum_size = Vector2(0, 34)
		var lbl := _handwritten(name_text if name_text != "" else "—", 26, FFUI.INK_PEN, "hero_%s" % name_text, true)
		lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		lbl.offset_left = 6
		lbl.offset_top = -34
		line.add_child(lbl)
		_name_line.add_child(line)
		_name_line.add_child(_pencil("hero_name"))


# --- Field builders ---------------------------------------------------------


## A classic two-box stat block: printed name header, an INITIAL cell and a NOW cell.
## The NOW cell renders the crossed-out score history (spec §3). STAMINA also carries a
## thin wound-track bar, and is struck through when the hero is dead (STAMINA 0).
func _stat_field(stat: String, name: String, cur: int, init: int, accent: Color, with_bar: bool) -> Control:
	var dead := with_bar and Adventure.sheet != null and Adventure.sheet.is_dead()
	var box := _Boxed.new(accent, 2.0, true)
	box.strike = dead
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	var hdr := FFUI.label(name, 17, FFUI.INK, false)
	hdr.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hdr)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override(&"separation", 8)
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cells.add_child(_value_cell("INITIAL", str(init), FFUI.INK_PEN, false, "%s_init_%d" % [stat, init], []))
	# NOW never renders above INITIAL — the invariant, surfaced. History gives the
	# struck-through prior values so a fallen score reads "22̶ 18̶ 14" like real play.
	var shown_cur := mini(cur, init)
	cells.add_child(_value_cell("NOW", str(shown_cur), FFUI.INK_PEN, true, "%s_now_%d" % [stat, shown_cur], Adventure.sheet.history(stat)))
	v.add_child(cells)
	if _sandbox:
		v.add_child(_stat_stepper(stat))
	if with_bar:
		var bar := ProgressBar.new()
		bar.max_value = maxi(init, 1)
		bar.value = clampi(cur, 0, maxi(init, 1))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.3)
		bg.set_corner_radius_all(2)
		var fg := StyleBoxFlat.new()
		fg.bg_color = accent
		fg.set_corner_radius_all(2)
		bar.add_theme_stylebox_override(&"background", bg)
		bar.add_theme_stylebox_override(&"fill", fg)
		v.add_child(bar)
	box.add_child(v)
	return box


## A small bordered cell: a printed caption above the hand-written value. When `priors`
## is non-empty the value is drawn as a `_ScratchNumber` (struck ghosts + current);
## otherwise a plain jittered handwriting label.
func _value_cell(caption: String, value: String, color: Color, emphatic: bool, seed_key: String, priors: Array) -> Control:
	var cell := _Boxed.new(Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.65), 1.0, false)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	var cap := FFUI.label(caption, 11, FFUI.FEN, false)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var big := 30 if emphatic else 24
	if priors.is_empty():
		holder.add_child(_handwritten(value, big, color, seed_key))
	else:
		holder.add_child(_ScratchNumber.new().setup(priors, value, big, color, seed_key))
	v.add_child(holder)
	cell.add_child(v)
	return cell


## Optional sandbox ± steppers. They do NOT write numbers — they call apply_delta so the
## engine clamp enforces never-exceed-Initial (spec §7). Visible only in GM/sandbox mode.
func _stat_stepper(stat: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 8)
	var minus := FFUI.chip("−")
	minus.custom_minimum_size = Vector2(40, 34)
	minus.pressed.connect(func() -> void: _step_stat(stat, -1))
	row.add_child(minus)
	var plus := FFUI.chip("+")
	plus.custom_minimum_size = Vector2(40, 34)
	plus.pressed.connect(func() -> void: _step_stat(stat, 1))
	row.add_child(plus)
	return row


func _step_stat(stat: String, dir: int) -> void:
	Adventure.sheet.apply_delta({stat: dir})   # clamp lives in the rules/engine
	Adventure.notify_sheet_changed()
	_render()


func _provisions_field(count: int) -> Control:
	var box := _Boxed.new(FFUI.VERDIGRIS, 2.0, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	v.add_child(_field_header("PROVISIONS"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var tr := _small_icon("provisions")
	if tr != null:
		row.add_child(tr)
	row.add_child(_handwritten("×%d" % count, 26, FFUI.INK_PEN, "prov_%d" % count))
	v.add_child(row)
	var note := FFUI.label("+4 STAMINA each (up to Initial)", 11, FFUI.FEN, false)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	box.add_child(v)
	return box


func _gold_field(gold: int) -> Control:
	var box := _Boxed.new(FFUI.FLAME, 2.0, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	v.add_child(_field_header("GOLD"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var tr := _small_icon("gold")
	if tr != null:
		row.add_child(tr)
	row.add_child(_handwritten(str(gold), 26, FFUI.INK_PEN, "gold_%d" % gold))
	v.add_child(row)
	var note := FFUI.label("gold pieces", 11, FFUI.FEN, false)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	box.add_child(v)
	return box


func _potion_field(pot: Dictionary) -> Control:
	var box := _Boxed.new(FFUI.VERDIGRIS, 2.0, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	v.add_child(_field_header("POTION"))
	var doses := int(pot.get("doses", 0))
	var ptype := str(pot.get("type", "")).capitalize()
	if doses > 0:
		var name_l := _handwritten(ptype if ptype != "" else "—", 20, FFUI.INK_PEN, "potion_%s" % ptype)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var nh := CenterContainer.new()
		nh.add_child(name_l)
		v.add_child(nh)
		var pips := FFUI.label("%s   (%d left)" % ["●".repeat(doses), doses], 13, FFUI.INK, false)
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pips)
		var use := FFUI.chip("tap to drink")
		use.pressed.connect(_on_drink)
		v.add_child(use)
	else:
		var spent := _handwritten("spent", 20, FFUI.FEN, "potion_spent")
		spent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sh := CenterContainer.new()
		sh.add_child(spent)
		v.add_child(sh)
		var note := FFUI.label("the flask is empty", 11, FFUI.FEN, false)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(note)
	box.add_child(v)
	return box


# --- Codewords & Notes ------------------------------------------------------


func _codewords_notes(s: FFAdventureSheet) -> Control:
	var cw_inner := VBoxContainer.new()
	cw_inner.add_theme_constant_override(&"separation", 4)
	cw_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cws := s.codewords.keys()
	if not cws.is_empty():
		var line := ""
		for w in cws:
			line += "◇ %s    " % str(w)
		var cwl := FFUI.label(line, 15, FFUI.VERDIGRIS, false)
		cwl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cw_inner.add_child(cwl)
	var note_rows: Array = []
	for n in s.notes:
		note_rows.append({"icon": "", "text": "“%s”" % str(n), "color": FFUI.INK_PEN, "hand": true})
	# an in-progress hand-written note (pencil ✎ → LineEdit → IFState.notes)
	if _editing == "note_new":
		var le := _line_edit("", "pencil a note onto the ledger…", func(txt: String) -> void:
			s.add_note(txt)
			_editing = ""
			Adventure.notify_sheet_changed()
			_render())
		cw_inner.add_child(le)
		le.call_deferred(&"grab_focus")
	if cws.is_empty() and note_rows.is_empty() and _editing != "note_new":
		cw_inner.add_child(FFUI.label("Nothing yet recorded in the ledger.", 14, FFUI.FEN, false))
	elif not note_rows.is_empty():
		cw_inner.add_child(_ruled_list(note_rows, 3, ""))
	return cw_inner


# --- Monster Encounter grid -------------------------------------------------


## The dominant feature (spec §6): a dense scrollable grid of ~18 pre-printed boxes.
## Rows in the sheet's encounter ledger fill in graphite; blank boxes stay blank + ruled;
## tapping the pencil hand-enters a foe into the first blank box.
func _encounter_grid(s: FFAdventureSheet) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override(&"separation", 6)
	var enote := FFUI.label("Each foe's SKILL and STAMINA is inked here in combat; STAMINA is scratched down as it is wounded.", 12, FFUI.FEN, false)
	enote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wrap.add_child(enote)

	var recs: Array = s.encounters
	var total_boxes := 18
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# index of the blank box that becomes the inline "add a foe" form (first blank)
	var blank_edit_at := recs.size() if _editing == "enc_new" else -1
	for i in maxi(total_boxes, recs.size()):
		if i < recs.size():
			grid.add_child(_encounter_box_filled(recs[i], i))
		elif i == blank_edit_at:
			grid.add_child(_encounter_box_edit())
		else:
			grid.add_child(_encounter_box_blank())
	scroll.add_child(grid)
	wrap.add_child(scroll)
	return wrap


## A FILLED encounter box: foe name + SKILL + STAMINA in graphite handwriting; STAMINA
## rendered as a _ScratchNumber so a wounded foe reads "5̶ 2" (max struck, current inked).
func _encounter_box_filled(rec: Dictionary, idx: int) -> Control:
	var dead := int(rec.get("stamina", 0)) <= 0
	var box := _Boxed.new(Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.7), 1.0, false)
	box.strike = dead
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 3)
	v.add_child(FFUI.label("MONSTER", 11, FFUI.FEN, false))
	var line := _WriteLine.new()
	line.custom_minimum_size = Vector2(0, 24)
	var nm := _handwritten(str(rec.get("name", "Foe")), 19, FFUI.GRAPHITE, "enc_%d_%s" % [idx, rec.get("name", "")], true)
	nm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	nm.offset_left = 4
	nm.offset_top = -24
	line.add_child(nm)
	v.add_child(line)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override(&"separation", 8)
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cells.add_child(_enc_cell("SKILL", str(int(rec.get("skill", 0))), "enc_%d_sk" % idx, []))
	# STAMINA: the max is struck, the current inked beside it (unless untouched)
	var st_max := int(rec.get("stamina_max", rec.get("stamina", 0)))
	var st_cur := int(rec.get("stamina", 0))
	var priors: Array = [st_max] if st_cur < st_max else []
	cells.add_child(_enc_cell("STAMINA", str(st_cur), "enc_%d_st_%d" % [idx, st_cur], priors))
	v.add_child(cells)
	box.add_child(v)
	return box


## A small captioned encounter cell, graphite handwriting (scratch when priors given).
func _enc_cell(caption: String, value: String, seed_key: String, priors: Array) -> Control:
	var cell := _Boxed.new(Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.6), 1.0, false)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	var cap := FFUI.label(caption, 10, FFUI.FEN, false)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, 28)
	if priors.is_empty():
		holder.add_child(_handwritten(value, 22, FFUI.GRAPHITE, seed_key))
	else:
		holder.add_child(_ScratchNumber.new().setup(priors, value, 22, FFUI.GRAPHITE, seed_key))
	v.add_child(holder)
	cell.add_child(v)
	return cell


## One BLANK, ruled encounter box — the form waiting to be used.
func _encounter_box_blank() -> Control:
	var box := _Boxed.new(Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.7), 1.0, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 5)
	v.add_child(FFUI.label("MONSTER", 11, FFUI.FEN, false))
	var nameline := _WriteLine.new()
	nameline.custom_minimum_size = Vector2(0, 20)
	v.add_child(nameline)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override(&"separation", 8)
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cells.add_child(_blank_cell("SKILL"))
	cells.add_child(_blank_cell("STAMINA"))
	v.add_child(cells)
	box.add_child(v)
	return box


## The inline "hand-enter a foe" form shown in the first blank box on pencil-tap (§7).
func _encounter_box_edit() -> Control:
	var box := _Boxed.new(FFUI.VERDIGRIS, 2.0, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	v.add_child(FFUI.label("MONSTER", 11, FFUI.FEN, false))
	var name_edit := _line_edit("", "foe…", Callable())
	v.add_child(name_edit)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override(&"separation", 8)
	var sk := _line_edit("", "SK", Callable())
	sk.custom_minimum_size = Vector2(56, 0)
	var st := _line_edit("", "ST", Callable())
	st.custom_minimum_size = Vector2(56, 0)
	cells.add_child(sk)
	cells.add_child(st)
	v.add_child(cells)
	var ink := FFUI.chip("ink it")
	ink.pressed.connect(func() -> void:
		var nm := name_edit.text.strip_edges()
		if nm != "":
			Adventure.sheet.record_encounter(nm, sk.text.to_int(), st.text.to_int())
			Adventure.notify_sheet_changed()
		_editing = ""
		_render())
	v.add_child(ink)
	box.add_child(v)
	name_edit.call_deferred(&"grab_focus")
	return box


## A small captioned box left blank for hand-filling (encounter SKILL / STAMINA).
func _blank_cell(caption: String) -> Control:
	var cell := _Boxed.new(Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.6), 1.0, false)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	var cap := FFUI.label(caption, 10, FFUI.FEN, false)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 22)
	v.add_child(spacer)
	cell.add_child(v)
	return cell


# --- Small helpers ----------------------------------------------------------


## A titled ledger box: a display-face header (optionally with a trailing pencil chip)
## over a double-ruled box that holds `content`.
func _titled_box(title_text: String, accent: Color, content: Control, pencil: Control = null) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override(&"separation", 2)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override(&"separation", 8)
	var hdr := _field_header(title_text, accent, HORIZONTAL_ALIGNMENT_LEFT)
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(hdr)
	if pencil != null:
		hrow.add_child(pencil)
	wrap.add_child(hrow)
	var box := _Boxed.new(accent, 2.0, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(content)
	wrap.add_child(box)
	return wrap


func _field_header(text: String, color: Color = FFUI.INK, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := FFUI.label(text, 15, color, false)
	l.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	l.horizontal_alignment = align
	return l


## A hand-written value: the handwriting face in the player's ink with seeded jitter.
## (Renamed from the old `_inked`, which wrongly used the ornamental Uncial TYPESET
## face — the spec's core fix.)
func _handwritten(text: String, size: int, color: Color, seed_key: String = "", loose: bool = false) -> Label:
	return FFUI.handwritten(text, size, color, seed_key, loose)


## A small graphite pencil ✎ chip — the universal "you can write here" cue (§7). On tap
## it swaps the field into edit state on the next render.
func _pencil(field_key: String) -> Button:
	var b := FFUI.chip("✎")
	b.custom_minimum_size = Vector2(40, 34)
	b.tooltip_text = "Write here"
	b.pressed.connect(func() -> void:
		_editing = "" if _editing == field_key else field_key
		_render())
	return b


## A LineEdit styled to sit on the paper (handwriting face, ink), committing via
## `on_commit` on Enter or focus-loss. Free text only — never a numeric score.
func _line_edit(text: String, placeholder: String, on_commit: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.placeholder_text = placeholder
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_override(&"font", FFUI.font_hand())
	le.add_theme_font_size_override(&"font_size", 22)
	le.add_theme_color_override(&"font_color", FFUI.INK_PEN)
	le.add_theme_color_override(&"font_placeholder_color", Color(FFUI.FEN.r, FFUI.FEN.g, FFUI.FEN.b, 0.7))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.5)
	sb.set_border_width_all(0)
	sb.border_width_bottom = 2
	sb.border_color = Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	le.add_theme_stylebox_override(&"normal", sb)
	le.add_theme_stylebox_override(&"focus", sb)
	if on_commit.is_valid():
		le.text_submitted.connect(func(t: String) -> void: on_commit.call(t))
	return le


func _small_icon(icon_name: String) -> TextureRect:
	var tex := FFUI.icon(icon_name)
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(24, 24)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.texture = tex
	return tr


## A ruled ledger list: rows sitting on printed rule-lines with a red margin rule down
## the left, and `min_lines` guaranteeing blank ruled lines below the content. A row's
## text renders in the handwriting face when `hand` is true (the player's entries).
func _ruled_list(rows: Array, min_lines: int, empty_text: String) -> Control:
	var ruled := _Ruled.new()
	ruled.line_h = 30.0
	ruled.min_lines = maxi(min_lines, rows.size() + 1)
	ruled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ruled.custom_minimum_size = Vector2(0, ruled.line_h * float(ruled.min_lines) + 12.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	if rows.is_empty() and empty_text != "":
		var e := FFUI.label(empty_text, 15, FFUI.FEN, false)
		e.custom_minimum_size = Vector2(0, 30)
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(e)
	for r in rows:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 30)
		row.add_theme_constant_override(&"separation", 8)
		var icon_name := str(r.get("icon", ""))
		if icon_name != "":
			var tr := _small_icon(icon_name)
			if tr != null:
				row.add_child(tr)
		var col: Color = r.get("color", FFUI.INK)
		var txt := str(r.get("text", ""))
		if bool(r.get("hand", false)):
			var hl := _handwritten(txt, 20, col, "ledger_%s" % txt)
			hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(hl)
		else:
			var lbl := FFUI.label(txt, 16, col, false)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(lbl)
		v.add_child(row)
	ruled.add_child(v)
	return ruled


func _item_icon(item: String) -> String:
	match item:
		"sword": return "sword"
		"leather armour", "leather_armour": return "leather_armour"
		"lantern": return "lantern"
		"saint_vexcels_blade": return "blessed_blade"
		"quittance_seal": return "scroll"
		"silver_key": return "silver_key"
		_: return "ledger"


func _pretty(item: String) -> String:
	return item.replace("_", " ").capitalize()


func _on_drink() -> void:
	if Adventure.sheet.drink_potion():
		Adventure.notify_sheet_changed()
		_render()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _editing != "":
			_editing = ""
			_render()
		else:
			_close()


# ============================================================================
# Hand-drawn chrome — inner Controls that ink the printed form.
# ============================================================================


## The parchment page: opaque aged-paper fill, faint paper-grain fibre noise, a
## double-ruled printed frame, corner ornaments, and foxing. Lays its child to full rect.
class _Ground extends MarginContainer:
	func _init() -> void:
		var m := 26
		add_theme_constant_override(&"margin_left", m)
		add_theme_constant_override(&"margin_right", m)
		add_theme_constant_override(&"margin_top", 22)
		add_theme_constant_override(&"margin_bottom", 22)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# aged paper ground (a hair darker than the reading page = a printed form)
		draw_rect(r, FFUI.PARCHMENT_2, true)
		# a faint top-to-bottom warm wash for depth
		draw_rect(r, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.05), true)
		# faint, DETERMINISTIC paper-grain: sparse short fibre flecks so the page isn't a
		# flat fill (spec §2.1). Seeded by size so it's stable across re-renders.
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x5EED ^ int(size.x) * 131 ^ int(size.y)
		var fibre := Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.05)
		var n := int(clampf(size.x * size.y / 900.0, 40, 520))
		for _i in n:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			draw_line(p, p + Vector2(rng.randf_range(1.5, 4.0), rng.randf_range(-0.8, 0.8)), fibre, 1.0)
		# foxing blotches near the corners (a recovered book)
		var fox := Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.06)
		draw_circle(Vector2(size.x * 0.06, size.y * 0.04), 22.0, fox)
		draw_circle(Vector2(size.x * 0.95, size.y * 0.5), 30.0, fox)
		draw_circle(Vector2(size.x * 0.12, size.y * 0.97), 26.0, fox)
		# double-ruled printed frame
		var o := r.grow(-10.0)
		draw_rect(o, FFUI.INK, false, 2.5)
		var inr := o.grow(-5.0)
		draw_rect(inr, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.7), false, 1.0)
		# corner ornaments
		_corner(o.position, 1, 1)
		_corner(Vector2(o.end.x, o.position.y), -1, 1)
		_corner(Vector2(o.position.x, o.end.y), 1, -1)
		_corner(o.end, -1, -1)

	func _corner(p: Vector2, sx: int, sy: int) -> void:
		var c := FFUI.VERDIGRIS
		var L := 16.0
		draw_line(p + Vector2(sx * 4, sy * 4), p + Vector2(sx * (4 + L), sy * (4 + L)), c, 1.5)
		draw_line(p + Vector2(sx * (4 + L), sy * 4), p + Vector2(sx * (4 + L), sy * (4 + L)), Color(c.r, c.g, c.b, 0.6), 1.0)
		draw_line(p + Vector2(sx * 4, sy * (4 + L)), p + Vector2(sx * (4 + L), sy * (4 + L)), Color(c.r, c.g, c.b, 0.6), 1.0)


## A double-ruled ledger box. `strike` scrawls a diagonal cancel across the box (used to
## stamp a dead STAMINA / a defeated foe — an in-fiction tell, spec §8).
class _Boxed extends MarginContainer:
	var accent: Color = FFUI.UMBER
	var thick: float = 2.0
	var ornament: bool = false
	var strike: bool = false

	func _init(a: Color = FFUI.UMBER, t: float = 2.0, orn: bool = false) -> void:
		accent = a
		thick = t
		ornament = orn
		add_theme_constant_override(&"margin_left", 12)
		add_theme_constant_override(&"margin_right", 12)
		add_theme_constant_override(&"margin_top", 10)
		add_theme_constant_override(&"margin_bottom", 10)

	func _draw() -> void:
		var r := Rect2(Vector2(thick, thick), size - Vector2(thick * 2.0, thick * 2.0))
		draw_rect(r, Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.35), true)
		draw_rect(r, accent, false, thick)
		if thick >= 2.0:
			var inr := r.grow(-3.5)
			draw_rect(inr, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.45), false, 1.0)
		if ornament:
			var t := 5.0
			for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
				draw_rect(Rect2(corner - Vector2(t, t), Vector2(t * 2, t * 2)), Color(accent.r, accent.g, accent.b, 0.25), true)
		if strike:
			var red := Color(FFUI.ARREARS.r, FFUI.ARREARS.g, FFUI.ARREARS.b, 0.75)
			draw_line(r.position + Vector2(4, 4), r.end - Vector2(4, 4), red, 2.5)
			draw_line(Vector2(r.end.x - 4, r.position.y + 4), Vector2(r.position.x + 4, r.end.y - 4), Color(red.r, red.g, red.b, 0.45), 1.5)


## A ruled writing surface: horizontal rule-lines with a red margin rule down the left,
## guaranteeing at least `min_lines` printed lines so a half-filled list still reads as
## a form. Lays its single child inside a left inset clearing the margin rule.
class _Ruled extends MarginContainer:
	var line_h: float = 30.0
	var min_lines: int = 4

	func _init() -> void:
		add_theme_constant_override(&"margin_left", 46)
		add_theme_constant_override(&"margin_right", 12)
		add_theme_constant_override(&"margin_top", 4)
		add_theme_constant_override(&"margin_bottom", 6)

	func _draw() -> void:
		var rule := Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.3)
		var y := line_h + 3.0
		while y < size.y - 2.0:
			draw_line(Vector2(10, y), Vector2(size.x - 10, y), rule, 1.0)
			y += line_h
		draw_line(Vector2(36, 4), Vector2(36, size.y - 4), Color(FFUI.ARREARS.r, FFUI.ARREARS.g, FFUI.ARREARS.b, 0.3), 1.0)


## A single blank underline for hand-writing on (monster name, hero name).
class _WriteLine extends Control:
	func _draw() -> void:
		var y := size.y - 3.0
		draw_line(Vector2(2, y), Vector2(size.x - 2, y), Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.4), 1.0)


## An ornamented double rule under the title banner.
class _TitleRule extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 12)

	func _draw() -> void:
		var y := 4.0
		draw_line(Vector2(0, y), Vector2(size.x, y), FFUI.INK, 2.0)
		draw_line(Vector2(0, y + 4), Vector2(size.x, y + 4), Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.6), 1.0)
		var cx := size.x * 0.5
		var d := 5.0
		var pts := PackedVector2Array([Vector2(cx, y - d), Vector2(cx + d, y + 2), Vector2(cx, y + d + 4), Vector2(cx - d, y + 2)])
		draw_colored_polygon(pts, FFUI.VERDIGRIS)


## The crossed-out-and-rewritten score (spec §3 — the single most recognisable tell of a
## real in-play FF sheet). Draws the prior values as faint struck-through ghosts, then
## the current value large in full ink, all in the handwriting face. Jitter is seeded
## from the field key so the same state always renders identically (screenshot-stable).
class _ScratchNumber extends Control:
	var priors: Array = []
	var current: String = ""
	var big: int = 30
	var ink: Color = FFUI.INK_PEN
	var seed_key: String = ""

	func setup(p_priors: Array, p_current: String, p_size: int, p_ink: Color, key: String) -> _ScratchNumber:
		priors = p_priors
		current = p_current
		big = p_size
		ink = p_ink
		seed_key = key
		var font := FFUI.font_hand()
		var small := int(big * 0.62)
		var w := 4.0
		for pv in priors:
			w += font.get_string_size(str(pv), HORIZONTAL_ALIGNMENT_LEFT, -1, small).x + 6.0
		w += font.get_string_size(current, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x + 4.0
		custom_minimum_size = Vector2(w, big + 12)
		return self

	func _draw() -> void:
		var font := FFUI.font_hand()
		var small := int(big * 0.62)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(seed_key)
		var ghost := Color(ink.r, ink.g, ink.b, 0.5)
		var baseline := float(big)
		var x := 2.0
		for pv in priors:
			var sstr := str(pv)
			var sw: float = font.get_string_size(sstr, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
			var yoff := rng.randf_range(-1.5, 1.5)
			var pos := Vector2(x, baseline - float(big - small) + yoff)
			font.draw_string(get_canvas_item(), pos, sstr, HORIZONTAL_ALIGNMENT_LEFT, -1, small, ghost)
			# a slightly angled biro strike through the cancelled value
			var sy := pos.y - float(small) * 0.28
			draw_line(Vector2(x - 1, sy + rng.randf_range(-1, 1)),
				Vector2(x + sw + 1, sy - float(small) * 0.08 + rng.randf_range(-1, 1)), ink, 1.6)
			x += sw + 6.0
		var cy := baseline + rng.randf_range(-1.0, 1.0)
		font.draw_string(get_canvas_item(), Vector2(x, cy), current, HORIZONTAL_ALIGNMENT_LEFT, -1, big, ink)
