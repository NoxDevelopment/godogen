extends RefCounted
class_name PokerEngine
## res://scripts/poker_engine.gd
## The PURE, seedable, headless-testable engine for a Balatro-style POKER-SCORING
## ROGUELIKE: draw a hand, play a 1-5 card poker hand to beat an escalating score
## TARGET, and warp the math with JOKERS + planet-style hand-level upgrades bought
## in a shop. There is NO Godot node dependency in here — it is plain data + rules,
## so an entire run replays BYTE-IDENTICALLY from a seed and can be driven with no
## UI at all. GameManager owns one instance and adds the autoload ABI + save;
## table.gd only reads state and forwards a human's chosen action.
##
## The model (why it is a real scoring engine, not an abstraction):
##   * A 52-card deck (rank 2..14, suit 0..3), cards can carry an ENHANCEMENT.
##     Draw HAND_SIZE cards; the player SELECTS 1-5 to play as a poker hand.
##   * REAL poker hand detection for all 12 types, including the wheel (A-2-3-4-5)
##     and ace-high straights, and the enhanced hands (five-of-a-kind, flush-house,
##     flush-five). See evaluate().
##   * EXACT deterministic scoring: score = (base_chips[type][level] + scored-card
##     chips) x (base_mult[type][level] + card mult) then every JOKER applies IN
##     SLOT ORDER (+chips / +mult / xmult, conditionally), then chips x mult rounded
##     half-up. See score_breakdown() — it returns every component so the math is
##     auditable and testable to the number.
##   * 25 JOKERS with genuinely varied, functional effects (flat, conditional,
##     per-held-card, per-discard, per-joker, retrigger, and SCALING jokers that
##     grow as a run progresses). Up to JOKER_SLOTS held, applied in order.
##   * RUN structure: antes 1..8, each = small/big/boss blind with an escalating
##     TARGET; N hands + M discards per blind; a SHOP between blinds sells jokers +
##     hand-level upgrades for MONEY (blind reward + interest). WIN = clear the
##     final ante's boss; LOSE = fail a blind's target within your hands.
##   * A deterministic AUTO-PLAY heuristic (best_play + auto_take_turn) that drives
##     a full run headlessly — it is NOT an opponent (this is solo).

# =====================================================================
#  Hand types (0..11, strictly increasing strength) — the scoring keys
# =====================================================================

enum HandType {
	HIGH_CARD, PAIR, TWO_PAIR, THREE_KIND, STRAIGHT, FLUSH,
	FULL_HOUSE, FOUR_KIND, STRAIGHT_FLUSH, FIVE_KIND, FLUSH_HOUSE, FLUSH_FIVE,
}

const TYPE_NAME := {
	HandType.HIGH_CARD: "High Card",
	HandType.PAIR: "Pair",
	HandType.TWO_PAIR: "Two Pair",
	HandType.THREE_KIND: "Three of a Kind",
	HandType.STRAIGHT: "Straight",
	HandType.FLUSH: "Flush",
	HandType.FULL_HOUSE: "Full House",
	HandType.FOUR_KIND: "Four of a Kind",
	HandType.STRAIGHT_FLUSH: "Straight Flush",
	HandType.FIVE_KIND: "Five of a Kind",
	HandType.FLUSH_HOUSE: "Flush House",
	HandType.FLUSH_FIVE: "Flush Five",
}

## base_chips / base_mult are the LEVEL-1 values; per_chips / per_mult are added
## for every level above 1. chips_at()/mult_at() apply the ramp. These are the
## auditable "planet" tuning table — swap them for your own game.
const HAND_BASE := {
	HandType.HIGH_CARD:      {"chips": 5,   "mult": 1,  "per_chips": 10, "per_mult": 1},
	HandType.PAIR:           {"chips": 10,  "mult": 2,  "per_chips": 15, "per_mult": 1},
	HandType.TWO_PAIR:       {"chips": 20,  "mult": 2,  "per_chips": 20, "per_mult": 1},
	HandType.THREE_KIND:     {"chips": 30,  "mult": 3,  "per_chips": 20, "per_mult": 2},
	HandType.STRAIGHT:       {"chips": 30,  "mult": 4,  "per_chips": 30, "per_mult": 3},
	HandType.FLUSH:          {"chips": 35,  "mult": 4,  "per_chips": 15, "per_mult": 2},
	HandType.FULL_HOUSE:     {"chips": 40,  "mult": 4,  "per_chips": 25, "per_mult": 2},
	HandType.FOUR_KIND:      {"chips": 60,  "mult": 7,  "per_chips": 30, "per_mult": 3},
	HandType.STRAIGHT_FLUSH: {"chips": 100, "mult": 8,  "per_chips": 40, "per_mult": 4},
	HandType.FIVE_KIND:      {"chips": 120, "mult": 12, "per_chips": 35, "per_mult": 3},
	HandType.FLUSH_HOUSE:    {"chips": 140, "mult": 14, "per_chips": 40, "per_mult": 4},
	HandType.FLUSH_FIVE:     {"chips": 160, "mult": 16, "per_chips": 50, "per_mult": 3},
}

# =====================================================================
#  Deck / card model
# =====================================================================

const SUIT_NAME := ["Spades", "Hearts", "Clubs", "Diamonds"]
const SUIT_GLYPH := ["S", "H", "C", "D"]
## Enhancements a card may carry (default ""): bonus (+30 chips when scored),
## mult (+4 mult when scored), glass (x2 mult when scored), wild (matches any
## suit for flush detection). Steel/stone-style ones extend from here.
const ENHANCEMENTS := ["", "bonus", "mult", "glass", "wild"]

# =====================================================================
#  Run tuning (auditable constants — swap for your own game)
# =====================================================================

