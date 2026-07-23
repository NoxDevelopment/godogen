extends Node
## res://_probes/qa_probe.gd
## Phase-8 INTERACTIVE playtest + hardening probe (windowed; needs a render context).
## Boots EVERY interactive screen/overlay into a real 1280x720 SubViewport, drives the
## interactive paths, and audits each state for the bug CLASS the user keeps hitting:
##   * CRASH on interaction (a runtime/script error aborts the run -> fails);
##   * a BaseButton clipped OFF-SCREEN with no ScrollContainer ancestor (the death/
##     victory "unreachable button" class) -> logged as an offscreen issue;
##   * a visible enabled BaseButton with NO signal wiring (pressed/toggled/
##     item_selected) -> logged as an unwired issue.
## Screenshots each screen into _probes/shots/qa_*.png so clipping can be eyeballed.
## Run: godot --path <skeleton> res://_probes/qa_probe.tscn   (windowed, NOT headless)

const OUT := "res://_probes/shots/"
const VP := Vector2(1280, 720)

const ROLL_UP := preload("res://scripts/screens/roll_up.tscn")
const READING := preload("res://scenes/reading_view.tscn")
const COMBAT := preload("res://scripts/screens/combat_view.tscn")
const SHEET := preload("res://scripts/screens/adventure_sheet.tscn")
const INV := preload("res://scripts/screens/inventory_view.tscn")
const MAP := preload("res://scripts/screens/map_view.tscn")
const DEATH := preload("res://scripts/screens/death_screen.tscn")
const VICTORY := preload("res://scripts/screens/victory_screen.tscn")
const OPTIONS := preload("res://scripts/screens/options_view.gd")
const PAUSE := preload("res://addons/nox_ui/scenes/pause_menu.tscn")
const MAIN_MENU := preload("res://addons/nox_ui/scenes/main_menu.tscn")
const LOAD_SCREEN := preload("res://addons/loading/load_screen.tscn")
const DICE := preload("res://scenes/dice_roll_popup.tscn")

var _vp: SubViewport
var issues: Array[String] = []
var notes: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	# faithful reduced/quick so animated overlays snap + auto-advance (bounded timing).
	# TRANSIENT direct assignment ONLY — never the set_*() setters: those _commit() to
	# user://ff_settings.cfg, which is SHARED with a real install, and once poisoned the
	# shipped DEFAULT experience (2D snap dice for a real player). See ff_settings.gd.
	if FFSettings != null:
		FFSettings.reduced_motion = true
		FFSettings.dice_animation = false
		FFSettings.dice_speed = 2.0

	await _t(2)
	await _run()

	print("DEBUG: qa_probe INTERACTIVE — %s" % " ".join(notes))
	if issues.is_empty():
		print("DEBUG: qa_probe issues=0 — ALL SCREENS CLEAN")
	else:
		print("DEBUG: qa_probe issues=%d" % issues.size())
		for i in issues:
			print("DEBUG:   ISSUE: %s" % i)
	get_tree().quit(0 if issues.is_empty() else 2)


