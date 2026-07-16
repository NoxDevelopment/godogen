extends Node
## res://addons/nox_netcode/euro_net_bridge.gd
## Autoload "EuroNet" — the HOST-AUTHORITATIVE action bus for the Euro engine-builder
## (STAGE 3 of the play-mode matrix). It is to EuroEngine what the vendored
## session_bridge.gd (NetBridge) is to the gamebook's SessionState: the same
## authority-turn model — host validates → applies → broadcasts; clients request —
## but generalized for a competitive board game where EVERY seat is an equal player
## (there is no DM). It rides on the shared `Net` autoload (net_session.gd) for
## transport / lobby / roster / shared-seed, and drives GameManager's EuroEngine.
##
## AUTHORITY MODEL (host = peer id 1 = the single source of truth):
##   * SEED — the host broadcasts one shared RNG seed at Start (via Net). Every peer
##     builds engine.setup(seed, n) with it, so the deck/board/opening hands are
##     identical everywhere. Determinism is the whole trick: broadcasting the APPLIED
##     ACTION (not full state) keeps peers in lockstep because the engine is a pure,
##     seeded state machine.
##   * SEATS — the host maps lobby peers → engine seats deterministically (peer ids
##     sorted ascending; the host, id 1, is always seat 0). Empty seats become
##     host-resolved AI. The host DICTATES the lineup (_setup_game, call_local); a
##     client never computes or claims its own seat.
##   * APPLY — a client REQUESTS an action for ITS seat (@rpc to the host). The host
##     re-checks require_host(), verifies the sender actually OWNS that seat (never
##     trusts the claim), re-validates engine.is_legal(seat, action), applies it,
##     then BROADCASTS the applied action (@rpc reliable) to every peer, who applies
##     it identically. AI seats + the host's own seat are resolved locally by the
##     host and broadcast the same way. Clients NEVER mutate shared state directly —
##     they only render off the broadcast (via GameManager's dispatcher + signals).
##
## OFFLINE INERTNESS: is_online() is false until Net hosts/joins AND the game has
## started. GameManager._net_active() gates on it, so with no session the bridge does
## NOTHING and single-player / hotseat / LLM modes are byte-identical.
##
## NOTE ON NAMING: this autoload is "EuroNet", NOT "NetBridge" — the gamebook's
## NetBridge (SessionState/DM bridge) is deliberately NOT vendored here (a euro game
## has no DM seat). Keeping a distinct name also lets the shared net_probe.tscn test
## the Net CORE cleanly (it finds no /root/NetBridge and skips the DM path).

## Emitted after an action is applied to the local engine (host apply, or a host
## broadcast landing on a client). The board refreshes off these.
signal action_applied(seat: int, action: Dictionary)
## Emitted after the turn advances — carries the new current seat.
signal turn_changed(seat: int)
## Emitted once when the networked game ends — carries the winning seat.
signal game_over(winner: int)

## seat index -> owning peer id (0 == a host-resolved AI seat). Host + clients hold
## the same map (the host dictates it in _setup_game). Used to reject seat spoofing.
var _seat_owner: Dictionary = {}
## True between _setup_game and teardown — the "a networked game is live" flag.
var _game_active := false

var _gm: Node = null


func _ready() -> void:
	add_to_group(&"persistent")
	_gm = get_node_or_null(^"/root/GameManager")
	# The host owns Start: when Net signals game_started, the host resolves the
	# lineup and pushes it (with the shared seed) to every peer. Clients do nothing
	# on their own game_started — they wait for the host's authoritative _setup_game.
	Net.game_started.connect(_on_game_started)
	Net.session_ended.connect(_on_session_ended)


# =====================================================================
#  Online-state query (the offline-inertness gate)
# =====================================================================

## True only when a live Net session owns a started game. GameManager gates every
## network branch on this; false == pure local play.
func is_online() -> bool:
	return Net.active and _game_active


