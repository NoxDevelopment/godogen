extends Node
## res://scripts/time_system.gd
## Game clock autoload ("TimeSystem"): a thin first-party wrapper around the
## TimeTick GDExtension. One tick (0.1 s real) = one game minute, so a full
## day runs ~2.4 minutes of real time at scale 1. Hierarchy:
## tick -> minute (0-59) -> hour (0-23) -> day (1..) with a derived
## 28-day season wheel (spring/summer/autumn/winter), Stardew style.
## Farm systems listen to day_changed to advance crop growth.

signal minute_changed(minute: int)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal season_changed(season: String)

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
const DAYS_PER_SEASON := 28
## Real seconds per game minute at time scale 1.0.
const TICK_INTERVAL := 0.1

var time_tick: TimeTick

var _last_season := "spring"


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


func _ready() -> void:
	time_tick = TimeTick.new()
	time_tick.initialize(TICK_INTERVAL)
	# register_time_unit(name, parent, step, wrap, start)
	time_tick.register_time_unit("minute", "tick", 1, 60, 0)
	time_tick.register_time_unit("hour", "minute", 60, 24, 6)  # days start 06:00
	time_tick.register_time_unit("day", "hour", 24, -1, 1)
	time_tick.time_unit_changed.connect(_on_time_unit_changed)


func _exit_tree() -> void:
	if time_tick:
		time_tick.shutdown()


func get_minute() -> int:
	return time_tick.get_time_unit("minute")


func get_hour() -> int:
	return time_tick.get_time_unit("hour")


func get_day() -> int:
	return time_tick.get_time_unit("day")


func get_season() -> String:
	return SEASONS[((get_day() - 1) / DAYS_PER_SEASON) % SEASONS.size()]


## Day progress in [0, 1) — 0.0 is midnight. Drives the day/night tint.
func get_day_fraction() -> float:
	return (get_hour() + get_minute() / 60.0) / 24.0


func get_clock_text() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


func set_time_scale(scale: float) -> void:
	time_tick.set_time_scale(scale)


## Jump the clock (probe / sleep mechanic): straight to 06:00 next day.
## Listeners must be day-idempotent — depending on the engine build,
## set_time_units may also fire time_unit_changed, so day_changed can arrive
## more than once per sleep (the farm computes growth from day deltas, so
## duplicates are harmless).
func sleep_to_next_day() -> void:
	time_tick.set_time_units({"day": get_day() + 1, "hour": 6, "minute": 0})
	day_changed.emit(get_day())
	_check_season()


## Jump the clock to an hour of the current day (probe / cutscenes).
func set_hour(hour: int) -> void:
	time_tick.set_time_units({"hour": hour, "minute": 0})
	hour_changed.emit(get_hour())


func _on_time_unit_changed(unit_name: String, new_value: int, _old_value: int) -> void:
	match unit_name:
		"minute":
			minute_changed.emit(new_value)
		"hour":
			hour_changed.emit(new_value)
		"day":
			day_changed.emit(new_value)
			_check_season()


func _check_season() -> void:
	var season := get_season()
	if season != _last_season:
		_last_season = season
		season_changed.emit(season)


## "persistent" group contract (see templates ABI).
func save_data() -> Dictionary:
	return {
		"day": get_day(),
		"hour": get_hour(),
		"minute": get_minute(),
	}


func load_data(data: Dictionary) -> void:
	time_tick.set_time_units({
		"day": int(data.get("day", 1)),
		"hour": int(data.get("hour", 6)),
		"minute": int(data.get("minute", 0)),
	})
