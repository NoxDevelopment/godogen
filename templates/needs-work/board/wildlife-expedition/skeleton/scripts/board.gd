extends Control
## res://scripts/board.gd
## The board VIEW + interaction for the wildlife-expedition engine. Renders the shared
## exploration TRAIL (sites + biomes + yields + pawn markers), the shared species OFFER
## + the active player's personal HAND + the gear/station SHOP, every player's FIELD
## JOURNAL (documented species) + resources + live score + pawns, the SEASON / GOAL /
## expedition track, a current-player indicator + a pass-the-device hand-off overlay,
## and a turn log. It reads seat CONTROLLER KINDS from the engine and drives the play
## matrix via GameManager: on a HUMAN_LOCAL seat's turn it enables exactly the legal
## actions and forwards the chosen one; AI seats auto-resolve into the log. For LOCAL
## HOTSEAT a "pass the device" banner appears before each human turn after the first.
## All rules live in WildlifeEngine; this only reads state and forwards a click. UI is
## built in code so the scene stays a bare Control + script; Labels join "scalable_text"
## (NoxDev ABI); ColorRect/Label placeholders stand in for real art (TEMPLATE.md).

const SEED := 20260715  ## deterministic showcase; set 0 for a random game.
const PLAYERS := 4

const BIOME_COLOR := {
	"forest": Color(0.30, 0.55, 0.32),
	"wetland": Color(0.28, 0.58, 0.62),
	"grassland": Color(0.72, 0.68, 0.32),
	"mountain": Color(0.55, 0.52, 0.60),
	"coast": Color(0.34, 0.52, 0.78),
}
const CAT_COLOR := {
	"mammal": Color(0.78, 0.52, 0.36),
	"bird": Color(0.40, 0.66, 0.86),
	"reptile": Color(0.52, 0.70, 0.40),
	"aquatic": Color(0.36, 0.62, 0.72),
	"insect": Color(0.82, 0.70, 0.34),
	"plant": Color(0.52, 0.72, 0.48),
}

var _layer: CanvasLayer
var _title: Label
var _status: Label
var _trail_row: HBoxContainer
var _move_row: HBoxContainer
var _offer_row: HBoxContainer
var _hand_row: HBoxContainer
var _gear_row: HBoxContainer
var _panels_row: HBoxContainer
var _track: Label
var _log_box: VBoxContainer

var _handoff_overlay: Control
var _handoff_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameManager.engine == null or GameManager.engine.players.is_empty():
		GameManager.new_game(SEED, PLAYERS)
	_build_ui()
	GameManager.changed.connect(_refresh)
	GameManager.handoff_requested.connect(_on_handoff_requested)
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
	bg.color = Color(0.08, 0.11, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)

	_title = _mk_label(Vector2(28, 14), 24, Color(0.86, 0.92, 0.72))
	_title.text = "WILDLIFE EXPEDITION"
	_status = _mk_label(Vector2(28, 48), 15, Color(0.80, 0.86, 0.82))

	_header(Vector2(28, 82), "EXPLORATION TRAIL  (Start → Trailhead)", 14, Color(0.70, 0.82, 0.74))
	_trail_row = _mk_row(Vector2(28, 104))

	_header(Vector2(28, 176), "YOUR MOVES  (advance a pawn)", 14, Color(0.70, 0.82, 0.74))
	_move_row = _mk_row(Vector2(28, 198))

	_header(Vector2(28, 244), "SPECIES OFFER  (document — needs matching biome + cost)", 14, Color(0.70, 0.82, 0.74))
	_offer_row = _mk_row(Vector2(28, 266))

	_header(Vector2(28, 342), "YOUR HAND", 13, Color(0.66, 0.78, 0.70))
	_hand_row = _mk_row(Vector2(28, 362))

	_header(Vector2(640, 342), "GEAR / STATIONS  (develop)", 13, Color(0.66, 0.78, 0.70))
	_gear_row = _mk_row(Vector2(640, 362))

	_header(Vector2(28, 430), "EXPLORERS", 14, Color(0.70, 0.82, 0.74))
	_panels_row = _mk_row(Vector2(28, 452))

	_track = _mk_label(Vector2(28, 636), 12, Color(0.80, 0.80, 0.60))

	_header(Vector2(28, 682), "LOG", 14, Color(0.70, 0.82, 0.74))
	_log_box = _column(Vector2(28, 704))

	var newbtn := _mk_button("New (1P+AI)")
	newbtn.position = Vector2(1060, 14)
	newbtn.pressed.connect(func() -> void: GameManager.new_game(SEED, PLAYERS))
	_layer.add_child(newbtn)

	var hotbtn := _mk_button("Hotseat 2P")
	hotbtn.position = Vector2(1060, 50)
	hotbtn.pressed.connect(func() -> void: GameManager.new_hotseat_game(2, 2, SEED))
	_layer.add_child(hotbtn)

	var aibtn := _mk_button("Watch AI (4)")
	aibtn.position = Vector2(1060, 86)
	aibtn.pressed.connect(func() -> void: GameManager.new_all_ai_game(4, SEED))
	_layer.add_child(aibtn)

	var restbtn := _mk_button("REST")
	restbtn.position = Vector2(1060, 122)
	restbtn.pressed.connect(func() -> void: GameManager.submit_action({"type": "REST"}))
	_layer.add_child(restbtn)

	_build_handoff_overlay()


