extends Control
## NoxMUD rich client — GemStone-IV / StormFront depth + uniqueness.
## Left: room title, live styled text stream, a Thoughts/ESP sub-stream, command input.
## Right (scroll): VITALS (health/mana/spirit/stamina + roundtime + cast-time),
## CONDITION (stance meter, encumbrance, mind-state with the acuity ladder, level +
## posture), HANDS (L/R/prepared spell), ACTIVE SPELLS (name + countdown), INJURIES
## (13-region body figure tinted by wound rank), COMPASS rose, and HERE (also/exits).
## Fed live by the Evennia server via OOB (nox_state / nox_room). Code-built so the
## whole thing reskins per world (fantasy/sci-fi/dark-fantasy/cyberpunk/horror).

const GOLD := Color("d4af37")
const PARCH := Color("e6dcc4")
const DIM := Color("9a8c6e")
const WOUND := {0: Color("2f3a2a"), 1: Color("b8a634"), 2: Color("c9772e"), 3: Color("b23a3a")}
const STANCES := ["offensive", "advance", "forward", "neutral", "guarded", "defensive"]

var _net: Node
var _disp: FontFile
var _stream: RichTextLabel
var _thoughts: RichTextLabel
var _title: Label
var _input: LineEdit
var _bars := {}
var _rt: ProgressBar
var _ct: ProgressBar
var _stance_lbl: Label
var _stance_meter: ProgressBar
var _enc: ProgressBar
var _mind: ProgressBar
var _mind_lbl: Label
var _level_lbl: Label
var _posture_lbl: Label
var _hands := {}
var _spells_box: VBoxContainer
var _regions := {}
var _also: Label
var _exits: Label

func _ready() -> void:
	_disp = load("res://fonts/fantasy_serif.ttf")
	_net = $Net
	_build_ui()
	_net.text_received.connect(func(bb): _stream.append_text(bb))
	_net.oob_received.connect(_on_oob)
	_net.connected.connect(func(): _stream.append_text("[color=#7cba7c]* connected to the realm *[/color]\n"))
	_net.disconnected.connect(func(): _stream.append_text("[color=#c46]* disconnected *[/color]\n"))

# ------------------------------------------------------------------- build
func _build_ui() -> void:
	var bg := ColorRect.new(); bg.color = Color("16110b")
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT); add_child(bg)
	var root := MarginContainer.new(); root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root.add_theme_constant_override(m, 10)
	add_child(root)
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 10); root.add_child(hb)

	# LEFT
	var left := VBoxContainer.new(); left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8); hb.add_child(left)
	var tb := PanelContainer.new(); left.add_child(tb)
	_title = _mklabel("The Realm", _disp, 30, Color("e8c766")); tb.add_child(_title)
	var sw := PanelContainer.new(); sw.size_flags_vertical = SIZE_EXPAND_FILL; left.add_child(sw)
	_stream = RichTextLabel.new()
	_stream.bbcode_enabled = true; _stream.scroll_following = true; _stream.selection_enabled = true
	_stream.size_flags_vertical = SIZE_EXPAND_FILL
	sw.add_child(_stream)
	# Thoughts / ESP sub-stream (GS4 routes ESP to its own window)
	var tp := _panel("THOUGHTS · ESP")
	_thoughts = RichTextLabel.new(); _thoughts.bbcode_enabled = true; _thoughts.scroll_following = true
	_thoughts.custom_minimum_size = Vector2(0, 96); _thoughts.fit_content = false
	tp[1].add_child(_thoughts)
	_thoughts.append_text("[color=#9a8cd6]You hear the distant murmur of other minds…[/color]\n")
	left.add_child(tp[0])
	_input = LineEdit.new(); _input.placeholder_text = "Enter a command  (look, north, say hello, stance defensive, help)…"
	_input.text_submitted.connect(_on_submit); left.add_child(_input)

	# RIGHT (scrollable)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(360, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(scroll)
	var right := VBoxContainer.new(); right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8); scroll.add_child(right)
	right.add_child(_vitals_panel())
	right.add_child(_condition_panel())
	right.add_child(_hands_panel())
	right.add_child(_spells_panel())
	right.add_child(_injuries_panel())
	right.add_child(_compass_panel())
	right.add_child(_room_panel())

func _mklabel(t: String, font: FontFile, size: int, col: Color) -> Label:
	var l := Label.new(); l.text = t
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	return l

func _panel(title: String) -> Array:
	var pc := PanelContainer.new()
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 5); pc.add_child(v)
	v.add_child(_mklabel(title, _disp, 17, GOLD))
	v.add_child(HSeparator.new())
	return [pc, v]

func _thin_bar(fill: Color, h: int = 14) -> ProgressBar:
	var b := ProgressBar.new(); b.show_percentage = false; b.custom_minimum_size = Vector2(0, h)
	var fs := StyleBoxFlat.new(); fs.bg_color = fill; fs.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", fs); return b

