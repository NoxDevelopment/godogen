extends Node3D
## res://scripts/crowd.gd
## The player crowd (groups "player", "persistent"): auto-runs forward along
## -Z and steers horizontally (A/D-arrows or mouse-x). Every unit is drawn by
## ONE MultiMesh in a phyllotaxis disc around this node — no per-unit nodes,
## no physics bodies — so 200+ units stay cheap; growing/shrinking the crowd
## is just visible_instance_count plus count arithmetic. Gates call
## apply_gate(), obstacles kill_unit_at(), clashes kill_units(); all of them
## are public so bots and the boot probe drive the same routines gameplay
## uses. Count 0 = the crowd is wiped and the run is over.

signal count_changed(count: int)
signal units_lost(amount: int, cause: String)
signal gate_applied(label: String, count_before: int, count_after: int)
signal died

const ACTION_LEFT := &"steer_left"
const ACTION_RIGHT := &"steer_right"

## Hard MultiMesh capacity — slots are allocated once at boot.
@export var max_units := 400
@export var start_units := 1
## Forward auto-run speed, units/s (the track runs toward -Z).
@export var run_speed := 8.0
## Horizontal steering speed, units/s.
@export var steer_speed := 7.0
## Playable half-width of the track; the leader is clamped inside it.
@export var track_half_width := 4.0
## Phyllotaxis ring spacing between units.
@export var unit_spacing := 0.55
## How fast units flow to their formation slot after the crowd changes size.
@export var reform_speed := 10.0
## Steer toward the mouse's viewport x once it moves (keyboard overrides).
@export var mouse_steer := true

var count := 0
var distance := 0.0
## Forward-motion gate — enemy clashes freeze the run while units fight.
var running := true

var _dead := false
var _start_z := 0.0
var _slots: PackedVector2Array
var _mm: MultiMesh
var _count_label: Label3D
var _mouse_active := false
var _mouse_x_norm := 0.5


func _ready() -> void:
	_start_z = global_position.z
	_slots.resize(max_units)
	var mmi := Formation.make_unit_multimesh(max_units, Color(0.301961, 0.65098, 1.0))
	add_child(mmi)
	_mm = mmi.multimesh
	_count_label = Label3D.new()
	_count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_count_label.font_size = 96
	_count_label.outline_size = 24
	_count_label.pixel_size = 0.01
	_count_label.position = Vector3(0.0, 2.4, 0.0)
	add_child(_count_label)
	set_count(start_units)


func _unhandled_input(event: InputEvent) -> void:
	if mouse_steer and event is InputEventMouseMotion:
		_mouse_active = true
		var vp := get_viewport().get_visible_rect().size
		_mouse_x_norm = clampf(event.position.x / maxf(vp.x, 1.0), 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var x := global_position.x
	var steer := Input.get_axis(ACTION_LEFT, ACTION_RIGHT)
	if steer != 0.0:
		_mouse_active = false
		x += steer * steer_speed * delta
	elif _mouse_active:
		var target_x := (_mouse_x_norm * 2.0 - 1.0) * track_half_width
		x = move_toward(x, target_x, steer_speed * delta)
	x = clampf(x, -track_half_width + 0.4, track_half_width - 0.4)

	var prev_z := global_position.z
	var z := prev_z
	if running:
		z -= run_speed * delta
	global_position = Vector3(x, global_position.y, z)
	distance = maxf(distance, _start_z - z)

	if z < prev_z:
		for gate in get_tree().get_nodes_in_group(&"gates"):
			if gate.try_cross(prev_z, z, x, self):
				break

	_update_units(delta)


## World position of the unit in slot i (obstacles hit-test against this —
## the exact positions the MultiMesh renders).
func unit_position(i: int) -> Vector3:
	return global_position + Vector3(_slots[i].x, 0.0, _slots[i].y)


## Grow/shrink to an absolute size. New units spawn at the leader and flow
## outward to their slot; at 0 the crowd is dead and `died` fires.
func set_count(value: int) -> void:
	var new_count := clampi(value, 0, max_units)
	if new_count == count:
		return
	for i in range(count, new_count):
		_slots[i] = Vector2.ZERO
		_mm.set_instance_transform(i,
				Transform3D(Basis.IDENTITY, Vector3(0.0, Formation.UNIT_HEIGHT * 0.5, 0.0)))
	count = new_count
	_mm.visible_instance_count = count
	_count_label.text = str(count)
	count_changed.emit(count)
	if count == 0 and not _dead:
		_dead = true
		running = false
		died.emit()


## Remove `amount` units from the formation edge (clash attrition).
func kill_units(amount: int, cause: String) -> void:
	if amount <= 0 or count <= 0:
		return
	var killed := mini(amount, count)
	set_count(count - killed)
	units_lost.emit(killed, cause)


## Remove the specific unit in slot i (obstacle hits); the outermost unit
## takes over the slot so the disc stays packed.
func kill_unit_at(i: int, cause: String) -> void:
	if i < 0 or i >= count:
		return
	_slots[i] = _slots[count - 1]
	set_count(count - 1)
	units_lost.emit(1, cause)


## Gate entry point (gate.gd calls this): "add" or "mul" applied to count.
func apply_gate(operation: String, amount: float, label: String) -> void:
	var before := count
	var after := before
	match operation:
		"add":
			after = before + roundi(amount)
		"mul":
			after = roundi(float(before) * amount)
	set_count(after)
	gate_applied.emit(label, before, count)
	if count < before:
		units_lost.emit(before - count, "gate")


## Reposition without triggering gate crossings (probe/checkpoint hook).
func teleport_to(x: float, z: float) -> void:
	global_position = Vector3(
			clampf(x, -track_half_width, track_half_width), global_position.y, z)


## "persistent" group contract (see templates ABI): return the state to save.
func save_data() -> Dictionary:
	return {
		"count": count,
		"distance": distance,
		"position": {"x": global_position.x, "z": global_position.z},
	}


func load_data(data: Dictionary) -> void:
	distance = float(data.get("distance", distance))
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("z"):
		global_position = Vector3(pos.x, global_position.y, pos.z)
	set_count(int(data.get("count", count)))


func _update_units(delta: float) -> void:
	var w := minf(reform_speed * delta, 1.0)
	var y := Formation.UNIT_HEIGHT * 0.5
	for i in count:
		var slot := _slots[i].lerp(Formation.slot_offset(i, unit_spacing), w)
		_slots[i] = slot
		_mm.set_instance_transform(i,
				Transform3D(Basis.IDENTITY, Vector3(slot.x, y, slot.y)))
