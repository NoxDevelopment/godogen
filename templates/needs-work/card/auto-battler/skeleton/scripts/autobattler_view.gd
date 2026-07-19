extends Node2D
## res://scripts/autobattler_view.gd
## The playable auto-battler view — renders GameManager's AutoBattlerEngine (the gold shop, your
## drafted team, round/gold/lives/trophies, and the last combat result) and turns clicks into
## shop actions. All rules live in AutoBattlerEngine; this is presentation + input only. Combat
## auto-resolves on End Round. Click a shop unit to buy · click a team unit to sell · Roll ·
## End Round (fight) · T autoplay · N new run. (Coloured cards are placeholders for unit art.)

const TAG_COLOR := {"melee": Color(0.85, 0.45, 0.4), "magic": Color(0.55, 0.5, 0.9), "support": Color(0.4, 0.75, 0.55)}
var eng: AutoBattlerEngine
var _shop_rects: Array = []
var _team_rects: Array = []
var _btn_rects: Array = []

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
			KEY_R: if not GameManager.autoplay: eng.roll()
			KEY_SPACE: if not GameManager.autoplay: eng.end_shop()
			KEY_T: GameManager.autoplay = not GameManager.autoplay
			KEY_N:
				GameManager.new_run()
				eng = GameManager.engine
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and not GameManager.autoplay:
		var p: Vector2 = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in range(_shop_rects.size()):
				if (_shop_rects[i] as Rect2).has_point(p): eng.buy(i)
			for i in range(_team_rects.size()):
				if (_team_rects[i] as Rect2).has_point(p): eng.sell(i)
			for b in _btn_rects:
				if (b.rect as Rect2).has_point(p):
					if str(b.id) == "roll": eng.roll()
					elif str(b.id) == "fight": eng.end_shop()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			for i in range(_shop_rects.size()):
				if (_shop_rects[i] as Rect2).has_point(p): eng.freeze(i)
		queue_redraw()

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _card(font: Font, r: Rect2, u: Dictionary, frozen: bool) -> void:
	var col: Color = TAG_COLOR.get(str(u.tag), Color.GRAY)
	draw_rect(r, Color(0.12, 0.13, 0.17))
	draw_rect(r, col if not frozen else Color(0.5, 0.8, 1.0), false, 2.0 if not frozen else 3.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), col)
	draw_string(font, r.position + Vector2(8, 30), str(u.kind), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(font, r.position + Vector2(8, 54), "%d / %d" % [int(u.atk), int(u.hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.6))
	if str(u.ability) != "":
		draw_string(font, r.position + Vector2(8, 76), str(u.ability), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.85, 0.95))
	if frozen:
		draw_string(font, r.position + Vector2(8, 96), "frozen", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.8, 1.0))

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	# HUD
	draw_string(font, Vector2(40, 40), "Round %d    Gold %d    Lives %d    Trophies %d / %d%s" % [
		eng.round_no, eng.gold, eng.lives, eng.trophies, AutoBattlerEngine.TROPHIES_TO_WIN,
		("    [AUTOPLAY]" if GameManager.autoplay else "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	if eng.last_combat != "":
		var lc := Color(0.4, 1, 0.5) if eng.last_combat == "win" else (Color(1, 0.4, 0.4) if eng.last_combat == "loss" else Color(1, 0.85, 0.4))
		draw_string(font, Vector2(720, 40), "last: %s" % eng.last_combat.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, lc)
	# synergy readout
	var melee := 0; var magic := 0; var support := 0
	for u in eng.team:
		match str(u.tag):
			"melee": melee += 1
			"magic": magic += 1
			"support": support += 1
	draw_string(font, Vector2(40, 66), "synergy — melee %d%s · magic %d%s · support %d%s" % [
		melee, (" (+atk!)" if melee >= 3 else ""), magic, (" (+zap!)" if magic >= 2 else ""), support, (" (+hp!)" if support >= 2 else "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.82, 0.86))
	# shop
	draw_string(font, Vector2(40, 110), "SHOP  (left-click buy $%d · right-click freeze)" % AutoBattlerEngine.BUY_COST, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))
	_shop_rects = []
	for i in range(eng.shop.size()):
		var r := Rect2(40 + i * 150, 130, 138, 116)
		_shop_rects.append(r)
		_card(font, r, eng.shop[i].unit, bool(eng.shop[i].frozen))
	# team
	draw_string(font, Vector2(40, 300), "YOUR TEAM  (front → back · click to sell for $%d)" % AutoBattlerEngine.SELL_VALUE, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))
	_team_rects = []
	for i in range(eng.team.size()):
		var r := Rect2(40 + i * 150, 320, 138, 116)
		_team_rects.append(r)
		_card(font, r, eng.team[i], false)
	# buttons
	_btn_rects = []
	var roll_r := Rect2(40, 470, 200, 50)
	var fight_r := Rect2(260, 470, 240, 50)
	_btn_rects.append({"id": "roll", "rect": roll_r})
	_btn_rects.append({"id": "fight", "rect": fight_r})
	draw_rect(roll_r, Color(0.15, 0.16, 0.22)); draw_rect(roll_r, Color(0.5, 0.5, 0.6), false, 1.5)
	draw_string(font, roll_r.position + Vector2(14, 32), "Roll  ($%d)  [R]" % AutoBattlerEngine.ROLL_COST, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_rect(fight_r, Color(0.2, 0.14, 0.14)); draw_rect(fight_r, Color(0.8, 0.4, 0.4), false, 1.5)
	draw_string(font, fight_r.position + Vector2(14, 32), "End Round — FIGHT  [Space]", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# log
	var ly := 550
	for i in range(max(0, eng.log_lines.size() - 5), eng.log_lines.size()):
		draw_string(font, Vector2(40, ly), str(eng.log_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.74, 0.76, 0.8))
		ly += 20
	draw_string(font, Vector2(40, 700), "Draft a team, then End Round to auto-battle the wave · T autoplay · N new run", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.64, 0.7))
	if eng.game_over:
		draw_string(font, Vector2(0, 300), "%s — press N" % ("VICTORY! (%d trophies)" % eng.trophies if eng.won else "OUT OF LIVES — round %d, %d trophies" % [eng.round_no, eng.trophies]),
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, Color(1, 0.85, 0.4))
