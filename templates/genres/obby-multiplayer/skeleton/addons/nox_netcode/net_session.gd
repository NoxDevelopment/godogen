extends Node
## res://addons/nox_netcode/net_session.gd
## Autoload "Net" — the shared multiplayer session core for the nox_netcode
## drop-in. BOTH profiles (authority-turn, realtime) ride on this one autoload.
##
## Responsibilities (per MULTIPLAYER_TEMPLATE_SPEC.md "Shared core"):
##   - Transport selection: build the right MultiplayerPeer (ENet / WebSocket;
##     WebRTC is an honest not-bundled error) and assign it.
##   - Peer lifecycle: wrap the raw multiplayer signals into a clean, UI-facing
##     set (peer_joined / peer_left / session_started / session_ended /
##     connection_error) plus a host-owned `peers` dictionary.
##   - Lobby state: display names, ready flags, seat assignment (incl. the DM
##     seat), and a host-controlled Start gate.
##   - Authority helpers: is_host / local_id / is_dm / assign_seat /
##     require_host / require_dm — the guards the profiles' RPC validation uses.
##   - Determinism: a shared RNG seed the host broadcasts at Start, so dice and
##     any procedural content replay identically across peers.
##   - Disconnect policy: pause-and-wait / drop-and-continue / (host-migration
##     hook is reserved for a later phase).
##
## Design contract: host-authoritative. Clients REQUEST; the host VALIDATES then
## BROADCASTS; clients apply and render. `active` is false until host()/join()
## succeeds, so every network guard the profiles inject is inert offline — the
## single-player core of an opted-in template is byte-identical.

## The DM seat identifier the seat picker / bridge use.
const SEAT_DM := "dm"
const SEAT_PLAYER := "player"

# --- UI-facing signals (the clean surface scenes/lobby bind to) --------------

## A peer entered the lobby. `info` = {name, ready, seat}.
signal peer_joined(id: int, info: Dictionary)
## A peer left (disconnect or graceful).
signal peer_left(id: int)
## The transport is up and this peer is part of a session (host: immediately;
## client: on connected_to_server).
signal session_started()
## The session ended. `reason`: "left" | "host_disconnected" | "closed".
signal session_ended(reason: String)
## A transport/connection problem the UI should show. Never fatal to the app.
signal connection_error(message: String)
## The lobby roster/seats/ready-flags changed (host broadcast applied).
signal lobby_changed()
## The host pressed Start — the game proper should begin on every peer.
signal game_started()
## The host broadcast the shared RNG seed (determinism handshake).
signal seed_broadcast(session_seed: int)
## The session paused (a member dropped under pause-and-wait) or resumed (they
## rejoined). The game layer gates progress on `Net.paused`.
signal session_paused(is_paused: bool)

# --- Session state -----------------------------------------------------------

## True while a transport is assigned and we are in a session. The profiles'
## injected guards short-circuit on `not Net.active`, so offline == untouched.
var active := false
## True on the host (peer id 1), false on clients.
var is_hosting := false
## Host-owned roster: peer_id -> {name:String, ready:bool, seat:String}.
var peers: Dictionary = {}
## The peer id currently holding the DM seat (0 = seat empty).
var dm_peer: int = 0
## The shared RNG seed for this session (0 until the host broadcasts it).
var session_seed: int = 0
## True when a pause-and-wait session is holding for a dropped member to rejoin.
var paused := false
## The local player's display name (used when we introduce ourselves).
var local_name := "Player"

# --- Resolved config (host()/join() fill these) ------------------------------

var _transport := "enet"
var _address := "127.0.0.1"
var _port := 24567
var _max_peers := 8
var _profile := "authority-turn"
var _arbitration := "dm-confirm"
var _disconnect_policy := "pause-and-wait"

var _bound := false
var _peer: MultiplayerPeer = null


func _enter_tree() -> void:
	add_to_group(&"persistent")


