extends Node
## res://scripts/game_manager.gd
## Autoload holding the SurvivalEngine + the NoxDev save/load ABI. The engine is the single
## source of truth (pure + deterministic). Interactive: the view sets a held MOVE each frame +
## queues one-shot ACTS, and the sim ticks once per frame; autoplay multi-ticks the survival AI.

var engine: SurvivalEngine = null
var run_seed: int = 0
var autoplay: bool = false
var speed: int = 3
var _accum := 0.0
var move_dir := Vector2.ZERO
var act_now := ""
var act_target := 0

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = SurvivalEngine.new()
	engine.setup(run_seed)

func advance(delta: float) -> void:
	if engine == null or engine.game_over:
		return
	if autoplay:
		_accum += delta * float(speed) * 8.0
		while _accum >= 1.0:
			_accum -= 1.0
			engine.auto_step()
	else:
		engine.tick({"move": move_dir, "act": act_now, "target": act_target})
		act_now = ""            # one-shot act consumed

func set_move(v: Vector2) -> void:
	move_dir = v

func queue_act(a: String, target: int = 0) -> void:
	if not autoplay:
		act_now = a
		act_target = target

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = SurvivalEngine.new()
	engine.load_data(d.get("engine", {}))
