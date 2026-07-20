extends Control
## res://scripts/board.gd
## The board VIEW + interaction for the Euro engine-builder. Renders the shared
## action board, every player's tableau + resource bank + VP + stars, a current-
## player indicator, the objective tokens, and a turn log. It reads seat CONTROLLER
## KINDS from the engine and drives the play-mode matrix (STAGE 1) via GameManager:
## on a HUMAN_LOCAL seat's turn it enables exactly the legal actions and forwards
## the chosen one; AI_HEURISTIC seats auto-resolve into the log. For LOCAL HOTSEAT
## (more than one human) a "pass the device" hand-off banner appears before each
## human turn after the first — one machine, one input, pass-and-play. All rules
## live in EuroEngine; this only reads state and forwards a click.
##
## LOOK (parity pass 2026-07-19): the board renders like a real table euro
## (Scythe/Wingspan lineage) using OUR CC0 art — a felt-green table gradient, a
## carved wood header bar (Kenney nox_ui panel_brown 9-slice), resources shown as
## tinted Kenney board-game ICON chips (wood/grain/metal/coin/energy) instead of
## letters, player tableaus as framed panels (panel_blue; the active seat gets the
## warm panel_brown), VP/★ as crown+star icons, and the hand as framed cards with a
## category-tinted header + the card icon. Icons: res://assets/icons/*.png (Kenney
## CC0). Labels join "scalable_text" (NoxDev ABI). Built in code so the scene stays
## a bare Control + script.

const SEED := 20260715  ## deterministic showcase; set 0 for a random game.
const PLAYERS := 4

const RES_COLOR := {
	"wood": Color(0.62, 0.44, 0.26),
	"grain": Color(0.90, 0.78, 0.32),
	"metal": Color(0.70, 0.74, 0.82),
	"coin": Color(0.95, 0.80, 0.30),
	"energy": Color(0.46, 0.78, 0.96),
}
const CAT_COLOR := {
	"forestry": Color(0.46, 0.68, 0.42),
	"farm": Color(0.86, 0.76, 0.36),
	"mining": Color(0.62, 0.66, 0.74),
	"energy": Color(0.44, 0.76, 0.94),
	"commerce": Color(0.88, 0.58, 0.42),
}
const RES_ICON := {
	"wood": "res://assets/icons/res_wood.png",
	"grain": "res://assets/icons/res_grain.png",
	"metal": "res://assets/icons/res_metal.png",
	"coin": "res://assets/icons/res_coin.png",
	"energy": "res://assets/icons/res_energy.png",
}
const ICON_VP := "res://assets/icons/vp.png"
const ICON_STAR := "res://assets/icons/star.png"
const ICON_HEX := "res://assets/icons/hex.png"
const ICON_CARD := "res://assets/icons/card_frame.png"
const ICON_PAWN := "res://assets/icons/pawn.png"
const PANEL_BLUE := "res://addons/nox_ui/theme/kenney/panel_blue.png"
const PANEL_BROWN := "res://addons/nox_ui/theme/kenney/panel_brown.png"

const FELT_TOP := Color(0.13, 0.24, 0.17)     ## table felt (deep green)
const FELT_BOT := Color(0.06, 0.12, 0.09)
const INK := Color(0.93, 0.90, 0.74)          ## warm parchment text
const INK_DIM := Color(0.74, 0.78, 0.72)

var _layer: CanvasLayer
var _title: Label
var _status: Label
var _bank_row: HBoxContainer      ## shared "supply" bank chips (flavor + legend)
var _action_row: HBoxContainer
var _hand_row: HBoxContainer
var _panels_row: HBoxContainer
var _objectives: Label
var _log_box: VBoxContainer

var _handoff_overlay: Control
var _handoff_label: Label

var _tex: Dictionary = {}          ## cached loaded textures


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preload_tex()
	if not _online() and (GameManager.engine == null or GameManager.engine.players.is_empty()):
		GameManager.new_game(SEED, PLAYERS)
	_build_ui()
	GameManager.changed.connect(_refresh)
	GameManager.handoff_requested.connect(_on_handoff_requested)
	var eb := get_node_or_null(^"/root/EuroNet")
	if eb != null:
		eb.action_applied.connect(func(_seat: int, _action: Dictionary) -> void: _refresh())
		eb.turn_changed.connect(func(_seat: int) -> void: _refresh())
		eb.game_over.connect(func(_winner: int) -> void: _refresh())
	_refresh()


