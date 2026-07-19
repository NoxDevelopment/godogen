extends Node
## _probes/rules_ui_probe.gd
## RULES + UI + SAVE probe: illegal / edge muscle inputs are rejected + counted
## (out-of-range indices, inputs after the run ends); the main scene builds its
## code UI (a CanvasLayer + HUD labels, and it boots clean offline); and the whole
## run round-trips through save/load unchanged. Prints one DEBUG line, quits.

func _count_type(node: Node, cls: String, acc: Array) -> void:
	if node.is_class(cls):
		acc[0] += 1
	for c in node.get_children():
		_count_type(c, cls, acc)


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- illegal / edge muscle inputs rejected ---
	var e: RagdollEngine = RagdollEngine.new()
	e.setup(20260716, {"preset": "normal"})
	var before: int = e.illegal_attempts
	# out-of-range muscle indices are rejected + counted.
	if e.set_muscle(-1, true):
		fails += 1
		notes.append("neg-index-allowed")
	if e.set_muscle(RagdollEngine.MUSCLE_COUNT, true):
		fails += 1
		notes.append("oob-index-allowed")
	if e.set_muscle(99, true):
		fails += 1
		notes.append("big-index-allowed")
	if e.illegal_attempts <= before:
		fails += 1
		notes.append("illegal-counter-flat")
	# a valid muscle index applies.
	if not e.set_muscle(RagdollEngine.MUSCLE_Q, true):
		fails += 1
		notes.append("valid-muscle-rejected")
	# inputs after the run ends are a no-op (not applied), never a crash.
	e.finished = true
	if e.set_muscle(RagdollEngine.MUSCLE_W, true):
		fails += 1
		notes.append("input-after-finish-applied")

	# --- the main scene builds its UI + boots clean offline ---
	var scene: PackedScene = load("res://scenes/track.tscn")
	var root: Node = scene.instantiate()
	add_child(root)
	var layers: Array = [0]
	var labels: Array = [0]
	_count_type(root, "CanvasLayer", layers)
	_count_type(root, "Label", labels)
	if int(layers[0]) < 1:
		fails += 1
		notes.append("no-canvaslayer")
	if int(labels[0]) < 4:
		fails += 1
		notes.append("too-few-labels(%d)" % int(labels[0]))
	# the offline scene must be running a single local athlete (no net session).
	if root.has_method("_net_active") and bool(root._net_active()):
		fails += 1
		notes.append("net-active-offline")
	root.queue_free()

	# --- save / load round-trips ---
	var s: RagdollEngine = RagdollEngine.new()
	s.setup(20260716, {"preset": "normal"})
	s.run_policy_steps("walk", 400)
	var snapshot: int = s.run_checksum()
	var blob: Dictionary = s.to_dict()
	# mutate to prove load overwrites.
	s.distance = 123456.0
	s.step_count = 999999
	s.outcome = "clobbered"
	s.from_dict(blob)
	var restored: int = s.run_checksum()
	if restored != snapshot:
		fails += 1
		notes.append("saveload-mismatch(%d!=%d)" % [snapshot, restored])
	# and the restored run keeps simulating deterministically after a load.
	var s2: RagdollEngine = RagdollEngine.new()
	s2.from_dict(blob)
	s.run_policy_steps("walk", 100)
	s2.run_policy_steps("walk", 100)
	if s.body_checksum() != s2.body_checksum():
		fails += 1
		notes.append("post-load-diverges")

	print("DEBUG: rules_ui_probe layers=%d labels=%d illegal=%d saveload=%s notes=%s fails=%d => %s" % [
		int(layers[0]), int(labels[0]), e.illegal_attempts, restored == snapshot,
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
