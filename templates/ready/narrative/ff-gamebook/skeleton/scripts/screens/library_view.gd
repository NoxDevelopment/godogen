extends Control
## res://scripts/screens/library_view.gd
## The LIBRARY / Bookshelf (GDD §6.1 #2; ADVENTURE_FORMAT.md) — the adventure-select
## that makes FF a many-book game. Lists every installed adventure package from both
## shelves (bundled res://data/adventures + installed user://adventures) as a book
## card — cover plate, title, author, difficulty pips, blurb, shelf badge — over the
## FFUI vellum "library at dusk" ground. Selecting a book opens its card in the
## reading-desk panel: Begin (select the book -> roll-up -> play) and, when that book
## owns the newest of its saves, Continue straight back into it (per-adventure
## saves). "Install" is a folder/zip dropped into user://adventures — the Open-folder
## button jumps there and Rescan picks new books up without a restart.

const ROLL_UP := "res://scripts/screens/roll_up.tscn"
const READING_VIEW := "res://scenes/reading_view.tscn"

var _cards := {}                # book id -> Button
var _selected_id := ""
var _desk: PanelContainer      # the reading-desk detail panel
var _desk_body: VBoxContainer
var _shelf_note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(FFUI.page_background(true))          # Drowned Vellum — a library at dusk
	add_child(FFUI.wash(FFUI.SLATE, 0.18))
	var ad := get_node_or_null("/root/AudioDirector")
	if ad != null:
		ad.play_music("menu")
	AdventureLibrary.scan(true)                    # pick up freshly-dropped installs
	_build()


func _build() -> void:
	for c in get_children():
		if not (c is ColorRect):
			c.queue_free()
	_cards.clear()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 20)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	margin.add_child(col)

	# --- header ----------------------------------------------------------------
	var head := FFUI.title("THE LIBRARY", 36, FFUI.PARCHMENT)
	head.add_theme_font_override(&"font", FFUI.font_runic())
	col.add_child(head)
	var sub := FFUI.label("Every book on this shelf is a world. Choose one, roll up your hero, and turn to §1.", 15, FFUI.VERDIGRIS_2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(FFUI.divider_rule())

	# --- the shelf (scrolling book-card flow) ----------------------------------
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var shelf := HFlowContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.alignment = FlowContainer.ALIGNMENT_CENTER
	shelf.add_theme_constant_override(&"h_separation", 18)
	shelf.add_theme_constant_override(&"v_separation", 18)
	scroll.add_child(shelf)

	var books := AdventureLibrary.entries()
	for e in books:
		shelf.add_child(_book_card(e))
	if books.is_empty():
		var empty := FFUI.label("The shelf is bare. Drop an adventure folder or .zip into the adventures folder below.", 16, FFUI.FEN)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shelf.add_child(empty)

	# --- the reading desk (selected-book detail + actions) ----------------------
	_desk = FFUI.framed_panel(FFUI.VERDIGRIS, true)
	_desk.visible = false
	_desk_body = VBoxContainer.new()
	_desk_body.add_theme_constant_override(&"separation", 8)
	_desk.add_child(_desk_body)
	col.add_child(_desk)

	# --- shelf-keeping footer ---------------------------------------------------
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override(&"separation", 10)
	var open_b := FFUI.chip("⤓  Open adventures folder")
	open_b.tooltip_text = "Install an adventure by dropping its folder or .zip here, then Rescan."
	open_b.pressed.connect(func() -> void: AdventureLibrary.open_user_folder())
	foot.add_child(open_b)
	var rescan := FFUI.chip("↻  Rescan the shelf")
	rescan.pressed.connect(_on_rescan)
	foot.add_child(rescan)
	_shelf_note = FFUI.label(_shelf_summary(books), 13, FFUI.FEN)
	_shelf_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shelf_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shelf_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_shelf_note)
	var back := FFUI.chip("◂  Back to the menu")
	back.pressed.connect(func() -> void: NoxShell.to_menu())
	foot.add_child(back)
	col.add_child(foot)

	# open on the flagship (or the active book) so the desk is never blank
	var pre := Adventure.book_id if Adventure.book_id != "" else AdventureLibrary.default_id()
	if _cards.has(pre):
		_select(pre)


func _shelf_summary(books: Array) -> String:
	var installed := 0
	for e in books:
		if str(e.get("source", "")) == "installed":
			installed += 1
	return "%d book(s) on the shelf  ·  %d installed by you" % [books.size(), installed]


# --- book cards ---------------------------------------------------------------


