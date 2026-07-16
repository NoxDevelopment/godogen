extends Node
## _probes/rules_ui_probe.gd
## RULES + UI + SAVE probe: illegal actions are rejected + counted (using a move
## from an unlearned style, switching to an unlearned style, acting during recovery);
## the main scene builds its code UI (a CanvasLayer + labels + buttons) and boots
## clean headless; and the whole run round-trips through save/load unchanged,
## including learned styles + progression + the RNG. One DEBUG line, then quit.

func _count_type(node: Node, cls: String, acc: Array) -> void:
	if node.is_class(cls):
		acc[0] += 1
	for c in node.get_children():
		_count_type(c, cls, acc)


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- illegal actions rejected + counted ---
	var e: BrawlerEngine = BrawlerEngine.new()
	e.setup(20260716, {"difficulty": "normal"})
	# a fighter who knows only drunken_fist.
	e.begin_fight(
		{"name": "P", "body": 6, "mind": 5, "spirit": 6,
			"known_styles": ["drunken_fist"], "upgrades": {},
			"active_style": "drunken_fist", "policy": "dummy", "hp_mult": 1.0, "dmg_mult": 1.0},
		{"name": "F", "body": 6, "mind": 5, "spirit": 6,
			"known_styles": ["iron_ox"], "upgrades": {},
			"active_style": "iron_ox", "policy": "dummy", "hp_mult": 1.0, "dmg_mult": 1.0})
	var before: int = e.illegal_attempts

	# switching to an unlearned style is rejected.
	if e.switch_style(0, "coiling_serpent"):
		fails += 1
		notes.append("unlearned-switch-allowed")
	# requesting a move while the active style is legit works...
	if not e.request_action(0, {"type": "attack", "kind": "light"}):
		fails += 1
		notes.append("legal-attack-rejected")
	# ...but a SECOND attack while mid-attack (recovery) is rejected.
	e.step()  # begins the attack; fighter is now in the attacking state
	if e.request_action(0, {"type": "attack", "kind": "heavy"}):
		fails += 1
		notes.append("attack-during-action-allowed")
	# an unknown move kind is rejected.
	if e.request_action(0, {"type": "attack", "kind": "grab"}):
		fails += 1
		notes.append("unknown-kind-allowed")
	if e.illegal_attempts <= before:
		fails += 1
		notes.append("illegal-counter-flat(%d<=%d)" % [e.illegal_attempts, before])

	# --- the main scene builds its UI + boots clean headless ---
	var scene: PackedScene = load("res://scenes/arena.tscn")
	var root: Node = scene.instantiate()
	add_child(root)
	var layers: Array = [0]
	var labels: Array = [0]
	var buttons: Array = [0]
	_count_type(root, "CanvasLayer", layers)
	_count_type(root, "Label", labels)
	_count_type(root, "Button", buttons)
	if int(layers[0]) < 1:
		fails += 1
		notes.append("no-canvaslayer")
	if int(labels[0]) < 4:
		fails += 1
		notes.append("too-few-labels(%d)" % int(labels[0]))
	if int(buttons[0]) < 6:
		fails += 1
		notes.append("too-few-buttons(%d)" % int(buttons[0]))
	root.queue_free()

	# --- save / load round-trips the WHOLE run (styles + progression + RNG) ---
	var s: BrawlerEngine = BrawlerEngine.new()
	s.setup(20260716, {"difficulty": "normal"})
	s.learn_style("ghost_palm")
	s.award_xp(BrawlerEngine.XP_PER_LEVEL)
	s.upgrade_technique("ghost_palm")
	s.begin_current_encounter("skilled_counter")
	for _i in 200:
		if s.fight_over:
			break
		s.step()
	var snapshot: int = s.run_checksum()
	var blob: Dictionary = s.to_dict()
	# clobber, then restore.
	s.player["level"] = 999
	s.encounter_index = 5
	s.fight_outcome = "clobbered"
	(s.fighters[0] as Dictionary)["hp"] = 12345.0
	s.from_dict(blob)
	var restored: int = s.run_checksum()
	if restored != snapshot:
		fails += 1
		notes.append("saveload-mismatch(%d!=%d)" % [snapshot, restored])
	# the learned style + upgrade survived the round-trip.
	if not s.knows_style("ghost_palm"):
		fails += 1
		notes.append("lost-learned-style")
	if int((s.player["upgrades"] as Dictionary).get("ghost_palm", 0)) <= 0:
		fails += 1
		notes.append("lost-upgrade")
	# and it keeps simulating deterministically after a load.
	var s2: BrawlerEngine = BrawlerEngine.new()
	s2.from_dict(blob)
	for _i in 120:
		if s.fight_over or s2.fight_over:
			break
		s.step()
		s2.step()
	if s.fight_checksum() != s2.fight_checksum():
		fails += 1
		notes.append("post-load-diverges")

	print("DEBUG: rules_ui_probe layers=%d labels=%d buttons=%d illegal=%d saveload=%s notes=%s fails=%d => %s" % [
		int(layers[0]), int(labels[0]), int(buttons[0]), e.illegal_attempts,
		restored == snapshot, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
