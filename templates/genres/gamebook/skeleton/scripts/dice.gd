extends Node
## res://scripts/dice.gd
## Dice layer (autoload "Dice"): Fighting-Fantasy-style 2d6 roll-UNDER tests
## against the adventure sheet — roll 2d6, succeed on total <= stat. Testing
## your luck also spends a point of LUCK afterwards, win or lose. The popup
## flow is awaited as a Dialogue Manager mutation:
##
##     do Dice.test("skill")
##     if Dice.last_success
##         => passage_7
##
##     do Dice.test_luck()
##
## (Same architecture as the visual-novel template's SkillCheck, re-rules'd
## from d20+modifier-vs-DC to the gamebook 2d6 roll-under.)

signal test_started(stat: String, target: int)
signal test_finished(result: Dictionary)

const DICE_POPUP_SCENE := preload("res://scenes/dice_roll_popup.tscn")

## Result of the most recent test (see roll_test() for the shape).
var last_result: Dictionary = {}
## Convenience for dialogue conditions: `if Dice.last_success`.
var last_success := false

var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(&"persistent")
	_rng.randomize()


## Deterministic rolls for tests/replays.
func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


## Pure dice logic — no UI. Gamebook rules: 2d6 <= stat succeeds; double 1s
## always succeed, double 6s always fail.
func roll_test(stat: String) -> Dictionary:
	var target := Sheet.get_stat(stat)
	var die_a := _rng.randi_range(1, 6)
	var die_b := _rng.randi_range(1, 6)
	var total := die_a + die_b
	var crit_success := die_a == 1 and die_b == 1
	var crit_fail := die_a == 6 and die_b == 6
	var success := crit_success or (not crit_fail and total <= target)
	var result := {
		"stat": stat,
		"target": target,
		"die_a": die_a,
		"die_b": die_b,
		"total": total,
		"success": success,
		"crit_success": crit_success,
		"crit_fail": crit_fail,
	}
	last_result = result
	last_success = success
	return result


## The full test flow: roll, show the popup, wait for the player to confirm.
## Await-able; returns the success bool so it also works as
## `set ok = Dice.test(...)` in dialogue.
func test(stat: String) -> bool:
	var result := roll_test(stat)
	test_started.emit(stat, result.target)
	var popup := DICE_POPUP_SCENE.instantiate()
	get_tree().root.add_child(popup)
	await popup.run(result)
	popup.queue_free()
	test_finished.emit(result)
	return result.success


## Test your luck: 2d6 <= LUCK, then LUCK drops by 1 regardless of outcome.
func test_luck() -> bool:
	var ok: bool = await test("luck")
	Sheet.spend_luck()
	return ok


## "persistent" group contract (see templates ABI).
func save_data() -> Dictionary:
	return {
		"last_result": last_result.duplicate(true),
		"last_success": last_success,
	}


func load_data(data: Dictionary) -> void:
	last_result = data.get("last_result", {}).duplicate(true)
	last_success = bool(data.get("last_success", false))
