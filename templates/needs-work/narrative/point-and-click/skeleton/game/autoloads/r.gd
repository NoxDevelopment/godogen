@tool
extends "res://addons/popochiu/engine/interfaces/i_room.gd"

# classes ----
const PRStudio := preload("res://game/rooms/studio/room_studio.gd")
# ---- classes

# nodes ----
var Studio: PRStudio : get = get_Studio
# ---- nodes

# functions ----
func get_Studio() -> PRStudio: return get_runtime_room("Studio")
# ---- functions

