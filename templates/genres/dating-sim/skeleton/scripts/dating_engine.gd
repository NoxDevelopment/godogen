class_name DatingEngine
extends RefCounted
## Pure, seedable DATING-SIM engine (Persona-social-link / stat-raiser lineage): raise player
## STATS through daily activities, spend a CALENDAR pursuing romanceable CHARACTERS via DATES +
## GIFTS matched to their seeded PREFERENCES, cross AFFECTION thresholds to unlock milestone
## events, and CONFESS to complete a route. It is a SYSTEMS template — it models the dating-sim
## MECHANICS (stats/affection/calendar/gifts/routes/endings) and exposes a `mature_content`
## GATING FLAG (off by default) that only unlocks EMPTY mature-event HOOKS; it ships NO explicit
## content. Node-free + Time-free: one seeded RNG sets the characters + daily mood, so a whole
## playthrough replays BYTE-IDENTICALLY from a seed (FNV-1a checksum). The scene (dating_view.gd)
## + GameManager wrap this; all rules live here (NoxDev ABI).

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

const SEMESTER := 40                ## days in a playthrough
const STATS := ["charm", "wit", "fitness"]
const GIFTS := {"flowers": 40, "book": 30, "chocolate": 25, "gadget": 80, "plush": 45}
const DATES := {"cafe": "charm", "gym": "fitness", "museum": "wit", "park": "charm", "concert": "wit"}
const NAMES := ["Aria", "Kai", "Nova", "Sage", "Ren", "Yuki", "Milo", "Iris"]
const CONFESS_AT := 90
const MILESTONES := [30, 60, 90]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var stats := {}                     ## stat → 0..100
var money := 0
var day := 1
var chars: Array = []               ## {name, liked_stat, liked_gift, pref_date, affection, milestones, confessed}
var mature_content := false         ## gating flag — OFF by default; unlocks empty hooks only
var route_done := false
var partner := ""                   ## the character whose route completed
var game_over := false
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	stats = {}
	for s in STATS:
		stats[s] = 10.0 + float(rng.randi_range(0, 10))
	money = 120
	day = 1
	chars = []
	var used := {}
	var stat_keys := STATS
	var gift_keys := GIFTS.keys()
	var date_keys := DATES.keys()
	for i in range(3):
		var name := _pick_name(used)
		chars.append({
			"name": name,
			"liked_stat": str(stat_keys[rng.randi_range(0, stat_keys.size() - 1)]),
			"liked_gift": str(gift_keys[rng.randi_range(0, gift_keys.size() - 1)]),
			"pref_date": str(date_keys[rng.randi_range(0, date_keys.size() - 1)]),
			"affection": 0.0, "milestones": 0, "confessed": false,
		})
	mature_content = false
	route_done = false
	partner = ""
	game_over = false
	log_lines = []

func _pick_name(used: Dictionary) -> String:
	for _t in range(30):
		var n: String = NAMES[rng.randi_range(0, NAMES.size() - 1)]
		if not used.has(n):
			used[n] = true
			return n
	return NAMES[rng.randi_range(0, NAMES.size() - 1)]

func char_by_name(name: String) -> Dictionary:
	for c in chars:
		if str(c.name) == name:
			return c
	return {}

# --------------------------------------------------------------------------- #
# Daily actions (each advances the calendar by one day)
# --------------------------------------------------------------------------- #

## Raise one stat through an activity.
func train(stat: String) -> bool:
	if game_over or not (stat in STATS):
		return false
	stats[stat] = minf(100.0, float(stats[stat]) + 8.0 + float(rng.randi_range(0, 3)))
	_end_day("trained %s" % stat)
	return true

## Earn spending money.
func work() -> bool:
	if game_over:
		return false
	money += 60
	_end_day("worked (+$60)")
	return true

## Go on a date with a character — affection rises with base + a preference/stat bonus.
func go_on_date(name: String, date_kind: String) -> bool:
	if game_over:
		return false
	var c := char_by_name(name)
	if c.is_empty() or not (date_kind in DATES):
		return false
	var gain := 6.0
	# their preferred date type is a big bonus
	if date_kind == str(c.pref_date):
		gain += 9.0
	# meeting their valued stat lands better as the relationship deepens
	var need := 30.0 + float(c.affection) * 0.5
	if float(stats[str(c.liked_stat)]) >= need:
		gain += 10.0
	# a little seeded daily variance
	gain += float(rng.randi_range(-2, 3))
	c.affection = minf(100.0, float(c.affection) + maxf(1.0, gain))
	_check_milestones(c)
	_end_day("%s date with %s (aff %.0f)" % [date_kind, name, float(c.affection)])
	return true

