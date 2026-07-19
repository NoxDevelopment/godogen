extends Control
## res://scripts/gacha.gd
## The SUMMON screen. Shows the wallet + pity + the current 5★ chance, offers a
## single and a 10-pull, lists the last results (rarity-coloured) and your
## collection by rarity. All rules live in GameManager (the gacha engine); this
## only reads state and forwards pulls. UI is built in code so the scene stays a
## bare Control + script.

const RARITY_COLOR := {
	5: Color(0.96, 0.78, 0.30),  # gold
	4: Color(0.72, 0.52, 0.92),  # purple
	3: Color(0.55, 0.68, 0.82),  # blue-grey
}

var _layer: CanvasLayer
var _wallet: Label
var _pity: Label
var _banner: Label
var _results_box: VBoxContainer
var _collection_box: VBoxContainer
var _pull1: Button
var _pull10: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.total_pulls == 0 and GameManager.owned.is_empty():
		GameManager.new_account(20260714)
	_build_ui()
	GameManager.gacha_changed.connect(_refresh)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		GameManager.new_account(0)


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_header(Vector2(28, 20), "SUMMON — Radiant Banner", 24, Color(0.96, 0.86, 0.55))
	_wallet = _mk_label(Vector2(28, 56), 17, Color(0.86, 0.86, 0.82))
	_pity = _mk_label(Vector2(28, 82), 14, Color(0.6, 0.6, 0.58))

	_pull1 = _mk_button(Vector2(28, 120), "Pull ×1  (160)")
	_pull1.pressed.connect(_on_pull.bind(1))
	_pull10 = _mk_button(Vector2(220, 120), "Pull ×10  (1600)")
	_pull10.pressed.connect(_on_pull.bind(10))

	var gift := _mk_button(Vector2(430, 120), "+1600 gems")
	gift.pressed.connect(func() -> void: GameManager.add_gems(1600))

	_header(Vector2(28, 176), "LAST PULL", 15, Color(0.8, 0.8, 0.78))
	_results_box = _column(Vector2(28, 204))

	_header(Vector2(440, 176), "COLLECTION", 15, Color(0.8, 0.8, 0.78))
	_collection_box = _column(Vector2(440, 204))

	_banner = _mk_label(Vector2(28, 660), 18, Color(0.96, 0.78, 0.30))


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


func _mk_button(pos: Vector2, text: String) -> Button:
	var b := Button.new()
	b.position = pos
	b.text = text
	b.add_to_group(&"scalable_text")
	_layer.add_child(b)
	return b


func _column(pos: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(380, 0)
	_layer.add_child(v)
	return v


# --- refresh ---------------------------------------------------------------

func _refresh() -> void:
	_wallet.text = "Gems %d      Pulls %d      Unique owned %d" % [
		GameManager.gems, GameManager.total_pulls, GameManager.unique_owned()]
	_pity.text = "5★ pity %d/%d   ·   4★ pity %d/%d   ·   next 5★ chance %.1f%%" % [
		GameManager.pity_5, GameManager.HARD_PITY_5,
		GameManager.pity_4, GameManager.PITY_4,
		GameManager.current_five_chance() * 100.0]
	_pull1.disabled = not GameManager.can_pull(1)
	_pull10.disabled = not GameManager.can_pull(10)
	_rebuild_collection()


func _rebuild_results(results: Array) -> void:
	_clear(_results_box)
	if results.is_empty():
		_results_box.add_child(_row("Not enough gems.", Color(0.85, 0.4, 0.4)))
		return
	var best := 3
	for r in results:
		var rarity := int(r["rarity"])
		best = maxi(best, rarity)
		var tag := "%d★  %s%s" % [rarity, String(r["item"]), "  (dupe)" if r["dupe"] else ""]
		_results_box.add_child(_row(tag, RARITY_COLOR.get(rarity, Color.WHITE)))
	_banner.text = "★★★★★ %s!  A 5★ joins you." % _first_five(results) if best == 5 \
		else ("A 4★ in the batch." if best == 4 else "Keep summoning…")
	_banner.add_theme_color_override("font_color", RARITY_COLOR.get(best, Color.WHITE))


func _rebuild_collection() -> void:
	_clear(_collection_box)
	for rarity in [5, 4, 3]:
		var owned := GameManager.owned_of_rarity(rarity)
		if owned.is_empty():
			continue
		for item in owned:
			_collection_box.add_child(_row("%d★  %s  ×%d" % [rarity, item, GameManager.count_of(item)],
				RARITY_COLOR.get(rarity, Color.WHITE)))


func _first_five(results: Array) -> String:
	for r in results:
		if int(r["rarity"]) == 5:
			return String(r["item"])
	return ""


func _row(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# --- interaction -----------------------------------------------------------

func _on_pull(count: int) -> void:
	var results := GameManager.pull(count)  # emits gacha_changed → _refresh
	_rebuild_results(results)
