extends Node
## res://scripts/game_manager.gd
## Autoload holding the DotIoEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic, 60Hz fixed-timestep). The view sets the player's steer vector
## each physics tick and calls engine.tick(); player_auto makes every hole AI (attract).

var engine: DotIoEngine = null
var run_seed: int = 0
var player_auto: bool = false
var move_dir := Vector2.ZERO

func _ready() -> void:
	new_match()

func new_match(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = DotIoEngine.new()
	engine.setup(run_seed)

func advance(_delta: float) -> void:
	if engine == null or engine.game_over:
		return
	if player_auto:
		engine.tick({"_ai": true})
	else:
		engine.tick({"move": move_dir})

func set_move(v: Vector2) -> void:
	move_dir = v

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "player_auto": player_auto,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	player_auto = bool(d.get("player_auto", false))
	engine = DotIoEngine.new()
	engine.load_data(d.get("engine", {}))
