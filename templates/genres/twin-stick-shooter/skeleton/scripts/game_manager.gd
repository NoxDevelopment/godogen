extends Node
## res://scripts/game_manager.gd
## Autoload holding the run's ShooterEngine + the NoxDev save/load ABI. The engine is the
## single source of truth (pure + deterministic, 60Hz fixed-timestep). The view samples the
## human's move/aim/fire each physics tick and calls engine.tick(input); player_auto hands
## control to the built-in kite-and-fire seat (attract mode).

var engine: ShooterEngine = null
var run_seed: int = 0
var player_auto: bool = false

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = ShooterEngine.new()
	engine.setup(run_seed)

## Advance exactly one fixed sim frame. Call from _physics_process (60Hz).
func advance(input: Dictionary) -> void:
	if engine == null or engine.game_over:
		return
	engine.tick(engine.ai_input() if player_auto else input)

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "player_auto": player_auto,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	player_auto = bool(d.get("player_auto", false))
	engine = ShooterEngine.new()
	engine.load_data(d.get("engine", {}))