func _vitals_panel() -> PanelContainer:
	var p := _panel("VITALS"); var v: VBoxContainer = p[1]
	for spec in [["Health", "a83232"], ["Mana", "3a6fb2"], ["Spirit", "b9c0d6"], ["Stamina", "4f9a4a"]]:
		var row := VBoxContainer.new()
		var hdr := HBoxContainer.new()
		var nm := _mklabel(spec[0], null, 15, PARCH); nm.size_flags_horizontal = SIZE_EXPAND_FILL
		var val := _mklabel("0/0", null, 14, DIM)
		hdr.add_child(nm); hdr.add_child(val); row.add_child(hdr)
		var bar := _thin_bar(Color(spec[1]), 16); row.add_child(bar)
		v.add_child(row); _bars[spec[0]] = {"bar": bar, "val": val}
	v.add_child(_mklabel("Roundtime", null, 13, DIM)); _rt = _thin_bar(Color("c9772e")); _rt.max_value = 10; v.add_child(_rt)
	v.add_child(_mklabel("Cast-time", null, 13, DIM)); _ct = _thin_bar(Color("8a5cc9")); _ct.max_value = 10; v.add_child(_ct)
	return p[0]

func _condition_panel() -> PanelContainer:
	var p := _panel("CONDITION"); var v: VBoxContainer = p[1]
	_stance_lbl = _mklabel("Stance: guarded", null, 15, PARCH); v.add_child(_stance_lbl)
	_stance_meter = _thin_bar(Color("caa64b"), 10); _stance_meter.max_value = 5; v.add_child(_stance_meter)
	v.add_child(_mklabel("Encumbrance", null, 13, DIM)); _enc = _thin_bar(Color("7a6a4a"), 12); v.add_child(_enc)
	var mh := HBoxContainer.new()
	var ml := _mklabel("Mind", null, 13, DIM); ml.size_flags_horizontal = SIZE_EXPAND_FILL
	_mind_lbl = _mklabel("clear as a bell", null, 13, Color("9ac6e0"))
	mh.add_child(ml); mh.add_child(_mind_lbl); v.add_child(mh)
	_mind = _thin_bar(Color("5a8fb2"), 12); v.add_child(_mind)
	var lh := HBoxContainer.new()
	_level_lbl = _mklabel("Level 1", null, 14, GOLD); _level_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	_posture_lbl = _mklabel("standing", null, 13, Color("8fb38f"))
	lh.add_child(_level_lbl); lh.add_child(_posture_lbl); v.add_child(lh)
	return p[0]

func _hands_panel() -> PanelContainer:
	var p := _panel("HANDS"); var v: VBoxContainer = p[1]
	for slot in ["Left", "Right", "Spell"]:
		var l := _mklabel("%s: empty" % slot, null, 14, PARCH)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(l); _hands[slot] = l
	return p[0]

func _spells_panel() -> PanelContainer:
	var p := _panel("ACTIVE SPELLS"); _spells_box = p[1]
	_set_spells([]); return p[0]

func _set_spells(spells: Array) -> void:
	# clear rows below the header+separator
	for c in _spells_box.get_children():
		if c is HSeparator or (c is Label and c.text == "ACTIVE SPELLS"): continue
		c.queue_free()
	if spells.is_empty():
		_spells_box.add_child(_mklabel("— none active —", null, 13, DIM)); return
	for sp in spells:
		var row := HBoxContainer.new()
		var nm := _mklabel(str(sp.get("name", "?")), null, 13, Color("cdb6f0")); nm.size_flags_horizontal = SIZE_EXPAND_FILL
		var secs := int(sp.get("left", 0))
		var tl := _mklabel("%d:%02d" % [secs / 60, secs % 60], null, 13, DIM)
		row.add_child(nm); row.add_child(tl); _spells_box.add_child(row)

func _injuries_panel() -> PanelContainer:
	var p := _panel("INJURIES"); var v: VBoxContainer = p[1]
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", 3); grid.add_theme_constant_override("v_separation", 3)
	var layout := [
		["", "head", ""], ["", "neck", ""],
		["left arm", "chest", "right arm"], ["left hand", "abdomen", "right hand"],
		["", "back", ""], ["left leg", "", "right leg"],
	]
	for rowarr in layout:
		for region in rowarr:
			if region == "":
				var sp := Control.new(); sp.custom_minimum_size = Vector2(96, 26); grid.add_child(sp)
			else:
				grid.add_child(_region(region))
	v.add_child(grid)
	v.add_child(_mklabel("green ok · yellow/orange/red = wound rank", null, 11, DIM))
	return p[0]

func _region(id: String) -> Panel:
	var pan := Panel.new(); pan.custom_minimum_size = Vector2(96, 26)
	var sb := StyleBoxFlat.new(); sb.bg_color = WOUND[0]; sb.set_corner_radius_all(3)
	sb.border_color = Color("4a4030"); sb.set_border_width_all(1)
	pan.add_theme_stylebox_override("panel", sb)
	var short := {"left arm": "L arm", "right arm": "R arm", "left hand": "L hand",
		"right hand": "R hand", "left leg": "L leg", "right leg": "R leg"}
	var l := _mklabel(short.get(id, id), null, 11, Color("d8d2c2"))
	l.set_anchors_and_offsets_preset(PRESET_FULL_RECT); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; pan.add_child(l)
	_regions[id] = pan; return pan