func _ready() -> void:
	# Pull project-baked defaults (the generator writes nox_netcode/*). No
	# network activity here — the autoload is dormant until host()/join().
	_transport = _setting("transport", _transport)
	_port = int(_setting("default_port", _port))
	_max_peers = int(_setting("max_peers", _max_peers))
	_profile = _setting("profile", _profile)
	_arbitration = _setting("arbitration", _arbitration)
	_disconnect_policy = _setting("disconnect_policy", _disconnect_policy)


# --- Public API: host / join / leave -----------------------------------------

## Start hosting. `config` overrides any project default:
##   {transport, port, max_peers, player_name, profile, arbitration,
##    disconnect_policy}. Returns OK or an Error.
func host(config: Dictionary = {}) -> Error:
	if active:
		leave()
	_apply_config(config)
	var server := _make_server()
	if server == null:
		return ERR_CANT_CREATE
	multiplayer.multiplayer_peer = server
	_peer = server
	is_hosting = true
	active = true
	# Seat the host. Gamebooks default the host into the DM seat; realtime
	# leaves everyone a plain player.
	var host_seat := SEAT_PLAYER
	if _profile == "authority-turn":
		host_seat = SEAT_DM
		dm_peer = 1
	peers = {1: {"name": local_name, "ready": true, "seat": host_seat}}
	_bind_multiplayer()
	session_started.emit()
	peer_joined.emit(1, peers[1])
	lobby_changed.emit()
	return OK


## Join a host. `config` overrides defaults; `address` is the host's IP (ENet)
## or the ws:// host (WebSocket). Returns OK once the transport is building
## (connection success arrives asynchronously via session_started).
func join(config: Dictionary = {}) -> Error:
	if active:
		leave()
	_apply_config(config)
	var client := _make_client()
	if client == null:
		return ERR_CANT_CONNECT
	multiplayer.multiplayer_peer = client
	_peer = client
	is_hosting = false
	active = true
	peers = {}
	_bind_multiplayer()
	return OK


## Leave / shut down the session cleanly. Idempotent.
func leave() -> void:
	var was_active := active
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	active = false
	is_hosting = false
	peers = {}
	dm_peer = 0
	session_seed = 0
	paused = false
	if was_active:
		session_ended.emit("left")
		lobby_changed.emit()


# --- Public API: lobby actions -----------------------------------------------

## Toggle this peer's ready flag. Host applies directly; a client routes the
## request to the host, who re-broadcasts the roster.
func set_ready(flag: bool) -> void:
	if not active:
		return
	if is_hosting:
		if peers.has(1):
			peers[1]["ready"] = flag
			_broadcast_lobby()
	else:
		_hello_set_ready.rpc_id(1, flag)


## Request the DM seat (authority-turn). Host grants directly; a client asks
## the host. Only meaningful when the seat is empty or reassigned by the host.
func take_dm_seat() -> void:
	if not active:
		return
	if is_hosting:
		assign_seat(1, SEAT_DM)
	else:
		_req_dm_seat.rpc_id(1)


## Host-only: assign `seat` to `peer`. Enforces a single DM seat (assigning DM
## to one peer demotes the previous holder to a plain player). Re-broadcasts.
func assign_seat(peer: int, seat: String) -> void:
	if not is_hosting or not peers.has(peer):
		return
	if seat == SEAT_DM:
		if dm_peer != 0 and dm_peer != peer and peers.has(dm_peer):
			peers[dm_peer]["seat"] = SEAT_PLAYER
		dm_peer = peer
	elif dm_peer == peer:
		dm_peer = 0
	peers[peer]["seat"] = seat
	_broadcast_lobby()


## Host-only Start gate: broadcast the shared seed, then signal every peer to
## begin. No-op for clients and until at least the host is present.
func start() -> void:
	if not is_hosting or not active:
		return
	session_seed = _fresh_seed()
	_sync_seed.rpc(session_seed)
	_start_game.rpc()


# --- Authority helpers (the profiles' validation leans on these) -------------

func is_host() -> bool:
	return active and is_hosting


