extends Node3D
## res://scripts/dungeon.gd
## The dungeon: one ASCII map constant parsed into a cell grid, all geometry
## built in code (one floor slab, one ceiling slab, a wall box per solid cell
## that touches walkable space, door leaves, the lever prop and spinning
## pickups). There is NO physics in this template — movement, bump-to-open
## doors, lever pulls, pickups and combat reach are all grid queries against
## this script (is_open / occupant / try_bump / pull_lever_at), which is what
## makes the classic grid-crawler illusion cheap and headless-robust. Doors,
## the lever and taken pickups write GameManager flags and restore themselves
## from them in _ready, so world state survives scene reloads.
##
## Map legend: '#' wall · '.' floor · '@' party start · 'D' locked door
## (consumes a key on bump) · 'd' plain door (opens on bump) · 'S' secret
## wall (looks like '#', opened by the lever) · 'L' lever · 'K' key pickup ·
## 'P' potion pickup · 'E' enemy spawn. Cells are (x=column, y=row).

signal message(text: String)
signal door_opened(cell: Vector2i)
signal secret_opened(cell: Vector2i)
signal lever_pulled(cell: Vector2i)
signal pickup_collected(cell: Vector2i, kind: String)

const CELL_SIZE := 2.0
const WALL_HEIGHT := 2.5

## 14x13 starter dungeon: start room west, locked door 'D' east to the lever
## room, plain door 'd' south to the key room, and a secret room behind 'S'
## that only the lever 'L' opens. The key sits behind the plain door, the
## lever sits behind the locked door, so the intended loop is: key -> locked
## door -> lever -> secret.
const MAP: Array[String] = [
	"##############",
	"#....#......##",
	"#.@..D.....L##",
	"#....#.E....##",
	"##.####S######",
	"##.###....####",
	"##.###.P..####",
	"##d###....####",
	"#.K.E#..E.####",
	"#....#########",
	"#....#########",
	"#...P#########",
	"##############",
]

const FLOOR_COLOR := Color(0.23, 0.21, 0.19)
const CEILING_COLOR := Color(0.14, 0.13, 0.12)
const WALL_COLOR := Color(0.44, 0.38, 0.31)
const DOOR_COLOR := Color(0.46, 0.31, 0.17)
const LOCKED_DOOR_COLOR := Color(0.38, 0.23, 0.13)
const KEY_COLOR := Color(0.92, 0.78, 0.25)
const POTION_COLOR := Color(0.82, 0.2, 0.24)
const LEVER_COLOR := Color(0.55, 0.55, 0.6)

var width := 0
var height := 0
var start_cell := Vector2i.ZERO
## Kept current by the party (warp + every step) — enemies path toward it.
var party_cell := Vector2i(-1, -1)

var _open_doors: Dictionary = {}
var _open_secrets: Dictionary = {}
var _levers_on: Dictionary = {}
var _pickups: Dictionary = {}        # cell -> {"kind": String, "mesh": Node3D}
var _door_leaves: Dictionary = {}    # cell -> MeshInstance3D
var _secret_meshes: Dictionary = {}  # cell -> MeshInstance3D
var _lever_handles: Dictionary = {}  # cell -> MeshInstance3D
var _occupants: Dictionary = {}      # cell -> Node3D (enemies)
var _spinners: Array[MeshInstance3D] = []
var _materials: Dictionary = {}      # Color -> shared StandardMaterial3D


func _ready() -> void:
	height = MAP.size()
	width = MAP[0].length()
	_build_slabs()
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			match cell_char(cell):
				"#":
					if _borders_walkable(cell):
						_build_wall(cell, WALL_COLOR)
				"S":
					if GameManager.get_flag(_lever_flag_for_secrets()):
						_open_secrets[cell] = true
					else:
						_secret_meshes[cell] = _build_wall(cell, WALL_COLOR)
				"D":
					_restore_or_build_door(cell, LOCKED_DOOR_COLOR)
				"d":
					_restore_or_build_door(cell, DOOR_COLOR)
				"L":
					_build_lever(cell)
				"K":
					_restore_or_place_pickup(cell, "key")
				"P":
					_restore_or_place_pickup(cell, "potion")
				"@":
					start_cell = cell


