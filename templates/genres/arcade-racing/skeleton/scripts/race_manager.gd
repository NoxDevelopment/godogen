extends Node3D
## res://scripts/race_manager.gd
## Track shell + first-party race logic on top of Godot-Easy-Vehicle-Physics:
## ordered checkpoint gates, a start/finish line that arms the lap timer on
## the first crossing and completes a lap once every gate has been passed in
## order, lap/best-lap timing, and the HUD readout. Emits the boot probe lines
## proving the core loop (GEVP vehicle driving + gate crossings feeding the
## lap counter) is alive.

signal checkpoint_passed(index: int, total: int)
signal lap_completed(lap: int, lap_time: float)

var lap := 0
var lap_time := 0.0
var best_lap_time := INF
var next_gate := 0
var timing := false

@onready var _vehicle: RigidBody3D = $VehicleController/VehicleRigidBody
@onready var _gates: Array[Node] = $Checkpoints.get_children()
@onready var _start_finish: Area3D = $StartFinish
@onready var _lap_label: Label = $HUD/Margin/Rows/LapLabel
@onready var _time_label: Label = $HUD/Margin/Rows/TimeLabel
@onready var _gate_label: Label = $HUD/Margin/Rows/GateLabel
@onready var _speed_label: Label = $HUD/Margin/Rows/SpeedLabel


func _ready() -> void:
	for gate in _gates:
		gate.gate_crossed.connect(_on_gate_crossed)
	_start_finish.body_entered.connect(_on_start_finish_entered)
	_refresh_hud()

	_emit_boot_probe.call_deferred()


func _physics_process(delta: float) -> void:
	if timing:
		lap_time += delta


func _process(_delta: float) -> void:
	_time_label.text = "Time %s   Best %s" % [
		_format_time(lap_time),
		"--:--.---" if best_lap_time == INF else _format_time(best_lap_time),
	]
	_speed_label.text = "%d km/h  gear %d" % [
		roundi(_vehicle.speed * 3.6), _vehicle.current_gear,
	]


## "persistent" group member via GameManager; race results worth saving go
## through flags so godotsmith's save_system picks them up.
func _record_best_lap() -> void:
	GameManager.set_flag("best_lap_time", best_lap_time)


func _on_gate_crossed(gate: Area3D, body: Node3D) -> void:
	if body != _vehicle:
		return
	var index := _gates.find(gate)
	if index != next_gate:
		return  # wrong order (or re-crossing an old gate) — ignore
	next_gate += 1
	checkpoint_passed.emit(next_gate, _gates.size())
	_refresh_hud()
	print("DEBUG: arcade-racing checkpoint crossed — gate=%d/%d lap=%d lap_time=%.2fs" % [
		next_gate, _gates.size(), lap, lap_time,
	])


func _on_start_finish_entered(body: Node3D) -> void:
	if body != _vehicle:
		return
	if not timing:
		# First crossing arms the lap timer.
		timing = true
		lap_time = 0.0
		next_gate = 0
	elif next_gate >= _gates.size():
		# All gates passed in order — that's a lap.
		lap += 1
		best_lap_time = minf(best_lap_time, lap_time)
		_record_best_lap()
		lap_completed.emit(lap, lap_time)
		lap_time = 0.0
		next_gate = 0
	_refresh_hud()


func _refresh_hud() -> void:
	_lap_label.text = "Lap %d" % lap
	_gate_label.text = "Gate %d/%d" % [next_gate, _gates.size()]


func _format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	return "%02d:%06.3f" % [minutes, seconds - minutes * 60]


func _emit_boot_probe() -> void:
	# Let the RigidBody settle onto its wheel raycasts first.
	for i in 8:
		await get_tree().physics_frame
	var has_wheels: bool = _vehicle.front_left_wheel != null \
			and _vehicle.rear_right_wheel != null
	print("DEBUG: arcade-racing vehicle ready — vehicle=%s wheels=%s gates=%d start_finish=%s" % [
		is_instance_valid(_vehicle), has_wheels, _gates.size(),
		is_instance_valid(_start_finish),
	])
	# Drive: full throttle, straight ahead — the start/finish line sits just
	# ahead of the grid and gate 1 is dead ahead after it, so within a few
	# seconds the gate-crossed probe line above fires too.
	Input.action_press(&"throttle")
