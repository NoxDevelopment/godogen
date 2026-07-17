extends Node2D
## res://scripts/srpg_view.gd
## The playable tactics-SRPG view — renders GameManager's SrpgEngine (terrain, units, HP,
## the selected unit's move-range + attackable enemies) and turns clicks into commands
## during the PLAYER phase. Classic 2-click flow: click your unit to select (its reachable
## tiles light up blue, enemies it can hit ring red), click a lit tile to move, then click
## an in-range enemy to attack (or an ally to heal, if a healer is selected). Enter ends
## the phase · W waits · A auto-plays · R restarts. All rules live in SrpgEngine.

const CELL := 40
const ORIGIN := Vector2(24, 72)
const TEAM_COLOR := [Color(0.40, 0.66, 1.0), Color(1.0, 0.46, 0.42)]
const TERRAIN_COLOR := {
	0: Color(0.30, 0.42, 0.26),   # plain
	1: Color(0.14, 0.34, 0.18),   # forest
	2: Color(0.46, 0.40, 0.30),   # hill
	3: Color(0.32, 0.34, 0.52),   # fort
	4: Color(0.20, 0.20, 0.22),   # wall
}
const CLASS_GLYPH := {"soldier": "S", "fighter": "F", "knight": "K", "archer": "A", "healer": "H"}

var eng: SrpgEngine
var sel := 0
var reach_tiles: Array = []
var target_ids: Array = []

func _ready() -> void:
	eng = GameManager.engine
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if eng == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(_screen_to_grid(event.position))
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_SPACE:
				GameManager.player_end_phase()
				_deselect()
			KEY_W:
				if sel != 0:
					eng.wait(sel)
					_deselect()
			KEY_A:
				GameManager.player_auto = not GameManager.player_auto
				if GameManager.player_auto:
					GameManager.auto_phase()
				_deselect()
			KEY_R:
				GameManager.new_battle()
				eng = GameManager.engine
				_deselect()
		queue_redraw()

func _screen_to_grid(p: Vector2) -> Vector2i:
	return Vector2i(int((p.x - ORIGIN.x) / CELL), int((p.y - ORIGIN.y) / CELL))

func _on_click(g: Vector2i) -> void:
	if eng.game_over or eng.current_team != SrpgEngine.TEAM_PLAYER or GameManager.player_auto:
		return
	if not eng.in_bounds(g.x, g.y):
		_deselect()
		return
	var u := eng._unit_at(g.x, g.y)
	# selecting one of your un-acted units
	if not u.is_empty() and int(u.team) == SrpgEngine.TEAM_PLAYER and not u.acted and int(u.id) != sel:
		_select(int(u.id))
		return
	if sel == 0:
		return
	var su := eng.unit_by_id(sel)
	if su.is_empty():
		_deselect()
		return
	# click an enemy in range → attack;  a wounded ally in range (healer) → heal
	if not u.is_empty():
		if int(u.team) != SrpgEngine.TEAM_PLAYER and int(u.id) in target_ids:
			eng.attack(sel, int(u.id))
			_deselect()
			return
		if str(su.cls) == "healer" and int(u.team) == SrpgEngine.TEAM_PLAYER and int(u.id) in target_ids:
			eng.heal(sel, int(u.id))
			_deselect()
			return
	# click a reachable tile → move there and refresh targets (stay selected)
	for t in reach_tiles:
		if t.x == g.x and t.y == g.y:
			eng.move_unit(sel, g.x, g.y)
			_refresh_targets()
			return
	_deselect()

func _select(id: int) -> void:
	sel = id
	var u := eng.unit_by_id(id)
	reach_tiles = eng.stand_tiles(u) if not u.is_empty() else []
	_refresh_targets()

func _refresh_targets() -> void:
	target_ids = []
	var u := eng.unit_by_id(sel)
	if u.is_empty():
		return
	if str(u.cls) == "healer":
		for a in eng.units_of(SrpgEngine.TEAM_PLAYER):
			if int(a.id) != sel and int(a.hp) < int(a.max_hp) and eng._man(int(u.x), int(u.y), int(a.x), int(a.y)) <= int(u.rng):
				target_ids.append(int(a.id))
	else:
		for e in eng.units_of(SrpgEngine.TEAM_ENEMY):
			if eng._man(int(u.x), int(u.y), int(e.x), int(e.y)) <= int(u.rng):
				target_ids.append(int(e.id))

