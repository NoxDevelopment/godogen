extends RefCounted
class_name CosmicEngine
## res://scripts/cosmic_engine.gd
## The PURE, seedable, headless-testable engine for a CO-OP cosmic-horror
## investigation board game (Eldritch Horror / Arkham Horror lineage — OUR OWN
## generic genre engine, no trademarked content). 1-4 INVESTIGATORS play as ONE
## TEAM and race to solve MYSTERIES before DOOM consumes the world. There is NO
## Godot node dependency in here — it is plain data + rules, so the whole game
## replays byte-identically from a seed and can be driven with no UI at all.
## GameManager owns one instance, adds the autoload ABI + save, and drives the
## turn dispatcher; the board only reads state and forwards a human's action.
##
## THE MODEL (why it is a real co-op engine, not an abstraction):
##   * INVESTIGATORS — each has 5 SKILLS (lore/influence/observation/strength/
##     will, 1-5), a HEALTH pool and a SANITY pool (either at 0 => that
##     investigator is DEFEATED and stops acting), an inventory of CLUES + ASSETS,
##     and a current LOCATION. >=6 distinct archetypes with different spreads.
##   * WORLD MAP — an undirected graph of 9 named LOCATIONS; some are GATE spots,
##     some are CLUE sites, some are SAFE towns. Investigators move along edges.
##   * GLOBAL TRACKS — DOOM (starts high, ticks DOWN on ominous mythos; LOST at 0)
##     and MYSTERY progress (solve N mysteries — default 3 — to WIN). A MYTHOS
##     deck (>=12 cards) drives the antagonist automatically every round.
##   * ROUND STRUCTURE — (1) ACTION phase: each investigator takes 2 actions from
##     {move, rest, acquire, prepare, trade, spend_clue}; (2) ENCOUNTER phase:
##     each investigator resolves an encounter at their location -> a SKILL CHECK;
##     (3) MYTHOS phase: automated — advance doom, spawn gates + monsters, apply a
##     global effect.
##   * SKILL CHECKS (core mechanic) — roll a dice pool of size = tested skill (+
##     asset/focus bonuses); each die is a SUCCESS on a threshold (5-6 on a d6);
##     the check PASSES at >= required successes; CLUES may be spent to reroll
##     failed dice. Failure costs health/sanity or advances doom. This is the one
##     reusable resolver (resolve_from_rolls / perform_check).
##   * MONSTERS — spawn from gates, hunt the nearest investigator, force COMBAT
##     (strength OR will check). Losing costs health/sanity; defeating yields a
##     clue reward. >=6 monster types with different stats.
##   * MYSTERIES — >=5 cards, each solved by a CONCRETE condition (invest K clues +
##     pass a check, defeat a target monster, or close X gates). Solve N to WIN.
##     Doom 0, ALL investigators defeated, or too many gates open = LOSS.
##   * CO-OP SEAT CONTROLLERS — all investigators are ONE team; each seat is
##     HUMAN_LOCAL or AI_AUTOPILOT (a genuine heuristic that plays an investigator
##     toward the shared objective). Deterministic. AI_LLM / REMOTE are documented
##     FUTURE seams (one enum value each) that fail LOUD if used — NOT stubbed.

# =====================================================================
#  Static rules / tuning (auditable constants — swap for your own game)
# =====================================================================

const SKILLS: Array[String] = ["lore", "influence", "observation", "strength", "will"]

## Dice model. A d6; a die is a SUCCESS at >= SUCCESS_THRESHOLD (5 or 6 => ~1/3).
const DIE_FACES := 6
const SUCCESS_THRESHOLD := 5

## Each investigator takes this many actions in the ACTION phase.
const ACTIONS_PER_TURN := 2

## Win / loss thresholds (defaults; difficulty presets override doom/gate/threat).
const MYSTERIES_TO_WIN := 3
const MAX_ROUNDS := 40          ## hard safety cap — if hit, the vigil is lost.
const FOCUS_MAX := 2            ## prepare stacks up to this many bonus dice.
const INVENTORY_MAX := 4        ## assets an investigator may hold.
const CLUE_CARRY_MAX := 8       ## clues an investigator may hold.

## The action names available in the ACTION phase.
const ACTIONS: Array[String] = ["move", "rest", "acquire", "prepare", "trade", "spend_clue"]

## Difficulty presets. The RULES are identical across presets — only the starting
## DOOM, the gate overflow limit, and the THREAT multiplier (monster toughness +
## mythos severity + spawn count) change. This is why BOTH a win (favorable) and a
## loss (harsh) are genuinely reachable without any hardcoding of the outcome.
const DIFFICULTY := {
	"normal": {"doom_start": 16, "gate_limit": 8, "threat": 1.0, "start_health_mod": 0, "start_sanity_mod": 0},
	"harsh":  {"doom_start": 5,  "gate_limit": 4, "threat": 2.0, "start_health_mod": -2, "start_sanity_mod": -2},
}

# ---------------------------------------------------------------------
#  World map — 9 locations, an undirected connection graph.
#  kind: "safe" (acquire assets, rest is always allowed), "clue" (an investigate
#  encounter yields a clue), "gate" (mythos opens gates + spawns monsters here).
#  A location may be BOTH a clue site and a gate spot (see flags).
# ---------------------------------------------------------------------
const LOCATIONS := {
	"town_square":  {"name": "Town Square",       "safe": true,  "clue": false, "gate": false},
	"university":   {"name": "University",         "safe": false, "clue": true,  "gate": false},
	"old_library":  {"name": "Old Library",        "safe": false, "clue": true,  "gate": false},
	"old_church":   {"name": "Old Church",         "safe": true,  "clue": false, "gate": false},
	"harbor":       {"name": "Fog-Bound Harbor",   "safe": false, "clue": false, "gate": true},
	"rail_station": {"name": "Rail Station",        "safe": true,  "clue": false, "gate": false},
	"asylum":       {"name": "Old Asylum",          "safe": false, "clue": false, "gate": true},
	"observatory":  {"name": "Hilltop Observatory", "safe": false, "clue": true,  "gate": true},
	"black_woods":  {"name": "The Black Woods",      "safe": false, "clue": true,  "gate": true},
}

## Undirected adjacency (both directions declared for O(1) lookup / clarity).
const MAP_EDGES := {
	"town_square":  ["university", "old_church", "rail_station"],
	"university":   ["town_square", "old_library", "observatory"],
	"old_library":  ["university", "old_church"],
	"old_church":   ["town_square", "old_library", "harbor"],
	"harbor":       ["old_church", "rail_station", "black_woods"],
	"rail_station": ["town_square", "harbor", "asylum"],
	"asylum":       ["rail_station", "observatory"],
	"observatory":  ["university", "asylum", "black_woods"],
	"black_woods":  ["harbor", "observatory"],
}

## Where investigators begin (cycled if fewer/more investigators).
const START_LOCATIONS: Array[String] = ["town_square", "old_church", "rail_station", "town_square"]

# ---------------------------------------------------------------------
#  Investigator archetypes (>=6). skills sum ~15; health+sanity ~12.
# ---------------------------------------------------------------------
const ARCHETYPES := {
	"scholar":   {"name": "The Scholar",   "skills": {"lore": 5, "influence": 2, "observation": 3, "strength": 1, "will": 4}, "health": 5, "sanity": 7, "asset": "tome_of_shadows"},
	"detective": {"name": "The Detective", "skills": {"lore": 2, "influence": 3, "observation": 5, "strength": 3, "will": 3}, "health": 6, "sanity": 6, "asset": "lantern"},
	"soldier":   {"name": "The Soldier",   "skills": {"lore": 1, "influence": 2, "observation": 3, "strength": 5, "will": 3}, "health": 8, "sanity": 4, "asset": "revolver"},
	"occultist": {"name": "The Occultist", "skills": {"lore": 4, "influence": 2, "observation": 2, "strength": 2, "will": 5}, "health": 4, "sanity": 8, "asset": "ward_charm"},
	"doctor":    {"name": "The Doctor",    "skills": {"lore": 3, "influence": 5, "observation": 3, "strength": 2, "will": 3}, "health": 6, "sanity": 6, "asset": "medkit"},
	"reporter":  {"name": "The Reporter",  "skills": {"lore": 3, "influence": 4, "observation": 4, "strength": 2, "will": 2}, "health": 5, "sanity": 6, "asset": "field_notes"},
	"drifter":   {"name": "The Drifter",   "skills": {"lore": 2, "influence": 3, "observation": 3, "strength": 4, "will": 4}, "health": 7, "sanity": 5, "asset": ""},
	"priest":    {"name": "The Priest",    "skills": {"lore": 4, "influence": 3, "observation": 2, "strength": 2, "will": 5}, "health": 6, "sanity": 7, "asset": "ward_charm"},
}

