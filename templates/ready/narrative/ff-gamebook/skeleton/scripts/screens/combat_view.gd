extends Control
## res://scripts/screens/combat_view.gd
## The Combat Screen (WIREFRAMES 5.4, GDD §6.1 #7; LOOKFEEL_PASS_2026-07 §combat)
## — resolves an encounter round by round over the faithful FF rules core
## (FFCombat, seeded IFDice), staying engine-authoritative: every wound routes
## through FFAdventureSheet.apply_delta and every die is the one the seeded core
## rolled.
##
## PRESENTATION: the fight is A PAGE OF THE BOOK (FFC keeps the page visible;
## Veritas rolls the dice onto the page and prints the math beneath) — paper
## ground, the foe as a portrait plate under an engraved name banner, BOTH
## combatants' sheet-strips in the printed-box idiom (foe STAMINA scratching
## down), the 3D dice tray INLINE on the page with the round's arithmetic
## printed under it in book type, and the round log written into a ruled ledger
## in the player's hand. The dice popup remains only for Luck tests.
##
## On resolution it emits `resolved(outcome_id)` and the reading view routes via
## Adventure.choose (which applies effects + goto).

signal resolved(outcome_id: String)

const DICE_POPUP := preload("res://scenes/dice_roll_popup.tscn")
const INVENTORY := preload("res://scripts/screens/inventory_view.tscn")

var _encounter: FFEncounter
var _enemies: Array[Dictionary] = []
var _outcomes := {}                 # {win, death, escape} -> choice id
var _section_no := ""
var _target := 0
var _quick := false
var _busy := false
var _round := 0
var _pending_luck := ""             # "" | "wounded_enemy" | "wounded_self"
var _last_player_total := 0
var _log_lines: Array[String] = []

# widgets
var _enemy_box: VBoxContainer
var _player_strip: HBoxContainer
var _round_head: Label
var _round_you: Label
var _round_foe: Label
var _log: RichTextLabel
var _log_scroll: ScrollContainer
var _actions: HBoxContainer
var _luck_bar: HBoxContainer
var _tray: Dice3DTray
var _dice_2d: HBoxContainer
var _banner: Label
var _continue_btn: Button


func setup(encounter: FFEncounter, outcomes: Dictionary, section_no: String) -> void:
	_encounter = encounter
	_outcomes = outcomes
	_section_no = section_no
	_enemies = encounter.make_enemy_records()
	if _enemies.is_empty():
		_enemies = [FFCombat.make_enemy("Foe", 6, 6)]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()
	_append_log("The encounter is joined.")
	# combat music stinger (STYLE_GUIDE §2.2) — the Reckoner's own tragic bed on the
	# boss fight, the grim combat bed otherwise.
	AudioDirector.play_music("boss" if _section_no == "s_reckoner_fight" else "combat")


