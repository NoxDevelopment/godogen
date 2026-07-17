extends Node
## res://scripts/game_manager.gd
## Autoload holding the game's TbsEngine + the NoxDev save/load ABI. The engine is the
## single source of truth (pure + deterministic, turn-based); the view reads it to render
## the player's turn and issues commands (move_unit/attack/found_city/set_city_build/
## end_turn). When the player ends their turn, the AI opponent plays its whole turn via
## engine.ai_take_turn(CIV_AI). Set player_auto to also let the AI play the player's side.

var engine: TbsEngine = null
var run_seed: int = 0
var player_auto: bool = false

func _ready() -> void:
	new_game()

func new_game(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = TbsEngine.new()
	engine.setup(run_seed)

## End the human's turn: hand control to the AI, which plays and ends its own turn,
## returning control to the player at the start of the next round.
func player_end_turn() -> void:
	if engine == null or engine.game_over:
		return
	if engine.current == TbsEngine.CIV_PLAYER:
		engine.end_turn()                       # player -> AI
	if engine.current == TbsEngine.CIV_AI and not engine.game_over:
		engine.ai_take_turn(TbsEngine.CIV_AI)   # AI plays + ends -> back to player

## Full auto: let the macro AI play the player's side too (one round per call).
func auto_round() -> void:
	if engine == null or engine.game_over:
		return
	engine.ai_take_turn(engine.current)

# NoxDev ABI — the whole game is one blob (deterministic replay from seed + commands,
# or the full snapshot here for a mid-game save).
func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "player_auto": player_auto,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	player_auto = bool(d.get("player_auto", false))
	engine = TbsEngine.new()
	engine.load_data(d.get("engine", {}))
