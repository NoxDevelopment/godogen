extends Node
## res://scripts/game_manager.gd
## Autoload holding the WordEngine + the NoxDev save/load ABI. The engine is the single source of
## truth (pure + deterministic). The view collects the player's typed guess and submits it;
## autoplay runs the deterministic filtering solver.

var engine: WordEngine = null
var run_seed: int = 0
var autoplay: bool = false
var typed: String = ""             ## the in-progress guess (letters)

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = WordEngine.new()
	engine.setup(run_seed)
	typed = ""

func type_letter(ch: String) -> void:
	if autoplay or engine == null or engine.game_over:
		return
	if typed.length() < WordEngine.WORD_LEN and ch.length() == 1:
		typed += ch.to_upper()

func backspace() -> void:
	if not autoplay and typed.length() > 0:
		typed = typed.substr(0, typed.length() - 1)

func submit_typed() -> void:
	if autoplay or engine == null:
		return
	if engine.submit(typed):
		typed = ""

func step_autoplay() -> void:
	if engine == null or engine.game_over or not autoplay:
		return
	engine.auto_step()

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = WordEngine.new()
	engine.load_data(d.get("engine", {}))
