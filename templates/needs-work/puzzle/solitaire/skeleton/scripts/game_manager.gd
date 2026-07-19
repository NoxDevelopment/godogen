extends Node
## res://scripts/game_manager.gd
## Autoload holding the SolitaireEngine + the NoxDev save/load ABI. The engine is the single source
## of truth (pure + deterministic). The view drives interactive moves through the helper methods
## here (draw / select-then-place / send-home); autoplay runs the deterministic greedy solver.

var engine: SolitaireEngine = null
var run_seed: int = 0
var autoplay: bool = false

# selection for click-to-move: {"kind": "waste"|"tableau", "col": int, "idx": int} or empty
var sel: Dictionary = {}

func _ready() -> void:
	new_game()

func new_game(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = SolitaireEngine.new()
	engine.setup(run_seed)
	sel = {}

func step_autoplay() -> void:
	if engine == null or not autoplay:
		return
	engine.auto_step()

func hint_step() -> void:
	## play a single solver move by hand (the "auto one move" button)
	if engine != null and not autoplay:
		engine.auto_step()

# ---- interactive move helpers (called by the view) ---- #

func draw() -> void:
	if engine and not autoplay:
		engine.draw()
		sel = {}

func select_waste() -> void:
	if engine and not engine.waste.is_empty():
		sel = {"kind": "waste"}

func select_tableau(col: int, idx: int) -> void:
	if engine == null:
		return
	var start := engine.run_start(col)
	if start >= 0 and idx >= start:
		sel = {"kind": "tableau", "col": col, "idx": idx}

## Try to place the current selection on tableau column `dst`. Returns true on success.
func place_on_tableau(dst: int) -> bool:
	if engine == null or sel.is_empty():
		return false
	var done := false
	if sel.kind == "waste":
		done = engine.waste_to_tableau(dst)
	elif sel.kind == "tableau":
		done = engine.tableau_to_tableau(int(sel.col), int(sel.idx), dst)
	if done:
		sel = {}
	return done

## Try to send the current selection (or a given tableau top) to its foundation.
func send_home_selection() -> bool:
	if engine == null or sel.is_empty():
		return false
	var done := false
	if sel.kind == "waste":
		done = engine.waste_to_foundation()
	elif sel.kind == "tableau":
		# only a single top card can go home
		var col: int = int(sel.col)
		if int(sel.idx) == engine.tableau[col].size() - 1:
			done = engine.tableau_to_foundation(col)
	if done:
		sel = {}
	return done

func clear_selection() -> void:
	sel = {}

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "autoplay": autoplay,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	autoplay = bool(d.get("autoplay", false))
	engine = SolitaireEngine.new()
	engine.load_data(d.get("engine", {}))
