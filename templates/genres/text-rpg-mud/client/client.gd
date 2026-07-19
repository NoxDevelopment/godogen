extends Control
## NoxMUD rich client — a GemStone-IV / StormFront-style docked layout, built in code
## so the whole thing is themeable per world (fantasy / sci-fi / dark-fantasy /
## cyberpunk / horror). Left: room title + styled scrolling text stream + command
## input. Right: vitals bars, roundtime, hands, compass rose, and room panel.
## Live text comes from the Evennia server via the Net child (websocket).

const GOLD := Color("d4af37")
const PARCH := Color("e6dcc4")
const DIM := Color("9a8c6e")

var _net: Node
var _disp_font: FontFile
var _stream: RichTextLabel
var _title: Label
var _input: LineEdit
var _bars := {}          # name -> {bar:ProgressBar, val:Label}
var _hands := {}         # slot -> Label
var _also: Label
var _exits: Label
var _rt: ProgressBar

func _ready() -> void:
	_disp_font = load("res://fonts/fantasy_serif.ttf")
	_net = $Net
	_build_ui()
	_net.text_received.connect(_on_text)
	_net.connected.connect(func(): _append("[color=#7cba7c]* connected to the realm *[/color]\n"))
	_net.disconnected.connect(func(): _append("[color=#c46]* disconnected *[/color]\n"))
	# demo/default vitals until the server sends live OOB data
	_set_bar("Health", 100, 100)
	_set_bar("Mana", 84, 120)
	_set_bar("Spirit", 10, 10)
	_set_bar("Stamina", 100, 100)
	_set_rt(0.0)

# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("16110b")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 10)
	root.add_theme_constant_override("margin_top", 10)
	root.add_theme_constant_override("margin_right", 10)
	root.add_theme_constant_override("margin_bottom", 10)
	add_child(root)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	root.add_child(hb)

	# ---- LEFT: title + text stream + input ----
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)

	var titlebar := PanelContainer.new()
	left.add_child(titlebar)
	_title = Label.new()
	_title.text = "The Realm"
	_title.add_theme_font_override("font", _disp_font)
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color("e8c766"))
	titlebar.add_child(_title)

	var streamwrap := PanelContainer.new()
	streamwrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(streamwrap)
	_stream = RichTextLabel.new()
	_stream.bbcode_enabled = true
	_stream.scroll_following = true
	_stream.selection_enabled = true
	_stream.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stream.add_theme_font_size_override("normal_font_size", 15)
	streamwrap.add_child(_stream)

	_input = LineEdit.new()
	_input.placeholder_text = "Enter a command  (look, north, say hello, help)…"
	_input.text_submitted.connect(_on_submit)
	left.add_child(_input)

	# ---- RIGHT: vitals / hands / compass / room ----
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)

	right.add_child(_vitals_panel())
	right.add_child(_hands_panel())
	right.add_child(_compass_panel())
	right.add_child(_room_panel())

func _panel(title: String) -> Array:
	# returns [PanelContainer, content VBox]
	var pc := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var h := Label.new()
	h.text = title
	h.add_theme_font_override("font", _disp_font)
	h.add_theme_font_size_override("font_size", 18)
	h.add_theme_color_override("font_color", GOLD)
	v.add_child(h)
	var sep := HSeparator.new()
	v.add_child(sep)
	return [pc, v]

func _vitals_panel() -> PanelContainer:
	var p := _panel("VITALS")
	var v: VBoxContainer = p[1]
	_add_bar(v, "Health", Color("a83232"))
	_add_bar(v, "Mana", Color("3a6fb2"))
	_add_bar(v, "Spirit", Color("b9c0d6"))
	_add_bar(v, "Stamina", Color("4f9a4a"))
	# roundtime
	var rtrow := VBoxContainer.new()
	var rl := Label.new(); rl.text = "Roundtime"; rl.add_theme_color_override("font_color", DIM)
	rtrow.add_child(rl)
	_rt = ProgressBar.new(); _rt.max_value = 10; _rt.value = 0; _rt.show_percentage = false
	_rt.custom_minimum_size = Vector2(0, 14)
	var rtfill := StyleBoxFlat.new(); rtfill.bg_color = Color("c9772e"); rtfill.set_corner_radius_all(3)
	_rt.add_theme_stylebox_override("fill", rtfill)
	rtrow.add_child(_rt)
	v.add_child(rtrow)
	return p[0]

