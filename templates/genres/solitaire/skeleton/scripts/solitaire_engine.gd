class_name SolitaireEngine
extends RefCounted
## Pure, seedable KLONDIKE SOLITAIRE engine run as a DETERMINISTIC sim: a seeded 52-card shuffle
## deals the classic 7-column tableau (1..7 cards, only the top of each face-up), a 24-card stock,
## a waste pile, and 4 foundations (build A->K by suit). You draw from stock, build alternating-
## colour descending runs across the tableau, uncover face-down cards, and race all 52 cards home
## to the foundations. Node-free + Time-free: the whole game is integer card state driven by one
## seeded RNG, so it replays BYTE-IDENTICALLY from a seed (FNV-1a checksum over the state). The
## scene (solitaire_view.gd) + GameManager wrap this; all rules live here (NoxDev ABI).

# Cards are ints 0..51:  suit = card / 13  (0=clubs,1=diamonds,2=hearts,3=spades) ; rank = card % 13 (0=A..12=K)

const DRAW_COUNT := 1              ## draw-1 Klondike (the solvable/friendly default)
const REDEAL_CAP := 6             ## unlimited-redeal solitaire, bounded so the solver terminates

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var tableau: Array = []            ## 7 columns; each = Array of {"card":int, "up":bool}
var stock: Array = []              ## face-down draw pile (ints)
var waste: Array = []              ## face-up pile (ints; top = last)
var foundations: Array = []        ## 4 entries: top rank present per suit (-1 = empty)
var moves := 0
var redeals := 0
var won := false
var stuck := false
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Card helpers
# --------------------------------------------------------------------------- #

func suit_of(card: int) -> int:
	return card / 13

func rank_of(card: int) -> int:
	return card % 13

func is_red(card: int) -> bool:
	var s := suit_of(card)
	return s == 1 or s == 2

func opposite_color(a: int, b: int) -> bool:
	return is_red(a) != is_red(b)

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	var deck: Array = []
	for c in range(52):
		deck.append(c)
	# Fisher-Yates with the seeded RNG
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = deck[i]; deck[i] = deck[j]; deck[j] = t
	tableau = []
	var idx := 0
	for col in range(7):
		var column: Array = []
		for row in range(col + 1):
			column.append({"card": int(deck[idx]), "up": row == col})
			idx += 1
		tableau.append(column)
	stock = []
	while idx < 52:
		stock.append(int(deck[idx]))
		idx += 1
	waste = []
	foundations = [-1, -1, -1, -1]
	moves = 0
	redeals = 0
	won = false
	stuck = false
	log_lines = []

func foundation_total() -> int:
	var n := 0
	for f in foundations:
		n += int(f) + 1
	return n

func _check_won() -> void:
	if foundation_total() == 52:
		won = true
		_log("Solved in %d moves, %d redeals" % [moves, redeals])

func _auto_flip(col: int) -> void:
	var column: Array = tableau[col]
	if column.size() > 0 and not bool(column[column.size() - 1].up):
		column[column.size() - 1].up = true

# --------------------------------------------------------------------------- #
# Move legality + application
# --------------------------------------------------------------------------- #

func can_to_foundation(card: int) -> bool:
	return rank_of(card) == int(foundations[suit_of(card)]) + 1

func _put_foundation(card: int) -> void:
	foundations[suit_of(card)] = rank_of(card)

## Can `card` be placed on tableau column `col`? (empty accepts only a King; else opposite-colour, rank-1)
func can_place_on(card: int, col: int) -> bool:
	var column: Array = tableau[col]
	if column.is_empty():
		return rank_of(card) == 12
	var top = column[column.size() - 1]
	if not bool(top.up):
		return false
	return opposite_color(card, int(top.card)) and rank_of(card) == rank_of(int(top.card)) - 1

## Smallest index in `col` starting a valid, all-face-up, alternating descending run to the end.
func run_start(col: int) -> int:
	var column: Array = tableau[col]
	if column.is_empty():
		return -1
	var i := column.size() - 1
	while i > 0:
		var cur = column[i]
		var prev = column[i - 1]
		if not bool(prev.up):
			break
		if opposite_color(int(prev.card), int(cur.card)) and rank_of(int(prev.card)) == rank_of(int(cur.card)) + 1:
			i -= 1
		else:
			break
	# ensure the run head itself is face-up
	while i < column.size() and not bool(column[i].up):
		i += 1
	return i

# ---- concrete moves (each returns true if it applied) ---- #

func draw() -> bool:
	if stock.is_empty():
		if waste.is_empty() or redeals >= REDEAL_CAP:
			return false
		# recycle the waste back into the stock (face down, order reversed)
		while not waste.is_empty():
			stock.append(int(waste.pop_back()))
		redeals += 1
		moves += 1
		return true
	for _i in range(DRAW_COUNT):
		if stock.is_empty():
			break
		waste.append(int(stock.pop_back()))
	moves += 1
	return true

func waste_to_foundation() -> bool:
	if waste.is_empty():
		return false
	var card := int(waste[waste.size() - 1])
	if can_to_foundation(card):
		waste.pop_back()
		_put_foundation(card)
		moves += 1
		_check_won()
		return true
	return false

func waste_to_tableau(col: int) -> bool:
	if waste.is_empty():
		return false
	var card := int(waste[waste.size() - 1])
	if can_place_on(card, col):
		waste.pop_back()
		tableau[col].append({"card": card, "up": true})
		moves += 1
		return true
	return false