func _build_handoff_overlay() -> void:
	_handoff_overlay = Control.new()
	_handoff_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handoff_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_handoff_overlay.visible = false
	_layer.add_child(_handoff_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.04, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_handoff_overlay.add_child(dim)

	var card := ColorRect.new()
	card.color = Color(0.13, 0.18, 0.15)
	card.position = Vector2(390, 250)
	card.custom_minimum_size = Vector2(500, 220)
	card.size = Vector2(500, 220)
	_handoff_overlay.add_child(card)

	var title := Label.new()
	title.text = "PASS THE DEVICE"
	title.position = Vector2(420, 285)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.86, 0.92, 0.66))
	title.add_to_group(&"scalable_text")
	_handoff_overlay.add_child(title)

	_handoff_label = Label.new()
	_handoff_label.text = "Next explorer's turn"
	_handoff_label.position = Vector2(420, 335)
	_handoff_label.add_theme_font_size_override("font_size", 18)
	_handoff_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.88))
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


func _mk_row(pos: Vector2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.position = pos
	h.add_theme_constant_override("separation", 6)
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
	var e: WildlifeEngine = GameManager.engine
	if e == null or e.players.is_empty():
		return
	if e.game_over:
		var w := e.winner
		_status.text = "EXPEDITION COMPLETE — Winner: %s with %d pts" % [
			e.seat_name(w), int(e.final_scores[w]["total"])]
	elif GameManager.pending_handoff:
		_status.text = "Pass the device — %s's turn   ·   Season %d/%d" % [
			e.seat_name(e.current), e.season + 1, WildlifeEngine.NUM_SEASONS]
	else:
		var who: String
		if e.is_human_seat(e.current):
			who = "%s — YOUR TURN" % e.seat_name(e.current)
		else:
			who = "%s (AI) exploring…" % e.seat_name(e.current)
		_status.text = "%s   ·   Season %d/%d   ·   round %d/%d" % [
			who, e.season + 1, WildlifeEngine.NUM_SEASONS, e.season_round + 1, WildlifeEngine.SEASON_ROUND_CAP]
	if _handoff_overlay != null:
		_handoff_overlay.visible = GameManager.pending_handoff and not e.game_over
		if _handoff_overlay.visible and _handoff_label != null:
			_handoff_label.text = "%s — take the seat, then press Ready." % e.seat_name(e.current)
	_rebuild_trail(e)
	_rebuild_moves(e)
	_rebuild_offer(e)
	_rebuild_hand(e)
	_rebuild_gear(e)
	_rebuild_panels(e)
	_rebuild_track(e)
	_rebuild_log(e)


func _rebuild_trail(e: WildlifeEngine) -> void:
	_clear(_trail_row)
	for idx in e.trail.size():
		var site: Dictionary = e.trail[idx]
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(118, 66)
		var frame := ColorRect.new()
		frame.custom_minimum_size = Vector2(118, 22)
		frame.color = BIOME_COLOR.get(String(site["biome"]), Color(0.4, 0.4, 0.4))
		box.add_child(frame)
		var name_l := Label.new()
		name_l.text = "%d %s" % [idx, site["name"]]
		name_l.add_theme_font_size_override("font_size", 10)
		name_l.add_theme_color_override("font_color", Color(0.92, 0.94, 0.88))
		name_l.add_to_group(&"scalable_text")
		box.add_child(name_l)
		var yl := Label.new()
		yl.text = "%s%s" % [e._fmt(site["yield"]),
			("  +%s" % site["bonus"]) if String(site["bonus"]) != "none" else ""]
		yl.add_theme_font_size_override("font_size", 9)
		yl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.76))
		yl.add_to_group(&"scalable_text")
		box.add_child(yl)
		# Pawn markers on this site.
		var pawns := ""
		for pi in e.players.size():
			for pawn_pos in e.players[pi]["pawns"]:
				if int(pawn_pos) == idx:
					pawns += "P%d " % (pi + 1)
		var pl := Label.new()
		pl.text = pawns
		pl.add_theme_font_size_override("font_size", 10)
		pl.add_theme_color_override("font_color", Color(0.94, 0.86, 0.50))
		pl.add_to_group(&"scalable_text")
		box.add_child(pl)
		_trail_row.add_child(box)


