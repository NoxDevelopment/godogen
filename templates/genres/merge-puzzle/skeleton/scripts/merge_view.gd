extends Node2D
## res://scripts/merge_view.gd
## The playable merge-puzzle (2048) view — renders GameManager's MergeEngine (the tile grid,
## score/best/moves) and turns arrow keys / WASD / swipes into moves. All rules live in
## MergeEngine; this is presentation + input only. Arrow keys or WASD (or swipe) to slide ·
## T autoplay · R restart.

const CELL := 128
const GAP := 12
const ORIGIN := Vector2(440, 120)
const TILE_COLORS := {
	0: Color(0.17, 0.16, 0.15), 2: Color(0.93, 0.89, 0.85), 4: Color(0.93, 0.88, 0.78),
	8: Color(0.95, 0.69, 0.47), 16: Color(0.96, 0.58, 0.39), 32: Color(0.96, 0.49, 0.37),
	64: Color(0.96, 0.37, 0.23), 128: Color(0.93, 0.81, 0.45), 256: Color(0.93, 0.80, 0.38),
	512: Color(0.93, 0.78, 0.31), 1024: Color(0.93, 0.77, 0.25), 2048: Color(0.93, 0.76, 0.18),
}
var eng: MergeEngine
var _drag_start := Vector2.ZERO
var _dragging := false

func _ready() -> void:
	eng = GameManager.engine
	set_process(true)

func _process(delta: float) -> void:
	if eng == null:
		return
	GameManager.advance(delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if eng == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A: GameManager.move("left")
			KEY_RIGHT, KEY_D: GameManager.move("right")
			KEY_UP, KEY_W: GameManager.move("up")
			KEY_DOWN, KEY_S: GameManager.move("down")
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_R:
				GameManager.new_game()
				eng = GameManager.engine
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start = event.position
		elif _dragging:
			_dragging = false
			var d: Vector2 = event.position - _drag_start
			if d.length() > 24.0:
				if absf(d.x) > absf(d.y):
					GameManager.move("right" if d.x > 0 else "left")
				else:
					GameManager.move("down" if d.y > 0 else "up")
			queue_redraw()

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# HUD
	draw_string(font, Vector2(440, 70), "MERGE 2048", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	draw_string(font, Vector2(760, 60), "Score %d" % eng.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.6))
	draw_string(font, Vector2(760, 88), "Best %d   Moves %d%s" % [eng.best_tile, eng.moves, ("   [AUTO]" if GameManager.autoplay else "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.9))
	# board background
	var boardsz := MergeEngine.N * CELL + (MergeEngine.N + 1) * GAP
	draw_rect(Rect2(ORIGIN - Vector2(GAP, GAP), Vector2(boardsz, boardsz)), Color(0.12, 0.11, 0.10))
	# tiles
	for y in range(MergeEngine.N):
		for x in range(MergeEngine.N):
			var v := eng.at(x, y)
			var pos := ORIGIN + Vector2(x * (CELL + GAP), y * (CELL + GAP))
			var col: Color = TILE_COLORS.get(v, Color(0.6, 0.5, 0.4))
			draw_rect(Rect2(pos, Vector2(CELL, CELL)), col)
			if v > 0:
				var tc := Color(0.3, 0.28, 0.25) if v <= 4 else Color(0.98, 0.96, 0.94)
				var fs := 44 if v < 128 else (36 if v < 1024 else 28)
				draw_string(font, pos + Vector2(0, CELL / 2 + fs / 3), str(v), HORIZONTAL_ALIGNMENT_CENTER, CELL, fs, tc)
	draw_string(font, Vector2(440, ORIGIN.y + boardsz + 24), "Arrow keys / WASD / swipe to slide · T autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.64, 0.7))
	if eng.game_over:
		var boardsz2 := MergeEngine.N * CELL + (MergeEngine.N + 1) * GAP
		draw_rect(Rect2(ORIGIN - Vector2(GAP, GAP), Vector2(boardsz2, boardsz2)), Color(0.05, 0.05, 0.08, 0.7))
		draw_string(font, Vector2(ORIGIN.x - GAP, ORIGIN.y + boardsz2 / 2 - 10), "%s\nscore %d — press R" % [("YOU WIN!" if eng.won else "GAME OVER"), eng.score],
			HORIZONTAL_ALIGNMENT_CENTER, boardsz2, 26, Color(1, 0.85, 0.4))
