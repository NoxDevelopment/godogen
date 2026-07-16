extends RefCounted
class_name EuroEngine
## res://scripts/euro_engine.gd
## The PURE, seedable, headless-testable engine for a competitive Euro-style
## ENGINE-BUILDER board game (Scythe / Wingspan / Wyrmspan lineage): every player
## grows a resource -> production -> victory-point engine, and the best engine
## wins. There is NO Godot node dependency in here — it is plain data + rules,
## so the whole game replays byte-identically from a seed and can be driven with
## no UI at all. GameManager owns one instance and adds the autoload ABI + save;
## board.gd only reads state and forwards a human's chosen action.
##
## The model (why it is a real engine-builder, not an abstraction):
##   * 5 tracked RESOURCES (wood, grain, metal, coin, energy) with a strict
##     conservation ledger — every unit is produced or spent by a named effect;
##     nothing appears or vanishes otherwise (verify_conservation()).
##   * A 25-card development DECK. Each card has a resource COST, a per-PRODUCE
##     OUTPUT, a category, and a VP value. Building a card grows your production.
##   * A shared ACTION board of 5 action types (PRODUCE / BUILD / TRADE /
##     RESEARCH / DEPLOY). On a turn a player takes exactly ONE legal action.
##   * Objective tokens (3 distinct types) claimed first-come during play, plus
##     end-game majorities, plus VP from built cards and goal-stars.
##   * A non-LLM heuristic AI that enumerates every legal action, scores each by a
##     weighted evaluation (immediate VP + resource-efficiency + engine growth +
##     progress-to-goal), and takes the best (deterministic index tie-break).

# =====================================================================
#  Static rules / tuning (auditable constants — swap for your own game)
# =====================================================================

const RESOURCES: Array[String] = ["wood", "grain", "metal", "coin", "energy"]

## Relative worth of each resource — drives trade math AND the AI's evaluation.
## Metal / energy are scarcer (gate DEPLOY); coin is the flexible sink.
const RESOURCE_VALUE := {
	"wood": 1.0, "grain": 1.0, "metal": 1.6, "coin": 1.3, "energy": 1.5,
}

## Starting bank + starting hand size + hand cap.
const START_RESOURCES := {"wood": 3, "grain": 3, "metal": 2, "coin": 4, "energy": 2}
const OPENING_HAND := 4
const HAND_MAX := 8

## PRODUCE always yields this base income on top of every built card's output —
## the "starting engine" so a fresh player is never fully stuck.
const BASE_PRODUCTION := {"wood": 1, "grain": 1, "energy": 1}

## RESEARCH draws this many cards for this cost. TRADE is a fixed 2:1 conversion.
const RESEARCH_DRAW := 2
const RESEARCH_COST := {"coin": 1}
const TRADE_IN := 2   ## give 2 of a resource…
const TRADE_OUT := 1  ## …get 1 of another.

## DEPLOY: spend this bundle to plant one goal-star (drives the end trigger).
const DEPLOY_COST := {"metal": 2, "energy": 2, "coin": 1}

## Scoring weights.
const STAR_VP := 3          ## VP per planted goal-star at final scoring.
const GOAL_STARS := 6       ## first player to reach this ends the game…
const MAX_ROUNDS := 18      ## …else the game ends after this many full rounds.
const MAJ_STARS_VP := 4     ## end-game majority: most stars.
const MAJ_CARDS_VP := 3     ## end-game majority: most cards built.
const MAJ_COIN_VP := 3      ## end-game majority: most coin banked (most-of-a-resource).

## Objective tokens — 3 distinct types, each claimed by the FIRST player to meet
## it (one-time), worth OBJ_VP. Types: N-cards-of-a-category, first-to-star-goal,
## first-to-resource-threshold (a most-of-a-resource race).
const OBJ_VP := 5
const OBJ_INDUSTRIALIST_CATEGORY := "mining"
const OBJ_INDUSTRIALIST_COUNT := 3      ## build 3 mining cards.
const OBJ_SELF_SUFFICIENT_STARS := 3    ## reach 3 stars.
const OBJ_TRADE_BARON_COIN := 12        ## bank 12 coin at once.