func _deselect() -> void:
	sel = 0
	reach_tiles = []
	target_ids = []

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	for y in range(SrpgEngine.H):
		for x in range(SrpgEngine.W):
			var pos := ORIGIN + Vector2(x * CELL, y * CELL)
			draw_rect(Rect2(pos, Vector2(CELL - 1, CELL - 1)), TERRAIN_COLOR[eng.tile(x, y)])
	# move-range overlay
	for t in reach_tiles:
		draw_rect(Rect2(ORIGIN + Vector2(t.x * CELL, t.y * CELL), Vector2(CELL - 1, CELL - 1)), Color(0.4, 0.6, 1.0, 0.28))
	# units
	for u in eng.units:
		var pos := ORIGIN + Vector2(int(u.x) * CELL, int(u.y) * CELL)
		var col: Color = TEAM_COLOR[int(u.team)]
		if bool(u.acted) and int(u.team) == SrpgEngine.TEAM_PLAYER:
			col = col.darkened(0.4)
		draw_rect(Rect2(pos + Vector2(4, 4), Vector2(CELL - 9, CELL - 9)), col)
		draw_string(font, pos + Vector2(13, CELL - 13), str(CLASS_GLYPH.get(str(u.cls), "?")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)
		_hp_bar(pos, int(u.hp), int(u.max_hp))
		if int(u.id) in target_ids:
			draw_rect(Rect2(pos + Vector2(1, 1), Vector2(CELL - 3, CELL - 3)), Color(1, 0.3, 0.3), false, 2.5)
		if int(u.id) == sel:
			draw_rect(Rect2(pos + Vector2(1, 1), Vector2(CELL - 3, CELL - 3)), Color(1, 1, 0.3), false, 2.5)
	_draw_hud(font)

func _hp_bar(pos: Vector2, hp: int, mx: int) -> void:
	if mx <= 0:
		return
	var f: float = clampf(float(hp) / float(mx), 0.0, 1.0)
	draw_rect(Rect2(pos + Vector2(4, CELL - 7), Vector2(CELL - 8, 3)), Color(0.15, 0.05, 0.05))
	draw_rect(Rect2(pos + Vector2(4, CELL - 7), Vector2((CELL - 8) * f, 3)), Color(0.3, 0.9, 0.3))

func _draw_hud(font: Font) -> void:
	var phase := "YOUR PHASE" if eng.current_team == SrpgEngine.TEAM_PLAYER else "ENEMY PHASE"
	if GameManager.player_auto:
		phase = "AUTO"
	var line := "Round %d   %s   YOU %d units   ENEMY %d units" % [
		eng.round_no, phase, eng.units_of(0).size(), eng.units_of(1).size()]
	draw_string(font, Vector2(24, 28), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_string(font, Vector2(24, 50),
		"Click a unit → blue = move, red-ring = target. Click a lit tile to move, then an enemy to attack. Enter end phase · W wait · A auto · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.72, 0.75))
	if sel != 0:
		var u := eng.unit_by_id(sel)
		if not u.is_empty():
			draw_string(font, Vector2(24, ORIGIN.y + SrpgEngine.H * CELL + 18),
				"%s [%s]  HP %d/%d · ATK %d · DEF %d · SPD %d · MOV %d · RNG %d" % [
					str(u.cls), str(u.weapon), int(u.hp), int(u.max_hp), int(u.atk),
					int(u.def), int(u.spd), int(u.move), int(u.rng)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.6))
	if eng.game_over:
		var msg := "VICTORY" if eng.winner == SrpgEngine.TEAM_PLAYER else ("DEFEAT" if eng.winner == SrpgEngine.TEAM_ENEMY else "DRAW")
		draw_string(font, Vector2(24, ORIGIN.y + SrpgEngine.H * CELL + 40), "%s — press R" % msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.4))
