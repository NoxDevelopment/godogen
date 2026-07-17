extends Node
## res://scripts/game_manager.gd
## Autoload holding the run's IdleEngine + the NoxDev save/load ABI. The engine is the single
## source of truth (pure + deterministic, 60Hz fixed-timestep). The view samples the human's
## click/buy/tap each physics tick and calls engine.tick(input); autoplay hands the run to the
## built-in greedy seat (idle/attract mode).

var engine: IdleEngine = null
var run_seed: int = 0
var autoplay: bool = false

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = IdleEngine.new()
	engine.setup(run_seed)

## Advance one fixed sim tick with the player's input (interactive), or the greedy seat.
func advance(input: Dictionary) -> void:
	if engine == null:
		return
	engine.tick(engine.ai_input() if autoplay else input)

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = IdleEngine.new()
	engine.load_data(d.get("engine", {}))
