extends Node
## res://scripts/sanity.gd
## Sanity autoload ("Sanity"): the horror stat. 0-100, drains from ambient
## dread and scripted scares, restores in safe zones. Purely a number with
## signals — the room script wires it to the overlay shader and the resonate
## music stems, so the systems stay decoupled (Amnesia-style architecture:
## stat, presentation, and audio react independently).

signal sanity_changed(current: float, max_sanity: float)
## Fired with hysteresis: entered below `low_threshold`, exited above
## `recover_threshold` — so the dread layer never flickers at the boundary.
signal low_sanity_entered
signal low_sanity_exited

@export var max_sanity := 100.0
## Passive drain per second while not in a safe zone (0 disables).
@export var ambient_drain := 0.5
## Restore per second while inside a safe zone.
@export var safe_zone_restore := 8.0
@export var low_threshold := 45.0
@export var recover_threshold := 60.0

var sanity: float
var is_low := false
## Safe zones (Area3D overlaps) push/pop this counter.
var safe_zone_count := 0


func _enter_tree() -> void:
	add_to_group(&"persistent")
	sanity = max_sanity


func _process(delta: float) -> void:
	if safe_zone_count > 0:
		restore(safe_zone_restore * delta)
	elif ambient_drain > 0.0:
		drain(ambient_drain * delta)


## Normalized 0..1 (drives the overlay shader and stem volumes).
func normalized() -> float:
	return sanity / max_sanity


func drain(amount: float) -> void:
	_set_sanity(sanity - amount)


func restore(amount: float) -> void:
	_set_sanity(sanity + amount)


## Scripted scares: an instant hit (monster sighting, jump scare, darkness).
func scare(amount: float) -> void:
	drain(amount)


func enter_safe_zone() -> void:
	safe_zone_count += 1


func exit_safe_zone() -> void:
	safe_zone_count = maxi(safe_zone_count - 1, 0)


func _set_sanity(value: float) -> void:
	var clamped := clampf(value, 0.0, max_sanity)
	if is_equal_approx(clamped, sanity):
		return
	sanity = clamped
	sanity_changed.emit(sanity, max_sanity)
	if not is_low and sanity <= low_threshold:
		is_low = true
		low_sanity_entered.emit()
	elif is_low and sanity >= recover_threshold:
		is_low = false
		low_sanity_exited.emit()


## "persistent" group contract (see templates ABI).
func save_data() -> Dictionary:
	return {"sanity": sanity, "is_low": is_low}


func load_data(data: Dictionary) -> void:
	sanity = float(data.get("sanity", max_sanity))
	is_low = bool(data.get("is_low", false))
	sanity_changed.emit(sanity, max_sanity)
