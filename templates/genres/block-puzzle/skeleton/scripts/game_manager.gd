extends Node
## res://scripts/game_manager.gd
## Autoload holding the game's BlockEngine + the NoxDev save/load ABI. The engine is the
## single source of truth (pure + deterministic). The view drives gravity by calling
## engine.tick(input) each physics tick with the player's sampled inputs; autoplay hands the
## board to the built-in Dellacherie placement AI (attract mode).

var engine: BlockEngine = null
var run_seed: int = 0
var autoplay: bool = false

func _ready() -> void:
	new_game()

func new_game(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = BlockEngine.new()
	engine.setup(run_seed)

## One physics tick of gravity + input (interactive), or one AI placement (attract).
func advance(input: Dictionary) -> void:
	if engine == null or engine.game_over:
		return
	if autoplay:
		engine.ai_place()
	else:
		engine.tick(input)

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = BlockEngine.new()
	engine.load_data(d.get("engine", {}))