# =====================================================================
#  Game start — host dictates lineup + shared seed to every peer
# =====================================================================

func _on_game_started() -> void:
	# Only the host resolves + broadcasts the lineup. Net.start() already broadcast
	# the shared seed (Net.session_seed) before this, so it is set on every peer.
	if not Net.is_host():
		return
	var lineup := _host_resolve_lineup()
	_setup_game.rpc(
		int(lineup["num_players"]),
		int(lineup["seed"]),
		lineup["owners"],
		lineup["names"])


## Host-side: deterministically map the lobby roster onto engine seats. Peer ids
## sorted ascending → the host (id 1) takes seat 0, other peers follow; any seats
## beyond the roster (up to a 2..5 table) are host-resolved AI (owner 0).
func _host_resolve_lineup() -> Dictionary:
	var ids: Array = Net.peers.keys()
	ids.sort()
	var roster := ids.size()
	var total := clampi(maxi(roster, 2), 2, 5)
	var owners: Array = []
	var names: Array = []
	for i in total:
		if i < roster:
			var pid := int(ids[i])
			owners.append(pid)
			names.append(String(Net.peers[pid].get("name", "P%d" % (i + 1))))
		else:
			owners.append(0)  # AI fill (host-resolved)
			names.append("P%d AI" % (i + 1))
	return {
		"num_players": total,
		"seed": int(Net.session_seed),
		"owners": owners,
		"names": names,
	}


## host -> all (call_local): build THIS peer's engine + lineup, then show the board.
## Every peer gets the SAME seed + owner map; the per-peer CONTROLLER kinds differ
## only in WHO is local: this peer's own seat is HUMAN_LOCAL, every other peer's
## seat is REMOTE, and (host only) AI-filled seats are AI_HEURISTIC (the host
## resolves + broadcasts them; on a client those same seats read as REMOTE).
@rpc("authority", "call_local", "reliable")
func _setup_game(num_players: int, seed_value: int, owners: Array, names: Array) -> void:
	_seat_owner = {}
	for i in owners.size():
		_seat_owner[i] = int(owners[i])
	var me := Net.local_id()
	var host := Net.is_host()
	var kinds: Array = []
	for i in num_players:
		var owner := int(owners[i]) if i < owners.size() else 0
		if owner == me and owner != 0:
			kinds.append(EuroEngine.ControllerKind.HUMAN_LOCAL)
		elif host and owner == 0:
			kinds.append(EuroEngine.ControllerKind.AI_HEURISTIC)
		else:
			kinds.append(EuroEngine.ControllerKind.REMOTE)
	_game_active = true
	if _gm == null:
		_gm = get_node_or_null(^"/root/GameManager")
	if _gm != null:
		_gm.begin_networked_game(kinds, names, seed_value, num_players)
	# Leave the lobby for the live board. Deferred so we never change scene from
	# inside an RPC dispatch. Guard: navigate ONLY when the peer is actually in the
	# lobby — the normal Host/Join → Start flow always is. This keeps the shared
	# net_probe (a standalone Net-core self-test that also calls Net.start()) from
	# having its own scene ripped out from under it, and is a no-op if we are already
	# on the board. Every real peer (host + clients) does this identically.
	var tree := get_tree()
	var scene := tree.current_scene
	if scene != null and String(scene.scene_file_path) == "res://addons/nox_netcode/lobby.tscn":
		tree.change_scene_to_file.call_deferred("res://scenes/board.tscn")


# =====================================================================
#  The action bus — request (client) / validate+apply+broadcast (host)
# =====================================================================