func local_id() -> int:
	if not active:
		return 0
	return multiplayer.get_unique_id()


## True when the LOCAL peer holds the DM seat.
func is_dm() -> bool:
	return active and dm_peer != 0 and dm_peer == local_id()


## True when `peer` holds the DM seat.
func is_dm_peer(peer: int) -> bool:
	return dm_peer != 0 and dm_peer == peer


## Guard for host-only RPC bodies. Call at the top of any handler that mutates
## shared truth: `if not Net.require_host(): return`.
func require_host() -> bool:
	return is_host()


## Guard for DM-only RPC bodies. `sender` defaults to the current RPC sender so
## a host-side handler validates the CALLER's claim, never trusts it.
func require_dm(sender: int = -1) -> bool:
	if not active:
		return false
	var who := sender
	if who < 0:
		who = multiplayer.get_remote_sender_id()
		if who == 0:
			who = local_id()  # a local (host-initiated) call
	return is_dm_peer(who)


func peer_name(id: int) -> String:
	return str(peers.get(id, {}).get("name", "peer %d" % id))


func profile() -> String:
	return _profile


func arbitration() -> String:
	return _arbitration


func transport() -> String:
	return _transport


# --- Transport construction --------------------------------------------------

func _make_server() -> MultiplayerPeer:
	match _transport:
		"enet":
			var p := ENetMultiplayerPeer.new()
			var err := p.create_server(_port, _max_peers)
			if err != OK:
				_fail("ENet server on port %d failed (err %d) — is the port already in use?" % [_port, err])
				return null
			return p
		"websocket":
			var p := WebSocketMultiplayerPeer.new()
			var err := p.create_server(_port)
			if err != OK:
				_fail("WebSocket server on port %d failed (err %d)." % [_port, err])
				return null
			return p
		"webrtc":
			_fail("WebRTC transport needs the webrtc-native GDExtension + a signaling server + STUN/TURN (spec Phase 5, not bundled). Use 'enet' for LAN or 'websocket' for web.")
			return null
		_:
			_fail("unknown transport '%s' (expected enet | websocket | webrtc)." % _transport)
			return null


func _make_client() -> MultiplayerPeer:
	match _transport:
		"enet":
			var p := ENetMultiplayerPeer.new()
			var err := p.create_client(_address, _port)
			if err != OK:
				_fail("ENet client to %s:%d failed (err %d)." % [_address, _port, err])
				return null
			return p
		"websocket":
			var p := WebSocketMultiplayerPeer.new()
			var url := _address
			if not url.begins_with("ws://") and not url.begins_with("wss://"):
				url = "ws://%s:%d" % [_address, _port]
			var err := p.create_client(url)
			if err != OK:
				_fail("WebSocket client to %s failed (err %d)." % [url, err])
				return null
			return p
		"webrtc":
			_fail("WebRTC transport needs the webrtc-native GDExtension + a signaling server (spec Phase 5, not bundled). Use 'enet' or 'websocket'.")
			return null
		_:
			_fail("unknown transport '%s'." % _transport)
			return null


# --- Raw multiplayer signal wiring -------------------------------------------

func _bind_multiplayer() -> void:
	if _bound:
		return
	_bound = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(_id: int) -> void:
	# Host learns of a raw connection; the client introduces itself via _hello
	# next (that carries its name), where it is seated. Nothing to do until then.
	pass


func _on_peer_disconnected(id: int) -> void:
	if is_hosting:
		var info: Dictionary = peers.get(id, {})
		peers.erase(id)
		if dm_peer == id:
			dm_peer = 0
		_broadcast_lobby()
		peer_left.emit(id)
		_apply_disconnect_policy(id, info)


func _on_connected_to_server() -> void:
	# Client side: transport up. Introduce ourselves so the host can seat us.
	_hello.rpc_id(1, local_name)
	session_started.emit()


func _on_connection_failed() -> void:
	_fail("could not reach the host (%s on %s:%d)." % [_transport, _address, _port])
	leave()


