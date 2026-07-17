class_name AutoBattlerEngine
extends RefCounted
## Pure, seedable AUTO-BATTLER engine (Super Auto Pets / "How Many Dudes" lineage): draft a
## roster of "Dudes" from a rolling GOLD SHOP, build ABILITY + SYNERGY combos, then watch the
## team AUTO-RESOLVE combat (no per-unit input) against ESCALATING enemy waves — win trophies,
## lose lives, and either win the run or run out of lives. Node-free + Time-free: one seeded RNG
## drives the shop + the enemy waves + combat tie-breaks, so a whole run replays BYTE-IDENTICALLY
## from a seed (FNV-1a checksum). The scene (autobattler_view.gd) + GameManager wrap this; all
## rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const TEAM_MAX := 5
const SHOP_SIZE := 5
const START_GOLD := 10
const BUY_COST := 3
const ROLL_COST := 1
const SELL_VALUE := 1
const START_LIVES := 5
const TROPHIES_TO_WIN := 8
const COMBAT_CAP := 300

# unit pool: {kind, atk, hp, tier, tag, ability}
# abilities: "" | "zap"(start: 2 dmg to enemy front) | "rage"(on-hurt +2 atk) |
##            "vengeance"(on-faint: +2/+2 to ally behind) | "mend"(each tick heal weakest ally +2) |
##            "coin"(on-buy: +1 gold)
const POOL := [
	{"kind": "Grunt", "atk": 2, "hp": 3, "tier": 1, "tag": "melee", "ability": ""},
	{"kind": "Scout", "atk": 3, "hp": 1, "tier": 1, "tag": "melee", "ability": ""},
	{"kind": "Wizard", "atk": 2, "hp": 2, "tier": 2, "tag": "magic", "ability": "zap"},
	{"kind": "Brute", "atk": 3, "hp": 4, "tier": 2, "tag": "melee", "ability": "rage"},
	{"kind": "Healer", "atk": 1, "hp": 3, "tier": 2, "tag": "support", "ability": "mend"},
	{"kind": "Martyr", "atk": 2, "hp": 3, "tier": 3, "tag": "support", "ability": "vengeance"},
	{"kind": "Worker", "atk": 1, "hp": 2, "tier": 1, "tag": "support", "ability": "coin"},
	{"kind": "Champion", "atk": 4, "hp": 5, "tier": 3, "tag": "melee", "ability": "rage"},
	{"kind": "Archmage", "atk": 3, "hp": 3, "tier": 3, "tag": "magic", "ability": "zap"},
]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var team: Array = []                ## Array[Dictionary] owned units (front..back)
var shop: Array = []                ## Array[Dictionary] {unit, frozen}
var gold := 0
var round_no := 1
var lives := START_LIVES
var trophies := 0
var phase := "shop"                 ## shop | done
var game_over := false
var won := false
var last_combat := ""               ## "win" | "loss" | "draw"
var log_lines: Array = []
var _next_id := 1

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	team = []
	shop = []
	gold = START_GOLD
	round_no = 1
	lives = START_LIVES
	trophies = 0
	phase = "shop"
	game_over = false
	won = false
	last_combat = ""
	log_lines = []
	_next_id = 1
	_roll_shop(true)

func _new_id() -> int:
	var v := _next_id
	_next_id += 1
	return v

func _make_unit(tpl: Dictionary) -> Dictionary:
	return {"id": _new_id(), "kind": str(tpl.kind), "atk": int(tpl.atk), "hp": int(tpl.hp),
		"max_hp": int(tpl.hp), "tier": int(tpl.tier), "tag": str(tpl.tag), "ability": str(tpl.ability)}

func _shop_tier_cap() -> int:
	return clampi(1 + round_no / 2, 1, 3)

func _roll_shop(free: bool) -> void:
	var cap := _shop_tier_cap()
	var kept: Array = []
	for s in shop:
		if bool(s.frozen):
			kept.append(s)
	shop = kept
	while shop.size() < SHOP_SIZE:
		var pick: Dictionary = POOL[rng.randi_range(0, POOL.size() - 1)]
		if int(pick.tier) > cap:
			continue
		shop.append({"unit": _make_unit(pick), "frozen": false})

# --------------------------------------------------------------------------- #
# Shop actions
# --------------------------------------------------------------------------- #

func roll() -> bool:
	if phase != "shop" or gold < ROLL_COST:
		return false
	gold -= ROLL_COST
	_roll_shop(false)
	return true

func buy(shop_idx: int) -> bool:
	if phase != "shop" or shop_idx < 0 or shop_idx >= shop.size():
		return false
	if gold < BUY_COST or team.size() >= TEAM_MAX:
		return false
	gold -= BUY_COST
	var u: Dictionary = shop[shop_idx].unit
	team.append(u)
	shop.remove_at(shop_idx)
	if str(u.ability) == "coin":
		gold += 1
	_apply_synergies()
	_log("Bought %s" % str(u.kind))
	return true

