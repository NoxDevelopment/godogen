extends Node2D
## res://scripts/solitaire_view.gd
## The playable Klondike view — renders GameManager's SolitaireEngine (foundations, stock, waste,
## the 7 tableau columns with face-down/face-up cards) and drives click-to-move. All rules live in
## SolitaireEngine; this is presentation + input only.
## Click stock = draw · click a card to select, click a column/foundation to move · right-click a
## card = send it home · H = one solver move (hint) · T = autoplay · R = restart.
## (Coloured card rects with rank+suit glyphs are placeholders for real card art.)

const CW := 74.0
const CH := 102.0
const STOCK_X := 60.0
const STOCK_Y := 40.0
const WASTE_X := 150.0
const FND_X := 720.0                ## first foundation slot x
const FND_DX := 96.0
const TAB_X0 := 60.0
const TAB_DX := 100.0
const TAB_Y0 := 180.0
const UP_DY := 30.0
const DOWN_DY := 12.0
const SUITS := ["♣", "♦", "♥", "♠"]   ## clubs diamonds hearts spades
const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

var eng: SolitaireEngine

func _ready() -> void:
	eng = GameManager.engine
	set_process(true)

func _process(_delta: float) -> void:
	if eng == null:
		return
	if GameManager.autoplay:
		GameManager.step_autoplay()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_H: GameManager.hint_step()
			KEY_R:
				GameManager.new_game()
				eng = GameManager.engine
			KEY_SPACE: GameManager.draw()
		return
	if GameManager.autoplay or eng == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var p: Vector2 = event.position
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_right_click(p)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_left_click(p)

# ---- geometry ---- #

func _stock_rect() -> Rect2:
	return Rect2(STOCK_X, STOCK_Y, CW, CH)

func _waste_rect() -> Rect2:
	return Rect2(WASTE_X, STOCK_Y, CW, CH)

func _fnd_rect(i: int) -> Rect2:
	return Rect2(FND_X + i * FND_DX, STOCK_Y, CW, CH)

func _col_x(col: int) -> float:
	return TAB_X0 + col * TAB_DX

## Which tableau (col, idx) is under `p`? idx = -1 means the empty-column drop zone. col=-1 = none.
func _tableau_hit(p: Vector2) -> Vector2i:
	for col in range(7):
		var x := _col_x(col)
		if p.x < x or p.x > x + CW:
			continue
		var column: Array = eng.tableau[col]
		if column.is_empty():
			if p.y >= TAB_Y0 and p.y <= TAB_Y0 + CH:
				return Vector2i(col, -1)
			continue
		var y := TAB_Y0
		var hit := -1
		for i in range(column.size()):
			var dy: float = UP_DY if bool(column[i].up) else DOWN_DY
			var span: float = CH if i == column.size() - 1 else dy
			if p.y >= y and p.y <= y + span:
				hit = i
			y += (dy if i < column.size() - 1 else CH)
		if hit >= 0:
			return Vector2i(col, hit)
		if p.y >= TAB_Y0 and p.y <= y:
			return Vector2i(col, column.size() - 1)
	return Vector2i(-1, -1)

func _left_click(p: Vector2) -> void:
	if _stock_rect().has_point(p):
		GameManager.draw()
		return
	var sel: Dictionary = GameManager.sel
	# clicking a foundation slot with a selection tries to send it home
	for i in range(4):
		if _fnd_rect(i).has_point(p):
			if not sel.is_empty():
				GameManager.send_home_selection()
			return
	if _waste_rect().has_point(p):
		if sel.is_empty():
			GameManager.select_waste()
		else:
			GameManager.clear_selection()
		return
	var hit := _tableau_hit(p)
	if hit.x < 0:
		GameManager.clear_selection()
		return
	if sel.is_empty():
		if hit.y >= 0:
			GameManager.select_tableau(hit.x, hit.y)
	else:
		if not GameManager.place_on_tableau(hit.x):
			# retarget: treat as a new selection
			GameManager.clear_selection()
			if hit.y >= 0:
				GameManager.select_tableau(hit.x, hit.y)

