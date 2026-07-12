extends Node3D
## res://scripts/finish_line.gd
## Finish line + end tower: crossing the line compares the surviving crowd
## against boss_count — strictly more units storms the tower (win), anything
## else is held off (lose). Emits `finished` once; main.gd turns it into the
## run summary + GameManager flags. Score = surviving units.

signal finished(survivors: int, boss_count: int, win: bool)

## The tower's defender count — beat it (strictly) to win.
@export var boss_count := 5
@export var line_width := 9.6

var evaluated := false


func _ready() -> void:
	_build_visuals()


func _physics_process(_delta: float) -> void:
	if evaluated:
		return
	var crowd := get_tree().get_first_node_in_group(&"player") as Node3D
	if crowd == null or crowd.count <= 0:
		return
	if crowd.global_position.z <= global_position.z:
		evaluated = true
		crowd.running = false
		finished.emit(crowd.count, boss_count, crowd.count > boss_count)


func _build_visuals() -> void:
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(line_width, 0.06, 0.8)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.95, 0.95, 0.95)
	line_mesh.material = line_mat
	var line := MeshInstance3D.new()
	line.mesh = line_mesh
	line.position = Vector3(0.0, 0.03, 0.0)
	add_child(line)

	var banner := Label3D.new()
	banner.text = "FINISH"
	banner.font_size = 160
	banner.outline_size = 32
	banner.pixel_size = 0.01
	banner.position = Vector3(0.0, 3.6, 0.0)
	add_child(banner)

	var tower_mesh := BoxMesh.new()
	tower_mesh.size = Vector3(3.0, 4.0, 2.0)
	var tower_mat := StandardMaterial3D.new()
	tower_mat.albedo_color = Color(0.45, 0.35, 0.6)
	tower_mesh.material = tower_mat
	var tower := MeshInstance3D.new()
	tower.mesh = tower_mesh
	tower.position = Vector3(0.0, 2.0, -4.0)
	add_child(tower)

	var tower_label := Label3D.new()
	tower_label.text = str(boss_count)
	tower_label.font_size = 200
	tower_label.outline_size = 32
	tower_label.pixel_size = 0.01
	tower_label.position = Vector3(0.0, 2.6, -2.85)
	add_child(tower_label)