func sell(team_idx: int) -> bool:
	if phase != "shop" or team_idx < 0 or team_idx >= team.size():
		return false
	gold += SELL_VALUE
	team.remove_at(team_idx)
	_apply_synergies()
	return true

func freeze(shop_idx: int) -> bool:
	if phase != "shop" or shop_idx < 0 or shop_idx >= shop.size():
		return false
	shop[shop_idx].frozen = not bool(shop[shop_idx].frozen)
	return true

func move_unit(from_idx: int, to_idx: int) -> bool:
	if phase != "shop" or from_idx < 0 or from_idx >= team.size() or to_idx < 0 or to_idx >= team.size():
		return false
	var u = team[from_idx]
	team.remove_at(from_idx)
	team.insert(to_idx, u)
	return true

## Synergies recompute a bonus layer on top of base stats (kept simple + deterministic).
func _apply_synergies() -> void:
	var melee := 0
	var magic := 0
	var support := 0
	for u in team:
		match str(u.tag):
			"melee": melee += 1
			"magic": magic += 1
			"support": support += 1
	# reset to base then apply
	for u in team:
		var tpl := _pool_of(str(u.kind))
		u.atk = int(tpl.atk)
		u.max_hp = int(tpl.hp)
		# keep current hp capped to new max later; here shop units are full
		u.hp = int(tpl.hp)
	if melee >= 3:
		for u in team:
			if str(u.tag) == "melee":
				u.atk = int(u.atk) + 2
	if support >= 2:
		for u in team:
			u.max_hp = int(u.max_hp) + 2
			u.hp = int(u.hp) + 2
	# magic synergy is applied at battle time (extra zap damage)

func magic_count() -> int:
	var n := 0
	for u in team:
		if str(u.tag) == "magic":
			n += 1
	return n

func _pool_of(kind: String) -> Dictionary:
	for t in POOL:
		if str(t.kind) == kind:
			return t
	return POOL[0]

# --------------------------------------------------------------------------- #
# Enemy waves (escalating, seeded)
# --------------------------------------------------------------------------- #

func _make_enemy_team() -> Array:
	var out: Array = []
	var count: int = clampi(2 + round_no / 2, 2, TEAM_MAX)
	var cap := _shop_tier_cap()
	var buff: int = round_no / 3           # waves get tougher (gentler curve)
	for i in range(count):
		var pick: Dictionary = POOL[rng.randi_range(0, POOL.size() - 1)]
		if int(pick.tier) > cap:
			pick = POOL[0]
		var u := _make_unit(pick)
		u.atk = int(u.atk) + buff
		u.hp = int(u.hp) + buff
		u.max_hp = int(u.hp)
		out.append(u)
	return out

# --------------------------------------------------------------------------- #
# Combat (deterministic auto-resolve)
# --------------------------------------------------------------------------- #

func _copy_team(src: Array, magic_bonus: int) -> Array:
	var out: Array = []
	for u in src:
		var c: Dictionary = u.duplicate()
		c.hp = int(u.max_hp) if int(u.max_hp) > int(u.hp) else int(u.hp)
		c["mbonus"] = magic_bonus
		out.append(c)
	return out

func simulate(player_team: Array, enemy_team: Array, my_magic: int, foe_magic: int) -> String:
	var a := _copy_team(player_team, 2 if my_magic >= 2 else 0)
	var b := _copy_team(enemy_team, 2 if foe_magic >= 2 else 0)
	_start_of_battle(a, b)
	_start_of_battle(b, a)
	_clear_fainted(a, b)
	_clear_fainted(b, a)
	var guard := 0
	while a.size() > 0 and b.size() > 0 and guard < COMBAT_CAP:
		guard += 1
		var fa: Dictionary = a[0]
		var fb: Dictionary = b[0]
		var da := int(fa.atk)
		var db := int(fb.atk)
		fb.hp = int(fb.hp) - da
		fa.hp = int(fa.hp) - db
		_on_hurt(fa)
		_on_hurt(fb)
		_tick_mend(a)
		_tick_mend(b)
		_clear_fainted(a, b)
		_clear_fainted(b, a)
	if a.size() > 0 and b.size() == 0:
		return "win"
	if b.size() > 0 and a.size() == 0:
		return "loss"
	return "draw"

func _start_of_battle(side: Array, foe: Array) -> void:
	for u in side:
		if str(u.ability) == "zap" and foe.size() > 0:
			var dmg := 2 + int(u.get("mbonus", 0))
			foe[0].hp = int(foe[0].hp) - dmg

func _on_hurt(u: Dictionary) -> void:
	if int(u.hp) > 0 and str(u.ability) == "rage":
		u.atk = int(u.atk) + 2

func _tick_mend(side: Array) -> void:
	var healer := false
	for u in side:
		if str(u.ability) == "mend" and int(u.hp) > 0:
			healer = true
			break
	if not healer:
		return
	# heal the lowest-hp living ally by 2 (not above max)
	var target := {}
	var lo := 1 << 30
	for u in side:
		if int(u.hp) > 0 and int(u.hp) < lo:
			lo = int(u.hp)
			target = u
	if not target.is_empty():
		target.hp = min(int(target.max_hp), int(target.hp) + 2)

