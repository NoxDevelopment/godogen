extends Node3D
## res://scripts/item_spawner.gd
## Arena item spawner (group "items"): a spinning color-coded blockout item
## (health/armor/shells/rockets) that a walking player collects on contact —
## distance-checked against the player each physics frame, no Area needed.
## Collection only consumes the item when the player can actually use it
## (full health refuses a medkit, Quake style); a consumed spawner counts a
## respawn_time countdown and pops back. try_give() is public — the boot
## probe collects through the same routine walk-over uses.

signal picked_up(kind: String, amount: int)
signal respawned(kind: String)

const COLORS := {
	"health": Color(0.9, 0.25, 0.25),
	"armor": Color(0.25, 0.75, 0.35),
	"shells": Color(0.95, 0.8, 0.25),
	"rockets": Color(0.95, 0.5, 0.15),
}

@export_enum("health", "armor", "shells", "rockets") var kind := "health"
@export var amount := 25
@export var respawn_time := 10.0
@export var pickup_radius := 1.1
@export var spin_speed := 2.0

var available := true

var _countdown := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group(&"items")
	_build_item()


func _physics_process(delta: float) -> void:
	if _mesh:
		_mesh.rotate_y(spin_speed * delta)
	if not available:
		_countdown -= delta
		if _countdown <= 0.0:
			available = true
			_mesh.visible = true
			respawned.emit(kind)
		return
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var player := players[0] as CharacterBody3D
	if player.is_dead():
		return
	var to := player.global_position - global_position
	if Vector2(to.x, to.z).length() <= pickup_radius and absf(to.y) < 1.5:
		try_give(player)


## Hand the item to the player. False when they cannot use it (nothing is
## consumed and the item stays up).
func try_give(player: CharacterBody3D) -> bool:
	if not available:
		return false
	var consumed := false
	match kind:
		"health":
			consumed = player.add_health(amount)
		"armor":
			consumed = player.add_armor(amount)
		"shells", "rockets":
			consumed = player.weapons.add_ammo(kind, amount)
	if not consumed:
		return false
	available = false
	_mesh.visible = false
	_countdown = respawn_time
	picked_up.emit(kind, amount)
	return true


func _build_item() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = COLORS[kind]
	material.emission_enabled = true
	material.emission = COLORS[kind]
	material.emission_energy_multiplier = 0.35
	box.material = material
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.7, 0.0)
	add_child(_mesh)
	var base := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.06
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color(0.4, 0.42, 0.48)
	disc.material = base_material
	base.mesh = disc
	base.position = Vector3(0.0, 0.03, 0.0)
	add_child(base)
