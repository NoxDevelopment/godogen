extends Node2D
## res://scripts/tbs_view.gd
## The playable turn-based 4X view — renders GameManager's TbsEngine (terrain under the
## player's fog of war, team-coloured cities + units, selection) and turns clicks/keys into
## engine commands during the PLAYER's turn. All rules live in TbsEngine; this is
## presentation + input only. Left-click: select your unit/city, or move/attack with a
## selected unit. Keys: Enter/Space end turn · F found city (settler) · 1-6 set the
## selected city's build · Tab cycle units · A auto-play · R restart.

const CELL := 26
const ORIGIN := Vector2(20, 84)
const TERRAIN_COLOR := {
	0: Color(0.10, 0.20, 0.42),   # ocean
	1: Color(0.55, 0.60, 0.32),   # plains
	2: Color(0.34, 0.56, 0.28),   # grass
	3: Color(0.18, 0.42, 0.24),   # forest
	4: Color(0.50, 0.44, 0.34),   # hill
	5: Color(0.42, 0.40, 0.40),   # mountain
}
const TEAM_COLOR := [Color(0.40, 0.68, 1.0), Color(1.0, 0.48, 0.42)]
const BUILD_KEYS := ["warrior", "settler", "spearman", "granary", "library", "walls"]

var eng: TbsEngine
var sel_unit := 0
var sel_city := 0

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
		_on_key(event.keycode)
		queue_redraw()

func _screen_to_grid(p: Vector2) -> Vector2i:
	return Vector2i(int((p.x - ORIGIN.x) / CELL), int((p.y - ORIGIN.y) / CELL))

func _on_click(g: Vector2i) -> void:
	if not eng.in_bounds(g.x, g.y) or eng.game_over:
		return
	if eng.current != TbsEngine.CIV_PLAYER or GameManager.player_auto:
		return
	# select own unit / city
	var u := eng._unit_at(g.x, g.y)
	var c := eng._city_at(g.x, g.y)
	if not u.is_empty() and int(u.owner) == TbsEngine.CIV_PLAYER:
		sel_unit = int(u.id)
		sel_city = 0
		return
	if not c.is_empty() and int(c.owner) == TbsEngine.CIV_PLAYER:
		sel_city = int(c.id)
		sel_unit = 0
		return
	# with a unit selected: attack adjacent enemy, else move toward the tile
	if sel_unit != 0:
		var su := eng.unit_by_id(sel_unit)
		if su.is_empty():
			sel_unit = 0
			return
		var enemy_u := eng._unit_at(g.x, g.y)
		var enemy_c := eng._city_at(g.x, g.y)
		var is_enemy := (not enemy_u.is_empty() and int(enemy_u.owner) != TbsEngine.CIV_PLAYER) \
			or (not enemy_c.is_empty() and int(enemy_c.owner) != TbsEngine.CIV_PLAYER)
		if is_enemy and eng._cheb(int(su.x), int(su.y), g.x, g.y) == 1:
			eng.attack(sel_unit, g.x, g.y)
		else:
			eng.move_unit(sel_unit, g.x, g.y)

func _on_key(k: int) -> void:
	match k:
		KEY_ENTER, KEY_SPACE:
			GameManager.player_end_turn()
			sel_unit = 0
			sel_city = 0
		KEY_F:
			if sel_unit != 0:
				eng.found_city(sel_unit)
				sel_unit = 0
		KEY_TAB:
			_cycle_unit()
		KEY_A:
			GameManager.player_auto = not GameManager.player_auto
			if GameManager.player_auto:
				GameManager.auto_round()
		KEY_R:
			GameManager.new_game()
			eng = GameManager.engine
			sel_unit = 0
			sel_city = 0
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			if sel_city != 0:
				var idx := k - KEY_1
				if idx < BUILD_KEYS.size():
					eng.set_city_build(sel_city, BUILD_KEYS[idx])

