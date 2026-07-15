extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager") AND the 3D action-
## adventure QUEST + COMBAT state. A Zelda-like dungeon run is a gated chain:
## fight through the room, find the KEY, unlock the DOOR, then beat the BOSS.
## This holds player health + that quest chain as pure, headless-testable logic
## with the ordering rules enforced (you can't open the door without the key, and
## the boss can't be hit until the door is open). The 3D world (player controller,
## camera, enemies) only reads + drives this.
##
## Lives in the "game_manager" + "persistent" groups and implements the
## save_data()/load_data() ABI contract, so godotsmith's save_system persists the
## run — hearts, key, door, boss HP, progress.

signal state_changed  ## hp/key/door/boss/win changed (HUD + world listen)
signal player_died
signal quest_won

const PLAYER_MAX_HP := 6         ## hearts.
const BOSS_MAX_HP := 8

var player_hp := PLAYER_MAX_HP
var has_key := false
var door_open := false
var boss_hp := BOSS_MAX_HP
var boss_defeated := false
var enemies_total := 0
var enemies_defeated := 0
var dead := false
var won := false

var flags: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


# =====================================================================
#  Quest lifecycle
# =====================================================================

func reset_quest(enemy_count: int = 0) -> void:
	player_hp = PLAYER_MAX_HP
	has_key = false
	door_open = false
	boss_hp = BOSS_MAX_HP
	boss_defeated = false
	enemies_total = maxi(enemy_count, 0)
	enemies_defeated = 0
	dead = false
	won = false
	state_changed.emit()


func is_over() -> bool:
	return dead or won


# =====================================================================
#  Combat — player
# =====================================================================

func damage_player(amount: int) -> void:
	if is_over():
		return
	player_hp = maxi(0, player_hp - amount)
	if player_hp == 0:
		dead = true
		player_died.emit()
	state_changed.emit()


func heal_player(amount: int) -> void:
	if is_over():
		return
	player_hp = mini(PLAYER_MAX_HP, player_hp + amount)
	state_changed.emit()


# =====================================================================
#  The gated quest chain: key → door → boss
# =====================================================================

## Pick up the dungeon key.
func collect_key() -> void:
	if is_over():
		return
	has_key = true
	state_changed.emit()


## Try to open the boss door. Succeeds only with the key in hand.
func try_open_door() -> bool:
	if is_over() or door_open or not has_key:
		return false
	door_open = true
	state_changed.emit()
	return true


## An ordinary enemy fell. Tracked for completion / rewards.
func register_enemy_defeated() -> void:
	if is_over():
		return
	enemies_defeated += 1
	state_changed.emit()


## Hit the boss. The boss is behind the door — it can't be damaged until the
## door is open (spatially true in the world; enforced here so the rule is
## testable). Defeating the boss wins the run.
func damage_boss(amount: int) -> bool:
	if is_over() or not door_open or boss_defeated:
		return false
	boss_hp = maxi(0, boss_hp - amount)
	if boss_hp == 0:
		boss_defeated = true
		won = true
		set_flag("dungeons_cleared", int(get_flag("dungeons_cleared", 0)) + 1)
		quest_won.emit()
	state_changed.emit()
	return true


# =====================================================================
#  Flags + persistence
# =====================================================================

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func save_data() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"player_hp": player_hp,
		"has_key": has_key,
		"door_open": door_open,
		"boss_hp": boss_hp,
		"boss_defeated": boss_defeated,
		"enemies_total": enemies_total,
		"enemies_defeated": enemies_defeated,
		"dead": dead,
		"won": won,
	}


func load_data(data: Dictionary) -> void:
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	player_hp = int(data.get("player_hp", PLAYER_MAX_HP))
	has_key = bool(data.get("has_key", false))
	door_open = bool(data.get("door_open", false))
	boss_hp = int(data.get("boss_hp", BOSS_MAX_HP))
	boss_defeated = bool(data.get("boss_defeated", false))
	enemies_total = int(data.get("enemies_total", 0))
	enemies_defeated = int(data.get("enemies_defeated", 0))
	dead = bool(data.get("dead", false))
	won = bool(data.get("won", false))
	state_changed.emit()
