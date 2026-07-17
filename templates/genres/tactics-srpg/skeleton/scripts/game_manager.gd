extends Node
## res://scripts/game_manager.gd
## Autoload holding the battle's SrpgEngine + the NoxDev save/load ABI. The engine is the
## single source of truth (pure + deterministic, team-phase turn-based); the view reads it
## to render the player phase and issues commands (move_unit/attack/heal/wait/end_phase).
## When the player ends their phase, the enemy AI plays its whole phase via ai_take_phase.

var engine: SrpgEngine = null
var run_seed: int = 0
var player_auto: bool = false

func _ready() -> void:
	new_battle()

func new_battle(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = SrpgEngine.new()
	engine.setup(run_seed)

## End the human's phase: hand control to the enemy AI, which plays + ends its phase,
## returning control to the player at the start of the next round.
func player_end_phase() -> void:
	if engine == null or engine.game_over:
		return
	if engine.current_team == SrpgEngine.TEAM_PLAYER:
		engine.end_phase()                          # player -> enemy
	if engine.current_team == SrpgEngine.TEAM_ENEMY and not engine.game_over:
		engine.ai_take_phase(SrpgEngine.TEAM_ENEMY) # enemy plays + ends -> back to player

## Full auto: let the macro AI play the player's side too (one phase per call).
func auto_phase() -> void:
	if engine == null or engine.game_over:
		return
	engine.ai_take_phase(engine.current_team)

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "player_auto": player_auto,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	player_auto = bool(d.get("player_auto", false))
	engine = SrpgEngine.new()
	engine.load_data(d.get("engine", {}))
