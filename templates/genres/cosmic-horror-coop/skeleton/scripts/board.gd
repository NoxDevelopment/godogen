extends Control
## res://scripts/board.gd
## The board VIEW + interaction for the CO-OP cosmic-horror game. Renders the world
## MAP (locations + connections + monster/investigator tokens), a PANEL per
## investigator (skills / health / sanity / clues / assets / location), the DOOM and
## MYSTERY tracks, the active mystery, and a turn LOG. It reads seat CONTROLLER
## KINDS from the engine and drives the co-op dispatcher via GameManager: on a
## HUMAN_LOCAL seat's action it enables exactly the legal actions and forwards the
## chosen one; AI_AUTOPILOT seats auto-resolve into the log. Encounter + mythos
## phases resolve automatically. All rules live in CosmicEngine; this only reads
## state and forwards a click. UI is built in code so the scene stays a bare Control
## + script. Labels join "scalable_text" (NoxDev ABI); ColorRect/Label placeholders
## stand in for real art (see TEMPLATE.md assetPlanHints).

const SEED := 424242         ## deterministic showcase; set 0 for a random vigil.
const INVESTIGATORS := 4
const DIFFICULTY := "normal"

## Fixed on-screen positions for the 9 map nodes (a rough geographic layout).
const NODE_POS := {
	"town_square":  Vector2(430, 300),
	"university":   Vector2(300, 190),
	"old_library":  Vector2(170, 300),
	"old_church":   Vector2(300, 410),
	"harbor":       Vector2(300, 540),
	"rail_station": Vector2(560, 410),
	"asylum":       Vector2(690, 300),
	"observatory":  Vector2(560, 170),
	"black_woods":  Vector2(430, 560),
}
const INV_COLOR := [
	Color(0.45, 0.75, 0.95), Color(0.95, 0.72, 0.40),
	Color(0.60, 0.90, 0.55), Color(0.90, 0.55, 0.80),
]

var _layer: CanvasLayer
var _title: Label
var _status: Label
var _tracks: Label
var _mystery: Label
var _map_root: Control
var _panels_row: VBoxContainer
var _action_row: HBoxContainer
var _hint: Label
var _log_box: VBoxContainer

var _handoff_overlay: Control
var _handoff_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine == null or GameManager.engine.investigators.is_empty():
		GameManager.new_game(SEED, INVESTIGATORS, DIFFICULTY)
	_build_ui()
	GameManager.changed.connect(_refresh)
	GameManager.handoff_requested.connect(_on_handoff_requested)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif e.is_action_pressed(&"restart"):
		GameManager.new_game(SEED, INVESTIGATORS, DIFFICULTY)


# =====================================================================
#  Static layout
# =====================================================================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_title = _mk_label(Vector2(24, 14), 24, Color(0.72, 0.86, 0.78))
	_title.text = "THE LONG VIGIL — Cosmic-Horror Co-op"
	_status = _mk_label(Vector2(24, 48), 15, Color(0.82, 0.84, 0.88))
	_tracks = _mk_label(Vector2(24, 72), 16, Color(0.92, 0.66, 0.60))
	_mystery = _mk_label(Vector2(24, 96), 15, Color(0.86, 0.82, 0.60))

	# Map area (left) — a bare Control we draw into via _rebuild_map().
	_map_root = Control.new()
	_map_root.position = Vector2(0, 120)
	_map_root.custom_minimum_size = Vector2(780, 520)
	_layer.add_child(_map_root)

	# Investigator panels (right column).
	_header(Vector2(800, 128), "INVESTIGATORS", 14, Color(0.70, 0.78, 0.84))
	_panels_row = VBoxContainer.new()
	_panels_row.position = Vector2(800, 150)
	_panels_row.add_theme_constant_override("separation", 6)
	_layer.add_child(_panels_row)

	# Action bar (bottom) for the active human seat.
	_header(Vector2(24, 636), "ACTIONS  (active investigator — click one)", 14, Color(0.70, 0.78, 0.84))
	_action_row = HBoxContainer.new()
	_action_row.position = Vector2(24, 658)
	_action_row.add_theme_constant_override("separation", 6)
	_layer.add_child(_action_row)
	_hint = _mk_label(Vector2(24, 694), 12, Color(0.66, 0.70, 0.76))

	# Log (bottom-right).
	_header(Vector2(800, 636), "CHRONICLE", 14, Color(0.70, 0.78, 0.84))
	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(800, 658)
	_log_box.add_theme_constant_override("separation", 1)
	_layer.add_child(_log_box)

	var restart := _mk_button("New Vigil (1P + AI)")
	restart.position = Vector2(1030, 14)
	restart.pressed.connect(func() -> void: GameManager.new_game(SEED, INVESTIGATORS, DIFFICULTY))
	_layer.add_child(restart)

	var allai := _mk_button("Watch AI Co-op")
	allai.position = Vector2(1030, 48)
	allai.tooltip_text = "All 4 investigators run on the co-op autopilot heuristic."
	allai.pressed.connect(func() -> void: GameManager.new_all_autopilot_game(4, SEED, DIFFICULTY))
	_layer.add_child(allai)

	var hot := _mk_button("Hotseat 2P")
	hot.position = Vector2(1030, 82)
	hot.pressed.connect(func() -> void: GameManager.new_hotseat_game(2, 2, SEED, DIFFICULTY))
	_layer.add_child(hot)

	_build_handoff_overlay()