## Default lineup used when no explicit archetype list is passed to setup().
const DEFAULT_LINEUP: Array[String] = ["scholar", "detective", "soldier", "doctor"]

# ---------------------------------------------------------------------
#  Assets (>=6). skill_bonus adds to matching checks; rest_bonus heals extra on
#  rest. A small deck drawn by the "acquire" action at a safe location.
# ---------------------------------------------------------------------
const ASSET_DB := {
	"revolver":        {"name": "Revolver",         "skill_bonus": {"strength": 2}, "rest_bonus": 0},
	"tome_of_shadows": {"name": "Tome of Shadows",  "skill_bonus": {"lore": 2},     "rest_bonus": 0},
	"lantern":         {"name": "Storm Lantern",    "skill_bonus": {"observation": 2}, "rest_bonus": 0},
	"ward_charm":      {"name": "Ward Charm",       "skill_bonus": {"will": 2},     "rest_bonus": 0},
	"field_notes":     {"name": "Field Notes",      "skill_bonus": {"lore": 1, "influence": 1}, "rest_bonus": 0},
	"medkit":          {"name": "Medical Kit",      "skill_bonus": {"influence": 1}, "rest_bonus": 1},
	"old_key":         {"name": "Rusted Key",       "skill_bonus": {"will": 1, "observation": 1}, "rest_bonus": 0},
	"blessed_knife":   {"name": "Blessed Knife",    "skill_bonus": {"strength": 1, "will": 1}, "rest_bonus": 0},
}

## The acquire deck: 2 copies of each asset, shuffled by the seeded RNG.
const ASSET_COPIES := 2

# ---------------------------------------------------------------------
#  Monsters (>=6). toughness=hit points; check=skill tested to fight; required=
#  successes to hurt it; damage=health lost on a failed fight; horror=sanity lost;
#  reward_clues=clues gained by whoever lands the killing blow; speed=steps/round.
# ---------------------------------------------------------------------
const MONSTER_DB := {
	"cultist":    {"name": "Cultist",       "toughness": 2, "check": "will",     "required": 1, "damage": 1, "horror": 1, "reward_clues": 1, "speed": 1},
	"deep_one":   {"name": "Deep One",      "toughness": 3, "check": "strength", "required": 1, "damage": 2, "horror": 0, "reward_clues": 1, "speed": 1},
	"shambler":   {"name": "Shambler",      "toughness": 4, "check": "strength", "required": 2, "damage": 2, "horror": 1, "reward_clues": 2, "speed": 1},
	"nightgaunt": {"name": "Nightgaunt",    "toughness": 2, "check": "will",     "required": 1, "damage": 1, "horror": 2, "reward_clues": 1, "speed": 2},
	"maniac":     {"name": "Maniac",        "toughness": 2, "check": "strength", "required": 1, "damage": 2, "horror": 1, "reward_clues": 1, "speed": 1},
	"star_spawn": {"name": "Spawn of the Outer Dark", "toughness": 6, "check": "strength", "required": 2, "damage": 3, "horror": 3, "reward_clues": 3, "speed": 1},
}

## The pool the mythos spawner draws ordinary monsters from (star_spawn is spawned
## only as a hunt-mystery target, never randomly).
const SPAWN_POOL: Array[String] = ["cultist", "deep_one", "shambler", "nightgaunt", "maniac"]

# ---------------------------------------------------------------------
#  Mythos deck (>=12 cards). Each round the top card resolves automatically:
#    doom  = how far DOOM ticks DOWN (scaled up by the threat multiplier),
#    gate  = open a new gate (+ spawn a monster there),
#    spawn = spawn this monster type at a random gate (or "" for none),
#    effect= a global effect id (see _apply_mythos_effect).
# ---------------------------------------------------------------------
const MYTHOS_DECK := [
	{"id": "the_stars_align",   "doom": 2, "gate": true,  "spawn": "cultist",    "effect": "none"},
	{"id": "creeping_fog",      "doom": 1, "gate": true,  "spawn": "",           "effect": "sanity_drain"},
	{"id": "whispers",          "doom": 1, "gate": false, "spawn": "cultist",    "effect": "none"},
	{"id": "the_deep_calls",    "doom": 1, "gate": true,  "spawn": "deep_one",   "effect": "none"},
	{"id": "night_terrors",     "doom": 1, "gate": false, "spawn": "nightgaunt", "effect": "sanity_drain"},
	{"id": "false_dawn",        "doom": 1, "gate": false, "spawn": "",           "effect": "clue_surge"},
	{"id": "the_hungry_dark",   "doom": 2, "gate": true,  "spawn": "shambler",   "effect": "none"},
	{"id": "madness_spreads",   "doom": 1, "gate": false, "spawn": "maniac",     "effect": "sanity_drain"},
	{"id": "thin_veil",         "doom": 1, "gate": true,  "spawn": "",           "effect": "none"},
	{"id": "ancient_pull",      "doom": 2, "gate": false, "spawn": "deep_one",   "effect": "none"},
	{"id": "gathering_storm",   "doom": 1, "gate": true,  "spawn": "cultist",    "effect": "none"},
	{"id": "a_moment_of_calm",  "doom": 0, "gate": false, "spawn": "",           "effect": "clue_surge"},
	{"id": "the_watchers",      "doom": 1, "gate": false, "spawn": "nightgaunt", "effect": "none"},
	{"id": "reality_bleeds",    "doom": 2, "gate": true,  "spawn": "shambler",   "effect": "sanity_drain"},
]

# ---------------------------------------------------------------------
#  Mysteries (>=5). Solve MYSTERIES_TO_WIN of them to win. Each has a KIND with a
#  concrete, checkable completion condition:
#    "research"/"ritual" — invest `target` clues (spend_clue action) then pass a
#                          finalize `check` of `required` successes.
#    "seal"              — close `target` gates while this mystery is active.
#    "hunt"              — defeat `target_monster` (spawned when it activates).
# ---------------------------------------------------------------------
const MYSTERY_DB := {
	"the_gathering_dark": {"name": "Decode the Cult's Ledger", "kind": "research", "target": 3, "check": "will",        "required": 1},
	"blood_trail":        {"name": "Follow the Blood Trail",    "kind": "research", "target": 2, "check": "observation", "required": 1},
	"the_final_rite":     {"name": "Perform the Banishing Rite", "kind": "ritual",  "target": 4, "check": "lore",        "required": 1},
	"seal_the_rifts":     {"name": "Seal the Rifts",            "kind": "seal",     "target": 2, "check": "",            "required": 0},
	"hunt_the_herald":    {"name": "Slay the Herald",           "kind": "hunt",     "target_monster": "star_spawn"},
	"map_the_ley_lines":  {"name": "Map the Ley Lines",         "kind": "research", "target": 3, "check": "lore",        "required": 1},
}

## Draw order for the mystery deck (shuffled by the seeded RNG at setup).
const MYSTERY_ORDER: Array[String] = [
	"the_gathering_dark", "blood_trail", "the_final_rite",
	"seal_the_rifts", "hunt_the_herald", "map_the_ley_lines",
]

