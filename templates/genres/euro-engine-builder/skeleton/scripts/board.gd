extends Control
## res://scripts/board.gd
## The board VIEW + interaction for the Euro engine-builder. Renders the shared
## action board, every player's tableau + resource bank + VP + stars, a current-
## player indicator, the objective tokens, and a turn log. On the human's turn
## (seat 0) it enables exactly the legal actions and forwards the chosen one to
## GameManager, which resolves it and auto-runs the AI seats. All rules live in
## EuroEngine; this only reads state and forwards a click. UI is built in code so
## the scene stays a bare Control + script. Labels join "scalable_text" (NoxDev
## ABI); ColorRect/Label placeholders stand in for real art (see TEMPLATE.md).

const SEED := 20260715  ## deterministic showcase; set 0 for a random game.
const PLAYERS := 4

const RES_COLOR := {
	"wood": Color(0.55, 0.40, 0.25),
	"grain": Color(0.85, 0.75, 0.30),
	"metal": Color(0.60, 0.63, 0.70),
	"coin": Color(0.90, 0.78, 0.35),
	"energy": Color(0.40, 0.72, 0.90),
}
const CAT_COLOR := {
	"forestry": Color(0.42, 0.62, 0.38),
	"farm": Color(0.80, 0.72, 0.34),
	"mining": Color(0.58, 0.60, 0.68),
	"energy": Color(0.40, 0.70, 0.88),
	"commerce": Color(0.82, 0.55, 0.40),
}

var _layer: CanvasLayer
var _title: Label
var _status: Label
var _action_row: HBoxContainer
var _hand_row: HBoxContainer
var _panels_row: HBoxContainer
var _objectives: Label
var _log_box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine == null or GameManager.engine.players.is_empty():
		GameManager.new_game(SEED, PLAYERS)
	_build_ui()
	GameManager.changed.connect(_refresh)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		GameManager.new_game(SEED, PLAYERS)


# =====================================================================
#  Static layout
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_title = _mk_label(Vector2(28, 16), 24, Color(0.92, 0.88, 0.66))
	_title.text = "EURO ENGINE-BUILDER"
	_status = _mk_label(Vector2(28, 50), 15, Color(0.80, 0.82, 0.86))

	_header(Vector2(28, 88), "ACTION BOARD  (take one)", 14, Color(0.72, 0.76, 0.82))
	_action_row = _mk_row(Vector2(28, 110))

	_header(Vector2(28, 158), "YOUR HAND  (click to BUILD)", 14, Color(0.72, 0.76, 0.82))
	_hand_row = _mk_row(Vector2(28, 180))

	_header(Vector2(28, 268), "PLAYERS", 14, Color(0.72, 0.76, 0.82))
	_panels_row = _mk_row(Vector2(28, 290))

	_objectives = _mk_label(Vector2(28, 560), 13, Color(0.78, 0.72, 0.55))

	_header(Vector2(28, 592), "LOG", 14, Color(0.72, 0.76, 0.82))
	_log_box = _column(Vector2(28, 614))

	var newbtn := _mk_button("New game")
	newbtn.position = Vector2(1040, 16)
	newbtn.pressed.connect(func() -> void: GameManager.new_game(SEED, PLAYERS))
	_layer.add_child(newbtn)


func _header(pos: Vector2, text: String, size: int, color: Color) -> void:
	var l := _mk_label(pos, size, color)
	l.text = text


func _mk_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_to_group(&"scalable_text")
	return b