func _preload_tex() -> void:
	for p in RES_ICON.values():
		_tex[p] = load(p)
	for p in [ICON_VP, ICON_STAR, ICON_HEX, ICON_CARD, ICON_PAWN, PANEL_BLUE, PANEL_BROWN]:
		if ResourceLoader.exists(p):
			_tex[p] = load(p)


func _t(path: String) -> Texture2D:
	return _tex.get(path) as Texture2D


func _online() -> bool:
	var eb := get_node_or_null(^"/root/EuroNet")
	return eb != null and eb.is_online()


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

	# Felt table — vertical gradient (deep green), the "board surface".
	var felt := TextureRect.new()
	felt.texture = _felt_texture()
	felt.set_anchors_preset(Control.PRESET_FULL_RECT)
	felt.stretch_mode = TextureRect.STRETCH_SCALE
	_layer.add_child(felt)

	# Everything flows in a top-down VBox inside a margin — no absolute positions,
	# so nothing ever overlaps regardless of window height / content.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	_layer.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# --- Header bar: wood panel with title + status, session buttons on the right.
	var header := _panel(PANEL_BROWN, Vector2.ZERO, Vector2(0, 66))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hsb := header.get_theme_stylebox("panel")
	if hsb is StyleBoxTexture:
		(hsb as StyleBoxTexture).set_content_margin_all(12)
	root.add_child(header)
	var hbar := HBoxContainer.new()
	header.add_child(hbar)
	var titlecol := VBoxContainer.new()
	titlecol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titlecol.add_theme_constant_override("separation", 0)
	hbar.add_child(titlecol)
	_title = _lbl(26, INK); _title.text = "EURO ENGINE-BUILDER"; titlecol.add_child(_title)
	_status = _lbl(14, Color(0.86, 0.83, 0.64)); titlecol.add_child(_status)
	# Session controls — an absolute top-right button strip on the CanvasLayer
	# (reliable placement, clear of the flowing board VBox).
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.position = Vector2(770, 26)
	_layer.add_child(btns)
	btns.add_child(_hdr_button("New", func() -> void: GameManager.new_game(SEED, PLAYERS)))
	btns.add_child(_hdr_button("Hotseat 2P", func() -> void: GameManager.new_hotseat_game(2, 1, SEED)))
	var llm := _hdr_button("You + LLM", func() -> void: GameManager.new_game_with_llm(SEED, PLAYERS))
	llm.tooltip_text = "Seat 2 is LLM-assisted (Ollama). Needs [euro_llm] enabled + a running model; falls back to the heuristic AI otherwise."
	btns.add_child(llm)
	var net := _hdr_button("Host / Join", func() -> void:
		get_tree().change_scene_to_file("res://addons/nox_netcode/lobby.tscn"))
	net.tooltip_text = "Networked multiplayer over LAN/internet (host-authoritative, turn-based). Opens the lobby."
	btns.add_child(net)

	# --- Supply legend (icon key) on the header row's flow.
	var supply := HBoxContainer.new()
	supply.add_theme_constant_override("separation", 6)
	supply.add_child(_lbl(12, INK_DIM, "SUPPLY"))
	_bank_row = HBoxContainer.new(); _bank_row.add_theme_constant_override("separation", 8)
	supply.add_child(_bank_row)
	root.add_child(supply)

	root.add_child(_section_label("ACTION BOARD  ·  take one"))
	_action_row = HBoxContainer.new(); _action_row.add_theme_constant_override("separation", 8)
	root.add_child(_action_row)

	root.add_child(_section_label("YOUR HAND  ·  click a card to BUILD"))
	_hand_row = HBoxContainer.new(); _hand_row.add_theme_constant_override("separation", 8)
	root.add_child(_hand_row)

	root.add_child(_section_label("PLAYERS"))
	_panels_row = HBoxContainer.new(); _panels_row.add_theme_constant_override("separation", 8)
	root.add_child(_panels_row)

	_objectives = _lbl(13, Color(0.84, 0.76, 0.52)); root.add_child(_objectives)

	root.add_child(_section_label("LOG"))
	_log_box = VBoxContainer.new(); _log_box.add_theme_constant_override("separation", 1)
	_log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_log_box)

	_build_handoff_overlay()


## Plain label helper (parented by caller; joins the scalable-text ABI group).
func _lbl(size: int, color: Color, text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	return l


func _section_label(text: String) -> Label:
	return _lbl(13, INK_DIM, text)


func _hdr_button(text: String, cb: Callable) -> Button:
	var b := _mk_button(text)
	b.custom_minimum_size = Vector2(0, 30)
	b.pressed.connect(cb)
	return b


## A vertical felt gradient texture for the table surface.
func _felt_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, FELT_TOP)
	g.set_color(1, FELT_BOT)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 32
	gt.height = 256
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	return gt


