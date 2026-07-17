extends Node2D
## res://scripts/rts_view.gd
## The playable RTS view — steps GameManager's RtsEngine on a fixed real-time cadence and
## renders the board (mineral patches, team-coloured buildings + units, HP bars, a live
## HUD). All rules live in RtsEngine; this is presentation + input only. Selection is a
## left-drag box over your own units; right-click issues a context command (gather a patch,
## attack an enemy, else move/attack-move). Keys: Q train worker · E train soldier ·
## B build barracks (with a selected worker) · Space pause · F let the AI play your side ·
## [ / ] sim speed · R restart.

const CELL := 16
const ORIGIN := Vector2(20, 64)

var eng: RtsEngine
var selected: Array = []          ## selected own-unit ids
var dragging := false
var drag_start := Vector2.ZERO
var drag_now := Vector2.ZERO
var paused := false
var ticks_per_frame := 1          ## sim speed
var _accum := 0.0

const TEAM_COLOR := [Color(0.35, 0.65, 1.0), Color(1.0, 0.45, 0.40)]   # player, AI

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null or paused or eng.game_over:
		queue_redraw()
		return
	for _i in range(ticks_per_frame):
		GameManager.advance()
		if eng.game_over:
			break
	queue_redraw()

# --------------------------------------------------------------------------- #
# Input
# --------------------------------------------------------------------------- #

func _unhandled_input(event: InputEvent) -> void:
	if eng == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_start = event.position
				drag_now = event.position
			else:
				dragging = false
				_finish_box_select()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_issue_context_command(_screen_to_grid(event.position))
	elif event is InputEventMouseMotion and dragging:
		drag_now = event.position
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: paused = not paused
			KEY_F: GameManager.player_auto = not GameManager.player_auto
			KEY_R: _restart()
			KEY_Q: _train_from_townhall("worker")
			KEY_E: _train_from_barracks("soldier")
			KEY_B: _build_barracks()
			KEY_BRACKETLEFT: ticks_per_frame = max(1, ticks_per_frame - 1)
			KEY_BRACKETRIGHT: ticks_per_frame = min(16, ticks_per_frame + 1)

func _screen_to_grid(p: Vector2) -> Vector2i:
	return Vector2i(int((p.x - ORIGIN.x) / CELL), int((p.y - ORIGIN.y) / CELL))

func _finish_box_select() -> void:
	var r := Rect2(drag_start, drag_now - drag_start).abs()
	selected.clear()
	# a click (tiny box) selects the single nearest own unit; a real drag selects all inside
	if r.size.length() < 6:
		var g := _screen_to_grid(drag_start)
		var best := 0
		var bd := 1 << 30
		for u in eng.units_of(RtsEngine.OWNER_PLAYER):
			var d: int = abs(int(u.x) - g.x) + abs(int(u.y) - g.y)
			if d < bd:
				bd = d
				best = int(u.id)
		if best != 0 and bd <= 2:
			selected.append(best)
	else:
		for u in eng.units_of(RtsEngine.OWNER_PLAYER):
			var sp := ORIGIN + Vector2(int(u.x) * CELL + CELL / 2, int(u.y) * CELL + CELL / 2)
			if r.has_point(sp):
				selected.append(int(u.id))

func _issue_context_command(g: Vector2i) -> void:
	if selected.is_empty():
		return
	# enemy unit/building under the cursor → attack
	var enemy_id := _entity_at(g, 1 - 0, true)
	if enemy_id != 0:
		for id in selected:
			eng.cmd_attack(id, enemy_id)
		return
	# mineral patch → gather (workers only)
	var pid := _patch_at(g)
	if pid != 0:
		for id in selected:
			var u := eng.unit_by_id(id)
			if not u.is_empty() and u.kind == "worker":
				eng.cmd_gather(id, pid)
		return
	# else: attack-move soldiers, plain move workers
	for id in selected:
		var u := eng.unit_by_id(id)
		if u.is_empty():
			continue
		if u.kind == "soldier":
			eng.cmd_attack_move(id, g.x, g.y)
		else:
			eng.cmd_move(id, g.x, g.y)

func _entity_at(g: Vector2i, owner: int, enemy_of_player: bool) -> int:
	var want_owner := RtsEngine.OWNER_AI if enemy_of_player else owner
	for u in eng.units:
		if int(u.owner) == want_owner and int(u.x) == g.x and int(u.y) == g.y:
			return int(u.id)
	for b in eng.buildings:
		if int(b.owner) == want_owner and int(b.x) == g.x and int(b.y) == g.y:
			return int(b.id)
	return 0

func _patch_at(g: Vector2i) -> int:
	for p in eng.patches:
		if int(p.x) == g.x and int(p.y) == g.y and int(p.amount) > 0:
			return int(p.id)
	return 0

func _train_from_townhall(kind: String) -> void:
	for b in eng.buildings_of(RtsEngine.OWNER_PLAYER):
		if b.kind == "townhall":
			eng.cmd_train(int(b.id), kind)
			return