func tableau_to_foundation(col: int) -> bool:
	var column: Array = tableau[col]
	if column.is_empty():
		return false
	var card := int(column[column.size() - 1].card)
	if bool(column[column.size() - 1].up) and can_to_foundation(card):
		column.pop_back()
		_put_foundation(card)
		_auto_flip(col)
		moves += 1
		_check_won()
		return true
	return false

## Move the run starting at `src`'s index `start` onto column `dst`.
func tableau_to_tableau(src: int, start: int, dst: int) -> bool:
	if src == dst or start < 0:
		return false
	var column: Array = tableau[src]
	if start >= column.size() or not bool(column[start].up):
		return false
	var head := int(column[start].card)
	if not can_place_on(head, dst):
		return false
	var moving: Array = []
	for i in range(start, column.size()):
		moving.append(column[i])
	for _i in range(moving.size()):
		column.pop_back()
	for m in moving:
		tableau[dst].append(m)
	_auto_flip(src)
	moves += 1
	return true

# --------------------------------------------------------------------------- #
# Deterministic greedy solver auto-seat (probe / demo)
# --------------------------------------------------------------------------- #

## A card is SAFE to auto-play home when it can never be needed to park an opposite-colour card:
## both opposite-colour foundations are already at least rank-1 (aces/twos are always safe).
func _safe_home(card: int) -> bool:
	var r := rank_of(card)
	if r <= 1:
		return true
	var reds := [1, 2]
	var blacks := [0, 3]
	var opp: Array = blacks if is_red(card) else reds
	return int(foundations[opp[0]]) >= r - 1 and int(foundations[opp[1]]) >= r - 1

## Try one genuinely useful move (priority order). Returns true if it changed the board.
func _useful_move() -> bool:
	# 1) safe foundation plays (waste, then tableau tops)
	if not waste.is_empty() and _safe_home(int(waste[waste.size() - 1])) and waste_to_foundation():
		return true
	for col in range(7):
		var column: Array = tableau[col]
		if not column.is_empty() and bool(column[column.size() - 1].up):
			if _safe_home(int(column[column.size() - 1].card)) and tableau_to_foundation(col):
				return true
	# 2) tableau->tableau moves that UNCOVER a face-down card or empty a column usefully
	for src in range(7):
		var start := run_start(src)
		if start <= 0:
			continue      # start==0 means moving the whole column (no uncover) — skip unless King-to-empty below
		# only worthwhile if the card just under the run is face-down (uncover)
		if bool(tableau[src][start - 1].up):
			continue
		for dst in range(7):
			if dst != src and tableau_to_tableau(src, start, dst):
				return true
	# 3) waste -> tableau (valid stack; reduces the waste and may enable a foundation play)
	for col in range(7):
		if waste_to_tableau(col):
			return true
	# 4) move a King run onto an empty column if it uncovers a face-down card
	for src in range(7):
		var start2 := run_start(src)
		if start2 <= 0:
			continue
		if rank_of(int(tableau[src][start2].card)) != 12:
			continue
		if bool(tableau[src][start2 - 1].up):
			continue
		for dst in range(7):
			if dst != src and tableau[dst].is_empty() and tableau_to_tableau(src, start2, dst):
				return true
	return false

## Last-resort: force ANY foundation play (even if not "safe") to break a stall.
func _force_home() -> bool:
	if not waste.is_empty() and waste_to_foundation():
		return true
	for col in range(7):
		if tableau_to_foundation(col):
			return true
	return false

func auto_step() -> bool:
	if won or stuck:
		return false
	if _useful_move():
		return true
	if draw():
		return true
	if _force_home():
		return true
	stuck = true
	return false

func auto_play_to_end() -> void:
	var guard := 0
	var dry := 0
	while not won and not stuck and guard < 20000:
		var before := foundation_total()
		if not auto_step():
			break
		guard += 1
		# stall detection: many actions with no foundation progress AND stock cycled
		if foundation_total() > before:
			dry = 0
		else:
			dry += 1
			if dry > 260:
				stuck = true
	if not won:
		stuck = true

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 20:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d|%d" % [moves, redeals, int(won), int(stuck),
		int(foundations[0]) + 1, int(foundations[1]) + 1, foundation_total()]
	s += "|F%d,%d,%d,%d" % [int(foundations[0]), int(foundations[1]), int(foundations[2]), int(foundations[3])]
	for col in range(tableau.size()):
		s += "|T"
		for e in tableau[col]:
			s += "%d%s," % [int(e.card), ("u" if bool(e.up) else "d")]
	s += "|S"
	for c in stock:
		s += "%d," % int(c)
	s += "|W"
	for c in waste:
		s += "%d," % int(c)
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	var tab: Array = []
	for col in tableau:
		var cc: Array = []
		for e in col:
			cc.append({"card": int(e.card), "up": bool(e.up)})
		tab.append(cc)
	return {"version": 1, "tableau": tab, "stock": stock.duplicate(), "waste": waste.duplicate(),
		"foundations": foundations.duplicate(), "moves": moves, "redeals": redeals,
		"won": won, "stuck": stuck, "seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	tableau = []
	for col in (d.get("tableau", []) as Array):
		var cc: Array = []
		for e in (col as Array):
			cc.append({"card": int(e.card), "up": bool(e.up)})
		tableau.append(cc)
	stock = (d.get("stock", []) as Array).duplicate()
	waste = (d.get("waste", []) as Array).duplicate()
	foundations = (d.get("foundations", [-1, -1, -1, -1]) as Array).duplicate()
	moves = int(d.get("moves", 0))
	redeals = int(d.get("redeals", 0))
	won = bool(d.get("won", false))
	stuck = bool(d.get("stuck", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