## The AI evaluation weights (the heuristic's "brain" — see ai_choose()).
const W_VP := 10.0        ## immediate victory points are king.
const W_ENGINE := 6.0     ## value of new per-turn production (engine growth).
const W_COST := 2.5       ## resource-efficiency: pay less, score higher.
const W_PRODUCE := 1.15   ## banking this turn's production.
const W_DEPLOY := 8.0     ## flat pull toward planting stars…
const W_GOAL := 22.0      ## …scaled up hard as a player nears the star goal.
const W_TRADE := 1.4      ## net value of a conversion (usually a small sink).
const W_TRADE_NEED := 4.0 ## bonus when a trade fills a gap for a wanted build/deploy.
const W_RESEARCH := 3.0   ## option value per missing hand card.
const AI_TARGET_HAND := 4 ## the AI likes to keep this many cards in hand.

## The 25-card development pool. category is used by objectives + AI synergy.
## cost / output are resource dictionaries; vp is the built card's score.
const CARD_DB := {
	# --- forestry (wood) ---------------------------------------------------
	"woodcutter_camp": {"name": "Woodcutter Camp", "category": "forestry", "cost": {"coin": 1}, "output": {"wood": 2}, "vp": 0},
	"sawmill":         {"name": "Sawmill", "category": "forestry", "cost": {"wood": 2, "coin": 1}, "output": {"wood": 1, "coin": 1}, "vp": 1},
	"logging_road":    {"name": "Logging Road", "category": "forestry", "cost": {"wood": 3}, "output": {"wood": 3}, "vp": 1},
	"tree_farm":       {"name": "Tree Farm", "category": "forestry", "cost": {"grain": 2, "coin": 1}, "output": {"wood": 2, "grain": 1}, "vp": 2},
	"lumber_mill":     {"name": "Lumber Mill", "category": "forestry", "cost": {"wood": 4, "metal": 1}, "output": {"wood": 2, "coin": 2}, "vp": 3},
	# --- farm (grain) ------------------------------------------------------
	"wheat_field":     {"name": "Wheat Field", "category": "farm", "cost": {"coin": 1}, "output": {"grain": 2}, "vp": 0},
	"granary":         {"name": "Granary", "category": "farm", "cost": {"grain": 2, "wood": 1}, "output": {"grain": 3}, "vp": 1},
	"orchard":         {"name": "Orchard", "category": "farm", "cost": {"grain": 3}, "output": {"grain": 2, "coin": 1}, "vp": 2},
	"irrigation":      {"name": "Irrigation", "category": "farm", "cost": {"wood": 2, "energy": 1}, "output": {"grain": 3}, "vp": 2},
	"mill_house":      {"name": "Mill House", "category": "farm", "cost": {"grain": 2, "metal": 1}, "output": {"grain": 2, "coin": 2}, "vp": 3},
	# --- mining (metal) ----------------------------------------------------
	"quarry":          {"name": "Quarry", "category": "mining", "cost": {"wood": 2}, "output": {"metal": 2}, "vp": 1},
	"iron_mine":       {"name": "Iron Mine", "category": "mining", "cost": {"wood": 2, "coin": 2}, "output": {"metal": 2}, "vp": 2},
	"smelter":         {"name": "Smelter", "category": "mining", "cost": {"metal": 2, "energy": 1}, "output": {"metal": 2, "coin": 1}, "vp": 3},
	"deep_mine":       {"name": "Deep Mine", "category": "mining", "cost": {"metal": 2, "energy": 2}, "output": {"metal": 3}, "vp": 3},
	"forge":           {"name": "Forge", "category": "mining", "cost": {"metal": 3, "coin": 1}, "output": {"metal": 1, "coin": 3}, "vp": 4},
	# --- energy ------------------------------------------------------------
	"windmill":        {"name": "Windmill", "category": "energy", "cost": {"wood": 2, "metal": 1}, "output": {"energy": 2}, "vp": 1},
	"coal_plant":      {"name": "Coal Plant", "category": "energy", "cost": {"metal": 2}, "output": {"energy": 3}, "vp": 2},
	"solar_array":     {"name": "Solar Array", "category": "energy", "cost": {"metal": 2, "coin": 2}, "output": {"energy": 2, "coin": 1}, "vp": 3},
	"hydro_dam":       {"name": "Hydro Dam", "category": "energy", "cost": {"wood": 3, "metal": 2}, "output": {"energy": 3, "coin": 1}, "vp": 4},
	"reactor":         {"name": "Reactor", "category": "energy", "cost": {"metal": 3, "energy": 2, "coin": 2}, "output": {"energy": 4}, "vp": 5},
	# --- commerce (coin) ---------------------------------------------------
	"market_stall":    {"name": "Market Stall", "category": "commerce", "cost": {"grain": 2}, "output": {"coin": 2}, "vp": 1},
	"trading_post":    {"name": "Trading Post", "category": "commerce", "cost": {"wood": 2, "grain": 2}, "output": {"coin": 3}, "vp": 2},
	"bank":            {"name": "Bank", "category": "commerce", "cost": {"coin": 4}, "output": {"coin": 3}, "vp": 3},
	"guild_hall":      {"name": "Guild Hall", "category": "commerce", "cost": {"coin": 3, "metal": 2}, "output": {"coin": 4}, "vp": 4},
	"bazaar":          {"name": "Bazaar", "category": "commerce", "cost": {"grain": 3, "energy": 2}, "output": {"coin": 3, "energy": 1}, "vp": 4},
}

