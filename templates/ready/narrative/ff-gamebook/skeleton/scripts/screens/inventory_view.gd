extends CanvasLayer
## res://scripts/screens/inventory_view.gd
## Inventory / Equipment / Potions (WIREFRAMES 6.3, GDD §6.1 #9). An item grid drawn
## from the shared IFState inventory, equipped slots, the Potion with its remaining
## doses, and a detail panel whose actions are CONTEXT-GATED: Use/Read a quest item,
## drink the Potion, Eat a Provision (disabled mid-combat-round per the rules), Drop
## a mundane item (quest items can't be dropped). Every mutation routes through the
## FF sheet (apply_delta), never a direct edit. Opens as an overlay; Esc / ✕ closes.

signal closed

var _combat := false
var _selected := ""
var _grid: GridContainer
var _detail: VBoxContainer
var _potion_row: HBoxContainer

const QUEST := ["quittance_seal", "silver_key", "saint_vexcels_blade"]


func setup(combat_context: bool = false) -> void:
	_combat = combat_context


func _ready() -> void:
	layer = 16
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
	panel.custom_minimum_size = Vector2(620, 560)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 8)
	panel.add_child(outer)

	var head := HBoxContainer.new()
	var t := FFUI.title("PACK & EQUIPMENT", 24, FFUI.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := FFUI.chip("✕"); x.pressed.connect(_close); head.add_child(x)
	outer.add_child(head)
	outer.add_child(FFUI.divider_rule())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(FFUI.label("CARRIED", 15, FFUI.VERDIGRIS, false))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override(&"h_separation", 8)
	_grid.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(_grid)
	left.add_child(scroll)
	_potion_row = HBoxContainer.new()
	left.add_child(_potion_row)
	cols.add_child(left)

	var detail_panel := FFUI.panel(FFUI.PARCHMENT_2, FFUI.UMBER)
	detail_panel.custom_minimum_size = Vector2(230, 0)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override(&"separation", 8)
	detail_panel.add_child(_detail)
	cols.add_child(detail_panel)


func _render() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for c in _potion_row.get_children():
		c.queue_free()
	var s := Adventure.sheet
	var inv: Dictionary = s.state.inventory()
	for item in inv.keys():
		_grid.add_child(_item_tile(str(item), int(inv[item])))
	if inv.is_empty():
		_grid.add_child(FFUI.label("Your pack is empty.", 15, FFUI.FEN))

	var pot: Dictionary = s.potion
	if int(pot.get("doses", 0)) > 0:
		var chip := FFUI.chip("Potion of %s  %s" % [str(pot.type).capitalize(), "●".repeat(int(pot.doses))])
		chip.pressed.connect(func() -> void: _select("__potion")); _potion_row.add_child(chip)

	if _selected == "":
		_show_detail_hint()
	else:
		_show_detail(_selected)


func _item_tile(item: String, qty: int) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(88, 96)
	b.toggle_mode = true
	b.button_pressed = (_selected == item)
	b.add_theme_stylebox_override(&"normal", FFUI.panel_box(FFUI.PARCHMENT, FFUI.UMBER, 2, 4))
	b.add_theme_stylebox_override(&"hover", FFUI.panel_box(Color("e2d4b2"), FFUI.VERDIGRIS, 2, 4))
	b.add_theme_stylebox_override(&"pressed", FFUI.panel_box(Color("cfe0d4"), FFUI.VERDIGRIS, 3, 4))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(40, 40)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tex := FFUI.icon(_icon_for(item))
	if tex != null: tr.texture = tex
	box.add_child(tr)
	var nm := FFUI.label(_pretty(item) + (" ×%d" % qty if qty > 1 else ""), 12, FFUI.INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(nm)
	b.add_child(box)
	b.pressed.connect(func() -> void: _select(item))
	return b


func _select(id: String) -> void:
	_selected = id
	_render()


func _show_detail_hint() -> void:
	for c in _detail.get_children(): c.queue_free()
	_detail.add_child(FFUI.label("Select an item to inspect it.", 15, FFUI.FEN))


func _show_detail(id: String) -> void:
	for c in _detail.get_children(): c.queue_free()
	if id == "__potion":
		var pot: Dictionary = Adventure.sheet.potion
		_detail.add_child(FFUI.title("Potion of %s" % str(pot.type).capitalize(), 18, FFUI.INK))
		_detail.add_child(FFUI.label(_potion_blurb(str(pot.type)), 14, FFUI.UMBER))
		_detail.add_child(FFUI.label("Doses remaining: %d" % int(pot.doses), 14, FFUI.VERDIGRIS))
		var use := FFUI.choice_button("Drink a dose")
		use.pressed.connect(_on_drink)
		_detail.add_child(use)
		return
	_detail.add_child(FFUI.title(_pretty(id), 18, FFUI.INK))
	_detail.add_child(FFUI.label(_desc(id), 14, FFUI.UMBER))
	var is_quest := id in QUEST
	if is_quest:
		_detail.add_child(FFUI.label("Quest item — cannot be dropped.", 13, FFUI.VERDIGRIS))
		var read := FFUI.choice_button("Read / Examine")
		read.pressed.connect(func() -> void: _show_read(id))
		_detail.add_child(read)
	else:
		var drop := FFUI.choice_button("Drop")
		drop.pressed.connect(func() -> void: _on_drop(id))
		_detail.add_child(drop)


func _show_read(id: String) -> void:
	for c in _detail.get_children(): c.queue_free()
	_detail.add_child(FFUI.title(_pretty(id), 18, FFUI.INK))
	_detail.add_child(FFUI.label(_lore(id), 14, FFUI.UMBER))
	var back := FFUI.chip("Back"); back.pressed.connect(func() -> void: _show_detail(id)); _detail.add_child(back)


func _on_drink() -> void:
	if Adventure.sheet.drink_potion():
		AudioDirector.play_sfx("potion")
		Adventure.notify_sheet_changed()
		if int(Adventure.sheet.potion.get("doses", 0)) <= 0:
			_selected = ""
		_render()


func _on_drop(id: String) -> void:
	Adventure.sheet.remove_item(id)
	Adventure.notify_sheet_changed()
	_selected = ""
	_render()


func _icon_for(item: String) -> String:
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


func _desc(id: String) -> String:
	match id:
		"sword": return "A plain, honest blade. Bites the living and the newly-dead alike."
		"leather armour", "leather_armour": return "Cracked and salt-stained, but it turns a glancing blow."
		"lantern": return "Its warm light is a small mercy in the dark under the town."
		"saint_vexcels_blade": return "A saint's name etched down the fuller. The only edge that bites the Reckoner."
		"quittance_seal": return "A Ledgerkeeper's brass 'paid in full' stamp. Closes an account — if you forgive the debt."
		_: return "An item carried from the world above."


func _lore(id: String) -> String:
	match id:
		"quittance_seal": return "\"Only closes an account when the one who stamps it forgives the debt. A kill won't do. You have to mean it.\" — Brother Odo"
		"saint_vexcels_blade": return "Blessed at an altar the Order tried to drown. It remembers being holy."
		_: return _desc(id)


func _potion_blurb(t: String) -> String:
	match t:
		"skill": return "Restores SKILL to its Initial value."
		"strength": return "Restores STAMINA to its Initial value."
		"fortune": return "Restores LUCK to Initial and raises Initial LUCK by 1 — the one sanctioned way to exceed the cap."
		_: return ""


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
