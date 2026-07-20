extends CanvasLayer
## res://scripts/screens/adventure_sheet.gd
## THE Adventure Sheet (WIREFRAMES 5.5, GDD §6.1 #8) — rendered to look like a
## genuine printed Fighting-Fantasy / old-school D&D pen-and-paper character sheet:
## a ruled, boxed form on aged parchment with a double-ruled frame, corner
## ornaments, a display-face title banner, the classic TWO-BOX (Initial / Now)
## stat blocks, boxed Provisions / Gold / Potion, a ruled Equipment ledger, a ruled
## Codewords & Notes panel, and the iconic MONSTER ENCOUNTER BOXES grid.
##
## The chrome is hand-drawn (custom `_draw` on inner Controls) so it reads as *ink
## printed on a form* rather than flat UI panels; the printed labels sit in the
## engraved display face while the filled-in values are set in the inked Uncial face
## (typography SKILL "illuminated / inked over the printed labels"). Palette + fonts
## are the shared STYLE_GUIDE "veritas-gamebook" set via FFUI, so the sheet reads as
## the SAME book as Reading / Combat.
##
## It is a thin VIEW over the ONE shared FFAdventureSheet / IFState. Read-only in
## faithful mode; the Potion is tap-to-use (routes through drink_potion -> apply_delta
## so the never-exceed-Initial invariant holds and is surfaced as text). Esc / ✕ close.

signal closed

var _body: VBoxContainer


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
	outer.add_theme_constant_override(&"separation", 6)
	ground.add_child(outer)

	# --- Title banner (display face) + close -------------------------------
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	var t := FFUI.title("ADVENTURE SHEET", 30, FFUI.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := FFUI.chip("✕")
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.pressed.connect(_close)
	head.add_child(x)
	outer.add_child(head)

	var sub := FFUI.label("The Grey Tithe  ·  being a true & current account", 14, FFUI.UMBER, false)
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
	for c in _body.get_children():
		c.queue_free()
	var s := Adventure.sheet
	if s == null:
		return

	# --- STATS: the classic two-box (Initial / Now) blocks -----------------
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override(&"separation", 10)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(_stat_field("SKILL", s.cur("skill"), s.init_of("skill"), FFUI.VERDIGRIS, false))
	stats.add_child(_stat_field("STAMINA", s.cur("stamina"), s.init_of("stamina"), FFUI.ARREARS, true))
	stats.add_child(_stat_field("LUCK", s.cur("luck"), s.init_of("luck"), FFUI.FLAME, false))
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

	# --- EQUIPMENT (ruled ledger) -----------------------------------------
	var eq_rows: Array = []
	for item in s.equipment:
		eq_rows.append({"icon": _item_icon(item), "text": _pretty(item)})
	_body.add_child(_titled_box("EQUIPMENT & JEWELS", FFUI.UMBER, _ruled_list(eq_rows, 5, "Your pack is empty.")))

	# --- CODEWORDS & NOTES -------------------------------------------------
	var cw_inner := VBoxContainer.new()
	cw_inner.add_theme_constant_override(&"separation", 4)
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
		note_rows.append({"icon": "", "text": "“%s”" % str(n), "color": FFUI.UMBER})
	if cws.is_empty() and note_rows.is_empty():
		cw_inner.add_child(FFUI.label("Nothing yet recorded in the ledger.", 14, FFUI.FEN, false))
	else:
		cw_inner.add_child(_ruled_list(note_rows, 3, ""))
	_body.add_child(_titled_box("CODEWORDS & NOTES", FFUI.VERDIGRIS, cw_inner))

	# --- MONSTER ENCOUNTER BOXES (the iconic FF grid) ---------------------
	var encv := VBoxContainer.new()
	encv.add_theme_constant_override(&"separation", 8)
	var enote := FFUI.label("Note each foe's SKILL and STAMINA here as you fight.", 12, FFUI.FEN, false)
	encv.add_child(enote)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	for i in 6:
		grid.add_child(_encounter_box())
	encv.add_child(grid)
	_body.add_child(_titled_box("MONSTER ENCOUNTER BOXES", FFUI.INK, encv))

	# --- THE GREY LEDGER (world's signature bookkeeping) ------------------
	var debt := int(Adventure.runner.state.get_var("tithe_debt")) if Adventure.runner != null else 0
	var led := FFUI.label("Tithe-debt owed to the Grey Ledger:   %d" % debt, 16, FFUI.VERDIGRIS_2, false)
	_body.add_child(_titled_box("THE GREY LEDGER", FFUI.VERDIGRIS, led))


# --- Field builders ---------------------------------------------------------


## A classic two-box stat block: printed name header, an "Initial" cell and a "Now"
## cell side by side. STAMINA also carries a thin wound-track bar beneath.
func _stat_field(name: String, cur: int, init: int, accent: Color, with_bar: bool) -> Control:
	var box := _Boxed.new(accent, 2.0, true)
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
	cells.add_child(_value_cell("Initial", str(init), FFUI.FEN, false))
	cells.add_child(_value_cell("Now", str(cur), accent, true))
	v.add_child(cells)
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


## A small bordered cell: a printed caption above an inked (Uncial) filled value.
func _value_cell(caption: String, value: String, color: Color, emphatic: bool) -> Control:
	var cell := _Boxed.new(Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.65), 1.0, false)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	var cap := FFUI.label(caption, 11, FFUI.FEN, false)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var num := _inked(value, 30 if emphatic else 24, color)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	cell.add_child(v)
	return cell


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
	row.add_child(_inked("×%d" % count, 26, FFUI.INK))
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
	row.add_child(_inked(str(gold), 26, FFUI.INK))
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
		var name_l := _inked(ptype if ptype != "" else "—", 20, FFUI.VERDIGRIS)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name_l)
		var pips := FFUI.label("%s   (%d left)" % ["●".repeat(doses), doses], 13, FFUI.INK, false)
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pips)
		var use := FFUI.chip("tap to drink")
		use.pressed.connect(_on_drink)
		v.add_child(use)
	else:
		var spent := _inked("spent", 20, FFUI.FEN)
		spent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(spent)
		var note := FFUI.label("the flask is empty", 11, FFUI.FEN, false)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(note)
	box.add_child(v)
	return box