## A 9-slice textured panel (Kenney nox_ui frame). Falls back to a flat box if the
## texture is missing so the board still renders on a partial clone.
func _panel(tex_path: String, pos: Vector2, size: Vector2) -> Control:
	var pc := PanelContainer.new()
	pc.position = pos
	pc.custom_minimum_size = size
	pc.size = size
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _t(tex_path)
	if t != null:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.set_texture_margin_all(18)
		pc.add_theme_stylebox_override("panel", sb)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.18, 0.20)
		sb.set_corner_radius_all(6)
		pc.add_theme_stylebox_override("panel", sb)
	return pc


func _build_handoff_overlay() -> void:
	_handoff_overlay = Control.new()
	_handoff_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handoff_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_handoff_overlay.visible = false
	_layer.add_child(_handoff_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.04, 0.93)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handoff_overlay.add_child(dim)

	var card := _panel(PANEL_BROWN, Vector2(390, 250), Vector2(500, 220))
	_handoff_overlay.add_child(card)

	var title := Label.new()
	title.text = "PASS THE DEVICE"
	title.position = Vector2(420, 285)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", INK)
	title.add_to_group(&"scalable_text")
	_handoff_overlay.add_child(title)

	_handoff_label = Label.new()
	_handoff_label.text = "Next player's turn"
	_handoff_label.position = Vector2(420, 335)
	_handoff_label.add_theme_font_size_override("font_size", 18)
	_handoff_label.add_theme_color_override("font_color", Color(0.88, 0.90, 0.84))
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


# =====================================================================
#  Small UI builders
# =====================================================================

func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_to_group(&"scalable_text")
	return b


## A resource icon + count "chip": the tinted Kenney token with its amount.
func _res_chip(res: String, amount: int, icon_px: int = 24, font_px: int = 14) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	var ic := TextureRect.new()
	ic.texture = _t(RES_ICON[res])
	ic.custom_minimum_size = Vector2(icon_px, icon_px)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.modulate = RES_COLOR[res]
	ic.tooltip_text = res
	h.add_child(ic)
	var l := Label.new()
	l.text = str(amount)
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", INK)
	l.add_to_group(&"scalable_text")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


## An icon + count pair for VP / stars.
func _icon_count(icon_path: String, amount: int, tint: Color, icon_px: int = 22) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	var ic := TextureRect.new()
	ic.texture = _t(icon_path)
	ic.custom_minimum_size = Vector2(icon_px, icon_px)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.modulate = tint
	h.add_child(ic)
	var l := Label.new()
	l.text = str(amount)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", INK)
	l.add_to_group(&"scalable_text")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


# =====================================================================
#  Refresh on every state change
# =====================================================================

func _refresh() -> void:
	var e: EuroEngine = GameManager.engine
	if e == null or e.players.is_empty():
		return
	if e.game_over:
		var w := e.winner
		_status.text = "GAME OVER — Winner: %s with %d VP  ·  round %d" % [
			e.seat_name(w), int(e.final_scores[w]["total"]), e.round_index]
	elif GameManager.pending_handoff:
		_status.text = "Pass the device — %s's turn   ·   round %d/%d" % [
			e.seat_name(e.current), e.round_index + 1, EuroEngine.MAX_ROUNDS]
	else:
		var who: String
		if e.is_human_seat(e.current):
			who = "%s — YOUR TURN" % e.seat_name(e.current)
		elif e.is_remote_seat(e.current):
			who = "%s (networked) — waiting…" % e.seat_name(e.current)
		else:
			who = "%s (AI) thinking…" % e.seat_name(e.current)
		_status.text = "%s   ·   round %d/%d   ·   deck %d" % [
			who, e.round_index + 1, EuroEngine.MAX_ROUNDS, e.deck.size()]
	if _handoff_overlay != null:
		_handoff_overlay.visible = GameManager.pending_handoff and not e.game_over
		if _handoff_overlay.visible and _handoff_label != null:
			_handoff_label.text = "%s — take the seat, then press Ready." % e.seat_name(e.current)
	_rebuild_bank(e)
	_rebuild_actions(e)
	_rebuild_hand(e)
	_rebuild_panels(e)
	_rebuild_objectives(e)
	_rebuild_log(e)