func _process(delta: float) -> void:
	for spinner in _spinners:
		if is_instance_valid(spinner):
			spinner.rotate_y(delta * 2.2)


## Cell center on the floor plane (y = 0).
func world_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)


func cell_char(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= height or cell.x < 0 or cell.x >= width:
		return "#"
	return MAP[cell.y][cell.x]


## True when the cell can be stood in: floor-ish, an opened door, or an
## opened secret. Occupancy is a separate question (see occupant()).
func is_open(cell: Vector2i) -> bool:
	match cell_char(cell):
		"#":
			return false
		"S":
			return _open_secrets.has(cell)
		"D", "d":
			return _open_doors.has(cell)
		_:
			return true


## Door interaction on bump (the party walked into the cell): plain doors
## swing open, locked doors consume a party key or refuse. Walls and open
## cells do nothing.
func try_bump(cell: Vector2i, party: Node3D) -> void:
	match cell_char(cell):
		"d":
			if not _open_doors.has(cell):
				_open_door(cell)
				message.emit("The door creaks open.")
		"D":
			if _open_doors.has(cell):
				return
			if party.keys > 0:
				party.spend_key()
				_open_door(cell)
				message.emit("The key turns — the door grinds open.")
			else:
				message.emit("The door is locked. It needs a key.")


## Pull the lever in `cell` if there is an unpulled one there. Opens every
## secret wall on the map (one lever, one secret in the starter dungeon).
func pull_lever_at(cell: Vector2i) -> bool:
	if cell_char(cell) != "L" or _levers_on.has(cell):
		return false
	_levers_on[cell] = true
	GameManager.set_flag(_lever_flag_for_secrets())
	var handle: MeshInstance3D = _lever_handles.get(cell)
	if handle:
		handle.rotation.x = -handle.rotation.x
	message.emit("The lever clunks down. Stone grinds somewhere far away...")
	lever_pulled.emit(cell)
	for y in height:
		for x in width:
			var secret := Vector2i(x, y)
			if cell_char(secret) == "S" and not _open_secrets.has(secret):
				_open_secret(secret)
	return true


## Consume the pickup in `cell` (called by the party when it arrives).
func collect_pickup(cell: Vector2i, party: Node3D) -> void:
	if not _pickups.has(cell):
		return
	var kind: String = _pickups[cell]["kind"]
	var mesh: Node3D = _pickups[cell]["mesh"]
	_spinners.erase(mesh)
	mesh.queue_free()
	_pickups.erase(cell)
	GameManager.set_flag("pickup_%d_%d" % [cell.x, cell.y])
	match kind:
		"key":
			party.gain_key()
			message.emit("Picked up a small key.")
		"potion":
			party.gain_potion()
			message.emit("Picked up a healing potion.")
	pickup_collected.emit(cell, kind)


## Enemy occupancy — one enemy per cell, party blocked by it.
func occupy(cell: Vector2i, node: Node3D) -> void:
	_occupants[cell] = node


func vacate(cell: Vector2i) -> void:
	_occupants.erase(cell)


func occupant(cell: Vector2i) -> Node3D:
	var node: Node3D = _occupants.get(cell)
	if node != null and not is_instance_valid(node):
		_occupants.erase(cell)
		return null
	return node


## Every 'E' cell — main.gd spawns one enemy per entry.
func enemy_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in height:
		for x in width:
			if MAP[y][x] == "E":
				cells.append(Vector2i(x, y))
	return cells


func _open_door(cell: Vector2i) -> void:
	_open_doors[cell] = true
	GameManager.set_flag("door_%d_%d" % [cell.x, cell.y])
	_sink_and_free(_door_leaves.get(cell))
	_door_leaves.erase(cell)
	door_opened.emit(cell)


func _open_secret(cell: Vector2i) -> void:
	_open_secrets[cell] = true
	_sink_and_free(_secret_meshes.get(cell))
	_secret_meshes.erase(cell)
	secret_opened.emit(cell)


## Doors and secret walls sink into the floor instead of popping out.
func _sink_and_free(mesh: Node3D) -> void:
	if mesh == null:
		return
	var tween := create_tween()
	tween.tween_property(mesh, "position:y", mesh.position.y - (WALL_HEIGHT + 0.2), 0.6)
	tween.tween_callback(mesh.queue_free)


func _restore_or_build_door(cell: Vector2i, color: Color) -> void:
	if GameManager.get_flag("door_%d_%d" % [cell.x, cell.y]):
		_open_doors[cell] = true
		return
	_door_leaves[cell] = _build_door_leaf(cell, color)


func _restore_or_place_pickup(cell: Vector2i, kind: String) -> void:
	if GameManager.get_flag("pickup_%d_%d" % [cell.x, cell.y]):
		return
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	if kind == "key":
		box.size = Vector3(0.5, 0.12, 0.22)
		box.material = _material(KEY_COLOR)
	else:
		box.size = Vector3(0.26, 0.5, 0.26)
		box.material = _material(POTION_COLOR)
	mesh.mesh = box
	mesh.position = world_pos(cell) + Vector3(0.0, 0.5, 0.0)
	add_child(mesh)
	_spinners.append(mesh)
	_pickups[cell] = {"kind": kind, "mesh": mesh}


## One flag covers the lever/secret pair — pull once, open forever.
func _lever_flag_for_secrets() -> String:
	return "lever_pulled"


func _borders_walkable(cell: Vector2i) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var neighbor := cell + Vector2i(dx, dy)
			if neighbor.y < 0 or neighbor.y >= height \
					or neighbor.x < 0 or neighbor.x >= width:
				continue
			if cell_char(neighbor) != "#":
				return true
	return false


func _build_slabs() -> void:
	var span_x := width * CELL_SIZE
	var span_z := height * CELL_SIZE
	var center := Vector3((width - 1) * CELL_SIZE * 0.5, 0.0, (height - 1) * CELL_SIZE * 0.5)
	_add_box(center + Vector3(0.0, -0.5, 0.0), Vector3(span_x, 1.0, span_z), FLOOR_COLOR)
	_add_box(center + Vector3(0.0, WALL_HEIGHT + 0.5, 0.0),
			Vector3(span_x, 1.0, span_z), CEILING_COLOR)


func _build_wall(cell: Vector2i, color: Color) -> MeshInstance3D:
	return _add_box(world_pos(cell) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0),
			Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE), color)


