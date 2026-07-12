extends TileMapLayer
## res://scripts/farm.gd
## The field: a TileMapLayer of grass/tilled/watered soil (painted in code
## from the 3-tile atlas) plus the planted-crop ledger. Growth is
## recomputed from day deltas (stage = f(today - planted_day)), so repeated
## day_changed signals are idempotent. Crops render as blockout Polygon2D
## markers that grow and recolor per stage.

signal crop_planted(cell: Vector2i, crop: Crop)
signal crop_stage_changed(cell: Vector2i, stage: int)
signal crop_harvested(cell: Vector2i, crop: Crop, amount: int)

const TILE_GRASS := Vector2i(0, 0)
const TILE_TILLED := Vector2i(1, 0)
const TILE_WATERED := Vector2i(2, 0)

@export var field_size := Vector2i(20, 12)

## cell -> {crop: Crop, planted_day: int, stage: int, marker: Node2D}
var plots: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(&"persistent")


func _ready() -> void:
	for x in field_size.x:
		for y in field_size.y:
			set_cell(Vector2i(x, y), 0, TILE_GRASS)
	TimeSystem.day_changed.connect(_on_day_changed)


func is_tilled(cell: Vector2i) -> bool:
	var atlas := get_cell_atlas_coords(cell)
	return atlas == TILE_TILLED or atlas == TILE_WATERED


func has_crop(cell: Vector2i) -> bool:
	return plots.has(cell)


func in_field(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 \
			and cell.x < field_size.x and cell.y < field_size.y


## Till a grass cell into soil. Returns true if the cell changed.
func till(cell: Vector2i) -> bool:
	if not in_field(cell) or is_tilled(cell):
		return false
	set_cell(cell, 0, TILE_TILLED)
	return true


## Plant a crop on tilled soil. Returns true on success.
func plant(cell: Vector2i, crop: Crop) -> bool:
	if not in_field(cell) or not is_tilled(cell) or has_crop(cell):
		return false
	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([-6, 6, 0, -6, 6, 6])
	marker.position = map_to_local(cell)
	add_child(marker)
	plots[cell] = {
		"crop": crop,
		"planted_day": TimeSystem.get_day(),
		"stage": 0,
		"marker": marker,
	}
	_refresh_plot(cell)
	crop_planted.emit(cell, crop)
	return true


## Harvest a mature crop. Returns the yielded amount (0 = nothing to harvest).
func harvest(cell: Vector2i) -> int:
	if not has_crop(cell):
		return 0
	var plot: Dictionary = plots[cell]
	var crop: Crop = plot.crop
	if not crop.is_mature(plot.stage):
		return 0
	plot.marker.queue_free()
	plots.erase(cell)
	var harvested := GameManager.get_flag("harvested_" + crop.harvest_item, 0) as int
	GameManager.set_flag("harvested_" + crop.harvest_item, harvested + crop.harvest_amount)
	crop_harvested.emit(cell, crop, crop.harvest_amount)
	return crop.harvest_amount


func get_stage(cell: Vector2i) -> int:
	return plots[cell].stage if has_crop(cell) else -1


func _on_day_changed(day: int) -> void:
	for cell: Vector2i in plots:
		var plot: Dictionary = plots[cell]
		var crop: Crop = plot.crop
		var stage := crop.stage_on_day(plot.planted_day, day)
		if stage != plot.stage:
			plot.stage = stage
			_refresh_plot(cell)
			crop_stage_changed.emit(cell, stage)


func _refresh_plot(cell: Vector2i) -> void:
	var plot: Dictionary = plots[cell]
	var crop: Crop = plot.crop
	var marker: Polygon2D = plot.marker
	var size: float = 4.0 + 3.0 * int(plot.stage)
	marker.polygon = PackedVector2Array([-size, size, 0.0, -size, size, size])
	marker.color = crop.color_for_stage(plot.stage)


## "persistent" group contract (see templates ABI). Markers rebuild on load.
func save_data() -> Dictionary:
	var tilled: Array = []
	for x in field_size.x:
		for y in field_size.y:
			if is_tilled(Vector2i(x, y)):
				tilled.append({"x": x, "y": y})
	var crops: Array = []
	for cell: Vector2i in plots:
		var plot: Dictionary = plots[cell]
		crops.append({
			"x": cell.x, "y": cell.y,
			"crop_path": (plot.crop as Resource).resource_path,
			"planted_day": plot.planted_day,
		})
	return {"tilled": tilled, "crops": crops}


func load_data(data: Dictionary) -> void:
	for entry in data.get("tilled", []):
		set_cell(Vector2i(int(entry.x), int(entry.y)), 0, TILE_TILLED)
	for entry in data.get("crops", []):
		var cell := Vector2i(int(entry.x), int(entry.y))
		var crop := load(entry.crop_path) as Crop
		if crop and plant(cell, crop):
			plots[cell].planted_day = int(entry.planted_day)
	_on_day_changed(TimeSystem.get_day())
