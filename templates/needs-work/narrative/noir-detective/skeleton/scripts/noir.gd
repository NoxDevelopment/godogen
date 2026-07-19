extends Control
## res://scripts/noir.gd
## The investigation screen — the game's entry scene. Three columns, built
## entirely in code in a noir palette: INVESTIGATE (a button per location →
## examine it, clues surface), the CASEBOOK (every clue you've turned up), and
## DEDUCTIONS + ACCUSE (combine clues into deductions; once the chain is
## complete, name the culprit). It only reads GameManager (the case engine) and
## forwards clicks; every rule lives there. The scene stays a bare Control +
## script.

const BG := Color(0.06, 0.06, 0.08)
const INK := Color(0.86, 0.86, 0.82)
const DIM := Color(0.52, 0.52, 0.50)
const AMBER := Color(0.90, 0.72, 0.36)
const GHOST := Color(0.30, 0.30, 0.32)

var _layer: CanvasLayer
var _locations_box: VBoxContainer
var _casebook_box: VBoxContainer
var _deduce_box: VBoxContainer
var _accuse_box: VBoxContainer
var _log: Label
var _banner: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.is_closed():
		GameManager.begin_case()
	_build_chrome()
	if not GameManager.case_changed.is_connected(_rebuild):
		GameManager.case_changed.connect(_rebuild)
	_rebuild()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		GameManager.begin_case()


# --- static chrome ---------------------------------------------------------

func _build_chrome() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_header(Vector2(40, 24), "THE NEON ALIBI", 26, AMBER)
	_header(Vector2(40, 58), "A body in the office. Three names in the frame. Work the case.", 14, DIM)

	_header(Vector2(40, 104), "INVESTIGATE", 16, INK)
	_locations_box = _column(Vector2(40, 134))

	_header(Vector2(430, 104), "CASEBOOK", 16, INK)
	_casebook_box = _column(Vector2(430, 134))

	_header(Vector2(830, 104), "DEDUCTIONS", 16, INK)
	_deduce_box = _column(Vector2(830, 134))

	_header(Vector2(830, 430), "ACCUSE", 16, INK)
	_accuse_box = _column(Vector2(830, 460))

	_log = _mk_label(Vector2(40, 620), 14, AMBER)
	_banner = _mk_label(Vector2(40, 656), 18, AMBER)


func _header(pos: Vector2, text: String, size: int, color: Color) -> void:
	var l := _mk_label(pos, size, color)
	l.text = text


func _column(pos: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(360, 0)
	_layer.add_child(v)
	return v


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


# --- rebuild on every case change ------------------------------------------

func _rebuild() -> void:
	_clear(_locations_box)
	for loc_id in GameManager.LOCATIONS.keys():
		var loc: Dictionary = GameManager.LOCATIONS[loc_id]
		var found := _found_count(loc_id)
		var total := GameManager.clues_at(loc_id).size()
		var b := _button("%s   (%d/%d clues)" % [loc["name"], found, total], INK)
		b.disabled = GameManager.is_closed()
		b.pressed.connect(_on_examine.bind(String(loc_id)))
		_locations_box.add_child(b)

	_clear(_casebook_box)
	if GameManager.discovered.is_empty():
		_casebook_box.add_child(_text("No clues yet — start investigating.", DIM))
	for clue_id in GameManager.discovered:
		var clue: Dictionary = GameManager.CLUES[clue_id]
		_casebook_box.add_child(_text("• %s — %s" % [clue["name"], clue["desc"]], INK))

	_clear(_deduce_box)
	for ded_id in GameManager.DEDUCTIONS.keys():
		var ded: Dictionary = GameManager.DEDUCTIONS[ded_id]
		if GameManager.deductions_made.has(ded_id):
			_deduce_box.add_child(_text("✓ %s" % ded["name"], AMBER))
		elif GameManager.can_form(String(ded_id)):
			var b := _button("Deduce: %s" % ded["name"], AMBER)
			b.pressed.connect(_on_deduce.bind(String(ded_id)))
			_deduce_box.add_child(b)
		else:
			_deduce_box.add_child(_text("… %s (need more)" % ded["name"], GHOST))

	_clear(_accuse_box)
	var can := GameManager.can_accuse()
	for sus_id in GameManager.SUSPECTS.keys():
		var sus: Dictionary = GameManager.SUSPECTS[sus_id]
		var b := _button("%s — %s" % [sus["name"], sus["role"]], INK if can else GHOST)
		b.disabled = not can or GameManager.is_closed()
		b.pressed.connect(_on_accuse.bind(String(sus_id)))
		_accuse_box.add_child(b)

	_update_banner()


func _update_banner() -> void:
	if GameManager.is_closed():
		if GameManager.solved:
			_banner.text = "CASE CLOSED — %s was the killer. You called it." % GameManager.SUSPECTS[GameManager.CULPRIT]["name"]
			_banner.add_theme_color_override("font_color", AMBER)
		else:
			_banner.text = "WRONG. %s walks; the real killer laughs. (Enter to reopen the case.)" % GameManager.SUSPECTS[GameManager.accused]["name"]
			_banner.add_theme_color_override("font_color", Color(0.85, 0.4, 0.4))
	elif GameManager.can_accuse():
		_banner.text = "The chain is complete. Name the killer."
		_banner.add_theme_color_override("font_color", AMBER)
	else:
		_banner.text = "%d/%d deductions made." % [GameManager.deductions_made.size(), GameManager.DEDUCTIONS.size()]
		_banner.add_theme_color_override("font_color", DIM)


func _found_count(location_id: String) -> int:
	var n := 0
	for clue_id in GameManager.clues_at(location_id):
		if GameManager.has_clue(clue_id):
			n += 1
	return n


# --- widgets ----------------------------------------------------------------

func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", color)
	b.add_to_group(&"scalable_text")
	b.custom_minimum_size = Vector2(360, 30)
	return b


func _text(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# --- interaction ------------------------------------------------------------

func _on_examine(location_id: String) -> void:
	var found := GameManager.examine(location_id)
	if found.is_empty():
		_log.text = "Nothing new at %s." % GameManager.LOCATIONS[location_id]["name"]
	else:
		var names: Array[String] = []
		for clue_id in found:
			names.append(String(GameManager.CLUES[clue_id]["name"]))
		_log.text = "Found: %s" % ", ".join(names)


func _on_deduce(deduction_id: String) -> void:
	if GameManager.form_deduction(deduction_id):
		_log.text = "Deduction made: %s" % GameManager.DEDUCTIONS[deduction_id]["name"]


func _on_accuse(suspect_id: String) -> void:
	GameManager.accuse(suspect_id)