func _build() -> void:
	add_child(FFUI.paper_ground())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	margin.add_child(root)

	# --- engraved combat banner ------------------------------------------------
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	var folio := FFUI.label("§ %s" % _section_no, 16, FFUI.UMBER)
	folio.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(folio)
	var t := FFUI.title(_banner_title(), 26, FFUI.ARREARS.darkened(0.15))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var qc := CheckButton.new()
	qc.text = "Quick Combat"
	qc.add_theme_font_override(&"font", FFUI.font_body())
	qc.add_theme_font_size_override(&"font_size", 15)
	qc.add_theme_color_override(&"font_color", FFUI.UMBER)
	var ff := get_node_or_null("/root/FFSettings")
	if ff != null:
		_quick = ff.quick_combat
		qc.button_pressed = _quick
	qc.toggled.connect(_on_quick_toggled)
	head.add_child(qc)
	root.add_child(head)
	root.add_child(FFUI.diamond_rule(FFUI.ARREARS))

	# --- two columns: the foe plate | the round on the page --------------------
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# left: foe portrait plate(s) + the player's sheet-strip
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	left.custom_minimum_size = Vector2(360, 0)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cols.add_child(left)
	var enemy_scroll := ScrollContainer.new()
	enemy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	enemy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_enemy_box = VBoxContainer.new()
	_enemy_box.add_theme_constant_override(&"separation", 8)
	_enemy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_scroll.add_child(_enemy_box)
	left.add_child(enemy_scroll)

	var you_cap := FFUI.label("YOUR SHEET", 12, FFUI.VERDIGRIS, false)
	you_cap.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	left.add_child(you_cap)
	_player_strip = HBoxContainer.new()
	_player_strip.add_theme_constant_override(&"separation", 8)
	left.add_child(_player_strip)

	# right: the dice ON the page + printed math + the ledger log
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	_round_head = FFUI.label("THE FIRST ROUND", 15, FFUI.UMBER, false)
	_round_head.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	_round_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_round_head)

	var tray_center := CenterContainer.new()
	_tray = Dice3DTray.new()
	_tray.visible = false
	tray_center.add_child(_tray)
	right.add_child(tray_center)
	_dice_2d = HBoxContainer.new()
	_dice_2d.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_2d.add_theme_constant_override(&"separation", 10)
	right.add_child(_dice_2d)

	# the arithmetic, printed like Veritas: "You — 2d6 = 7  + SKILL 9 = 16"
	_round_you = FFUI.label("", 16, FFUI.INK)
	_round_you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_round_you)
	_round_foe = FFUI.label("", 16, FFUI.INK)
	_round_foe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_round_foe)

	_banner = FFUI.title("", 22, FFUI.VERDIGRIS)
	right.add_child(_banner)

	_continue_btn = FFUI.chip("Tap to continue")
	_continue_btn.custom_minimum_size = Vector2(220, 44)
	_continue_btn.visible = false
	var cc := CenterContainer.new()
	cc.add_child(_continue_btn)
	right.add_child(cc)

	# the round LEDGER — written in the player's hand on ruled paper
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var ledger := _LedgerBox.new()
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.add_theme_font_override(&"normal_font", FFUI.font_hand())
	_log.add_theme_font_size_override(&"normal_font_size", 18)
	_log.add_theme_color_override(&"default_color", FFUI.GRAPHITE)
	_log.add_theme_constant_override(&"line_separation", 9)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger.add_child(_log)
	_log_scroll.add_child(ledger)
	right.add_child(_log_scroll)

	# luck-in-combat prompt bar (hidden until offered)
	_luck_bar = HBoxContainer.new()
	_luck_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_luck_bar.add_theme_constant_override(&"separation", 10)
	_luck_bar.visible = false
	root.add_child(_luck_bar)

	# action buttons
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override(&"separation", 10)
	root.add_child(_actions)
	_build_actions()


func _banner_title() -> String:
	return "COMBAT"


func _build_actions() -> void:
	for c in _actions.get_children():
		c.queue_free()
	var attack := FFUI.chip("⚔  Attack")
	attack.custom_minimum_size = Vector2(0, 52)
	attack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attack.pressed.connect(_on_attack)
	_actions.add_child(attack)
	attack.grab_focus()

	var luck := FFUI.chip("🎲  Test Luck")
	luck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	luck.pressed.connect(_on_test_luck_freely)
	_actions.add_child(luck)

	if _encounter != null and _encounter.offers_escape():
		var esc := FFUI.chip("🏃  Escape")
		esc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		esc.pressed.connect(_on_escape)
		_actions.add_child(esc)

	var use := FFUI.chip("🎒  Use Item")
	use.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use.pressed.connect(_on_use_item)
	_actions.add_child(use)

	var eat := FFUI.chip("🍖  Eat")
	eat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eat.disabled = Adventure.sheet.provisions <= 0
	eat.pressed.connect(_on_eat)
	_actions.add_child(eat)


func _refresh() -> void:
	# Feed the Adventure Sheet's Monster Encounter grid (ADVENTURE_SHEET_SPEC §6).
	Adventure.sheet.sync_encounters(_enemies)
	# enemy plates
	for c in _enemy_box.get_children():
		c.queue_free()
	for i in _enemies.size():
		_enemy_box.add_child(_enemy_panel(i))
	# the player's sheet-strip: printed boxes, values in the player's hand
	var s := Adventure.sheet
	for c in _player_strip.get_children():
		c.queue_free()
	_player_strip.add_child(_strip_box("SKILL", s.cur("skill"), -1, FFUI.VERDIGRIS))
	_player_strip.add_child(_strip_box("STAMINA", s.cur("stamina"), s.init_of("stamina"), FFUI.ARREARS))
	_player_strip.add_child(_strip_box("LUCK", s.cur("luck"), s.init_of("luck"), FFUI.FLAME))
	_player_strip.add_child(_strip_box("PROV", s.provisions, -1, FFUI.UMBER))