func _mk_row(pos: Vector2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.position = pos
	h.add_theme_constant_override("separation", 8)
	_layer.add_child(h)
	return h


func _column(pos: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", 2)
	_layer.add_child(v)
	return v


# =====================================================================
#  Refresh on every state change
# =====================================================================

func _refresh() -> void:
	var e: EuroEngine = GameManager.engine
	if e.game_over:
		var w := e.winner
		_status.text = "GAME OVER — Winner: Player %d with %d VP  ·  round %d" % [
			w, int(e.final_scores[w]["total"]), e.round_index]
	else:
		var who := "YOUR TURN" if e.current == GameManager.HUMAN else "Player %d (AI) thinking…" % e.current
		_status.text = "%s   ·   round %d/%d   ·   deck %d" % [who, e.round_index + 1, EuroEngine.MAX_ROUNDS, e.deck.size()]
	_rebuild_actions(e)
	_rebuild_hand(e)
	_rebuild_panels(e)
	_rebuild_objectives(e)
	_rebuild_log(e)


func _rebuild_actions(e: EuroEngine) -> void:
	_clear(_action_row)
	var human := GameManager.HUMAN
	var can := GameManager.is_human_turn()
	# PRODUCE
	_action_row.add_child(_action_button("PRODUCE", can and e.is_legal(human, {"type": "PRODUCE"}),
		{"type": "PRODUCE"}))
	# RESEARCH
	_action_row.add_child(_action_button("RESEARCH", can and e.is_legal(human, {"type": "RESEARCH"}),
		{"type": "RESEARCH"}))
	# DEPLOY
	_action_row.add_child(_action_button("DEPLOY ★", can and e.is_legal(human, {"type": "DEPLOY"}),
		{"type": "DEPLOY"}))
	# A couple of representative TRADE options (2 wood -> coin, 2 grain -> coin).
	_action_row.add_child(_action_button("TRADE 2 wood→coin",
		can and e.is_legal(human, {"type": "TRADE", "from": "wood", "to": "coin"}),
		{"type": "TRADE", "from": "wood", "to": "coin"}))
	_action_row.add_child(_action_button("TRADE 2 grain→metal",
		can and e.is_legal(human, {"type": "TRADE", "from": "grain", "to": "metal"}),
		{"type": "TRADE", "from": "grain", "to": "metal"}))


func _action_button(text: String, enabled: bool, action: Dictionary) -> Button:
	var b := _mk_button(text)
	b.disabled = not enabled
	b.pressed.connect(func() -> void: GameManager.human_action(action))
	return b


func _rebuild_hand(e: EuroEngine) -> void:
	_clear(_hand_row)
	var human := GameManager.HUMAN
	var p: Dictionary = e.players[human]
	var can := GameManager.is_human_turn()
	for i in (p["hand"] as Array).size():
		var card_id := String(p["hand"][i])
		var card: Dictionary = EuroEngine.CARD_DB[card_id]
		var b := _mk_button("%s\ncost %s\n→ %s  (vp %d)" % [
			card["name"], e._fmt(card["cost"]), e._fmt(card["output"]), int(card["vp"])])
		b.custom_minimum_size = Vector2(150, 66)
		b.modulate = CAT_COLOR.get(String(card["category"]), Color.WHITE)
		b.disabled = not (can and e.is_legal(human, {"type": "BUILD", "hand_index": i}))
		b.pressed.connect(func() -> void: GameManager.human_action({"type": "BUILD", "hand_index": i}))
		_hand_row.add_child(b)


func _rebuild_panels(e: EuroEngine) -> void:
	_clear(_panels_row)
	for pi in e.players.size():
		_panels_row.add_child(_player_panel(e, pi))


func _player_panel(e: EuroEngine, pi: int) -> Control:
	var p: Dictionary = e.players[pi]
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(250, 240)
	box.add_theme_constant_override("separation", 2)

	var frame := ColorRect.new()
	frame.custom_minimum_size = Vector2(250, 240)
	frame.color = Color(0.14, 0.16, 0.20) if pi != e.current else Color(0.20, 0.24, 0.16)
	box.add_child(frame)

	var head := Label.new()
	head.text = "%s%s" % ["YOU (P0)" if pi == 0 else "AI P%d" % pi,
		"  ◄ turn" if pi == e.current and not e.game_over else ""]
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.95, 0.92, 0.70))
	head.add_to_group(&"scalable_text")
	box.add_child(head)

	var vp := Label.new()
	vp.text = "VP %d   ·   ★ %d   ·   cards %d" % [
		e.live_vp(pi), int(p["stars"]), (p["tableau"] as Array).size()]
	vp.add_theme_font_size_override("font_size", 14)
	vp.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	vp.add_to_group(&"scalable_text")
	box.add_child(vp)

	var res := Label.new()
	var parts: Array[String] = []
	for r in EuroEngine.RESOURCES:
		parts.append("%s %d" % [r.substr(0, 1), int(p["resources"][r])])
	res.text = "  ".join(parts)
	res.add_theme_font_size_override("font_size", 13)
	res.add_theme_color_override("font_color", Color(0.78, 0.82, 0.86))
	res.add_to_group(&"scalable_text")
	box.add_child(res)

	# Tableau by category (a compact production summary).
	var prod := Label.new()
	prod.text = "produces: %s" % e._fmt(e.production_of(p))
	prod.add_theme_font_size_override("font_size", 12)
	prod.add_theme_color_override("font_color", Color(0.66, 0.78, 0.68))
	prod.add_to_group(&"scalable_text")
	box.add_child(prod)

	for card_id in p["tableau"]:
		var card: Dictionary = EuroEngine.CARD_DB[card_id]
		var row := Label.new()
		row.text = "  • %s (%s)" % [card["name"], card["category"]]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", CAT_COLOR.get(String(card["category"]), Color.WHITE))
		row.add_to_group(&"scalable_text")
		box.add_child(row)

	return box


func _rebuild_objectives(e: EuroEngine) -> void:
	var parts: Array[String] = []
	for obj_id in e.objectives.keys():
		var by := int(e.objectives[obj_id]["claimed_by"])
		parts.append("%s: %s" % [obj_id, ("P%d" % by) if by >= 0 else "open"])
	_objectives.text = "OBJECTIVES (+%d each)  —  %s" % [EuroEngine.OBJ_VP, "   ·   ".join(parts)]


func _rebuild_log(e: EuroEngine) -> void:
	_clear(_log_box)
	for line in e.recent_log(6):
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.70, 0.72, 0.76))
		l.add_to_group(&"scalable_text")
		_log_box.add_child(l)


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
