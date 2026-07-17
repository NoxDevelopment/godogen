extends Node
## res://scripts/game_manager.gd
## Autoload holding the PuzzleDateEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic). The view drives token selection / swaps + gift purchases;
## autoplay runs the deterministic greedy player.
## NOTE: the `mature_content` gating flag defaults OFF and only unlocks EMPTY author hooks; this
## template ships the puzzle + dating SYSTEMS, not explicit content.

var engine: PuzzleDateEngine = null
var run_seed: int = 0
var autoplay: bool = false
var sel := Vector2i(-1, -1)          ## first-selected cell for a swap (or -1,-1)

func _ready() -> void:
	new_run()

func new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = PuzzleDateEngine.new()
	engine.setup(run_seed)
	sel = Vector2i(-1, -1)

## Click a cell: first selects, a second adjacent click attempts the swap.
func click_cell(r: int, c: int) -> void:
	if engine == null or autoplay or engine.game_over:
		return
	if sel.x < 0:
		sel = Vector2i(r, c)
		return
	if sel.x == r and sel.y == c:
		sel = Vector2i(-1, -1)
		return
	engine.play_move(sel.x, sel.y, r, c)      # engine no-ops if illegal
	sel = Vector2i(-1, -1)

func buy_gift(i: int) -> void:
	if engine and not autoplay:
		engine.buy_gift(i)

func step_autoplay() -> void:
	if engine and autoplay and not engine.game_over:
		engine.auto_step()

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = PuzzleDateEngine.new()
	engine.load_data(d.get("engine", {}))
