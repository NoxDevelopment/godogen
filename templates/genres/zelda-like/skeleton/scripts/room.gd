extends Node2D
## res://scripts/room.gd
## One screen of the world. Rooms sit on a screen grid (position must be a
## multiple of ROOM_SIZE — coords are derived from it), and each builds its
## own floor and perimeter walls in code at boot, leaving a DOORWAY_WIDTH gap
## centered on any side flagged gap_*, so the scene file stays free of dozens
## of hand-authored wall shapes. Doors (door.tscn) are placed on the shared
## boundary between two gaps. Rooms also gate their own enemies: main.gd calls
## set_active() on transitions so only the current screen's enemies run.

const ROOM_SIZE := Vector2(1152, 648)
const WALL_THICKNESS := 32.0
const DOORWAY_WIDTH := 128.0
const WALL_COLOR := Color(0.227451, 0.247059, 0.290196)

@export var gap_north := false
@export var gap_east := false
@export var gap_south := false
@export var gap_west := false
@export var floor_color := Color(0.113725, 0.12549, 0.14902)

var coords := Vector2i.ZERO
var _walls: StaticBody2D


func _ready() -> void:
	coords = Vector2i((position / ROOM_SIZE).round())
	add_to_group(&"rooms")
	_build_floor()
	_build_walls()


func rect() -> Rect2:
	return Rect2(position, ROOM_SIZE)


## Wake/sleep every enemy that lives in this room (classic Zelda: only the
## current screen is alive). Called by main.gd on room transitions.
func set_active(active: bool) -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Node2D and is_ancestor_of(node) and node.has_method("set_room_active"):
			node.set_room_active(active)


func _build_floor() -> void:
	var floor_visual := Polygon2D.new()
	floor_visual.name = "Floor"
	floor_visual.z_index = -10
	floor_visual.color = floor_color
	floor_visual.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(ROOM_SIZE.x, 0), ROOM_SIZE, Vector2(0, ROOM_SIZE.y),
	])
	add_child(floor_visual)


func _build_walls() -> void:
	_walls = StaticBody2D.new()
	_walls.name = "Walls"
	_walls.collision_layer = 1
	_walls.collision_mask = 0
	add_child(_walls)

	var w := ROOM_SIZE.x
	var h := ROOM_SIZE.y
	var t := WALL_THICKNESS
	var gap_lo_x := (w - DOORWAY_WIDTH) * 0.5
	var gap_hi_x := (w + DOORWAY_WIDTH) * 0.5
	var gap_lo_y := (h - DOORWAY_WIDTH) * 0.5
	var gap_hi_y := (h + DOORWAY_WIDTH) * 0.5

	# North and south walls span the full width (corners included); east and
	# west run between them. Gaps are DOORWAY_WIDTH, centered on each side.
	if gap_north:
		_add_wall(Rect2(0, 0, gap_lo_x, t))
		_add_wall(Rect2(gap_hi_x, 0, w - gap_hi_x, t))
	else:
		_add_wall(Rect2(0, 0, w, t))
	if gap_south:
		_add_wall(Rect2(0, h - t, gap_lo_x, t))
		_add_wall(Rect2(gap_hi_x, h - t, w - gap_hi_x, t))
	else:
		_add_wall(Rect2(0, h - t, w, t))
	if gap_west:
		_add_wall(Rect2(0, t, t, gap_lo_y - t))
		_add_wall(Rect2(0, gap_hi_y, t, h - t - gap_hi_y))
	else:
		_add_wall(Rect2(0, t, t, h - 2.0 * t))
	if gap_east:
		_add_wall(Rect2(w - t, t, t, gap_lo_y - t))
		_add_wall(Rect2(w - t, gap_hi_y, t, h - t - gap_hi_y))
	else:
		_add_wall(Rect2(w - t, t, t, h - 2.0 * t))


func _add_wall(wall_rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = wall_rect.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = wall_rect.get_center()
	_walls.add_child(collider)

	var visual := Polygon2D.new()
	visual.color = WALL_COLOR
	visual.polygon = PackedVector2Array([
		wall_rect.position,
		wall_rect.position + Vector2(wall_rect.size.x, 0),
		wall_rect.end,
		wall_rect.position + Vector2(0, wall_rect.size.y),
	])
	add_child(visual)
