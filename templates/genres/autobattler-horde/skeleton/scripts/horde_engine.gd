class_name HordeEngine
extends RefCounted
## Pure, seedable HORDE AUTO-BATTLER engine ("How Many Dudes?"-lineage army-scaler) run as a
## DETERMINISTIC sim: between waves you spend gold to RECRUIT a horde (cheap DUDES + tougher BRUTES
## + rare CHAMPIONS), then your whole army AUTO-BATTLES the wave's enemy army in a deterministic
## focus-fire attrition sim where BOTH numbers AND stats matter (more units = more total DPS AND a
## deeper HP pool to grind through). Survivors persist + heal; clear all waves to WIN, get wiped to
## LOSE. This is a DISTINCT auto-battler flavor from the team-shop `auto-battler` template (that one
## is TFT-lite bench/synergy; this one is army-scaling horde combat). Node-free + Time-free: one
## seeded RNG builds the enemy waves (combat itself is pure arithmetic), so a whole run replays
## BYTE-IDENTICALLY from a seed (FNV-1a checksum). The scene (horde_view.gd) + GameManager wrap this.

# --------------------------------------------------------------------------- #
# Rules
# --------------------------------------------------------------------------- #

const WAVES := 12
const START_GOLD := 30
# unit archetypes: cost / hp / atk
const UNITS := {
	"dude":     {"cost": 3,  "hp": 12, "atk": 3},
	"brute":    {"cost": 8,  "hp": 34, "atk": 7},
	"champion": {"cost": 22, "hp": 90, "atk": 16},
}
const TIER_ORDER := ["dude", "brute", "champion"]

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var rng := RandomNumberGenerator.new()
var wave := 1
var gold := START_GOLD
var army: Array = []                 ## player units: {kind, hp, maxhp, atk}
var last_enemy_size := 0
var last_survivors := 0
var last_result := ""
var game_over := false
var won := false
var log_lines: Array = []

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	wave = 1
	gold = START_GOLD
	army = []
	last_enemy_size = 0
	last_survivors = 0
	last_result = ""
	game_over = false
	won = false
	log_lines = []

func _make_unit(kind: String) -> Dictionary:
	var u: Dictionary = UNITS[kind]
	return {"kind": kind, "hp": int(u.hp), "maxhp": int(u.hp), "atk": int(u.atk)}

func army_size() -> int:
	return army.size()

func army_power() -> int:
	var p := 0
	for u in army:
		p += int(u.atk)
	return p

func count_of(kind: String) -> int:
	var n := 0
	for u in army:
		if str(u.kind) == kind:
			n += 1
	return n

# --------------------------------------------------------------------------- #
# Recruiting (player OR ai)
# --------------------------------------------------------------------------- #

func can_buy(kind: String) -> bool:
	return not game_over and UNITS.has(kind) and gold >= int(UNITS[kind].cost)

func recruit(kind: String) -> bool:
	if not can_buy(kind):
		return false
	gold -= int(UNITS[kind].cost)
	army.append(_make_unit(kind))
	return true

# --------------------------------------------------------------------------- #
# Enemy waves + the auto-battle (deterministic focus-fire attrition)
# --------------------------------------------------------------------------- #

func _build_enemy(w: int) -> Array:
	# a gold-equivalent budget that scales with the wave, spent mostly on dudes early and on
	# brutes/champions as the wave climbs.
	var budget := 8 + w * 6
	var out: Array = []
	var guard := 0
	while budget >= int(UNITS["dude"].cost) and guard < 4000:
		guard += 1
		var roll := rng.randf()
		var kind := "dude"
		if w >= 8 and roll < 0.18 and budget >= int(UNITS["champion"].cost):
			kind = "champion"
		elif w >= 3 and roll < 0.45 and budget >= int(UNITS["brute"].cost):
			kind = "brute"
		budget -= int(UNITS[kind].cost)
		out.append(_make_unit(kind))
	return out

