extends Node
## res://scripts/game_manager.gd
## Autoload holding the match's FightEngine + the NoxDev save/load ABI. The engine is the
## single source of truth (pure + deterministic, 60Hz fixed-timestep). The view samples the
## human's inputs each physics tick and calls engine.tick(p1_input, ai_input); the AI drives
## P2 via engine.ai_input(1). Set player_auto to let the AI drive P1 too (attract mode).

var engine: FightEngine = null
var run_seed: int = 0
var player_auto: bool = false

func _ready() -> void:
	new_match()

func new_match(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = FightEngine.new()
	engine.setup(run_seed)

## Advance exactly one fixed sim frame. Call from _physics_process (60Hz) with the human's
## sampled input for P1; P2 is the AI. player_auto hands P1 to the AI as well.
func advance(p1_input: Dictionary) -> void:
	if engine == null or engine.game_over:
		return
	var i0: Dictionary = engine.ai_input(0) if player_auto else p1_input
	engine.tick(i0, engine.ai_input(1))

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "player_auto": player_auto,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	player_auto = bool(d.get("player_auto", false))
	engine = FightEngine.new()
	engine.load_data(d.get("engine", {}))