func _right_click(p: Vector2) -> void:
	# quick send-home: select what was right-clicked, then try foundation
	if _waste_rect().has_point(p):
		GameManager.select_waste()
		GameManager.send_home_selection()
		return
	var hit := _tableau_hit(p)
	if hit.x >= 0 and hit.y >= 0:
		GameManager.select_tableau(hit.x, hit.y)
		GameManager.send_home_selection()

# ---- drawing ---- #

func _draw_card(pos: Vector2, card: int, face_up: bool, highlight: bool) -> void:
	var r := Rect2(pos.x, pos.y, CW, CH)
	if not face_up:
		draw_rect(r, Color(0.18, 0.24, 0.42))
		draw_rect(r, Color(0.34, 0.42, 0.66), false, 2.0)
		return
	draw_rect(r, Color(0.96, 0.96, 0.98))
	draw_rect(r, (Color(0.98, 0.85, 0.2) if highlight else Color(0.2, 0.2, 0.24)), false, (3.0 if highlight else 1.5))
	var suit := eng.suit_of(card)
	var col: Color = Color(0.8, 0.15, 0.15) if (suit == 1 or suit == 2) else Color(0.1, 0.1, 0.12)
	var font := ThemeDB.fallback_font
	var label: String = RANKS[eng.rank_of(card)] + SUITS[suit]
	draw_string(font, Vector2(pos.x + 6, pos.y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
	draw_string(font, Vector2(pos.x + 6, pos.y + CH - 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)

func _empty_slot(r: Rect2, glyph: String) -> void:
	draw_rect(r, Color(0.10, 0.20, 0.14))
	draw_rect(r, Color(0.24, 0.4, 0.3), false, 1.5)
	if glyph != "":
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x + 24, r.position.y + 60), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.3, 0.5, 0.4))

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	var sel: Dictionary = GameManager.sel
	# stock
	if eng.stock.is_empty():
		_empty_slot(_stock_rect(), "↻")
	else:
		_draw_card(Vector2(STOCK_X, STOCK_Y), 0, false, false)
	# waste (top card)
	if eng.waste.is_empty():
		_empty_slot(_waste_rect(), "")
	else:
		var wc := int(eng.waste[eng.waste.size() - 1])
		_draw_card(Vector2(WASTE_X, STOCK_Y), wc, true, sel.get("kind", "") == "waste")
	# foundations
	for i in range(4):
		var r := _fnd_rect(i)
		if int(eng.foundations[i]) < 0:
			_empty_slot(r, SUITS[i])
		else:
			_draw_card(r.position, i * 13 + int(eng.foundations[i]), true, false)
	# tableau
	for col in range(7):
		var x := _col_x(col)
		var column: Array = eng.tableau[col]
		if column.is_empty():
			_empty_slot(Rect2(x, TAB_Y0, CW, CH), "")
			continue
		var y := TAB_Y0
		for i in range(column.size()):
			var e = column[i]
			var hl: bool = str(sel.get("kind", "")) == "tableau" and int(sel.get("col", -1)) == col and i >= int(sel.get("idx", 99))
			_draw_card(Vector2(x, y), int(e.card), bool(e.up), hl)
			y += (UP_DY if bool(e.up) else DOWN_DY)
	_draw_hud(font)

func _draw_hud(font: Font) -> void:
	draw_string(font, Vector2(FND_X, 24), "Foundations  %d / 52" % eng.foundation_total(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.9, 0.85))
	draw_string(font, Vector2(STOCK_X, 170), "Moves %d   Redeals %d%s" % [eng.moves, eng.redeals,
		("   [AUTOPLAY]" if GameManager.autoplay else "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.75, 0.8))
	draw_string(font, Vector2(60, 700), "Click stock=draw · click to select→click column to move · right-click=send home · H hint · T autoplay · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.68))
	if eng.won:
		draw_string(font, Vector2(0, 130), "YOU WIN — press R", HORIZONTAL_ALIGNMENT_CENTER, 1280, 26, Color(1, 0.85, 0.4))
	elif eng.stuck:
		draw_string(font, Vector2(0, 130), "NO MOVES LEFT (%d/52) — press R" % eng.foundation_total(),
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, Color(1, 0.7, 0.4))
