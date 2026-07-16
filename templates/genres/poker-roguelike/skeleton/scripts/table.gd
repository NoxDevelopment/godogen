extends Control
## res://scripts/table.gd
## The play surface. Shows the current ante / blind / TARGET + running score, your
## money + hands/discards left, the hand as SELECTABLE card buttons (1-5), the
## joker slots, Play / Discard buttons, and a simple SHOP panel between blinds. A
## human plays; the "Auto" button steps the deterministic auto-play to demo a run.
## All rules live in GameManager (the poker engine); this only reads state and
## forwards the chosen action. UI is built in code so the scene stays a bare
## Control + script.

const CARD_COLOR := {
	0: Color(0.82, 0.84, 0.90),  # spades  (blue-grey)
	1: Color(0.90, 0.45, 0.45),  # hearts  (red)
	2: Color(0.55, 0.80, 0.60),  # clubs   (green)
	3: Color(0.92, 0.70, 0.40),  # diamonds(orange)
}

var _layer: CanvasLayer
var _header: Label
var _status: Label
var _score: Label
var _result: Label
var _hand_box: HBoxContainer
var _joker_box: HBoxContainer
var _shop_box: VBoxContainer
var _log_box: VBoxContainer
var _play_btn: Button
var _discard_btn: Button
var _selected: Dictionary = {}  ## hand index -> true.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine.hand.is_empty() and not GameManager.engine.run_over:
		GameManager.new_run(20260715)
	_build_ui()
	GameManager.changed.connect(_refresh)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		_selected.clear()
		GameManager.new_run(20260715)


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.09, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_header = _mk_label(Vector2(28, 18), 24, Color(0.95, 0.88, 0.55))
	_status = _mk_label(Vector2(28, 54), 16, Color(0.82, 0.86, 0.82))
	_score = _mk_label(Vector2(28, 82), 18, Color(0.60, 0.90, 0.70))
	_result = _mk_label(Vector2(28, 112), 15, Color(0.90, 0.80, 0.50))

	_mk_header(Vector2(28, 150), "JOKERS")
	_joker_box = _mk_hbox(Vector2(28, 174))

	_mk_header(Vector2(28, 300), "HAND — select 1-5")
	_hand_box = _mk_hbox(Vector2(28, 324))

	_play_btn = _mk_button(Vector2(28, 430), "Play Hand")
	_play_btn.pressed.connect(_on_play)
	_discard_btn = _mk_button(Vector2(160, 430), "Discard")
	_discard_btn.pressed.connect(_on_discard)
	var auto_btn := _mk_button(Vector2(300, 430), "Auto Step")
	auto_btn.pressed.connect(func() -> void:
		_selected.clear()
		GameManager.auto_step())
	var restart_btn := _mk_button(Vector2(430, 430), "New Run")
	restart_btn.pressed.connect(func() -> void:
		_selected.clear()
		GameManager.new_run(20260715))

	_mk_header(Vector2(28, 486), "SHOP")
	_shop_box = _mk_vbox(Vector2(28, 510), 560)

	_mk_header(Vector2(640, 150), "LOG")
	_log_box = _mk_vbox(Vector2(640, 174), 560)


func _mk_header(pos: Vector2, text: String) -> void:
	var l := _mk_label(pos, 15, Color(0.78, 0.80, 0.78))
	l.text = text


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _mk_button(pos: Vector2, text: String) -> Button:
	var b := Button.new()
	b.position = pos
	b.text = text
	b.add_to_group(&"scalable_text")
	_layer.add_child(b)
	return b


