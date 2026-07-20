extends CanvasLayer
## res://scripts/dice_roll_popup.gd
## The Dice-Roll Overlay (WIREFRAMES 5.3 / GDD §6.6) — the honest, dramatized dice.
## It dims the page and presents a roll the SEEDED rules core already made
## (Adventure.test_luck / test_attribute / FFCombat.attack_round). It NEVER rolls
## its own dice and NEVER hides a result: it animates real pips (FFDie) settling on
## the rolled faces, shows the modifier math explicitly ("2d6=7  +SKILL 9 = 16" /
## "2d6=7  ≤ LUCK 7"), a colour+text outcome banner (LUCKY!/UNLUCKY/wounded), and
## LUCK depletion. Quick/auto mode flashes the result and auto-advances; reduced-
## motion snaps the pips instantly. Built in code so the scene stays a bare layer.
##
##   run_test({context, faces, total, compare_label, band, banner, banner_color,
##             depletion?, quick?, reduced_motion?})            # 1 group of 2 dice
##   run_combat({context, you:{faces,total,label}, enemy:{name,faces,total,label},
##             banner, banner_color, quick?, reduced_motion?})  # 2 groups

signal finished

const TUMBLE_TIME := 0.75
const TUMBLE_TICK := 0.05

var _root: Control
var _panel: PanelContainer
var _context: Label
var _dice_row: HBoxContainer          # test-mode dice
var _combat_box: VBoxContainer        # combat-mode two rows
var _math: Label
var _banner: Label
var _deplete: Label
var _continue: Button
var _dice: Array[FFDie] = []
var _quick := false
var _reduced := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.03, 0.62)
	add_child(dim)

	_root = CenterContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_panel = FFUI.framed_panel(FFUI.VERDIGRIS)
	_panel.custom_minimum_size = Vector2(460, 0)
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(col)

	_context = FFUI.title("", 22, FFUI.INK)
	col.add_child(_context)

	_dice_row = HBoxContainer.new()
	_dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_row.add_theme_constant_override(&"separation", 16)
	col.add_child(_dice_row)

	_combat_box = VBoxContainer.new()
	_combat_box.add_theme_constant_override(&"separation", 10)
	col.add_child(_combat_box)

	_math = FFUI.label("", 18, FFUI.UMBER)
	_math.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_math)

	_banner = FFUI.title("", 26, FFUI.VERDIGRIS)
	col.add_child(_banner)

	_deplete = FFUI.label("", 16, FFUI.ARREARS)
	_deplete.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_deplete)

	_continue = FFUI.chip("Tap to continue")
	_continue.custom_minimum_size = Vector2(0, 48)
	col.add_child(_continue)


func _make_dice(container: Node, count: int) -> Array[FFDie]:
	for c in container.get_children():
		c.queue_free()
	var out: Array[FFDie] = []
	for i in count:
		var d := FFDie.new()
		d.custom_minimum_size = Vector2(72, 72)
		container.add_child(d)
		out.append(d)
	return out


# --- Test-your-X (single 2d6 roll-under) -----------------------------------


func run_test(p: Dictionary) -> void:
	_quick = bool(p.get("quick", false))
	_reduced = bool(p.get("reduced_motion", false))
	_combat_box.visible = false
	_dice_row.visible = true
	_context.text = str(p.get("context", "TEST YOUR LUCK"))
	var faces: Array = p.get("faces", [3, 4])
	_dice = _make_dice(_dice_row, faces.size())
	_math.visible = false
	_banner.visible = false
	_deplete.visible = false
	_continue.visible = false

	await _tumble(_dice, faces)

	_math.text = "2d6 = %d   %s" % [int(p.get("total", 0)), str(p.get("compare_label", ""))]
	_math.visible = true
	_banner.text = str(p.get("banner", ""))
	_banner.add_theme_color_override(&"font_color", p.get("banner_color", FFUI.VERDIGRIS))
	_banner.visible = true
	var pip: Color = p.get("banner_color", FFUI.INK)
	for d in _dice:
		d.pip_color = pip
	if str(p.get("depletion", "")) != "":
		_deplete.text = str(p["depletion"])
		_deplete.visible = true
	await _await_dismiss()


# --- Combat round (two 2d6+SKILL groups) -----------------------------------


func run_combat(p: Dictionary) -> void:
	_quick = bool(p.get("quick", false))
	_reduced = bool(p.get("reduced_motion", false))
	_dice_row.visible = false
	_combat_box.visible = true
	_context.text = str(p.get("context", "COMBAT"))
	_math.visible = false
	_banner.visible = false
	_deplete.visible = false
	_continue.visible = false

	for c in _combat_box.get_children():
		c.queue_free()
	var you: Dictionary = p.get("you", {})
	var foe: Dictionary = p.get("enemy", {})
	var you_dice := _combat_group("You", you)
	var foe_dice := _combat_group(str(foe.get("name", "Foe")), foe)
	# tumble both groups together
	await _tumble(you_dice + foe_dice, (you.get("faces", []) as Array) + (foe.get("faces", []) as Array))

	_banner.text = str(p.get("banner", ""))
	_banner.add_theme_color_override(&"font_color", p.get("banner_color", FFUI.INK))
	_banner.visible = true
	await _await_dismiss()


func _combat_group(who: String, g: Dictionary) -> Array[FFDie]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_l := FFUI.label(who, 16, FFUI.UMBER)
	name_l.custom_minimum_size = Vector2(96, 0)
	row.add_child(name_l)
	var dice: Array[FFDie] = []
	for _i in (g.get("faces", [3, 4]) as Array).size():
		var d := FFDie.new()
		d.custom_minimum_size = Vector2(52, 52)
		row.add_child(d)
		dice.append(d)
	var total_l := FFUI.label("= %d" % int(g.get("total", 0)), 20, FFUI.INK)
	total_l.add_theme_font_override(&"font", FFUI.font_display())
	var mod_l := FFUI.label(str(g.get("label", "")), 14, FFUI.UMBER)
	row.add_child(mod_l)
	row.add_child(total_l)
	_combat_box.add_child(row)
	return dice


# --- shared animation + dismissal ------------------------------------------


func _tumble(dice: Array[FFDie], final_faces: Array) -> void:
	# The sacred dice (STYLE_GUIDE §2.2): bone-clatter shake while tumbling, pips
	# landing on the settle, and the music ducks under the roll — the roll is the
	# moment nothing competes with. Reduced-motion snaps straight to the landing.
	if _reduced:
		_settle(dice, final_faces)
		AudioDirector.play_sfx("dice_land", true)
		return
	AudioDirector.play_sfx("dice_shake", true)
	var elapsed := 0.0
	while elapsed < TUMBLE_TIME:
		for d in dice:
			d.value = randi_range(1, 6)
		var tick := TUMBLE_TICK * (1.0 + 3.0 * elapsed / TUMBLE_TIME)
		await get_tree().create_timer(tick).timeout
		elapsed += tick
	_settle(dice, final_faces)
	AudioDirector.play_sfx("dice_land")


func _settle(dice: Array[FFDie], final_faces: Array) -> void:
	for i in dice.size():
		dice[i].value = int(final_faces[i]) if i < final_faces.size() else 6


func _await_dismiss() -> void:
	if _quick:
		await get_tree().create_timer(0.35).timeout
		finished.emit()
		return
	_continue.visible = true
	_continue.grab_focus()   # focused button: Space/Enter/gamepad-A also continue
	await _continue.pressed
	finished.emit()
