extends Node
## res://scripts/game_manager.gd
## Autoload holding the MergeEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic). The view calls move(dir) on a swipe/key; autoplay runs the
## corner-heuristic seat a few moves per second.

var engine: MergeEngine = null
var run_seed: int = 0
var autoplay: bool = false
var _accum := 0.0

func _ready() -> void:
	new_game()

func new_game(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = MergeEngine.new()
	engine.setup(run_seed)

func advance(delta: float) -> void:
	if engine == null or engine.game_over or not autoplay:
		return
	_accum += delta
	if _accum >= 0.1:
		_accum = 0.0
		engine.auto_step()

func move(dir_name: String) -> void:
	if engine and not engine.game_over and not autoplay:
		engine.move(dir_name)

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = MergeEngine.new()
	engine.load_data(d.get("engine", {}))
