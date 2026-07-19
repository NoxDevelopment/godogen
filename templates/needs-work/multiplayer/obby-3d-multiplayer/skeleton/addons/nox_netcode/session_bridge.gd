extends Node
## res://addons/nox_netcode/session_bridge.gd
## Autoload "NetBridge" — the authority-turn profile's SessionState bridge and
## DM-seat authority model (spec: "Authority model → DM-seat authority model").
##
## The template's `SessionState` autoload routes ALL story state through three
## methods (advance_passage / choose / roll+roll_luck) and three signals
## (passage_changed / choice_made / roll_resolved). The generator applies a
## pinned guard patch to session_state.gd that hands those three methods to this
## bridge when a session is live, and points the two DM-seat no-op hooks
## (dm_push_passage / dm_override_roll) here. NOTHING in the book scene changes.
##
## Authority rules enforced here (host = peer 1 = the only source of truth):
##   - advance_passage : host mutates + broadcasts; a client SUPPRESSES its
##     local walk and applies only the host's broadcast (renders off signals).
##   - choose          : a client's press becomes a request to the host; the
##     host ARBITRATES the party decision (leader | vote | dm-confirm) then
##     drives its own advance, which broadcasts to all.
##   - roll / roll_luck: the HOST rolls with the shared seed (Net.session_seed),
##     so results are authoritative and reproducible; it broadcasts the result
##     and every peer replays it. Clients never roll their own dice.
##   - dm_push_passage : verify the caller holds the DM seat (require_dm), then
##     do a host-authoritative advance. Returns true when handled.
##   - dm_override_roll: verify the DM seat, then stage a pending result that
##     replaces the next host roll (a fudge). Returns true when handled.
##
## Offline (Net.active == false) every entry point is inert / returns false, so
## the single-player core is byte-identical.

## Meta key set on SessionState while the bridge applies a host broadcast, so
## the injected guard reuses the REAL method body instead of re-intercepting.
const APPLYING_META := "_net_applying"

## Emitted on a client when the host's advance broadcast lands, carrying the id
## the party moved to. A multiplayer-aware book can connect this to walk its
## local DialogueResource to `id` so the passage TEXT renders in step (the plate
## / history / sheet already update off SessionState's own signals). Single-
## player and host peers never need it.
signal remote_advance(passage_id: String)
## Emitted on every peer when a host-authoritative roll result lands.
signal roll_received(result: Dictionary)
## Emitted when a party choice is committed by the host (post-arbitration).
signal choice_committed(next_id: String)

## Staged DM roll override (consumed by the next host roll). Empty = none.
var _pending_override: Dictionary = {}
## Arbitration tally for the current open choice: next_id -> [voter peer ids].
var _votes: Dictionary = {}
## The choice awaiting DM confirmation (dm-confirm mode): {next_id, text}.
var _pending_choice: Dictionary = {}

var _session: Node = null


func _ready() -> void:
	# No network activity at boot; just cache the SessionState autoload if the
	# host template provides one (the addon stays inert without it).
	_session = get_node_or_null("/root/SessionState")


# --- advance_passage interception -------------------------------------------

## Called by the patched SessionState.advance_passage. Returns true to SUPPRESS
## the local mutation (client waiting for the host), false to let it run (host,
## or a broadcast being applied).
func intercept_advance(passage_id: String) -> bool:
	if not Net.active:
		return false
	if Net.is_host():
		# Host mutates locally (falls through) and tells the clients.
		_apply_advance.rpc(passage_id)
		return false
	# Client: do not lead. The host's _apply_advance broadcast drives us.
	return true


## host -> clients: apply an authoritative passage move. Reuses the real
## SessionState body under the APPLYING_META guard so history/signals stay
## single-sourced, then nudges any MP-aware book to walk its text.
@rpc("authority", "call_remote", "reliable")
func _apply_advance(passage_id: String) -> void:
	if _session == null:
		return
	_session.set_meta(APPLYING_META, true)
	_session.advance_passage(passage_id)
	_session.remove_meta(APPLYING_META)
	remote_advance.emit(passage_id)


# --- choose interception -----------------------------------------------------

