extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one EuroEngine —
## the pure, seedable Euro engine-builder rules — and adds the NoxDev template
## ABI on top: it lives in the "game_manager" + "persistent" groups and implements
## save_data()/load_data(), so godotsmith's save_system persists the WHOLE game
## (every player's bank, tableau, hand, stars, the shared deck, objectives and the
## turn cursor) with no extra wiring. board.gd only reads this and forwards the
## human's chosen action; all rules stay in EuroEngine.

signal changed  ## any state change — the board redraws on this.

const HUMAN := 0  ## the human always plays seat 0 in the UI.

var engine: EuroEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = EuroEngine.new()


## Start a fresh game. Pass a non-zero seed for a deterministic showcase / tests.
func new_game(seed_value: int = 0, player_count: int = 4) -> void:
	engine.setup(seed_value, player_count)
	changed.emit()


func reset() -> void:
	new_game(0, engine.num_players if engine != null else 4)


# =====================================================================
#  Human turn (seat 0) — apply one legal action, then auto-run the AIs
# =====================================================================

## The human takes their single action for the round. If it is legal it is
## applied, the turn advances, and every AI seat resolves its turn until control
## returns to the human (or the game ends). Returns false if the action was
## illegal (the board leaves the seat with the human).
func human_action(action: Dictionary) -> bool:
	if engine.game_over or engine.current != HUMAN:
		return false
	if not engine.apply_action(HUMAN, action):
		return false
	engine.advance_turn()
	_run_ai_seats()
	changed.emit()
	return true


func _run_ai_seats() -> void:
	var guard := 0
	while not engine.game_over and engine.current != HUMAN and guard < 512:
		engine.ai_take_turn(engine.current)
		engine.advance_turn()
		guard += 1


func is_human_turn() -> bool:
	return not engine.game_over and engine.current == HUMAN


# =====================================================================
#  Persistence — the WHOLE game round-trips through save_system
# =====================================================================

func save_data() -> Dictionary:
	return {"engine": engine.to_dict()}


func load_data(data: Dictionary) -> void:
	if data.has("engine"):
		engine.from_dict(data["engine"] as Dictionary)
	changed.emit()