const HAND_SIZE := 8            ## cards drawn to hand each refill.
const JOKER_SLOTS := 5          ## max jokers held at once.
const MAX_ANTE := 8             ## clear ante 8's boss to WIN.
const BASE_HANDS := 4           ## plays allowed per blind.
const BASE_DISCARDS := 3        ## discards allowed per blind.
const START_MONEY := 4
const HAND_UPGRADE_COST := 3    ## a planet (levels one hand type) in the shop.
const SHOP_JOKERS := 2          ## jokers offered per shop.
const SHOP_PLANETS := 2         ## hand-upgrades offered per shop.
const INTEREST_PER := 5         ## +$1 interest per $5 held…
const INTEREST_CAP := 5         ## …capped at $5.
const LEFTOVER_HAND_CAP := 5    ## +$1 per unused hand, capped.

## Base score target per ante (index 1..8) and the per-blind multiplier
## (small / big / boss). target = int(ANTE_BASE[ante] * BLIND_MULT[blind] * scale).
const ANTE_BASE := [0, 300, 800, 2000, 5000, 11000, 20000, 35000, 50000]
const BLIND_MULT := [1.0, 1.5, 2.0]
const BLIND_NAMES := ["Small Blind", "Big Blind", "Boss Blind"]
const BLIND_REWARD := [3, 4, 5]

# =====================================================================
#  Joker database — 25 real, varied scoring effects (id -> definition)
# =====================================================================
## effect names map to branches in _apply_joker(). feature in
## {pair,two_pair,three,four,straight,flush,any}. Scaling jokers grow a per-copy
## counter on play (see _grow_scaling). Costs drive the shop economy.
const JOKER_DB := {
	"joker_basic":  {"name": "Wildcard",      "cost": 2, "effect": "flat_mult", "n": 4,  "desc": "+4 Mult."},
	"greedy_chips": {"name": "Chip Hoarder",  "cost": 3, "effect": "flat_chips", "n": 30, "desc": "+30 Chips."},
	"half_joker":   {"name": "Half Joker",    "cost": 4, "effect": "mult_if_handsize_le", "k": 3, "n": 8, "desc": "+8 Mult if 3 or fewer cards played."},
	"jolly":        {"name": "Jolly",         "cost": 3, "effect": "cond_mult", "feature": "pair", "n": 8,  "desc": "+8 Mult if hand contains a Pair."},
	"zany":         {"name": "Zany",          "cost": 4, "effect": "cond_mult", "feature": "three", "n": 12, "desc": "+12 Mult if hand contains Three of a Kind."},
	"mad":          {"name": "Mad",           "cost": 4, "effect": "cond_mult", "feature": "two_pair", "n": 10, "desc": "+10 Mult if hand contains Two Pair."},
	"crazy":        {"name": "Crazy",         "cost": 4, "effect": "cond_mult", "feature": "straight", "n": 12, "desc": "+12 Mult if hand contains a Straight."},
	"droll":        {"name": "Droll",         "cost": 4, "effect": "cond_mult", "feature": "flush", "n": 10, "desc": "+10 Mult if hand contains a Flush."},
	"crafty":       {"name": "Crafty",        "cost": 4, "effect": "cond_chips", "feature": "flush", "n": 40, "desc": "+40 Chips if hand contains a Flush."},
	"wily":         {"name": "Wily",          "cost": 4, "effect": "cond_chips", "feature": "three", "n": 40, "desc": "+40 Chips if hand contains Three of a Kind."},
	"clever":       {"name": "Clever",        "cost": 4, "effect": "cond_chips", "feature": "two_pair", "n": 50, "desc": "+50 Chips if hand contains Two Pair."},
	"devious":      {"name": "Devious",       "cost": 4, "effect": "cond_chips", "feature": "straight", "n": 40, "desc": "+40 Chips if hand contains a Straight."},
	"multiplier":   {"name": "Multiplier",    "cost": 6, "effect": "x_mult", "x": 1.5, "desc": "x1.5 Mult."},
	"steel":        {"name": "Steel Focus",   "cost": 6, "effect": "x_mult_if_handsize_le", "k": 2, "x": 2.0, "desc": "x2 Mult if 2 or fewer cards played."},
	"banner":       {"name": "Banner",        "cost": 5, "effect": "chips_per_discard", "n": 30, "desc": "+30 Chips per discard remaining."},
	"mystic":       {"name": "Mystic Summit", "cost": 5, "effect": "mult_if_no_discard", "n": 15, "desc": "+15 Mult when 0 discards remaining."},
	"abstract":     {"name": "Abstract",      "cost": 4, "effect": "mult_per_joker", "n": 3, "desc": "+3 Mult per Joker held."},
	"even_steven":  {"name": "Even Steven",   "cost": 4, "effect": "mult_per_scored_even", "n": 4, "desc": "+4 Mult per scored even-rank card."},
	"odd_todd":     {"name": "Odd Todd",      "cost": 4, "effect": "chips_per_scored_odd", "n": 30, "desc": "+30 Chips per scored odd-rank card."},
	"chad":         {"name": "Hanging Chad",  "cost": 4, "effect": "retrigger_first", "desc": "Retriggers the first scored card."},
	"collector":    {"name": "Card Collector","cost": 4, "effect": "chips_per_card_held", "n": 8, "desc": "+8 Chips per card still held."},
	"green":        {"name": "Green Joker",   "cost": 4, "effect": "scaling_mult", "grow": 1, "feature": "any", "desc": "+1 Mult, gains +1 Mult per hand played."},
	"runner":       {"name": "Runner",        "cost": 5, "effect": "scaling_chips", "grow": 15, "feature": "straight", "desc": "Gains +15 Chips per Straight played."},
	"obelisk":      {"name": "Obelisk",       "cost": 5, "effect": "mult_per_type_count", "n": 2, "desc": "+2 Mult per prior play of this hand type this run."},
	"blueprint":    {"name": "Bootstraps",    "cost": 5, "effect": "mult_per_money", "per": 5, "n": 2, "desc": "+2 Mult per $5 you hold."},
}