func _clear_fainted(side: Array, foe: Array) -> void:
	var alive: Array = []
	for i in range(side.size()):
		var u: Dictionary = side[i]
		if int(u.hp) > 0:
			alive.append(u)
		else:
			# vengeance: buff the ally behind
			if str(u.ability) == "vengeance" and i + 1 < side.size():
				side[i + 1].atk = int(side[i + 1].atk) + 2
				side[i + 1].hp = int(side[i + 1].hp) + 2
				side[i + 1].max_hp = int(side[i + 1].max_hp) + 2
	# rebuild the side in place
	side.clear()
	for u in alive:
		side.append(u)

# --------------------------------------------------------------------------- #
# Round flow
# --------------------------------------------------------------------------- #

func end_shop() -> void:
	if phase != "shop" or game_over:
		return
	var foe := _make_enemy_team()
	var foe_magic := 0
	for u in foe:
		if str(u.tag) == "magic":
			foe_magic += 1
	last_combat = simulate(team, foe, magic_count(), foe_magic)
	if last_combat == "win":
		trophies += 1
		_log("Round %d: WIN (%d trophies)" % [round_no, trophies])
	elif last_combat == "loss":
		lives -= 1
		_log("Round %d: LOSS (%d lives left)" % [round_no, lives])
	else:
		_log("Round %d: draw" % round_no)
	# end conditions
	if trophies >= TROPHIES_TO_WIN:
		_finish(true)
		return
	if lives <= 0:
		_finish(false)
		return
	# next shop
	round_no += 1
	gold = START_GOLD
	# heal team back to full for the next shop (SAP-style)
	for u in team:
		u.hp = int(u.max_hp)
	_roll_shop(false)

func _finish(victory: bool) -> void:
	game_over = true
	won = victory
	phase = "done"
	_log("Run over: %s (round %d, %d trophies)" % [("VICTORY!" if victory else "out of lives"), round_no, trophies])

# --------------------------------------------------------------------------- #
# Heuristic shop AI (probe / demo) — build the strongest affordable board
# --------------------------------------------------------------------------- #

func _unit_value(u: Dictionary) -> int:
	return int(u.atk) + int(u.hp) + (2 if str(u.ability) != "" else 0)

func ai_shop_turn() -> void:
	if phase != "shop" or game_over:
		return
	# buy the best affordable shop units until full or broke
	var guard := 0
	while gold >= BUY_COST and team.size() < TEAM_MAX and guard < 20:
		guard += 1
		var best := -1
		var bv := -1
		for i in range(shop.size()):
			var v := _unit_value(shop[i].unit)
			if v > bv:
				bv = v
				best = i
		if best < 0:
			break
		buy(best)
	# if the board is full but we still have gold, replace the weakest with a stronger shop unit
	if team.size() >= TEAM_MAX and gold >= BUY_COST:
		var weak := 0
		var wv := 1 << 30
		for i in range(team.size()):
			var v := _unit_value(team[i])
			if v < wv:
				wv = v
				weak = i
		var bestshop := -1
		var bsv := -1
		for i in range(shop.size()):
			var v := _unit_value(shop[i].unit)
			if v > bsv:
				bsv = v
				bestshop = i
		if bestshop >= 0 and bsv > wv + 1:
			sell(weak)
			buy(bestshop)
	# roll once if we have spare gold and room/upgrades to find
	if gold >= BUY_COST + ROLL_COST and team.size() < TEAM_MAX:
		roll()
		ai_shop_turn()
		return

func auto_step() -> void:
	if game_over:
		return
	ai_shop_turn()
	end_shop()

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < 200:
		auto_step()
		guard += 1
	if not game_over:
		_finish(won)

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 40:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d|%s|%s" % [round_no, gold, lives, trophies, int(game_over), int(won), phase, last_combat]
	for u in team:
		s += "|T%s,%d,%d" % [str(u.kind), int(u.atk), int(u.hp)]
	for sh in shop:
		s += "|S%s,%d" % [str(sh.unit.kind), int(sh.frozen)]
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "team": team.duplicate(true), "shop": shop.duplicate(true), "gold": gold,
		"round_no": round_no, "lives": lives, "trophies": trophies, "phase": phase,
		"game_over": game_over, "won": won, "last_combat": last_combat, "next_id": _next_id,
		"seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	team = (d.get("team", []) as Array).duplicate(true)
	shop = (d.get("shop", []) as Array).duplicate(true)
	gold = int(d.get("gold", 0))
	round_no = int(d.get("round_no", 1))
	lives = int(d.get("lives", START_LIVES))
	trophies = int(d.get("trophies", 0))
	phase = str(d.get("phase", "shop"))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	last_combat = str(d.get("last_combat", ""))
	_next_id = int(d.get("next_id", 1))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