## A printed sheet-strip box: engraved caption over a hand-written value; when
## `initial` is given and higher, the value reads "of N" beneath (the sheet rule).
func _strip_box(caption: String, value: int, initial: int, accent: Color) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.4)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.8)
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override(&"panel", sb)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	var cap := FFUI.label(caption, 10, FFUI.FEN, false)
	cap.add_theme_font_override(&"font", FFUI.font_display_tracked(1))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var holder := CenterContainer.new()
	holder.add_child(FFUI.handwritten(str(value), 24, FFUI.INK_PEN, "cbt_%s_%d" % [caption, value]))
	v.add_child(holder)
	if initial > 0:
		var of := FFUI.label("of %d" % initial, 10, FFUI.UMBER, false)
		of.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(of)
	box.add_child(v)
	return box


## A foe presented as a book plate: the portrait in the double-rule frame, an
## engraved name banner, SKILL / STAMINA in printed boxes (STAMINA scratching
## down against its opening value), a diagonal cancel when dispersed.
func _enemy_panel(index: int) -> Control:
	var e: Dictionary = _enemies[index]
	var alive := int(e.get("stamina", 0)) > 0
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override(&"separation", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var port_tex := FFUI.portrait(_portrait_name(e))
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(120, 120)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if port_tex != null:
		tr.texture = port_tex
	var plate := FFUI.plate_frame(tr, FFUI.ARREARS if index == _target and alive else FFUI.UMBER)
	if not alive:
		plate.modulate = Color(0.55, 0.55, 0.55)
	row.add_child(plate)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 4)
	var nm := FFUI.label(str(e.get("name", "Foe")).to_upper(), 17, FFUI.INK if alive else FFUI.FEN, false)
	nm.add_theme_font_override(&"font", FFUI.font_display_tracked(2))
	info.add_child(nm)
	var rule := FFUI.diamond_rule(FFUI.ARREARS if alive else FFUI.FEN)
	rule.custom_minimum_size = Vector2(0, 8)
	info.add_child(rule)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override(&"separation", 6)
	cells.add_child(_strip_box("SKILL", int(e.get("skill", 0)), -1, FFUI.VERDIGRIS))
	cells.add_child(_strip_box("STAMINA", int(e.get("stamina", 0)), int(e.get("stamina_max", 1)), FFUI.ARREARS))
	info.add_child(cells)
	if not alive:
		info.add_child(FFUI.label("— dispersed —", 13, FFUI.FEN))
	elif _enemies.size() > 1:
		var pick := FFUI.chip("Target" if index != _target else "◈ Target")
		pick.pressed.connect(func() -> void: _target = index; _refresh())
		info.add_child(pick)
	row.add_child(info)
	wrap.add_child(row)
	return wrap


func _portrait_name(e: Dictionary) -> String:
	var p := str(e.get("portrait", ""))
	if p.begins_with("portrait/"):
		return p.substr("portrait/".length())
	return p


func _first_alive() -> int:
	for i in _enemies.size():
		if int(_enemies[i].get("stamina", 0)) > 0:
			return i
	return -1


func _round_no() -> int:
	return maxi(_round, 1)


func _on_quick_toggled(v: bool) -> void:
	_quick = v
	if v:
		_auto_run()


# --- Attack ----------------------------------------------------------------


