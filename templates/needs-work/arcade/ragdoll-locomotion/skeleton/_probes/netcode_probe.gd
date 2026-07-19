extends Node
## _probes/netcode_probe.gd
## NETCODE seam probe (the realtime-config half of requirement (f); the vendored
## addon's own self-test — res://addons/nox_netcode/net_probe.tscn — is run
## separately). Proves: the Net autoload + its realtime API are present; the seam
## is INERT offline (_net_active() == false); the per-peer athlete avatar is wired
## exactly like obby's net_player seam (authority from the node name, a code-built
## MultiplayerSynchronizer, an owned RagdollEngine + a replicated pose); and the
## OFFLINE run is BYTE-IDENTICAL whether the netcode nodes are present in the scene
## or not (a pure RagdollEngine). Prints one DEBUG line, quits.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- 1) Net autoload + realtime API present + dormant offline ---
	var net := get_node_or_null("/root/Net")
	if net == null:
		fails += 1
		notes.append("no-Net-autoload")
	else:
		for m in ["host", "join", "leave", "is_host", "local_id", "profile", "active"]:
			if not (m in net or net.has_method(m)):
				fails += 1
				notes.append("net-missing:%s" % m)
		if bool(net.active):
			fails += 1
			notes.append("net-active-at-boot")
		if String(net.profile()) != "realtime":
			fails += 1
			notes.append("profile-not-realtime(%s)" % String(net.profile()))

	# --- 2) the main scene's seam is inert offline ---
	var scene: PackedScene = load("res://scenes/track.tscn")
	var track: Node = scene.instantiate()
	add_child(track)
	if track.get_node_or_null("NetSpawner") == null:
		fails += 1
		notes.append("no-NetSpawner")
	if track.get_node_or_null("NetEvents") == null:
		fails += 1
		notes.append("no-NetEvents")
	if track.has_method("_net_active") and bool(track._net_active()):
		fails += 1
		notes.append("seam-active-offline")

	# --- 3) per-peer athlete avatar wired like obby's net_player seam ---
	var ath_scene: PackedScene = load("res://scenes/athlete.tscn")
	var ath: Node2D = ath_scene.instantiate()
	ath.name = "7"  # the spawner names the node after the peer id.
	add_child(ath)
	if int(ath.peer_id) != 7:
		fails += 1
		notes.append("peer-id-not-from-name(%d)" % int(ath.peer_id))
	if ath.get_multiplayer_authority() != 7:
		fails += 1
		notes.append("authority-not-set(%d)" % ath.get_multiplayer_authority())
	if ath.get_node_or_null("Sync") == null:
		fails += 1
		notes.append("no-synchronizer")
	if ath.engine == null:
		fails += 1
		notes.append("athlete-no-engine")
	# the replicated pose payload is the flat node snapshot (11 nodes x 2).
	if ath.pose.size() != RagdollEngine.NODE_COUNT * 2:
		fails += 1
		notes.append("pose-size(%d)" % ath.pose.size())
	# a remote pose can be applied for rendering (owner-writes / others-render).
	var snap: PackedFloat32Array = ath.engine.pose_snapshot()
	ath.engine.apply_pose_snapshot(snap)
	ath.queue_free()

	# --- 4) OFFLINE byte-identical: netcode nodes present vs a pure engine ---
	# drive GameManager's engine (the one the seam owns, with NetSpawner/NetEvents
	# siblings in the tree) with a canned policy, and a standalone RagdollEngine
	# with the same seed + policy — the checksums must match exactly.
	GameManager.new_run(20260716, {"preset": "normal"})
	for _s in 600:
		if GameManager.engine.finished:
			break
		GameManager.engine.set_muscle_mask(GameManager.engine.policy_walk(GameManager.engine.step_count))
		GameManager.engine.step()
	var with_netcode: int = GameManager.engine.body_checksum()

	var pure: RagdollEngine = RagdollEngine.new()
	pure.setup(20260716, {"preset": "normal"})
	for _s in 600:
		if pure.finished:
			break
		pure.set_muscle_mask(pure.policy_walk(pure.step_count))
		pure.step()
	var pure_chk: int = pure.body_checksum()

	if with_netcode != pure_chk:
		fails += 1
		notes.append("offline-not-identical(%d!=%d)" % [with_netcode, pure_chk])

	track.queue_free()

	print("DEBUG: netcode_probe profile=%s active=%s seam_offline=%s pose=%d byteident=%s notes=%s fails=%d => %s" % [
		(String(net.profile()) if net != null else "?"),
		(str(net.active) if net != null else "?"),
		(str(track._net_active()) if track.has_method("_net_active") else "?"),
		RagdollEngine.NODE_COUNT * 2, with_netcode == pure_chk,
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
