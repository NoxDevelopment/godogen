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
## state and forwards a click.
##
## LOOK (parity pass 2026-07-19): an Eldritch-Horror-style vigil built from OUR CC0
## art — a cosmic void gradient, map locations as bordered nodes carrying a Kenney
## structure icon (gates glow red, clue sites carry a tome, safe houses a shield),
## investigators as tinted pawn tokens and monsters as skull tokens on the map, the
## DOOM/MYSTERY/GATE/MONSTER tracks as icon+count chips, and each investigator as a
## framed panel (Kenney nox_ui panel_blue) with heart/mind/tome vitals. Icons:
## res://assets/icons/*.png (Kenney CC0). Labels join "scalable_text" (NoxDev ABI).

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
## Thematic structure icon per location id (fallback = generic node).
const LOC_ICON := {
	"town_square": "res://assets/icons/loc_house.png",
	"university": "res://assets/icons/loc_tower.png",
	"old_library": "res://assets/icons/clue.png",
	"old_church": "res://assets/icons/loc_church.png",
	"harbor": "res://assets/icons/loc_node.png",
	"rail_station": "res://assets/icons/loc_house.png",
	"asylum": "res://assets/icons/loc_watch.png",
	"observatory": "res://assets/icons/loc_tower.png",
	"black_woods": "res://assets/icons/loc_node.png",
}
const ICON_GATE := "res://assets/icons/loc_gate.png"
const ICON_SAFE := "res://assets/icons/loc_safe.png"
const ICON_CLUE := "res://assets/icons/clue.png"
const ICON_MONSTER := "res://assets/icons/monster.png"
const ICON_PAWN := "res://assets/icons/pawn.png"
const ICON_HP := "res://assets/icons/hp.png"
const ICON_SAN := "res://assets/icons/sanity.png"
const ICON_FOCUS := "res://assets/icons/focus.png"
const PANEL_BLUE := "res://addons/nox_ui/theme/kenney/panel_blue.png"
const PANEL_BROWN := "res://addons/nox_ui/theme/kenney/panel_brown.png"

const VOID_TOP := Color(0.09, 0.07, 0.15)   ## cosmic void (indigo)
const VOID_BOT := Color(0.03, 0.03, 0.06)
const INK := Color(0.80, 0.88, 0.82)
const INK_DIM := Color(0.64, 0.70, 0.76)

var _layer: CanvasLayer
var _title: Label
var _status: Label
var _tracks_row: HBoxContainer
var _mystery: Label
var _map_root: Control
var _panels_row: VBoxContainer
var _action_row: HFlowContainer
var _hint: Label
var _log_box: VBoxContainer

var _handoff_overlay: Control
var _handoff_label: Label

var _tex: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preload_tex()
	if GameManager.engine == null or GameManager.engine.investigators.is_empty():
		GameManager.new_game(SEED, INVESTIGATORS, DIFFICULTY)
	_build_ui()
	GameManager.changed.connect(_refresh)
	GameManager.handoff_requested.connect(_on_handoff_requested)
	_refresh()


func _preload_tex() -> void:
	var paths := LOC_ICON.values() + [ICON_GATE, ICON_SAFE, ICON_CLUE, ICON_MONSTER,
		ICON_PAWN, ICON_HP, ICON_SAN, ICON_FOCUS, PANEL_BLUE, PANEL_BROWN]
	for p in paths:
		if ResourceLoader.exists(p):
			_tex[p] = load(p)