func _on_attack() -> void:
	if _busy:
		return
	if int(_enemies[_target].get("stamina", 0)) <= 0:
		_target = _first_alive()
		if _target < 0:
			return
	_busy = true
	_round += 1
	_set_actions_enabled(false)
	var enemy: Dictionary = _enemies[_target]
	var res := FFCombat.attack_round(Adventure.sheet, enemy, Adventure.dice)
	_last_player_total = int(res.player_total)

	var banner := "PARRIED — no blood drawn"
	var bcolor := FFUI.FEN
	match str(res.outcome):
		"player_wounds":
			banner = "You wound the %s  (−%d)" % [enemy.get("name"), int(res.wound)]
			bcolor = FFUI.VERDIGRIS
		"enemy_wounds":
			banner = "The %s wounds you  (−%d)" % [enemy.get("name"), int(res.wound)]
			bcolor = FFUI.ARREARS

	# the dice roll ON the page (LOOKFEEL: FFC/Veritas), math printed beneath
	await _roll_inline(res, enemy, banner, bcolor)

	# round resolution maps 1:1 to audio (STYLE_GUIDE §2.3)
	match str(res.outcome):
		"player_wounds": AudioDirector.play_sfx("hit", true)
		"enemy_wounds": AudioDirector.play_sfx("wound", true)
		_: AudioDirector.play_sfx("parry", true)

	# gang rule: other alive foes also swing this round
	if _encounter != null and _encounter.is_gang():
		for i in _enemies.size():
			if i == _target or int(_enemies[i].get("stamina", 0)) <= 0:
				continue
			var gr := Adventure.dice.roll("2d6")
			var gtot := int(gr.total) + int(_enemies[i].get("skill", 0))
			if gtot > _last_player_total and not Adventure.sheet.is_dead():
				var rep := Adventure.sheet.apply_delta({"stamina": -FFCombat.WOUND})
				_append_log("The %s also strikes — you take −%d." % [_enemies[i].get("name"), FFCombat.WOUND])
				if bool(rep.get("died", false)):
					break

	_append_log(banner)
	Adventure.notify_sheet_changed(res)
	_refresh()

	# resolution checks
	if Adventure.sheet.is_dead():
		await _end(_outcomes.get("death", "_ondeath"), "You have fallen.")
		return
	if _all_defeated():
		await _end(_outcomes.get("win", "_onwin"), "The last of them is undone.")
		return

	# offer luck-in-combat
	if str(res.outcome) == "player_wounds":
		_offer_luck("wounded_enemy", "Test your Luck to press the wound?")
	elif str(res.outcome) == "enemy_wounds":
		_offer_luck("wounded_self", "Test your Luck to soften the blow?")
	else:
		_finish_turn()


## The inline round roll: throw all four dice in the page's tray (yours bone,
## the foe's greyer bone), then print the arithmetic + banner and gate on "Tap
## to continue" exactly as the popup did (probe-compatible). Quick mode flashes.
func _roll_inline(res: Dictionary, enemy: Dictionary, banner: String, bcolor: Color) -> void:
	_round_head.text = "ROUND %d" % _round_no()
	_round_you.text = ""
	_round_foe.text = ""
	_banner.text = ""
	_continue_btn.visible = false

	var you_faces: Array = res.player_faces
	var foe_faces: Array = res.enemy_faces
	var faces: Array = you_faces + foe_faces
	var tints: Array = []
	for _i in you_faces.size():
		tints.append(Dice3DTray.BONE)
	for _i in foe_faces.size():
		tints.append(Dice3DTray.ENEMY_BONE)

	if _reduced():
		_tray.visible = false
		_settle_2d(faces, tints)
		AudioDirector.play_sfx("dice_land", true)
	elif _use_3d():
		_clear_2d()
		_tray.visible = true
		AudioDirector.play_sfx("dice_shake", true)
		await _tray.roll(faces, tints)
		AudioDirector.play_sfx("dice_land")
	else:
		_tray.visible = false
		AudioDirector.play_sfx("dice_shake", true)
		await _tumble_2d(faces, tints)
		AudioDirector.play_sfx("dice_land")

	_round_you.text = "You — 2d6 = %d   + SKILL %d   =  %d" % [
		int(you_faces[0]) + int(you_faces[1]), Adventure.sheet.cur("skill"), int(res.player_total)]
	_round_foe.text = "%s — 2d6 = %d   + SKILL %d   =  %d" % [
		str(enemy.get("name", "Foe")), int(foe_faces[0]) + int(foe_faces[1]), int(enemy.get("skill")), int(res.enemy_total)]
	_banner.text = banner
	_banner.add_theme_color_override(&"font_color", bcolor)

	if _quick:
		await get_tree().create_timer(0.35).timeout
		return
	_continue_btn.visible = true
	_continue_btn.grab_focus()
	await _continue_btn.pressed
	_continue_btn.visible = false


func _clear_2d() -> void:
	for c in _dice_2d.get_children():
		c.queue_free()


func _settle_2d(faces: Array, tints: Array) -> void:
	_clear_2d()
	for i in faces.size():
		var d := FFDie.new()
		d.custom_minimum_size = Vector2(56, 56)
		if i < tints.size() and tints[i] == Dice3DTray.ENEMY_BONE:
			d.modulate = Color(0.85, 0.83, 0.78)
		d.value = int(faces[i])
		_dice_2d.add_child(d)


