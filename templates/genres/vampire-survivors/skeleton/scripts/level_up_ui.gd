extends CanvasLayer
## res://scripts/level_up_ui.gd
## 3-choice level-up UI. The pool is data-driven: every Upgrade .tres in
## res://resources/upgrades/ is loaded at boot (new upgrades are new files,
## zero code). open() offers 3 distinct random picks and pauses the tree
## (PROCESS_MODE_ALWAYS keeps the UI live); pick via click or the choice_1..3
## actions. choose(i) is the programmatic entry point used by the boot probe.

signal upgrade_chosen(upgrade: Upgrade)

const UPGRADE_DIR := "res://resources/upgrades"
const CHOICE_ACTIONS: Array[StringName] = [&"choice_1", &"choice_2", &"choice_3"]

var _pool: Array[Upgrade] = []
var _offered: Array[Upgrade] = []
var _player: Node = null
var _rng := RandomNumberGenerator.new()

@onready var _buttons: Array[Button] = [
	$Panel/Rows/Choice1, $Panel/Rows/Choice2, $Panel/Rows/Choice3,
]


func _ready() -> void:
	visible = false
	_rng.randomize()
	_pool = _load_pool()
	for i in _buttons.size():
		var index := i
		_buttons[i].pressed.connect(func() -> void: choose(index))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in CHOICE_ACTIONS.size():
		if event.is_action_pressed(CHOICE_ACTIONS[i]):
			get_viewport().set_input_as_handled()
			choose(i)
			return


## Offer 3 distinct upgrades for `player` and pause the run.
func open(player: Node) -> void:
	_player = player
	_offered.clear()
	var candidates := _pool.duplicate()
	while _offered.size() < _buttons.size() and not candidates.is_empty():
		_offered.append(candidates.pop_at(_rng.randi_range(0, candidates.size() - 1)))
	for i in _buttons.size():
		if i < _offered.size():
			_buttons[i].text = "%d)  %s — %s" % [
				i + 1, _offered[i].display_name, _offered[i].description,
			]
			_buttons[i].visible = true
		else:
			_buttons[i].visible = false
	visible = true
	get_tree().paused = true


## Apply offered upgrade `index` to the player, unpause, and return it
## (null if the UI is closed or the index is out of range).
func choose(index: int) -> Upgrade:
	if not visible or index < 0 or index >= _offered.size():
		return null
	var upgrade := _offered[index]
	upgrade.apply_to(_player)
	visible = false
	get_tree().paused = false
	upgrade_chosen.emit(upgrade)
	return upgrade


## Deterministic offers for tests.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func _load_pool() -> Array[Upgrade]:
	var pool: Array[Upgrade] = []
	var dir := DirAccess.open(UPGRADE_DIR)
	if dir == null:
		push_warning("level_up_ui: upgrade directory missing: " + UPGRADE_DIR)
		return pool
	for file in dir.get_files():
		# Exported builds list remapped resources as <file>.tres.remap.
		var res_file := file.trim_suffix(".remap")
		if not res_file.ends_with(".tres"):
			continue
		var upgrade := load(UPGRADE_DIR.path_join(res_file)) as Upgrade
		if upgrade != null:
			pool.append(upgrade)
	return pool
