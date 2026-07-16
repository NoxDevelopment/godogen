extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one BrawlerEngine —
## the pure, seedable, deterministic Jade-Empire-lineage martial-arts beat-'em-up +
## campaign RPG — and adds the NoxDev template ABI on top: it lives in the
## "game_manager" + "persistent" groups and implements save_data()/load_data(), so
## godotsmith's save_system persists the WHOLE run (learned styles, technique
## upgrades, attributes/level, campaign progress, the live fight + RNG).
##
## All combat + rules stay in BrawlerEngine; arena.gd only reads state + forwards
## the human's chosen action (attack / block / walk / style-switch / learn) through
## here, and this file emits `changed` so the view redraws. The sim is
## deterministic, so a run replays byte-identically from a seed + its input/AI
## script and the auto-play can demo the whole campaign with no UI.

signal changed  ## any state change — the arena redraws on this.

const DEFAULT_SEED: int = 20260716

var engine: BrawlerEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = BrawlerEngine.new()
	engine.setup(DEFAULT_SEED)


# =====================================================================
#  Run lifecycle
# =====================================================================

## Start a fresh campaign. seed == 0 -> random; any other value is deterministic.
## `config` optionally overrides difficulty (see BrawlerEngine.setup).
func new_run(seed_value: int = 0, config: Dictionary = {}) -> void:
	engine.setup(seed_value, config)
	engine.start_campaign()
	engine.begin_current_encounter("skilled_counter")
	changed.emit()


func is_run_over() -> bool:
	return engine.campaign_over


func is_won() -> bool:
	return engine.is_campaign_won()


# =====================================================================
#  Human input — the arena forwards ONE chosen action through here
# =====================================================================

## Queue the player's (side 0) action for the next combat step.
func player_action(action: Dictionary) -> bool:
	var ok: bool = engine.request_action(0, action)
	changed.emit()
	return ok


## Switch the player's active style mid-fight (the Jade-Empire move). Legal only
## between actions + only among learned styles.
func player_switch_style(style_id: String) -> bool:
	var ok: bool = engine.switch_style(0, style_id)
	changed.emit()
	return ok


## Learn a style / spend a technique point from the learn panel.
func learn_style(style_id: String) -> bool:
	var ok: bool = engine.learn_style(style_id)
	changed.emit()
	return ok


func upgrade_technique(style_id: String) -> bool:
	var ok: bool = engine.upgrade_technique(style_id)
	changed.emit()
	return ok


## Advance the local fight one fixed step under the current inputs. The arena calls
## this on a fixed accumulator; the auto-play demo also uses it. Resolves the
## encounter + advances the campaign when a fight ends. Emits `changed`.
func step() -> void:
	if engine.fighters.size() < 2:
		return
	if not engine.fight_over:
		engine.step()
		if engine.fight_over and not engine.campaign_over:
			engine.resolve_encounter_outcome()
			if not engine.campaign_over:
				engine.begin_current_encounter("skilled_counter")
	changed.emit()


## Fully auto-play the remainder of the campaign (the "Auto Campaign" demo button).
func auto_campaign() -> void:
	engine.run_campaign("skilled_counter")
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
