extends Control
## res://scripts/screens/combat_view.gd
## The Combat Screen (WIREFRAMES 5.4, GDD §6.1 #7) — resolves an encounter round by
## round over the faithful FF rules core (FFCombat, seeded IFDice), staying
## engine-authoritative: every wound routes through FFAdventureSheet.apply_delta and
## every die is the one the seeded core rolled (shown honestly via the Dice overlay).
##
## Features: enemy panel(s) with portrait + SKILL + STAMINA bar (multi-enemy rows +
## target select); player stat strip; a round-resolution area with both Attack
## Strengths + totals + a scrolling log; action buttons (Attack / Test Luck /
## Escape / Use Item / Eat); Luck-in-combat prompts after a wound; a Quick Combat
## toggle that auto-runs rounds. On resolution it emits `resolved(outcome_id)` and
## the reading view routes via Adventure.choose (which applies effects + goto).

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
var _player_strip: Label
var _round_head: Label
var _round_you: Label
var _round_foe: Label
var _log: RichTextLabel
var _actions: HBoxContainer
var _luck_bar: HBoxContainer


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
	_append_log("[i]The encounter is joined.[/i]")
	# combat music stinger (STYLE_GUIDE §2.2) — the Reckoner's own tragic bed on the
	# boss fight, the grim combat bed otherwise.
	AudioDirector.play_music("boss" if _section_no == "s_reckoner_fight" else "combat")


func _build() -> void:
	add_child(FFUI.page_background(true))        # dark combat bed
	add_child(FFUI.wash(FFUI.SLATE, 0.28))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 12)
	margin.add_child(root)

	# top bar
	var top := HBoxContainer.new()
	var t := FFUI.title("§%s   COMBAT" % _section_no, 22, FFUI.PARCHMENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var qc := CheckButton.new()
	qc.text = "Quick Combat"
	qc.add_theme_color_override(&"font_color", FFUI.PARCHMENT)
	# seed from the Options → Combat preference (live per-fight toggle still overrides)
	var ff := get_node_or_null("/root/FFSettings")
	if ff != null:
		_quick = ff.quick_combat
		qc.button_pressed = _quick
	qc.toggled.connect(_on_quick_toggled)
	top.add_child(qc)
	root.add_child(top)

	# two columns
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# left: enemies + player
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	_enemy_box = VBoxContainer.new()
	_enemy_box.add_theme_constant_override(&"separation", 8)
	left.add_child(_enemy_box)
	var pl := FFUI.panel(Color("2a3330"), FFUI.VERDIGRIS)
	var plc := VBoxContainer.new()
	plc.add_child(FFUI.label("YOU", 15, FFUI.VERDIGRIS_2, false))
	_player_strip = FFUI.label("", 18, FFUI.PARCHMENT)
	plc.add_child(_player_strip)
	pl.add_child(plc)
	left.add_child(pl)

	# right: round resolution + log
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rr := FFUI.panel(Color("241f19"), FFUI.UMBER)
	var rrc := VBoxContainer.new()
	rrc.add_theme_constant_override(&"separation", 4)
	_round_head = FFUI.label("ROUND 1", 18, FFUI.FLAME, false)
	rrc.add_child(_round_head)
	_round_you = FFUI.label("You    —", 17, FFUI.PARCHMENT)
	_round_foe = FFUI.label("Enemy  —", 17, FFUI.PARCHMENT)
	rrc.add_child(_round_you)
	rrc.add_child(_round_foe)
	rr.add_child(rrc)
	right.add_child(rr)

	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var log_panel := FFUI.panel(Color("1c1814"), FFUI.UMBER)
	_log = FFUI.rich(15, FFUI.PARCHMENT)
	_log.add_theme_color_override(&"default_color", Color(0.86, 0.82, 0.72))
	log_panel.add_child(_log)
	log_scroll.add_child(log_panel)
	right.add_child(log_scroll)

	# luck-in-combat prompt bar (hidden until offered)
	_luck_bar = HBoxContainer.new()
	_luck_bar.add_theme_constant_override(&"separation", 10)
	_luck_bar.visible = false
	root.add_child(_luck_bar)

	# action buttons
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override(&"separation", 10)
	root.add_child(_actions)
	_build_actions()


func _build_actions() -> void:
	for c in _actions.get_children():
		c.queue_free()
	var attack := FFUI.chip("⚔  Attack")
	attack.custom_minimum_size = Vector2(0, 56)
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
	# enemy panels
	for c in _enemy_box.get_children():
		c.queue_free()
	for i in _enemies.size():
		_enemy_box.add_child(_enemy_panel(i))
	# player strip
	var s := Adventure.sheet
	_player_strip.text = "SKILL %d    STAMINA %d/%d    LUCK %d/%d" % [
		s.cur("skill"), s.cur("stamina"), s.init_of("stamina"), s.cur("luck"), s.init_of("luck")]


func _enemy_panel(index: int) -> Control:
	var e: Dictionary = _enemies[index]
	var alive := int(e.get("stamina", 0)) > 0
	var panel := FFUI.panel(Color("2a2119") if alive else Color("1a1614"), FFUI.ARREARS if index == _target and alive else FFUI.UMBER)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	panel.add_child(row)
	var port := FFUI.portrait_panel(FFUI.portrait(_portrait_name(e)), 110, FFUI.VERDIGRIS if alive else FFUI.FEN)
	if not alive:
		port.modulate = Color(0.5, 0.5, 0.5)
	row.add_child(port)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 4)
	info.add_child(FFUI.label(str(e.get("name", "Foe")), 19, FFUI.PARCHMENT if alive else FFUI.FEN, false))
	info.add_child(FFUI.label("SKILL %d" % int(e.get("skill", 0)), 15, FFUI.VERDIGRIS_2))
	info.add_child(FFUI.stat_bar("STAMINA", int(e.get("stamina", 0)), int(e.get("stamina_max", 1)), FFUI.ARREARS))
	if not alive:
		info.add_child(FFUI.label("— dispersed —", 14, FFUI.FEN))
	elif _enemies.size() > 1:
		var pick := FFUI.chip("Target" if index != _target else "◈ Target")
		pick.pressed.connect(func() -> void: _target = index; _refresh())
		info.add_child(pick)
	row.add_child(info)
	return panel


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

	# dramatize with the honest dice overlay
	var banner := "PARRIED — no blood drawn"
	var bcolor := FFUI.FEN
	match str(res.outcome):
		"player_wounds":
			banner = "You wound the %s  (−%d)" % [enemy.get("name"), int(res.wound)]
			bcolor = FFUI.VERDIGRIS
		"enemy_wounds":
			banner = "The %s wounds you  (−%d)" % [enemy.get("name"), int(res.wound)]
			bcolor = FFUI.ARREARS
	await _show_dice_combat(res, enemy, banner, bcolor)

	# round resolution maps 1:1 to audio (STYLE_GUIDE §2.3): hit on a wound dealt,
	# a fleshy wound-thud when struck, a distinct parry ring on a tie. Ducks music.
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

	_round_head.text = "ROUND %d" % _round_no()
	_round_you.text = "You     2d6=%d  +SK %d = %d" % [int(res.player_faces[0]) + int(res.player_faces[1]), Adventure.sheet.cur("skill"), int(res.player_total)]
	_round_foe.text = "%s   2d6=%d  +SK %d = %d" % [enemy.get("name"), int(res.enemy_faces[0]) + int(res.enemy_faces[1]), int(enemy.get("skill")), int(res.enemy_total)]
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