# =====================================================================
#  Live run state
# =====================================================================

var ante := 1                   ## 1..MAX_ANTE.
var blind_index := 0            ## 0 small, 1 big, 2 boss.
var phase := "blind"            ## "blind" | "shop" | "done".
var current_target := 0         ## score needed to clear the current blind.
var round_score := 0            ## chips scored so far this blind.
var hands_left := 0
var discards_left := 0
var money := START_MONEY
var run_over := false
var run_won := false

var deck: Array = []            ## remaining draw pile (card dicts).
var hand: Array = []            ## current cards in hand (card dicts).
var jokers: Array = []          ## owned jokers: {id, counter}.
var hand_levels: Dictionary = {}  ## HandType -> level (>=1).
var type_play_counts: Dictionary = {}  ## HandType -> times played this run.
var shop_items: Array = []      ## current shop offerings.
var extra_cards: Array = []     ## cards bought into the deck (persist across blinds).
var last_reward := 0
var last_score := 0             ## score of the most recent play (for the HUD).
var illegal_attempts := 0
var log_lines: Array[String] = []

var _rng := RandomNumberGenerator.new()
var _seed := 0
var _hands_per_blind := BASE_HANDS
var _discards_per_blind := BASE_DISCARDS
var _target_scale := 1.0
var _hand_size := HAND_SIZE


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh run. seed_value == 0 -> random; any other value replays
## byte-identically. `config` optionally overrides difficulty knobs:
##   hands_per_blind, discards_per_blind, target_scale, hand_size,
##   start_money, start_jokers (Array of ids).
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	_seed = seed_value
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value
	_hands_per_blind = int(config.get("hands_per_blind", BASE_HANDS))
	_discards_per_blind = int(config.get("discards_per_blind", BASE_DISCARDS))
	_target_scale = float(config.get("target_scale", 1.0))
	_hand_size = int(config.get("hand_size", HAND_SIZE))
	ante = 1
	blind_index = 0
	phase = "blind"
	round_score = 0
	money = int(config.get("start_money", START_MONEY))
	run_over = false
	run_won = false
	jokers = []
	for jid in config.get("start_jokers", []):
		if JOKER_DB.has(String(jid)) and jokers.size() < JOKER_SLOTS:
			jokers.append({"id": String(jid), "counter": 0})
	hand_levels = {}
	type_play_counts = {}
	for t in HAND_BASE.keys():
		hand_levels[t] = 1
		type_play_counts[t] = 0
	extra_cards = []
	shop_items = []
	last_reward = 0
	last_score = 0
	illegal_attempts = 0
	log_lines = []
	_begin_blind()
	_log("Run start — seed %d." % _seed)


func _begin_blind() -> void:
	phase = "blind"
	round_score = 0
	hands_left = _hands_per_blind
	discards_left = _discards_per_blind
	current_target = _target_for(ante, blind_index)
	_build_and_shuffle_deck()
	hand = []
	_refill_hand()
	_log("Ante %d %s — target %d." % [ante, BLIND_NAMES[blind_index], current_target])


func _target_for(a: int, bi: int) -> int:
	var base: int = ANTE_BASE[clampi(a, 1, MAX_ANTE)]
	return int(round(float(base) * BLIND_MULT[bi] * _target_scale))


