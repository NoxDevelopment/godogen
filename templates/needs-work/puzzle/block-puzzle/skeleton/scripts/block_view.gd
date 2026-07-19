extends Node2D
## res://scripts/block_view.gd
## The playable falling-block view — steps GameManager's BlockEngine at the physics rate
## (gravity lives in the engine) with sampled inputs, and draws the well, the active piece +
## its GHOST (landing preview), the NEXT piece, and a score/lines/level HUD. All rules live in
## BlockEngine; this is presentation + input only. ←/→ (or A/D) move · ↓ soft drop · Space
## hard drop · ↑/X rotate CW · Z rotate CCW · T autoplay · R restart.

const CELL := 26
const OX := 510.0
const OY := 90.0
const COLORS := [
	Color(0.12, 0.13, 0.16),        # 0 empty
	Color(0.3, 0.85, 0.95),         # I
	Color(0.95, 0.85, 0.3),         # O
	Color(0.75, 0.4, 0.95),         # T
	Color(0.4, 0.9, 0.45),          # S
	Color(0.95, 0.4, 0.42),         # Z
	Color(0.4, 0.55, 0.95),         # J
	Color(0.95, 0.6, 0.3),          # L
]

var eng: BlockEngine
var _prev := {}
var _das := {"left": 0, "right": 0}

func _ready() -> void:
	eng = GameManager.engine
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if eng == null:
		return
	if not eng.game_over:
		GameManager.advance(_sample())
	queue_redraw()

func _edge(key: int) -> bool:
	var down: bool = Input.is_key_pressed(key)
	var was: bool = bool(_prev.get(key, false))
	_prev[key] = down
	return down and not was

func _sample() -> Dictionary:
	var inp := {"dx": 0, "rot": 0, "soft": false, "hard": false}
	# horizontal with a little DAS (auto-repeat while held)
	for pair in [["left", KEY_LEFT, KEY_A, -1], ["right", KEY_RIGHT, KEY_D, 1]]:
		var held: bool = Input.is_key_pressed(pair[1]) or Input.is_key_pressed(pair[2])
		if held:
			var t: int = int(_das[pair[0]]) + 1
			_das[pair[0]] = t
			if t == 1 or (t > 10 and t % 3 == 0):
				inp.dx = pair[3]
		else:
			_das[pair[0]] = 0
	if _edge(KEY_UP) or _edge(KEY_X):
		inp.rot = 1
	elif _edge(KEY_Z):
		inp.rot = -1
	inp.soft = Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
	if _edge(KEY_SPACE):
		inp.hard = true
	return inp

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			GameManager.autoplay = not GameManager.autoplay
		elif event.keycode == KEY_R:
			GameManager.new_game()
			eng = GameManager.engine
			_prev = {}

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _cellrect(x: int, y: int) -> Rect2:
	return Rect2(OX + x * CELL, OY + y * CELL, CELL - 1, CELL - 1)

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# well border
	draw_rect(Rect2(OX - 3, OY - 3, BlockEngine.W * CELL + 6, BlockEngine.H * CELL + 6), Color(0.3, 0.32, 0.4), false, 3.0)
	# settled board
	for y in range(BlockEngine.H):
		for x in range(BlockEngine.W):
			var v: int = eng.board[y * BlockEngine.W + x]
			draw_rect(_cellrect(x, y), COLORS[clampi(v, 0, 7)])
	# ghost + active piece
	if not eng.piece.is_empty():
		var t: String = str(eng.piece.type)
		var rot: int = int(eng.piece.rot)
		var px: int = int(eng.piece.x)
		var py: int = int(eng.piece.y)
		var idx: int = BlockEngine.TYPES.find(t) + 1
		# ghost: drop to rest
		var gy := py
		while eng._valid(t, rot, px, gy + 1):
			gy += 1
		for c in eng.cells_of(t, rot, px, gy):
			if c.y >= 0:
				draw_rect(_cellrect(c.x, c.y), COLORS[idx] * Color(1, 1, 1, 0.28))
		for c in eng.current_cells():
			if c.y >= 0:
				draw_rect(_cellrect(c.x, c.y), COLORS[idx])
	# next-piece preview
	draw_string(font, Vector2(OX + BlockEngine.W * CELL + 30, OY + 6), "NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	if eng.next_type != "":
		var nidx: int = BlockEngine.TYPES.find(eng.next_type) + 1
		for c in eng.cells_of(eng.next_type, 0, 0, 0):
			var r := Rect2(OX + BlockEngine.W * CELL + 30 + c.x * CELL, OY + 20 + c.y * CELL, CELL - 1, CELL - 1)
			draw_rect(r, COLORS[nidx])
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	var hx := OX - 190.0
	draw_string(font, Vector2(hx, OY + 30), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.72, 0.78))
	draw_string(font, Vector2(hx, OY + 54), str(eng.score), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(hx, OY + 100), "LINES  %d" % eng.lines, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.85, 0.9))
	draw_string(font, Vector2(hx, OY + 124), "LEVEL  %d" % eng.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.85, 0.9))
	if GameManager.autoplay:
		draw_string(font, Vector2(hx, OY + 160), "AUTOPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.9, 0.7))
	draw_string(font, Vector2(hx, OY + 220),
		"←/→ move\n↓ soft drop\nSpace hard drop\n↑/X rotate CW\nZ rotate CCW\nT autoplay\nR restart",
		HORIZONTAL_ALIGNMENT_LEFT, 180, 12, Color(0.62, 0.64, 0.7))
	if eng.game_over:
		draw_string(font, Vector2(OX - 4, OY + BlockEngine.H * CELL / 2), "GAME OVER — press R",
			HORIZONTAL_ALIGNMENT_LEFT, BlockEngine.W * CELL, 20, Color(1, 0.85, 0.4))