func _mk_hbox(pos: Vector2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.position = pos
	h.add_theme_constant_override("separation", 6)
	_layer.add_child(h)
	return h


func _mk_vbox(pos: Vector2, width: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", 3)
	v.custom_minimum_size = Vector2(width, 0)
	_layer.add_child(v)
	return v


# --- refresh ---------------------------------------------------------------

func _refresh() -> void:
	var e: PokerEngine = GameManager.engine
	_header.text = e.ante_label()
	_status.text = "Target %d   ·   $%d   ·   Hands %d   ·   Discards %d" % [
		e.current_target, e.money, e.hands_left, e.discards_left]
	_score.text = "Round score:  %d / %d" % [e.round_score, e.current_target]
	if e.run_over:
		_result.text = "RUN WON!" if e.run_won else "RUN LOST"
		_result.add_theme_color_override("font_color",
			Color(0.5, 0.95, 0.6) if e.run_won else Color(0.95, 0.45, 0.45))
	elif e.last_score > 0:
		_result.text = "Last play scored %d" % e.last_score
	_rebuild_jokers(e)
	_rebuild_hand(e)
	_rebuild_shop(e)
	_rebuild_log(e)
	_play_btn.disabled = e.phase != "blind" or e.run_over
	_discard_btn.disabled = e.phase != "blind" or e.run_over or e.discards_left <= 0


func _rebuild_jokers(e: PokerEngine) -> void:
	_clear(_joker_box)
	if e.jokers.is_empty():
		_joker_box.add_child(_pill("(no jokers)", Color(0.5, 0.5, 0.5)))
		return
	for slot in e.jokers.size():
		var b := Button.new()
		b.text = "%s\n%s" % [e.joker_name(slot), e.joker_desc(slot)]
		b.custom_minimum_size = Vector2(150, 92)
		b.add_to_group(&"scalable_text")
		b.tooltip_text = "Click to sell (in shop)"
		b.pressed.connect(func() -> void:
			if e.phase == "shop":
				GameManager.sell_joker(slot))
		_joker_box.add_child(b)


func _rebuild_hand(e: PokerEngine) -> void:
	_clear(_hand_box)
	for i in e.hand.size():
		var card: Dictionary = e.hand[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = _selected.has(i)
		b.text = e.card_label(card)
		b.custom_minimum_size = Vector2(64, 90)
		b.add_theme_color_override("font_color", CARD_COLOR[int(card["suit"])])
		b.add_to_group(&"scalable_text")
		b.toggled.connect(_on_card_toggled.bind(i))
		_hand_box.add_child(b)


func _rebuild_shop(e: PokerEngine) -> void:
	_clear(_shop_box)
	if e.phase != "shop":
		_shop_box.add_child(_pill("(shop opens between blinds)", Color(0.5, 0.5, 0.5)))
		return
	for i in e.shop_items.size():
		var item: Dictionary = e.shop_items[i]
		var label: String
		if String(item["kind"]) == "joker":
			label = "Joker: %s — $%d" % [String(PokerEngine.JOKER_DB[String(item["id"])]["name"]), int(item["cost"])]
		else:
			label = "Planet: level up %s — $%d" % [String(PokerEngine.TYPE_NAME[int(item["type"])]), int(item["cost"])]
		var b := Button.new()
		b.text = ("[SOLD] " if bool(item.get("bought", false)) else "") + label
		b.disabled = bool(item.get("bought", false)) or not e.is_legal({"type": "buy", "index": i})
		b.add_to_group(&"scalable_text")
		b.pressed.connect(func() -> void: GameManager.buy(i))
		_shop_box.add_child(b)
	var leave := Button.new()
	leave.text = "Leave shop -> next blind"
	leave.add_to_group(&"scalable_text")
	leave.pressed.connect(func() -> void: GameManager.leave_shop())
	_shop_box.add_child(leave)


func _rebuild_log(e: PokerEngine) -> void:
	_clear(_log_box)
	for line in e.recent_log(14):
		_log_box.add_child(_pill(line, Color(0.72, 0.74, 0.72)))


func _pill(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# --- interaction -----------------------------------------------------------

func _on_card_toggled(pressed: bool, index: int) -> void:
	if pressed:
		if _selected.size() >= 5:
			# cap at 5 — reject the toggle visually.
			var btn := _hand_box.get_child(index) as Button
			btn.button_pressed = false
			return
		_selected[index] = true
	else:
		_selected.erase(index)


func _current_selection() -> Array:
	var arr: Array = _selected.keys()
	arr.sort()
	return arr


func _on_play() -> void:
	var sel := _current_selection()
	if sel.is_empty():
		return
	GameManager.play_selected(sel)
	_selected.clear()


func _on_discard() -> void:
	var sel := _current_selection()
	if sel.is_empty():
		return
	GameManager.discard_selected(sel)
	_selected.clear()
