extends Node3D
## res://scripts/main.gd
## Sandbox shell: builds the blocky VoxelTerrain entirely in code (a
## 2-model VoxelBlockyLibrary — air + a colored cube — over a flat TYPE
## generator), attaches a VoxelViewer to the player so chunks stream around
## them, hands the terrain's VoxelTool to the player for dig/place, and
## emits the boot probe proving the loop: terrain streaming + a block edit
## applied and read back. Everything voxel is constructed here on purpose:
## the scene file stays parseable even without the GDExtension, and the
## whole voxel setup is diffable GDScript instead of opaque .tres blobs.

## Ground level (voxels below y=0 are solid).
@export var ground_height := 0.0
## How far (in voxels) terrain streams around the player.
@export var view_distance := 32

var terrain: VoxelTerrain
var voxel_tool: VoxelTool

@onready var _player: Node3D = $Player
@onready var _blocks_label: Label = $HUD/Margin/Rows/BlocksLabel
@onready var _hint_label: Label = $HUD/Margin/Rows/HintLabel

var _edits := 0


func _ready() -> void:
	_build_terrain()
	voxel_tool = terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_player.setup(voxel_tool)
	_player.block_dug.connect(func(_pos: Vector3i) -> void: _count_edit("dug"))
	_player.block_placed.connect(func(_pos: Vector3i, _id: int) -> void: _count_edit("placed"))
	_hint_label.text = "Click: capture mouse   WASD+Space/Shift: fly   LMB: dig   RMB: place   Esc: release"

	_emit_boot_probe.call_deferred()


func _build_terrain() -> void:
	# Two-model blocky library: 0 = air, 1 = a plain colored cube.
	var air := VoxelBlockyModelEmpty.new()
	var solid := VoxelBlockyModelCube.new()
	solid.color = Color(0.45, 0.62, 0.36)
	var library := VoxelBlockyLibrary.new()
	library.models = [air, solid]

	var mesher := VoxelMesherBlocky.new()
	mesher.library = library

	var generator := VoxelGeneratorFlat.new()
	generator.channel = VoxelBuffer.CHANNEL_TYPE
	generator.voxel_type = 1
	generator.height = ground_height

	terrain = VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	terrain.mesher = mesher
	terrain.generator = generator
	terrain.max_view_distance = view_distance
	add_child(terrain)

	var viewer := VoxelViewer.new()
	viewer.view_distance = view_distance
	_player.add_child(viewer)


func _count_edit(kind: String) -> void:
	_edits += 1
	GameManager.set_flag("voxel_edits", _edits)
	_blocks_label.text = "Edits: %d (last: %s)" % [_edits, kind]


func _emit_boot_probe() -> void:
	# Terrain streams asynchronously — wait until the area around the origin
	# is editable (loaded), then prove the edit loop: read ground, place a
	# block in the air, read it back, dig it out again.
	var probe_box := AABB(Vector3(-4, -4, -4), Vector3(12, 12, 12))
	var frames := 0
	while frames < 900 and not voxel_tool.is_area_editable(probe_box):
		await get_tree().process_frame
		frames += 1
	var loaded := voxel_tool.is_area_editable(probe_box)
	var ground := -1
	var placed := false
	var dug := false
	if loaded:
		ground = voxel_tool.get_voxel(Vector3i(2, -2, 2))
		var spot := Vector3i(2, 3, 2)
		voxel_tool.set_voxel(spot, 1)
		placed = voxel_tool.get_voxel(spot) == 1
		voxel_tool.set_voxel(spot, 0)
		dug = voxel_tool.get_voxel(spot) == 0
	print("DEBUG: voxel-sandbox core loop ready — terrain=%s loaded=%s(%d frames) ground_voxel=%d block_placed=%s block_dug=%s" % [
		is_instance_valid(terrain), loaded, frames, ground, placed, dug,
	])