func _run() -> void:
	# ---- MAIN MENU ---------------------------------------------------------
	# seed a save so Continue is visible + Load has a slot
	Adventure.new_adventure(20260719)
	Adventure.choose("causeway")
	SaveManager.save_to_slot(1, SaveManager.capture_current())
	var menu := _mount(MAIN_MENU.instantiate())
	await _t(6)
	_audit("main_menu", menu)
	_expect_btn(menu, ["New Game", "New"], "main_menu:New")
	_expect_btn(menu, ["Continue"], "main_menu:Continue (save present)")
	_expect_btn(menu, ["Options"], "main_menu:Options")
	_expect_btn(menu, ["Credits"], "main_menu:Credits")
	_expect_btn(menu, ["Quit"], "main_menu:Quit")
	# open Options overlay from the menu (in-scene, safe)
	menu.add_child(OPTIONS.new())
	await _t(6)
	_audit("main_menu+options", menu)
	await _shoot("qa_00_menu")
	# drive every Options tab so each tab body lays out + audits
	var opt := _find_options(menu)
	if opt != null:
		var tc := _find(opt, "TabContainer") as TabContainer
		if tc != null:
			for i in tc.get_tab_count():
				tc.current_tab = i
				await _t(3)
				_audit("options:tab%d" % i, opt)
			await _shoot("qa_01_options")
	# Load slot picker from the menu
	var ls := LOAD_SCREEN.instantiate()
	ls.mode = 0
	menu.add_child(ls)
	await _t(6)
	_audit("load_picker", menu)
	_expect_btn(menu, ["Load"], "load_picker:Load slot btn")
	_expect_btn(menu, ["BACK", "Back"], "load_picker:Back")
	await _shoot("qa_02_load")
	_clear()

	# ---- ROLL-UP -----------------------------------------------------------
	Adventure.new_adventure(20260719)
	var ru := _mount(ROLL_UP.instantiate())
	await _wait_rolled(ru)   # deterministic: frame counts race the 0.06s pen timers
	_audit("rollup", ru)
	# Begin must start DISABLED (no potion picked)
	if not _begin_disabled(ru):
		issues.append("rollup: Begin not disabled before a potion is chosen")
	# pick EACH potion, then settle on skill
	for pid in ["skill", "strength", "fortune"]:
		ru._select_potion(pid)
		await _t(2)
	# settings-reroll
	ru._on_reroll()
	await _wait_rolled(ru)
	ru._select_potion("skill")
	await _t(2)
	if _begin_disabled(ru):
		issues.append("rollup: Begin still disabled after choosing a potion + roll settled")
	_audit("rollup+chosen", ru)
	await _shoot("qa_03_rollup")
	_clear()

	# ---- READING VIEW ------------------------------------------------------
	Adventure.new_adventure(20260719)
	Adventure.sheet.potion = {"type": "skill", "doses": 2}
	var rv := _mount(READING.instantiate())
	await _t(8)
	_audit("reading", rv)
	# HUD quick-buttons -> overlays (in-scene, safe): Sheet / Inventory / Map
	rv._open_sheet(); await _t(6); _audit("reading+sheet", rv)
	_close_overlays(rv)
	rv._open_inventory(); await _t(6); _audit("reading+inventory", rv)
	_close_overlays(rv)
	rv._open_map(); await _t(6); _audit("reading+map", rv)
	_close_overlays(rv)
	# bookmark + quick-save (safe)
	rv._toggle_bookmark(); await _t(2)
	rv._quick_save(); await _t(2)
	# Eat a Provision (safe)
	rv._on_eat(); await _t(3)
	# pause toggle (safe overlay)
	rv._open_pause(); await _t(6); _audit("reading+pause", rv)
	await _shoot("qa_04_reading")
	rv._open_pause()  # close pause
	await _t(3)
	# advance a page: pick the first real choice via the engine (stays in reading view)
	var walked := _advance_one(rv)
	await _t(6)
	_audit("reading:page2", rv)
	notes.append("reading_advanced=%s" % walked)
	await _shoot("qa_05_reading_p2")
	_clear()

	# ---- DICE OVERLAY (Test-your-Luck + Test-your-Skill via reading) -------
	await _dice_test("luck")
	await _dice_test("skill")

	# ---- COMBAT ------------------------------------------------------------
	await _combat_boot_and_actions()
	await _combat_outcome(true)    # WIN
	await _combat_outcome(false)   # LOSS

	# ---- ADVENTURE SHEET (standalone, tap-to-drink) ------------------------
	Adventure.new_adventure(20260719)
	Adventure.sheet.potion = {"type": "strength", "doses": 2}
	Adventure.sheet.apply_delta({"stamina": -6})
	var sh := _mount_layer(SHEET.instantiate())
	await _t(8)
	_audit("sheet", sh)
	# tap-to-drink potion (safe) — find the chip and press it
	var drink := _find_button_by_text(sh, ["tap to drink"])
	if drink != null:
		drink.pressed.emit(); await _t(4)
		notes.append("sheet_potion_drank=%d" % int(Adventure.sheet.potion.get("doses", -1)))
	else:
		issues.append("sheet: 'tap to drink' potion button not found")
	_audit("sheet+drank", sh)
	await _shoot("qa_08_sheet")
	_clear()

	# ---- INVENTORY (drink / read quest item / drop) ------------------------
	Adventure.new_adventure(20260719)
	Adventure.sheet.potion = {"type": "fortune", "doses": 2}
	Adventure.sheet.add_item("silver_key")     # quest item (lock-protected)
	Adventure.sheet.add_item("rope")           # mundane (droppable)
	var iv := _mount_layer(INV.instantiate())
	await _t(8)
	_audit("inventory", iv)
	# select + read the quest item (must offer Read, must NOT offer Drop)
	iv._select("silver_key"); await _t(4)
	_audit("inventory:quest", iv)
	if _find_button_by_text(iv, ["Drop"]) != null:
		issues.append("inventory: quest item 'silver_key' offered a Drop button (lock broken)")
	var readb := _find_button_by_text(iv, ["Read / Examine", "Read"])
	if readb != null:
		readb.pressed.emit(); await _t(4)
	else:
		issues.append("inventory: quest item did not offer Read/Examine")
	# select the mundane item -> Drop it
	iv._select("rope"); await _t(4)
	var dropb := _find_button_by_text(iv, ["Drop"])
	if dropb != null:
		dropb.pressed.emit(); await _t(4)
		notes.append("inventory_dropped_rope=%s" % (not Adventure.sheet.state.inventory().has("rope")))
	else:
		issues.append("inventory: mundane item 'rope' offered no Drop")
	# drink the potion from the picker
	iv._select("__potion"); await _t(4)
	var idrink := _find_button_by_text(iv, ["Drink a dose"])
	if idrink != null:
		idrink.pressed.emit(); await _t(4)
	else:
		issues.append("inventory: potion 'Drink a dose' not found")
	_audit("inventory+used", iv)
	await _shoot("qa_09_inventory")
	_clear()

	# ---- MAP (standalone; toggle Travel toast) -----------------------------
	Adventure.new_adventure(20260719)
	Adventure.choose("causeway")
	var mv := _mount_layer(MAP.instantiate())
	await _t(8)
	_audit("map", mv)
	var travel := _find_button_by_text(mv, ["Travel"])
	if travel != null:
		travel.pressed.emit(); await _t(4)
	await _shoot("qa_10_map")
	_clear()

	# ---- DEATH SCREEN (pinned footer must be on-screen) --------------------
	Adventure.new_adventure(20260719)
	Adventure.choose("reeds")   # instant-death terminal
	var ds := _mount(DEATH.instantiate())
	await _t(8)
	_audit("death", ds)
	_expect_btn(ds, ["Restart"], "death:Restart")
	_expect_btn(ds, ["Load"], "death:Load")
	_expect_btn(ds, ["Return to the menu", "Menu"], "death:Menu")
	await _shoot("qa_11_death")
	_clear()

	# ---- VICTORY SCREEN (pinned footer) ------------------------------------
	Adventure.new_adventure(20260719)
	_walk_golden()
	var win_ok := Adventure.is_ended() and str(Adventure.ending().get("kind", "")) == "victory"
	notes.append("victory_reached=%s" % win_ok)
	var vs := _mount(VICTORY.instantiate())
	await _t(8)
	_audit("victory", vs)
	_expect_btn(vs, ["New Adventure", "New"], "victory:New")
	_expect_btn(vs, ["Library"], "victory:Library")
	_expect_btn(vs, ["Menu"], "victory:Menu")
	await _shoot("qa_12_victory")
	_clear()

	# ---- PAUSE MENU (standalone, all buttons) ------------------------------
	Adventure.new_adventure(20260719)
	var pm := _mount_layer(PAUSE.instantiate())
	pm.call("toggle")   # show it
	await _t(6)
	_audit("pause", pm)
	_expect_btn(pm, ["Resume"], "pause:Resume")
	_expect_btn(pm, ["Options"], "pause:Options")
	_expect_btn(pm, ["Save"], "pause:Save")
	_expect_btn(pm, ["Menu"], "pause:Quit-to-menu")
	# open Save picker from pause (SAVE mode)
	pm.call("_on_save_pressed")
	await _t(6)
	_audit("pause+save_picker", pm)
	var savebtn := _find_button_by_text(pm, ["Save", "Overwrite"])
	if savebtn != null:
		savebtn.pressed.emit(); await _t(4)   # write a slot (safe)
	await _shoot("qa_13_pause")
	_clear()

	SaveManager.delete_slot(1)