## Give a gift (costs money) — a liked gift is worth much more.
func give_gift(name: String, gift: String) -> bool:
	if game_over:
		return false
	var c := char_by_name(name)
	if c.is_empty() or not (gift in GIFTS):
		return false
	var cost: int = int(GIFTS[gift])
	if money < cost:
		return false
	money -= cost
	var gain := 14.0 if gift == str(c.liked_gift) else 5.0
	c.affection = minf(100.0, float(c.affection) + gain)
	_check_milestones(c)
	_end_day("gave %s a %s (aff %.0f)" % [name, gift, float(c.affection)])
	return true

## Confess — only at CONFESS_AT affection; completes that character's route.
func confess(name: String) -> bool:
	if game_over:
		return false
	var c := char_by_name(name)
	if c.is_empty() or float(c.affection) < float(CONFESS_AT) or bool(c.confessed):
		return false
	c.confessed = true
	route_done = true
	partner = name
	_log("Confessed to %s — a route is complete!" % name)
	# mature epilogue is a GATED, EMPTY hook — no content ships in the template
	if mature_content:
		_log("(mature epilogue hook unlocked — author your own gated scene here)")
	game_over = true
	return true

func _check_milestones(c: Dictionary) -> void:
	while int(c.milestones) < MILESTONES.size() and float(c.affection) >= float(MILESTONES[int(c.milestones)]):
		c.milestones = int(c.milestones) + 1
		var lvl: int = int(MILESTONES[int(c.milestones) - 1])
		_log("Milestone with %s at affection %d!" % [str(c.name), lvl])
		if lvl >= 90 and mature_content:
			_log("(mature milestone hook available for %s — gated + empty)" % str(c.name))

func _end_day(what: String) -> void:
	_log("Day %d: %s" % [day, what])
	day += 1
	if day > SEMESTER and not game_over:
		game_over = true
		_log("The semester ended%s" % ("" if route_done else " with no confession"))

# --------------------------------------------------------------------------- #
# Heuristic auto-play seat (probe / demo) — pursue the most promising character
# --------------------------------------------------------------------------- #

func _target() -> Dictionary:
	# pick the character we're furthest along with (ties → first)
	var best := {}
	var bv := -1.0
	for c in chars:
		if float(c.affection) > bv:
			bv = float(c.affection)
			best = c
	return best if not best.is_empty() else (chars[0] if chars.size() > 0 else {})

func auto_step() -> void:
	if game_over:
		return
	var t := _target()
	if t.is_empty():
		work()
		return
	# ready to confess?
	if float(t.affection) >= float(CONFESS_AT):
		confess(str(t.name))
		return
	# make sure we can land the stat bonus on dates
	var ls := str(t.liked_stat)
	var need := 30.0 + float(t.affection) * 0.5
	if float(stats[ls]) < need + 5.0 and float(stats[ls]) < 100.0:
		train(ls)
		return
	# a liked gift is efficient affection — buy one when we can afford it
	var lg := str(t.liked_gift)
	if money >= int(GIFTS[lg]):
		give_gift(str(t.name), lg)
		return
	# otherwise take them on their favourite date (earn money if we're broke and can't date well)
	if money < 30 and float(t.affection) < 20.0:
		work()
		return
	go_on_date(str(t.name), str(t.pref_date))

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < SEMESTER + 4:
		auto_step()
		guard += 1

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

func _q(v: float) -> int:
	return int(round(v))

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%s|%d" % [day, money, int(game_over), int(route_done), partner, int(mature_content)]
	for st in STATS:
		s += "|S%s%d" % [st, _q(stats[st])]
	for c in chars:
		s += "|C%s,%d,%d,%d" % [str(c.name), _q(c.affection), int(c.milestones), int(c.confessed)]
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"version": 1, "stats": stats.duplicate(), "money": money, "day": day,
		"chars": chars.duplicate(true), "mature_content": mature_content, "route_done": route_done,
		"partner": partner, "game_over": game_over, "seed": int(rng.seed), "rng_state": int(rng.state),
	}

func load_data(d: Dictionary) -> void:
	stats = (d.get("stats", {}) as Dictionary).duplicate()
	money = int(d.get("money", 0))
	day = int(d.get("day", 1))
	chars = (d.get("chars", []) as Array).duplicate(true)
	mature_content = bool(d.get("mature_content", false))
	route_done = bool(d.get("route_done", false))
	partner = str(d.get("partner", ""))
	game_over = bool(d.get("game_over", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