func _build_handoff_overlay() -> void:
	_handoff_overlay = Control.new()
	_handoff_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handoff_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_handoff_overlay.visible = false
	_layer.add_child(_handoff_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.93)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handoff_overlay.add_child(dim)

	var card := ColorRect.new()
	card.color = Color(0.12, 0.15, 0.19)
	card.position = Vector2(390, 250)
	card.size = Vector2(500, 220)
	_handoff_overlay.add_child(card)

	var title := Label.new()
	title.text = "PASS THE DEVICE"
	title.position = Vector2(420, 285)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.74, 0.88, 0.80))
	title.add_to_group(&"scalable_text")
	_handoff_overlay.add_child(title)

	_handoff_label = Label.new()
	_handoff_label.text = "Next investigator's turn"
	_handoff_label.position = Vector2(420, 335)
	_handoff_label.add_theme_font_size_override("font_size", 18)
	_handoff_label.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	_handoff_label.add_to_group(&"scalable_text")
	_handoff_overlay.add_child(_handoff_label)

	var ready := _mk_button("Ready — reveal my turn")
	ready.position = Vector2(420, 400)
	ready.custom_minimum_size = Vector2(240, 40)
	ready.pressed.connect(func() -> void: GameManager.acknowledge_handoff())
	_handoff_overlay.add_child(ready)


func _on_handoff_requested(_seat: int, seat_name: String) -> void:
	if _handoff_label != null:
		_handoff_label.text = "%s — take the seat, then press Ready." % seat_name


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


# =====================================================================
#  Refresh on every state change
# =====================================================================

func _refresh() -> void:
	var e: CosmicEngine = GameManager.engine
	if e.game_over:
		if e.is_win():
			_status.text = "VICTORY — %d mysteries solved. The world holds. (round %d)" % [e.mysteries_solved, e.round_index]
		else:
			_status.text = "DEFEAT — %s. (round %d)" % [e.loss_reason, e.round_index]
	elif GameManager.pending_handoff:
		_status.text = "Pass the device — %s's turn   ·   round %d" % [e.seat_name(e.active_index), e.round_index + 1]
	else:
		var who := e.seat_name(e.active_index)
		if e.is_human_seat(e.active_index):
			_status.text = "%s — YOUR TURN   ·   %d action(s) left   ·   round %d" % [who, e.actions_remaining, e.round_index + 1]
		else:
			_status.text = "%s (autopilot) acting…   ·   round %d" % [who, e.round_index + 1]

	_tracks.text = "DOOM %d   ·   MYSTERIES %d / %d   ·   GATES %d / %d   ·   MONSTERS %d" % [
		e.doom, e.mysteries_solved, CosmicEngine.MYSTERIES_TO_WIN,
		e.open_gates.size(), int(e.cfg["gate_limit"]), e.monsters.size()]
	_mystery.text = "Active Mystery: %s  [%s]   ·   progress %d" % [
		e.active_mystery_name(), e.active_mystery_kind(), e.mystery_progress]

	if _handoff_overlay != null:
		_handoff_overlay.visible = GameManager.pending_handoff and not e.game_over
		if _handoff_overlay.visible and _handoff_label != null:
			_handoff_label.text = "%s — take the seat, then press Ready." % e.seat_name(e.active_index)

	_rebuild_map(e)
	_rebuild_panels(e)
	_rebuild_actions(e)
	_rebuild_log(e)