func _build_and_shuffle_deck() -> void:
	deck = []
	for suit in 4:
		for rank in range(2, 15):
			deck.append({"rank": rank, "suit": suit, "enh": ""})
	for c in extra_cards:
		deck.append({"rank": int(c["rank"]), "suit": int(c["suit"]), "enh": String(c["enh"])})
	# Fisher-Yates with the seeded RNG (deterministic under _seed).
	for i in range(deck.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp


func _refill_hand() -> void:
	while hand.size() < _hand_size and not deck.is_empty():
		hand.append(deck.pop_back())


# =====================================================================
#  Poker hand evaluation — REAL detection of all 12 types
# =====================================================================

## Evaluate 1..5 cards. Returns a dict with the detected type, flush/straight
## flags, rank-count summary, and the indices (into `cards`) that SCORE.
func evaluate(cards: Array) -> Dictionary:
	var n := cards.size()
	# --- rank buckets: rank -> Array of indices ---
	var buckets: Dictionary = {}
	for i in n:
		var r := int(cards[i]["rank"])
		if not buckets.has(r):
			buckets[r] = []
		(buckets[r] as Array).append(i)
	var counts: Array[int] = []
	for r in buckets.keys():
		counts.append((buckets[r] as Array).size())
	counts.sort()
	counts.reverse()  # descending
	var max_count := counts[0] if counts.size() > 0 else 0
	var pair_count := 0
	for c in counts:
		if c >= 2:
			pair_count += 1

	# --- flush (needs exactly 5 cards, one suit; wild matches any) ---
	var is_flush := false
	if n == 5:
		var suit := -1
		var ok := true
		for c in cards:
			if String(c["enh"]) == "wild":
				continue
			if suit == -1:
				suit = int(c["suit"])
			elif int(c["suit"]) != suit:
				ok = false
				break
		is_flush = ok

	# --- straight (needs 5 distinct consecutive ranks; wheel + ace-high) ---
	var is_straight := _is_straight(cards) if n == 5 else false

	# --- base category from the count pattern ---
	var base_type: int
	if max_count >= 5:
		base_type = HandType.FIVE_KIND
	elif max_count == 4:
		base_type = HandType.FOUR_KIND
	elif max_count == 3 and pair_count >= 2:
		base_type = HandType.FULL_HOUSE
	elif max_count == 3:
		base_type = HandType.THREE_KIND
	elif pair_count == 2:
		base_type = HandType.TWO_PAIR
	elif pair_count == 1:
		base_type = HandType.PAIR
	else:
		base_type = HandType.HIGH_CARD

	# --- combine with flush / straight into the final type ---
	var type: int = base_type
	if base_type == HandType.FIVE_KIND and is_flush:
		type = HandType.FLUSH_FIVE
	elif base_type == HandType.FIVE_KIND:
		type = HandType.FIVE_KIND
	elif base_type == HandType.FULL_HOUSE and is_flush:
		type = HandType.FLUSH_HOUSE
	elif is_straight and is_flush:
		type = HandType.STRAIGHT_FLUSH
	elif base_type == HandType.FOUR_KIND:
		type = HandType.FOUR_KIND
	elif base_type == HandType.FULL_HOUSE:
		type = HandType.FULL_HOUSE
	elif is_flush:
		type = HandType.FLUSH
	elif is_straight:
		type = HandType.STRAIGHT
	else:
		type = base_type

	var scored := _scored_indices(cards, type, buckets)
	return {
		"type": type,
		"type_name": String(TYPE_NAME[type]),
		"is_flush": is_flush,
		"is_straight": is_straight,
		"max_count": max_count,
		"pair_count": pair_count,
		"scored": scored,
	}


func _is_straight(cards: Array) -> bool:
	if cards.size() != 5:
		return false
	var rs: Array[int] = []
	var seen: Dictionary = {}
	for c in cards:
		var r := int(c["rank"])
		if seen.has(r):
			return false  # duplicate rank cannot be a straight
		seen[r] = true
		rs.append(r)
	rs.sort()
	if rs[4] - rs[0] == 4:
		return true
	# The wheel: A-2-3-4-5 (Ace low) == ranks [2,3,4,5,14].
	if rs == [2, 3, 4, 5, 14]:
		return true
	return false


## Which played-card indices actually score for `type`. For n-of-a-kind hands
## only the matching cards score; for straights/flushes/full-house/five-kind all
## five score; for high card the single highest (ace-high, lowest index breaks
## ties).
func _scored_indices(cards: Array, type: int, buckets: Dictionary) -> Array[int]:
	var out: Array[int] = []
	match type:
		HandType.STRAIGHT, HandType.FLUSH, HandType.FULL_HOUSE, HandType.STRAIGHT_FLUSH, \
		HandType.FIVE_KIND, HandType.FLUSH_HOUSE, HandType.FLUSH_FIVE:
			for i in cards.size():
				out.append(i)
		HandType.FOUR_KIND:
			out = _indices_with_count(buckets, 4)
		HandType.THREE_KIND:
			out = _indices_with_count(buckets, 3)
		HandType.TWO_PAIR:
			out = _indices_with_count(buckets, 2)
		HandType.PAIR:
			out = _indices_with_count(buckets, 2)
		HandType.HIGH_CARD:
			var best_i := 0
			var best_r := -1
			for i in cards.size():
				if int(cards[i]["rank"]) > best_r:
					best_r = int(cards[i]["rank"])
					best_i = i
			out.append(best_i)
	out.sort()
	return out


func _indices_with_count(buckets: Dictionary, min_count: int) -> Array[int]:
	var out: Array[int] = []
	for r in buckets.keys():
		var idxs: Array = buckets[r]
		if idxs.size() >= min_count:
			for i in idxs:
				out.append(int(i))
	return out


# =====================================================================
#  Card + hand-level chip/mult helpers
# =====================================================================

## Chip value of a card's rank: number cards = pip, J/Q/K = 10, Ace = 11.
func card_chips(card: Dictionary) -> int:
	var r := int(card["rank"])
	if r >= 11 and r <= 13:
		return 10
	if r == 14:
		return 11
	return r


func chips_at(type: int, level: int) -> int:
	var b: Dictionary = HAND_BASE[type]
	return int(b["chips"]) + (level - 1) * int(b["per_chips"])


func mult_at(type: int, level: int) -> int:
	var b: Dictionary = HAND_BASE[type]
	return int(b["mult"]) + (level - 1) * int(b["per_mult"])


func level_of(type: int) -> int:
	return int(hand_levels.get(type, 1))


# =====================================================================
#  Scoring — the exact, component-by-component pipeline
# =====================================================================

## Score the poker hand made from `indices` into the current hand. PURE: it reads
## live state (jokers, hand_levels, discards_left, money, held cards) but MUTATES
## nothing — play() commits scaling growth separately. Returns a full breakdown so
## every component (base chips, card chips, mult, each joker's delta, final score)
## is auditable + testable to the number.
func score_breakdown(indices: Array) -> Dictionary:
	var cards: Array = []
	for i in indices:
		cards.append(hand[int(i)])
	var ev := evaluate(cards)
	var type: int = ev["type"]
	var level := level_of(type)
	var base_chips := chips_at(type, level)
	var base_mult := float(mult_at(type, level))
	var chips := base_chips
	var mult := base_mult

	# --- scored cards contribute chips + their enhancement effects ---
	var scored: Array = ev["scored"]
	var card_chips_sum := 0
	# The first scored card's contribution (for retrigger jokers).
	var first_chips := 0
	var first_mult_add := 0.0
	var first_mult_x := 1.0
	var first_done := false
	for si in scored:
		var c: Dictionary = cards[int(si)]
		var cc := card_chips(c)
		chips += cc
		card_chips_sum += cc
		var this_mult_add := 0.0
		var this_mult_x := 1.0
		var this_bonus := 0
		match String(c["enh"]):
			"bonus":
				this_bonus = 30
			"mult":
				this_mult_add = 4.0
			"glass":
				this_mult_x = 2.0
		if this_bonus > 0:
			chips += this_bonus
			card_chips_sum += this_bonus
		if this_mult_add > 0.0:
			mult += this_mult_add
		if this_mult_x != 1.0:
			mult *= this_mult_x
		if not first_done:
			first_done = true
			first_chips = cc + this_bonus
			first_mult_add = this_mult_add
			first_mult_x = this_mult_x

	var chips_after_cards := chips
	var mult_after_cards := mult

	# --- jokers apply IN SLOT ORDER ---
	var ctx := {
		"ev": ev,
		"cards": cards,
		"scored": scored,
		"played_size": cards.size(),
		"cards_held": maxi(0, hand.size() - cards.size()),
		"discards_left": discards_left,
		"money": money,
		"num_jokers": jokers.size(),
		"type": type,
		"prior_type_count": int(type_play_counts.get(type, 0)),
		"first_chips": first_chips,
		"first_mult_add": first_mult_add,
		"first_mult_x": first_mult_x,
	}
	var acc := {"chips": float(chips), "mult": mult}
	var joker_log: Array = []
	for j in jokers:
		var before_chips: float = acc["chips"]
		var before_mult: float = acc["mult"]
		_apply_joker(j, ctx, acc)
		joker_log.append({
			"id": String(j["id"]),
			"name": String(JOKER_DB[String(j["id"])]["name"]),
			"chips_before": int(round(before_chips)),
			"mult_before": before_mult,
			"chips_after": int(round(acc["chips"])),
			"mult_after": acc["mult"],
		})

	var final_chips := int(round(acc["chips"]))
	var final_mult: float = acc["mult"]
	var score := int(floor(float(final_chips) * final_mult + 0.5))  # round half-up.
	return {
		"eval": ev,
		"type": type,
		"type_name": String(TYPE_NAME[type]),
		"level": level,
		"base_chips": base_chips,
		"base_mult": base_mult,
		"card_chips": card_chips_sum,
		"chips_after_cards": chips_after_cards,
		"mult_after_cards": mult_after_cards,
		"joker_log": joker_log,
		"final_chips": final_chips,
		"final_mult": final_mult,
		"score": score,
	}


## Apply one joker's effect to the accumulator {chips: float, mult: float}.
func _apply_joker(j: Dictionary, ctx: Dictionary, acc: Dictionary) -> void:
	var def: Dictionary = JOKER_DB[String(j["id"])]
	var ev: Dictionary = ctx["ev"]
	match String(def["effect"]):
		"flat_mult":
			acc["mult"] += float(def["n"])
		"flat_chips":
			acc["chips"] += float(def["n"])
		"x_mult":
			acc["mult"] *= float(def["x"])
		"cond_mult":
			if _contains(ev, String(def["feature"])):
				acc["mult"] += float(def["n"])
		"cond_chips":
			if _contains(ev, String(def["feature"])):
				acc["chips"] += float(def["n"])
		"mult_if_handsize_le":
			if int(ctx["played_size"]) <= int(def["k"]):
				acc["mult"] += float(def["n"])
		"x_mult_if_handsize_le":
			if int(ctx["played_size"]) <= int(def["k"]):
				acc["mult"] *= float(def["x"])
		"chips_per_discard":
			acc["chips"] += float(def["n"]) * float(int(ctx["discards_left"]))
		"mult_if_no_discard":
			if int(ctx["discards_left"]) == 0:
				acc["mult"] += float(def["n"])
		"mult_per_joker":
			acc["mult"] += float(def["n"]) * float(int(ctx["num_jokers"]))
		"mult_per_money":
			acc["mult"] += float(def["n"]) * float(int(ctx["money"]) / int(def["per"]))
		"mult_per_scored_even":
			acc["mult"] += float(def["n"]) * float(_scored_parity(ctx, true))
		"chips_per_scored_odd":
			acc["chips"] += float(def["n"]) * float(_scored_parity(ctx, false))
		"retrigger_first":
			acc["chips"] += float(int(ctx["first_chips"]))
			acc["mult"] += float(ctx["first_mult_add"])
			if float(ctx["first_mult_x"]) != 1.0:
				acc["mult"] *= float(ctx["first_mult_x"])
		"chips_per_card_held":
			acc["chips"] += float(def["n"]) * float(int(ctx["cards_held"]))
		"scaling_mult":
			acc["mult"] += float(int(j["counter"]))
		"scaling_chips":
			acc["chips"] += float(int(j["counter"]))
		"mult_per_type_count":
			acc["mult"] += float(def["n"]) * float(int(ctx["prior_type_count"]))
		_:
			push_error("PokerEngine: unknown joker effect '%s'." % String(def["effect"]))


## Count scored cards whose rank parity matches (even==true -> even ranks).
func _scored_parity(ctx: Dictionary, even: bool) -> int:
	var cards: Array = ctx["cards"]
	var scored: Array = ctx["scored"]
	var n := 0
	for si in scored:
		var r := int(cards[int(si)]["rank"])
		if (r % 2 == 0) == even:
			n += 1
	return n


## Does the evaluated hand CONTAIN the feature (Balatro semantics: a Full House
## contains a Pair AND Three of a Kind, etc.)?
func _contains(ev: Dictionary, feature: String) -> bool:
	match feature:
		"pair":
			return int(ev["max_count"]) >= 2
		"two_pair":
			return int(ev["pair_count"]) >= 2
		"three":
			return int(ev["max_count"]) >= 3
		"four":
			return int(ev["max_count"]) >= 4
		"straight":
			return bool(ev["is_straight"])
		"flush":
			return bool(ev["is_flush"])
		"any":
			return true
	return false


# =====================================================================
#  Legality
# =====================================================================

## Is `action` legal in the current state? action.type in
## {play, discard, buy, sell, leave_shop}. Rejects illegal card counts, empty
## resources, unaffordable buys, out-of-phase actions.
func is_legal(action: Dictionary) -> bool:
	if run_over:
		return false
	match String(action.get("type", "")):
		"play":
			if phase != "blind" or hands_left <= 0:
				return false
			return _valid_selection(action.get("indices", []))
		"discard":
			if phase != "blind" or discards_left <= 0:
				return false
			return _valid_selection(action.get("indices", []))
		"buy":
			if phase != "shop":
				return false
			var idx := int(action.get("index", -1))
			if idx < 0 or idx >= shop_items.size():
				return false
			var item: Dictionary = shop_items[idx]
			if bool(item.get("bought", false)):
				return false
			if money < int(item["cost"]):
				return false
			if String(item["kind"]) == "joker" and jokers.size() >= JOKER_SLOTS:
				return false
			return true
		"sell":
			if phase != "shop":
				return false
			var slot := int(action.get("slot", -1))
			return slot >= 0 and slot < jokers.size()
		"leave_shop":
			return phase == "shop"
		_:
			return false


func _valid_selection(indices: Variant) -> bool:
	if not (indices is Array):
		return false
	var arr: Array = indices
	if arr.size() < 1 or arr.size() > 5:
		return false
	var seen: Dictionary = {}
	for v in arr:
		var i := int(v)
		if i < 0 or i >= hand.size() or seen.has(i):
			return false
		seen[i] = true
	return true


# =====================================================================
#  Actions — play / discard (blind), buy / sell / leave (shop)
# =====================================================================

## Play the selected 1-5 cards as a poker hand. Scores them, banks the score,
## consumes a hand, removes+refills the cards, grows scaling jokers, and resolves
## the blind (clear -> shop, or fail -> lose). Returns the score breakdown, or {}
## if illegal.
func play(indices: Array) -> Dictionary:
	if not is_legal({"type": "play", "indices": indices}):
		illegal_attempts += 1
		return {}
	var bd := score_breakdown(indices)
	round_score += int(bd["score"])
	last_score = int(bd["score"])
	hands_left -= 1
	var ev: Dictionary = bd["eval"]
	_remove_from_hand(indices)
	_grow_scaling(ev)
	type_play_counts[int(bd["type"])] = int(type_play_counts.get(int(bd["type"]), 0)) + 1
	_refill_hand()
	_log("Play %s -> %d (total %d/%d)" % [String(bd["type_name"]), int(bd["score"]), round_score, current_target])
	if round_score >= current_target:
		_win_blind()
	elif hands_left <= 0:
		_lose_run()
	return bd


## Discard the selected 1-5 cards (consumes a discard) and refill the hand.
func discard(indices: Array) -> bool:
	if not is_legal({"type": "discard", "indices": indices}):
		illegal_attempts += 1
		return false
	discards_left -= 1
	_remove_from_hand(indices)
	_refill_hand()
	_log("Discard %d card(s)." % indices.size())
	return true


func _remove_from_hand(indices: Array) -> void:
	var sorted: Array = indices.duplicate()
	sorted.sort()
	sorted.reverse()  # remove high indices first so lower ones stay valid.
	for i in sorted:
		hand.remove_at(int(i))


## Scaling jokers grow their per-copy counter AFTER a hand resolves (so the
## breakdown used the pre-play value). green grows every hand; runner only on a
## Straight.
func _grow_scaling(ev: Dictionary) -> void:
	for j in jokers:
		var def: Dictionary = JOKER_DB[String(j["id"])]
		var effect := String(def["effect"])
		if effect == "scaling_mult" or effect == "scaling_chips":
			if _contains(ev, String(def["feature"])):
				j["counter"] = int(j["counter"]) + int(def["grow"])


# =====================================================================
#  Blind resolution + shop
# =====================================================================

func _win_blind() -> void:
	# The final ante's boss ends the run in victory (no shop after).
	if ante >= MAX_ANTE and blind_index == 2:
		run_over = true
		run_won = true
		phase = "done"
		_log("BOSS of Ante %d cleared — RUN WON." % ante)
		return
	# Reward: blind payout + $1 per unused hand (capped) + interest (capped).
	var reward: int = BLIND_REWARD[blind_index]
	reward += mini(hands_left, LEFTOVER_HAND_CAP)
	reward += mini(money / INTEREST_PER, INTEREST_CAP)
	money += reward
	last_reward = reward
	_roll_shop()
	phase = "shop"
	_log("Blind cleared — +$%d (now $%d). Shop open." % [reward, money])


func _lose_run() -> void:
	run_over = true
	run_won = false
	phase = "done"
	_log("Failed %s (%d/%d) — RUN LOST." % [BLIND_NAMES[blind_index], round_score, current_target])


func _roll_shop() -> void:
	shop_items = []
	# Offer jokers not already owned, drawn deterministically.
	var pool: Array = []
	for jid in JOKER_DB.keys():
		if not _owns(jid):
			pool.append(String(jid))
	pool.sort()  # stable base order before the seeded shuffle.
	for i in range(pool.size() - 1, 0, -1):
		var k := _rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[k]
		pool[k] = tmp
	for i in mini(SHOP_JOKERS, pool.size()):
		var jid := String(pool[i])
		shop_items.append({"kind": "joker", "id": jid, "cost": int(JOKER_DB[jid]["cost"]), "bought": false})
	# Offer planets (level a specific hand type). Pick distinct types by RNG.
	var types: Array = HAND_BASE.keys()
	var picked: Dictionary = {}
	var guard := 0
	while picked.size() < SHOP_PLANETS and guard < 64:
		guard += 1
		var t := int(types[_rng.randi_range(0, types.size() - 1)])
		if not picked.has(t):
			picked[t] = true
			shop_items.append({"kind": "planet", "type": t, "cost": HAND_UPGRADE_COST, "bought": false})


func _owns(jid: String) -> bool:
	for j in jokers:
		if String(j["id"]) == jid:
			return true
	return false


## Buy shop item `index`. Spends money; a joker fills a slot, a planet levels its
## hand type. Returns true on success.
func buy(index: int) -> bool:
	if not is_legal({"type": "buy", "index": index}):
		illegal_attempts += 1
		return false
	var item: Dictionary = shop_items[index]
	money -= int(item["cost"])
	item["bought"] = true
	if String(item["kind"]) == "joker":
		jokers.append({"id": String(item["id"]), "counter": 0})
		_log("Bought joker %s (-$%d)." % [String(JOKER_DB[String(item["id"])]["name"]), int(item["cost"])])
	else:
		var t := int(item["type"])
		hand_levels[t] = level_of(t) + 1
		_log("Leveled %s to L%d (-$%d)." % [String(TYPE_NAME[t]), level_of(t), int(item["cost"])])
	return true


## Sell the joker in `slot` for half its cost (min $1). Returns true on success.
func sell_joker(slot: int) -> bool:
	if not is_legal({"type": "sell", "slot": slot}):
		illegal_attempts += 1
		return false
	var jid := String(jokers[slot]["id"])
	var refund := maxi(1, int(JOKER_DB[jid]["cost"]) / 2)
	money += refund
	jokers.remove_at(slot)
	_log("Sold %s (+$%d)." % [String(JOKER_DB[jid]["name"]), refund])
	return true


## Leave the shop and start the next blind (advancing ante after the boss).
func leave_shop() -> bool:
	if not is_legal({"type": "leave_shop"}):
		illegal_attempts += 1
		return false
	blind_index += 1
	if blind_index > 2:
		blind_index = 0
		ante += 1
	_begin_blind()
	return true


# =====================================================================
#  Auto-play heuristic (drives a full run headlessly — NOT an opponent)
# =====================================================================

## The best-scoring legal play from the current hand. Enumerates every subset of
## size 1..5, scores each, and keeps the highest (deterministic tie-break: higher
## score, then fewer cards, then lexicographically smallest indices).
func best_play() -> Dictionary:
	var combos := _combinations(hand.size(), 5)
	var best_indices: Array = []
	var best := {}
	var best_score := -1
	for combo in combos:
		var bd := score_breakdown(combo)
		var s := int(bd["score"])
		if s > best_score:
			best_score = s
			best_indices = combo
			best = bd
	return {"indices": best_indices, "score": best_score, "breakdown": best}


## All non-empty subsets of [0..n) with size 1..max_k, in a fixed order (by size
## then lexicographic) so enumeration + tie-breaks are deterministic.
func _combinations(n: int, max_k: int) -> Array:
	var out: Array = []
	var k_cap := mini(max_k, n)
	for k in range(1, k_cap + 1):
		_combos_of_size(n, k, 0, [], out)
	return out


func _combos_of_size(n: int, k: int, start: int, cur: Array, out: Array) -> void:
	if cur.size() == k:
		out.append(cur.duplicate())
		return
	for i in range(start, n):
		cur.append(i)
		_combos_of_size(n, k, i + 1, cur, out)
		cur.pop_back()


## Take one deterministic auto-play step: in a blind, discard weak cards when it
## clearly helps else play the best hand; in a shop, buy one sensible item then
## leave. Drives a whole run when called in a loop.
func auto_take_turn() -> void:
	if run_over:
		return
	if phase == "shop":
		_auto_shop()
		return
	var bp := best_play()
	var bd: Dictionary = bp["breakdown"]
	var type := int(bd["type"])
	# Discard weak hands (high card / pair) while we still have discards AND
	# another hand AND the best play would not already clear the target.
	var would_clear := round_score + int(bp["score"]) >= current_target
	if discards_left > 0 and type <= HandType.PAIR and hands_left > 1 and not would_clear:
		_auto_discard(bd)
	else:
		play(bp["indices"])


## Discard up to 5 of the lowest-rank cards NOT part of the best hand (keeps the
## scoring core, fishes for a better hand). Always discards at least one.
func _auto_discard(best_bd: Dictionary) -> void:
	var keep: Dictionary = {}
	var ev: Dictionary = best_bd["eval"]
	# best_play() indices are into the hand; map its scored subset back to hand.
	var bp_indices: Array = []
	# Recompute best indices are not stored on bd; use a fresh best_play.
	var bp := best_play()
	bp_indices = bp["indices"]
	var scored: Array = ev["scored"]
	for si in scored:
		if int(si) < bp_indices.size():
			keep[int(bp_indices[int(si)])] = true
	# Rank every hand index; drop the lowest that we are not keeping.
	var candidates: Array = []
	for i in hand.size():
		if not keep.has(i):
			candidates.append(i)
	# Sort candidates by rank ascending (discard weakest first).
	candidates.sort_custom(func(a: int, b: int) -> bool:
		return int(hand[a]["rank"]) < int(hand[b]["rank"]))
	var to_discard: Array = []
	for i in mini(5, candidates.size()):
		to_discard.append(candidates[i])
	if to_discard.is_empty():
		# Nothing outside the kept set — discard the single lowest card instead.
		var low := 0
		for i in hand.size():
			if int(hand[i]["rank"]) < int(hand[low]["rank"]):
				low = i
		to_discard.append(low)
	discard(to_discard)


func _auto_shop() -> void:
	# Buy the first affordable joker (slot permitting), else the first affordable
	# planet; then leave. Deterministic.
	var bought := false
	for i in shop_items.size():
		var item: Dictionary = shop_items[i]
		if bool(item.get("bought", false)):
			continue
		if String(item["kind"]) == "joker" and jokers.size() < JOKER_SLOTS and money >= int(item["cost"]):
			buy(i)
			bought = true
			break
	if not bought:
		for i in shop_items.size():
			var item2: Dictionary = shop_items[i]
			if not bool(item2.get("bought", false)) and String(item2["kind"]) == "planet" and money >= int(item2["cost"]):
				buy(i)
				break
	leave_shop()


# =====================================================================
#  Queries for the view
# =====================================================================

func ante_label() -> String:
	return "Ante %d/%d — %s" % [ante, MAX_ANTE, BLIND_NAMES[blind_index]]


func joker_name(slot: int) -> String:
	if slot < 0 or slot >= jokers.size():
		return ""
	return String(JOKER_DB[String(jokers[slot]["id"])]["name"])


func joker_desc(slot: int) -> String:
	if slot < 0 or slot >= jokers.size():
		return ""
	var jid := String(jokers[slot]["id"])
	var d := String(JOKER_DB[jid]["desc"])
	var counter := int(jokers[slot]["counter"])
	if counter != 0:
		d += " (+%d)" % counter
	return d


func card_label(card: Dictionary) -> String:
	var r := int(card["rank"])
	var rs: String
	match r:
		14: rs = "A"
		13: rs = "K"
		12: rs = "Q"
		11: rs = "J"
		10: rs = "T"
		_: rs = str(r)
	var s: String = rs + String(SUIT_GLYPH[int(card["suit"])])
	if String(card["enh"]) != "":
		s += "*"
	return s


func recent_log(n: int = 12) -> Array[String]:
	var out: Array[String] = []
	var start := maxi(0, log_lines.size() - n)
	for i in range(start, log_lines.size()):
		out.append(log_lines[i])
	return out


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 200:
		log_lines.remove_at(0)


# =====================================================================
#  Save / load — the WHOLE run round-trips (deep, JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	return {
		"seed": _seed,
		"rng_state": str(_rng.state),  # uint64 as String (survives JSON).
		"hands_per_blind": _hands_per_blind,
		"discards_per_blind": _discards_per_blind,
		"target_scale": _target_scale,
		"hand_size": _hand_size,
		"ante": ante,
		"blind_index": blind_index,
		"phase": phase,
		"current_target": current_target,
		"round_score": round_score,
		"hands_left": hands_left,
		"discards_left": discards_left,
		"money": money,
		"run_over": run_over,
		"run_won": run_won,
		"deck": deck.duplicate(true),
		"hand": hand.duplicate(true),
		"jokers": jokers.duplicate(true),
		"hand_levels": _int_keyed(hand_levels),
		"type_play_counts": _int_keyed(type_play_counts),
		"shop_items": shop_items.duplicate(true),
		"extra_cards": extra_cards.duplicate(true),
		"last_reward": last_reward,
		"last_score": last_score,
		"illegal_attempts": illegal_attempts,
	}


