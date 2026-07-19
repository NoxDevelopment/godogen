extends "res://addons/MetroidvaniaSystem/Template/Scripts/MetSysGame.gd"
## res://scripts/main.gd
## Game shell built on MetSys' MetSysGame template: boots the map system, loads
## the starting room, drives automatic room transitions and clamps the player
## camera to the current room's bounds.

const STARTING_ROOM := "res://maps/room_a.tscn"


func _ready() -> void:
	# Fresh MetSys state (matters when returning from a menu / reloading).
	MetSys.reset_state()
	MetSys.set_save_data()

	# MetSysGame tracks this node's position on the world map every physics tick.
	set_player($Player)

	# Automatic scene swapping when the player crosses into another room's cell.
	add_module("RoomTransitions.gd")

	room_loaded.connect(_on_room_loaded, CONNECT_DEFERRED)
	await load_room(STARTING_ROOM)

	var spawn := map.get_node_or_null(^"SpawnPoint")
	if spawn:
		player.position = spawn.position


func _on_room_loaded() -> void:
	# Untyped on purpose: MetSys is an autoload, invisible to --check-only runs.
	var room = MetSys.get_current_room_instance()
	if room:
		room.adjust_camera_limits($Player/Camera2D)
