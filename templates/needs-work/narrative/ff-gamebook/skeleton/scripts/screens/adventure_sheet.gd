extends CanvasLayer
## res://scripts/screens/adventure_sheet.gd
## The Adventure Sheet (WIREFRAMES 5.5, GDD §6.1 #8) — the self-maintaining
## character record, rendered on parchment. Read-only in faithful mode (the player
## never hand-edits stats); the Potion is tap-to-use (routes through the sheet's
## drink_potion -> apply_delta, so the never-exceed-Initial invariant holds and is
## surfaced as text). Opens as an overlay over Reading/Combat and reads the whole
## FFAdventureSheet view of the ONE shared IFState. Esc / ✕ closes.

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
	dim.color = Color(0.02, 0.03, 0.03, 0.55)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := FFUI.framed_panel(FFUI.UMBER)
	panel.custom_minimum_size = Vector2(540, 620)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 8)
	panel.add_child(outer)

	var head := HBoxContainer.new()
	var t := FFUI.title("ADVENTURE SHEET", 24, FFUI.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := FFUI.chip("✕")
	x.pressed.connect(_close)
	head.add_child(x)
	outer.add_child(head)
	outer.add_child(FFUI.divider_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


func _render() -> void:
	for c in _body.get_children():
		c.queue_free()
	var s := Adventure.sheet
	if s == null:
		return

	_section("STATS")
	_stat_line("SKILL", s.cur("skill"), s.init_of("skill"), FFUI.VERDIGRIS)
	_body.add_child(FFUI.stat_bar("STAMINA", s.cur("stamina"), s.init_of("stamina"), FFUI.ARREARS))
	_stat_line("LUCK", s.cur("luck"), s.init_of("luck"), FFUI.FLAME)
	_body.add_child(FFUI.label("Current may fall but never exceed Initial.", 13, FFUI.FEN))

	_section("CONSUMABLES")
	_body.add_child(FFUI.stat_bar("Provisions", s.provisions, maxi(s.provisions, 10), FFUI.VERDIGRIS))
	_kv_icon("gold", "Gold", "%d gp" % s.gold)
	var pot: Dictionary = s.potion
	if int(pot.get("doses", 0)) > 0:
		var use := FFUI.chip("Potion of %s   %s   ·  tap to use" % [str(pot.get("type", "")).capitalize(), "●".repeat(int(pot.doses))])
		use.pressed.connect(_on_drink)
		_body.add_child(use)
	else:
		_kv_icon("potion_fortune", "Potion", "spent")

	_section("EQUIPMENT")
	var eq := s.equipment
	if eq.is_empty():
		_body.add_child(FFUI.label("Your pack is empty.", 15, FFUI.FEN))
	else:
		for item in eq:
			_kv_icon(_item_icon(item), _pretty(item), "")

	_section("CODEWORDS / NOTES")
	var cws := s.codewords.keys()
	if cws.is_empty():
		_body.add_child(FFUI.label("(none recorded)", 14, FFUI.FEN))
	else:
		var line := ""
		for w in cws:
			line += "◇ %s    " % str(w)
		_body.add_child(FFUI.label(line, 15, FFUI.VERDIGRIS))
	for n in s.notes:
		_body.add_child(FFUI.label("“%s”" % str(n), 14, FFUI.UMBER))

	# a running debt gauge — the world's signature bookkeeping
	var debt := int(Adventure.runner.state.get_var("tithe_debt")) if Adventure.runner != null else 0
	_section("THE LEDGER")
	_body.add_child(FFUI.label("Tithe-debt owed to the Grey Ledger:  %d" % debt, 15, FFUI.VERDIGRIS_2))


func _section(name: String) -> void:
	var l := FFUI.label("── %s ──" % name, 15, FFUI.VERDIGRIS, false)
	_body.add_child(l)


func _stat_line(name: String, cur: int, init: int, accent: Color) -> void:
	var row := HBoxContainer.new()
	var n := FFUI.label(name, 17, FFUI.INK, false)
	n.custom_minimum_size = Vector2(120, 0)
	row.add_child(n)
	var v := FFUI.label("%d / %d" % [cur, init], 17, accent)
	v.add_theme_font_override(&"font", FFUI.font_display())
	row.add_child(v)
	var init_l := FFUI.label("   (init %d)" % init, 13, FFUI.FEN)
	row.add_child(init_l)
	_body.add_child(row)


func _kv_icon(icon_name: String, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(28, 28)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := FFUI.icon(icon_name)
	if tex != null: tr.texture = tex
	row.add_child(tr)
	var k := FFUI.label(key, 16, FFUI.INK)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	if value != "":
		row.add_child(FFUI.label(value, 16, FFUI.INK))
	_body.add_child(row)


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
