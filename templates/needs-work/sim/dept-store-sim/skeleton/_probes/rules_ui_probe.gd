extends Node
## _probes/rules_ui_probe.gd
## RULES + UI + SAVE probe: illegal actions are rejected and leave meaningful state
## untouched (restock over cash / non-positive qty / invalid line, over-allocate staff,
## over-allocate floor space, an out-of-range markdown, liquidate more than on hand,
## over-borrow, repay with no debt); the main scene builds its code UI (a CanvasLayer +
## labels + buttons + sliders + option buttons); and the whole store round-trips through
## save/load unchanged, through both the engine and the GameManager ABI.

func _count_type(node: Node, cls: String, acc: Array) -> void:
	if node.is_class(cls):
		acc[0] += 1
	for c in node.get_children():
		_count_type(c, cls, acc)

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- illegal actions rejected + counter advances + state untouched ---
	var e: DeptStoreEngine = DeptStoreEngine.new()
	e.setup(20260716, {})
	# give the store some stock to make liquidate-overflow meaningful.
	e.restock(0, 5)
	var before_attempts: int = e.illegal_attempts
	var b_cash: int = e.cash
	var b_day: int = e.day
	var b_debt: int = e.debt
	var b_staff: int = e.total_staff()
	var b_space: int = e.total_space()
	var b_onhand: int = e.total_on_hand()
	var b_md: int = e.line_markdown_bp(0)

	# restock more than cash allows.
	var huge: int = e.cash / DeptStoreEngine.LINE_COST[0] + 1000
	if e.restock(0, huge):
		fails += 1
		notes.append("restock-overcash-allowed")
	# restock a non-positive quantity.
	if e.restock(0, 0):
		fails += 1
		notes.append("restock-zero-allowed")
	if e.restock(0, -5):
		fails += 1
		notes.append("restock-negative-allowed")
	# restock an invalid line.
	if e.restock(999, 1):
		fails += 1
		notes.append("restock-badline-allowed")

	# over-allocate STAFF past the total headcount cap.
	if e.set_dept_staff(0, e.max_staff_total + 5):
		fails += 1
		notes.append("staff-overmax-allowed")
	if e.set_dept_staff(0, -1):
		fails += 1
		notes.append("staff-negative-allowed")

	# over-allocate FLOOR SPACE past the floor total (store opens fully allocated).
	if e.set_dept_space(0, e.floor_total + 10):
		fails += 1
		notes.append("space-overfloor-allowed")

	# markdown out of range.
	if e.set_markdown(0, -100):
		fails += 1
		notes.append("markdown-negative-allowed")
	if e.set_markdown(0, e.max_markdown_bp + 500):
		fails += 1
		notes.append("markdown-overmax-allowed")

	# liquidate more units than on hand.
	if e.liquidate(0, e.line_on_hand(0) + 100):
		fails += 1
		notes.append("liquidate-overflow-allowed")

	# over-borrow past the debt ceiling.
	if e.take_loan(e.max_debt + 1000):
		fails += 1
		notes.append("loan-overmax-allowed")
	# repay with no debt.
	if e.repay_loan(500):
		fails += 1
		notes.append("repay-nodebt-allowed")

	if e.illegal_attempts <= before_attempts:
		fails += 1
		notes.append("illegal-counter-flat")
	if e.cash != b_cash or e.day != b_day or e.debt != b_debt or e.total_staff() != b_staff \
			or e.total_space() != b_space or e.total_on_hand() != b_onhand or e.line_markdown_bp(0) != b_md:
		fails += 1
		notes.append("illegal-mutated-state")

	# --- main scene builds its code UI ---
	var scene: PackedScene = load("res://scenes/store_floor.tscn")
	var root: Node = scene.instantiate()
	add_child(root)               # triggers _ready → builds the UI.
	var layers: Array = [0]
	var labels: Array = [0]
	var buttons: Array = [0]
	var sliders: Array = [0]
	var options: Array = [0]
	_count_type(root, "CanvasLayer", layers)
	_count_type(root, "Label", labels)
	_count_type(root, "Button", buttons)
	_count_type(root, "HSlider", sliders)
	_count_type(root, "OptionButton", options)
	if int(layers[0]) < 1:
		fails += 1
		notes.append("no-canvaslayer")
	if int(labels[0]) < 6:
		fails += 1
		notes.append("too-few-labels(%d)" % int(labels[0]))
	if int(buttons[0]) < 8:
		fails += 1
		notes.append("too-few-buttons(%d)" % int(buttons[0]))
	if int(sliders[0]) < 1:
		fails += 1
		notes.append("no-slider")
	if int(options[0]) < 1:
		fails += 1
		notes.append("no-option")
	root.queue_free()

	# --- save / load round-trips (engine level) ---
	var s: DeptStoreEngine = DeptStoreEngine.new()
	s.setup(20260716, {})
	for _i in 50:
		if s.outcome != DeptStoreEngine.ONGOING:
			break
		s.auto_play_step()
	var checksum: int = s.state_checksum()
	var blob: Dictionary = s.save_data()
	# mutate to prove load overwrites.
	s.cash = 123456
	s.reputation = 1.0
	s.day = 4242
	s.load_data(blob)
	if s.state_checksum() != checksum:
		fails += 1
		notes.append("engine-saveload-mismatch")
	# lockstep continuation after load matches a never-saved twin.
	var twin: DeptStoreEngine = DeptStoreEngine.new()
	twin.setup(20260716, {})
	for _i in 50:
		if twin.outcome != DeptStoreEngine.ONGOING:
			break
		twin.auto_play_step()
	for _i in 12:
		if s.outcome != DeptStoreEngine.ONGOING:
			break
		s.auto_play_step()
		twin.auto_play_step()
	if s.state_checksum() != twin.state_checksum():
		fails += 1
		notes.append("post-load-lockstep-diverged")

	# --- save / load round-trips through the GameManager ABI ---
	var gm: Node = get_node_or_null("/root/GameManager")
	var abi_ok: bool = false
	if gm != null:
		gm.new_game(20260716, {})
		for _i in 25:
			gm.auto_step()
		var gm_sum: int = gm.engine.state_checksum()
		var gm_blob: Dictionary = gm.save_data()
		gm.engine.cash = -777
		gm.engine.day = 9
		gm.load_data(gm_blob)
		abi_ok = gm.engine.state_checksum() == gm_sum
		if not abi_ok:
			fails += 1
			notes.append("abi-saveload-mismatch")
	else:
		fails += 1
		notes.append("no-gamemanager-autoload")

	print("DEBUG: rules_ui_probe layers=%d labels=%d buttons=%d sliders=%d options=%d abi=%s notes=%s fails=%d => %s" % [
		int(layers[0]), int(labels[0]), int(buttons[0]), int(sliders[0]), int(options[0]),
		str(abi_ok), str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
