extends Node
## res://scripts/game_manager.gd
## Autoload holding the LifeEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic). The view steps the sim on a real-time cadence (a game-tick
## every ~0.15s, speed-adjustable) with the player's chosen action; autoplay lets the built-in
## routine AI run the character's day.

var engine: LifeEngine = null
var run_seed: int = 0
var autoplay: bool = false
var speed: int = 2                  ## ticks per real second cadence multiplier
var _accum := 0.0
var pending_action := ""

func _ready() -> void:
	new_life()

func new_life(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = LifeEngine.new()
	engine.setup(run_seed)

func advance(delta: float) -> void:
	if engine == null:
		return
	_accum += delta * float(speed) * 6.0
	while _accum >= 1.0:
		_accum -= 1.0
		if autoplay:
			engine.auto_step()
		else:
			engine.tick({"action": pending_action})
			pending_action = ""

func choose(kind: String) -> void:
	if not autoplay:
		pending_action = kind

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = LifeEngine.new()
	engine.load_data(d.get("engine", {}))