## Called by GameManager.submit_action when a LOCAL human commits an action online.
## HOST: validate + apply + broadcast + continue the turn locally. CLIENT: send a
## request to the host and wait — the host's broadcast is what actually applies it,
## so a client never mutates shared state on its own.
func submit_local(seat: int, action: Dictionary) -> bool:
	if not is_online() or _gm == null:
		return false
	var engine: EuroEngine = _gm.engine
	if Net.is_host():
		if not engine.is_legal(seat, action):
			return false
		_host_apply_and_continue(seat, action)
		return true
	# Client: a local legality pre-check for snappy UI (the host RE-VALIDATES and is
	# the only authority). Then request; suppress local input until the broadcast.
	if not engine.is_legal(seat, action):
		return false
	_req_action.rpc_id(1, seat, action)
	_gm.awaiting_input = false
	_gm.changed.emit()
	return true


## client -> host: "apply THIS action for my seat". The host trusts NOTHING: it
## re-checks it is the host, that the sender actually owns the seat, that it is that
## seat's turn, and that the action is legal — then applies + broadcasts. A spoofed
## seat / out-of-turn / illegal request is dropped, state unchanged.
@rpc("any_peer", "call_remote", "reliable")
func _req_action(seat: int, action: Dictionary) -> void:
	if not Net.require_host() or not is_online() or _gm == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if int(_seat_owner.get(seat, -1)) != sender:
		push_warning("EuroNet: peer %d tried to act on seat %d it does not own — dropped." % [sender, seat])
		return
	var engine: EuroEngine = _gm.engine
	if engine.current != seat:
		return  # not this seat's turn (a stale / racing request)
	if not engine.is_legal(seat, action):
		return  # host is the authority — reject an illegal client request outright
	_host_apply_and_continue(seat, action)


## Host authoritative apply: mutate the canonical engine, tell the clients, then let
## the dispatcher resolve every following AI seat and stop at the next human/remote.
func _host_apply_and_continue(seat: int, action: Dictionary) -> void:
	var engine: EuroEngine = _gm.engine
	engine.apply_action(seat, action)
	engine.advance_turn()
	host_broadcast_and_notify(seat, action)
	_gm.resume_after_network()


## Host -> clients broadcast of an APPLIED action + local signal emission. Called
## for the host's own seat, host-resolved AI seats (from the dispatcher), and
## resolved client requests. On a solo host (no clients) the rpc simply reaches
## nobody — the notifications still fire so the board refreshes.
func host_broadcast_and_notify(seat: int, action: Dictionary) -> void:
	_apply_broadcast.rpc(seat, action)
	_emit_applied(seat, action)


## host -> clients (call_remote): apply the authoritative action to the replica
## engine. The client's engine is in lockstep (same seed, same prior actions), so
## is_legal holds; if it ever did not, that is a desync and we refuse to corrupt
## state further. After applying we advance + re-enter the client's dispatcher,
## which walks to the next REMOTE stop or opens input on this peer's own seat.
@rpc("authority", "call_remote", "reliable")
func _apply_broadcast(seat: int, action: Dictionary) -> void:
	if Net.is_host() or not is_online() or _gm == null:
		return
	var engine: EuroEngine = _gm.engine
	if not engine.is_legal(seat, action):
		push_error("EuroNet: host broadcast rejected on client (seat %d, action %s) — desync." % [seat, action])
		return
	engine.apply_action(seat, action)
	engine.advance_turn()
	_emit_applied(seat, action)
	_gm.resume_after_network()


## Emit the board-facing signals after a local apply/advance. game_over fires once;
## otherwise turn_changed carries the new current seat.
func _emit_applied(seat: int, action: Dictionary) -> void:
	action_applied.emit(seat, action)
	var engine: EuroEngine = _gm.engine
	if engine.game_over:
		game_over.emit(engine.winner)
	else:
		turn_changed.emit(engine.current)


# =====================================================================
#  Teardown
# =====================================================================

func _on_session_ended(_reason: String) -> void:
	_game_active = false
	_seat_owner = {}


# --- "persistent" group contract (no per-session game state to persist here;
#     GameManager already saves the whole EuroEngine, Net saves the seed). ------

func save_data() -> Dictionary:
	return {}


func load_data(_data: Dictionary) -> void:
	pass
