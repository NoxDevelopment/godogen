extends Node
## res://scripts/game_manager.gd
## Autoload holding the RunnerEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic, 60Hz fixed-timestep). The view feeds the player's per-tick
## intent (lane change / jump / slide); autoplay runs the dodge AI.

var engine: RunnerEngine = null
var run_seed: int = 0
var autoplay: bool = false
var _dir := 0
var _jump := false
var _slide := false

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = RunnerEngine.new()
	engine.setup(run_seed)

func advance(_delta: float) -> void:
	if engine == null or engine.game_over:
		return
	if autoplay:
		engine.tick(engine.ai_input())
	else:
		engine.tick({"dir": _dir, "jump": _jump, "slide": _slide})
		_dir = 0
		_jump = false
		_slide = false

func queue_dir(d: int) -> void:
	if not autoplay:
		_dir = d

func queue_jump() -> void:
	if not autoplay:
		_jump = true

func queue_slide() -> void:
	if not autoplay:
		_slide = true

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = RunnerEngine.new()
	engine.load_data(d.get("engine", {}))
