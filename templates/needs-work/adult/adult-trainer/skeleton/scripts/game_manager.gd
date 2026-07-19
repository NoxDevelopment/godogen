extends Node
## res://scripts/game_manager.gd
## Autoload holding the TrainerEngine + the NoxDev save/load ABI. The engine is the single source of
## truth (pure + deterministic). The view picks each week's activity; autoplay runs the greedy
## trainer.
## NOTE: the `mature_content` gating flag defaults OFF and only unlocks EMPTY author hooks; this
## template ships the raiser SYSTEMS, not explicit content.

var engine: TrainerEngine = null
var run_seed: int = 0
var autoplay: bool = false

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = TrainerEngine.new()
	engine.setup(run_seed)

func choose(id: String) -> void:
	if engine and not autoplay and not engine.game_over:
		engine.do_activity(id)

func step_autoplay() -> void:
	if engine and autoplay and not engine.game_over:
		engine.auto_step()

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = TrainerEngine.new()
	engine.load_data(d.get("engine", {}))
