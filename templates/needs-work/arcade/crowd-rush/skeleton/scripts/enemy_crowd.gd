extends Node3D
## res://scripts/enemy_crowd.gd
## A blocking enemy crowd (group "enemy_crowds"): stands on the track in the
## same phyllotaxis MultiMesh formation as the player crowd. When the two
## discs touch, the run freezes and units annihilate 1:1 at clash_rate until
## one side is empty — the bigger crowd survives with exactly the difference;
## a tie wipes both (and ends the run). Movement resumes when the enemy is
## cleared.

signal clash_started(enemy_count: int, player_count: int)
signal clash_ended(player_survivors: int)

@export var count := 12
@export var unit_spacing := 0.55
## Unit pairs annihilated per second while the crowds fight.
@export var clash_rate := 20.0
## Extra reach added to the two disc radii for the engage test.
@export var engage_padding := 0.6

var engaged := false

var _mm: MultiMesh
var _label: Label3D
var _drain := 0.0


func _ready() -> void:
	add_to_group(&"enemy_crowds")
	var mmi := Formation.make_unit_multimesh(count, Color(1.0, 0.35, 0.3))
	add_child(mmi)
	_mm = mmi.multimesh
	var y := Formation.UNIT_HEIGHT * 0.5
	for i in count:
		var off := Formation.slot_offset(i, unit_spacing)
		_mm.set_instance_transform(i,
				Transform3D(Basis.IDENTITY, Vector3(off.x, y, off.y)))
	_mm.visible_instance_count = count
	_label = Label3D.new()
	_label.text = str(count)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 96
	_label.outline_size = 24
	_label.pixel_size = 0.01
	_label.modulate = Color(1.0, 0.6, 0.55)
	_label.position = Vector3(0.0, 2.4, 0.0)
	add_child(_label)


func _physics_process(delta: float) -> void:
	if count <= 0:
		return
	var crowd := get_tree().get_first_node_in_group(&"player") as Node3D
	if crowd == null or crowd.count <= 0:
		return
	if not engaged:
		var to_crowd := Vector2(
				crowd.global_position.x - global_position.x,
				crowd.global_position.z - global_position.z)
		var reach: float = Formation.disc_radius(count, unit_spacing) \
				+ Formation.disc_radius(crowd.count, crowd.unit_spacing) + engage_padding
		if to_crowd.length() <= reach:
			engaged = true
			_drain = 0.0
			crowd.running = false
			clash_started.emit(count, crowd.count)
		return
	_drain += clash_rate * delta
	var pairs: int = mini(int(_drain), mini(count, crowd.count))
	if pairs <= 0:
		return
	_drain -= float(pairs)
	_set_count(count - pairs)
	crowd.kill_units(pairs, "clash")
	if count <= 0:
		engaged = false
		if crowd.count > 0:
			crowd.running = true
		clash_ended.emit(crowd.count)


func _set_count(value: int) -> void:
	count = maxi(value, 0)
	_mm.visible_instance_count = count
	_label.text = str(count)
	_label.visible = count > 0
