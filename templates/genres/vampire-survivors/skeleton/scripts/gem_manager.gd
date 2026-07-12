extends Node2D
## res://scripts/gem_manager.gd
## Pooled XP gems with magnet pickup, driven by one loop (same swarm pattern
## as enemy_spawner.gd): a gem idles where it dropped until the player's
## magnet_radius reaches it, then flies to the player and is collected within
## collect_radius, feeding player.gain_xp(). Dead gems return to the pool.

signal gem_collected(value: int)

@export var gem_scene: PackedScene = preload("res://scenes/xp_gem.tscn")
## Flight speed of a magnetized gem, in px/s.
@export var fly_speed := 480.0
## Distance at which a gem is absorbed, in pixels.
@export var collect_radius := 20.0

var _active: Array[Node2D] = []
var _pool: Array[Node2D] = []


func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return
	var ppos := player.global_position
	var magnet: float = player.get_stat("magnet_radius") \
			if player.has_method("get_stat") else 0.0
	var i := _active.size() - 1
	while i >= 0:
		var gem: Node2D = _active[i]
		var dist := gem.global_position.distance_to(ppos)
		if dist <= collect_radius:
			if player.has_method("gain_xp"):
				player.gain_xp(gem.value)
			gem_collected.emit(gem.value)
			gem.deactivate()
			_pool.append(gem)
			_active.remove_at(i)
		elif dist <= magnet:
			gem.global_position = gem.global_position.move_toward(ppos, fly_speed * delta)
		i -= 1


## Drop a gem worth `value` XP at `pos` (wired to the spawner's enemy_killed).
func spawn_gem(pos: Vector2, value := 1) -> Node2D:
	var gem: Node2D
	if _pool.is_empty():
		gem = gem_scene.instantiate()
		add_child(gem)
	else:
		gem = _pool.pop_back()
	gem.activate(pos, value)
	_active.append(gem)
	return gem


func active_count() -> int:
	return _active.size()
