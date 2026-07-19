extends Node2D
## res://scripts/dungeon.gd
## The playable roguelike view — renders GameManager.engine's grid + entities and
## turns keyboard input into engine turns. All rules live in RogueEngine; this is
## presentation + input only (the pure-engine ABI). Movement: arrows / WASD; wait:
## space; quaff a potion: Q; descend on stairs: > (or walk onto them). Permadeath:
## R starts a fresh seeded run.

const CELL := 24
const ORIGIN := Vector2(24, 56)

var eng: RogueEngine

func _ready() -> void:
	eng = GameManager.engine
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if eng == null:
		return
	var k: int = event.keycode
	if eng.game_over:
		if k == KEY_R:
			GameManager.new_run()
			eng = GameManager.engine
			queue_redraw()
		return
	var action := ""
	match k:
		KEY_UP, KEY_W: action = "up"
		KEY_DOWN, KEY_S: action = "down"
		KEY_LEFT, KEY_A: action = "left"
		KEY_RIGHT, KEY_D: action = "right"
		KEY_SPACE: action = "wait"
		KEY_Q: action = "quaff"
		KEY_PERIOD, KEY_GREATER: action = "descend"
		KEY_R:
			GameManager.new_run()
			eng = GameManager.engine
			queue_redraw()
			return
	if action != "":
		eng.step(action)
		queue_redraw()

func _draw() -> void:
	if eng == null:
		return
	# terrain
	for y in range(RogueEngine.H):
		for x in range(RogueEngine.W):
			if eng.seen[y * RogueEngine.W + x] == 0:
				continue
			var t: int = eng.tile(x, y)
			var col := Color(0.10, 0.10, 0.13)
			if t == RogueEngine.FLOOR:
				col = Color(0.24, 0.24, 0.30)
			elif t == RogueEngine.STAIRS:
				col = Color(0.85, 0.75, 0.30)
			draw_rect(Rect2(ORIGIN + Vector2(x * CELL, y * CELL), Vector2(CELL - 1, CELL - 1)), col)
	# items
	for it in eng.items:
		var c: Color = Color(0.9, 0.8, 0.3) if it.kind == "gold" else Color(0.4, 0.8, 1.0)
		draw_circle(ORIGIN + Vector2(it.x * CELL + CELL / 2, it.y * CELL + CELL / 2), 4, c)
	# monsters
	for m in eng.monsters:
		draw_rect(Rect2(ORIGIN + Vector2(m.x * CELL + 4, m.y * CELL + 4), Vector2(CELL - 9, CELL - 9)),
			Color(0.85, 0.30, 0.30))
	# player
	draw_rect(Rect2(ORIGIN + Vector2(eng.player.x * CELL + 3, eng.player.y * CELL + 3),
		Vector2(CELL - 7, CELL - 7)), Color(0.95, 0.95, 0.95))
	# HUD
	var font := ThemeDB.fallback_font
	var hud := "Depth %d   HP %d/%d   ATK %d   Lv %d   Gold %d   Potions %d" % [
		eng.depth, eng.player.hp, eng.player.max_hp, eng.player.atk,
		eng.player.level, eng.player.gold, eng.player.potions]
	draw_string(font, Vector2(24, 32), hud, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	if eng.log_lines.size() > 0:
		draw_string(font, Vector2(24, 48), eng.log_lines[eng.log_lines.size() - 1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.85))
	if eng.game_over:
		var msg := "YOU WIN — press R" if eng.won else "YOU DIED — press R"
		draw_string(font, Vector2(24, ORIGIN.y + RogueEngine.H * CELL + 20), msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.4))
