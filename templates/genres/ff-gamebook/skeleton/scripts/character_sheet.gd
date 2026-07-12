extends Node
## res://scripts/character_sheet.gd
## The adventure sheet (autoload "Sheet"): Fighting-Fantasy-style stats —
## SKILL (1d6+6), STAMINA (2d6+12), LUCK (1d6+6) — plus provisions and an
## inventory LIST, exactly what a solo pen-and-paper gamebook tracks in its
## front cover. Dialogue mutates it directly:
##
##     do Sheet.add_item("brass key")
##     if Sheet.has_item("brass key")
##     do Sheet.take_damage(2)
##
## Dice tests against these stats live in dice.gd (autoload "Dice") and are
## routed through SessionState.roll() (see session_state.gd).

signal stats_changed
signal inventory_changed(items: Array)
signal died

var skill := 9
var stamina := 19
var luck := 9
var max_skill := 9
var max_stamina := 19
var max_luck := 9
var provisions := 4
var inventory: Array[String] = []

var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(&"persistent")
	_rng.randomize()


## Deterministic sheets for tests/replays.
func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


## Roll a fresh adventurer: SKILL 1d6+6, STAMINA 2d6+12, LUCK 1d6+6 (the
## classic gamebook creation rules). Clears the inventory.
func roll_new_character() -> void:
	max_skill = _rng.randi_range(1, 6) + 6
	max_stamina = _rng.randi_range(1, 6) + _rng.randi_range(1, 6) + 12
	max_luck = _rng.randi_range(1, 6) + 6
	skill = max_skill
	stamina = max_stamina
	luck = max_luck
	provisions = 4
	inventory.clear()
	stats_changed.emit()
	inventory_changed.emit(inventory)


func get_stat(stat: String) -> int:
	match stat.to_lower():
		"skill": return skill
		"stamina": return stamina
		"luck": return luck
		_:
			push_warning("Sheet: unknown stat '%s'" % stat)
			return 0


func take_damage(amount: int) -> void:
	stamina = maxi(stamina - amount, 0)
	stats_changed.emit()
	if stamina <= 0:
		died.emit()


func heal(amount: int) -> void:
	stamina = mini(stamina + amount, max_stamina)
	stats_changed.emit()


## Eat one provision: +4 STAMINA (gamebook standard).
func eat_provision() -> bool:
	if provisions <= 0:
		return false
	provisions -= 1
	heal(4)
	return true


## Spend a point of LUCK (dice.gd calls this after every luck test — testing
## your luck always erodes it, win or lose).
func spend_luck() -> void:
	luck = maxi(luck - 1, 0)
	stats_changed.emit()


func add_item(item: String) -> void:
	inventory.append(item)
	inventory_changed.emit(inventory)


func has_item(item: String) -> bool:
	return item in inventory


func remove_item(item: String) -> bool:
	var index := inventory.find(item)
	if index < 0:
		return false
	inventory.remove_at(index)
	inventory_changed.emit(inventory)
	return true


## "persistent" group contract (see templates ABI).
func save_data() -> Dictionary:
	return {
		"skill": skill, "stamina": stamina, "luck": luck,
		"max_skill": max_skill, "max_stamina": max_stamina, "max_luck": max_luck,
		"provisions": provisions,
		"inventory": inventory.duplicate(),
	}


func load_data(data: Dictionary) -> void:
	skill = int(data.get("skill", skill))
	stamina = int(data.get("stamina", stamina))
	luck = int(data.get("luck", luck))
	max_skill = int(data.get("max_skill", max_skill))
	max_stamina = int(data.get("max_stamina", max_stamina))
	max_luck = int(data.get("max_luck", max_luck))
	provisions = int(data.get("provisions", provisions))
	inventory.assign(data.get("inventory", []))
	stats_changed.emit()
	inventory_changed.emit(inventory)
