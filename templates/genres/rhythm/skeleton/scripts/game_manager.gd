extends Node
## res://scripts/game_manager.gd
## Autoload holding the song's RhythmEngine + the NoxDev save/load ABI. The engine is the
## single source of truth (pure + deterministic, 60Hz fixed-timestep). The view samples the
## human's lane taps each physics tick and calls engine.tick({lanes:[...]}); autoplay hands
## the chart to the built-in perfect seat (attract mode).

var engine: RhythmEngine = null
var run_seed: int = 0
var autoplay: bool = false

func _ready() -> void:
	new_song()

func new_song(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = RhythmEngine.new()
	engine.setup(run_seed)

## Advance exactly one fixed sim tick. Call from _physics_process (60Hz).
func advance(input: Dictionary) -> void:
	if engine == null or engine.game_over:
		return
	engine.tick(engine.seat_input("perfect") if autoplay else input)

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = RhythmEngine.new()
	engine.load_data(d.get("engine", {}))
