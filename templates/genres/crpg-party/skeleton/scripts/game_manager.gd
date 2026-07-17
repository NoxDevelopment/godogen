extends Node
## res://scripts/game_manager.gd
## Autoload holding the run's CrpgEngine + the NoxDev save/load ABI. The engine is the
## single source of truth (pure + deterministic). The view drives the PARTY's combat turns
## (act_attack / act_spell / act_defend) and taps continue on events/rests; enemy turns are
## resolved by the engine's AI. Toggle party_auto to hand the party to the AI too.

var engine: CrpgEngine = null
var run_seed: int = 0
var party_auto: bool = false

func _ready() -> void:
	new_game()

func new_game(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system())
	engine = CrpgEngine.new()
	engine.setup(run_seed)

## Run enemy turns (and, if party_auto, party turns) until it is the human's turn to act,
## the combat ends, or the run finishes. Call after each player action + on load.
func resolve_ai_turns() -> void:
	if engine == null:
		return
	var guard := 0
	while not engine.game_over and engine.in_combat and guard < 400:
		guard += 1
		var a := engine.actor_at_ptr()
		if a.is_empty():
			break
		if int(a.side) == 0 and not party_auto:
			return                          # human decides this turn
		if not engine.ai_act(party_auto):
			return

## Advance one non-combat node (event resolved by the best-suited hero, or a rest applied).
func continue_explore() -> void:
	if engine == null or engine.game_over:
		return
	if engine.phase == "event":
		engine.resolve_event(-1)
	resolve_ai_turns()

## One step of full auto (used when party_auto is on).
func auto_step() -> void:
	if engine == null or engine.game_over:
		return
	engine.auto_step("auto")

func save_data() -> Dictionary:
	return {"version": 1, "run_seed": run_seed, "party_auto": party_auto,
		"engine": engine.save_data() if engine else {}}

func load_save(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	party_auto = bool(d.get("party_auto", false))
	engine = CrpgEngine.new()
	engine.load_data(d.get("engine", {}))
