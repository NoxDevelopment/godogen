extends CanvasModulate
## res://scripts/day_night.gd
## First-party 2D day/night layer: tints the whole canvas from the game
## clock (TimeSystem.get_day_fraction()) via a 24-hour gradient — night
## blues, dawn/dusk warmth, clear noon. Kit note: the Wave-2 survey pick
## for day/night (maetzemax day-and-night-cycle) is 3D-only
## (DirectionalLight3D + WorldEnvironment sky), so the 2D farm drives its
## own CanvasModulate instead; swap this node for that addon if the project
## goes 3D.

signal day_started
signal night_started

const NIGHT_START_HOUR := 19
const DAY_START_HOUR := 6

var is_night := false

var _gradient := Gradient.new()


func _ready() -> void:
	# offsets are day fractions: hour / 24.
	_gradient.offsets = PackedFloat32Array([
		0.0,           # 00:00 deep night
		0.2083,        # 05:00 late night
		0.2917,        # 07:00 dawn
		0.5,           # 12:00 noon
		0.75,          # 18:00 late afternoon
		0.8333,        # 20:00 dusk
		0.9167,        # 22:00 night
		1.0,           # 24:00 deep night
	])
	_gradient.colors = PackedColorArray([
		Color(0.22, 0.26, 0.45),
		Color(0.25, 0.30, 0.50),
		Color(0.95, 0.78, 0.66),
		Color(1.0, 1.0, 1.0),
		Color(1.0, 0.96, 0.86),
		Color(0.85, 0.55, 0.45),
		Color(0.30, 0.32, 0.55),
		Color(0.22, 0.26, 0.45),
	])
	TimeSystem.minute_changed.connect(func(_m: int) -> void: _refresh())
	TimeSystem.hour_changed.connect(func(_h: int) -> void: _refresh())
	TimeSystem.day_changed.connect(func(_d: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	color = _gradient.sample(TimeSystem.get_day_fraction())
	var hour := TimeSystem.get_hour()
	var night_now := hour >= NIGHT_START_HOUR or hour < DAY_START_HOUR
	if night_now != is_night:
		is_night = night_now
		if is_night:
			night_started.emit()
		else:
			day_started.emit()
