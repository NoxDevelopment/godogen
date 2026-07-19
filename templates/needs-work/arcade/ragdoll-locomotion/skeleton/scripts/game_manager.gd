extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one RagdollEngine
## — the pure, seedable, deterministic articulated-body QWOP-locomotion sim — and
## adds the NoxDev template ABI on top: it lives in the "game_manager" +
## "persistent" groups and implements save_data()/load_data(), so godotsmith's
## save_system persists the WHOLE run (the full body state, muscle inputs,
## progress, difficulty + RNG).
##
## All physics + rules stay in RagdollEngine; track.gd only reads state + forwards
## the human's per-frame muscle inputs through here, and this file emits `changed`
## so the view redraws. The sim is deterministic, so a run replays byte-identically
## from a seed + its input history and the scripted policies demo a whole run with
## no UI.

signal changed  ## any state change — the track redraws on this.

const DEFAULT_SEED: int = 20260716

var engine: RagdollEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = RagdollEngine.new()
	engine.setup(DEFAULT_SEED)


# =====================================================================
#  Run lifecycle
# =====================================================================

## Start a fresh run. seed == 0 -> random; any other value is deterministic.
## `config` optionally overrides difficulty (see RagdollEngine.setup).
func new_run(seed_value: int = 0, config: Dictionary = {}) -> void:
	engine.setup(seed_value, config)
	changed.emit()


func is_run_over() -> bool:
	return engine.finished


func is_won() -> bool:
	return engine.is_won()


# =====================================================================
#  Human input — the track forwards per-frame muscle state through here
# =====================================================================

## Engage / release a muscle group (0..3 = Q/W/O/P).
func set_muscle(index: int, on: bool) -> bool:
	return engine.set_muscle(index, on)


## Advance the local sim one fixed step under the current muscle inputs. Offline
## the track calls this on a fixed accumulator; online each peer steps its OWN
## athlete. Emits `changed`.
func step() -> void:
	engine.step()
	changed.emit()


# =====================================================================
#  Persistence — the WHOLE run round-trips through save_system
# =====================================================================

func save_data() -> Dictionary:
	return {"engine": engine.to_dict()}


func load_data(data: Dictionary) -> void:
	if data.has("engine"):
		engine.from_dict(data["engine"] as Dictionary)
	changed.emit()