# ============================================================================
# interactive helpers
# ============================================================================

func _dice_test(stat: String) -> void:
	Adventure.new_adventure(20260719)
	Adventure.sheet.potion = {"type": "skill", "doses": 2}
	# jump to a section carrying the wanted event
	var target := _find_event_section(stat)
	if target == "":
		notes.append("dice_%s=no_section" % stat)
		return
	Adventure.jump_to(target)
	var rv := _mount(READING.instantiate())
	await _t(8)
	# reading view auto-renders the test chip; press it
	var chip := _find_button_by_text(rv, ["Test your"])
	if chip == null:
		notes.append("dice_%s=no_chip@%s" % [stat, target])
		_clear(); return
	chip.pressed.emit()
	# bounded wait for the dice popup, then press "Tap to continue"
	var popped := false
	for _i in 240:
		await _t(1)
		var cont := _find_button_by_text(rv, ["Tap to continue"])
		if cont != null and cont.is_visible_in_tree():
			_audit("dice_%s" % stat, rv)
			await _shoot("qa_06_dice_%s" % stat if stat == "luck" else "qa_07_dice_%s" % stat)
			cont.pressed.emit()
			popped = true
			break
	await _t(6)
	notes.append("dice_%s=%s" % [stat, "ok" if popped else "NO_POPUP"])
	if not popped:
		issues.append("dice: %s test never showed the dice overlay / continue button" % stat)
	_clear()


