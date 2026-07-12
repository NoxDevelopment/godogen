extends Node3D
## res://scripts/obstacle.gd
## Unit-killing hazard (group "obstacles"): a spike strip covering an AABB of
## the track. While the crowd passes through its z-band it hit-tests every
## unit slot against the box and kills the ones inside — individual units
## die, the rest of the crowd flows on. No physics: the same per-slot
## positions the MultiMesh renders are the positions tested.

signal units_killed(amount: int, total_kills: int)

## Hazard extents: x = width across the track, z = depth along it.
@export var size := Vector3(2.8, 0.9, 0.6)
## Only scan the crowd when its leader is within this many units in z.
@export var active_window := 8.0

var kills := 0


func _ready() -> void:
	add_to_group(&"obstacles")
	_build_spikes()


func _physics_process(_delta: float) -> void:
	var crowd := get_tree().get_first_node_in_group(&"player") as Node3D
	if crowd == null or crowd.count <= 0:
		return
	if absf(crowd.global_position.z - global_position.z) > active_window:
		return
	var killed := 0
	var i: int = crowd.count - 1
	while i >= 0:
		var local: Vector3 = crowd.unit_position(i) - global_position
		if absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5:
			crowd.kill_unit_at(i, "obstacle")
			killed += 1
		i -= 1
	if killed > 0:
		kills += killed
		units_killed.emit(killed, kills)


func _build_spikes() -> void:
	var spike_count := maxi(int(size.x / 0.55), 2)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.2
	mesh.height = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.2)
	mesh.material = mat
	for s in spike_count:
		var spike := MeshInstance3D.new()
		spike.mesh = mesh
		var t := (float(s) + 0.5) / float(spike_count)
		spike.position = Vector3((t - 0.5) * size.x, 0.45, 0.0)
		add_child(spike)