func from_dict(data: Dictionary) -> void:
	_seed = int(data.get("seed", 0))
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	_hands_per_blind = int(data.get("hands_per_blind", BASE_HANDS))
	_discards_per_blind = int(data.get("discards_per_blind", BASE_DISCARDS))
	_target_scale = float(data.get("target_scale", 1.0))
	_hand_size = int(data.get("hand_size", HAND_SIZE))
	ante = int(data.get("ante", 1))
	blind_index = int(data.get("blind_index", 0))
	phase = String(data.get("phase", "blind"))
	current_target = int(data.get("current_target", 0))
	round_score = int(data.get("round_score", 0))
	hands_left = int(data.get("hands_left", 0))
	discards_left = int(data.get("discards_left", 0))
	money = int(data.get("money", START_MONEY))
	run_over = bool(data.get("run_over", false))
	run_won = bool(data.get("run_won", false))
	deck = _coerce_cards(data.get("deck", []))
	hand = _coerce_cards(data.get("hand", []))
	jokers = []
	for jv in data.get("jokers", []):
		var jd: Dictionary = jv
		jokers.append({"id": String(jd["id"]), "counter": int(jd.get("counter", 0))})
	hand_levels = {}
	for t in HAND_BASE.keys():
		hand_levels[t] = 1
	for k in (data.get("hand_levels", {}) as Dictionary).keys():
		hand_levels[int(k)] = int(data["hand_levels"][k])
	type_play_counts = {}
	for t in HAND_BASE.keys():
		type_play_counts[t] = 0
	for k in (data.get("type_play_counts", {}) as Dictionary).keys():
		type_play_counts[int(k)] = int(data["type_play_counts"][k])
	shop_items = []
	for sv in data.get("shop_items", []):
		var s: Dictionary = sv
		var item := {"kind": String(s["kind"]), "cost": int(s["cost"]), "bought": bool(s.get("bought", false))}
		if String(s["kind"]) == "joker":
			item["id"] = String(s["id"])
		else:
			item["type"] = int(s["type"])
		shop_items.append(item)
	extra_cards = _coerce_cards(data.get("extra_cards", []))
	last_reward = int(data.get("last_reward", 0))
	last_score = int(data.get("last_score", 0))
	illegal_attempts = int(data.get("illegal_attempts", 0))


func _int_keyed(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[int(k)] = int(d[k])
	return out


func _coerce_cards(src: Variant) -> Array:
	var out: Array = []
	for cv in (src as Array):
		var c: Dictionary = cv
		out.append({"rank": int(c["rank"]), "suit": int(c["suit"]), "enh": String(c.get("enh", ""))})
	return out