func _cycle_unit() -> void:
	var own := eng.units_of(TbsEngine.CIV_PLAYER)
	if own.is_empty():
		return
	var start := 0
	for i in range(own.size()):
		if int(own[i].id) == sel_unit:
			start = i + 1
			break
	sel_unit = int(own[start % own.size()].id)
	sel_city = 0

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# terrain under the player's fog
	for y in range(TbsEngine.H):
		for x in range(TbsEngine.W):
			var pos := ORIGIN + Vector2(x * CELL, y * CELL)
			var seen := eng.is_seen(TbsEngine.CIV_PLAYER, x, y)
			var col: Color = TERRAIN_COLOR[eng.tile(x, y)] if seen else Color(0.05, 0.05, 0.07)
			draw_rect(Rect2(pos, Vector2(CELL - 1, CELL - 1)), col)
	# cities
	for c in eng.cities:
		if not eng.is_seen(TbsEngine.CIV_PLAYER, int(c.x), int(c.y)):
			continue
		var pos := ORIGIN + Vector2(int(c.x) * CELL, int(c.y) * CELL)
		draw_rect(Rect2(pos, Vector2(CELL - 1, CELL - 1)), TEAM_COLOR[int(c.owner)])
		draw_rect(Rect2(pos, Vector2(CELL - 1, CELL - 1)), Color.BLACK, false, 2.0)
		draw_string(font, pos + Vector2(4, CELL - 6), str(int(c.pop)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
		_bar(pos, int(c.hp), int(c.max_hp), Color(0.9, 0.3, 0.3))
		if int(c.id) == sel_city:
			draw_rect(Rect2(pos, Vector2(CELL - 1, CELL - 1)), Color(1, 1, 0.3), false, 2.5)
	# units
	for u in eng.units:
		if not eng.is_seen(TbsEngine.CIV_PLAYER, int(u.x), int(u.y)):
			continue
		var ctr := ORIGIN + Vector2(int(u.x) * CELL + CELL / 2, int(u.y) * CELL + CELL / 2)
		var col: Color = TEAM_COLOR[int(u.owner)]
		match str(u.kind):
			"settler": draw_circle(ctr, CELL * 0.24, col.lightened(0.3))
			"warrior": draw_rect(Rect2(ctr - Vector2(CELL * 0.24, CELL * 0.24), Vector2(CELL * 0.48, CELL * 0.48)), col)
			_: # spearman etc.
				draw_rect(Rect2(ctr - Vector2(CELL * 0.26, CELL * 0.26), Vector2(CELL * 0.52, CELL * 0.52)), col.darkened(0.15))
		if int(u.hp) < int(u.max_hp):
			_bar(ORIGIN + Vector2(int(u.x) * CELL, int(u.y) * CELL), int(u.hp), int(u.max_hp), Color(0.3, 0.9, 0.3))
		if int(u.id) == sel_unit:
			draw_circle(ctr, CELL * 0.4, Color(1, 1, 0.3, 0.9), false, 2.0)
	_draw_hud(font)

func _bar(pos: Vector2, v: int, mx: int, col: Color) -> void:
	if mx <= 0:
		return
	var f: float = clampf(float(v) / float(mx), 0.0, 1.0)
	draw_rect(Rect2(pos + Vector2(1, -3), Vector2(CELL - 3, 2)), Color(0.15, 0.05, 0.05))
	draw_rect(Rect2(pos + Vector2(1, -3), Vector2((CELL - 3) * f, 2)), col)

func _draw_hud(font: Font) -> void:
	var civ := eng.current
	var researching := str(eng.civ_research[TbsEngine.CIV_PLAYER])
	var line := "Turn %d   %s   YOU: cities %d · sci %d · gold %d · tech %d (%s)   ENEMY: cities %d" % [
		eng.turn,
		("AUTO" if GameManager.player_auto else ("YOUR TURN" if civ == TbsEngine.CIV_PLAYER else "AI TURN")),
		eng.cities_of(TbsEngine.CIV_PLAYER).size(), int(eng.civ_science[0]), int(eng.civ_gold[0]),
		eng.civ_techs[0].size(), researching,
		eng.cities_of(TbsEngine.CIV_AI).size()]
	draw_string(font, Vector2(20, 26), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	var help := "Click select/move · click adjacent enemy to attack · Enter end turn · F found · 1-6 city build · Tab cycle · A auto · R restart"
	draw_string(font, Vector2(20, 46), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.72, 0.75))
	if sel_city != 0:
		var c := eng.city_by_id(sel_city)
		if not c.is_empty():
			draw_string(font, Vector2(20, 66),
				"%s — pop %d · building %s (1 warrior 2 settler 3 spearman 4 granary 5 library 6 walls)" % [c.name, int(c.pop), str(c.build)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.6))
	elif sel_unit != 0:
		var u := eng.unit_by_id(sel_unit)
		if not u.is_empty():
			draw_string(font, Vector2(20, 66), "%s — hp %d · moves %d/%d" % [str(u.kind), int(u.hp), int(u.moves_left), int(u.moves)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.6))
	if eng.game_over:
		var msg := "VICTORY" if eng.winner == TbsEngine.CIV_PLAYER else ("DEFEAT" if eng.winner == TbsEngine.CIV_AI else "DRAW")
		draw_string(font, Vector2(20, ORIGIN.y + TbsEngine.H * CELL + 24), "%s — press R" % msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.4))
