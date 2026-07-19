extends Node
## _probes/rules_ui_probe.gd
## RULES + UI + SAVE probe: illegal actions are rejected and leave meaningful state
## untouched (plant an empty field with no cash / harvest an empty field / plant out of
## season without an override / over-buy livestock past the cap / sell more head than owned
## / sell commodity you don't hold / over-borrow / repay with no debt); the main scene
## builds its code UI (a CanvasLayer + labels + buttons + sliders + option buttons); and the
## whole farm round-trips through save/load unchanged, through both the engine and the
## GameManager ABI.

func _count_type(node: Node, cls: String, acc: Array) -> void:
	if node.is_class(cls):
		acc[0] += 1
	for c in node.get_children():
		_count_type(c, cls, acc)

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- illegal actions rejected + counter advances + state untouched ---
	var e: FarmEngine = FarmEngine.new()
	e.setup(20260716, {})
	# give a herd + some grain stock so overflow/oversell checks are meaningful.
	e.buy_livestock(FarmEngine.A_CHICKENS, 10)
	var before_attempts: int = e.illegal_attempts
	var b_cash: int = e.cash
	var b_day: int = e.day
	var b_debt: int = e.debt
	var b_herd: int = e.herd(FarmEngine.A_CHICKENS)
	var b_feed: int = e.feed_stock()

	# harvest an EMPTY (fallow) field.
	if e.harvest(0):
		fails += 1
		notes.append("harvest-empty-allowed")
	# plant a crop OUT OF SEASON without an override. Find a crop not plantable today.
	var out_crop: int = -1
	for c in FarmEngine.CROP_COUNT:
		if not e.crop_in_season(c, e.day):
			out_crop = c
			break
	if out_crop >= 0:
		if e.plant(0, out_crop, false):
			fails += 1
			notes.append("plant-offseason-allowed")
	# plant an invalid crop / invalid field.
	if e.plant(0, 999, true):
		fails += 1
		notes.append("plant-badcrop-allowed")
	if e.plant(999, 0, true):
		fails += 1
		notes.append("plant-badfield-allowed")
	# plant a crop you cannot AFFORD (drain cash first via a huge but legal-less path):
	# force a no-cash state by comparing seed cost against a zeroed clone.
	var broke: FarmEngine = FarmEngine.new()
	broke.setup(20260716, {"start_cash": 10})
	var in_crop: int = -1
	for c in FarmEngine.CROP_COUNT:
		if broke.crop_in_season(c, broke.day):
			in_crop = c
			break
	if in_crop >= 0 and broke.plant(0, in_crop, false):
		fails += 1
		notes.append("plant-overcash-allowed")

	# over-buy livestock past the herd cap.
	if e.buy_livestock(FarmEngine.A_CHICKENS, FarmEngine.ANIMAL_CAP[FarmEngine.A_CHICKENS] + 50):
		fails += 1
		notes.append("livestock-overcap-allowed")
	# sell more head than owned.
	if e.sell_livestock(FarmEngine.A_CHICKENS, e.herd(FarmEngine.A_CHICKENS) + 100):
		fails += 1
		notes.append("livestock-oversell-allowed")
	# sell a commodity you don't hold.
	if e.sell_commodity(FarmEngine.C_GRAIN, 5):
		fails += 1
		notes.append("commodity-oversell-allowed")
	# sell FEED (an input, never a product).
	if e.sell_commodity(FarmEngine.C_FEED, 1):
		fails += 1
		notes.append("feed-sold-allowed")
	# over-borrow past the debt ceiling; repay with no debt.
	if e.take_loan(e.max_debt + 5000):
		fails += 1
		notes.append("loan-overmax-allowed")
	if e.repay_loan(500):
		fails += 1
		notes.append("repay-nodebt-allowed")

	if e.illegal_attempts <= before_attempts:
		fails += 1
		notes.append("illegal-counter-flat")
	if e.cash != b_cash or e.day != b_day or e.debt != b_debt \
			or e.herd(FarmEngine.A_CHICKENS) != b_herd or e.feed_stock() != b_feed:
		fails += 1
		notes.append("illegal-mutated-state")

	# --- main scene builds its code UI ---
	var scene: PackedScene = load("res://scenes/farm.tscn")
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
	var s: FarmEngine = FarmEngine.new()
	s.setup(20260716, {})
	for _i in 80:
		if s.outcome != FarmEngine.ONGOING:
			break
		s.auto_play_step()
	var checksum: int = s.state_checksum()
	var blob: Dictionary = s.save_data()
	# mutate to prove load overwrites.
	s.cash = 123456
	s.day = 4242
	s.load_data(blob)
	if s.state_checksum() != checksum:
		fails += 1
		notes.append("engine-saveload-mismatch")
	# lockstep continuation after load matches a never-saved twin.
	var twin: FarmEngine = FarmEngine.new()
	twin.setup(20260716, {})
	for _i in 80:
		if twin.outcome != FarmEngine.ONGOING:
			break
		twin.auto_play_step()
	for _i in 20:
		if s.outcome != FarmEngine.ONGOING:
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
		for _i in 40:
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