## Called by the patched SessionState.choose. Returns the id the caller should
## advance its dialogue to. Host arbitrates and returns the resolved id; a
## client optimistically returns its own pick (the host corrects via a later
## _apply_advance if arbitration diverges).
func intercept_choose(next_id: String, choice_text: String) -> String:
	if not Net.active:
		return next_id
	if Net.is_host():
		# Match the single-player local emit so listeners behave identically.
		if _session != null:
			_session.choice_made.emit(next_id, choice_text)
		var resolved := _host_arbitrate(Net.local_id(), next_id, choice_text)
		if resolved == "":
			# Deferred (vote without a majority yet, or dm-confirm pending). Hold
			# on the current passage rather than walking to "" (which would kick
			# an unmodified book to its finish handler). The host commits and
			# broadcasts the real advance once the vote/DM resolves; a fully
			# MP-aware book connects `choice_committed`/`remote_advance` and skips
			# the optimistic walk entirely.
			return _held_passage(next_id)
		return resolved
	# Client: send the request; render optimistically off our own choice_made.
	_req_choose.rpc_id(1, next_id, choice_text)
	if _session != null:
		_session.choice_made.emit(next_id, choice_text)
	return next_id


## The passage to "stay on" while a choice is deferred (safe fallback for the
## unmodified book — never returns "").
func _held_passage(fallback: String) -> String:
	if _session != null and str(_session.current_passage) != "":
		return str(_session.current_passage)
	return fallback


## client -> host: I choose next_id.
@rpc("any_peer", "call_remote", "reliable")
func _req_choose(next_id: String, choice_text: String) -> void:
	if not Net.require_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var resolved := _host_arbitrate(sender, next_id, choice_text)
	# leader/vote may resolve immediately; dm-confirm returns "" until confirmed.
	if resolved != "":
		_commit_choice(resolved, choice_text)


## Host-side arbitration. Returns the resolved next_id, or "" when the decision
## is deferred (dm-confirm pending, or a vote without a majority yet).
func _host_arbitrate(voter: int, next_id: String, choice_text: String) -> String:
	match Net.arbitration():
		"leader":
			# First choice to reach the host wins; the host is the default leader.
			return next_id
		"vote":
			if not _votes.has(next_id):
				_votes[next_id] = []
			if not _votes[next_id].has(voter):
				_votes[next_id].append(voter)
			return _resolve_vote()
		"dm-confirm":
			# Stage it; the DM must confirm via dm_confirm_choice().
			_pending_choice = {"next_id": next_id, "text": choice_text}
			return ""
		_:
			return next_id


## Tally votes; a strict majority of the current roster decides, else "".
func _resolve_vote() -> String:
	var roster := Net.peers.size()
	var needed := int(floor(roster / 2.0)) + 1
	var best_id := ""
	var best := 0
	for id in _votes:
		var count: int = _votes[id].size()
		if count > best:
			best = count
			best_id = id
	if best >= needed:
		return best_id
	return ""


## DM confirms (or overrides) the pending choice in dm-confirm mode. Host/DM
## only. Passing "" confirms the staged choice; a non-empty id overrides it.
func dm_confirm_choice(override_id: String = "") -> bool:
	if not Net.active or not Net.require_dm():
		return false
	if _pending_choice.is_empty():
		return false
	var chosen: String = override_id if override_id != "" else str(_pending_choice["next_id"])
	var text := str(_pending_choice.get("text", ""))
	if Net.is_host():
		_commit_choice(chosen, text)
	else:
		_req_dm_confirm.rpc_id(1, chosen, text)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _req_dm_confirm(chosen: String, text: String) -> void:
	if not Net.require_host() or not Net.require_dm(multiplayer.get_remote_sender_id()):
		return
	_commit_choice(chosen, text)


## Host: commit an arbitrated choice — broadcast the decision, clear tallies,
## then drive the authoritative advance so the party's passage moves on every
## peer (this is the step that makes a CLIENT's choice actually change state:
## the client only requested; the host owns the mutation).
func _commit_choice(next_id: String, choice_text: String) -> void:
	_votes.clear()
	_pending_choice.clear()
	_broadcast_choice.rpc(next_id, choice_text)
	choice_committed.emit(next_id)
	if _session != null:
		# advance_passage runs through the patched guard -> intercept_advance
		# (host) -> broadcasts _apply_advance to clients + mutates locally.
		_session.advance_passage(next_id)


@rpc("authority", "call_remote", "reliable")
func _broadcast_choice(next_id: String, choice_text: String) -> void:
	if _session != null:
		_session.choice_made.emit(next_id, choice_text)
	choice_committed.emit(next_id)


# --- roll interception -------------------------------------------------------