func _rebuild_bank(_e: EuroEngine) -> void:
	_clear(_bank_row)
	for r in EuroEngine.RESOURCES:
		# The supply legend shows each token type (large, unmuted) as a key.
		_bank_row.add_child(_res_chip(r, 0, 26, 1))  # count hidden (font 1px); icon-only legend


func _rebuild_actions(e: EuroEngine) -> void:
	_clear(_action_row)
	var seat := e.current
	var can := GameManager.can_accept_input()
	_action_row.add_child(_action_tile("PRODUCE", "gather resources",
		can and e.is_legal(seat, {"type": "PRODUCE"}), {"type": "PRODUCE"}))
	_action_row.add_child(_action_tile("RESEARCH", "draw + refine",
		can and e.is_legal(seat, {"type": "RESEARCH"}), {"type": "RESEARCH"}))
	_action_row.add_child(_action_tile("DEPLOY ★", "claim a star",
		can and e.is_legal(seat, {"type": "DEPLOY"}), {"type": "DEPLOY"}))
	_action_row.add_child(_action_tile("TRADE", "2 wood → coin",
		can and e.is_legal(seat, {"type": "TRADE", "from": "wood", "to": "coin"}),
		{"type": "TRADE", "from": "wood", "to": "coin"}))
	_action_row.add_child(_action_tile("TRADE", "2 grain → metal",
		can and e.is_legal(seat, {"type": "TRADE", "from": "grain", "to": "metal"}),
		{"type": "TRADE", "from": "grain", "to": "metal"}))


## An action-board tile: a hexagon token behind a title + hint, clickable.
func _action_tile(title: String, hint: String, enabled: bool, action: Dictionary) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(184, 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.20, 0.16) if enabled else Color(0.12, 0.13, 0.13)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.55, 0.72, 0.48, 0.9) if enabled else Color(0.28, 0.30, 0.30, 0.7)
	sb.content_margin_left = 10
	sb.content_margin_top = 6
	sb.content_margin_right = 10
	sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	pc.add_child(h)
	var hex := TextureRect.new()
	hex.texture = _t(ICON_HEX)
	hex.custom_minimum_size = Vector2(34, 34)
	hex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hex.modulate = Color(0.80, 0.86, 0.72) if enabled else Color(0.4, 0.42, 0.42)
	h.add_child(hex)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", INK if enabled else Color(0.55, 0.57, 0.57))
	t.add_to_group(&"scalable_text")
	v.add_child(t)
	var hn := Label.new()
	hn.text = hint
	hn.add_theme_font_size_override("font_size", 11)
	hn.add_theme_color_override("font_color", INK_DIM if enabled else Color(0.42, 0.44, 0.44))
	hn.add_to_group(&"scalable_text")
	v.add_child(hn)

	if enabled:
		pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pc.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				GameManager.submit_action(action))
	return pc


func _rebuild_hand(e: EuroEngine) -> void:
	_clear(_hand_row)
	var seat := e.current
	var p: Dictionary = e.players[seat]
	var can := GameManager.can_accept_input()
	for i in (p["hand"] as Array).size():
		var card_id := String(p["hand"][i])
		var card: Dictionary = EuroEngine.CARD_DB[card_id]
		var buildable := can and e.is_legal(seat, {"type": "BUILD", "hand_index": i})
		_hand_row.add_child(_card(e, card, i, buildable))


## A framed hand card: card_frame art behind a category-tinted header + cost/output
## rows (with resource icons) + VP star. Clickable to BUILD when legal.
func _card(e: EuroEngine, card: Dictionary, hand_index: int, buildable: bool) -> Control:
	var cat := String(card["category"])
	var tint: Color = CAT_COLOR.get(cat, Color.WHITE)

	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(164, 124)
	var t := _t(ICON_CARD)
	if t != null:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.set_texture_margin_all(16)
		sb.set_content_margin_all(10)
		pc.add_theme_stylebox_override("panel", sb)
		pc.modulate = Color(1, 1, 1) if buildable else Color(0.62, 0.62, 0.62)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint if buildable else tint.darkened(0.5)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		pc.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)

	# Header band: category-tinted name.
	var name_l := Label.new()
	name_l.text = String(card["name"])
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", tint if buildable else tint.darkened(0.3))
	name_l.add_to_group(&"scalable_text")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)

	var cat_l := Label.new()
	cat_l.text = cat
	cat_l.add_theme_font_size_override("font_size", 10)
	cat_l.add_theme_color_override("font_color", INK_DIM)
	cat_l.add_to_group(&"scalable_text")
	v.add_child(cat_l)

	v.add_child(_cost_row("cost", card["cost"]))
	v.add_child(_cost_row("→", card["output"]))

	var vp_row := _icon_count(ICON_STAR, int(card["vp"]), Color(0.95, 0.84, 0.35), 18)
	v.add_child(vp_row)

	if buildable:
		pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := hand_index
		pc.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				GameManager.submit_action({"type": "BUILD", "hand_index": idx}))
	return pc