func _rebuild_moves(e: WildlifeEngine) -> void:
	_clear(_move_row)
	var seat := e.current
	var can := GameManager.can_accept_input()
	if not can:
		return
	var shown := 0
	for action in e.legal_actions(seat):
		if String(action["type"]) != "MOVE":
			continue
		if shown >= 12:
			break
		var to := int(action["to"])
		var site: Dictionary = e.trail[to]
		var b := _mk_button("P%d → %s\n%s" % [int(action["pawn"]) + 1, site["name"], e._fmt(site["yield"])])
		b.custom_minimum_size = Vector2(120, 40)
		var a: Dictionary = action
		b.pressed.connect(func() -> void: GameManager.submit_action(a))
		_move_row.add_child(b)
		shown += 1


func _rebuild_offer(e: WildlifeEngine) -> void:
	_clear(_offer_row)
	var seat := e.current
	var can := GameManager.can_accept_input()
	for i in e.offer.size():
		var id := String(e.offer[i])
		if id == "":
			continue
		var species: Dictionary = WildlifeEngine.SPECIES_DB[id]
		var b := _species_button(e, species, seat,
			{"type": "DOCUMENT", "source": "offer", "index": i}, can)
		_offer_row.add_child(b)


func _rebuild_hand(e: WildlifeEngine) -> void:
	_clear(_hand_row)
	var seat := e.current
	if seat < 0 or seat >= e.players.size():
		return
	var can := GameManager.can_accept_input()
	var hand: Array = e.players[seat]["hand"]
	for i in hand.size():
		var species: Dictionary = WildlifeEngine.SPECIES_DB[hand[i]]
		var b := _species_button(e, species, seat,
			{"type": "DOCUMENT", "source": "hand", "index": i}, can)
		_hand_row.add_child(b)


func _species_button(e: WildlifeEngine, species: Dictionary, seat: int, action: Dictionary, can: bool) -> Button:
	var b := _mk_button("%s\n%s·%s  %dpt\ncost %s" % [
		species["name"], species["category"], species["biome"], int(species["points"]),
		e._fmt(species["cost"])])
	b.custom_minimum_size = Vector2(140, 62)
	b.modulate = CAT_COLOR.get(String(species["category"]), Color.WHITE)
	b.disabled = not (can and e.is_legal(seat, action))
	var a := action
	b.pressed.connect(func() -> void: GameManager.submit_action(a))
	return b


func _rebuild_gear(e: WildlifeEngine) -> void:
	_clear(_gear_row)
	var seat := e.current
	var can := GameManager.can_accept_input()
	for i in e.gear_shop.size():
		var id := String(e.gear_shop[i])
		if id == "":
			continue
		var gear: Dictionary = WildlifeEngine.GEAR_DB[id]
		var b := _mk_button("%s\n%dpt · %s\ncost %s" % [
			gear["name"], int(gear["points"]), gear["perk"], e._fmt(gear["cost"])])
		b.custom_minimum_size = Vector2(130, 62)
		b.disabled = not (can and e.is_legal(seat, {"type": "DEVELOP", "index": i}))
		var idx := i
		b.pressed.connect(func() -> void: GameManager.submit_action({"type": "DEVELOP", "index": idx}))
		_gear_row.add_child(b)


