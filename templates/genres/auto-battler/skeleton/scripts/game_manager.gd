extends Node
## res://scripts/game_manager.gd
## Autoload holding the AutoBattlerEngine + the NoxDev save/load ABI. The engine is the single
## source of truth (pure + deterministic). The view drives the SHOP phase directly
## (buy/sell/roll/freeze/move) then calls end_shop() to auto-resolve the round; autoplay runs the
## built-in shop AI + combat one round per tick.

var engine: AutoBattlerEngine = null
var run_seed: int = 0
var autoplay: bool = false
var _accum := 0.0

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = AutoBattlerEngine.new()
	engine.setup(run_seed)

## Autoplay: play one full round (shop AI + combat) every ~0.6s so it is watchable.
func advance(delta: float) -> void:
	if engine == null or engine.game_over or not autoplay:
		return
	_accum += delta
	if _accum >= 0.6:
		_accum = 0.0
		engine.auto_step()

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = AutoBattlerEngine.new()
	engine.load_data(d.get("engine", {}))