## A compact resource row: a leading label then icon-chips for each {res: n}.
func _cost_row(prefix: String, bundle: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var pre := Label.new()
	pre.text = prefix
	pre.add_theme_font_size_override("font_size", 11)
	pre.add_theme_color_override("font_color", INK_DIM)
	pre.add_to_group(&"scalable_text")
	h.add_child(pre)
	for r in bundle.keys():
		if r in RES_ICON:
			h.add_child(_res_chip(String(r), int(bundle[r]), 16, 11))
	return h


func _rebuild_panels(e: EuroEngine) -> void:
	_clear(_panels_row)
	for pi in e.players.size():
		_panels_row.add_child(_player_panel(e, pi))


func _player_panel(e: EuroEngine, pi: int) -> Control:
	var p: Dictionary = e.players[pi]
	var active := pi == e.current and not e.game_over
	# Active seat gets the warm wood frame; others the blue frame.
	var pc := _panel(PANEL_BROWN if active else PANEL_BLUE, Vector2.ZERO, Vector2(252, 200))
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var sbt := pc.get_theme_stylebox("panel")
	if sbt is StyleBoxTexture:
		(sbt as StyleBoxTexture).set_content_margin_all(14)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	pc.add_child(box)

	# Header: pawn icon + name [KIND] + turn marker.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	box.add_child(head)
	var pawn := TextureRect.new()
	pawn.texture = _t(ICON_PAWN)
	pawn.custom_minimum_size = Vector2(22, 22)
	pawn.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pawn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pawn.modulate = _seat_color(pi)
	head.add_child(pawn)
	var kind_tag := "HUMAN"
	if e.is_llm_seat(pi):
		kind_tag = "LLM"
	elif e.is_remote_seat(pi):
		kind_tag = "NET"
	elif not e.is_human_seat(pi):
		kind_tag = "AI"
	var head_l := Label.new()
	head_l.text = "%s  [%s]%s" % [e.seat_name(pi), kind_tag, "  ◄" if active else ""]
	head_l.add_theme_font_size_override("font_size", 15)
	head_l.add_theme_color_override("font_color", INK)
	head_l.add_to_group(&"scalable_text")
	head.add_child(head_l)

	# VP + stars as icon counts.
	var vp_row := HBoxContainer.new()
	vp_row.add_theme_constant_override("separation", 12)
	vp_row.add_child(_icon_count(ICON_VP, e.live_vp(pi), Color(0.95, 0.82, 0.32)))
	vp_row.add_child(_icon_count(ICON_STAR, int(p["stars"]), Color(0.90, 0.90, 0.95)))
	box.add_child(vp_row)

	# Resource bank as icon chips.
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 6)
	for r in EuroEngine.RESOURCES:
		res_row.add_child(_res_chip(r, int(p["resources"][r]), 18, 12))
	box.add_child(res_row)

	var prod := Label.new()
	prod.text = "produces: %s" % e._fmt(e.production_of(p))
	prod.add_theme_font_size_override("font_size", 11)
	prod.add_theme_color_override("font_color", Color(0.68, 0.80, 0.70))
	prod.add_to_group(&"scalable_text")
	prod.clip_text = true                              # keep the panel at its fixed width
	prod.custom_minimum_size = Vector2(224, 0)
	box.add_child(prod)

	for card_id in p["tableau"]:
		var card: Dictionary = EuroEngine.CARD_DB[card_id]
		var row := Label.new()
		row.text = "  • %s" % card["name"]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", CAT_COLOR.get(String(card["category"]), Color.WHITE))
		row.add_to_group(&"scalable_text")
		row.clip_text = true
		row.custom_minimum_size = Vector2(224, 0)
		box.add_child(row)

	return pc


func _seat_color(pi: int) -> Color:
	const SEAT := [
		Color(0.86, 0.36, 0.34), Color(0.38, 0.62, 0.90),
		Color(0.52, 0.80, 0.46), Color(0.90, 0.76, 0.34),
	]
	return SEAT[pi % SEAT.size()]


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
		l.add_theme_color_override("font_color", Color(0.72, 0.74, 0.70))
		l.add_to_group(&"scalable_text")
		_log_box.add_child(l)


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