func _t(path: String) -> Texture2D:
	return _tex.get(path) as Texture2D


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

	# Cosmic void — vertical indigo→black gradient.
	var bg := TextureRect.new()
	bg.texture = _void_texture()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	_layer.add_child(bg)

	_title = _lbl(Vector2(24, 14), 24, Color(0.72, 0.86, 0.80))
	_title.text = "THE LONG VIGIL  ·  Cosmic-Horror Co-op"
	_status = _lbl(Vector2(24, 48), 15, Color(0.82, 0.84, 0.88))

	# Tracks as icon chips.
	_tracks_row = HBoxContainer.new()
	_tracks_row.position = Vector2(24, 74)
	_tracks_row.add_theme_constant_override("separation", 18)
	_layer.add_child(_tracks_row)
	_mystery = _lbl(Vector2(24, 100), 14, Color(0.86, 0.82, 0.62))

	# Map area (left) — a bare Control we draw into via _rebuild_map().
	_map_root = Control.new()
	_map_root.position = Vector2(0, 124)
	_map_root.custom_minimum_size = Vector2(780, 520)
	_layer.add_child(_map_root)

	# Investigator panels (right column).
	_hdr(Vector2(800, 128), "INVESTIGATORS")
	_panels_row = VBoxContainer.new()
	_panels_row.position = Vector2(800, 150)
	_panels_row.add_theme_constant_override("separation", 6)
	_layer.add_child(_panels_row)

	# Action bar (bottom) for the active human seat.
	_hdr(Vector2(24, 646), "ACTIONS  ·  active investigator — click one")
	_action_row = HFlowContainer.new()
	_action_row.position = Vector2(24, 668)
	_action_row.custom_minimum_size = Vector2(752, 0)
	_action_row.size = Vector2(752, 60)
	_action_row.add_theme_constant_override("h_separation", 6)
	_action_row.add_theme_constant_override("v_separation", 4)
	_layer.add_child(_action_row)
	_hint = _lbl(Vector2(24, 738), 12, Color(0.66, 0.70, 0.76))

	# Log (bottom-right).
	_hdr(Vector2(800, 648), "CHRONICLE")
	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(800, 670)
	_log_box.add_theme_constant_override("separation", 1)
	_layer.add_child(_log_box)

	# Session buttons (top-right strip).
	var btns := HBoxContainer.new()
	btns.position = Vector2(800, 40)
	btns.add_theme_constant_override("separation", 6)
	_layer.add_child(btns)
	btns.add_child(_sbtn("New Vigil", func() -> void: GameManager.new_game(SEED, INVESTIGATORS, DIFFICULTY)))
	var watch := _sbtn("Watch AI", func() -> void: GameManager.new_all_autopilot_game(4, SEED, DIFFICULTY))
	watch.tooltip_text = "All 4 investigators run on the co-op autopilot heuristic."
	btns.add_child(watch)
	btns.add_child(_sbtn("Hotseat 2P", func() -> void: GameManager.new_hotseat_game(2, 2, SEED, DIFFICULTY)))

	_build_handoff_overlay()


func _void_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, VOID_TOP)
	g.set_color(1, VOID_BOT)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 32; gt.height = 256
	gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	return gt


func _panel(tex_path: String, size: Vector2) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = size
	var t := _t(tex_path)
	if t != null:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.set_texture_margin_all(18)
		sb.set_content_margin_all(12)
		pc.add_theme_stylebox_override("panel", sb)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.14, 0.18)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(10)
		pc.add_theme_stylebox_override("panel", sb)
	return pc


func _build_handoff_overlay() -> void:
	_handoff_overlay = Control.new()
	_handoff_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handoff_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_handoff_overlay.visible = false
	_layer.add_child(_handoff_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handoff_overlay.add_child(dim)
	var card := _panel(PANEL_BROWN, Vector2(500, 200))
	card.position = Vector2(390, 260)
	_handoff_overlay.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)
	var title := Label.new()
	title.text = "PASS THE DEVICE"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.74, 0.88, 0.80))
	title.add_to_group(&"scalable_text")
	col.add_child(title)
	_handoff_label = Label.new()
	_handoff_label.text = "Next investigator's turn"
	_handoff_label.add_theme_font_size_override("font_size", 18)
	_handoff_label.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	_handoff_label.add_to_group(&"scalable_text")
	col.add_child(_handoff_label)
	var ready := _mk_button("Ready — reveal my turn")
	ready.custom_minimum_size = Vector2(240, 40)
	ready.pressed.connect(func() -> void: GameManager.acknowledge_handoff())
	col.add_child(ready)


func _on_handoff_requested(_seat: int, seat_name: String) -> void:
	if _handoff_label != null:
		_handoff_label.text = "%s — take the seat, then press Ready." % seat_name


# =====================================================================
#  Small builders
# =====================================================================

