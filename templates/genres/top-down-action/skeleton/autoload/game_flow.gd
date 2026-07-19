extends Node
## GameFlow — full-game flow for the Twin Shooter template.
## Turns the twin-stick combat loop into an actual game: title menu -> a run of
## escalating combat waves with live scoring and a timer -> victory screen, with
## the best score/time persisted to disk. Registered as an autoload so it
## survives scene changes between waves.

const ARENA := "res://scenes/play/arena.tscn"
const MENU := "res://ui/main_menu.tscn"
const WIN := "res://ui/win_screen.tscn"
const STORY := "res://scenes/main.tscn"
const SAVE_PATH := "user://twinshooter_save.cfg"

## How many waves make up a full run.
const TOTAL_LEVELS := 3

var current := 1                 ## 1-based wave the player is on
var enemies_defeated := 0        ## cumulative kills committed from cleared waves
var wave_kills := 0              ## kills so far in the current wave (live)
var items := 0                   ## pickups collected this run
var run_time := 0.0              ## elapsed run time in seconds
var enemies_left := 0            ## live enemy count in the current wave (HUD)

var best_score := 0
var best_time := 0.0

var _timing := false

func _ready() -> void:
	_load()

func _process(delta: float) -> void:
	if _timing:
		run_time += delta

## Live score = every kill (committed + current wave) plus pickup bonuses.
func score() -> int:
	return (enemies_defeated + wave_kills) * 100 + items * 50

func new_game() -> void:
	current = 1
	enemies_defeated = 0
	wave_kills = 0
	items = 0
	run_time = 0.0
	enemies_left = 0
	_timing = true
	get_tree().change_scene_to_file(ARENA)

## Called by the level exit when a wave is cleared and the player reaches it.
func next_level() -> void:
	enemies_defeated += wave_kills
	wave_kills = 0
	if current >= TOTAL_LEVELS:
		_win()
	else:
		current += 1
		get_tree().change_scene_to_file(ARENA)

func add_item() -> void:
	items += 1

func to_menu() -> void:
	_timing = false
	get_tree().change_scene_to_file(MENU)

func play_story() -> void:
	_timing = false
	get_tree().change_scene_to_file(STORY)

func pause_timer() -> void:
	_timing = false

func _win() -> void:
	_timing = false
	_save()
	get_tree().change_scene_to_file(WIN)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = int(cfg.get_value("run", "best_score", 0))
		best_time = float(cfg.get_value("run", "best_time", 0.0))

func _save() -> void:
	var final_score := score()
	if final_score > best_score:
		best_score = final_score
	if best_time <= 0.0 or (run_time > 0.0 and run_time < best_time):
		best_time = run_time
	var cfg := ConfigFile.new()
	cfg.set_value("run", "best_score", best_score)
	cfg.set_value("run", "best_time", best_time)
	cfg.save(SAVE_PATH)

static func format_time(t: float) -> String:
	return "%02d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]