# =====================================================================
#  Seat controllers — the co-op play-mode matrix
# =====================================================================
## Every seat (== one investigator) has a CONTROLLER KIND that decides WHO produces
## that investigator's ACTION-phase choices — never WHAT the rules are. A turn is
## always "produce one legal action; apply_action() validates it", so the kind is a
## pure input seam: it changes nothing about the engine, its determinism, or the
## automated encounter/mythos phases.
##
## TWO kinds are FULLY IMPLEMENTED:
##   * HUMAN_LOCAL   — a local human. The dispatcher (GameManager) BLOCKS on this
##                     seat and waits for the board to forward the chosen action.
##   * AI_AUTOPILOT  — the built-in co-op heuristic ai_choose(); auto-resolves an
##                     investigator toward the SHARED objective (gather clues,
##                     advance the active mystery, fight threatening monsters, rest
##                     when low, close gates). Deterministic.
##
## TWO kinds are DOCUMENTED FUTURE SEAMS — present as enum values, NOT wired, NOT
## stubbed. Using one FAILS LOUD (is_supported_kind is false; the dispatcher's
## default branch asserts). Each drops in as ONE dispatch case + one hook:
##   * AI_LLM  — a local-LLM-assisted seat that picks from legal_actions() via an
##               HTTP endpoint, re-validated through is_legal()/apply_action().
##   * REMOTE  — a networked human/agent whose chosen action arrives over a
##               transport, then apply_action() applies it.
enum ControllerKind { HUMAN_LOCAL, AI_AUTOPILOT, AI_LLM, REMOTE }

const CONTROLLER_LABEL := {
	ControllerKind.HUMAN_LOCAL: "human",
	ControllerKind.AI_AUTOPILOT: "autopilot",
	ControllerKind.AI_LLM: "llm",
	ControllerKind.REMOTE: "remote",
}

# =====================================================================
#  AI autopilot tuning (the co-op heuristic's weights — see ai_choose())
# =====================================================================
const W_REST_URGENT := 40.0     ## rest when a pool is critically low (and safe).
const W_REST_SOFT := 8.0        ## light pull to top off when moderately hurt.
const W_INVEST := 30.0          ## spend a clue into the active clue-mystery.
const W_INVEST_FINISH := 60.0   ## the clue that could COMPLETE the mystery.
const W_MOVE_TO_GOAL := 18.0    ## step that reduces distance to the mystery goal.
const W_MOVE_TO_CLUE := 12.0    ## step toward a clue site (income).
const W_ACQUIRE := 6.0          ## grab an asset at a safe location (if room).
const W_PREPARE := 5.0          ## bank a focus die before a hard encounter.
const W_TRADE := 4.0            ## hand a clue to a teammate finalizing a mystery.
const W_STAY_FIGHT := 22.0      ## stay put when a monster here must be fought.
const LOW_HEALTH_FRAC := 0.34   ## "critically low" threshold (fraction of max).
const CLUE_COMBAT_RESERVE := 1  ## clues the autopilot keeps back for encounters.

# =====================================================================
#  Live state
# =====================================================================

var difficulty := "normal"
var cfg := {}                     ## resolved DIFFICULTY[difficulty] (overridable).
var num_investigators := 4
var investigators: Array = []     ## each: investigator dict (see _new_investigator)
var controllers: Array[int] = []  ## per-seat ControllerKind (source of truth).
var seat_names: Array[String] = []

var doom := 16                    ## global doom track; LOST at 0.
var mysteries_solved := 0         ## WON at MYSTERIES_TO_WIN.
var active_mystery := ""          ## current mystery id (drawn from the deck).
var mystery_deck: Array = []      ## remaining mystery ids (draw order).
var mystery_progress := 0         ## clues invested / gates closed toward active.
var mystery_ready := false        ## clue mystery reached its clue target (awaiting finalize pass).

var monsters: Array = []          ## active monsters: {type, location, toughness, id}
var open_gates: Array = []        ## location ids with an open gate.
var _monster_seq := 0             ## monotonic id source for monster instances.

var mythos_deck: Array = []       ## shuffled mythos card ids (draw pile).
var mythos_discard: Array = []    ## discard; reshuffled when the draw pile empties.
var asset_deck: Array = []        ## shuffled asset ids (acquire draw pile).

var round_index := 0              ## full rounds completed.
var phase := "action"             ## "action" | "encounter" | "mythos" | "gameover"
var active_index := 0             ## whose ACTION turn it is (investigator index).
var actions_remaining := ACTIONS_PER_TURN

var game_over := false
var outcome := ""                 ## "" | "win" | "loss"
var loss_reason := ""
var illegal_attempts := 0         ## apply_action() rejections (stays 0 in real play).
var action_count := 0             ## total legal actions taken.
var log_lines: Array[String] = []

var _rng := RandomNumberGenerator.new()
var _seed := 0


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh game. seed_value == 0 -> random; any other value replays byte-
## identically. investigator_count in 1..4. difficulty_name in DIFFICULTY.
## lineup optionally names the archetypes (else DEFAULT_LINEUP is cycled).
func setup(seed_value: int = 0, investigator_count: int = 4, difficulty_name: String = "normal", lineup: Array = []) -> void:
	num_investigators = clampi(investigator_count, 1, 4)
	difficulty = difficulty_name if DIFFICULTY.has(difficulty_name) else "normal"
	cfg = (DIFFICULTY[difficulty] as Dictionary).duplicate(true)
	_seed = seed_value
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value

	var chosen_lineup: Array = lineup if not lineup.is_empty() else DEFAULT_LINEUP
	investigators = []
	for i in num_investigators:
		var arch := String(chosen_lineup[i % chosen_lineup.size()])
		if not ARCHETYPES.has(arch):
			arch = DEFAULT_LINEUP[i % DEFAULT_LINEUP.size()]
		investigators.append(_new_investigator(i, arch))

	# Default preset: seat 0 is the local human, the rest are autopilot teammates.
	controllers = []
	seat_names = []
	for i in num_investigators:
		var kind := ControllerKind.HUMAN_LOCAL if i == 0 else ControllerKind.AI_AUTOPILOT
		controllers.append(kind)
		seat_names.append(_default_seat_name(i, kind))

	doom = int(cfg["doom_start"])
	mysteries_solved = 0
	monsters = []
	open_gates = []
	_monster_seq = 0
	round_index = 0
	phase = "action"
	active_index = 0
	actions_remaining = ACTIONS_PER_TURN
	game_over = false
	outcome = ""
	loss_reason = ""
	illegal_attempts = 0
	action_count = 0
	log_lines = []

	_build_mythos_deck()
	_build_asset_deck()
	_build_mystery_deck()
	_activate_next_mystery()

	_log("The vigil begins — %d investigators, doom %d, difficulty %s (seed %d)." % [
		num_investigators, doom, difficulty, _seed])
	# The first actor may be defeated only in pathological configs; normalise cursor.
	_skip_defeated_actor()


func _new_investigator(index: int, archetype: String) -> Dictionary:
	var a: Dictionary = ARCHETYPES[archetype]
	var skills := {}
	for s in SKILLS:
		skills[s] = int((a["skills"] as Dictionary).get(s, 1))
	var start_assets: Array = []
	if String(a.get("asset", "")) != "":
		start_assets.append(String(a["asset"]))
	var max_health := maxi(1, int(a["health"]) + int(cfg.get("start_health_mod", 0)))
	var max_sanity := maxi(1, int(a["sanity"]) + int(cfg.get("start_sanity_mod", 0)))
	return {
		"index": index,
		"archetype": archetype,
		"name": String(a["name"]),
		"skills": skills,
		"max_health": max_health,
		"max_sanity": max_sanity,
		"health": max_health,
		"sanity": max_sanity,
		"clues": 0,
		"assets": start_assets,
		"focus": 0,
		"location": String(START_LOCATIONS[index % START_LOCATIONS.size()]),
		"defeated": false,
	}


# =====================================================================
#  Seat-controller configuration + queries
# =====================================================================