func _lbl(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	_layer.add_child(l)
	return l


func _hdr(pos: Vector2, text: String) -> void:
	var l := _lbl(pos, 14, Color(0.70, 0.78, 0.84))
	l.text = text


func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_to_group(&"scalable_text")
	return b


func _sbtn(text: String, cb: Callable) -> Button:
	var b := _mk_button(text)
	b.custom_minimum_size = Vector2(0, 30)
	b.pressed.connect(cb)
	return b


func _icon(path: String, px: int, tint: Color) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = _t(path)
	ic.custom_minimum_size = Vector2(px, px)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.modulate = tint
	return ic


## Icon + count chip (parented by caller).
func _chip(path: String, amount: int, tint: Color, px: int = 20, fs: int = 14, suffix: String = "") -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.add_child(_icon(path, px, tint))
	var l := Label.new()
	l.text = str(amount) + suffix
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", INK)
	l.add_to_group(&"scalable_text")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


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

	_rebuild_tracks(e)
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


func _rebuild_tracks(e: CosmicEngine) -> void:
	_clear(_tracks_row)
	_tracks_row.add_child(_chip(ICON_MONSTER, e.doom, Color(0.90, 0.40, 0.40), 20, 15, " DOOM"))
	_tracks_row.add_child(_chip(ICON_CLUE, e.mysteries_solved, Color(0.86, 0.82, 0.55), 20, 15,
		" / %d MYST" % CosmicEngine.MYSTERIES_TO_WIN))
	_tracks_row.add_child(_chip(ICON_GATE, e.open_gates.size(), Color(0.85, 0.45, 0.60), 20, 15,
		" / %d GATES" % int(e.cfg["gate_limit"])))
	_tracks_row.add_child(_chip(ICON_MONSTER, e.monsters.size(), Color(0.70, 0.55, 0.85), 20, 15, " MON"))


func _rebuild_map(e: CosmicEngine) -> void:
	_clear(_map_root)
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
	for id in CosmicEngine.LOCATIONS.keys():
		_node(e, String(id))
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
	line.default_color = Color(0.30, 0.26, 0.42, 0.7)
	_map_root.add_child(line)


func _node(e: CosmicEngine, id: String) -> void:
	var loc: Dictionary = CosmicEngine.LOCATIONS[id]
	var p: Vector2 = NODE_POS[id] - _map_root.position
	var gate_open: bool = bool(loc["gate"]) and e.open_gates.has(id)
	# Node card (rounded, state-bordered).
	var card := PanelContainer.new()
	card.size = Vector2(116, 44)
	card.position = p - Vector2(58, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.12, 0.20, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(4)
	if gate_open:
		sb.border_color = Color(0.90, 0.30, 0.36)          # open gate — red alarm
		sb.bg_color = Color(0.26, 0.10, 0.14, 0.95)
	elif bool(loc["gate"]):
		sb.border_color = Color(0.60, 0.40, 0.70)          # dormant gate — violet
	elif bool(loc["clue"]):
		sb.border_color = Color(0.66, 0.70, 0.42)          # clue site — pale gold
	elif bool(loc["safe"]):
		sb.border_color = Color(0.42, 0.62, 0.52)          # safe house — teal
	else:
		sb.border_color = Color(0.34, 0.34, 0.44)
	card.add_theme_stylebox_override("panel", sb)
	_map_root.add_child(card)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(h)
	var icon_path := String(LOC_ICON.get(id, "res://assets/icons/loc_node.png"))
	if gate_open or bool(loc["gate"]):
		icon_path = ICON_GATE
	h.add_child(_icon(icon_path, 22, Color(0.92, 0.90, 0.86)))
	var nm := Label.new()
	nm.text = String(loc["name"])
	nm.add_theme_font_size_override("font_size", 10)
	nm.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	nm.add_to_group(&"scalable_text")
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(70, 0)
	h.add_child(nm)


func _inv_token(e: CosmicEngine, inv: Dictionary) -> void:
	var idx := int(inv["index"])
	var p: Vector2 = NODE_POS[inv["location"]] - _map_root.position
	var tint: Color = INV_COLOR[idx % INV_COLOR.size()] if not bool(inv["defeated"]) else Color(0.4, 0.4, 0.4)
	var ic := _icon(ICON_PAWN, 20, tint)
	ic.position = p + Vector2(-46 + idx * 15, 20)
	_map_root.add_child(ic)


func _mon_token(e: CosmicEngine, mon: Dictionary, offset: int) -> void:
	var p: Vector2 = NODE_POS[mon["location"]] - _map_root.position
	var ic := _icon(ICON_MONSTER, 18, Color(0.90, 0.38, 0.40))
	ic.position = p + Vector2(20 + (offset % 4) * 12, -34)
	_map_root.add_child(ic)


func _rebuild_panels(e: CosmicEngine) -> void:
	_clear(_panels_row)
	for pi in e.investigators.size():
		_panels_row.add_child(_inv_panel(e, pi))


func _inv_panel(e: CosmicEngine, pi: int) -> Control:
	var inv: Dictionary = e.investigators[pi]
	var active := (pi == e.active_index and not e.game_over and e.phase == "action")
	var pc := _panel(PANEL_BROWN if active else PANEL_BLUE, Vector2(452, 104))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	pc.add_child(box)

	# Header: pawn + name [KIND] + status.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	box.add_child(head)
	head.add_child(_icon(ICON_PAWN, 20, INV_COLOR[pi % INV_COLOR.size()]))
	var kind_tag := "HUMAN" if e.is_human_seat(pi) else "AUTO"
	var status := "" if not bool(inv["defeated"]) else "  — DEFEATED"
	var head_l := Label.new()
	head_l.text = "%s  [%s]%s%s" % [e.seat_name(pi), kind_tag, "  ◄" if active else "", status]
	head_l.add_theme_font_size_override("font_size", 14)
	head_l.add_theme_color_override("font_color", INV_COLOR[pi % INV_COLOR.size()])
	head_l.add_to_group(&"scalable_text")
	head.add_child(head_l)

	# Vitals as icon chips: HP / SAN / clues / focus + location.
	var vit := HBoxContainer.new()
	vit.add_theme_constant_override("separation", 12)
	box.add_child(vit)
	vit.add_child(_chip(ICON_HP, int(inv["health"]), Color(0.90, 0.40, 0.42), 18, 12, "/%d" % int(inv["max_health"])))
	vit.add_child(_chip(ICON_SAN, int(inv["sanity"]), Color(0.55, 0.75, 0.95), 18, 12, "/%d" % int(inv["max_sanity"])))
	vit.add_child(_chip(ICON_CLUE, int(inv["clues"]), Color(0.86, 0.82, 0.55), 18, 12))
	vit.add_child(_chip(ICON_FOCUS, int(inv["focus"]), Color(0.95, 0.62, 0.35), 18, 12))
	var loc_l := Label.new()
	loc_l.text = "@ %s" % String(CosmicEngine.LOCATIONS[inv["location"]]["name"])
	loc_l.add_theme_font_size_override("font_size", 12)
	loc_l.add_theme_color_override("font_color", INK_DIM)
	loc_l.add_to_group(&"scalable_text")
	vit.add_child(loc_l)

	# Skills + assets (compact text row).
	var parts: Array[String] = []
	for s in CosmicEngine.SKILLS:
		parts.append("%s %d" % [s.substr(0, 3), int(inv["skills"][s])])
	var skills := Label.new()
	skills.text = "  ".join(parts)
	skills.add_theme_font_size_override("font_size", 11)
	skills.add_theme_color_override("font_color", Color(0.70, 0.78, 0.84))
	skills.add_to_group(&"scalable_text")
	box.add_child(skills)

	var anames: Array[String] = []
	for aid in inv["assets"]:
		anames.append(String(CosmicEngine.ASSET_DB[aid]["name"]))
	var assets := Label.new()
	assets.text = "assets: %s" % (", ".join(anames) if not anames.is_empty() else "—")
	assets.add_theme_font_size_override("font_size", 11)
	assets.add_theme_color_override("font_color", Color(0.66, 0.72, 0.66))
	assets.add_to_group(&"scalable_text")
	assets.clip_text = true
	assets.custom_minimum_size = Vector2(420, 0)
	box.add_child(assets)

	return pc


func _rebuild_actions(e: CosmicEngine) -> void:
	_clear(_action_row)
	if e.game_over:
		_hint.text = "The vigil has ended. Press New Vigil to begin again."
		return
	var seat := e.active_index
	var can := GameManager.can_accept_input()
	if not can:
		_hint.text = "Waiting…" if e.is_human_seat(seat) else "%s is on autopilot — actions resolve automatically." % e.seat_name(seat)
		return
	_hint.text = "Encounter + mythos phases resolve automatically after all actions."
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