## Deck composition — 3 copies of each of the 25 cards = a 75-card shared draw
## deck, shuffled by the seeded RNG at setup.
const DECK_COPIES := 3

## The five action types on the shared board.
const ACTIONS: Array[String] = ["PRODUCE", "BUILD", "TRADE", "RESEARCH", "DEPLOY"]

# =====================================================================
#  Live state
# =====================================================================

var num_players := 4
var players: Array = []          ## each: player dict (see _new_player)
var deck: Array = []             ## shared draw deck (card ids)
var round_index := 0             ## full rounds completed.
var current := 0                 ## whose turn it is (0 == the human in the UI).
var game_over := false
var winner := -1
var objectives: Dictionary = {}  ## obj_id -> {"claimed_by": int}  (-1 == open)
var illegal_attempts := 0        ## apply_action() rejections (should stay 0 in play).
var turn_count := 0              ## total legal actions taken (all players).
var log_lines: Array[String] = []
var final_scores: Array = []     ## filled by final_scoring(): per-player breakdown.

var _rng := RandomNumberGenerator.new()
var _seed := 0


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh game. seed_value == 0 -> random; any other value is fully
## deterministic (the entire game replays byte-identically). players in 2..5.
func setup(seed_value: int = 0, player_count: int = 4) -> void:
	num_players = clampi(player_count, 2, 5)
	_seed = seed_value
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value
	players = []
	for i in num_players:
		players.append(_new_player(i))
	_build_deck()
	round_index = 0
	current = 0
	game_over = false
	winner = -1
	illegal_attempts = 0
	turn_count = 0
	log_lines = []
	final_scores = []
	objectives = {
		"industrialist": {"claimed_by": -1},   # 3 mining cards
		"self_sufficient": {"claimed_by": -1},  # 3 stars
		"trade_baron": {"claimed_by": -1},       # 12 coin at once
	}
	for p in players:
		for _i in OPENING_HAND:
			_draw(p)
	_log("Game start — %d players, seed %d." % [num_players, _seed])


func _new_player(index: int) -> Dictionary:
	var res := {}
	var produced := {}
	var spent := {}
	for r in RESOURCES:
		res[r] = int(START_RESOURCES.get(r, 0))
		produced[r] = 0
		spent[r] = 0
	return {
		"index": index,
		"is_ai": index != 0,
		"resources": res,
		"produced": produced,   # conservation ledger (gains after start).
		"spent": spent,         # conservation ledger (losses).
		"tableau": ([] as Array),  # built card ids.
		"hand": ([] as Array),     # card ids in hand.
		"stars": 0,
	}