## Assign every seat a controller kind (+ optional display names). Call AFTER
## setup(); kinds length must equal num_investigators and each must be a SUPPORTED
## kind (HUMAN_LOCAL or AI_AUTOPILOT). Only WHO acts changes — never the rules.
func configure_seats(kinds: Array, names: Array = []) -> void:
	assert(kinds.size() == num_investigators,
		"configure_seats: expected %d kinds, got %d" % [num_investigators, kinds.size()])
	var new_controllers: Array[int] = []
	var new_names: Array[String] = []
	for i in num_investigators:
		var kind := int(kinds[i])
		assert(is_supported_kind(kind),
			"configure_seats: seat %d has invalid/unsupported ControllerKind %d" % [i, kind])
		new_controllers.append(kind)
		if i < names.size() and String(names[i]) != "":
			new_names.append(String(names[i]))
		else:
			new_names.append(_default_seat_name(i, kind))
	controllers = new_controllers
	seat_names = new_names


## True iff `kind` is a controller kind this engine actually IMPLEMENTS. Only
## HUMAN_LOCAL and AI_AUTOPILOT are supported; AI_LLM / REMOTE are open seams.
func is_supported_kind(kind: int) -> bool:
	return kind == ControllerKind.HUMAN_LOCAL or kind == ControllerKind.AI_AUTOPILOT


func controller_of(seat: int) -> int:
	return int(controllers[seat]) if seat >= 0 and seat < controllers.size() else ControllerKind.AI_AUTOPILOT


func seat_name(seat: int) -> String:
	return seat_names[seat] if seat >= 0 and seat < seat_names.size() else "Investigator %d" % (seat + 1)


func is_human_seat(seat: int) -> bool:
	return controller_of(seat) == ControllerKind.HUMAN_LOCAL


func is_autopilot_seat(seat: int) -> bool:
	return controller_of(seat) == ControllerKind.AI_AUTOPILOT


func human_seat_count() -> int:
	var n := 0
	for k in controllers:
		if int(k) == ControllerKind.HUMAN_LOCAL:
			n += 1
	return n


func _default_seat_name(seat: int, kind: int) -> String:
	var arch_name := String((investigators[seat] as Dictionary)["name"]) if seat < investigators.size() else "Investigator"
	if kind == ControllerKind.HUMAN_LOCAL:
		return "%s (you)" % arch_name if seat == 0 else "%s (human)" % arch_name
	return "%s (auto)" % arch_name


# =====================================================================
#  Deck construction (all shuffles use the seeded RNG => deterministic)
# =====================================================================

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _build_mythos_deck() -> void:
	mythos_deck = []
	mythos_discard = []
	for card in MYTHOS_DECK:
		mythos_deck.append(String(card["id"]))
	_shuffle(mythos_deck)


func _build_asset_deck() -> void:
	asset_deck = []
	var ids: Array = ASSET_DB.keys()
	ids.sort()
	for _c in ASSET_COPIES:
		for id in ids:
			asset_deck.append(String(id))
	_shuffle(asset_deck)


func _build_mystery_deck() -> void:
	mystery_deck = []
	for id in MYSTERY_ORDER:
		mystery_deck.append(String(id))
	_shuffle(mystery_deck)


func _card_by_id(mythos_id: String) -> Dictionary:
	for card in MYTHOS_DECK:
		if String(card["id"]) == mythos_id:
			return card
	return MYTHOS_DECK[0]


# =====================================================================
#  Mystery lifecycle
# =====================================================================

func _activate_next_mystery() -> void:
	if mystery_deck.is_empty():
		active_mystery = ""
		return
	active_mystery = String(mystery_deck.pop_front())
	mystery_progress = 0
	mystery_ready = false
	var m: Dictionary = MYSTERY_DB[active_mystery]
	# A HUNT mystery guarantees its quarry exists: spawn it at a random gate spot
	# (opening one if none are open) so the objective is always reachable.
	if String(m["kind"]) == "hunt":
		var loc := _random_gate_spot()
		if not open_gates.has(loc):
			open_gates.append(loc)
		_spawn_monster(String(m["target_monster"]), loc)
	_log("New Mystery: %s (%s)." % [String(m["name"]), String(m["kind"])])


func active_mystery_name() -> String:
	return String(MYSTERY_DB[active_mystery]["name"]) if active_mystery != "" else "—"


func active_mystery_kind() -> String:
	return String(MYSTERY_DB[active_mystery]["kind"]) if active_mystery != "" else ""


func _solve_active_mystery() -> void:
	mysteries_solved += 1
	_log("MYSTERY SOLVED (%d/%d): %s." % [mysteries_solved, MYSTERIES_TO_WIN, active_mystery_name()])
	if mysteries_solved >= MYSTERIES_TO_WIN:
		_end_game("win", "")
		return
	_activate_next_mystery()


# =====================================================================
#  Map helpers — adjacency + BFS distance (drives autopilot movement)
# =====================================================================

func neighbors(loc: String) -> Array:
	return (MAP_EDGES.get(loc, []) as Array).duplicate()


func are_adjacent(a: String, b: String) -> bool:
	return (MAP_EDGES.get(a, []) as Array).has(b)


## Shortest hop count between two locations via BFS (0 if same, big if unreachable).
func hop_distance(from_loc: String, to_loc: String) -> int:
	if from_loc == to_loc:
		return 0
	var visited := {from_loc: true}
	var frontier: Array = [from_loc]
	var dist := 0
	while not frontier.is_empty():
		dist += 1
		var next_frontier: Array = []
		for node in frontier:
			for nb in MAP_EDGES.get(node, []):
				if nb == to_loc:
					return dist
				if not visited.has(nb):
					visited[nb] = true
					next_frontier.append(String(nb))
		frontier = next_frontier
	return 999


## The neighbor of `from_loc` that most reduces the distance to `to_loc`
## (deterministic: neighbors are scanned in declared order). "" if already there.
func step_toward(from_loc: String, to_loc: String) -> String:
	if from_loc == to_loc:
		return ""
	var best := ""
	var best_d := 999
	for nb in MAP_EDGES.get(from_loc, []):
		var d := hop_distance(String(nb), to_loc)
		if d < best_d:
			best_d = d
			best = String(nb)
	return best


func _random_gate_spot() -> String:
	var spots: Array = []
	for id in LOCATIONS.keys():
		if bool(LOCATIONS[id]["gate"]):
			spots.append(String(id))
	spots.sort()
	return String(spots[_rng.randi_range(0, spots.size() - 1)])


func _clue_sites() -> Array:
	var out: Array = []
	for id in LOCATIONS.keys():
		if bool(LOCATIONS[id]["clue"]):
			out.append(String(id))
	out.sort()
	return out


# =====================================================================
#  The reusable SKILL-CHECK resolver (the core mechanic)
# =====================================================================

## Count how many dice in `rolls` meet the success threshold.
func count_successes(rolls: Array, threshold: int = SUCCESS_THRESHOLD) -> int:
	var n := 0
	for r in rolls:
		if int(r) >= threshold:
			n += 1
	return n


## PURE, fully-deterministic check resolution given explicit dice. Counts successes
## in `rolls`; while short of `required`, spends up to `clue_budget` clues, each
## rerolling ONE still-failing die using the next value from `reroll_rolls` (a
## reroll that meets the threshold ADDS a success). Never spends a clue once the
## check has passed, and never consumes more reroll values than provided. Returns
## {successes, passed, clues_used}. This is what perform_check() wraps with RNG,
## and what the skill-check probe drives at the boundaries.
func resolve_from_rolls(rolls: Array, required: int, reroll_rolls: Array, clue_budget: int, threshold: int = SUCCESS_THRESHOLD) -> Dictionary:
	var work: Array = rolls.duplicate()
	var successes := count_successes(work, threshold)
	var clues_used := 0
	var ri := 0
	while successes < required and clues_used < clue_budget and ri < reroll_rolls.size():
		var idx := -1
		for i in work.size():
			if int(work[i]) < threshold:
				idx = i
				break
		if idx < 0:
			break  # no failing die left to reroll.
		var newv := int(reroll_rolls[ri])
		ri += 1
		clues_used += 1
		var was_fail := int(work[idx]) < threshold
		work[idx] = newv
		if was_fail and newv >= threshold:
			successes += 1
	return {"successes": successes, "passed": successes >= required, "clues_used": clues_used}


