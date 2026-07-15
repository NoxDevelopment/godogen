extends Node2D
## res://scripts/duel.gd
## The duel view + interaction. Renders both boards, your hand, life/mana, and an
## end-turn button; forwards clicks to the GameManager engine (which owns all
## rules). Play a card from hand, attack with a ready creature (face or a trade),
## end your turn and the greedy AI opponent takes theirs. UI is built in code so
## the scene stays a bare Node2D + script. Extend the card art + effects freely.

const SEED := 12345  ## deterministic opening deck; set 0 for a random shuffle.

var _sel_hand := -1       ## a spell selected, awaiting a target
var _sel_attacker := -1   ## your creature selected, awaiting a target

var _layer: CanvasLayer
var _opp_face: Button
var _opp_info: Label
var _you_info: Label
var _opp_board: HBoxContainer
var _you_board: HBoxContainer
var _hand: HBoxContainer
var _end_btn: Button
var _banner: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.setup(SEED)
	_build_ui()
	GameManager.changed.connect(_rebuild)
	_rebuild()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused


# --- static layout ---------------------------------------------------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	_opp_face = Button.new()
	_opp_face.position = Vector2(40, 24)
	_opp_face.add_to_group(&"scalable_text")
	_opp_face.pressed.connect(_on_target_face)
	_layer.add_child(_opp_face)

	_opp_info = _mk_label(Vector2(320, 30), 14)
	_opp_board = _mk_row(Vector2(40, 96))
	_you_board = _mk_row(Vector2(40, 300))

	_banner = _mk_label(Vector2(40, 240), 16)
	_banner.modulate = Color(0.9, 0.8, 0.4)

	_hand = _mk_row(Vector2(40, 430))
	_you_info = _mk_label(Vector2(40, 560), 16)

	_end_btn = Button.new()
	_end_btn.position = Vector2(520, 556)
	_end_btn.text = "End turn"
	_end_btn.add_to_group(&"scalable_text")
	_end_btn.pressed.connect(_on_end_turn)
	_layer.add_child(_end_btn)

	var newbtn := Button.new()
	newbtn.position = Vector2(640, 556)
	newbtn.text = "New duel"
	newbtn.add_to_group(&"scalable_text")
	newbtn.pressed.connect(_on_new_duel)
	_layer.add_child(newbtn)


func _mk_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _mk_row(pos: Vector2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.position = pos
	h.add_theme_constant_override("separation", 8)
	_layer.add_child(h)
	return h


# --- rebuild on every state change -----------------------------------------

func _rebuild() -> void:
	var you: Dictionary = GameManager.players[0]
	var opp: Dictionary = GameManager.players[1]
	var targeting := _sel_hand >= 0 or _sel_attacker >= 0

	_opp_face.text = "Opponent  HP %d" % int(opp["life"])
	_opp_face.disabled = not targeting
	_opp_info.text = "mana %d/%d · hand %d · deck %d" % [int(opp["mana"]), int(opp["max_mana"]), opp["hand"].size(), opp["deck"].size()]
	_you_info.text = "You  HP %d · mana %d/%d · deck %d" % [int(you["life"]), int(you["mana"]), int(you["max_mana"]), you["deck"].size()]

	_clear(_opp_board)
	for i in range(opp["board"].size()):
		var c: Dictionary = opp["board"][i]
		var b := _creature_button(c, false)
		b.disabled = not targeting
		b.pressed.connect(_on_target_creature.bind(i))
		_opp_board.add_child(b)

	_clear(_you_board)
	for i in range(you["board"].size()):
		var c: Dictionary = you["board"][i]
		var ready := bool(c["ready"]) and GameManager.active == 0 and GameManager.winner == -1
		var b := _creature_button(c, ready)
		b.disabled = not ready
		b.pressed.connect(_on_select_attacker.bind(i))
		if _sel_attacker == i:
			b.modulate = Color(1.0, 0.9, 0.4)
		_you_board.add_child(b)

	_clear(_hand)
	for i in range(you["hand"].size()):
		var card: Dictionary = GameManager.CARDS[you["hand"][i]]
		var b := Button.new()
		b.add_to_group(&"scalable_text")
		if card["type"] == "creature":
			b.text = "%s\n%d/%d  (%d)" % [card["name"], int(card["atk"]), int(card["hp"]), int(card["cost"])]
		else:
			b.text = "%s\n%d dmg  (%d)" % [card["name"], int(card["damage"]), int(card["cost"])]
		b.custom_minimum_size = Vector2(84, 60)
		b.modulate = card["color"] if _sel_hand != i else Color(1.0, 0.9, 0.4)
		b.disabled = not GameManager.can_play(0, i)
		b.pressed.connect(_on_hand.bind(i))
		_hand.add_child(b)

	_end_btn.disabled = GameManager.active != 0 or GameManager.winner != -1

	if GameManager.winner == 0:
		_banner.text = "You win!  —  New duel to play again."
	elif GameManager.winner == 1:
		_banner.text = "Defeated.  —  New duel to try again."
	elif targeting:
		_banner.text = "Pick a target: the enemy hero or a creature."
	elif GameManager.active == 1:
		_banner.text = "Opponent's turn…"
	else:
		_banner.text = "Your turn — play a card, attack, or end turn."


func _creature_button(c: Dictionary, ready: bool) -> Button:
	var b := Button.new()
	b.add_to_group(&"scalable_text")
	b.text = "%d/%d" % [int(c["atk"]), int(c["hp"])]
	b.custom_minimum_size = Vector2(56, 56)
	var col: Color = GameManager.CARDS[c["id"]]["color"]
	b.modulate = col if ready else Color(col.r * 0.7, col.g * 0.7, col.b * 0.7)
	return b


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# --- interaction -----------------------------------------------------------

func _on_hand(i: int) -> void:
	var card: Dictionary = GameManager.CARDS[GameManager.players[0]["hand"][i]]
	if card["type"] == "creature":
		GameManager.play_card(0, i, -1)  # emits changed → rebuild
	else:
		_sel_hand = i  # spell: await a target
		_sel_attacker = -1
		_rebuild()


func _on_select_attacker(i: int) -> void:
	_sel_attacker = i
	_sel_hand = -1
	_rebuild()


func _on_target_face() -> void:
	if _sel_hand >= 0:
		GameManager.play_card(0, _sel_hand, -1)
	elif _sel_attacker >= 0:
		GameManager.attack(0, _sel_attacker, -1)
	_sel_hand = -1
	_sel_attacker = -1


func _on_target_creature(enemy_index: int) -> void:
	if _sel_hand >= 0:
		GameManager.play_card(0, _sel_hand, enemy_index)
	elif _sel_attacker >= 0:
		GameManager.attack(0, _sel_attacker, enemy_index)
	_sel_hand = -1
	_sel_attacker = -1


func _on_end_turn() -> void:
	_sel_hand = -1
	_sel_attacker = -1
	GameManager.end_turn()  # → opponent's turn
	if GameManager.active == 1 and GameManager.winner == -1:
		get_tree().create_timer(0.7).timeout.connect(_run_ai)


func _run_ai() -> void:
	GameManager.ai_take_turn()  # plays, attacks, ends its turn → back to you


func _on_new_duel() -> void:
	_sel_hand = -1
	_sel_attacker = -1
	GameManager.setup(SEED)
