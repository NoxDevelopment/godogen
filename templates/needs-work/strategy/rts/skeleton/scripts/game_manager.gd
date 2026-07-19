extends Node
## res://scripts/game_manager.gd
## Autoload holding the match's RtsEngine + the NoxDev save/load ABI. The engine is the
## single source of truth (pure + deterministic, fixed-timestep lockstep); the view reads
## it to render and issues commands (cmd_move/cmd_gather/cmd_train/...) on input. The AI
## opponent is driven by engine.ai_take_turn(OWNER_AI); the player may hand-drive OWNER_PLAYER
## or hand control to engine.ai_take_turn(OWNER_PLAYER) for a full auto-demo.

var engine: RtsEngine = null
var run_seed: int = 0
var player_auto: bool = false          ## true = let the macro AI also drive the player

func _ready() -> void:
	new_match()

func new_match(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = RtsEngine.new()
	engine.setup(run_seed)

## Advance one fixed sim tick. The AI opponent re-plans on the engine's AI cadence; the
## player side re-plans too only when player_auto is on (otherwise the view issues its
## commands). Call this from _physics_process for a real-time feel.
func advance() -> void:
	if engine == null or engine.game_over:
		return
	if engine.tick % RtsEngine.AI_TICK == 0:
		engine.ai_take_turn(RtsEngine.OWNER_AI)
		if player_auto:
			engine.ai_take_turn(RtsEngine.OWNER_PLAYER)
	engine.step()

# NoxDev ABI — the whole match is one blob (deterministic replay from seed + commands,
# or the full snapshot here for a mid-match save).
func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "player_auto": player_auto,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	player_auto = bool(d.get("player_auto", false))
	engine = RtsEngine.new()
	engine.load_data(d.get("engine", {}))
