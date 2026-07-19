extends TileMapLayer
## res://scripts/floor.gd
## Paints the isometric floor at runtime: a grid_size x grid_size diamond of
## alternating light/dark tiles from the 2-tile atlas. Painting in code keeps
## the scene file free of opaque packed tile data — replace with hand-painted
## TileMapLayer content (or keep generating) when real art lands.

@export var grid_size := 10


func _ready() -> void:
	for x in grid_size:
		for y in grid_size:
			set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))
