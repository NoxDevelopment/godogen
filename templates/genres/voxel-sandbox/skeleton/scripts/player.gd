extends Node3D
## res://scripts/player.gd
## First-person fly controller for the sandbox: mouse look (click to
## capture, Esc via `pause` releases), WASD + Space/Shift flight, and
## dig/place against the voxel terrain through VoxelToolTerrain raycasts —
## LMB removes the aimed block, RMB places the build block against the hit
## face. Fly-mode keeps the skeleton collision-free; a walking
## CharacterBody3D is a documented extension (VoxelTerrain generates
## collision meshes when enabled).

signal block_dug(position: Vector3i)
signal block_placed(position: Vector3i, block_id: int)

@export var move_speed := 12.0
@export var sprint_multiplier := 2.5
@export var mouse_sensitivity := 0.0025
@export var reach := 40.0
## The VoxelBlockyLibrary model id placed by RMB (1 = the solid block).
@export var build_block_id := 1

var _voxel_tool: VoxelTool
var _pitch := 0.0

@onready var _camera: Camera3D = $Camera3D


## main.gd hands over the terrain's voxel tool once the terrain exists.
func setup(voxel_tool: VoxelTool) -> void:
	_voxel_tool = voxel_tool


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
		_camera.rotation.x = _pitch
	if event.is_action_pressed(&"dig"):
		dig()
	elif event.is_action_pressed(&"place"):
		place()


func _process(delta: float) -> void:
	var axis := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var vertical := Input.get_action_strength(&"fly_up") - Input.get_action_strength(&"fly_down")
	var direction := (global_transform.basis * Vector3(axis.x, 0.0, axis.y)).normalized()
	direction.y += vertical
	position += direction * move_speed * delta


## Remove the aimed block. Returns the mined voxel position or Vector3i.MAX.
func dig() -> Vector3i:
	var hit := _aim_raycast()
	if hit == null:
		return Vector3i.MAX
	_voxel_tool.set_voxel(hit.position, 0)
	block_dug.emit(hit.position)
	return hit.position


## Place the build block against the aimed face. Returns the position or Vector3i.MAX.
func place() -> Vector3i:
	var hit := _aim_raycast()
	if hit == null:
		return Vector3i.MAX
	_voxel_tool.set_voxel(hit.previous_position, build_block_id)
	block_placed.emit(hit.previous_position, build_block_id)
	return hit.previous_position


func _aim_raycast() -> VoxelRaycastResult:
	if _voxel_tool == null:
		return null
	return _voxel_tool.raycast(
		_camera.global_position, -_camera.global_transform.basis.z, reach)