## Resolve one round with NO dice overlay — used by the screenshot harness so the
## enemy panel + round-resolution area are visible together. Same math path.
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
	_round_you.text = "You     2d6=%d  +SK %d = %d" % [int(res.player_faces[0]) + int(res.player_faces[1]), Adventure.sheet.cur("skill"), int(res.player_total)]
	_round_foe.text = "%s   2d6=%d  +SK %d = %d" % [enemy.get("name"), int(res.enemy_faces[0]) + int(res.enemy_faces[1]), int(enemy.get("skill")), int(res.enemy_total)]
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
	_luck_bar.add_child(FFUI.label(prompt, 16, FFUI.FLAME))
	var yes := FFUI.chip("Yes — Test Luck")
	yes.pressed.connect(_on_luck_yes)
	_luck_bar.add_child(yes)
	var no := FFUI.chip("No")
	no.pressed.connect(func() -> void: _luck_bar.visible = false; _pending_luck = ""; _finish_turn())
	_luck_bar.add_child(no)
	yes.grab_focus()


func _on_luck_yes() -> void:
	_luck_bar.visible = false
	var before := Adventure.sheet.cur("luck")
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


# --- dice overlay helpers --------------------------------------------------


func _show_dice_combat(res: Dictionary, enemy: Dictionary, banner: String, bcolor: Color) -> void:
	var pop := DICE_POPUP.instantiate()
	add_child(pop)
	await pop.run_combat({
		"context": "ROUND %d" % _round_no(),
		"you": {"faces": res.player_faces, "total": int(res.player_total), "label": "+SK %d" % Adventure.sheet.cur("skill")},
		"enemy": {"name": str(enemy.get("name", "Foe")), "faces": res.enemy_faces, "total": int(res.enemy_total), "label": "+SK %d" % int(enemy.get("skill"))},
		"banner": banner, "banner_color": bcolor, "quick": _quick,
		"reduced_motion": _dice_reduced(), "speed": _dice_speed(),
	})
	pop.queue_free()


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
		"reduced_motion": _dice_reduced(), "speed": _dice_speed(),
	})
	pop.queue_free()


## Dice preferences from Options (Dice / Accessibility), guarded so combat still runs
## if FFSettings isn't present.
func _dice_reduced() -> bool:
	var ff := get_node_or_null("/root/FFSettings")
	return ff != null and (ff.reduced_motion or not ff.dice_animation)

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
	_log.text = ""
	for l in _log_lines:
		_log.text += "• " + l + "\n"


func _end(outcome_id: String, closing: String) -> void:
	_append_log("[b]%s[/b]" % closing)
	await get_tree().create_timer(0.2 if _quick else 0.5).timeout
	resolved.emit(outcome_id)
