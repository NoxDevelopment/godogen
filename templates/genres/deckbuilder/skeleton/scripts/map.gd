extends Control
## res://scripts/map.gd
## The roguelike run HUB — the game's entry scene. Draws the branching node map
## the GameManager engine generated (floors left→right, the boss on the right),
## your HP / gold / relics / deck at a glance, and lets you click a REACHABLE
## node to take it: a combat/elite/boss node loads the combat scene; a rest node
## heals; an event resolves on the spot. When the fight scene finishes it changes
## back here, and the map has already advanced. UI is built in code so the scene
## stays a bare Control + script.

const RUN_SEED := 20260714  ## a stable first-run showcase; New run rolls fresh.

const TYPE_LABEL := {
	"combat": "Fight",
	"elite": "Elite",
	"event": "Event",
	"rest": "Rest",
	"boss": "BOSS",
}
const TYPE_COLOR := {
	"combat": Color(0.72, 0.76, 0.85),
	"elite": Color(0.92, 0.62, 0.35),
	"event": Color(0.55, 0.82, 0.72),
	"rest": Color(0.62, 0.85, 0.55),
	"boss": Color(0.95, 0.42, 0.42),
}

var _layer: CanvasLayer
var _hud: Label
var _relics_label: Label
var _banner: Label
var _map_box: Control
var _new_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameManager.has_run or GameManager.is_run_over():
		GameManager.new_run(RUN_SEED)
	_build_chrome()
	if not GameManager.run_changed.is_connected(_rebuild):
		GameManager.run_changed.connect(_rebuild)
	_rebuild()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused


# --- static chrome ---------------------------------------------------------

func _build_chrome() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_hud = _mk_label(Vector2(28, 20), 18)
	_relics_label = _mk_label(Vector2(28, 50), 15)
	_banner = _mk_label(Vector2(28, 80), 20)
	_banner.modulate = Color(0.95, 0.86, 0.45)

	_map_box = Control.new()
	_map_box.position = Vector2(0, 120)
	_layer.add_child(_map_box)

	_new_btn = Button.new()
	_new_btn.position = Vector2(28, 660)
	_new_btn.text = "New run"
	_new_btn.add_to_group(&"scalable_text")
	_new_btn.pressed.connect(_on_new_run)
	_layer.add_child(_new_btn)


func _mk_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


# --- rebuild on every run change -------------------------------------------

func _rebuild() -> void:
	_hud.text = "HP %d/%d    Gold %d    Deck %d    Floor %d/%d" % [
		GameManager.hp, GameManager.max_hp, GameManager.gold,
		GameManager.deck.size(), _current_floor() + 1, GameManager.NUM_FLOORS,
	]
	_relics_label.text = "Relics: %s" % (_relic_names() if not GameManager.relics.is_empty() else "none yet")

	for c in _map_box.get_children():
		_map_box.remove_child(c)
		c.queue_free()

	var col_w := 200
	var row_h := 92
	for f in GameManager.map.size():
		var row: Array = GameManager.map[f]
		for i in row.size():
			var node: Dictionary = row[i]
			var b := Button.new()
			b.add_to_group(&"scalable_text")
			b.position = Vector2(28 + f * col_w, 20 + i * row_h)
			b.custom_minimum_size = Vector2(150, 66)
			var t := String(node["type"])
			b.text = "%s\n%s" % [TYPE_LABEL.get(t, t), _preview(node)]
			var reachable := GameManager.available.has(int(node["id"])) and not GameManager.is_run_over()
			b.disabled = not reachable
			b.modulate = TYPE_COLOR.get(t, Color.WHITE) if reachable else Color(0.35, 0.37, 0.42)
			if reachable:
				b.pressed.connect(_on_node.bind(int(node["id"])))
			_map_box.add_child(b)

	if GameManager.is_run_over():
		_banner.text = "VICTORY — the Archivist falls. New run to go again." if GameManager.run_won \
			else "DEFEAT — the run ends. New run to try again."
	elif GameManager.available.is_empty():
		_banner.text = "…"
	else:
		_banner.text = "Choose your next node."


func _preview(node: Dictionary) -> String:
	match String(node["type"]):
		"rest":
			return "heal"
		"event":
			return "?"
		"elite":
			return "hard"
		"boss":
			return "final"
		_:
			return "enemy"


func _current_floor() -> int:
	# the lowest floor still holding a reachable node = where the run stands.
	for f in GameManager.map.size():
		for node in GameManager.map[f]:
			if GameManager.available.has(int(node["id"])):
				return f
	return GameManager.NUM_FLOORS - 1


func _relic_names() -> String:
	var parts: Array[String] = []
	for id in GameManager.relics:
		parts.append(String(GameManager.RELICS.get(id, {}).get("name", id)))
	return ", ".join(parts)


# --- interaction -----------------------------------------------------------

func _on_node(node_id: int) -> void:
	var node: Dictionary = GameManager.enter_node(node_id)
	if node.is_empty():
		return
	if GameManager.is_combat_node(node):
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	# rest/event already resolved + advanced inside enter_node → _rebuild ran.


func _on_new_run() -> void:
	GameManager.new_run(0)  # a fresh, random run
