extends Node
## _probes/rules_ui_probe.gd
## RULES + UI probe — illegal decisions are rejected (assign a role to a
## dead/out-of-range member, assign a kit, assign the Kit role, and any decision once
## the band is lost — e.g. move on with no survivors / forage with an empty band); the
## main scene builds its UI (a decision button per action + a stack of labels); and
## save/load round-trips the FULL state (the band + roles + needs + morale + journey +
## RNG) through JSON, byte-identically, then continues to replay in lock-step.

func _count_type(node: Node, cls: String, acc: Array) -> void:
	if node.is_class(cls):
		acc[0] += 1
	for c in node.get_children():
		_count_type(c, cls, acc)


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- illegal decisions on a LIVE game ------------------------------------
	var e: WarrenEngine = WarrenEngine.new()
	e.setup(20260716)
	var before_illegal: int = e.illegal_attempts

	# assign a role to an OUT-OF-RANGE (fallen / nonexistent) member -> rejected
	if e.is_legal_action(WarrenEngine.ACT_ASSIGN, 999, WarrenEngine.FORAGER):
		fails += 1
		notes.append("assign-dead-legal")
	if e.take_action(WarrenEngine.ACT_ASSIGN, 999, WarrenEngine.FORAGER):
		fails += 1
		notes.append("assign-dead-applied")

	# assign to the Kit member (index 6 is the founding kit) -> rejected
	if e.is_legal_action(WarrenEngine.ACT_ASSIGN, 6, WarrenEngine.FORAGER):
		fails += 1
		notes.append("assign-kit-legal")

	# assign the Kit ROLE to an adult -> rejected
	if e.is_legal_action(WarrenEngine.ACT_ASSIGN, 0, WarrenEngine.KIT):
		fails += 1
		notes.append("assign-kitrole-legal")

	if e.illegal_attempts <= before_illegal:
		fails += 1
		notes.append("illegal-not-counted")

	# --- decisions on a LOST game are all rejected (no survivors to act) ------
	var dead: WarrenEngine = WarrenEngine.new()
	dead.setup(20260716)
	dead.auto_play_to_end("reckless")  # the reckless band is lost on the road
	if not dead.game_over:
		fails += 1
		notes.append("reckless-not-over")
	if dead.is_legal_action(WarrenEngine.ACT_MOVE_ON):
		fails += 1
		notes.append("moveon-after-loss-legal")
	if dead.is_legal_action(WarrenEngine.ACT_FORAGE):
		fails += 1
		notes.append("forage-after-loss-legal")
	if dead.take_action(WarrenEngine.ACT_MOVE_ON) or dead.take_action(WarrenEngine.ACT_FORAGE):
		fails += 1
		notes.append("act-after-loss-applied")

	# move on when already AT the goal is rejected
	var arr: WarrenEngine = WarrenEngine.new()
	arr.setup(20260716)
	arr.debug_force_arrived()
	if arr.is_legal_action(WarrenEngine.ACT_MOVE_ON):
		fails += 1
		notes.append("moveon-at-goal-legal")

	# --- the main scene builds its UI ----------------------------------------
	var scene: PackedScene = load("res://scenes/warren.tscn")
	var root: Node = scene.instantiate()
	add_child(root)
	var btns: Array = [0]
	var lbls: Array = [0]
	_count_type(root, "Button", btns)
	_count_type(root, "Label", lbls)
	var button_count: int = int(btns[0])
	var label_count: int = int(lbls[0])
	if button_count != WarrenEngine.ACTION_COUNT:
		fails += 1
		notes.append("buttons(%d!=%d)" % [button_count, WarrenEngine.ACTION_COUNT])
	if label_count < 5:
		fails += 1
		notes.append("labels(%d<5)" % label_count)
	# a scripted decision through the view mutates state + repaints
	var day0: int = GameManager.band.day
	root.debug_decide(WarrenEngine.ACT_FORAGE)
	if GameManager.band.day <= day0 and not GameManager.band.game_over:
		fails += 1
		notes.append("view-decision-noop")
	root.queue_free()

	# --- save / load round-trips the FULL state (JSON) -----------------------
	var g: WarrenEngine = WarrenEngine.new()
	g.setup(20260716)
	for _i in 14:
		if g.game_over:
			break
		g.auto_step("balanced")
	var pre_chk: int = g.checksum()
	var json_text: String = JSON.stringify(g.to_dict())
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		fails += 1
		notes.append("json-parse")
	var g2: WarrenEngine = WarrenEngine.new()
	g2.from_dict(parsed if typeof(parsed) == TYPE_DICTIONARY else {})
	var post_chk: int = g2.checksum()
	if pre_chk != post_chk:
		fails += 1
		notes.append("roundtrip(%d!=%d)" % [pre_chk, post_chk])

	# mutate the ORIGINAL after the snapshot; the reload is unaffected (deep copy)
	if not g.game_over:
		g.auto_step("balanced")
	if g2.checksum() != post_chk:
		fails += 1
		notes.append("snapshot-aliased")

	# the reload continues to replay in LOCK-STEP with a fresh identical run
	var g3: WarrenEngine = WarrenEngine.new()
	g3.setup(20260716)
	for _i in 14:
		if g3.game_over:
			break
		g3.auto_step("balanced")
	# advance both g2 (loaded) and g3 (fresh) the same way -> identical checksums
	for _i in 6:
		if not g2.game_over:
			g2.auto_step("balanced")
		if not g3.game_over:
			g3.auto_step("balanced")
	if g2.checksum() != g3.checksum():
		fails += 1
		notes.append("lockstep(%d!=%d)" % [g2.checksum(), g3.checksum()])

	print("DEBUG: rules_ui_probe buttons=%d labels=%d roundtrip=%s illegal=%d notes=%s fails=%d => %s" % [
		button_count, label_count, str(pre_chk == post_chk), e.illegal_attempts,
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
