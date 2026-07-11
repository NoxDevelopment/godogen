extends Node
## res://scripts/skill_check.gd
## Dice layer (autoload "SkillCheck"): d20 + stat modifier vs a difficulty
## class, with crit rules, a seedable RNG, and a UI flow that shows the
## dice-roll popup. Designed to be called from Dialogue Manager mutations:
##
##     do SkillCheck.skill_check("mind", 12)
##     if SkillCheck.last_success
##         => cracked_it
##
## `skill_check()` is a coroutine — Dialogue Manager awaits it, so the story
## pauses on the popup until the player rolls and confirms.

signal check_started(stat: String, dc: int)
signal check_finished(result: Dictionary)

const DICE_POPUP_SCENE := preload("res://scenes/dice_roll_popup.tscn")

## The character sheet: stat name -> modifier. Extend freely; dialogue refers
## to stats by name, so new stats need no code changes.
var stats: Dictionary = {
	"body": 1,
	"mind": 2,
	"finesse": 1,
	"presence": 0,
}

## Result of the most recent check (see roll() for the shape).
var last_result: Dictionary = {}
## Convenience for dialogue conditions: `if SkillCheck.last_success`.
var last_success := false

var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(&"persistent")
	_rng.randomize()


## Deterministic rolls for tests/replays.
func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


## Pure dice logic — no UI. Rules: d20 + modifier >= dc succeeds;
## a natural 1 always fails, a natural 20 always succeeds.
func roll(stat: String, dc: int) -> Dictionary:
	var die := _rng.randi_range(1, 20)
	var modifier := int(stats.get(stat, 0))
	var total := die + modifier
	var crit_fail := die == 1
	var crit_success := die == 20
	var success := crit_success or (not crit_fail and total >= dc)
	var result := {
		"stat": stat,
		"dc": dc,
		"die": die,
		"modifier": modifier,
		"total": total,
		"success": success,
		"crit_success": crit_success,
		"crit_fail": crit_fail,
	}
	last_result = result
	last_success = success
	return result


## The full check flow: roll, show the popup, wait for the player to confirm.
## Await-able; returns the success bool so it also works as
## `set ok = SkillCheck.skill_check(...)` in dialogue.
func skill_check(stat: String, dc: int) -> bool:
	var result := roll(stat, dc)
	check_started.emit(stat, dc)
	var popup := DICE_POPUP_SCENE.instantiate()
	get_tree().root.add_child(popup)
	await popup.run(stat, dc, result)
	popup.queue_free()
	check_finished.emit(result)
	return result.success


## "persistent" group contract (see templates ABI): the character sheet and
## the last outcome survive saves.
func save_data() -> Dictionary:
	return {
		"stats": stats.duplicate(true),
		"last_result": last_result.duplicate(true),
		"last_success": last_success,
	}


func load_data(data: Dictionary) -> void:
	stats = data.get("stats", stats).duplicate(true)
	last_result = data.get("last_result", {}).duplicate(true)
	last_success = bool(data.get("last_success", false))