func _on_server_disconnected() -> void:
	active = false
	is_hosting = false
	peers = {}
	dm_peer = 0
	paused = false
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	session_ended.emit("host_disconnected")
	lobby_changed.emit()


# --- Lobby RPC surface (host owns the roster, broadcasts it whole) -----------

## client -> host: "here is my name". Host seats the new peer and re-broadcasts.
@rpc("any_peer", "call_remote", "reliable")
func _hello(their_name: String) -> void:
	if not is_hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	peers[id] = {"name": their_name, "ready": false, "seat": SEAT_PLAYER}
	_broadcast_lobby()
	peer_joined.emit(id, peers[id])
	# A pause-and-wait session resumes once a member (re)joins.
	if paused and _disconnect_policy == "pause-and-wait":
		paused = false
		session_paused.emit(false)


## client -> host: set my ready flag.
@rpc("any_peer", "call_remote", "reliable")
func _hello_set_ready(flag: bool) -> void:
	if not is_hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	if peers.has(id):
		peers[id]["ready"] = flag
		_broadcast_lobby()


## client -> host: request the DM seat.
@rpc("any_peer", "call_remote", "reliable")
func _req_dm_seat() -> void:
	if not is_hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	assign_seat(id, SEAT_DM)


## host -> all: replace the whole roster (single source of truth).
@rpc("authority", "call_remote", "reliable")
func _sync_lobby(roster: Dictionary, dm: int) -> void:
	peers = roster.duplicate(true)
	dm_peer = dm
	lobby_changed.emit()


## host -> all (call_local): the shared RNG seed. Every peer seeds its dice.
@rpc("authority", "call_local", "reliable")
func _sync_seed(seed_value: int) -> void:
	session_seed = seed_value
	var dice := get_node_or_null("/root/Dice")
	if dice != null and dice.has_method("set_seed"):
		dice.set_seed(seed_value)
	seed_broadcast.emit(seed_value)


## host -> all (call_local): begin the game proper.
@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	game_started.emit()


func _broadcast_lobby() -> void:
	if not is_hosting:
		return
	_sync_lobby.rpc(peers, dm_peer)
	lobby_changed.emit()


# --- Disconnect policy -------------------------------------------------------

func _apply_disconnect_policy(_id: int, _info: Dictionary) -> void:
	match _disconnect_policy:
		"pause-and-wait":
			# A party shouldn't advance without a member: pause and hold the
			# session (roster + seed) alive for a rejoin. The game layer gates
			# progress on Net.paused / session_paused.
			if not paused:
				paused = true
				session_paused.emit(true)
		"drop-and-continue":
			# The course keeps running; nothing to hold.
			pass
		_:
			pass


# --- Config / settings helpers ----------------------------------------------

func _apply_config(config: Dictionary) -> void:
	_transport = str(config.get("transport", _transport))
	_address = str(config.get("address", _address))
	_port = int(config.get("port", _port))
	_max_peers = int(config.get("max_peers", _max_peers))
	_profile = str(config.get("profile", _profile))
	_arbitration = str(config.get("arbitration", _arbitration))
	_disconnect_policy = str(config.get("disconnect_policy", _disconnect_policy))
	if config.has("player_name"):
		local_name = str(config["player_name"])


func _setting(key: String, fallback):
	var full := "nox_netcode/%s" % key
	if ProjectSettings.has_setting(full):
		return ProjectSettings.get_setting(full)
	return fallback


func _fresh_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi())


func _fail(message: String) -> void:
	push_error("[nox_netcode] " + message)
	connection_error.emit(message)


# --- "persistent" group contract (host snapshot = the party save) ------------

func save_data() -> Dictionary:
	return {
		"session_seed": session_seed,
		"dm_peer": dm_peer,
	}


func load_data(data: Dictionary) -> void:
	session_seed = int(data.get("session_seed", 0))
	dm_peer = int(data.get("dm_peer", 0))
