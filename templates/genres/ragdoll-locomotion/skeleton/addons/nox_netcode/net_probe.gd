extends Node
## res://addons/nox_netcode/net_probe.gd
## Headless self-test for the nox_netcode drop-in (mirrors the ff-gamebook probe
## convention: drive the API, print ONE deterministic DEBUG line, quit).
##
## A single process cannot validate true two-peer sync — that needs two running
## instances (see the addon README for the manual steps). What this DOES prove,
## headless and CI-friendly, is that the drop-in loads with zero parse/script
## errors, the Net autoload registers and its transport/authority API is sound,
## and (when present) the NetBridge DM-seat authority model answers correctly.
##
## Run:
##   Godot --headless --path <project> res://addons/nox_netcode/net_probe.tscn
## (net_probe.tscn wraps this script). Exits the tree when done.

const PROBE_PORT := 24597


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[String] = []

	# 0) Dormant before host(): every injected guard is inert offline.
	checks.append("dormant=%s" % (not Net.active))

	# 1) Host over ENet on loopback (the LAN default transport).
	var err := Net.host({"transport": "enet", "port": PROBE_PORT, "profile": "authority-turn", "arbitration": "leader", "player_name": "Host"})
	var hosted := err == OK and Net.active and Net.is_host() and Net.local_id() == 1
	checks.append("host=%s" % hosted)

	# 2) Roster seeded with the host; authority-turn seats the host as DM.
	var roster_ok := Net.peers.size() == 1 and Net.peers.has(1)
	checks.append("roster=%d" % Net.peers.size())
	checks.append("is_dm=%s" % Net.is_dm())
	checks.append("require_host=%s" % Net.require_host())
	checks.append("require_dm=%s" % Net.require_dm())

	# 3) Seat reassignment API (demote then retake the DM seat).
	Net.assign_seat(1, Net.SEAT_PLAYER)
	var demoted := not Net.is_dm()
	Net.take_dm_seat()
	var retaken := Net.is_dm()
	checks.append("seat_cycle=%s" % (demoted and retaken))

	# 4) DM authority model + the host-authoritative SessionState bridge
	#    (NetBridge + SessionState present only in an authority-turn template).
	#    As host+DM with no clients: dm_push/override report handled (true), and
	#    advance/roll/choose/dm-push actually move the canonical session state.
	var bridge := get_node_or_null("/root/NetBridge")
	var session := get_node_or_null("/root/SessionState")
	var dice := get_node_or_null("/root/Dice")
	var dm_ok := true
	var bridge_state := "no-session"
	if bridge != null:
		dm_ok = bridge.dm_push_passage("passage_probe") == true \
			and bridge.dm_override_roll({"success": true, "total": 2}) == true
		if session != null:
			if dice != null:
				dice.show_popup = false  # resolve tests without the tray (headless)
			session.reset_session()
			session.advance_passage("p1")             # host mutates + would broadcast
			var adv_ok: bool = str(session.current_passage) == "p1"
			var roll_ok := true
			if dice != null:
				var before: int = session.roll_log.size()
				Net.session_seed = 12345
				dice.set_seed(12345)
				await session.roll("skill")           # host rolls (seeded), records
				roll_ok = session.roll_log.size() == before + 1
			bridge.dm_push_passage("p7")              # DM steers the party
			var push_ok: bool = str(session.current_passage) == "p7"
			var chosen: String = session.choose("p2", "go")  # leader arbitration
			var choose_ok: bool = chosen == "p2"
			bridge_state = "adv=%s roll=%s push=%s choose=%s" % [adv_ok, roll_ok, push_ok, choose_ok]
			dm_ok = dm_ok and adv_ok and roll_ok and push_ok and choose_ok
			session.reset_session()
	checks.append("dm_authority=%s" % dm_ok)
	checks.append("bridge_state=(%s)" % bridge_state)

	# 5) Determinism handshake: Start broadcasts a non-zero shared seed. (A dict
	#    is the capture-by-reference trick — GDScript lambdas capture locals by
	#    value, so a plain bool flag would never propagate back out.)
	var flags := {"seed": false, "ended": false}
	Net.seed_broadcast.connect(func(_s): flags.seed = true, CONNECT_ONE_SHOT)
	Net.start()
	await get_tree().process_frame
	var seed_ok: bool = Net.session_seed != 0 and flags.seed
	checks.append("seed=%s" % seed_ok)

	# 6) Clean teardown.
	Net.session_ended.connect(func(_r): flags.ended = true, CONNECT_ONE_SHOT)
	Net.leave()
	var teardown_ok: bool = not Net.active and flags.ended
	checks.append("teardown=%s" % teardown_ok)

	var all_ok := hosted and roster_ok and demoted and retaken and dm_ok \
		and seed_ok and teardown_ok
	print("DEBUG: nox_netcode probe — profile=%s transport=%s bridge=%s %s => %s" % [
		Net.profile(), "enet", bridge != null,
		" ".join(checks),
		"OK" if all_ok else "FAIL",
	])

	get_tree().quit(0 if all_ok else 1)