func _combat_boot_and_actions() -> void:
	Adventure.new_adventure(20260719)
	Adventure.sheet.potion = {"type": "skill", "doses": 2}
	var sec := _find_combat_section()
	if sec == "":
		issues.append("combat: no combat section found in scenario")
		return
	Adventure.jump_to(sec)
	var cv := COMBAT.instantiate()
	cv.setup(FFEncounter.from_passage(Adventure.current_section().raw()),
		{"win": "_onwin", "death": "_ondeath", "escape": "_onescape"}, sec)
	_mount(cv)
	await _t(8)
	_audit("combat", cv)
	# All action buttons present + wired
	for want in ["Attack", "Test Luck", "Use Item", "Eat"]:
		_expect_btn(cv, [want], "combat:%s" % want)
	# deterministic round (no overlay) to fill the round area + log
	cv.debug_resolve_round(); await _t(3)
	cv.debug_resolve_round(); await _t(3)
	_audit("combat:mid", cv)
	await _shoot("qa_08a_combat")
	# Use Item overlay (opens inventory in combat context) — safe
	cv._on_use_item(); await _t(6)
	_audit("combat+useitem", cv)
	_close_overlays(cv)
	# Eat (safe)
	cv._on_eat(); await _t(3)
	# a REAL animated attack round through the dice overlay (reduced -> snaps)
	cv._on_attack()
	for _i in 180:
		await _t(1)
		var cont := _find_button_by_text(cv, ["Tap to continue"])
		if cont != null and cont.is_visible_in_tree():
			cont.pressed.emit()
			break
	await _t(6)
	notes.append("combat_boot=ok")
	_clear()


func _combat_outcome(want_win: bool) -> void:
	Adventure.new_adventure(20260719)
	Adventure.sheet.potion = {"type": "skill", "doses": 2}
	var sec := _find_combat_section()
	if sec == "":
		return
	Adventure.jump_to(sec)
	var cv := COMBAT.instantiate()
	cv.setup(FFEncounter.from_passage(Adventure.current_section().raw()),
		{"win": "_onwin", "death": "_ondeath", "escape": "_onescape"}, sec)
	# stack the deck deterministically
	if want_win:
		var weak: Array[Dictionary] = [FFCombat.make_enemy("Straw Foe", 1, 1)]
		cv._enemies = weak
	else:
		var strong: Array[Dictionary] = [FFCombat.make_enemy("Reckoner", 12, 30)]
		cv._enemies = strong
		Adventure.sheet.apply_delta({"stamina": -(Adventure.sheet.cur("stamina") - 2)})
	var got := {"id": ""}
	cv.resolved.connect(func(oid: String) -> void: got.id = oid)
	_mount(cv)
	await _t(6)
	# quick auto-run to resolution (reduced+quick already set)
	cv._on_quick_toggled(true)
	var resolved := false
	for _i in 900:
		await _t(1)
		# press any lingering dice-continue (quick auto-dismisses, but be safe)
		var cont := _find_button_by_text(cv, ["Tap to continue"])
		if cont != null and cont.is_visible_in_tree():
			cont.pressed.emit()
		if got.id != "":
			resolved = true
			break
	var kind := "win" if want_win else "loss"
	if not resolved:
		issues.append("combat:%s never emitted resolved() (auto-run stalled)" % kind)
	else:
		var oid := str(got.id)
		var expect_win := oid.begins_with("_onwin")
		var expect_death := oid.begins_with("_ondeath")
		if want_win and not expect_win:
			issues.append("combat:WIN resolved with '%s' (expected _onwin)" % got.id)
		if (not want_win) and not expect_death:
			issues.append("combat:LOSS resolved with '%s' (expected _ondeath)" % got.id)
	notes.append("combat_%s=%s(%s)" % [kind, resolved, got.id])
	_clear()