func _tumble_2d(faces: Array, tints: Array) -> void:
	_clear_2d()
	var dice: Array[FFDie] = []
	for i in faces.size():
		var d := FFDie.new()
		d.custom_minimum_size = Vector2(56, 56)
		if i < tints.size() and tints[i] == Dice3DTray.ENEMY_BONE:
			d.modulate = Color(0.85, 0.83, 0.78)
		_dice_2d.add_child(d)
		dice.append(d)
	var speed := _dice_speed()
	var t := 0.0
	while t < 0.7 / speed:
		for d in dice:
			d.value = randi_range(1, 6)
		await get_tree().create_timer(0.05 / speed).timeout
		t += 0.05 / speed
	for i in dice.size():
		dice[i].value = int(faces[i])


## Resolve one round with NO dice theatre — used by the screenshot harness so the
## foe plate + round arithmetic are visible together. Same math path.
func debug_resolve_round() -> void:
	if _all_defeated() or Adventure.sheet.is_dead():
		return
	_round += 1
	var enemy: Dictionary = _enemies[_target]
	var res := FFCombat.attack_round(Adventure.sheet, enemy, Adventure.dice)
	var banner := "Parried — no blood drawn"
	match str(res.outcome):
		"player_wounds": banner = "You wound the %s (−%d)" % [enemy.get("name"), int(res.wound)]
		"enemy_wounds": banner = "The %s wounds you (−%d)" % [enemy.get("name"), int(res.wound)]
	_round_head.text = "ROUND %d" % _round
	_round_you.text = "You — 2d6 = %d   + SKILL %d   =  %d" % [int(res.player_faces[0]) + int(res.player_faces[1]), Adventure.sheet.cur("skill"), int(res.player_total)]
	_round_foe.text = "%s — 2d6 = %d   + SKILL %d   =  %d" % [enemy.get("name"), int(res.enemy_faces[0]) + int(res.enemy_faces[1]), int(enemy.get("skill")), int(res.enemy_total)]
	_settle_2d((res.player_faces as Array) + (res.enemy_faces as Array),
		[Dice3DTray.BONE, Dice3DTray.BONE, Dice3DTray.ENEMY_BONE, Dice3DTray.ENEMY_BONE])
	_banner.text = banner
	_append_log(banner)
	Adventure.notify_sheet_changed(res)
	_refresh()


func _all_defeated() -> bool:
	for e in _enemies:
		if int(e.get("stamina", 0)) > 0:
			return false
	return true


# --- Luck in combat --------------------------------------------------------


func _offer_luck(kind: String, prompt: String) -> void:
	if _quick:
		_finish_turn()
		return
	_pending_luck = kind
	for c in _luck_bar.get_children():
		c.queue_free()
	_luck_bar.visible = true
	_luck_bar.add_child(FFUI.label(prompt, 16, FFUI.FLAME.darkened(0.2)))
	var yes := FFUI.chip("Yes — Test Luck")
	yes.pressed.connect(_on_luck_yes)
	_luck_bar.add_child(yes)
	var no := FFUI.chip("No")
	no.pressed.connect(func() -> void: _luck_bar.visible = false; _pending_luck = ""; _finish_turn())
	_luck_bar.add_child(no)
	yes.grab_focus()


func _on_luck_yes() -> void:
	_luck_bar.visible = false
	var lr := Adventure.test_luck()
	await _show_dice_test(lr, "TEST YOUR LUCK — combat")
	var enemy: Dictionary = _enemies[_target]
	if _pending_luck == "wounded_enemy":
		var r := FFCombat.luck_after_wounding(enemy, lr)
		_append_log("Luck in combat: %s — enemy %+d." % ["LUCKY" if lr.lucky else "UNLUCKY", -int(r.extra)])
	elif _pending_luck == "wounded_self":
		var r2 := FFCombat.luck_after_wounded(Adventure.sheet, lr)
		_append_log("Luck in combat: %s — you %+d." % ["LUCKY" if lr.lucky else "UNLUCKY", int(r2.extra)])
	_pending_luck = ""
	Adventure.notify_sheet_changed()
	_refresh()
	if Adventure.sheet.is_dead():
		await _end(_outcomes.get("death", "_ondeath"), "You have fallen.")
		return
	if _all_defeated():
		await _end(_outcomes.get("win", "_onwin"), "The last of them is undone.")
		return
	_finish_turn()


func _on_test_luck_freely() -> void:
	if _busy:
		return
	_busy = true
	_set_actions_enabled(false)
	var lr := Adventure.test_luck()
	await _show_dice_test(lr, "TEST YOUR LUCK")
	_append_log("Test your Luck: %s (LUCK now %d)." % ["LUCKY" if lr.lucky else "UNLUCKY", int(lr.luck_after)])
	Adventure.notify_sheet_changed()
	_refresh()
	_finish_turn()


