extends Node
## res://scripts/game_manager.gd
## Autoload holding the run's RogueEngine + the NoxDev save/load ABI. The engine is
## the single source of truth (pure + deterministic); the dungeon scene reads it to
## render and calls step()/quaff()/descend() on input. Permadeath: a new run reseeds.

var engine: RogueEngine = null
var run_seed: int = 0

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = RogueEngine.new()
	engine.setup(run_seed)

## NoxDev ABI — the whole run is one blob (deterministic replay from the seed + moves,
## or the full snapshot here for a mid-run save).
func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	engine = RogueEngine.new()
	engine.load_data(d.get("engine", {}))