func _rebuild_panels(e: WildlifeEngine) -> void:
	_clear(_panels_row)
	for pi in e.players.size():
		_panels_row.add_child(_player_panel(e, pi))


func _player_panel(e: WildlifeEngine, pi: int) -> Control:
	var p: Dictionary = e.players[pi]
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(258, 176)
	box.add_theme_constant_override("separation", 1)

	var frame := ColorRect.new()
	frame.custom_minimum_size = Vector2(258, 20)
	frame.color = Color(0.13, 0.17, 0.15) if pi != e.current else Color(0.20, 0.26, 0.16)
	box.add_child(frame)

	var kind_tag := "HUMAN" if e.is_human_seat(pi) else "AI"
	var head := Label.new()
	head.text = "%s [%s]%s" % [e.seat_name(pi), kind_tag,
		"  ◄ turn" if pi == e.current and not e.game_over else ""]
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", Color(0.90, 0.94, 0.68))
	head.add_to_group(&"scalable_text")
	box.add_child(head)

	var sc := Label.new()
	sc.text = "score %d   ·   goals %d   ·   pawns %s%s" % [
		e.live_score(pi), int(p["goal_points"]), str(p["pawns"]),
		"  DONE" if bool(p["finished"]) else ""]
	sc.add_theme_font_size_override("font_size", 12)
	sc.add_theme_color_override("font_color", Color(0.84, 0.88, 0.90))
	sc.add_to_group(&"scalable_text")
	box.add_child(sc)

	var res := Label.new()
	var parts: Array[String] = []
	for r in WildlifeEngine.RESOURCES:
		parts.append("%s%d" % [r.substr(0, 2), int(p["resources"][r])])
	res.text = " ".join(parts)
	res.add_theme_font_size_override("font_size", 11)
	res.add_theme_color_override("font_color", Color(0.76, 0.82, 0.78))
	res.add_to_group(&"scalable_text")
	box.add_child(res)

	var jhead := Label.new()
	jhead.text = "JOURNAL (%d):" % (p["journal"] as Array).size()
	jhead.add_theme_font_size_override("font_size", 11)
	jhead.add_theme_color_override("font_color", Color(0.70, 0.80, 0.72))
	jhead.add_to_group(&"scalable_text")
	box.add_child(jhead)

	for jid in p["journal"]:
		var species: Dictionary = WildlifeEngine.SPECIES_DB[jid]
		var row := Label.new()
		row.text = "  • %s (%s)" % [species["name"], species["category"]]
		row.add_theme_font_size_override("font_size", 10)
		row.add_theme_color_override("font_color", CAT_COLOR.get(String(species["category"]), Color.WHITE))
		row.add_to_group(&"scalable_text")
		box.add_child(row)

	for gid in p["gear"]:
		var gear: Dictionary = WildlifeEngine.GEAR_DB[gid]
		var grow := Label.new()
		grow.text = "  ⚙ %s" % gear["name"]
		grow.add_theme_font_size_override("font_size", 10)
		grow.add_theme_color_override("font_color", Color(0.78, 0.76, 0.60))
		grow.add_to_group(&"scalable_text")
		box.add_child(grow)

	return box


func _rebuild_track(e: WildlifeEngine) -> void:
	var goal: Dictionary = e.active_goal()
	var exp_parts: Array[String] = []
	for exp in WildlifeEngine.EXPEDITION_DB:
		exp_parts.append("%s(+%d)" % [exp["name"], int(exp["bonus"])])
	_track.text = "SEASON %d/%d GOAL: %s (+%d)   |   EXPEDITIONS: %s" % [
		e.season + 1, WildlifeEngine.NUM_SEASONS, goal["name"], WildlifeEngine.GOAL_FIRST,
		"  ·  ".join(exp_parts)]


func _rebuild_log(e: WildlifeEngine) -> void:
	_clear(_log_box)
	for line in e.recent_log(4):
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(0.68, 0.74, 0.70))
		l.add_to_group(&"scalable_text")
		_log_box.add_child(l)


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