## Effective value of `skill_name` for an investigator including held-asset bonuses.
func effective_skill(inv: Dictionary, skill_name: String) -> int:
	var v := int((inv["skills"] as Dictionary).get(skill_name, 1))
	for aid in inv["assets"]:
		var bonus: Dictionary = (ASSET_DB[aid] as Dictionary).get("skill_bonus", {})
		v += int(bonus.get(skill_name, 0))
	return v


## Roll and resolve a real skill check for `inv`. Pool = effective skill + any
## situational bonus + banked focus (focus is consumed). `max_clue_spend` caps how
## many clues the resolver may burn on rerolls — it is CLAMPED to the clues the
## investigator actually holds (an over-spend is impossible, never illegal here).
## Deducts the clues used and returns the resolution dict (with "pool").
func perform_check(inv: Dictionary, skill_name: String, required: int, situational_bonus: int = 0, max_clue_spend: int = 0) -> Dictionary:
	var pool := maxi(1, effective_skill(inv, skill_name) + situational_bonus + int(inv["focus"]))
	inv["focus"] = 0
	var rolls: Array = []
	for _i in pool:
		rolls.append(_rng.randi_range(1, DIE_FACES))
	var budget := clampi(max_clue_spend, 0, int(inv["clues"]))
	# Pre-roll the reroll dice the resolver MIGHT consume (budget of them), so the
	# whole check is a single deterministic RNG draw sequence.
	var reroll_rolls: Array = []
	for _i in budget:
		reroll_rolls.append(_rng.randi_range(1, DIE_FACES))
	var res := resolve_from_rolls(rolls, required, reroll_rolls, budget, SUCCESS_THRESHOLD)
	inv["clues"] = int(inv["clues"]) - int(res["clues_used"])
	res["pool"] = pool
	return res


# =====================================================================
#  Damage / defeat
# =====================================================================

func _hurt(inv: Dictionary, health_loss: int, sanity_loss: int) -> void:
	if health_loss > 0:
		inv["health"] = maxi(0, int(inv["health"]) - health_loss)
	if sanity_loss > 0:
		inv["sanity"] = maxi(0, int(inv["sanity"]) - sanity_loss)
	if (int(inv["health"]) <= 0 or int(inv["sanity"]) <= 0) and not bool(inv["defeated"]):
		inv["defeated"] = true
		var why := "slain" if int(inv["health"]) <= 0 else "driven mad"
		_log("%s is DEFEATED (%s)." % [String(inv["name"]), why])


func active_investigators() -> int:
	var n := 0
	for inv in investigators:
		if not bool(inv["defeated"]):
			n += 1
	return n


# =====================================================================
#  ACTION phase — legality + enumeration + application
# =====================================================================

## Is `action` legal for investigator `inv_index` right now (their action turn, in
## the action phase, not game over, and the action's own preconditions met)?
func is_legal(inv_index: int, action: Dictionary) -> bool:
	if game_over or phase != "action":
		return false
	if inv_index != active_index:
		return false
	if inv_index < 0 or inv_index >= investigators.size():
		return false
	var inv: Dictionary = investigators[inv_index]
	if bool(inv["defeated"]) or actions_remaining <= 0:
		return false
	match String(action.get("type", "")):
		"move":
			var dest := String(action.get("to", ""))
			return are_adjacent(String(inv["location"]), dest)
		"rest":
			# May rest anywhere with no monster present (danger prevents rest).
			return not _monster_here(String(inv["location"]))
		"acquire":
			return bool(LOCATIONS[inv["location"]]["safe"]) \
				and not asset_deck.is_empty() \
				and (inv["assets"] as Array).size() < INVENTORY_MAX
		"prepare":
			return int(inv["focus"]) < FOCUS_MAX
		"trade":
			# Give a clue to a co-located, non-defeated teammate.
			var to_i := int(action.get("to_index", -1))
			if to_i < 0 or to_i >= investigators.size() or to_i == inv_index:
				return false
			var other: Dictionary = investigators[to_i]
			return int(inv["clues"]) > 0 and not bool(other["defeated"]) \
				and String(other["location"]) == String(inv["location"]) \
				and int(other["clues"]) < CLUE_CARRY_MAX
		"spend_clue":
			# Invest a clue into a clue-based active mystery (research / ritual).
			if int(inv["clues"]) <= 0 or active_mystery == "":
				return false
			var kind := active_mystery_kind()
			return kind == "research" or kind == "ritual"
		_:
			return false


## Every legal action for `inv_index`, in a fixed deterministic order:
## move(neighbor order), rest, acquire, prepare, trade(teammate order), spend_clue.
func legal_actions(inv_index: int) -> Array:
	var out: Array = []
	if game_over or phase != "action" or inv_index != active_index:
		return out
	var inv: Dictionary = investigators[inv_index]
	if bool(inv["defeated"]) or actions_remaining <= 0:
		return out
	for nb in neighbors(String(inv["location"])):
		out.append({"type": "move", "to": String(nb)})
	if is_legal(inv_index, {"type": "rest"}):
		out.append({"type": "rest"})
	if is_legal(inv_index, {"type": "acquire"}):
		out.append({"type": "acquire"})
	if is_legal(inv_index, {"type": "prepare"}):
		out.append({"type": "prepare"})
	for j in investigators.size():
		var candidate := {"type": "trade", "to_index": j}
		if is_legal(inv_index, candidate):
			out.append(candidate)
	if is_legal(inv_index, {"type": "spend_clue"}):
		out.append({"type": "spend_clue"})
	return out


## Take ONE action for `inv_index`. Rejects an illegal action (state unchanged,
## counted in illegal_attempts). On success consumes one of the investigator's
## actions and, when they run out, advances to the next investigator — and when the
## whole ACTION phase completes, auto-resolves the ENCOUNTER and MYTHOS phases.
func apply_action(inv_index: int, action: Dictionary) -> bool:
	if not is_legal(inv_index, action):
		illegal_attempts += 1
		return false
	var inv: Dictionary = investigators[inv_index]
	match String(action["type"]):
		"move":
			_do_move(inv, String(action["to"]))
		"rest":
			_do_rest(inv)
		"acquire":
			_do_acquire(inv)
		"prepare":
			_do_prepare(inv)
		"trade":
			_do_trade(inv, int(action["to_index"]))
		"spend_clue":
			_do_spend_clue(inv)
	action_count += 1
	actions_remaining -= 1
	if not game_over and actions_remaining <= 0:
		_advance_actor()
	return true


func _do_move(inv: Dictionary, dest: String) -> void:
	inv["location"] = dest
	_log("%s moves to %s." % [String(inv["name"]), String(LOCATIONS[dest]["name"])])


func _do_rest(inv: Dictionary) -> void:
	var heal := 1
	for aid in inv["assets"]:
		heal += int((ASSET_DB[aid] as Dictionary).get("rest_bonus", 0))
	inv["health"] = mini(int(inv["max_health"]), int(inv["health"]) + heal)
	inv["sanity"] = mini(int(inv["max_sanity"]), int(inv["sanity"]) + 1)
	_log("%s rests (+%d health, +1 sanity)." % [String(inv["name"]), heal])


func _do_acquire(inv: Dictionary) -> void:
	var aid := String(asset_deck.pop_back())
	(inv["assets"] as Array).append(aid)
	_log("%s acquires %s." % [String(inv["name"]), String(ASSET_DB[aid]["name"])])


func _do_prepare(inv: Dictionary) -> void:
	inv["focus"] = mini(FOCUS_MAX, int(inv["focus"]) + 1)
	_log("%s prepares (focus %d)." % [String(inv["name"]), int(inv["focus"])])


