extends Node
## res://scripts/game_manager.gd
## Autoload holding the quiz's QuizEngine + the NoxDev save/load ABI. The engine is the single
## source of truth (pure + deterministic). The view drives the per-question timer via
## engine.tick() each physics tick and calls engine.answer(choice) on a selection; autoplay
## hands the quiz to the built-in perfect seat (demo/attract).

var engine: QuizEngine = null
var run_seed: int = 0
var autoplay: bool = false
var _auto_accum := 0.0

func _ready() -> void:
	new_quiz()

func new_quiz(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = QuizEngine.new()
	engine.setup(run_seed)

## Called each physics tick by the view: run the countdown, or (in autoplay) answer paced.
func advance(delta: float) -> void:
	if engine == null or engine.done:
		return
	if autoplay:
		_auto_accum += delta
		if _auto_accum >= 0.6:
			_auto_accum = 0.0
			engine.auto_step("perfect")
	else:
		engine.tick()

func choose(i: int) -> void:
	if engine and not engine.done and not autoplay:
		engine.answer(i)

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = QuizEngine.new()
	engine.load_data(d.get("engine", {}))
