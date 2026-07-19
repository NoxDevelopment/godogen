extends Node
## res://scripts/game_manager.gd
## Autoload holding the SandboxEngine + the NoxDev save/load ABI. The engine is the single source of
## truth (pure + deterministic). The view drives travel + context actions; autoplay runs the greedy
## resident.
## NOTE: the `mature_content` gating flag defaults OFF and only unlocks EMPTY author hooks; this
## template ships the sandbox SYSTEMS, not explicit content.

var engine: SandboxEngine = null
var run_seed: int = 0
var autoplay: bool = false

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = SandboxEngine.new()
	engine.setup(run_seed)

func travel(loc: int) -> void:
	if engine and not autoplay:
		engine.travel(loc)

## Perform a context action by id (with an optional npc index).
func act(id: String, npc: int = -1) -> void:
	if engine == null or autoplay or engine.game_over:
		return
	match id:
		"work": engine.work()
		"train": engine.train()
		"buy": engine.buy_gift()
		"relax": engine.relax()
		"sleep": engine.sleep()
		"wait": engine.wait()
		"socialize": engine.socialize(npc)
		"gift": engine.gift(npc)

func step_autoplay() -> void:
	if engine and autoplay and not engine.game_over:
		engine.ai_step()

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = SandboxEngine.new()
	engine.load_data(d.get("engine", {}))
