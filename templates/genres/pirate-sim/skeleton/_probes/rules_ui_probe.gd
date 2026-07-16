extends Node
## _probes/rules_ui_probe.gd
## RULES + UI + SAVE probe: illegal actions are rejected (sail with no crew, buy over
## cargo/gold, sell more than aboard, attack with no encounter); the main scene builds
## its code UI (a CanvasLayer + labels + buttons + sliders + option buttons); and the
## whole career round-trips through save/load unchanged.

func _count_type(node: Node, cls: String, acc: Array) -> void:
	if node.is_class(cls):
		acc[0] += 1
	for c in node.get_children():
		_count_type(c, cls, acc)

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- illegal actions rejected ---
	var e: PirateEngine = PirateEngine.new()
	e.setup(20260715)
	var before: int = e.illegal_attempts

	# sail with no crew.
	e.ship["crew"] = 0
	if e.sail_to((e.location + 1) % e.ports.size()):
		fails += 1
		notes.append("sail-nocrew-allowed")
	e.ship["crew"] = 34

	# sail to the current port / invalid index.
	if e.sail_to(e.location):
		fails += 1
		notes.append("sail-self-allowed")
	if e.sail_to(9999):
		fails += 1
		notes.append("sail-oob-allowed")

	# buy over cargo capacity.
	e.gold = 1000000
	if e.buy(String(e.GOOD_IDS[0]), e.ship["cargo_cap"] + 50):
		fails += 1
		notes.append("buy-overcargo-allowed")

	# buy over gold.
	e.gold = 0
	if e.buy(String(e.GOOD_IDS[0]), 5):
		fails += 1
		notes.append("buy-overgold-allowed")

	# sell more than aboard.
	e.gold = 1000
	if e.sell(String(e.GOOD_IDS[0]), 999):
		fails += 1
		notes.append("sell-empty-allowed")

	# attack with no encounter.
	e.encounter = {}
	if not e.attack("sink").is_empty():
		fails += 1
		notes.append("attack-noenc-allowed")

	if e.illegal_attempts <= before:
		fails += 1
		notes.append("illegal-counter-flat")

	# --- main scene builds its UI ---
	var scene: PackedScene = load("res://scenes/port_map.tscn")
	var root: Node = scene.instantiate()
	add_child(root)
	# let _ready build the UI.
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
	if int(options[0]) < 2:
		fails += 1
		notes.append("too-few-options(%d)" % int(options[0]))
	# an OptionButton is a Button subclass; ensure our tally treats them distinctly enough.
	root.queue_free()

	# --- save / load round-trips ---
	var s: PirateEngine = PirateEngine.new()
	s.setup(20260715, {"policy": "trade"})
	for _i in 6:
		if s.career_over:
			break
		s.auto_step()
	var snapshot: int = s.career_checksum()
	var blob: Dictionary = s.to_dict()
	# mutate to prove load overwrites.
	s.gold = 123456
	s.fame = 999999
	s.day = 4242
	s.from_dict(blob)
	var restored: int = s.career_checksum()
	if restored != snapshot:
		fails += 1
		notes.append("saveload-mismatch(%d!=%d)" % [snapshot, restored])

	print("DEBUG: rules_ui_probe layers=%d labels=%d buttons=%d sliders=%d options=%d notes=%s fails=%d => %s" % [
		int(layers[0]), int(labels[0]), int(buttons[0]), int(sliders[0]), int(options[0]),
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