func _do_trade(inv: Dictionary, to_index: int) -> void:
	var other: Dictionary = investigators[to_index]
	inv["clues"] = int(inv["clues"]) - 1
	other["clues"] = int(other["clues"]) + 1
	_log("%s gives a clue to %s." % [String(inv["name"]), String(other["name"])])


## Invest one clue into the active clue-mystery. When the invested total reaches
## the target, the investing investigator immediately attempts the finalize CHECK
## (may burn extra held clues on rerolls); passing SOLVES it, failing leaves it
## "ready" so a later spend_clue retries the finalize.
func _do_spend_clue(inv: Dictionary) -> void:
	var m: Dictionary = MYSTERY_DB[active_mystery]
	inv["clues"] = int(inv["clues"]) - 1
	mystery_progress += 1
	_log("%s invests a clue in '%s' (%d/%d)." % [
		String(inv["name"]), String(m["name"]), mystery_progress, int(m["target"])])
	if mystery_progress >= int(m["target"]):
		mystery_ready = true
		var res := perform_check(inv, String(m["check"]), int(m["required"]), 0, int(inv["clues"]))
		if bool(res["passed"]):
			_solve_active_mystery()
		else:
			_log("%s falters on the finalize check (%d/%d successes) — try again." % [
				String(inv["name"]), int(res["successes"]), int(m["required"])])


# =====================================================================
#  Actor / phase advancement
# =====================================================================

## Move the ACTION cursor to the next non-defeated investigator; if none remain in
## this round, resolve the ENCOUNTER + MYTHOS phases and open the next round.
func _advance_actor() -> void:
	active_index += 1
	actions_remaining = ACTIONS_PER_TURN
	if active_index >= num_investigators:
		_run_encounter_phase()
		if not game_over:
			_run_mythos_phase()
		if not game_over:
			round_index += 1
			if round_index >= MAX_ROUNDS:
				_end_game("loss", "the vigil dragged on too long — the stars completed their turn")
				return
			active_index = 0
			phase = "action"
			actions_remaining = ACTIONS_PER_TURN
			_skip_defeated_actor()
	else:
		_skip_defeated_actor()


## Skip over defeated investigators at the current cursor. If ALL are defeated the
## party is lost; otherwise leaves active_index on a living investigator.
func _skip_defeated_actor() -> void:
	if game_over:
		return
	if active_investigators() == 0:
		_end_game("loss", "every investigator has fallen")
		return
	var guard := 0
	while active_index < num_investigators and bool(investigators[active_index]["defeated"]) and guard < num_investigators + 1:
		active_index += 1
		actions_remaining = ACTIONS_PER_TURN
		guard += 1
	if active_index >= num_investigators:
		# Wrapped past the end while skipping — resolve the round's later phases.
		_run_encounter_phase()
		if not game_over:
			_run_mythos_phase()
		if not game_over:
			round_index += 1
			if round_index >= MAX_ROUNDS:
				_end_game("loss", "the vigil dragged on too long — the stars completed their turn")
				return
			active_index = 0
			phase = "action"
			actions_remaining = ACTIONS_PER_TURN
			_skip_defeated_actor()


# =====================================================================
#  ENCOUNTER phase (automated) — one encounter per living investigator
# =====================================================================
## Encounter priority at an investigator's location:
##   1. a monster present  -> COMBAT (strength/will check),
##   2. an open gate here  -> attempt to CLOSE it (lore check, may spend clues),
##   3. a clue site here    -> INVESTIGATE (observation check) -> gain a clue,
##   4. otherwise           -> a quiet watch (a light will check; failure unnerves).
func _run_encounter_phase() -> void:
	phase = "encounter"
	for inv in investigators:
		if bool(inv["defeated"]) or game_over:
			continue
		var loc := String(inv["location"])
		var mon := _first_monster_at(loc)
		if not mon.is_empty():
			_resolve_combat(inv, mon)
		elif open_gates.has(loc):
			_resolve_gate(inv, loc)
		elif bool(LOCATIONS[loc]["clue"]):
			_resolve_investigate(inv, loc)
		else:
			_resolve_quiet(inv, loc)
		if game_over:
			return


func _resolve_combat(inv: Dictionary, mon: Dictionary) -> void:
	var mdef: Dictionary = MONSTER_DB[String(mon["type"])]
	var reserve := maxi(0, int(inv["clues"]))  # combat may spend everything if needed.
	var res := perform_check(inv, String(mdef["check"]), int(mdef["required"]), 0, reserve)
	if bool(res["passed"]):
		mon["toughness"] = int(mon["toughness"]) - int(res["successes"])
		_log("%s fights the %s (%d dmg)." % [String(inv["name"]), String(mdef["name"]), int(res["successes"])])
		if int(mon["toughness"]) <= 0:
			_defeat_monster(inv, mon)
	else:
		_log("%s is wounded by the %s." % [String(inv["name"]), String(mdef["name"])])
		_hurt(inv, int(mdef["damage"]), int(mdef["horror"]))


func _defeat_monster(inv: Dictionary, mon: Dictionary) -> void:
	var mtype := String(mon["type"])
	var mdef: Dictionary = MONSTER_DB[mtype]
	_remove_monster(int(mon["id"]))
	inv["clues"] = mini(CLUE_CARRY_MAX, int(inv["clues"]) + int(mdef["reward_clues"]))
	_log("%s slays the %s (+%d clue)." % [String(inv["name"]), String(mdef["name"]), int(mdef["reward_clues"])])
	# HUNT mystery: defeating the quarry completes it.
	if active_mystery != "" and active_mystery_kind() == "hunt" \
			and String(MYSTERY_DB[active_mystery]["target_monster"]) == mtype:
		_solve_active_mystery()


func _resolve_gate(inv: Dictionary, loc: String) -> void:
	# Closing a gate is a lore check; being able to spend a couple of clues helps.
	var budget := mini(2, int(inv["clues"]))
	var res := perform_check(inv, "lore", 1, 0, budget)
	if bool(res["passed"]):
		open_gates.erase(loc)
		inv["clues"] = mini(CLUE_CARRY_MAX, int(inv["clues"]) + 1)
		_log("%s SEALS the gate at %s (+1 clue)." % [String(inv["name"]), String(LOCATIONS[loc]["name"])])
		# SEAL mystery: each closed gate counts toward the active seal target.
		if active_mystery != "" and active_mystery_kind() == "seal":
			mystery_progress += 1
			if mystery_progress >= int(MYSTERY_DB[active_mystery]["target"]):
				_solve_active_mystery()
	else:
		_log("%s fails to seal the gate at %s (the void claws back)." % [
			String(inv["name"]), String(LOCATIONS[loc]["name"])])
		_hurt(inv, 0, 1)


func _resolve_investigate(inv: Dictionary, loc: String) -> void:
	var budget := mini(1, int(inv["clues"]))
	var res := perform_check(inv, "observation", 1, 0, budget)
	if bool(res["passed"]):
		inv["clues"] = mini(CLUE_CARRY_MAX, int(inv["clues"]) + 1)
		_log("%s uncovers a clue at %s." % [String(inv["name"]), String(LOCATIONS[loc]["name"])])
	else:
		_log("%s searches %s but finds nothing." % [String(inv["name"]), String(LOCATIONS[loc]["name"])])


func _resolve_quiet(inv: Dictionary, loc: String) -> void:
	var res := perform_check(inv, "will", 1, 0, 0)
	if bool(res["passed"]):
		_log("%s keeps watch at %s — nerves hold." % [String(inv["name"]), String(LOCATIONS[loc]["name"])])
	else:
		_log("%s is unnerved by the quiet at %s." % [String(inv["name"]), String(LOCATIONS[loc]["name"])])
		_hurt(inv, 0, 1)


