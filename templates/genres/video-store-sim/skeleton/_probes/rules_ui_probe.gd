extends Node
## _probes/rules_ui_probe.gd
## RULES + UI + SAVE probe: illegal actions are rejected and leave state untouched
## (buy over cash, buy a non-positive quantity, buy an unreleased title, over/under-
## staff, an out-of-range late-fee policy, over-borrow, repay with no debt, salvage an
## absent copy); the main scene builds its code UI (a CanvasLayer + labels + buttons
## + sliders + an option button); and the whole store round-trips through save/load
## unchanged, through both the engine and the GameManager ABI.

func _count_type(node: Node, cls: String, acc: Array) -> void:
	if node.is_class(cls):
		acc[0] += 1
	for c in node.get_children():
		_count_type(c, cls, acc)

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- illegal actions rejected + counter advances + state untouched ---
	var e: VideoStoreEngine = VideoStoreEngine.new()
	e.setup(20260716, {})
	var before_attempts: int = e.illegal_attempts
	# Snapshot the MEANINGFUL state (everything a rejected action must not touch —
	# illegal_attempts itself is expected to rise, so it is not part of this).
	var b_cash: int = e.cash
	var b_day: int = e.day
	var b_debt: int = e.debt
	var b_staff: int = e.staff
	var b_fee: int = e.late_fee_per_day
	var b_rep: float = e.reputation
	var b_members: int = e.members
	var b_copies: int = e.total_copies_owned()
	var b_rentals: int = e.active_rentals()

	# buy more copies than cash allows.
	var t_cat: int = 0                       # a released catalogue title.
	var huge: int = e.cash / VideoStoreEngine.TITLE_COST[t_cat] + 100
	if e.buy_copies(t_cat, huge):
		fails += 1
		notes.append("buy-overcash-allowed")

	# buy a non-positive quantity.
	if e.buy_copies(t_cat, 0):
		fails += 1
		notes.append("buy-zero-allowed")
	if e.buy_copies(t_cat, -5):
		fails += 1
		notes.append("buy-negative-allowed")

	# buy an UNRELEASED title (title 23 drops on day 310; we're on day 0).
	if e.buy_copies(23, 1):
		fails += 1
		notes.append("buy-unreleased-allowed")

	# staff out of range.
	if e.set_staff(-1):
		fails += 1
		notes.append("staff-negative-allowed")
	if e.set_staff(e.max_staff + 3):
		fails += 1
		notes.append("staff-overmax-allowed")

	# late-fee policy out of range.
	if e.set_late_fee(-1):
		fails += 1
		notes.append("fee-negative-allowed")
	if e.set_late_fee(e.max_late_fee + 5):
		fails += 1
		notes.append("fee-overmax-allowed")

	# over-borrow past the debt ceiling.
	if e.take_loan(e.max_debt + 1000):
		fails += 1
		notes.append("loan-overmax-allowed")

	# repay with no debt.
	if e.repay_loan(500):
		fails += 1
		notes.append("repay-nodebt-allowed")

	# salvage an on-shelf copy that does not exist.
	if e.remove_copy(t_cat):
		fails += 1
		notes.append("salvage-empty-allowed")

	if e.illegal_attempts <= before_attempts:
		fails += 1
		notes.append("illegal-counter-flat")
	if e.cash != b_cash or e.day != b_day or e.debt != b_debt or e.staff != b_staff \
			or e.late_fee_per_day != b_fee or e.reputation != b_rep or e.members != b_members \
			or e.total_copies_owned() != b_copies or e.active_rentals() != b_rentals:
		fails += 1
		notes.append("illegal-mutated-state")

	# --- main scene builds its code UI ---
	var scene: PackedScene = load("res://scenes/store.tscn")
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
	var s: VideoStoreEngine = VideoStoreEngine.new()
	s.setup(20260716, {})
	for _i in 40:
		if s.outcome != VideoStoreEngine.ONGOING:
			break
		s.auto_play_step()
	var checksum: int = s.state_checksum()
	var blob: Dictionary = s.save_data()
	# mutate to prove load overwrites.
	s.cash = 123456
	s.reputation = 1.0
	s.day = 4242
	s.members = 99999
	s.load_data(blob)
	if s.state_checksum() != checksum:
		fails += 1
		notes.append("engine-saveload-mismatch")
	# lockstep continuation after load matches a never-saved twin.
	var twin: VideoStoreEngine = VideoStoreEngine.new()
	twin.setup(20260716, {})
	for _i in 40:
		if twin.outcome != VideoStoreEngine.ONGOING:
			break
		twin.auto_play_step()
	for _i in 10:
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
		for _i in 20:
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