func _build_deck() -> void:
	deck = []
	var ids: Array = CARD_DB.keys()
	ids.sort()  # stable base order before the seeded shuffle.
	for _c in DECK_COPIES:
		for id in ids:
			deck.append(String(id))
	# Fisher-Yates with the seeded RNG (deterministic under _seed).
	for i in range(deck.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp


func _draw(p: Dictionary) -> bool:
	if deck.is_empty():
		return false
	if (p["hand"] as Array).size() >= HAND_MAX:
		return false
	(p["hand"] as Array).append(String(deck.pop_back()))
	return true


# =====================================================================
#  Resource ledger — the ONLY paths that touch a pool. This keeps
#  conservation provable: pool == start + produced - spent, always.
# =====================================================================

func _gain(p: Dictionary, res: String, amount: int) -> void:
	if amount <= 0:
		return
	(p["resources"] as Dictionary)[res] = int(p["resources"][res]) + amount
	(p["produced"] as Dictionary)[res] = int(p["produced"][res]) + amount


func _spend(p: Dictionary, res: String, amount: int) -> void:
	if amount <= 0:
		return
	(p["resources"] as Dictionary)[res] = int(p["resources"][res]) - amount
	(p["spent"] as Dictionary)[res] = int(p["spent"][res]) + amount


func _can_afford(p: Dictionary, cost: Dictionary) -> bool:
	for r in cost.keys():
		if int(p["resources"].get(r, 0)) < int(cost[r]):
			return false
	return true


func _pay(p: Dictionary, cost: Dictionary) -> void:
	for r in cost.keys():
		_spend(p, String(r), int(cost[r]))


## Verify the conservation invariant for every player and every resource.
## Returns true iff pool == start + produced - spent everywhere.
func verify_conservation() -> bool:
	for p in players:
		for r in RESOURCES:
			var expected := int(START_RESOURCES.get(r, 0)) \
				+ int(p["produced"][r]) - int(p["spent"][r])
			if int(p["resources"][r]) != expected:
				return false
			if int(p["resources"][r]) < 0:
				return false
	return true


# =====================================================================
#  Legality + the enumerated action list (the shared action board)
# =====================================================================

## Is this action legal for player `p_index` right now? Rejects out-of-turn
## actions, actions after game over, and any action the player cannot pay for.
func is_legal(p_index: int, action: Dictionary) -> bool:
	if game_over:
		return false
	if p_index != current:
		return false
	if p_index < 0 or p_index >= players.size():
		return false
	var p: Dictionary = players[p_index]
	match String(action.get("type", "")):
		"PRODUCE":
			return true
		"BUILD":
			var hi := int(action.get("hand_index", -1))
			var hand: Array = p["hand"]
			if hi < 0 or hi >= hand.size():
				return false
			var card: Dictionary = CARD_DB[hand[hi]]
			return _can_afford(p, card["cost"])
		"TRADE":
			var from_r := String(action.get("from", ""))
			var to_r := String(action.get("to", ""))
			if from_r == to_r or not RESOURCES.has(from_r) or not RESOURCES.has(to_r):
				return false
			return int(p["resources"].get(from_r, 0)) >= TRADE_IN
		"RESEARCH":
			return not deck.is_empty() and _can_afford(p, RESEARCH_COST) \
				and (p["hand"] as Array).size() < HAND_MAX
		"DEPLOY":
			return _can_afford(p, DEPLOY_COST)
		_:
			return false


## Every legal action for `p_index`, in a fixed deterministic order. Order:
## PRODUCE, BUILD(hand order), TRADE(resource-pair order), RESEARCH, DEPLOY.
## PRODUCE is always present, so a player can NEVER stall.
func legal_actions(p_index: int) -> Array:
	var out: Array = []
	if game_over or p_index != current:
		return out
	var p: Dictionary = players[p_index]
	out.append({"type": "PRODUCE"})
	var hand: Array = p["hand"]
	for i in hand.size():
		var card: Dictionary = CARD_DB[hand[i]]
		if _can_afford(p, card["cost"]):
			out.append({"type": "BUILD", "hand_index": i})
	for from_r in RESOURCES:
		if int(p["resources"][from_r]) >= TRADE_IN:
			for to_r in RESOURCES:
				if to_r != from_r:
					out.append({"type": "TRADE", "from": from_r, "to": to_r})
	if is_legal(p_index, {"type": "RESEARCH"}):
		out.append({"type": "RESEARCH"})
	if is_legal(p_index, {"type": "DEPLOY"}):
		out.append({"type": "DEPLOY"})
	return out


# =====================================================================
#  Applying an action (exactly ONE action == one turn)
# =====================================================================

## Take `action` for player `p_index`. Returns true on success. An illegal
## action is REJECTED (state unchanged) and counted in illegal_attempts.
func apply_action(p_index: int, action: Dictionary) -> bool:
	if not is_legal(p_index, action):
		illegal_attempts += 1
		return false
	var p: Dictionary = players[p_index]
	match String(action["type"]):
		"PRODUCE":
			_do_produce(p)
		"BUILD":
			_do_build(p, int(action["hand_index"]))
		"TRADE":
			_do_trade(p, String(action["from"]), String(action["to"]))
		"RESEARCH":
			_do_research(p)
		"DEPLOY":
			_do_deploy(p)
	turn_count += 1
	_check_objectives(p)
	return true


func _do_produce(p: Dictionary) -> void:
	var yielded := production_of(p)
	for r in yielded.keys():
		_gain(p, String(r), int(yielded[r]))
	_log("P%d PRODUCE -> %s" % [int(p["index"]), _fmt(yielded)])


func _do_build(p: Dictionary, hand_index: int) -> void:
	var card_id := String(p["hand"][hand_index])
	var card: Dictionary = CARD_DB[card_id]
	_pay(p, card["cost"])
	(p["hand"] as Array).remove_at(hand_index)
	(p["tableau"] as Array).append(card_id)
	_log("P%d BUILD %s (vp %d)" % [int(p["index"]), card["name"], int(card["vp"])])


func _do_trade(p: Dictionary, from_r: String, to_r: String) -> void:
	_spend(p, from_r, TRADE_IN)
	_gain(p, to_r, TRADE_OUT)
	_log("P%d TRADE %d %s -> %d %s" % [int(p["index"]), TRADE_IN, from_r, TRADE_OUT, to_r])


func _do_research(p: Dictionary) -> void:
	_pay(p, RESEARCH_COST)
	var drawn := 0
	for _i in RESEARCH_DRAW:
		if _draw(p):
			drawn += 1
	_log("P%d RESEARCH -> drew %d" % [int(p["index"]), drawn])


func _do_deploy(p: Dictionary) -> void:
	_pay(p, DEPLOY_COST)
	p["stars"] = int(p["stars"]) + 1
	_log("P%d DEPLOY -> star #%d" % [int(p["index"]), int(p["stars"])])


## What PRODUCE would yield for this player right now (base + every built card's
## output). Pure — used by both _do_produce and the AI evaluation.
func production_of(p: Dictionary) -> Dictionary:
	var out := {}
	for r in BASE_PRODUCTION.keys():
		out[r] = int(BASE_PRODUCTION[r])
	for card_id in p["tableau"]:
		var output: Dictionary = CARD_DB[card_id]["output"]
		for r in output.keys():
			out[r] = int(out.get(r, 0)) + int(output[r])
	return out


# =====================================================================
#  Objective tokens — first player to meet each claims it (one-time)
# =====================================================================

func _check_objectives(p: Dictionary) -> void:
	var pi := int(p["index"])
	if int(objectives["industrialist"]["claimed_by"]) < 0 \
			and _category_count(p, OBJ_INDUSTRIALIST_CATEGORY) >= OBJ_INDUSTRIALIST_COUNT:
		objectives["industrialist"]["claimed_by"] = pi
		_log("P%d claims INDUSTRIALIST objective (+%d)" % [pi, OBJ_VP])
	if int(objectives["self_sufficient"]["claimed_by"]) < 0 \
			and int(p["stars"]) >= OBJ_SELF_SUFFICIENT_STARS:
		objectives["self_sufficient"]["claimed_by"] = pi
		_log("P%d claims SELF-SUFFICIENT objective (+%d)" % [pi, OBJ_VP])
	if int(objectives["trade_baron"]["claimed_by"]) < 0 \
			and int(p["resources"]["coin"]) >= OBJ_TRADE_BARON_COIN:
		objectives["trade_baron"]["claimed_by"] = pi
		_log("P%d claims TRADE-BARON objective (+%d)" % [pi, OBJ_VP])


func _category_count(p: Dictionary, category: String) -> int:
	var n := 0
	for card_id in p["tableau"]:
		if String(CARD_DB[card_id]["category"]) == category:
			n += 1
	return n


# =====================================================================
#  Turn / round flow + the end trigger
# =====================================================================

## Advance to the next player. When the turn order wraps, a full round has
## elapsed — that is when the end trigger is checked, so every player always
## takes an equal number of turns (the star-goal triggerer's round completes).
func advance_turn() -> void:
	if game_over:
		return
	current += 1
	if current >= num_players:
		current = 0
		round_index += 1
		_check_end()


func _check_end() -> void:
	var top_stars := 0
	for p in players:
		top_stars = maxi(top_stars, int(p["stars"]))
	if top_stars >= GOAL_STARS or round_index >= MAX_ROUNDS:
		game_over = true
		final_scoring()


## The AI takes its whole turn: choose the best legal action and apply it.
func ai_take_turn(p_index: int) -> Dictionary:
	var action := ai_choose(p_index)
	apply_action(p_index, action)
	return action


# =====================================================================
#  The heuristic AI (non-LLM, deterministic, real weighted evaluation)
# =====================================================================

## Pick the highest-scoring legal action for `p_index`. Enumerates ALL legal
## actions and scores each with a weighted evaluation of its concrete effects:
##   * immediate VP gained (build vp, star vp)
##   * resource-efficiency (cost paid, valued by RESOURCE_VALUE)
##   * engine growth (the new per-turn production a build adds)
##   * progress-to-goal (DEPLOY scales up sharply as stars near GOAL_STARS)
##   * option value (RESEARCH when the hand is thin), conversion value (TRADE)
## Deterministic: ties break to the lowest index in legal_actions() order, so
## the same seed always produces the same game.
func ai_choose(p_index: int) -> Dictionary:
	var options := legal_actions(p_index)
	if options.is_empty():
		return {"type": "PRODUCE"}  # unreachable (PRODUCE is always legal), but safe.
	var p: Dictionary = players[p_index]
	var best_i := 0
	var best_score := -INF
	for i in options.size():
		var score := _score_action(p, options[i])
		if score > best_score:
			best_score = score
			best_i = i
	return options[best_i]


func _score_action(p: Dictionary, action: Dictionary) -> float:
	match String(action["type"]):
		"PRODUCE":
			# Value of banking this turn's whole production.
			return W_PRODUCE * _dict_value(production_of(p))
		"BUILD":
			var card: Dictionary = CARD_DB[p["hand"][int(action["hand_index"])]]
			var immediate := W_VP * float(int(card["vp"]))
			# Engine growth = the per-turn production this card adds, valued and
			# credited across the remaining rounds (a light lookahead horizon).
			var horizon := float(maxi(1, MAX_ROUNDS - round_index)) * 0.35
			var engine := W_ENGINE * _dict_value(card["output"]) * clampf(horizon, 1.0, 4.0)
			var cost := W_COST * _dict_value(card["cost"])
			var synergy := 0.0
			# Nudge toward the industrialist objective while it is still open.
			if String(card["category"]) == OBJ_INDUSTRIALIST_CATEGORY \
					and int(objectives["industrialist"]["claimed_by"]) < 0:
				synergy += 3.0
			return immediate + engine - cost + synergy
		"DEPLOY":
			var near := float(int(p["stars"]) + 1) / float(GOAL_STARS)
			var goal := W_GOAL * near * near  # quadratic: races hard near the goal.
			var star_vp := W_VP * float(STAR_VP)
			var cost2 := W_COST * _dict_value(DEPLOY_COST)
			return W_DEPLOY + star_vp + goal - cost2
		"TRADE":
			var from_r := String(action["from"])
			var to_r := String(action["to"])
			var net := float(RESOURCE_VALUE[to_r]) * TRADE_OUT \
				- float(RESOURCE_VALUE[from_r]) * TRADE_IN
			var need := 0.0
			# Bonus if the gained resource is one we are short of for DEPLOY.
			if DEPLOY_COST.has(to_r) \
					and int(p["resources"][to_r]) < int(DEPLOY_COST[to_r]):
				need += W_TRADE_NEED
			return W_TRADE * net + need
		"RESEARCH":
			var deficit := float(maxi(0, AI_TARGET_HAND - (p["hand"] as Array).size()))
			return W_RESEARCH * deficit - W_COST * _dict_value(RESEARCH_COST)
		_:
			return -INF


func _dict_value(d: Dictionary) -> float:
	var v := 0.0
	for r in d.keys():
		v += float(RESOURCE_VALUE.get(r, 1.0)) * float(int(d[r]))
	return v


# =====================================================================
#  Scoring
# =====================================================================

## Running VP from built cards (used for the live UI; the final total also adds
## stars, objectives and majorities via final_scoring()).
func card_vp(p: Dictionary) -> int:
	var v := 0
	for card_id in p["tableau"]:
		v += int(CARD_DB[card_id]["vp"])
	return v


## A live VP estimate (cards + stars + claimed objective tokens) for the HUD —
## majorities are only resolved at the end.
func live_vp(p_index: int) -> int:
	var p: Dictionary = players[p_index]
	var v := card_vp(p) + int(p["stars"]) * STAR_VP
	for obj_id in objectives.keys():
		if int(objectives[obj_id]["claimed_by"]) == p_index:
			v += OBJ_VP
	return v


## Compute every player's final score breakdown and the winner. Fills
## final_scores with per-player dicts whose components SUM to "total" (the probe
## checks this exactly). Winner tie-break: total, then stars, then cards, then
## lowest index — always a single winner.
func final_scoring() -> void:
	var max_stars := 0
	var max_cards := 0
	var max_coin := 0
	for p in players:
		max_stars = maxi(max_stars, int(p["stars"]))
		max_cards = maxi(max_cards, (p["tableau"] as Array).size())
		max_coin = maxi(max_coin, int(p["resources"]["coin"]))
	final_scores = []
	for pi in players.size():
		var p: Dictionary = players[pi]
		var vp_cards := card_vp(p)
		var vp_stars := int(p["stars"]) * STAR_VP
		var vp_objectives := 0
		for obj_id in objectives.keys():
			if int(objectives[obj_id]["claimed_by"]) == pi:
				vp_objectives += OBJ_VP
		var vp_majorities := 0
		if int(p["stars"]) == max_stars and max_stars > 0:
			vp_majorities += MAJ_STARS_VP
		if (p["tableau"] as Array).size() == max_cards and max_cards > 0:
			vp_majorities += MAJ_CARDS_VP
		if int(p["resources"]["coin"]) == max_coin and max_coin > 0:
			vp_majorities += MAJ_COIN_VP
		var total := vp_cards + vp_stars + vp_objectives + vp_majorities
		final_scores.append({
			"index": pi,
			"vp_cards": vp_cards,
			"vp_stars": vp_stars,
			"vp_objectives": vp_objectives,
			"vp_majorities": vp_majorities,
			"total": total,
		})
	winner = _decide_winner()
	_log("GAME OVER — winner P%d (%d VP)." % [winner, int(final_scores[winner]["total"])])


func _decide_winner() -> int:
	var best := 0
	for pi in range(1, players.size()):
		if _beats(pi, best):
			best = pi
	return best


## Strict deterministic ordering: total, then stars, then card count, then the
## LOWER index wins (so the comparison is total and yields exactly one winner).
func _beats(a: int, b: int) -> bool:
	var sa: Dictionary = final_scores[a]
	var sb: Dictionary = final_scores[b]
	if int(sa["total"]) != int(sb["total"]):
		return int(sa["total"]) > int(sb["total"])
	if int(players[a]["stars"]) != int(players[b]["stars"]):
		return int(players[a]["stars"]) > int(players[b]["stars"])
	var ca := (players[a]["tableau"] as Array).size()
	var cb := (players[b]["tableau"] as Array).size()
	if ca != cb:
		return ca > cb
	return a < b


# =====================================================================
#  Small helpers + logging
# =====================================================================

func _fmt(d: Dictionary) -> String:
	var parts: Array[String] = []
	for r in RESOURCES:
		if d.has(r) and int(d[r]) != 0:
			parts.append("%d %s" % [int(d[r]), r])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 200:
		log_lines.remove_at(0)


func recent_log(n: int = 10) -> Array[String]:
	var out: Array[String] = []
	var start := maxi(0, log_lines.size() - n)
	for i in range(start, log_lines.size()):
		out.append(log_lines[i])
	return out


# =====================================================================
#  Save / load — the FULL game state round-trips (deep, JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	return {
		"num_players": num_players,
		"seed": _seed,
		# uint64 RNG state as a String so it survives JSON without float rounding.
		"rng_state": str(_rng.state),
		"players": players.duplicate(true),
		"deck": deck.duplicate(),
		"round_index": round_index,
		"current": current,
		"game_over": game_over,
		"winner": winner,
		"objectives": objectives.duplicate(true),
		"illegal_attempts": illegal_attempts,
		"turn_count": turn_count,
		"final_scores": final_scores.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	num_players = int(data.get("num_players", 4))
	_seed = int(data.get("seed", 0))
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	players = []
	for p_variant in data.get("players", []):
		players.append(_coerce_player(p_variant as Dictionary))
	deck = []
	for c in data.get("deck", []):
		deck.append(String(c))
	round_index = int(data.get("round_index", 0))
	current = int(data.get("current", 0))
	game_over = bool(data.get("game_over", false))
	winner = int(data.get("winner", -1))
	objectives = {}
	for obj_id in (data.get("objectives", {}) as Dictionary).keys():
		objectives[String(obj_id)] = {
			"claimed_by": int(data["objectives"][obj_id]["claimed_by"]),
		}
	illegal_attempts = int(data.get("illegal_attempts", 0))
	turn_count = int(data.get("turn_count", 0))
	final_scores = []
	for s_variant in data.get("final_scores", []):
		var s: Dictionary = s_variant
		final_scores.append({
			"index": int(s["index"]),
			"vp_cards": int(s["vp_cards"]),
			"vp_stars": int(s["vp_stars"]),
			"vp_objectives": int(s["vp_objectives"]),
			"vp_majorities": int(s["vp_majorities"]),
			"total": int(s["total"]),
		})


## Rebuild a player dict from (possibly JSON-float) data, coercing to ints so a
## reloaded state is byte-identical to the saved one.
func _coerce_player(src: Dictionary) -> Dictionary:
	var res := {}
	var produced := {}
	var spent := {}
	for r in RESOURCES:
		res[r] = int((src.get("resources", {}) as Dictionary).get(r, 0))
		produced[r] = int((src.get("produced", {}) as Dictionary).get(r, 0))
		spent[r] = int((src.get("spent", {}) as Dictionary).get(r, 0))
	var tableau: Array = []
	for c in src.get("tableau", []):
		tableau.append(String(c))
	var hand: Array = []
	for c in src.get("hand", []):
		hand.append(String(c))
	return {
		"index": int(src["index"]),
		"is_ai": bool(src.get("is_ai", int(src["index"]) != 0)),
		"resources": res,
		"produced": produced,
		"spent": spent,
		"tableau": tableau,
		"hand": hand,
		"stars": int(src["stars"]),
	}
