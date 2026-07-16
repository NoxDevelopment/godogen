extends Node
## res://addons/nox_netcode/net_events.gd
## Realtime profile — host-validated event RPCs + the shared race clock (spec
## "Obby integration points": checkpoint / respawn / finish are host-validated
## reliable RPCs so the finish order is authoritative and cheat-resistant; a
## small host-owned synchronized object holds the round timer / finish order).
##
## Add this as a child named "NetEvents" of the same level root the spawner
## manages (the fixed node name keeps its RPC path identical on every peer).
## Clients REQUEST events; the host VALIDATES and BROADCASTS the resulting state.
##
## Shared clock: if netfox's NetworkTime autoload is present it is the source of
## truth (tick-accurate); otherwise the host owns a float timer and broadcasts
## it on a light cadence. Both paths are complete — netfox is an optimization,
## not a requirement.

signal checkpoint_confirmed(peer: int, checkpoint_id: int)
signal player_respawned(peer: int, checkpoint_id: int)
signal player_finished(peer: int, place: int, finish_time: float)
signal race_reset()

## Host-owned truth.
var finish_order: Array = []           # [{peer, place, time}]
var checkpoints: Dictionary = {}       # peer -> highest checkpoint id reached
var round_time: float = 0.0
var racing: bool = false

const _BROADCAST_HZ := 4.0
var _accum := 0.0
var _netfox: Node = null


func _ready() -> void:
	_netfox = get_node_or_null("/root/NetworkTime")
	set_process(true)


func _process(delta: float) -> void:
	if not racing:
		return
	if _netfox != null and _netfox.has_method("get") and _netfox.get("time") != null:
		round_time = float(_netfox.time)
		return
	# Fallback: host advances the clock and broadcasts it a few times a second.
	if Net.is_host():
		round_time += delta
		_accum += delta
		if _accum >= 1.0 / _BROADCAST_HZ:
			_accum = 0.0
			_sync_clock.rpc(round_time)


# --- Race control (host) -----------------------------------------------------

## Host: begin the race. Resets order/checkpoints and starts the clock.
func start_race() -> void:
	if not Net.is_host():
		return
	_reset_race.rpc()


@rpc("authority", "call_local", "reliable")
func _reset_race() -> void:
	finish_order.clear()
	checkpoints.clear()
	round_time = 0.0
	racing = true
	race_reset.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_clock(t: float) -> void:
	round_time = t


# --- Checkpoints -------------------------------------------------------------

## A peer reached a checkpoint. Host validates monotonic progress (no skipping
## backwards or teleporting ahead by more than one gate) then broadcasts.
func report_checkpoint(checkpoint_id: int) -> void:
	if not Net.active:
		return
	if Net.is_host():
		_host_checkpoint(Net.local_id(), checkpoint_id)
	else:
		_req_checkpoint.rpc_id(1, checkpoint_id)


@rpc("any_peer", "call_remote", "reliable")
func _req_checkpoint(checkpoint_id: int) -> void:
	if not Net.require_host():
		return
	_host_checkpoint(multiplayer.get_remote_sender_id(), checkpoint_id)


func _host_checkpoint(peer: int, checkpoint_id: int) -> void:
	var current: int = int(checkpoints.get(peer, -1))
	# Anti-cheat: only accept the very next checkpoint in sequence.
	if checkpoint_id != current + 1:
		return
	checkpoints[peer] = checkpoint_id
	_apply_checkpoint.rpc(peer, checkpoint_id)


@rpc("authority", "call_remote", "reliable")
func _apply_checkpoint(peer: int, checkpoint_id: int) -> void:
	checkpoints[peer] = checkpoint_id
	checkpoint_confirmed.emit(peer, checkpoint_id)


# --- Respawn -----------------------------------------------------------------

## A peer fell / requests a respawn to its last checkpoint. Host authoritative.
func request_respawn() -> void:
	if not Net.active:
		return
	if Net.is_host():
		_host_respawn(Net.local_id())
	else:
		_req_respawn.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_respawn() -> void:
	if not Net.require_host():
		return
	_host_respawn(multiplayer.get_remote_sender_id())


func _host_respawn(peer: int) -> void:
	var cp: int = int(checkpoints.get(peer, -1))
	_apply_respawn.rpc(peer, cp)


@rpc("authority", "call_remote", "reliable")
func _apply_respawn(peer: int, checkpoint_id: int) -> void:
	player_respawned.emit(peer, checkpoint_id)


# --- Finish line -------------------------------------------------------------

## A peer crossed the finish line. Host assigns the authoritative place + time,
## rejecting duplicates, and broadcasts the standing.
func report_finish() -> void:
	if not Net.active:
		return
	if Net.is_host():
		_host_finish(Net.local_id())
	else:
		_req_finish.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_finish() -> void:
	if not Net.require_host():
		return
	_host_finish(multiplayer.get_remote_sender_id())


func _host_finish(peer: int) -> void:
	for entry in finish_order:
		if int(entry.get("peer", 0)) == peer:
			return  # already finished
	var place := finish_order.size() + 1
	var record := {"peer": peer, "place": place, "time": round_time}
	finish_order.append(record)
	_apply_finish.rpc(peer, place, round_time)


@rpc("authority", "call_remote", "reliable")
func _apply_finish(peer: int, place: int, finish_time: float) -> void:
	var record := {"peer": peer, "place": place, "time": finish_time}
	# Clients keep their own copy of the standings for the leaderboard UI.
	var known := false
	for entry in finish_order:
		if int(entry.get("peer", 0)) == peer:
			known = true
			break
	if not known:
		finish_order.append(record)
	player_finished.emit(peer, place, finish_time)
