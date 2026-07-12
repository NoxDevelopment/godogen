extends Node3D
## res://scripts/gate.gd
## One gate panel ("+10", "-5", "x2"...) in the "gates" group. Place two side
## by side at the same z for the classic choice pair — the leader's lane
## decides which one applies, and each gate consumes itself on its first
## crossing. Visuals (translucent panel + Label3D) are code-built so the
## scene stays lean; green = grows the crowd, red = shrinks it.

@export_enum("add", "mul") var operation: String = "add"
## add: units added (negative removes). mul: count multiplier (0.5 halves).
@export var amount := 10.0
## Half of the panel's x extent — a crossing counts when the crowd leader is
## within this of the gate's x.
@export var half_width := 1.9
@export var height := 2.6

var consumed := false

var _panel: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	add_to_group(&"gates")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(half_width * 2.0, height, 0.25)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.85, 0.35, 0.4) if _is_positive() \
			else Color(0.9, 0.25, 0.2, 0.4)
	mesh.material = mat
	_panel = MeshInstance3D.new()
	_panel.mesh = mesh
	_panel.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(_panel)
	_label = Label3D.new()
	_label.text = label_text()
	_label.font_size = 140
	_label.outline_size = 28
	_label.pixel_size = 0.01
	_label.position = Vector3(0.0, height * 0.5, 0.2)
	add_child(_label)


func label_text() -> String:
	if operation == "add":
		return "%+d" % roundi(amount)
	return "x" + String.num(amount)


## Crossing test the crowd runs every frame it moves forward: the gate is
## consumed when the leader's z steps over the gate plane inside the panel's
## x range. Returns true if this gate applied.
func try_cross(prev_z: float, new_z: float, leader_x: float, crowd: Node3D) -> bool:
	if consumed:
		return false
	var z := global_position.z
	if not (prev_z >= z and new_z < z):
		return false
	if absf(leader_x - global_position.x) > half_width:
		return false
	consumed = true
	crowd.apply_gate(operation, amount, label_text())
	var tween := create_tween()
	tween.tween_property(_panel, "scale", Vector3(1.15, 1.15, 1.15), 0.12)
	tween.parallel().tween_property(_label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(hide)
	return true


func _is_positive() -> bool:
	if operation == "add":
		return amount > 0.0
	return amount > 1.0
