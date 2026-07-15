extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager") AND the GACHA engine —
## the summon/collection core of a companion-collection game. A pull spends
## premium currency, rolls a rarity against published rates WITH a pity system
## (a guaranteed high rarity if you go dry), draws a character/item from that
## rarity's pool, and banks it (dupes tracked). All of it is pure, seedable,
## headless-testable logic; the summon screen only reads this and forwards pulls.
##
## Lives in the "game_manager" + "persistent" groups and implements the
## save_data()/load_data() ABI contract, so godotsmith's save_system persists the
## wallet + pity + the whole collection.

signal gacha_changed  ## a pull resolved / gems changed (the view rebuilds)

# --- economy + rates -------------------------------------------------------
const PULL_COST := 160          ## gems per single pull.
const START_GEMS := 1600        ## enough for a 10-pull to start.

const BASE_5 := 0.006           ## 0.6% base 5★ (published-rate realism).
const BASE_4 := 0.051           ## 5.1% base 4★.
const SOFT_PITY_5 := 74         ## 5★ rate ramps hard from here…
const SOFT_RAMP := 0.06         ## …by +6% per pull past soft pity…
const HARD_PITY_5 := 90         ## …and is guaranteed here.
const PITY_4 := 10              ## a 4★ (or better) at least every 10 pulls.

## Rarity → the pool it draws from. Swap these to your own roster (5★ = the
## marquee companions, 4★ = the supporting cast, 3★ = fodder/materials).
const POOL := {
	5: ["Aurora", "Seraphina"],
	4: ["Mika", "Lena", "Yuki"],
	3: ["Training Doll", "Basic Charm", "Common Gift"],
}

# --- state -----------------------------------------------------------------
var gems := START_GEMS
var pity_5 := 0                 ## pulls since the last 5★.
var pity_4 := 0                 ## pulls since the last 4★+.
var total_pulls := 0
var owned: Dictionary = {}      ## item name -> count (dupes tracked).

var flags: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


# =====================================================================
#  Lifecycle
# =====================================================================

## Reset the account. seed == 0 → random; any other value is deterministic.
func new_account(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	gems = START_GEMS
	pity_5 = 0
	pity_4 = 0
	total_pulls = 0
	owned = {}
	gacha_changed.emit()


func add_gems(amount: int) -> void:
	gems = maxi(0, gems + amount)
	gacha_changed.emit()


func can_pull(count: int = 1) -> bool:
	return gems >= PULL_COST * count


## The current 5★ chance for the NEXT pull (base + soft-pity ramp, 1.0 at hard
## pity) — the summon screen shows it so the pity is legible.
func current_five_chance() -> float:
	var five := BASE_5
	if pity_5 + 1 >= SOFT_PITY_5:
		five += (pity_5 + 1 - SOFT_PITY_5 + 1) * SOFT_RAMP
	if pity_5 + 1 >= HARD_PITY_5:
		return 1.0
	return clampf(five, 0.0, 1.0)


# =====================================================================
#  Pulling
# =====================================================================

## Pull `count` times (a 1-pull or a 10-pull). Spends gems per pull; stops early
## if the wallet runs dry. Returns one result dict per pull:
## {rarity, item, dupe, pity5_at} — dupe = you already owned that item.
func pull(count: int) -> Array:
	var results: Array = []
	for i in count:
		if gems < PULL_COST:
			break
		gems -= PULL_COST
		total_pulls += 1
		var rarity := _roll_rarity()
		var item := _pick(rarity)
		var dupe := int(owned.get(item, 0)) > 0
		owned[item] = int(owned.get(item, 0)) + 1
		results.append({"rarity": rarity, "item": item, "dupe": dupe, "pity5_at": pity_5})
	if not results.is_empty():
		gacha_changed.emit()
	return results


## Roll a rarity with pity. A 5★ resets both counters; a 4★ resets the 4★
## counter. Guarantees: 5★ by HARD_PITY_5, a 4★+ every PITY_4.
func _roll_rarity() -> int:
	pity_5 += 1
	pity_4 += 1
	var five := BASE_5
	if pity_5 >= SOFT_PITY_5:
		five += (pity_5 - SOFT_PITY_5 + 1) * SOFT_RAMP
	if pity_5 >= HARD_PITY_5:
		five = 1.0
	var r := _rng.randf()
	if r < five:
		pity_5 = 0
		pity_4 = 0
		return 5
	if pity_4 >= PITY_4 or r < five + BASE_4:
		pity_4 = 0
		return 4
	return 3


func _pick(rarity: int) -> String:
	var list: Array = POOL[rarity]
	return String(list[_rng.randi() % list.size()])


# =====================================================================
#  Collection queries (for the roster screen)
# =====================================================================

func count_of(item: String) -> int:
	return int(owned.get(item, 0))


func unique_owned() -> int:
	return owned.size()


func owned_of_rarity(rarity: int) -> Array[String]:
	var out: Array[String] = []
	for item in POOL.get(rarity, []):
		if owned.has(item):
			out.append(String(item))
	return out


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
		"gems": gems,
		"pity_5": pity_5,
		"pity_4": pity_4,
		"total_pulls": total_pulls,
		"owned": owned.duplicate(true),
	}


func load_data(data: Dictionary) -> void:
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	gems = int(data.get("gems", START_GEMS))
	pity_5 = int(data.get("pity_5", 0))
	pity_4 = int(data.get("pity_4", 0))
	total_pulls = int(data.get("total_pulls", 0))
	owned = {}
	for k in (data.get("owned", {}) as Dictionary).keys():
		owned[String(k)] = int(data["owned"][k])
	gacha_changed.emit()
