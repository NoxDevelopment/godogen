extends Node
## res://scripts/game_manager.gd
## Autoload holding the VenueMgmtEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic). The view drives management actions + advances the day; autoplay
## runs the deterministic greedy manager.
## NOTE: the `mature_content` gating flag defaults OFF and only unlocks EMPTY author hooks; this
## template ships the venue-management SYSTEMS, not explicit content.

var engine: VenueMgmtEngine = null
var run_seed: int = 0
var autoplay: bool = false

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = VenueMgmtEngine.new()
	engine.setup(run_seed)

func advance_day() -> void:
	if engine and not engine.game_over and not autoplay:
		engine.run_shift()

func step_autoplay() -> void:
	if engine and autoplay and not engine.game_over:
		engine.ai_day()

# passthrough management actions
func hire() -> void: if engine and not autoplay: engine.hire()
func add_room() -> void: if engine and not autoplay: engine.add_room()
func upgrade_room(i: int) -> void: if engine and not autoplay: engine.upgrade_room(i)
func run_marketing() -> void: if engine and not autoplay: engine.run_marketing()

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = VenueMgmtEngine.new()
	engine.load_data(d.get("engine", {}))