## One monster-encounter box: a name line plus a SKILL cell and a STAMINA cell, all
## left blank for the player to fill in during a fight (the paper sheet's ritual).
func _encounter_box() -> Control:
	var box := _Boxed.new(Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.7), 1.0, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 5)
	v.add_child(FFUI.label("MONSTER", 11, FFUI.FEN, false))
	# a blank ruled name line
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


## A titled ledger box: a display-face header sitting over a double-ruled box that
## holds `content`. Returns the whole header+box assembly to add to the page.
func _titled_box(title_text: String, accent: Color, content: Control) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override(&"separation", 2)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(_field_header(title_text, accent, HORIZONTAL_ALIGNMENT_LEFT))
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


func _inked(text: String, size: int, color: Color) -> Label:
	var l := FFUI.label(text, size, color, false)
	l.add_theme_font_override(&"font", FFUI.font_runic())
	return l


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


## A ruled ledger list: item rows sitting on printed rule-lines, with a red margin
## rule down the left, and `min_lines` guaranteeing blank ruled lines below the
## content (an authentic half-filled form). `empty_text` shows when there are none.
func _ruled_list(rows: Array, min_lines: int, empty_text: String) -> Control:
	var ruled := _Ruled.new()
	ruled.line_h = 30.0
	ruled.min_lines = maxi(min_lines, rows.size() + 1)
	ruled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# guarantee blank ruled lines below the content (a half-filled form)
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
		var lbl := FFUI.label(str(r.get("text", "")), 16, col, false)
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
		_close()


# ============================================================================
# Hand-drawn chrome — inner Controls that ink the printed form.
# ============================================================================


## The parchment page: opaque aged-paper fill, a double-ruled printed frame, corner
## ornaments, and faint foxing at the edges. Lays its single child to full rect.
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
		# faint foxing blotches near the corners (a recovered book)
		var fox := Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.06)
		draw_circle(Vector2(size.x * 0.06, size.y * 0.04), 22.0, fox)
		draw_circle(Vector2(size.x * 0.95, size.y * 0.5), 30.0, fox)
		draw_circle(Vector2(size.x * 0.12, size.y * 0.97), 26.0, fox)
		# double-ruled printed frame
		var o := r.grow(-10.0)
		draw_rect(o, FFUI.INK, false, 2.5)
		var inr := o.grow(-5.0)
		draw_rect(inr, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.7), false, 1.0)
		# corner ornaments — short filigree strokes at each corner of the frame
		_corner(o.position, 1, 1)
		_corner(Vector2(o.end.x, o.position.y), -1, 1)
		_corner(Vector2(o.position.x, o.end.y), 1, -1)
		_corner(o.end, -1, -1)

	func _corner(p: Vector2, sx: int, sy: int) -> void:
		var c := FFUI.VERDIGRIS
		var L := 16.0
		# an inward diagonal + two small ticks = a printed corner flourish
		draw_line(p + Vector2(sx * 4, sy * 4), p + Vector2(sx * (4 + L), sy * (4 + L)), c, 1.5)
		draw_line(p + Vector2(sx * (4 + L), sy * 4), p + Vector2(sx * (4 + L), sy * (4 + L)), Color(c.r, c.g, c.b, 0.6), 1.0)
		draw_line(p + Vector2(sx * 4, sy * (4 + L)), p + Vector2(sx * (4 + L), sy * (4 + L)), Color(c.r, c.g, c.b, 0.6), 1.0)


## A double-ruled ledger box that lays its single child inside its margins; the
## outer rule is the accent colour, the inner is a faint umber. `ornament` adds
## small corner ticks (used to give the stat blocks their engraved-form feel).
class _Boxed extends MarginContainer:
	var accent: Color = FFUI.UMBER
	var thick: float = 2.0
	var ornament: bool = false

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
		# a faint parchment fill so the box reads as a printed cell on the page
		draw_rect(r, Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.35), true)
		draw_rect(r, accent, false, thick)
		if thick >= 2.0:
			var inr := r.grow(-3.5)
			draw_rect(inr, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.45), false, 1.0)
		if ornament:
			var t := 5.0
			for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
				draw_rect(Rect2(corner - Vector2(t, t), Vector2(t * 2, t * 2)), Color(accent.r, accent.g, accent.b, 0.25), true)


## A ruled writing surface: horizontal rule-lines every `line_h` px with a red
## margin rule down the left, guaranteeing at least `min_lines` printed lines so a
## half-filled list still reads as a form. Lays its single child inside a left inset
## that clears the margin rule.
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
		# the ledger's red margin rule
		draw_line(Vector2(36, 4), Vector2(36, size.y - 4), Color(FFUI.ARREARS.r, FFUI.ARREARS.g, FFUI.ARREARS.b, 0.3), 1.0)


## A single blank underline for hand-writing a monster's name.
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
		# a small diamond centred on the rule (a printed ornament)
		var cx := size.x * 0.5
		var d := 5.0
		var pts := PackedVector2Array([Vector2(cx, y - d), Vector2(cx + d, y + 2), Vector2(cx, y + d + 4), Vector2(cx - d, y + 2)])
		draw_colored_polygon(pts, FFUI.VERDIGRIS)