# =====================================================================
#  MYTHOS phase (automated) — the antagonist's turn
# =====================================================================
## Draw the top mythos card: tick DOOM down (scaled by the threat multiplier),
## optionally open a gate + spawn a monster there, spawn a card monster, apply a
## global effect, then MOVE every monster toward the nearest investigator. Checks
## the doom/gate loss invariants.
func _run_mythos_phase() -> void:
	phase = "mythos"
	var card := _draw_mythos()
	var threat := float(cfg.get("threat", 1.0))
	var tick := int(round(float(int(card["doom"])) * threat))
	if tick > 0:
		doom = maxi(0, doom - tick)
	_log("Mythos: %s (doom -%d -> %d)." % [String(card["id"]), tick, doom])

	if bool(card["gate"]):
		_open_gate_and_spawn(threat)
	if String(card["spawn"]) != "":
		_spawn_monster(String(card["spawn"]), _random_gate_spot())
	# Harsh difficulty spawns an EXTRA monster on gate cards (threat pressure).
	if threat >= 2.0 and bool(card["gate"]):
		_spawn_monster(SPAWN_POOL[_rng.randi_range(0, SPAWN_POOL.size() - 1)], _random_gate_spot())

	_apply_mythos_effect(String(card["effect"]))
	_move_monsters()

	# Loss invariants checked at the end of the antagonist's turn.
	if doom <= 0:
		_end_game("loss", "the Doom track reached zero — the world is consumed")
		return
	if open_gates.size() >= int(cfg["gate_limit"]):
		_end_game("loss", "too many gates tore open (%d) — reality collapses" % open_gates.size())
		return
	if active_investigators() == 0:
		_end_game("loss", "every investigator has fallen")


func _draw_mythos() -> Dictionary:
	if mythos_deck.is_empty():
		mythos_deck = mythos_discard.duplicate()
		mythos_discard = []
		_shuffle(mythos_deck)
	var id := String(mythos_deck.pop_back())
	mythos_discard.append(id)
	return _card_by_id(id)


func _open_gate_and_spawn(threat: float) -> void:
	var loc := _random_gate_spot()
	if not open_gates.has(loc):
		open_gates.append(loc)
		_log("A gate tears open at %s." % String(LOCATIONS[loc]["name"]))
	_spawn_monster(SPAWN_POOL[_rng.randi_range(0, SPAWN_POOL.size() - 1)], loc)


func _spawn_monster(mtype: String, loc: String) -> void:
	if not MONSTER_DB.has(mtype):
		return
	_monster_seq += 1
	var mdef: Dictionary = MONSTER_DB[mtype]
	monsters.append({
		"id": _monster_seq,
		"type": mtype,
		"location": loc,
		"toughness": int(mdef["toughness"]),
	})
	_log("A %s manifests at %s." % [String(mdef["name"]), String(LOCATIONS[loc]["name"])])


func _apply_mythos_effect(effect: String) -> void:
	match effect:
		"sanity_drain":
			for inv in investigators:
				if not bool(inv["defeated"]):
					_hurt(inv, 0, 1)
			_log("A wave of dread — every investigator loses 1 sanity.")
		"clue_surge":
			# A lead surfaces: the investigator on a clue site with the fewest clues
			# gains one (a small mercy that keeps the mystery economy moving).
			var best := -1
			var best_clues := 999
			for inv in investigators:
				if bool(inv["defeated"]):
					continue
				if bool(LOCATIONS[inv["location"]]["clue"]) and int(inv["clues"]) < best_clues:
					best_clues = int(inv["clues"])
					best = int(inv["index"])
			if best >= 0:
				var t: Dictionary = investigators[best]
				t["clues"] = mini(CLUE_CARRY_MAX, int(t["clues"]) + 1)
				_log("A lead surfaces — %s gains a clue." % String(t["name"]))
		_:
			pass


## Each monster steps `speed` hops toward the nearest living investigator.
func _move_monsters() -> void:
	for mon in monsters:
		var target := _nearest_investigator_location(String(mon["location"]))
		if target == "":
			continue
		var mdef: Dictionary = MONSTER_DB[String(mon["type"])]
		var steps := int(mdef["speed"])
		for _s in steps:
			var loc := String(mon["location"])
			if loc == target:
				break
			var nxt := step_toward(loc, target)
			if nxt == "":
				break
			mon["location"] = nxt


func _nearest_investigator_location(from_loc: String) -> String:
	var best := ""
	var best_d := 999
	for inv in investigators:
		if bool(inv["defeated"]):
			continue
		var d := hop_distance(from_loc, String(inv["location"]))
		if d < best_d:
			best_d = d
			best = String(inv["location"])
	return best


# =====================================================================
#  Monster helpers
# =====================================================================

func _monster_here(loc: String) -> bool:
	for mon in monsters:
		if String(mon["location"]) == loc:
			return true
	return false


func _first_monster_at(loc: String) -> Dictionary:
	# Deterministic: lowest monster id at the location (spawn order).
	var best := {}
	var best_id := 1 << 30
	for mon in monsters:
		if String(mon["location"]) == loc and int(mon["id"]) < best_id:
			best_id = int(mon["id"])
			best = mon
	return best


func _remove_monster(mid: int) -> void:
	for i in monsters.size():
		if int(monsters[i]["id"]) == mid:
			monsters.remove_at(i)
			return


func monsters_at(loc: String) -> Array:
	var out: Array = []
	for mon in monsters:
		if String(mon["location"]) == loc:
			out.append(mon)
	return out


# =====================================================================
#  The CO-OP autopilot heuristic (deterministic, genuine — no randomness)
# =====================================================================

## Choose the best ACTION-phase action for investigator `inv_index`, playing toward
## the SHARED objective. Enumerates every legal action and scores each by its
## concrete contribution: resting when a pool is critically low (and safe),
## investing clues into the active clue-mystery (huge when it could COMPLETE it),
## moving toward the mystery goal (its clue sites / open gates / quarry), grabbing
## assets at a safe stop, banking focus, trading a clue to a teammate about to
## finalize, and STAYING to fight a monster that is on it. Deterministic: ties
## break to the earliest action in legal_actions() order.
func ai_choose(inv_index: int) -> Dictionary:
	var options := legal_actions(inv_index)
	if options.is_empty():
		return {}
	var inv: Dictionary = investigators[inv_index]
	var goal := _autopilot_goal(inv)
	var best_i := 0
	var best_score := -INF
	for i in options.size():
		var s := _score_action(inv, options[i], goal)
		if s > best_score:
			best_score = s
			best_i = i
	return options[best_i]


## The location this investigator should be moving toward given the active mystery.
func _autopilot_goal(inv: Dictionary) -> String:
	var here := String(inv["location"])
	# A monster on us must be fought here — no goal to walk to.
	if _monster_here(here):
		return here
	if active_mystery == "":
		return _nearest_clue_site(here)
	var kind := active_mystery_kind()
	match kind:
		"seal":
			return _nearest_open_gate(here)
		"hunt":
			return _nearest_quarry(here)
		_:
			# research / ritual: if we still need clues, hunt clue income; else head
			# somewhere safe/quiet is fine — keep gathering as backup.
			return _nearest_clue_site(here)