func _rebuild_map(e: CosmicEngine) -> void:
	_clear(_map_root)
	# Edges first (so nodes draw on top).
	var drawn := {}
	for a in CosmicEngine.MAP_EDGES.keys():
		var an := String(a)
		for b in CosmicEngine.MAP_EDGES[an]:
			var bn := String(b)
			var key: String = an + "|" + bn if an < bn else bn + "|" + an
			if drawn.has(key):
				continue
			drawn[key] = true
			_edge(Vector2(NODE_POS[an]) - _map_root.position, Vector2(NODE_POS[bn]) - _map_root.position)
	# Nodes.
	for id in CosmicEngine.LOCATIONS.keys():
		_node(e, String(id))
	# Tokens: investigators + monsters clustered near their node.
	for inv in e.investigators:
		_inv_token(e, inv)
	var mi := 0
	for mon in e.monsters:
		_mon_token(e, mon, mi)
		mi += 1


func _edge(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.add_point(a)
	line.add_point(b)
	line.width = 2.0
	line.default_color = Color(0.24, 0.28, 0.34)
	_map_root.add_child(line)


func _node(e: CosmicEngine, id: String) -> void:
	var loc: Dictionary = CosmicEngine.LOCATIONS[id]
	var p: Vector2 = NODE_POS[id] - _map_root.position
	var col := Color(0.20, 0.24, 0.30)
	if bool(loc["gate"]) and e.open_gates.has(id):
		col = Color(0.55, 0.25, 0.35)   # an open gate glows red.
	elif bool(loc["gate"]):
		col = Color(0.32, 0.26, 0.34)
	elif bool(loc["clue"]):
		col = Color(0.24, 0.32, 0.30)
	elif bool(loc["safe"]):
		col = Color(0.22, 0.30, 0.26)
	var dot := ColorRect.new()
	dot.color = col
	dot.position = p - Vector2(46, 16)
	dot.size = Vector2(92, 32)
	_map_root.add_child(dot)
	var l := Label.new()
	l.text = String(loc["name"])
	l.position = p - Vector2(44, 14)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	l.add_to_group(&"scalable_text")
	_map_root.add_child(l)


func _inv_token(e: CosmicEngine, inv: Dictionary) -> void:
	var idx := int(inv["index"])
	var p: Vector2 = NODE_POS[inv["location"]] - _map_root.position
	var dot := ColorRect.new()
	dot.color = INV_COLOR[idx % INV_COLOR.size()] if not bool(inv["defeated"]) else Color(0.35, 0.35, 0.35)
	dot.position = p + Vector2(-44 + idx * 12, 18)
	dot.size = Vector2(11, 11)
	_map_root.add_child(dot)


func _mon_token(e: CosmicEngine, mon: Dictionary, offset: int) -> void:
	var p: Vector2 = NODE_POS[mon["location"]] - _map_root.position
	var dot := ColorRect.new()
	dot.color = Color(0.85, 0.35, 0.35)
	dot.position = p + Vector2(18 + (offset % 4) * 9, -18)
	dot.size = Vector2(8, 8)
	_map_root.add_child(dot)


func _rebuild_panels(e: CosmicEngine) -> void:
	_clear(_panels_row)
	for pi in e.investigators.size():
		_panels_row.add_child(_inv_panel(e, pi))


func _inv_panel(e: CosmicEngine, pi: int) -> Control:
	var inv: Dictionary = e.investigators[pi]
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 108)
	box.add_theme_constant_override("separation", 0)

	var active := (pi == e.active_index and not e.game_over and e.phase == "action")
	var frame := ColorRect.new()
	frame.custom_minimum_size = Vector2(400, 108)
	frame.color = Color(0.11, 0.13, 0.17) if not active else Color(0.16, 0.20, 0.16)
	box.add_child(frame)

	var kind_tag := "AUTO"
	if e.is_human_seat(pi):
		kind_tag = "HUMAN"
	var head := Label.new()
	var status := "" if not bool(inv["defeated"]) else "  — DEFEATED"
	head.text = "%s  [%s]%s%s" % [e.seat_name(pi), kind_tag, "  ◄ turn" if active else "", status]
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", INV_COLOR[pi % INV_COLOR.size()])
	head.add_to_group(&"scalable_text")
	box.add_child(head)

	var vitals := Label.new()
	vitals.text = "HP %d/%d   SAN %d/%d   clues %d   focus %d   @ %s" % [
		int(inv["health"]), int(inv["max_health"]), int(inv["sanity"]), int(inv["max_sanity"]),
		int(inv["clues"]), int(inv["focus"]), String(CosmicEngine.LOCATIONS[inv["location"]]["name"])]
	vitals.add_theme_font_size_override("font_size", 12)
	vitals.add_theme_color_override("font_color", Color(0.84, 0.86, 0.90))
	vitals.add_to_group(&"scalable_text")
	box.add_child(vitals)

	var skills := Label.new()
	var parts: Array[String] = []
	for s in CosmicEngine.SKILLS:
		parts.append("%s %d" % [s.substr(0, 3), int(inv["skills"][s])])
	skills.text = "  ".join(parts)
	skills.add_theme_font_size_override("font_size", 11)
	skills.add_theme_color_override("font_color", Color(0.70, 0.78, 0.84))
	skills.add_to_group(&"scalable_text")
	box.add_child(skills)

	var assets := Label.new()
	var anames: Array[String] = []
	for aid in inv["assets"]:
		anames.append(String(CosmicEngine.ASSET_DB[aid]["name"]))
	assets.text = "assets: %s" % (", ".join(anames) if not anames.is_empty() else "—")
	assets.add_theme_font_size_override("font_size", 11)
	assets.add_theme_color_override("font_color", Color(0.66, 0.72, 0.66))
	assets.add_to_group(&"scalable_text")
	box.add_child(assets)

	return box