## Focus-fire attrition: each tick, the SUM of a side's atk hits the OTHER side's front unit; a
## front that drops to <=0 is removed and the next unit becomes the front. Pure + deterministic.
## Returns {player_win, survivors}. Mutates the passed arrays' hp (copies made by caller).
func _battle(pa: Array, ea: Array) -> Dictionary:
	var pi := 0
	var ei := 0
	var p_atk := 0
	for u in pa:
		p_atk += int(u.atk)
	var e_atk := 0
	for u in ea:
		e_atk += int(u.atk)
	var guard := 0
	while pi < pa.size() and ei < ea.size() and guard < 200000:
		guard += 1
		ea[ei].hp = int(ea[ei].hp) - p_atk
		pa[pi].hp = int(pa[pi].hp) - e_atk
		while ei < ea.size() and int(ea[ei].hp) <= 0:
			e_atk -= int(ea[ei].atk)
			ei += 1
		while pi < pa.size() and int(pa[pi].hp) <= 0:
			p_atk -= int(pa[pi].atk)
			pi += 1
	var survivors: Array = []
	for k in range(pi, pa.size()):
		survivors.append(pa[k])
	return {"player_win": pi < pa.size(), "survivors": survivors}

## Fight the current wave with the current army. Survivors persist (healed to full); win the wave
## for a gold reward + interest, or get wiped and lose.
func fight_wave() -> void:
	if game_over:
		return
	# deep-copy both armies so the sim mutates copies (save/replay stays clean)
	var pa: Array = []
	for u in army:
		pa.append({"kind": u.kind, "hp": int(u.maxhp), "maxhp": int(u.maxhp), "atk": int(u.atk)})
	var ea := _build_enemy(wave)
	last_enemy_size = ea.size()
	var res := _battle(pa, ea)
	if bool(res.player_win):
		# survivors persist + heal to full
		army = []
		for u in (res.survivors as Array):
			army.append({"kind": u.kind, "hp": int(u.maxhp), "maxhp": int(u.maxhp), "atk": int(u.atk)})
		last_survivors = army.size()
		last_result = "won"
		var reward := 16 + wave * 7 + mini(gold / 10, 8)     # clear reward + interest (outpaces the enemy curve → the horde snowballs)
		gold += reward
		_log("Wave %d cleared: %d survivors, +%d gold (now %d)" % [wave, last_survivors, reward, gold])
		wave += 1
		if wave > WAVES:
			game_over = true
			won = true
			_log("All %d waves cleared — victory!" % WAVES)
	else:
		army = []
		last_survivors = 0
		last_result = "lost"
		game_over = true
		won = false
		_log("Wave %d: the horde was wiped out." % wave)

# --------------------------------------------------------------------------- #
# Deterministic commander auto-seat (probe / demo) — the "how many dudes" strategy
# --------------------------------------------------------------------------- #

## Spend the round's gold: a couple of brutes for a front-line HP wall, an occasional champion
## when flush, then pile the rest into DUDES (max total DPS per gold). Then fight.
func ai_round() -> void:
	if game_over:
		return
	# a champion anchor when we're flush and don't have many
	if gold >= 50 and count_of("champion") < 1 + wave / 4:
		recruit("champion")
	# a modest brute front line (leaves plenty of gold for the horde)
	while gold >= 12 and count_of("brute") < 1 + wave / 2:
		if not recruit("brute"):
			break
	# HOW MANY DUDES: dump the rest into cheap dudes
	while recruit("dude"):
		pass
	fight_wave()

func auto_play_to_end() -> void:
	var guard := 0
	while not game_over and guard < WAVES + 4:
		ai_round()
		guard += 1
	if not game_over:
		game_over = true

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 24:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	var s := "%d|%d|%d|%d|%d|%d|%d|%d" % [wave, gold, army.size(), army_power(), last_enemy_size,
		last_survivors, int(game_over), int(won)]
	for kind in TIER_ORDER:
		s += "|%s%d" % [kind, count_of(kind)]
	for ch in s.to_utf8_buffer():
		h = (h ^ int(ch)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {"version": 1, "wave": wave, "gold": gold, "army": army.duplicate(true),
		"last_enemy_size": last_enemy_size, "last_survivors": last_survivors, "last_result": last_result,
		"game_over": game_over, "won": won, "seed": int(rng.seed), "rng_state": int(rng.state)}

func load_data(d: Dictionary) -> void:
	wave = int(d.get("wave", 1))
	gold = int(d.get("gold", START_GOLD))
	army = (d.get("army", []) as Array).duplicate(true)
	last_enemy_size = int(d.get("last_enemy_size", 0))
	last_survivors = int(d.get("last_survivors", 0))
	last_result = str(d.get("last_result", ""))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng_state", rng.state))