func _score_action(inv: Dictionary, action: Dictionary, goal: String) -> float:
	var here := String(inv["location"])
	var t := String(action["type"])
	match t:
		"rest":
			var hp_frac := float(inv["health"]) / float(inv["max_health"])
			var san_frac := float(inv["sanity"]) / float(inv["max_sanity"])
			var worst := minf(hp_frac, san_frac)
			if worst <= LOW_HEALTH_FRAC:
				return W_REST_URGENT * (1.0 - worst)
			if worst < 0.75:
				return W_REST_SOFT * (1.0 - worst)
			return -5.0  # topped up; don't waste an action.
		"spend_clue":
			var m: Dictionary = MYSTERY_DB[active_mystery]
			# Keep a clue in reserve for encounters unless this clue could FINISH it.
			var would_finish := (mystery_progress + 1) >= int(m["target"])
			if would_finish:
				return W_INVEST_FINISH
			if int(inv["clues"]) > CLUE_COMBAT_RESERVE:
				return W_INVEST
			return -2.0  # too few clues in hand — hold them for a check.
		"move":
			var dest := String(action["to"])
			if goal == "" or goal == here:
				return -1.0
			var d_here := hop_distance(here, goal)
			var d_dest := hop_distance(dest, goal)
			if d_dest < d_here:
				var base := W_MOVE_TO_GOAL if active_mystery != "" else W_MOVE_TO_CLUE
				# Prefer stepping onto a clue site (income on the way).
				var bonus := 3.0 if bool(LOCATIONS[dest]["clue"]) else 0.0
				return base * (1.0 / float(d_dest + 1)) + bonus
			return -1.0
		"acquire":
			# Value assets while inventory has room and we are not desperate.
			return W_ACQUIRE if (inv["assets"] as Array).size() < INVENTORY_MAX else -2.0
		"prepare":
			# Bank focus if a hard encounter looms (a monster within one hop).
			return W_PREPARE if _threat_within(inv, 1) else -3.0
		"trade":
			var to_i := int(action["to_index"])
			var other: Dictionary = investigators[to_i]
			# Feed a teammate who is close to finalizing a clue mystery.
			if active_mystery != "" and (active_mystery_kind() == "research" or active_mystery_kind() == "ritual"):
				var need := int(MYSTERY_DB[active_mystery]["target"]) - mystery_progress
				if need > 0 and int(other["clues"]) >= int(inv["clues"]):
					return W_TRADE
			return -4.0
		_:
			return -10.0


func _nearest_clue_site(from_loc: String) -> String:
	var best := from_loc
	var best_d := 999
	for site in _clue_sites():
		var d := hop_distance(from_loc, String(site))
		if d < best_d:
			best_d = d
			best = String(site)
	return best


func _nearest_open_gate(from_loc: String) -> String:
	var best := ""
	var best_d := 999
	for g in open_gates:
		var d := hop_distance(from_loc, String(g))
		if d < best_d:
			best_d = d
			best = String(g)
	return best if best != "" else _nearest_clue_site(from_loc)


func _nearest_quarry(from_loc: String) -> String:
	if active_mystery == "":
		return _nearest_clue_site(from_loc)
	var quarry := String(MYSTERY_DB[active_mystery].get("target_monster", ""))
	var best := ""
	var best_d := 999
	for mon in monsters:
		if String(mon["type"]) == quarry:
			var d := hop_distance(from_loc, String(mon["location"]))
			if d < best_d:
				best_d = d
				best = String(mon["location"])
	return best if best != "" else _nearest_clue_site(from_loc)


func _threat_within(inv: Dictionary, hops: int) -> bool:
	for mon in monsters:
		if hop_distance(String(inv["location"]), String(mon["location"])) <= hops:
			return true
	return false


## The autopilot takes ITS whole action (one action). GameManager calls this per
## action until the seat's actions are spent.
func autopilot_take_action(inv_index: int) -> Dictionary:
	var action := ai_choose(inv_index)
	if action.is_empty():
		return {}
	apply_action(inv_index, action)
	return action


# =====================================================================
#  Game end
# =====================================================================

func _end_game(result: String, reason: String) -> void:
	if game_over:
		return
	game_over = true
	phase = "gameover"
	outcome = result
	loss_reason = reason
	if result == "win":
		_log("VICTORY — %d mysteries solved before the Doom. The world holds." % mysteries_solved)
	else:
		_log("DEFEAT — %s." % reason)


func is_win() -> bool:
	return game_over and outcome == "win"


func is_loss() -> bool:
	return game_over and outcome == "loss"


# =====================================================================
#  Logging
# =====================================================================

func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 400:
		log_lines.remove_at(0)


func recent_log(n: int = 10) -> Array[String]:
	var out: Array[String] = []
	var start := maxi(0, log_lines.size() - n)
	for i in range(start, log_lines.size()):
		out.append(log_lines[i])
	return out


# =====================================================================
#  Save / load — the FULL state round-trips (deep, JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	return {
		"difficulty": difficulty,
		"cfg": cfg.duplicate(true),
		"seed": _seed,
		"rng_state": str(_rng.state),
		"num_investigators": num_investigators,
		"controllers": controllers.duplicate(),
		"seat_names": seat_names.duplicate(),
		"investigators": investigators.duplicate(true),
		"doom": doom,
		"mysteries_solved": mysteries_solved,
		"active_mystery": active_mystery,
		"mystery_deck": mystery_deck.duplicate(),
		"mystery_progress": mystery_progress,
		"mystery_ready": mystery_ready,
		"monsters": monsters.duplicate(true),
		"open_gates": open_gates.duplicate(),
		"monster_seq": _monster_seq,
		"mythos_deck": mythos_deck.duplicate(),
		"mythos_discard": mythos_discard.duplicate(),
		"asset_deck": asset_deck.duplicate(),
		"round_index": round_index,
		"phase": phase,
		"active_index": active_index,
		"actions_remaining": actions_remaining,
		"game_over": game_over,
		"outcome": outcome,
		"loss_reason": loss_reason,
		"illegal_attempts": illegal_attempts,
		"action_count": action_count,
	}


func from_dict(data: Dictionary) -> void:
	difficulty = String(data.get("difficulty", "normal"))
	cfg = (data.get("cfg", DIFFICULTY["normal"]) as Dictionary).duplicate(true)
	_seed = int(data.get("seed", 0))
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	num_investigators = int(data.get("num_investigators", 4))
	controllers = []
	for c in data.get("controllers", []):
		controllers.append(int(c))
	seat_names = []
	for s in data.get("seat_names", []):
		seat_names.append(String(s))
	investigators = []
	for v in data.get("investigators", []):
		investigators.append(_coerce_investigator(v as Dictionary))
	doom = int(data.get("doom", 16))
	mysteries_solved = int(data.get("mysteries_solved", 0))
	active_mystery = String(data.get("active_mystery", ""))
	mystery_deck = []
	for id in data.get("mystery_deck", []):
		mystery_deck.append(String(id))
	mystery_progress = int(data.get("mystery_progress", 0))
	mystery_ready = bool(data.get("mystery_ready", false))
	monsters = []
	for v in data.get("monsters", []):
		var md: Dictionary = v
		monsters.append({
			"id": int(md["id"]),
			"type": String(md["type"]),
			"location": String(md["location"]),
			"toughness": int(md["toughness"]),
		})
	open_gates = []
	for g in data.get("open_gates", []):
		open_gates.append(String(g))
	_monster_seq = int(data.get("monster_seq", 0))
	mythos_deck = []
	for id in data.get("mythos_deck", []):
		mythos_deck.append(String(id))
	mythos_discard = []
	for id in data.get("mythos_discard", []):
		mythos_discard.append(String(id))
	asset_deck = []
	for id in data.get("asset_deck", []):
		asset_deck.append(String(id))
	round_index = int(data.get("round_index", 0))
	phase = String(data.get("phase", "action"))
	active_index = int(data.get("active_index", 0))
	actions_remaining = int(data.get("actions_remaining", ACTIONS_PER_TURN))
	game_over = bool(data.get("game_over", false))
	outcome = String(data.get("outcome", ""))
	loss_reason = String(data.get("loss_reason", ""))
	illegal_attempts = int(data.get("illegal_attempts", 0))
	action_count = int(data.get("action_count", 0))


func _coerce_investigator(src: Dictionary) -> Dictionary:
	var skills := {}
	for s in SKILLS:
		skills[s] = int((src.get("skills", {}) as Dictionary).get(s, 1))
	var assets: Array = []
	for a in src.get("assets", []):
		assets.append(String(a))
	return {
		"index": int(src["index"]),
		"archetype": String(src.get("archetype", "scholar")),
		"name": String(src["name"]),
		"skills": skills,
		"max_health": int(src["max_health"]),
		"max_sanity": int(src["max_sanity"]),
		"health": int(src["health"]),
		"sanity": int(src["sanity"]),
		"clues": int(src["clues"]),
		"assets": assets,
		"focus": int(src.get("focus", 0)),
		"location": String(src["location"]),
		"defeated": bool(src["defeated"]),
	}
