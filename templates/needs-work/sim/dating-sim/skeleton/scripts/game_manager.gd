extends Node
## res://scripts/game_manager.gd
## Autoload holding the DatingEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic, calendar/day-driven — not real-time). The view calls the
## day-actions (train/work/go_on_date/give_gift/confess) directly on the player's choice; autoplay
## runs the built-in pursue-a-partner seat one day per tick.
##
## NOTE: the `mature_content` gating flag defaults OFF and only unlocks EMPTY author hooks; this
## template ships the dating-sim SYSTEMS, not explicit content.

var engine: DatingEngine = null
var run_seed: int = 0
var autoplay: bool = false
var _accum := 0.0

func _ready() -> void:
	new_game()

func new_game(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = DatingEngine.new()
	engine.setup(run_seed)

## In autoplay, advance one in-game day every ~0.4s so the calendar is watchable.
func advance(delta: float) -> void:
	if engine == null or engine.game_over or not autoplay:
		return
	_accum += delta
	if _accum >= 0.4:
		_accum = 0.0
		engine.auto_step()

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = DatingEngine.new()
	engine.load_data(d.get("engine", {}))