## Door leaf: a thin full-height panel across the passage axis (walls above
## and below the door cell mean an east-west passage, and vice versa).
func _build_door_leaf(cell: Vector2i, color: Color) -> MeshInstance3D:
	var north_south_solid: bool = cell_char(cell + Vector2i(0, -1)) == "#" \
			and cell_char(cell + Vector2i(0, 1)) == "#"
	var size := Vector3(0.3, WALL_HEIGHT, CELL_SIZE - 0.2) if north_south_solid \
			else Vector3(CELL_SIZE - 0.2, WALL_HEIGHT, 0.3)
	return _add_box(world_pos(cell) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0), size, color)


func _build_lever(cell: Vector2i) -> void:
	_add_box(world_pos(cell) + Vector3(0.0, 0.45, 0.0),
			Vector3(0.24, 0.9, 0.24), LEVER_COLOR)
	var handle := _add_box(world_pos(cell) + Vector3(0.0, 1.05, 0.0),
			Vector3(0.1, 0.55, 0.1), KEY_COLOR)
	handle.rotation.x = 0.6
	_lever_handles[cell] = handle
	if GameManager.get_flag(_lever_flag_for_secrets()):
		_levers_on[cell] = true
		handle.rotation.x = -0.6


func _add_box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	mesh.mesh = box
	mesh.position = pos
	add_child(mesh)
	return mesh


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		_materials[color] = material
	return _materials[color]
