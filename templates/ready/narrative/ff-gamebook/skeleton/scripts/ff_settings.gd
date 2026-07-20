extends Node
## res://scripts/ff_settings.gd
## FFSettings (autoload "FFSettings") — the FF-gamebook-specific preferences that the
## fleshed Options screen (GDD §6.1 "Fully fleshed Options": Reading / Combat / Dice /
## Accessibility / Rules-Mode) reads and writes. Video + master/music/sfx volume stay
## in the shared NoxSettings; everything gameplay-shaped lives here so the generic
## shell autoload is never forked. Persisted to user://ff_settings.cfg, applied on
## boot, and live-applied where feasible (UI/text scale is applied immediately via the
## window content-scale; the reading view reacts to `changed` for prose font size and
## page theme). Consumers (reading view, combat, dice overlay, SaveManager) read the
## typed getters on demand.

signal changed

const PATH := "user://ff_settings.cfg"

## GDD §4 death/save modes. Bookmarks is the approachable default; Ironman for purists.
enum SaveMode { BOOKMARKS, IRONMAN, REWIND, CHECKPOINTS }
const SAVE_MODE_NAMES := ["Bookmarks", "Ironman", "Rewind", "Checkpoints"]

## Reading page themes (STYLE_GUIDE parchment/sepia/dark grounds).
enum ReadingTheme { PARCHMENT, SEPIA, DARK }
const READING_THEME_NAMES := ["Parchment", "Sepia", "Dark"]

# --- Reading ---------------------------------------------------------------------
var font_scale: float = 1.0          # 0.8 .. 1.6 — reading prose size multiplier
var reading_theme: int = ReadingTheme.PARCHMENT

# --- Combat ----------------------------------------------------------------------
var quick_combat: bool = false       # auto-run combat rounds

# --- Dice ------------------------------------------------------------------------
var dice_animation: bool = true      # animate the tumble (off = snap to result)
var dice_speed: float = 1.0          # 0.5 (slow) .. 2.0 (fast) tumble-time scale
var dice_3d: bool = true             # 3D physics dice (off = honest-pips 2D fallback)

# --- Accessibility ---------------------------------------------------------------
var text_scale: float = 1.0          # 0.8 .. 2.0 — global UI scale (content_scale)
var reduced_motion: bool = false     # snap dice / pause credit crawl / no crossfades

# --- Rules / Mode ----------------------------------------------------------------
var save_mode: int = SaveMode.BOOKMARKS


func _ready() -> void:
	load_settings()
	apply()


## Apply the settings that have an immediate, global effect. Text scale drives the
## window content-scale factor so the whole UI grows/shrinks live (accessibility).
func apply() -> void:
	var win := get_window()
	if win != null:
		win.content_scale_factor = clampf(text_scale, 0.5, 3.0)


func save_mode_name() -> String:
	return SAVE_MODE_NAMES[clampi(save_mode, 0, SAVE_MODE_NAMES.size() - 1)]


func is_ironman() -> bool:
	return save_mode == SaveMode.IRONMAN


# --- setters (persist + live-apply + notify) -------------------------------------

func set_font_scale(v: float) -> void:
	font_scale = clampf(v, 0.8, 1.6)
	_commit()

func set_reading_theme(v: int) -> void:
	reading_theme = clampi(v, 0, ReadingTheme.size() - 1)
	_commit()

func set_quick_combat(on: bool) -> void:
	quick_combat = on
	_commit()

func set_dice_animation(on: bool) -> void:
	dice_animation = on
	_commit()

func set_dice_speed(v: float) -> void:
	dice_speed = clampf(v, 0.5, 2.0)
	_commit()

func set_dice_3d(on: bool) -> void:
	dice_3d = on
	_commit()

func set_text_scale(v: float) -> void:
	text_scale = clampf(v, 0.8, 2.0)
	apply()
	_commit()

func set_reduced_motion(on: bool) -> void:
	reduced_motion = on
	_commit()

func set_save_mode(v: int) -> void:
	save_mode = clampi(v, 0, SaveMode.size() - 1)
	_commit()


func _commit() -> void:
	save_settings()
	changed.emit()


# --- persistence -----------------------------------------------------------------

func save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("reading", "font_scale", font_scale)
	c.set_value("reading", "theme", reading_theme)
	c.set_value("combat", "quick_combat", quick_combat)
	c.set_value("dice", "animation", dice_animation)
	c.set_value("dice", "speed", dice_speed)
	c.set_value("dice", "dice_3d", dice_3d)
	c.set_value("accessibility", "text_scale", text_scale)
	c.set_value("accessibility", "reduced_motion", reduced_motion)
	c.set_value("rules", "save_mode", save_mode)
	c.save(PATH)


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	font_scale = float(c.get_value("reading", "font_scale", 1.0))
	reading_theme = int(c.get_value("reading", "theme", ReadingTheme.PARCHMENT))
	quick_combat = bool(c.get_value("combat", "quick_combat", false))
	dice_animation = bool(c.get_value("dice", "animation", true))
	dice_speed = float(c.get_value("dice", "speed", 1.0))
	dice_3d = bool(c.get_value("dice", "dice_3d", true))
	text_scale = float(c.get_value("accessibility", "text_scale", 1.0))
	reduced_motion = bool(c.get_value("accessibility", "reduced_motion", false))
	save_mode = int(c.get_value("rules", "save_mode", SaveMode.BOOKMARKS))
