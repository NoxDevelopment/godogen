extends Node
## NoxSettings — standard NoxDev settings (video + audio), persisted to
## user://nox_settings.cfg and applied on boot. Autoload this as "NoxSettings".
## Audio applies to the "Master", "Music", "SFX" buses when they exist.

const PATH := "user://nox_settings.cfg"

var fullscreen := false
var vsync := true
var master := 0.9
var music := 0.8
var sfx := 0.9

func _ready() -> void:
	load_settings()
	apply()

func apply() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	_set_bus("Master", master)
	_set_bus("Music", music)
	_set_bus("SFX", sfx)

func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return  # bus not defined in this project — skip
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(v, 0.0001, 1.0)))

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save_settings()

func set_vsync(on: bool) -> void:
	vsync = on
	apply()
	save_settings()

func set_volume(kind: String, v: float) -> void:
	match kind:
		"master": master = v
		"music": music = v
		"sfx": sfx = v
	apply()
	save_settings()

func save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("video", "vsync", vsync)
	c.set_value("audio", "master", master)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.save(PATH)

func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	fullscreen = bool(c.get_value("video", "fullscreen", false))
	vsync = bool(c.get_value("video", "vsync", true))
	master = float(c.get_value("audio", "master", 0.9))
	music = float(c.get_value("audio", "music", 0.8))
	sfx = float(c.get_value("audio", "sfx", 0.9))