# ============================================================================
# scenario helpers
# ============================================================================

func _advance_one(_rv: Node) -> bool:
	for ch in Adventure.available_choices():
		var cid := str(ch.get("id", ""))
		if cid.begins_with("_"):
			continue
		if Adventure.runner.state.conditions_met(ch.get("conditions", null)):
			Adventure.choose(cid)
			return true
	return false


func _walk_golden() -> void:
	var golden := ["shrine", "to_bridge", "pay_gold", "cross", "call_grissel",
		"to_ferrant", "buy_provisions", "leave", "to_grissel", "offer_provision",
		"back", "confess", "back", "to_odo", "ask_gently", "back",
		"descend", "go_on", "free_her", "release"]
	for cid in golden:
		var ok := false
		for ch in Adventure.available_choices():
			if str(ch.get("id", "")) == cid:
				ok = true; break
		if not ok:
			break
		Adventure.choose(cid)


func _find_event_section(stat: String) -> String:
	var want := "luck_test" if stat == "luck" else ("skill_test")
	var scen := Adventure.scenario
	if scen == null:
		return ""
	for pid in scen.passages.keys():
		var p: Dictionary = scen.passages[pid]
		if str(p.get("event", "")) == want:
			return str(pid)
		for ev in p.get("events", []):
			if ev is Dictionary and str(ev.get("kind", ev.get("type", ""))) == want:
				return str(pid)
	return ""


func _find_combat_section() -> String:
	var scen := Adventure.scenario
	if scen == null:
		return "s7"
	for pid in scen.passages.keys():
		var p: Dictionary = scen.passages[pid]
		if str(p.get("event", "")) == "combat":
			return str(pid)
		for ev in p.get("events", []):
			if ev is Dictionary and str(ev.get("kind", ev.get("type", ""))) == "combat":
				return str(pid)
	return "s7"


# ============================================================================
# audit + utilities
# ============================================================================

## Audit a mounted subtree for the bug class: offscreen-unreachable + unwired buttons.
func _audit(label: String, root: Node) -> void:
	var btns: Array[BaseButton] = []
	_gather_buttons(root, btns)
	# also audit any overlay CanvasLayers parented under the subviewport
	for extra in _vp.get_children():
		if extra != root:
			_gather_buttons(extra, btns)
	var count := 0
	for b in btns:
		if not is_instance_valid(b) or not b.is_visible_in_tree():
			continue
		count += 1
		var gr: Rect2 = b.get_global_rect()
		var sc := _scroll_ancestor(b)
		if sc == null:
			# not scrollable: the button must sit within the viewport
			var center := gr.get_center()
			if center.x < -8 or center.y < -8 or center.x > VP.x + 8 or center.y > VP.y + 8:
				issues.append("%s: button '%s' center %s is OFF-SCREEN (no scroll ancestor) — unreachable" % [
					label, _btext(b), str(center.round())])
		else:
			# scrollable: reachable ONLY on an axis the scroll can actually scroll.
			# A button clipped past the scroll rect on a DISABLED-scroll axis is unreachable.
			var sr: Rect2 = sc.get_global_rect()
			var h_off: bool = sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
			var v_off: bool = sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
			if h_off and (gr.position.x < sr.position.x - 8 or gr.end.x > sr.end.x + 8):
				issues.append("%s: button '%s' is CLIPPED horizontally inside a no-h-scroll ScrollContainer — unreachable" % [label, _btext(b)])
			if v_off and (gr.position.y < sr.position.y - 8 or gr.end.y > sr.end.y + 8):
				issues.append("%s: button '%s' is CLIPPED vertically inside a no-v-scroll ScrollContainer — unreachable" % [label, _btext(b)])
		# wiring check (enabled buttons only)
		if not b.disabled and not _is_wired(b):
			issues.append("%s: button '%s' is UNWIRED (no pressed/toggled/item_selected)" % [label, _btext(b)])
	notes.append("%s[btns=%d]" % [label, count])