func _book_card(e: Dictionary) -> Control:
	var id := str(e.get("id", ""))
	var ok := bool(e.get("format_ok", false))
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(300, 332)
	b.add_theme_stylebox_override(&"normal", FFUI.panel_box(Color("241f19"), FFUI.UMBER, 2, 6))
	b.add_theme_stylebox_override(&"hover", FFUI.panel_box(Color("2b251d"), FFUI.VERDIGRIS, 2, 6))
	b.add_theme_stylebox_override(&"pressed", FFUI.panel_box(Color("2b251d"), FFUI.VERDIGRIS, 3, 6))
	b.add_theme_stylebox_override(&"focus", FFUI.panel_box(Color(0, 0, 0, 0), FFUI.FLAME, 2, 6))
	if not ok:
		b.modulate = Color(1, 1, 1, 0.55)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override(&"separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)

	# cover plate in the reused verdigris frame
	var frame := FFUI.tex_framed(FFUI.VERDIGRIS if ok else FFUI.FEN)
	frame.custom_minimum_size = Vector2(0, 168)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(240, 136)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var cover := AdventureLibrary.cover_texture(e)
	if cover != null:
		tr.texture = cover
	else:
		var ph := ColorRect.new()
		ph.color = FFUI.SLATE
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.add_child(ph)
	frame.add_child(tr)
	v.add_child(frame)

	var title := FFUI.label(str(e.get("title", id)), 19, FFUI.PARCHMENT, false)
	title.add_theme_font_override(&"font", FFUI.font_display_tracked(1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(title)

	var byline := FFUI.label("by %s" % str(e.get("author", "?")), 13, FFUI.VERDIGRIS_2)
	byline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(byline)

	var meta := HBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override(&"separation", 10)
	meta.add_child(_difficulty_pips(int(e.get("difficulty", 3))))
	var badge_text := "installed" if str(e.get("source", "")) == "installed" else "bundled"
	if bool(e.get("legacy", false)):
		badge_text += " · legacy"
	meta.add_child(FFUI.label(badge_text, 12, FFUI.FEN))
	v.add_child(meta)

	if not ok:
		var warn := FFUI.label("⚠ incompatible package", 12, FFUI.ARREARS)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(warn)

	b.pressed.connect(func() -> void: _select(id))
	_cards[id] = b
	return b


func _difficulty_pips(difficulty: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	row.add_child(FFUI.label("peril", 12, FFUI.FEN))
	var pips := ""
	for i in 5:
		pips += "●" if i < difficulty else "○"
	var l := FFUI.label(pips, 13, FFUI.ARREARS if difficulty >= 4 else FFUI.FLAME)
	row.add_child(l)
	return row


# --- the reading desk ---------------------------------------------------------


func _select(id: String) -> void:
	_selected_id = id
	for cid in _cards:
		_cards[cid].button_pressed = (cid == id)
	var e := AdventureLibrary.get_entry(id)
	if e.is_empty():
		_desk.visible = false
		return
	_desk.visible = true
	for c in _desk_body.get_children():
		c.queue_free()

	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	var t := FFUI.label(str(e.get("title", id)).to_upper(), 20, FFUI.PARCHMENT, false)
	t.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(FFUI.label("by %s" % str(e.get("author", "?")), 14, FFUI.VERDIGRIS_2))
	_desk_body.add_child(head)

	var blurb := FFUI.label(str(e.get("blurb", "")), 15, Color(0.86, 0.82, 0.72))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	_desk_body.add_child(blurb)

	var ok := bool(e.get("format_ok", false))
	if not ok:
		var problems: Array = e.get("problems", [])
		var why := FFUI.label("This package cannot be opened: %s" % "; ".join(problems), 13, FFUI.ARREARS)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD
		_desk_body.add_child(why)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 10)
	var begin := FFUI.choice_button("Begin this adventure  ▸", not ok, "incompatible" if not ok else "")
	begin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	begin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ok:
		begin.pressed.connect(_on_begin)
	actions.add_child(begin)
	var save_slot := SaveManager.newest_slot_for_book(id)
	if ok and save_slot >= 0:
		var cont := FFUI.choice_button("Continue your bookmark  ⌁")
		cont.alignment = HORIZONTAL_ALIGNMENT_CENTER
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cont.pressed.connect(func() -> void: _on_continue(save_slot))
		actions.add_child(cont)
	_desk_body.add_child(actions)


func _on_begin() -> void:
	if _selected_id == "" or not Adventure.set_book(_selected_id):
		return
	Adventure.new_adventure()
	get_tree().change_scene_to_file(ROLL_UP)


func _on_continue(slot: int) -> void:
	var entry = SaveManager.load_from_slot(slot)
	if entry == null:
		return
	get_tree().change_scene_to_file(READING_VIEW)


func _on_rescan() -> void:
	AdventureLibrary.scan(true)
	_build()
