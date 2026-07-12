extends Node2D
## res://scripts/main.gd
## Farm shell: wires the clock/season/harvest HUD and emits the boot probe
## proving the core loop — TimeTick clock live, till -> plant -> growth
## advanced by sleeping two game days, and the day/night tint reacting to a
## clock jump.

@onready var _farm: TileMapLayer = $Farm
@onready var _player: CharacterBody2D = $Player
@onready var _day_night: CanvasModulate = $DayNight
@onready var _clock_label: Label = $HUD/Margin/Rows/ClockLabel
@onready var _harvest_label: Label = $HUD/Margin/Rows/HarvestLabel
@onready var _hint_label: Label = $HUD/Margin/Rows/HintLabel


func _ready() -> void:
	TimeSystem.minute_changed.connect(func(_m: int) -> void: _refresh_clock())
	TimeSystem.day_changed.connect(func(_d: int) -> void: _refresh_clock())
	TimeSystem.season_changed.connect(func(_s: String) -> void: _refresh_clock())
	_farm.crop_harvested.connect(_on_crop_harvested)
	_hint_label.text = "WASD: move   E: till / plant / harvest"
	_refresh_clock()

	_emit_boot_probe.call_deferred()


func _refresh_clock() -> void:
	_clock_label.text = "Day %d (%s)  %s%s" % [
		TimeSystem.get_day(), TimeSystem.get_season(),
		TimeSystem.get_clock_text(),
		"  [night]" if _day_night.is_night else "",
	]


func _on_crop_harvested(_cell: Vector2i, crop: Crop, amount: int) -> void:
	var total := GameManager.get_flag("harvested_" + crop.harvest_item, 0) as int
	_harvest_label.text = "Harvested: %d %s (+%d)" % [total, crop.display_name, amount]


func _emit_boot_probe() -> void:
	for i in 4:
		await get_tree().physics_frame
	var tick_ok := ClassDB.class_exists("TimeTick") and TimeSystem.time_tick != null
	# Farming loop on the tile under the farmer: till, plant, then sleep two
	# game days so the crop advances two growth stages.
	var tilled: bool = _player.interact_here() == "till"
	var planted: bool = _player.interact_here() == "plant"
	var cell: Vector2i = _player.current_cell()
	TimeSystem.sleep_to_next_day()
	TimeSystem.sleep_to_next_day()
	var stage: int = _farm.get_stage(cell)
	# Day/night: jump the clock to 22:00 and check the tint reacted.
	var day_tint := _day_night.color
	TimeSystem.set_hour(22)
	var night_tint := _day_night.color
	print("DEBUG: farming-sim core loop ready — time_tick=%s day=%d tilled=%s planted=%s stage_after_2_days=%d night=%s tint_shift=%s" % [
		tick_ok, TimeSystem.get_day(), tilled, planted, stage,
		_day_night.is_night, day_tint != night_tint,
	])