func _gather_buttons(n: Node, out: Array[BaseButton]) -> void:
	if n is BaseButton:
		out.append(n)
	for c in n.get_children():
		_gather_buttons(c, out)


func _scroll_ancestor(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null


func _is_wired(b: BaseButton) -> bool:
	if b.pressed.get_connections().size() > 0:
		return true
	if b.toggled.get_connections().size() > 0:
		return true
	if b is OptionButton and (b as OptionButton).item_selected.get_connections().size() > 0:
		return true
	# a TabContainer's tab bar buttons are internal (no user signal) — treat as wired
	if b.get_parent() != null and b.get_parent().get_class() == "TabBar":
		return true
	return false


func _btext(b: BaseButton) -> String:
	if b is Button:
		var t := (b as Button).text
		return t if t.strip_edges() != "" else "<icon:%s>" % b.name
	return b.name


# ---- mounting --------------------------------------------------------------

func _mount(c: Node) -> Node:
	_vp.add_child(c)
	return c

func _mount_layer(c: Node) -> Node:
	# CanvasLayer overlays render into the subviewport when parented under it
	_vp.add_child(c)
	return c

func _clear() -> void:
	for c in _vp.get_children():
		c.queue_free()
	# let frees settle
	for _i in 3:
		if is_inside_tree():
			get_tree().process_frame

func _close_overlays(host: Node) -> void:
	# free CanvasLayer overlays (sheet/inventory/map/dice/pause) added under a screen
	for c in host.get_children():
		if c is CanvasLayer:
			c.queue_free()
	for c in _vp.get_children():
		if c is CanvasLayer:
			c.queue_free()


# ---- finders ---------------------------------------------------------------

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null

func _find_options(n: Node) -> Node:
	# options_view is a plain Control with a TabContainer inside
	for c in n.get_children():
		if _find(c, "TabContainer") != null and c is Control:
			return c
	return null

func _find_button_by_text(n: Node, needles: Array) -> BaseButton:
	var all: Array[BaseButton] = []
	_gather_buttons(n, all)
	for extra in _vp.get_children():
		if extra != n:
			_gather_buttons(extra, all)
	for b in all:
		if not is_instance_valid(b):
			continue
		var t := _btext(b)
		for nd in needles:
			if t.findn(str(nd)) >= 0:
				return b
	return null

func _expect_btn(root: Node, needles: Array, tag: String) -> void:
	var b := _find_button_by_text(root, needles)
	if b == null:
		issues.append("%s: expected a button matching %s — NOT FOUND" % [tag, str(needles)])
	elif not b.is_visible_in_tree():
		issues.append("%s: button found but NOT visible" % tag)
	elif not _is_wired(b) and not b.disabled:
		issues.append("%s: button present but UNWIRED" % tag)


func _begin_disabled(ru: Node) -> bool:
	var b := _find_button_by_text(ru, ["Begin"])
	return b != null and (b as BaseButton).disabled


# ---- frames + screenshots --------------------------------------------------

func _t(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame

## Wait until the roll-up's reveal-roll coroutine finishes (bounded). Headless frames
## are UNCAPPED, so counting frames races the roll's real-time 0.06s pen timers —
## polling the screen's own _rolling flag is the only deterministic settle.
func _wait_rolled(ru: Node, timeout_sec: float = 10.0) -> void:
	var waited := 0.0
	await _t(2)   # let the reveal coroutine actually start
	while bool(ru.get("_rolling")) and waited < timeout_sec:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05

func _shoot(name: String) -> void:
	for _i in 6:
		await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	notes.append("shot:%s" % name)