# --- other actions ---------------------------------------------------------


func _on_eat() -> void:
	if _busy:
		return
	if Adventure.sheet.eat_provision():
		_append_log("You eat a Provision (+4 STAMINA).")
		Adventure.notify_sheet_changed()
		_refresh()
		_build_actions()


func _on_escape() -> void:
	if _busy:
		return
	var r := FFCombat.escape(Adventure.sheet)
	_append_log("You break off — a parting blow costs 2 STAMINA.")
	Adventure.notify_sheet_changed(r)
	if Adventure.sheet.is_dead():
		await _end(_outcomes.get("death", "_ondeath"), "The parting blow was the last.")
		return
	await _end(_outcomes.get("escape", "_onescape"), "You escape into the fog.")


func _on_use_item() -> void:
	var inv := INVENTORY.instantiate()
	inv.setup(true)   # combat context (Eat disabled mid-round handled inside)
	add_child(inv)


# --- dice overlay helper (Luck tests keep the pinned-card popup) ------------


func _show_dice_test(lr: Dictionary, context: String) -> void:
	var pop := DICE_POPUP.instantiate()
	add_child(pop)
	await pop.run_test({
		"context": context,
		"faces": lr.faces, "total": int(lr.total),
		"compare_label": "≤ LUCK %d" % int(lr.target),
		"banner": "LUCKY!" if lr.lucky else "UNLUCKY",
		"banner_color": FFUI.VERDIGRIS if lr.lucky else FFUI.ARREARS,
		"depletion": "LUCK %d → %d  (−1)" % [int(lr.luck_before), int(lr.luck_after)],
		"quick": _quick,
		"reduced_motion": _reduced(), "speed": _dice_speed(),
	})
	pop.queue_free()


## Dice preferences from Options (Dice / Accessibility), guarded so combat still
## runs if FFSettings isn't present.
func _reduced() -> bool:
	var ff := get_node_or_null("/root/FFSettings")
	return ff != null and (ff.reduced_motion or not ff.dice_animation)


func _use_3d() -> bool:
	if _reduced():
		return false
	if DisplayServer.get_name() == "headless":
		return false
	var ff := get_node_or_null("/root/FFSettings")
	return ff != null and bool(ff.dice_3d)


func _dice_speed() -> float:
	var ff := get_node_or_null("/root/FFSettings")
	return ff.dice_speed if ff != null else 1.0


# --- flow ------------------------------------------------------------------


func _finish_turn() -> void:
	_busy = false
	_set_actions_enabled(true)
	if _quick:
		_auto_run()


func _auto_run() -> void:
	# Quick Combat: keep attacking until win/loss/escape.
	if _busy or Adventure.sheet.is_dead() or _all_defeated():
		return
	await get_tree().create_timer(0.15).timeout
	_on_attack()


func _set_actions_enabled(on: bool) -> void:
	for c in _actions.get_children():
		if c is BaseButton:
			c.disabled = not on
	if on:
		_build_actions()


func _append_log(line: String) -> void:
	_log_lines.append(line)
	var text := ""
	for i in _log_lines.size():
		text += "— " + _log_lines[i] + "\n"
	_log.text = text
	if _log_scroll != null:
		await get_tree().process_frame
		_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _end(outcome_id: String, closing: String) -> void:
	_append_log("[b]%s[/b]" % closing)
	await get_tree().create_timer(0.2 if _quick else 0.5).timeout
	resolved.emit(outcome_id)


## Ruled ledger paper for the round log: faint rule lines + a red margin rule.
class _LedgerBox extends MarginContainer:
	func _init() -> void:
		add_theme_constant_override(&"margin_left", 40)
		add_theme_constant_override(&"margin_right", 10)
		add_theme_constant_override(&"margin_top", 6)
		add_theme_constant_override(&"margin_bottom", 6)

	func _draw() -> void:
		var rule := Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.25)
		var y := 27.0
		while y < size.y - 2.0:
			draw_line(Vector2(6, y), Vector2(size.x - 6, y), rule, 1.0)
			y += 27.0
		draw_line(Vector2(30, 2), Vector2(30, size.y - 2),
			Color(FFUI.ARREARS.r, FFUI.ARREARS.g, FFUI.ARREARS.b, 0.30), 1.0)
