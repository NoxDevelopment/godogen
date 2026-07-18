extends Node
## res://scripts/game_manager.gd
## Autoload holding the HordeEngine + the NoxDev save/load ABI. The engine is the single source of
## truth (pure + deterministic). The view recruits units then fights the wave; autoplay runs the
## greedy commander.

var engine: HordeEngine = null
var run_seed: int = 0
var autoplay: bool = false

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = HordeEngine.new()
	engine.setup(run_seed)

func recruit(kind: String) -> void:
	if engine and not autoplay:
		engine.recruit(kind)

func fight() -> void:
	if engine and not autoplay and not engine.game_over:
		engine.fight_wave()

func step_autoplay() -> void:
	if engine and autoplay and not engine.game_over:
		engine.ai_round()

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = HordeEngine.new()
	engine.load_data(d.get("engine", {}))
