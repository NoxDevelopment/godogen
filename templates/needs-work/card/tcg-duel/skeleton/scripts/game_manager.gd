extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). The whole card-duel
## engine as pure, headless-testable logic — two players (you = 0, opponent = 1),
## a mana curve, decks/hands/boards, playing creatures + a damage spell, attacking
## face-or-trade, and win detection, plus a greedy AI opponent. The scene (duel.gd)
## only renders + forwards clicks. NoxDev ABI: "game_manager" + "persistent"
## groups, save_data()/load_data(). RNG is seedable so tests are deterministic.

signal changed  ## any state change — the view redraws on this.

## Card catalogue (data-driven). Creatures have atk/hp; the spell has damage.
const CARDS := {
	"recruit": {"name": "Recruit", "cost": 1, "type": "creature", "atk": 1, "hp": 1, "color": Color(0.55, 0.6, 0.65)},
	"archer": {"name": "Archer", "cost": 2, "type": "creature", "atk": 2, "hp": 1, "color": Color(0.45, 0.6, 0.4)},
	"knight": {"name": "Knight", "cost": 3, "type": "creature", "atk": 2, "hp": 3, "color": Color(0.5, 0.55, 0.75)},
	"golem": {"name": "Golem", "cost": 5, "type": "creature", "atk": 4, "hp": 5, "color": Color(0.6, 0.5, 0.4)},
	"bolt": {"name": "Bolt", "cost": 2, "type": "spell", "damage": 3, "color": Color(0.8, 0.5, 0.35)},
}

## A fixed 20-card pool per player (shuffled by the seeded RNG).
const DECK_POOL := [
	"recruit", "recruit", "recruit", "recruit", "recruit",
	"archer", "archer", "archer", "archer",
	"knight", "knight", "knight",
	"golem", "golem", "golem",
	"bolt", "bolt", "bolt", "archer", "knight",
]

const START_LIFE := 20
const MAX_MANA := 10
const HAND_MAX := 7
const OPENING_HAND := 3

var players: Array = []  ## [you, opponent]; each a player dict (see _new_player)
var active := 0          ## whose turn it is
var winner := -1         ## -1 none, 0 you, 1 opponent
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


## Start a fresh duel. Pass a non-zero seed for a deterministic deck order.
func setup(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	players = [_new_player(), _new_player()]
	active = 0
	winner = -1
	for p in players:
		for i in range(OPENING_HAND):
			_draw(p)
	start_turn(0)


func _new_player() -> Dictionary:
	var deck: Array = DECK_POOL.duplicate()
	# Fisher-Yates with the seeded RNG.
	for i in range(deck.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	return {"life": START_LIFE, "mana": 0, "max_mana": 0, "deck": deck, "hand": [], "board": []}


func _draw(p: Dictionary) -> void:
	if p["deck"].is_empty():
		p["life"] -= 1  # fatigue
		return
	var card_id: String = p["deck"].pop_back()
	if p["hand"].size() < HAND_MAX:
		p["hand"].append(card_id)
	# else: burned (hand full)


func start_turn(who: int) -> void:
	active = who
	var p: Dictionary = players[who]
	p["max_mana"] = mini(MAX_MANA, int(p["max_mana"]) + 1)
	p["mana"] = p["max_mana"]
	_draw(p)
	for c in p["board"]:
		c["ready"] = true
	_check_winner()
	changed.emit()


func can_play(who: int, hand_index: int) -> bool:
	if who != active or winner != -1:
		return false
	var p: Dictionary = players[who]
	if hand_index < 0 or hand_index >= p["hand"].size():
		return false
	var card: Dictionary = CARDS[p["hand"][hand_index]]
	return int(p["mana"]) >= int(card["cost"])


## Play a card from hand. target: -1 = enemy face (spell) / n/a (creature);
## >= 0 = enemy board index (spell target). Returns false if illegal.
func play_card(who: int, hand_index: int, target: int = -1) -> bool:
	if not can_play(who, hand_index):
		return false
	var p: Dictionary = players[who]
	var card_id: String = p["hand"][hand_index]
	var card: Dictionary = CARDS[card_id]
	p["mana"] = int(p["mana"]) - int(card["cost"])
	p["hand"].remove_at(hand_index)
	if card["type"] == "creature":
		p["board"].append({"id": card_id, "atk": int(card["atk"]), "hp": int(card["hp"]), "ready": false})
	else:  # spell: bolt
		var foe: Dictionary = players[1 - who]
		if target < 0:
			foe["life"] = int(foe["life"]) - int(card["damage"])
		elif target < foe["board"].size():
			foe["board"][target]["hp"] = int(foe["board"][target]["hp"]) - int(card["damage"])
			_clear_dead(foe)
	_check_winner()
	changed.emit()
	return true


## Attack with a board creature. target: -1 = enemy face; >= 0 = enemy board index.
func attack(who: int, board_index: int, target: int = -1) -> bool:
	if who != active or winner != -1:
		return false
	var p: Dictionary = players[who]
	if board_index < 0 or board_index >= p["board"].size():
		return false
	var attacker: Dictionary = p["board"][board_index]
	if not bool(attacker["ready"]):
		return false
	var foe: Dictionary = players[1 - who]
	if target < 0:
		foe["life"] = int(foe["life"]) - int(attacker["atk"])
	elif target < foe["board"].size():
		var defender: Dictionary = foe["board"][target]
		defender["hp"] = int(defender["hp"]) - int(attacker["atk"])
		attacker["hp"] = int(attacker["hp"]) - int(defender["atk"])
		_clear_dead(foe)
		_clear_dead(p)
	else:
		return false
	attacker["ready"] = false
	_check_winner()
	changed.emit()
	return true


func end_turn() -> void:
	if winner != -1:
		return
	start_turn(1 - active)


func _clear_dead(p: Dictionary) -> void:
	p["board"] = p["board"].filter(func(c): return int(c["hp"]) > 0)


func _check_winner() -> void:
	if winner != -1:
		return
	if int(players[1]["life"]) <= 0:
		winner = 0
	elif int(players[0]["life"]) <= 0:
		winner = 1


## Greedy AI for the opponent (player 1): play the cheapest affordable card while
## it can, then swing all ready creatures at the face, then end the turn.
func ai_take_turn() -> void:
	if active != 1 or winner != -1:
		return
	var p: Dictionary = players[1]
	var guard := 0
	while guard < 20:
		guard += 1
		var best := -1
		var best_cost := 999
		for i in range(p["hand"].size()):
			var card: Dictionary = CARDS[p["hand"][i]]
			if int(card["cost"]) <= int(p["mana"]) and int(card["cost"]) < best_cost:
				best = i
				best_cost = int(card["cost"])
		if best < 0:
			break
		play_card(1, best, -1)  # bolt goes face; creatures ignore target
	# attack face with everything ready (indices shift as none are removed on a face hit)
	for i in range(p["board"].size()):
		if bool(p["board"][i]["ready"]):
			attack(1, i, -1)
		if winner != -1:
			break
	end_turn()


func reset() -> void:
	setup(0)


func save_data() -> Dictionary:
	return {"players": players.duplicate(true), "active": active, "winner": winner}


func load_data(data: Dictionary) -> void:
	if data.has("players"):
		players = (data["players"] as Array).duplicate(true)
	active = int(data.get("active", 0))
	winner = int(data.get("winner", -1))
	changed.emit()
