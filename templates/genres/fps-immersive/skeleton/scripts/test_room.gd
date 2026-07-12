extends "res://addons/cogito/SceneManagement/cogito_scene.gd"
## res://scripts/test_room.gd
## COGITO scene root for the test room: inherits the addon's scene contract
## (registers itself with CogitoSceneManager, connector spawn points, optional
## bgm) and adds the boot probe proving the immersive-sim core loop is live —
## a COGITO player registered with the scene manager plus interactable objects
## (door + pickup) in the "interactable" group.


func _ready() -> void:
	_emit_boot_probe.call_deferred()


func _emit_boot_probe() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: Node = CogitoSceneManager._current_player_node
	var interactables := get_tree().get_nodes_in_group(&"interactable").size()
	print("DEBUG: fps-immersive core loop ready — player=%s interactables=%d door=%s pickup=%s" % [
		is_instance_valid(player),
		interactables,
		is_instance_valid(get_node_or_null(^"Door")),
		is_instance_valid(get_node_or_null(^"HealthPotion")),
	])