func _add_bar(v: VBoxContainer, name: String, fill: Color) -> void:
	var row := VBoxContainer.new()
	var hdr := HBoxContainer.new()
	var nl := Label.new(); nl.text = name; nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.add_theme_color_override("font_color", PARCH)
	var vl := Label.new(); vl.text = "0/0"; vl.add_theme_color_override("font_color", DIM)
	hdr.add_child(nl); hdr.add_child(vl)
	row.add_child(hdr)
	var bar := ProgressBar.new(); bar.show_percentage = false; bar.custom_minimum_size = Vector2(0, 16)
	var fs := StyleBoxFlat.new(); fs.bg_color = fill; fs.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fs)
	row.add_child(bar)
	v.add_child(row)
	_bars[name] = {"bar": bar, "val": vl}

func _hands_panel() -> PanelContainer:
	var p := _panel("HANDS")
	var v: VBoxContainer = p[1]
	for slot in ["Left", "Right", "Spell"]:
		var l := Label.new()
		l.text = "%s: empty" % slot
		l.add_theme_color_override("font_color", PARCH)
		v.add_child(l)
		_hands[slot] = l
	return p[0]

func _compass_panel() -> PanelContainer:
	var p := _panel("COMPASS")
	var v: VBoxContainer = p[1]
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4); grid.add_theme_constant_override("v_separation", 4)
	var layout := [["nw","n","ne"],["w","·","e"],["sw","s","se"]]
	for rowarr in layout:
		for d in rowarr:
			if d == "·":
				var spacer := Label.new(); spacer.text = "✦"; spacer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				spacer.add_theme_color_override("font_color", GOLD)
				grid.add_child(spacer)
			else:
				grid.add_child(_dir_btn(d))
	v.add_child(grid)
	var ud := HBoxContainer.new(); ud.add_theme_constant_override("separation", 4)
	for d in ["up","down","out"]:
		ud.add_child(_dir_btn(d))
	v.add_child(ud)
	return p[0]

func _dir_btn(d: String) -> Button:
	var b := Button.new()
	b.text = d.to_upper()
	b.custom_minimum_size = Vector2(58, 30)
	b.pressed.connect(func(): _send(d))
	return b

func _room_panel() -> PanelContainer:
	var p := _panel("HERE")
	var v: VBoxContainer = p[1]
	_also = Label.new(); _also.text = "Also here: —"; _also.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_also.add_theme_color_override("font_color", PARCH)
	v.add_child(_also)
	_exits = Label.new(); _exits.text = "Obvious exits: —"; _exits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_exits.add_theme_color_override("font_color", Color("8fb3c9"))
	v.add_child(_exits)
	return p[0]

# ---------------------------------------------------------------- logic

func _on_text(bbcode: String) -> void:
	_append(bbcode)
	_scan_room(bbcode)

func _append(bbcode: String) -> void:
	_stream.append_text(bbcode)

func _on_submit(cmd: String) -> void:
	_send(cmd)
	_input.clear()

func _send(cmd: String) -> void:
	if cmd.strip_edges() == "":
		return
	_append("[color=#6f7f9a]> %s[/color]\n" % cmd)
	_net.send(cmd)

func _set_bar(name: String, cur: int, maxv: int) -> void:
	if not _bars.has(name):
		return
	var b = _bars[name]
	b.bar.max_value = maxv
	b.bar.value = cur
	b.val.text = "%d/%d" % [cur, maxv]

func _set_rt(seconds: float) -> void:
	_rt.value = seconds

func _scan_room(text: String) -> void:
	# lightweight parse of the plain text for the room title + exits until the
	# server sends structured OOB (GS4 tag protocol) — good enough to feel alive.
	var plain := _strip_bb(text)
	for line in plain.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("Obvious exits:") or l.begins_with("Obvious paths:"):
			_exits.text = l
		elif l.begins_with("Also here:"):
			_also.text = l

func _strip_bb(s: String) -> String:
	var re := RegEx.new(); re.compile("\\[/?[a-zA-Z][^\\]]*\\]")
	return re.sub(s, "", true)
