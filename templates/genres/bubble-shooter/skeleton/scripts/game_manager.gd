extends Node
## res://scripts/game_manager.gd
## Autoload holding the BubbleEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic). The view sets the aim angle and requests a fire; autoplay
## runs the deterministic aim seat.

var engine: BubbleEngine = null
var run_seed: int = 0
var autoplay: bool = false
var aim: float = 0.0                ## radians, 0 = straight up

func _ready() -> void:
	new_match()

func new_match(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = BubbleEngine.new()
	engine.setup(run_seed)
	aim = 0.0

func set_aim(a: float) -> void:
	aim = clampf(a, -1.35, 1.35)

func shoot() -> void:
	if engine == null or engine.game_over:
		return
	engine.fire(aim)

func step_autoplay() -> void:
	if engine == null or engine.game_over or not autoplay:
		return
	engine.fire(engine.ai_angle())

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = BubbleEngine.new()
	engine.load_data(d.get("engine", {}))