func _compass_panel() -> PanelContainer:
	var p := _panel("COMPASS"); var v: VBoxContainer = p[1]
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4); grid.add_theme_constant_override("v_separation", 4)
	for rowarr in [["nw", "n", "ne"], ["w", "·", "e"], ["sw", "s", "se"]]:
		for d in rowarr:
			if d == "·":
				var s := _mklabel("✦", null, 16, GOLD); s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; grid.add_child(s)
			else: grid.add_child(_dir(d))
	v.add_child(grid)
	var ud := HBoxContainer.new(); ud.add_theme_constant_override("separation", 4)
	for d in ["up", "down", "out"]: ud.add_child(_dir(d))
	v.add_child(ud); return p[0]

func _dir(d: String) -> Button:
	var b := Button.new(); b.text = d.to_upper(); b.custom_minimum_size = Vector2(58, 28)
	b.pressed.connect(func(): _send(d)); return b

func _room_panel() -> PanelContainer:
	var p := _panel("HERE"); var v: VBoxContainer = p[1]
	_also = _mklabel("Also here: —", null, 13, PARCH); _also.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(_also)
	_exits = _mklabel("Obvious exits: —", null, 13, Color("8fb3c9")); _exits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(_exits)
	return p[0]

# ------------------------------------------------------------------- logic
func _on_submit(cmd: String) -> void:
	_send(cmd); _input.clear()

func _send(cmd: String) -> void:
	if cmd.strip_edges() == "": return
	_stream.append_text("[color=#6f7f9a]> %s[/color]\n" % cmd); _net.send(cmd)

func _on_oob(cmd: String, _args: Array, kw: Dictionary) -> void:
	match cmd:
		"nox_state": _apply_state(kw)
		"nox_room": _apply_room(kw)

func _apply_state(s: Dictionary) -> void:
	# flat payload (Evennia OOB flattens nested dicts, so vitals arrive as top-level
	# [cur,max] lists and wounds/spells as flat alternating lists)
	for name in _bars:
		var key := str(name).to_lower()
		if s.has(key) and typeof(s[key]) == TYPE_ARRAY and s[key].size() >= 2:
			var cur := int(s[key][0]); var mx := int(s[key][1])
			_bars[name].bar.max_value = max(mx, 1); _bars[name].bar.value = cur
			_bars[name].val.text = "%d/%d" % [cur, mx]
	_rt.value = float(s.get("rt", 0.0)); _ct.value = float(s.get("casttime", 0.0))
	var stance := str(s.get("stance", "guarded"))
	_stance_lbl.text = "Stance: %s" % stance
	_stance_meter.value = STANCES.find(stance) if STANCES.has(stance) else 3
	_enc.value = int(s.get("encumbrance", 0))
	_mind.value = int(s.get("mind", 0)); _mind_lbl.text = str(s.get("mind_label", ""))
	_level_lbl.text = "Level %d" % int(s.get("level", 1))
	_posture_lbl.text = str(s.get("posture", "standing"))
	if _hands.has("Left"): _hands["Left"].text = "Left: %s" % str(s.get("hand_left", "empty"))
	if _hands.has("Right"): _hands["Right"].text = "Right: %s" % str(s.get("hand_right", "empty"))
	if _hands.has("Spell"): _hands["Spell"].text = "Spell: %s" % str(s.get("hand_spell", "none"))
	# unpack flat spells [name, secs, name, secs, ...]
	var sflat: Array = s.get("spells", [])
	var spells := []
	for i in range(0, sflat.size() - 1, 2):
		spells.append({"name": str(sflat[i]), "left": int(sflat[i + 1])})
	_set_spells(spells)
	# unpack flat wounds [loc, rank, loc, rank, ...]
	var wflat: Array = s.get("wounds", [])
	var wounds := {}
	for i in range(0, wflat.size() - 1, 2):
		wounds[str(wflat[i])] = int(wflat[i + 1])
	_tint_wounds(wounds)

func _tint_wounds(wounds: Dictionary) -> void:
	for id in _regions:
		var rank := int(wounds.get(id, 0))
		var sb: StyleBoxFlat = _regions[id].get_theme_stylebox("panel")
		sb.bg_color = WOUND.get(rank, WOUND[0])

func _apply_room(r: Dictionary) -> void:
	_title.text = str(r.get("title", "The Realm"))
	var also: Array = r.get("also", [])
	_also.text = "Also here: %s" % (", ".join(PackedStringArray(also)) if also else "—")
	var exits: Array = r.get("exits", [])
	_exits.text = "Obvious exits: %s" % (", ".join(PackedStringArray(exits)) if exits else "—")