## Called by the patched SessionState.roll / roll_luck. Awaitable; returns the
## success bool. Host rolls authoritatively (seeded) and broadcasts; a client
## asks the host and awaits the broadcast result.
func intercept_roll(stat: String, is_luck: bool) -> bool:
	if not Net.active:
		# Should not happen (guard checks Net.active) — fall back to a local roll.
		return await _local_roll(stat, is_luck)
	if Net.is_host():
		return await _host_roll(stat, is_luck)
	# Client: request the roll, await the authoritative result.
	_req_roll.rpc_id(1, stat, is_luck)
	var result: Dictionary = await roll_received
	return bool(result.get("success", false))


func _local_roll(stat: String, is_luck: bool) -> bool:
	var dice := get_node_or_null("/root/Dice")
	if dice == null:
		return false
	if is_luck:
		return await dice.test_luck()
	return await dice.test(stat)


## client -> host: roll `stat` for me.
@rpc("any_peer", "call_remote", "reliable")
func _req_roll(stat: String, is_luck: bool) -> void:
	if not Net.require_host():
		return
	await _host_roll(stat, is_luck)


## Host rolls with the shared seed, applies any staged DM override, records the
## result into the session log, and broadcasts it for every peer to replay.
func _host_roll(stat: String, is_luck: bool) -> bool:
	var dice := get_node_or_null("/root/Dice")
	if dice == null:
		return false
	var ok: bool = await _local_roll(stat, is_luck)
	# DM fudge: replace the pending result before it is recorded / broadcast.
	if not _pending_override.is_empty():
		dice.last_result = _pending_override.duplicate(true)
		dice.last_success = bool(_pending_override.get("success", ok))
		ok = dice.last_success
		_pending_override = {}
	_record_and_broadcast(dice.last_result)
	return ok


## host -> clients: replay an authoritative roll result.
@rpc("authority", "call_remote", "reliable")
func _apply_roll(result: Dictionary) -> void:
	var dice := get_node_or_null("/root/Dice")
	if dice != null:
		dice.last_result = result.duplicate(true)
		dice.last_success = bool(result.get("success", false))
	_record_roll(result)
	roll_received.emit(result)


## Host path: record locally and push to clients (and satisfy the host's own
## awaiting caller via roll_received).
func _record_and_broadcast(result: Dictionary) -> void:
	_record_roll(result)
	_apply_roll.rpc(result)
	roll_received.emit(result)


## Append to SessionState.roll_log and re-emit roll_resolved (mirrors the
## template's private _record_roll, kept here so the guard patch stays tiny).
func _record_roll(result: Dictionary) -> void:
	if _session == null:
		return
	_session.roll_log.append(result.duplicate(true))
	_session.roll_resolved.emit(result)


# --- DM seat hooks (the template's two no-ops, now real) ---------------------

## DM seat: force the party's book to a passage. Host-authoritative; returns
## true only when the local peer holds the DM seat AND a session is live.
func dm_push_passage(passage_id: String) -> bool:
	if not Net.active or not Net.is_dm():
		return false
	if Net.is_host():
		# Host + DM: broadcast to clients, then apply locally.
		_apply_advance.rpc(passage_id)
		if _session != null:
			_session.set_meta(APPLYING_META, true)
			_session.advance_passage(passage_id)
			_session.remove_meta(APPLYING_META)
		return true
	# Client DM: ask the host to do it under a DM-verified RPC.
	_req_dm_push.rpc_id(1, passage_id)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _req_dm_push(passage_id: String) -> void:
	if not Net.require_host() or not Net.require_dm(multiplayer.get_remote_sender_id()):
		return
	_apply_advance.rpc(passage_id)
	if _session != null:
		_session.set_meta(APPLYING_META, true)
		_session.advance_passage(passage_id)
		_session.remove_meta(APPLYING_META)


## DM seat: stage a dice result to replace the next host roll (a fudge).
## Returns true only when the local peer holds the DM seat AND a session is live.
func dm_override_roll(result: Dictionary) -> bool:
	if not Net.active or not Net.is_dm():
		return false
	if Net.is_host():
		_pending_override = result.duplicate(true)
		return true
	_req_override.rpc_id(1, result)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _req_override(result: Dictionary) -> void:
	if not Net.require_host() or not Net.require_dm(multiplayer.get_remote_sender_id()):
		return
	_pending_override = result.duplicate(true)