func _rebuild_actions(e: CosmicEngine) -> void:
	_clear(_action_row)
	if e.game_over:
		_hint.text = "The vigil has ended. Press New Vigil to begin again."
		return
	var seat := e.active_index
	var can := GameManager.can_accept_input()
	if not can:
		if e.is_human_seat(seat):
			_hint.text = "Waiting…"
		else:
			_hint.text = "%s is on autopilot — actions resolve automatically." % e.seat_name(seat)
		return
	_hint.text = "Encounter + mythos phases resolve automatically after all actions."
	# One button per legal action (labelled), forwarding it to the dispatcher.
	for action in e.legal_actions(seat):
		var a: Dictionary = action
		var b := _mk_button(_action_label(e, a))
		b.pressed.connect(func() -> void: GameManager.submit_action(a))
		_action_row.add_child(b)


func _action_label(e: CosmicEngine, action: Dictionary) -> String:
	match String(action["type"]):
		"move":
			return "Move → %s" % String(CosmicEngine.LOCATIONS[action["to"]]["name"])
		"rest":
			return "Rest (+HP/+SAN)"
		"acquire":
			return "Acquire asset"
		"prepare":
			return "Prepare (+focus)"
		"trade":
			return "Give clue → %s" % e.seat_name(int(action["to_index"]))
		"spend_clue":
			return "Invest clue (mystery)"
		_:
			return String(action["type"])


func _rebuild_log(e: CosmicEngine) -> void:
	_clear(_log_box)
	for line in e.recent_log(9):
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(0.70, 0.72, 0.76))
		l.add_to_group(&"scalable_text")
		_log_box.add_child(l)


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