func _train_from_barracks(kind: String) -> void:
	for b in eng.buildings_of(RtsEngine.OWNER_PLAYER):
		if b.kind == "barracks" and b.complete:
			eng.cmd_train(int(b.id), kind)
			return

func _build_barracks() -> void:
	for id in selected:
		var u := eng.unit_by_id(id)
		if not u.is_empty() and u.kind == "worker":
			var hall := eng._townhall_of(RtsEngine.OWNER_PLAYER)
			if not hall.is_empty():
				eng.cmd_build(id, "barracks", int(hall.x) + 3, int(hall.y) + 4)
			return

func _restart() -> void:
	GameManager.new_match()
	eng = GameManager.engine
	selected.clear()
	paused = false

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	# board background
	draw_rect(Rect2(ORIGIN, Vector2(RtsEngine.W * CELL, RtsEngine.H * CELL)), Color(0.12, 0.14, 0.12))
	# mineral patches
	for p in eng.patches:
		if int(p.amount) <= 0:
			continue
		var frac: float = clampf(float(p.amount) / float(RtsEngine.PATCH_AMOUNT), 0.15, 1.0)
		draw_rect(Rect2(ORIGIN + Vector2(int(p.x) * CELL, int(p.y) * CELL),
			Vector2(CELL - 1, CELL - 1)), Color(0.25, 0.75, 0.90, frac))
	# buildings
	for b in eng.buildings:
		var col: Color = TEAM_COLOR[int(b.owner)]
		if not b.complete:
			col = col.darkened(0.5)
		var sz: int = CELL + 6 if b.kind == "townhall" else CELL + 2
		var pos := ORIGIN + Vector2(int(b.x) * CELL - (sz - CELL) / 2, int(b.y) * CELL - (sz - CELL) / 2)
		draw_rect(Rect2(pos, Vector2(sz, sz)), col)
		draw_rect(Rect2(pos, Vector2(sz, sz)), Color.BLACK, false, 1.0)
		_hp_bar(int(b.x), int(b.y), int(b.hp), int(b.max_hp), sz)
	# units
	for u in eng.units:
		var col: Color = TEAM_COLOR[int(u.owner)]
		var c := ORIGIN + Vector2(int(u.x) * CELL + CELL / 2, int(u.y) * CELL + CELL / 2)
		if u.kind == "worker":
			draw_circle(c, CELL * 0.32, col)
		else:
			draw_rect(Rect2(c - Vector2(CELL * 0.34, CELL * 0.34), Vector2(CELL * 0.68, CELL * 0.68)), col)
		if int(u.owner) == RtsEngine.OWNER_PLAYER and int(u.id) in selected:
			draw_circle(c, CELL * 0.5, Color(1, 1, 0.3, 0.9), false, 1.5)
		if int(u.hp) < int(u.max_hp):
			_hp_bar(int(u.x), int(u.y), int(u.hp), int(u.max_hp), CELL)
	# drag box
	if dragging:
		var r := Rect2(drag_start, drag_now - drag_start).abs()
		draw_rect(r, Color(1, 1, 0.4, 0.15))
		draw_rect(r, Color(1, 1, 0.4, 0.7), false, 1.0)
	_draw_hud()

func _hp_bar(gx: int, gy: int, hp: int, max_hp: int, sz: int) -> void:
	if max_hp <= 0:
		return
	var w: float = float(sz)
	var frac: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var base := ORIGIN + Vector2(gx * CELL + (CELL - sz) / 2.0, gy * CELL - 4)
	draw_rect(Rect2(base, Vector2(w, 2)), Color(0.2, 0.05, 0.05))
	draw_rect(Rect2(base, Vector2(w * frac, 2)), Color(0.3, 0.9, 0.3))

func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var y := 24.0
	var p_workers := eng.count_kind(RtsEngine.OWNER_PLAYER, "worker")
	var p_army := eng.count_kind(RtsEngine.OWNER_PLAYER, "soldier")
	var a_workers := eng.count_kind(RtsEngine.OWNER_AI, "worker")
	var a_army := eng.count_kind(RtsEngine.OWNER_AI, "soldier")
	var hud := "t%d  x%d%s   YOU  min %d · wrk %d · army %d      ENEMY  min %d · wrk %d · army %d" % [
		eng.tick, ticks_per_frame, ("  [PAUSED]" if paused else ("  [AUTO]" if GameManager.player_auto else "")),
		int(eng.minerals[0]), p_workers, p_army, int(eng.minerals[1]), a_workers, a_army]
	draw_string(font, Vector2(20, y), hud, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(font, Vector2(20, 44),
		"L-drag select · R-click command · Q worker · E soldier · B barracks · Space pause · F auto · [ ] speed · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.72, 0.75))
	if eng.game_over:
		var msg := "VICTORY" if eng.winner == RtsEngine.OWNER_PLAYER else ("DEFEAT" if eng.winner == RtsEngine.OWNER_AI else "DRAW")
		draw_string(font, Vector2(20, ORIGIN.y + RtsEngine.H * CELL + 22),
			"%s — press R" % msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.4))
