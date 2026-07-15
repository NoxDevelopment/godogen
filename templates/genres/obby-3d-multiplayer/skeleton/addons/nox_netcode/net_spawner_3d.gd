extends Node
## res://addons/nox_netcode/net_spawner_3d.gd
## Realtime profile — the 3D MultiplayerSpawner wiring (the Node3D-positioned twin
## of net_spawner.gd). Add this node under a 3D level root; point `player_scene`
## at your NetPlayer3D avatar and `avatar_parent` at the node that should hold the
## avatars. Spawn points are read from the `net_spawn_point` group (any Node3D /
## Marker3D), assigned to peers in join order.
##
## The server is the spawn authority: it calls spawn() and the MultiplayerSpawner
## replicates the instantiation to every client through a custom spawn_function,
## so all peers build the same avatar deterministically from {peer, index}.

## The avatar to instantiate per peer (a scene whose root uses net_player_3d.gd).
@export var player_scene: PackedScene
## Where avatars are parented. Empty = this node's parent (the level root).
@export var avatar_parent_path: NodePath
## Fallback spawn positions used when no `net_spawn_point` nodes exist.
@export var fallback_spawns: PackedVector3Array = PackedVector3Array([
	Vector3(-3, 1, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(3, 1, 0),
])

var _spawner: MultiplayerSpawner
var _avatar_parent: Node
var _spawn_index := 0


func _ready() -> void:
	_avatar_parent = get_node_or_null(avatar_parent_path)
	if _avatar_parent == null:
		_avatar_parent = get_parent()

	_spawner = MultiplayerSpawner.new()
	_spawner.name = "PlayerSpawner"
	_spawner.spawn_path = _spawner.get_path_to(_avatar_parent)
	_spawner.spawn_function = Callable(self, "_spawn_avatar")
	add_child(_spawner)

	# React to the shared-core lobby lifecycle. Only the host spawns; clients
	# receive the replicated instances.
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.game_started.connect(_on_game_started)


## Host-only: spawn every peer already present when the round starts.
func _on_game_started() -> void:
	if not Net.is_host():
		return
	for id in Net.peers.keys():
		_spawn_for(int(id))


func _on_peer_joined(id: int, _info: Dictionary) -> void:
	if not Net.is_host():
		return
	# Spawn late joiners immediately; if the round hasn't started, _on_game_started
	# will handle everyone at once (spawn() is idempotent-guarded below).
	_spawn_for(id)


func _on_peer_left(id: int) -> void:
	if not Net.is_host():
		return
	var existing := _avatar_parent.get_node_or_null(NodePath(str(id)))
	if existing != null:
		existing.queue_free()


func _spawn_for(peer: int) -> void:
	if _avatar_parent.has_node(NodePath(str(peer))):
		return  # already spawned
	_spawner.spawn({"peer": peer, "index": _spawn_index})
	_spawn_index += 1


## The custom spawn function (runs on EVERY peer via the spawner). Builds the
## avatar, names it after the peer id (net_player_3d.gd reads that for authority),
## and drops it on an assigned spawn point.
func _spawn_avatar(data: Dictionary) -> Node:
	var peer := int(data.get("peer", 1))
	var index := int(data.get("index", 0))
	var avatar: Node3D = player_scene.instantiate()
	avatar.name = str(peer)
	avatar.position = _spawn_position(index)
	return avatar


func _spawn_position(index: int) -> Vector3:
	var points := get_tree().get_nodes_in_group(&"net_spawn_point")
	if points.size() > 0:
		var node := points[index % points.size()] as Node3D
		if node != null:
			return node.global_position
	if fallback_spawns.size() > 0:
		return fallback_spawns[index % fallback_spawns.size()]
	return Vector3.ZERO
