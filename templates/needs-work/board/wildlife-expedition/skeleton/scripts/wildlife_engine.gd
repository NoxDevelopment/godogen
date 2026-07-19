extends RefCounted
class_name WildlifeEngine
## res://scripts/wildlife_engine.gd
## The PURE, seedable, headless-testable engine for a competitive NATURE-EXPLORATION
## + WILDLIFE-DOCUMENTATION board game (a National-Geographic-flavoured original genre
## engine — GENERIC content, no trademarks). There is NO Godot node dependency in
## here: it is plain data + rules, so the whole game replays byte-identically from a
## seed and can be driven with no UI at all. GameManager owns one instance and adds
## the autoload ABI + save; board.gd only reads state and forwards a human's action.
##
## The design synthesises the SIGNATURE mechanics of three modern classics — this is
## a real depth engine, not a shallow generic loop:
##
##   * The shared EXPLORATION TRAIL + resources + SEASONS (the PARKS lineage). A shared
##     linear trail of TRAIL_LEN site tiles from a Start camp to the Trailhead. Each
##     site yields NATURE resources (sun / water / forest / mountain / wildlife-sighting
##     / film) or a small action (draw a species, restock gear). Explorer pawns advance
##     FORWARD only (never backward); good interior sites have limited CAPACITY, so the
##     trail is a race. The game runs 4 SEASONS: at each season boundary the trail is
##     RE-SEEDED (its sites/bonuses shift), season income + season goals resolve, and
##     every pawn resets to the Start camp for the next season.
##
##   * A SPECIES-CARD TABLEAU ENGINE with powers + goals (the Wingspan lineage). A deck
##     of 37 unique species (x2 copies), each with a biome/habitat, a documentation
##     COST in resources, a POINT value, a CATEGORY (mammal/bird/reptile/aquatic/insect/
##     plant), and an ONGOING or WHEN-DOCUMENTED POWER (gain resources now; chain a gain
##     whenever you later document a matching category / any species; per-season income;
##     draw on rest; end-game scoring hooks). Documenting plays a species to your FIELD
##     JOURNAL (tableau) and fires its power AND any chain powers already in your journal.
##     Four end-of-SEASON GOAL tiles (one active per season) score the season leader.
##
##   * BIODIVERSITY / SET-VARIETY SCORING (the Cascadia lineage). End-game rewards
##     VARIETY: an escalating tier for distinct CATEGORIES, an escalating tier for
##     distinct BIOMES, a bonus for your LARGEST single-category collection, per-species
##     points, seven completed EXPEDITION contracts, and gear/station development.
##
## Turn structure: a turn is exactly ONE legal action from {MOVE, DOCUMENT, REST,
## DEVELOP}. MOVE advances a pawn forward to a site and collects its yield; DOCUMENT
## pays a species' cost (you must be OBSERVING its biome — a pawn stands on a matching-
## biome site) and plays it to the journal firing powers; DEVELOP buys a gear/station;
## REST banks film + draws. is_legal() rejects out-of-turn / move-backward / unaffordable
## / off-biome / malformed actions. After 4 seasons -> final scoring -> a single
## deterministic winner. The AI is a genuine NON-LLM weighted heuristic.

# =====================================================================
#  Static rules / tuning (auditable constants)
# =====================================================================

## Six tracked resources. A strict conservation ledger holds for every one of them:
## pool == start + produced - spent, proven every turn (verify_conservation()).
const RESOURCES: Array[String] = ["sun", "water", "forest", "mountain", "sighting", "film"]

## Relative worth — drives the AI's cost/yield evaluation. Sightings (the observation
## currency) and film (the flexible documentation resource) are the scarce ones.
const RESOURCE_VALUE := {
	"sun": 1.0, "water": 1.0, "forest": 1.0, "mountain": 1.2, "sighting": 1.6, "film": 1.4,
}

const START_RESOURCES := {"sun": 1, "water": 1, "forest": 1, "mountain": 1, "sighting": 1, "film": 1}

## The six species categories (the diversity set for set-variety scoring).
const CATEGORIES: Array[String] = ["mammal", "bird", "reptile", "aquatic", "insect", "plant"]

## The five habitats/biomes. A species can only be documented while one of your pawns
## OBSERVES its biome (stands on a trail site of that biome).
const BIOMES: Array[String] = ["forest", "wetland", "grassland", "mountain", "coast"]

const TRAIL_LEN := 9         ## sites 0..8: [Start camp] + 7 interior + [Trailhead].
const PAWNS := 2             ## explorer pawns per player.
const OFFER_SIZE := 4        ## shared face-up species offer (the "wildlife tray").
const GEAR_SHOP_SIZE := 4    ## shared face-up gear/station shop.
const START_HAND := 2        ## species drawn to each player's personal hand at setup.
const NUM_SEASONS := 4
const SEASON_ROUND_CAP := 14 ## a season also ends after this many rounds (safety terminator).
const HAND_MAX := 8
const SPECIES_COPIES := 2
const GEAR_COPIES := 2

## Set-variety scoring tiers (Cascadia-style escalation — jackpot at full variety).
const CATEGORY_TIER: Array[int] = [0, 0, 2, 5, 9, 14, 20]  ## index = distinct categories (0..6).
const BIOME_TIER: Array[int] = [0, 0, 3, 7, 12, 18]        ## index = distinct biomes (0..5).
const LARGEST_MULT := 2   ## points per card in your largest single-category collection.
const GOAL_FIRST := 5     ## season-goal points to each leader in the active season goal.

## The AI evaluation weights (the heuristic's "brain" — see ai_choose()).
const W_DOC_PTS := 6.0     ## a documented species' raw point value.
const W_COST := 1.6        ## resource-efficiency: pay less, score higher.
const W_NEWCAT := 7.0      ## documenting a NEW category (chases the category tier).
const W_NEWBIOME := 5.0    ## documenting a NEW biome (chases the biome tier).
const W_GOAL := 4.0        ## progress toward the active season goal.
const W_EXP := 5.0         ## progress toward an unmet expedition contract.
const W_POWER := 3.0       ## value multiplier on a species' power.
const W_MOVE_YIELD := 1.15 ## banking a move's resource yield.
const W_MOVE_BIOME := 3.0  ## reaching a NEW biome this season (season-goal + observation).
const W_MOVE_BONUS := 1.0  ## a site's draw/gear bonus action.
const W_DEV_PTS := 5.0     ## a gear/station's point value.
const W_DEV_PERK := 4.0    ## a gear/station's ongoing perk value.
const W_REST := 0.6        ## a small floor so resting is a last resort, never a stall.

# ---------------------------------------------------------------------
#  Species database — 37 unique species. power.kind is one of:
#   "none"                       — no power.
#   "gain"   {res, amt}          — WHEN documented, gain amt of res immediately.
#   "chain_cat" {cat, res, amt}  — ongoing: when you LATER document another species of
#                                   category cat, gain amt of res.
#   "chain_any" {res, amt}       — ongoing: when you LATER document ANY species, gain amt.
#   "season" {res, amt}          — ongoing: at each season boundary, gain amt of res.
#   "score_cat" {cat, per}       — end-game: +per per species of cat in your journal.
#   "score_biome" {per}          — end-game: +per per distinct biome in your journal.
#   "draw_rest" {n}              — ongoing: when you REST, draw n extra species to hand.
# ---------------------------------------------------------------------
const SPECIES_DB := {
	# --- mammals -----------------------------------------------------------
	"red_fox": {"name": "Red Fox", "biome": "grassland", "category": "mammal", "cost": {"forest": 1, "sighting": 1}, "points": 2, "power": {"kind": "gain", "res": "film", "amt": 1}},
	"gray_wolf": {"name": "Gray Wolf", "biome": "forest", "category": "mammal", "cost": {"forest": 2, "sighting": 1}, "points": 3, "power": {"kind": "chain_cat", "cat": "mammal", "res": "film", "amt": 1}},
	"brown_bear": {"name": "Brown Bear", "biome": "mountain", "category": "mammal", "cost": {"mountain": 2, "forest": 1, "sighting": 1}, "points": 4, "power": {"kind": "season", "res": "forest", "amt": 1}},
	"river_otter": {"name": "River Otter", "biome": "wetland", "category": "mammal", "cost": {"water": 2, "sighting": 1}, "points": 3, "power": {"kind": "gain", "res": "water", "amt": 1}},
	"mountain_goat": {"name": "Mountain Goat", "biome": "mountain", "category": "mammal", "cost": {"mountain": 2, "sighting": 1}, "points": 3, "power": {"kind": "gain", "res": "mountain", "amt": 1}},
	"white_tail_deer": {"name": "White-tailed Deer", "biome": "forest", "category": "mammal", "cost": {"forest": 1, "sun": 1}, "points": 2, "power": {"kind": "none"}},
	"harbor_seal": {"name": "Harbor Seal", "biome": "coast", "category": "mammal", "cost": {"water": 2, "sighting": 1}, "points": 3, "power": {"kind": "chain_any", "res": "sighting", "amt": 1}},
	# --- birds -------------------------------------------------------------
	"bald_eagle": {"name": "Bald Eagle", "biome": "coast", "category": "bird", "cost": {"water": 1, "mountain": 1, "sighting": 1}, "points": 4, "power": {"kind": "chain_cat", "cat": "bird", "res": "film", "amt": 1}},
	"great_owl": {"name": "Great Owl", "biome": "forest", "category": "bird", "cost": {"forest": 2, "sighting": 1}, "points": 3, "power": {"kind": "draw_rest", "n": 1}},
	"blue_heron": {"name": "Blue Heron", "biome": "wetland", "category": "bird", "cost": {"water": 2, "sighting": 1}, "points": 3, "power": {"kind": "gain", "res": "water", "amt": 1}},
	"hummingbird": {"name": "Hummingbird", "biome": "grassland", "category": "bird", "cost": {"sun": 1, "sighting": 1}, "points": 2, "power": {"kind": "gain", "res": "film", "amt": 1}},
	"peregrine_falcon": {"name": "Peregrine Falcon", "biome": "mountain", "category": "bird", "cost": {"mountain": 1, "sighting": 2}, "points": 4, "power": {"kind": "chain_any", "res": "film", "amt": 1}},
	"wood_duck": {"name": "Wood Duck", "biome": "wetland", "category": "bird", "cost": {"water": 1, "forest": 1}, "points": 2, "power": {"kind": "none"}},
	"sandpiper": {"name": "Sandpiper", "biome": "coast", "category": "bird", "cost": {"water": 1, "sun": 1}, "points": 2, "power": {"kind": "season", "res": "sighting", "amt": 1}},
	"kingfisher": {"name": "Kingfisher", "biome": "wetland", "category": "bird", "cost": {"water": 1, "sighting": 1}, "points": 3, "power": {"kind": "score_biome", "per": 1}},
	# --- reptiles ----------------------------------------------------------
	"painted_turtle": {"name": "Painted Turtle", "biome": "wetland", "category": "reptile", "cost": {"water": 1, "sighting": 1}, "points": 2, "power": {"kind": "gain", "res": "sun", "amt": 1}},
	"garter_snake": {"name": "Garter Snake", "biome": "grassland", "category": "reptile", "cost": {"sun": 1, "forest": 1}, "points": 2, "power": {"kind": "none"}},
	"desert_iguana": {"name": "Desert Iguana", "biome": "grassland", "category": "reptile", "cost": {"sun": 2, "sighting": 1}, "points": 3, "power": {"kind": "season", "res": "sun", "amt": 1}},
	"rock_lizard": {"name": "Rock Lizard", "biome": "mountain", "category": "reptile", "cost": {"mountain": 1, "sun": 1}, "points": 2, "power": {"kind": "gain", "res": "mountain", "amt": 1}},
	"sea_turtle": {"name": "Sea Turtle", "biome": "coast", "category": "reptile", "cost": {"water": 2, "sighting": 2}, "points": 5, "power": {"kind": "score_cat", "cat": "reptile", "per": 1}},
	"box_tortoise": {"name": "Box Tortoise", "biome": "forest", "category": "reptile", "cost": {"forest": 2, "sun": 1}, "points": 3, "power": {"kind": "gain", "res": "forest", "amt": 1}},
	# --- aquatic -----------------------------------------------------------
	"rainbow_trout": {"name": "Rainbow Trout", "biome": "wetland", "category": "aquatic", "cost": {"water": 2}, "points": 2, "power": {"kind": "gain", "res": "film", "amt": 1}},
	"river_salmon": {"name": "River Salmon", "biome": "coast", "category": "aquatic", "cost": {"water": 2, "sighting": 1}, "points": 3, "power": {"kind": "chain_cat", "cat": "aquatic", "res": "water", "amt": 1}},
	"spotted_frog": {"name": "Spotted Frog", "biome": "wetland", "category": "aquatic", "cost": {"water": 1, "forest": 1}, "points": 2, "power": {"kind": "none"}},
	"crayfish": {"name": "Crayfish", "biome": "wetland", "category": "aquatic", "cost": {"water": 1, "sun": 1}, "points": 2, "power": {"kind": "gain", "res": "sighting", "amt": 1}},
	"tide_crab": {"name": "Tide Crab", "biome": "coast", "category": "aquatic", "cost": {"water": 1, "sighting": 1}, "points": 3, "power": {"kind": "season", "res": "water", "amt": 1}},
	"pond_newt": {"name": "Pond Newt", "biome": "wetland", "category": "aquatic", "cost": {"water": 2, "forest": 1}, "points": 3, "power": {"kind": "gain", "res": "water", "amt": 1}},
	# --- insects -----------------------------------------------------------
	"monarch_butterfly": {"name": "Monarch Butterfly", "biome": "grassland", "category": "insect", "cost": {"sun": 2}, "points": 2, "power": {"kind": "gain", "res": "film", "amt": 1}},
	"bumblebee": {"name": "Bumblebee", "biome": "grassland", "category": "insect", "cost": {"sun": 1, "forest": 1}, "points": 2, "power": {"kind": "chain_cat", "cat": "insect", "res": "sun", "amt": 1}},
	"dragonfly": {"name": "Dragonfly", "biome": "wetland", "category": "insect", "cost": {"water": 1, "sun": 1}, "points": 2, "power": {"kind": "gain", "res": "sighting", "amt": 1}},
	"firefly": {"name": "Firefly", "biome": "forest", "category": "insect", "cost": {"forest": 1, "sun": 1}, "points": 3, "power": {"kind": "season", "res": "film", "amt": 1}},
	"stag_beetle": {"name": "Stag Beetle", "biome": "forest", "category": "insect", "cost": {"forest": 2, "sighting": 1}, "points": 3, "power": {"kind": "score_cat", "cat": "insect", "per": 1}},
	# --- plants ------------------------------------------------------------
	"wild_orchid": {"name": "Wild Orchid", "biome": "forest", "category": "plant", "cost": {"forest": 2, "sun": 1}, "points": 3, "power": {"kind": "score_biome", "per": 1}},
	"alpine_flower": {"name": "Alpine Flower", "biome": "mountain", "category": "plant", "cost": {"mountain": 2, "sun": 1}, "points": 3, "power": {"kind": "season", "res": "sun", "amt": 1}},
	"marsh_reed": {"name": "Marsh Reed", "biome": "wetland", "category": "plant", "cost": {"water": 2, "forest": 1}, "points": 2, "power": {"kind": "gain", "res": "forest", "amt": 1}},
	"sagebrush": {"name": "Sagebrush", "biome": "grassland", "category": "plant", "cost": {"sun": 1, "forest": 1}, "points": 2, "power": {"kind": "gain", "res": "sun", "amt": 1}},
	"sequoia_sapling": {"name": "Sequoia Sapling", "biome": "forest", "category": "plant", "cost": {"forest": 3, "water": 1}, "points": 4, "power": {"kind": "score_cat", "cat": "plant", "per": 2}},
}

## Gear/station development. perk is one of:
##   "obs_discount"  — documenting costs 1 fewer sighting (min 0).
##   "film_on_doc"   — gain 1 film whenever you document a species.
##   "biome_bonus"   — end-game: +1 point per distinct biome in your journal.
##   "income" {income:{res:amt}} — at each season boundary, gain the income resources.
const GEAR_DB := {
	"binoculars": {"name": "Binoculars", "cost": {"sighting": 1, "film": 2}, "points": 2, "perk": "obs_discount"},
	"canteen": {"name": "Canteen", "cost": {"water": 2, "sun": 1}, "points": 2, "perk": "income", "income": {"water": 2}},
	"field_guide": {"name": "Field Guide", "cost": {"forest": 2, "sighting": 1}, "points": 3, "perk": "biome_bonus"},
	"camera": {"name": "Camera", "cost": {"film": 3, "sun": 1}, "points": 3, "perk": "film_on_doc"},
	"trek_poles": {"name": "Trekking Poles", "cost": {"mountain": 2, "forest": 1}, "points": 2, "perk": "income", "income": {"film": 1}},
	"ranger_tent": {"name": "Ranger Tent", "cost": {"forest": 2, "water": 2}, "points": 4, "perk": "income", "income": {"sun": 1, "film": 1}},
}

## Season goal tiles — one active per season (season index -> goal). metric is the
## per-season statistic the leader is judged on. Each leader (ties included, metric>0)
## scores GOAL_FIRST at the season boundary.
const GOAL_DB: Array = [
	{"id": "mammal_survey", "name": "Most mammals documented", "metric": "mammal"},
	{"id": "biome_trek", "name": "Most biomes visited", "metric": "biomes"},
	{"id": "field_census", "name": "Most species documented", "metric": "species"},
	{"id": "birdwatch", "name": "Most birds documented", "metric": "bird"},
]

## Expedition contracts — seven concrete end-game goals. Each player scores the bonus
## of EVERY contract they satisfy at final scoring (Cascadia-style bonus objectives).
## kind "cat_count" {cat, need} -> journal has >= need of that category.
## kind "biome_count" {need}   -> journal spans >= need distinct biomes.
const EXPEDITION_DB: Array = [
	{"id": "big_five", "name": "Big Five (5+ mammals)", "kind": "cat_count", "cat": "mammal", "need": 5, "bonus": 8},
	{"id": "ornithologist", "name": "Ornithologist (4+ birds)", "kind": "cat_count", "cat": "bird", "need": 4, "bonus": 6},
	{"id": "herpetology", "name": "Herpetology (3+ reptiles)", "kind": "cat_count", "cat": "reptile", "need": 3, "bonus": 5},
	{"id": "aquatic_survey", "name": "Aquatic Survey (3+ aquatic)", "kind": "cat_count", "cat": "aquatic", "need": 3, "bonus": 5},
	{"id": "pollinators", "name": "Pollinator Count (3+ insects)", "kind": "cat_count", "cat": "insect", "need": 3, "bonus": 5},
	{"id": "botanist", "name": "Botanist (4+ plants)", "kind": "cat_count", "cat": "plant", "need": 4, "bonus": 6},
	{"id": "grand_tour", "name": "Grand Tour (all 5 biomes)", "kind": "biome_count", "need": 5, "bonus": 7},
]

## The fixed Start camp + Trailhead sites (the trail endpoints, unlimited capacity).
const START_SITE := {"name": "Trailhead Camp", "biome": "forest", "yield": {}, "bonus": "none", "capacity": 99}
const END_SITE := {"name": "Summit Lookout", "biome": "mountain", "yield": {"sighting": 1}, "bonus": "none", "capacity": 99}

## The interior-site pool. Each season, TRAIL_LEN-2 (=7) of these are seeded in a
## shuffled order between the endpoints — the "trail re-seeds / bonuses shift" rule.
## bonus: "none" | "draw" (draw a species to hand) | "gear" (restock the gear shop).
const SITE_POOL: Array = [
	{"name": "Sunny Meadow", "biome": "grassland", "yield": {"sun": 2}, "bonus": "none", "capacity": 1},
	{"name": "Clear Spring", "biome": "wetland", "yield": {"water": 2}, "bonus": "none", "capacity": 1},
	{"name": "Old Grove", "biome": "forest", "yield": {"forest": 2}, "bonus": "none", "capacity": 1},
	{"name": "Rocky Pass", "biome": "mountain", "yield": {"mountain": 2}, "bonus": "none", "capacity": 1},
	{"name": "Birdwatch Blind", "biome": "wetland", "yield": {"sighting": 1, "water": 1}, "bonus": "draw", "capacity": 1},
	{"name": "Ranger Station", "biome": "forest", "yield": {"film": 1}, "bonus": "gear", "capacity": 1},
	{"name": "Coastal Tidepool", "biome": "coast", "yield": {"water": 1, "sighting": 1}, "bonus": "none", "capacity": 1},
	{"name": "Wildflower Field", "biome": "grassland", "yield": {"sun": 1, "sighting": 1}, "bonus": "none", "capacity": 1},
	{"name": "Fern Hollow", "biome": "forest", "yield": {"forest": 1, "water": 1}, "bonus": "none", "capacity": 2},
	{"name": "Alpine Ridge", "biome": "mountain", "yield": {"mountain": 1, "sighting": 1}, "bonus": "none", "capacity": 1},
	{"name": "Marsh Boardwalk", "biome": "wetland", "yield": {"water": 1, "forest": 1}, "bonus": "draw", "capacity": 2},
	{"name": "Overlook Point", "biome": "coast", "yield": {"sighting": 2}, "bonus": "none", "capacity": 1},
]

# =====================================================================
#  Seat controllers — the play-mode matrix
# =====================================================================
## Every seat carries a CONTROLLER KIND that decides HOW its turn is produced — WHO
## chooses the action, never WHAT the rules are. A turn is ALWAYS "produce one legal
## action; apply_action() validates it", so the kind is a pure input seam.
##
## TWO kinds are FULLY IMPLEMENTED:
##   * HUMAN_LOCAL  — a local human. The dispatcher (GameManager) BLOCKS and waits for
##                    UI input (board.gd). Supports LOCAL HOTSEAT pass-and-play.
##   * AI_HEURISTIC — the built-in weighted evaluator ai_choose(); auto-resolves.
##
## TWO kinds are DOCUMENTED FUTURE SEAMS — present as enum values, NOT wired, NOT
## stubbed. Using one FAILS LOUD (is_supported_kind is false; the dispatcher's default
## branch asserts). Each drops in as ONE dispatch case + one hook:
##   * AI_LLM  — a local-LLM-assisted seat that picks from legal_actions() via a local
##               HTTP endpoint (validated through is_legal/apply_action like any other).
##   * REMOTE  — a networked human/agent whose chosen action arrives over a transport.
enum ControllerKind { HUMAN_LOCAL, AI_HEURISTIC, AI_LLM, REMOTE }

const CONTROLLER_LABEL := {
	ControllerKind.HUMAN_LOCAL: "human",
	ControllerKind.AI_HEURISTIC: "ai",
	ControllerKind.AI_LLM: "llm",
	ControllerKind.REMOTE: "net",
}

# =====================================================================
#  Live state
# =====================================================================

var num_players := 4
var players: Array = []           ## each: player dict (see _new_player).
var controllers: Array[int] = []  ## per-seat ControllerKind (source of truth).
var seat_names: Array[String] = []

var trail: Array = []             ## the current season's TRAIL_LEN site dicts.
var offer: Array = []             ## shared face-up species ids ("" == an empty slot).
var gear_shop: Array = []         ## shared face-up gear ids ("" == an empty slot).
var deck: Array = []              ## species draw deck (ids).
var gear_deck: Array = []         ## gear draw deck (ids).

var season := 0                   ## 0..NUM_SEASONS-1.
var season_round := 0             ## rounds elapsed this season (cap terminator).
var current := 0                  ## whose turn it is.
var game_over := false
var winner := -1
var illegal_attempts := 0         ## apply_action() rejections (should stay 0 in play).
var turn_count := 0               ## total legal actions taken.
var log_lines: Array[String] = []
var final_scores: Array = []      ## filled by final_scoring(): per-player breakdown.

var _rng := RandomNumberGenerator.new()
var _seed := 0


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh game. seed_value == 0 -> random; any other value is fully
## deterministic. players in 2..5.
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
	controllers = []
	seat_names = []
	for i in num_players:
		var kind := ControllerKind.HUMAN_LOCAL if i == 0 else ControllerKind.AI_HEURISTIC
		controllers.append(kind)
		seat_names.append(_default_seat_name(i, kind))
	_build_species_deck()
	_build_gear_deck()
	season = 0
	season_round = 0
	current = 0
	game_over = false
	winner = -1
	illegal_attempts = 0
	turn_count = 0
	log_lines = []
	final_scores = []
	_seed_trail()
	offer = []
	for _i in OFFER_SIZE:
		offer.append(_draw_species())
	gear_shop = []
	for _i in GEAR_SHOP_SIZE:
		gear_shop.append(_draw_gear())
	for p in players:
		for _i in START_HAND:
			var id := _draw_species()
			if id != "":
				(p["hand"] as Array).append(id)
	_log("Expedition begins — %d explorers, seed %d. Season 1 of %d." % [num_players, _seed, NUM_SEASONS])


func _new_player(index: int) -> Dictionary:
	var res := {}
	var produced := {}
	var spent := {}
	for r in RESOURCES:
		res[r] = int(START_RESOURCES.get(r, 0))
		produced[r] = 0
		spent[r] = 0
	var pawns: Array = []
	for _i in PAWNS:
		pawns.append(0)  # all pawns start at the Start camp (site 0).
	return {
		"index": index,
		"is_ai": index != 0,
		"resources": res,
		"produced": produced,   # conservation ledger (gains after start).
		"spent": spent,         # conservation ledger (losses).
		"pawns": pawns,         # pawn positions along the trail.
		"journal": ([] as Array),   # documented species ids (the tableau).
		"hand": ([] as Array),      # species ids in the personal hand.
		"gear": ([] as Array),      # owned gear ids.
		"finished": false,          # all pawns reached the Trailhead this season.
		"goal_points": 0,           # accumulated season-goal points.
		"season_stats": _new_season_stats(),
	}


func _new_season_stats() -> Dictionary:
	var s := {"species": 0, "biomes": {}}
	for c in CATEGORIES:
		s[c] = 0
	return s


func _default_seat_name(seat: int, kind: int) -> String:
	if kind == ControllerKind.HUMAN_LOCAL:
		return "P%d You" % (seat + 1) if seat == 0 else "P%d Human" % (seat + 1)
	if kind == ControllerKind.REMOTE:
		return "P%d Net" % (seat + 1)
	return "P%d AI" % (seat + 1)


# =====================================================================
#  Seat-controller configuration + queries
# =====================================================================

func configure_seats(kinds: Array, names: Array = []) -> void:
	assert(kinds.size() == num_players,
		"configure_seats: expected %d kinds, got %d" % [num_players, kinds.size()])
	var new_controllers: Array[int] = []
	var new_names: Array[String] = []
	for i in num_players:
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
	_sync_is_ai()


## HUMAN_LOCAL and AI_HEURISTIC are supported; AI_LLM / REMOTE are open seams that
## fail loud if assigned (see the enum doc + the dispatcher default branch).
func is_supported_kind(kind: int) -> bool:
	return kind == ControllerKind.HUMAN_LOCAL or kind == ControllerKind.AI_HEURISTIC


func controller_of(seat: int) -> int:
	return int(controllers[seat]) if seat >= 0 and seat < controllers.size() else ControllerKind.AI_HEURISTIC


func seat_name(seat: int) -> String:
	return seat_names[seat] if seat >= 0 and seat < seat_names.size() else "P%d" % (seat + 1)


func is_human_seat(seat: int) -> bool:
	return controller_of(seat) == ControllerKind.HUMAN_LOCAL


func is_ai_seat(seat: int) -> bool:
	return controller_of(seat) == ControllerKind.AI_HEURISTIC


func human_seat_count() -> int:
	var n := 0
	for k in controllers:
		if int(k) == ControllerKind.HUMAN_LOCAL:
			n += 1
	return n


func _sync_is_ai() -> void:
	for i in num_players:
		if i < players.size():
			(players[i] as Dictionary)["is_ai"] = int(controllers[i]) != ControllerKind.HUMAN_LOCAL


# =====================================================================
#  Deck + trail construction (all seeded)
# =====================================================================

func _build_species_deck() -> void:
	deck = []
	var ids: Array = SPECIES_DB.keys()
	ids.sort()
	for _c in SPECIES_COPIES:
		for id in ids:
			deck.append(String(id))
	_shuffle(deck)


func _build_gear_deck() -> void:
	gear_deck = []
	var ids: Array = GEAR_DB.keys()
	ids.sort()
	for _c in GEAR_COPIES:
		for id in ids:
			gear_deck.append(String(id))
	_shuffle(gear_deck)


## Fisher-Yates with the seeded RNG (deterministic under _seed).
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _draw_species() -> String:
	if deck.is_empty():
		return ""
	return String(deck.pop_back())


func _draw_gear() -> String:
	if gear_deck.is_empty():
		return ""
	return String(gear_deck.pop_back())


## Build this season's trail: [Start camp] + 7 shuffled interior sites + [Trailhead].
## Deep-copies the site dicts so per-season mutation can never leak into the const pool.
func _seed_trail() -> void:
	var pool: Array = SITE_POOL.duplicate(true)
	_shuffle(pool)
	trail = []
	trail.append((START_SITE as Dictionary).duplicate(true))
	for i in TRAIL_LEN - 2:
		trail.append((pool[i] as Dictionary).duplicate(true))
	trail.append((END_SITE as Dictionary).duplicate(true))


# =====================================================================
#  Resource ledger — the ONLY paths that touch a pool (conservation-provable).
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


## Verify conservation for every player and resource: pool == start + produced - spent.
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
#  Gear perks + effective documentation cost
# =====================================================================

func has_gear_perk(p: Dictionary, perk: String) -> bool:
	for gid in p["gear"]:
		if String(GEAR_DB[gid]["perk"]) == perk:
			return true
	return false


func gear_perk_count(p: Dictionary, perk: String) -> int:
	var n := 0
	for gid in p["gear"]:
		if String(GEAR_DB[gid]["perk"]) == perk:
			n += 1
	return n


## The documentation cost for a species AFTER this player's gear discounts (the
## observation cost in sightings drops by 1 per Binoculars, floored at 0). Zero-valued
## entries are dropped so the cost dict stays clean for is_legal / _pay.
func effective_cost(p: Dictionary, species_id: String) -> Dictionary:
	var base: Dictionary = SPECIES_DB[species_id]["cost"]
	var out := {}
	for r in base.keys():
		out[r] = int(base[r])
	var disc := gear_perk_count(p, "obs_discount")
	if disc > 0 and out.has("sighting"):
		out["sighting"] = maxi(0, int(out["sighting"]) - disc)
	var clean := {}
	for r in out.keys():
		if int(out[r]) > 0:
			clean[r] = int(out[r])
	return clean


## The biomes this player can currently OBSERVE — the biome of each pawn's site.
func observed_biomes(p: Dictionary) -> Dictionary:
	var out := {}
	for pos in p["pawns"]:
		out[String(trail[int(pos)]["biome"])] = true
	return out


# =====================================================================
#  Trail helpers
# =====================================================================

## How many pawns (all players) currently stand on trail site `idx`.
func occupancy(idx: int) -> int:
	var n := 0
	for p in players:
		for pos in p["pawns"]:
			if int(pos) == idx:
				n += 1
	return n


func site_capacity(idx: int) -> int:
	return int(trail[idx]["capacity"])


# =====================================================================
#  Legality + the enumerated action list
# =====================================================================

## Is this action legal for player `p_index` right now? Rejects out-of-turn / finished /
## move-backward / occupied-site / off-biome / unaffordable / malformed actions.
func is_legal(p_index: int, action: Dictionary) -> bool:
	if game_over:
		return false
	if p_index != current:
		return false
	if p_index < 0 or p_index >= players.size():
		return false
	var p: Dictionary = players[p_index]
	if bool(p["finished"]):
		return false
	match String(action.get("type", "")):
		"MOVE":
			var pawn := int(action.get("pawn", -1))
			var to := int(action.get("to", -1))
			var pawns: Array = p["pawns"]
			if pawn < 0 or pawn >= pawns.size():
				return false
			if to <= int(pawns[pawn]) or to >= TRAIL_LEN:  # forward only, in range.
				return false
			return occupancy(to) < site_capacity(to)
		"DOCUMENT":
			var source := String(action.get("source", ""))
			var idx := int(action.get("index", -1))
			var species_id := _species_at(p, source, idx)
			if species_id == "":
				return false
			var species: Dictionary = SPECIES_DB[species_id]
			if not observed_biomes(p).has(String(species["biome"])):
				return false
			return _can_afford(p, effective_cost(p, species_id))
		"DEVELOP":
			var gidx := int(action.get("index", -1))
			if gidx < 0 or gidx >= gear_shop.size() or String(gear_shop[gidx]) == "":
				return false
			return _can_afford(p, GEAR_DB[gear_shop[gidx]]["cost"])
		"REST":
			return true
		_:
			return false


## The species id at (source, index) for this player, or "" if the slot is invalid/empty.
func _species_at(p: Dictionary, source: String, idx: int) -> String:
	if source == "offer":
		if idx < 0 or idx >= offer.size():
			return ""
		return String(offer[idx])
	if source == "hand":
		var hand: Array = p["hand"]
		if idx < 0 or idx >= hand.size():
			return ""
		return String(hand[idx])
	return ""


## Every legal action for `p_index`, in a fixed deterministic order:
## MOVE (pawn, then target asc), DOCUMENT (offer then hand, index asc), DEVELOP, REST.
## REST is always present for the active (unfinished) player, so a player can never stall.
func legal_actions(p_index: int) -> Array:
	var out: Array = []
	if game_over or p_index != current:
		return out
	var p: Dictionary = players[p_index]
	if bool(p["finished"]):
		return out
	var pawns: Array = p["pawns"]
	for pawn in pawns.size():
		for to in range(int(pawns[pawn]) + 1, TRAIL_LEN):
			if occupancy(to) < site_capacity(to):
				out.append({"type": "MOVE", "pawn": pawn, "to": to})
	var obs := observed_biomes(p)
	for i in offer.size():
		if is_legal(p_index, {"type": "DOCUMENT", "source": "offer", "index": i}):
			out.append({"type": "DOCUMENT", "source": "offer", "index": i})
	var hand: Array = p["hand"]
	for i in hand.size():
		if is_legal(p_index, {"type": "DOCUMENT", "source": "hand", "index": i}):
			out.append({"type": "DOCUMENT", "source": "hand", "index": i})
	for i in gear_shop.size():
		if is_legal(p_index, {"type": "DEVELOP", "index": i}):
			out.append({"type": "DEVELOP", "index": i})
	out.append({"type": "REST"})
	return out


# =====================================================================
#  Applying an action (exactly ONE action == one turn)
# =====================================================================

## Take `action` for player `p_index`. Returns true on success. An illegal action is
## REJECTED (state unchanged) and counted in illegal_attempts.
func apply_action(p_index: int, action: Dictionary) -> bool:
	if not is_legal(p_index, action):
		illegal_attempts += 1
		return false
	var p: Dictionary = players[p_index]
	match String(action["type"]):
		"MOVE":
			_do_move(p, int(action["pawn"]), int(action["to"]))
		"DOCUMENT":
			_do_document(p, String(action["source"]), int(action["index"]))
		"DEVELOP":
			_do_develop(p, int(action["index"]))
		"REST":
			_do_rest(p)
	turn_count += 1
	return true


func _do_move(p: Dictionary, pawn: int, to: int) -> void:
	(p["pawns"] as Array)[pawn] = to
	var site: Dictionary = trail[to]
	for r in (site["yield"] as Dictionary).keys():
		_gain(p, String(r), int(site["yield"][r]))
	(p["season_stats"]["biomes"] as Dictionary)[String(site["biome"])] = true
	match String(site["bonus"]):
		"draw":
			_draw_to_hand(p, 1)
		"gear":
			_restock_gear()
	if _all_pawns_at_end(p):
		p["finished"] = true
	_log("%s hikes to %s (%s)%s" % [seat_name(int(p["index"])), site["name"], site["biome"],
		"  [Trailhead reached]" if bool(p["finished"]) else ""])


func _all_pawns_at_end(p: Dictionary) -> bool:
	for pos in p["pawns"]:
		if int(pos) != TRAIL_LEN - 1:
			return false
	return true


func _draw_to_hand(p: Dictionary, n: int) -> int:
	var drawn := 0
	for _i in n:
		if (p["hand"] as Array).size() >= HAND_MAX:
			break
		var id := _draw_species()
		if id == "":
			break
		(p["hand"] as Array).append(id)
		drawn += 1
	return drawn


func _restock_gear() -> void:
	for i in gear_shop.size():
		if String(gear_shop[i]) == "":
			gear_shop[i] = _draw_gear()


func _do_document(p: Dictionary, source: String, idx: int) -> void:
	var species_id := _species_at(p, source, idx)
	var species: Dictionary = SPECIES_DB[species_id]
	_pay(p, effective_cost(p, species_id))
	# Remove the card from its source.
	if source == "offer":
		offer[idx] = _draw_species()  # refill the shared offer slot.
	else:
		(p["hand"] as Array).remove_at(idx)
	# Fire chain powers of species ALREADY in the journal, triggered by this new one.
	for existing_id in p["journal"]:
		var pw: Dictionary = SPECIES_DB[existing_id]["power"]
		match String(pw["kind"]):
			"chain_cat":
				if String(pw["cat"]) == String(species["category"]):
					_gain(p, String(pw["res"]), int(pw["amt"]))
			"chain_any":
				_gain(p, String(pw["res"]), int(pw["amt"]))
	# Add to the journal.
	(p["journal"] as Array).append(species_id)
	# Fire the new species' own immediate (when-documented) power.
	var power: Dictionary = species["power"]
	if String(power["kind"]) == "gain":
		_gain(p, String(power["res"]), int(power["amt"]))
	# Gear: a Camera grants film on every documentation.
	var cams := gear_perk_count(p, "film_on_doc")
	if cams > 0:
		_gain(p, "film", cams)
	# Season stats (for the season goals).
	var stats: Dictionary = p["season_stats"]
	stats["species"] = int(stats["species"]) + 1
	stats[String(species["category"])] = int(stats[String(species["category"])]) + 1
	_log("%s documents %s (%s, %s) — %d pts" % [seat_name(int(p["index"])), species["name"],
		species["category"], species["biome"], int(species["points"])])


func _do_develop(p: Dictionary, idx: int) -> void:
	var gear_id := String(gear_shop[idx])
	var gear: Dictionary = GEAR_DB[gear_id]
	_pay(p, gear["cost"])
	(p["gear"] as Array).append(gear_id)
	gear_shop[idx] = _draw_gear()
	_log("%s develops %s (station, %d pts)" % [seat_name(int(p["index"])), gear["name"], int(gear["points"])])


func _do_rest(p: Dictionary) -> void:
	_gain(p, "film", 2)
	var extra := 1
	for jid in p["journal"]:
		var pw: Dictionary = SPECIES_DB[jid]["power"]
		if String(pw["kind"]) == "draw_rest":
			extra += int(pw["n"])
	var drawn := _draw_to_hand(p, extra)
	_log("%s rests at camp — +2 film, drew %d species" % [seat_name(int(p["index"])), drawn])


# =====================================================================
#  Turn / season flow + the end trigger
# =====================================================================

func _next_unfinished_after(c: int) -> int:
	for step in range(1, num_players + 1):
		var idx := (c + step) % num_players
		if not bool(players[idx]["finished"]):
			return idx
	return -1


## Advance to the next actor. A season ends when every player is finished (all pawns at
## the Trailhead) OR the season round cap is hit; then season income + the season goal
## resolve, the trail re-seeds and pawns reset — or, after the 4th season, the game ends.
func advance_turn() -> void:
	if game_over:
		return
	if _every_player_finished():
		_end_season()
		return
	var next_idx := _next_unfinished_after(current)
	if next_idx < 0:
		_end_season()
		return
	if next_idx <= current:
		season_round += 1
	current = next_idx
	if season_round >= SEASON_ROUND_CAP:
		_end_season()


func _every_player_finished() -> bool:
	for p in players:
		if not bool(p["finished"]):
			return false
	return true


func _end_season() -> void:
	# 1) Season income: species "season" powers + gear "income" perks.
	for p in players:
		for jid in p["journal"]:
			var pw: Dictionary = SPECIES_DB[jid]["power"]
			if String(pw["kind"]) == "season":
				_gain(p, String(pw["res"]), int(pw["amt"]))
		for gid in p["gear"]:
			var gear: Dictionary = GEAR_DB[gid]
			if String(gear["perk"]) == "income":
				for r in (gear["income"] as Dictionary).keys():
					_gain(p, String(r), int(gear["income"][r]))
	# 2) Score the active season goal.
	_score_season_goal()
	# 3) Advance the season; either end the game or start the next season.
	season += 1
	if season >= NUM_SEASONS:
		game_over = true
		final_scoring()
		return
	_log("--- Season %d begins ---" % (season + 1))
	for p in players:
		p["finished"] = false
		var pawns: Array = p["pawns"]
		for i in pawns.size():
			pawns[i] = 0
		p["season_stats"] = _new_season_stats()
	season_round = 0
	current = 0
	_seed_trail()
	# Refill any depleted offer / gear-shop slots for the new season.
	for i in offer.size():
		if String(offer[i]) == "":
			offer[i] = _draw_species()
	_restock_gear()


## The season goal metric per player, then award GOAL_FIRST to every leader (metric > 0).
func _score_season_goal() -> void:
	var goal: Dictionary = GOAL_DB[season % GOAL_DB.size()]
	var metric := String(goal["metric"])
	var best := 0
	var vals: Array[int] = []
	for p in players:
		var v := _season_metric(p, metric)
		vals.append(v)
		best = maxi(best, v)
	if best <= 0:
		_log("Season goal '%s' — no leader." % goal["name"])
		return
	var leaders: Array[String] = []
	for pi in players.size():
		if vals[pi] == best:
			players[pi]["goal_points"] = int(players[pi]["goal_points"]) + GOAL_FIRST
			leaders.append(seat_name(pi))
	_log("Season goal '%s' -> %s (+%d)" % [goal["name"], ", ".join(leaders), GOAL_FIRST])


func _season_metric(p: Dictionary, metric: String) -> int:
	var stats: Dictionary = p["season_stats"]
	if metric == "species":
		return int(stats["species"])
	if metric == "biomes":
		return (stats["biomes"] as Dictionary).size()
	return int(stats.get(metric, 0))  # a category name (mammal / bird / ...).


## The AI takes its whole turn: choose the best legal action and apply it.
func ai_take_turn(p_index: int) -> Dictionary:
	var action := ai_choose(p_index)
	apply_action(p_index, action)
	return action


# =====================================================================
#  The heuristic AI (non-LLM, deterministic, real weighted evaluation)
# =====================================================================

## Pick the highest-scoring legal action. Enumerates ALL legal actions and scores each
## by a weighted evaluation of its concrete effects: species points + power synergy +
## progress toward season goals & expeditions + resource efficiency + diversity gain +
## trail-yield value. Deterministic: ties break to the lowest index in legal_actions().
func ai_choose(p_index: int) -> Dictionary:
	var options := legal_actions(p_index)
	if options.is_empty():
		return {"type": "REST"}
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
		"MOVE":
			var to := int(action["to"])
			var site: Dictionary = trail[to]
			var yield_val := W_MOVE_YIELD * _dict_value(site["yield"])
			var biome := String(site["biome"])
			var biome_bonus := 0.0
			if not (p["season_stats"]["biomes"] as Dictionary).has(biome):
				biome_bonus = W_MOVE_BIOME
			var act_bonus := 0.0
			if String(site["bonus"]) == "draw":
				act_bonus = W_MOVE_BONUS
			elif String(site["bonus"]) == "gear":
				act_bonus = W_MOVE_BONUS * 0.8
			return yield_val + biome_bonus + act_bonus
		"DOCUMENT":
			var species_id := _species_at(p, String(action["source"]), int(action["index"]))
			var species: Dictionary = SPECIES_DB[species_id]
			var pts := W_DOC_PTS * float(int(species["points"]))
			var cost := W_COST * _dict_value(effective_cost(p, species_id))
			var newcat := 0.0
			if _category_count(p, String(species["category"])) == 0:
				newcat = W_NEWCAT
			var newbiome := 0.0
			if not _journal_has_biome(p, String(species["biome"])):
				newbiome = W_NEWBIOME
			var power := W_POWER * _power_value(p, species)
			var goal := W_GOAL * _goal_progress_value(p, species)
			var exp := W_EXP * _expedition_progress_value(p, species)
			return pts + power + newcat + newbiome + goal + exp - cost
		"DEVELOP":
			var gear: Dictionary = GEAR_DB[gear_shop[int(action["index"])]]
			var pts2 := W_DEV_PTS * float(int(gear["points"]))
			var perk := W_DEV_PERK * _perk_value(p, gear)
			var cost2 := W_COST * _dict_value(gear["cost"])
			return pts2 + perk - cost2
		"REST":
			var draws := 1.0
			for jid in p["journal"]:
				var pw: Dictionary = SPECIES_DB[jid]["power"]
				if String(pw["kind"]) == "draw_rest":
					draws += float(int(pw["n"]))
			return W_REST + 2.0 * RESOURCE_VALUE["film"] * 0.5 + draws * 0.4
		_:
			return -INF


## The estimated value of a species' power to this player (rough expected worth).
func _power_value(p: Dictionary, species: Dictionary) -> float:
	var pw: Dictionary = species["power"]
	var remaining := float(maxi(1, NUM_SEASONS - season))
	match String(pw["kind"]):
		"gain":
			return float(RESOURCE_VALUE.get(String(pw["res"]), 1.0)) * float(int(pw["amt"]))
		"chain_cat":
			return 1.2 * float(RESOURCE_VALUE.get(String(pw["res"]), 1.0)) * float(int(pw["amt"]))
		"chain_any":
			return 2.0 * float(RESOURCE_VALUE.get(String(pw["res"]), 1.0)) * float(int(pw["amt"]))
		"season":
			return remaining * float(RESOURCE_VALUE.get(String(pw["res"]), 1.0)) * float(int(pw["amt"]))
		"score_cat":
			return 2.0 * float(int(pw["per"])) * float(maxi(1, _category_count(p, String(pw["cat"]))))
		"score_biome":
			return 2.0 * float(int(pw["per"])) * float(maxi(1, _journal_biome_count(p)))
		"draw_rest":
			return 1.5 * float(int(pw["n"]))
		_:
			return 0.0


## How much documenting this species advances the CURRENT season's goal.
func _goal_progress_value(p: Dictionary, species: Dictionary) -> float:
	var goal: Dictionary = GOAL_DB[season % GOAL_DB.size()]
	var metric := String(goal["metric"])
	if metric == "species":
		return 1.0
	if metric == "biomes":
		return 0.0  # advanced by MOVE, not DOCUMENT.
	if metric == String(species["category"]):
		return 1.5
	return 0.0


## How much documenting this species advances an as-yet-unmet expedition contract.
func _expedition_progress_value(p: Dictionary, species: Dictionary) -> float:
	var v := 0.0
	for exp in EXPEDITION_DB:
		if String(exp["kind"]) == "cat_count" and String(exp["cat"]) == String(species["category"]):
			var have := _category_count(p, String(species["category"]))
			var need := int(exp["need"])
			if have < need:
				# Closer to the threshold = more valuable; completing it = most.
				v += float(int(exp["bonus"])) / float(need) * (1.0 if have + 1 < need else 2.0)
		elif String(exp["kind"]) == "biome_count":
			if not _journal_has_biome(p, String(species["biome"])):
				var need2 := int(exp["need"])
				var have2 := _journal_biome_count(p)
				if have2 < need2:
					v += float(int(exp["bonus"])) / float(need2)
	return v


func _perk_value(p: Dictionary, gear: Dictionary) -> float:
	match String(gear["perk"]):
		"obs_discount":
			return 3.0
		"film_on_doc":
			return 2.5
		"biome_bonus":
			return float(maxi(1, _journal_biome_count(p)))
		"income":
			return float(maxi(1, NUM_SEASONS - season)) * _dict_value(gear["income"])
		_:
			return 0.0


func _dict_value(d: Dictionary) -> float:
	var v := 0.0
	for r in d.keys():
		v += float(RESOURCE_VALUE.get(r, 1.0)) * float(int(d[r]))
	return v


# =====================================================================
#  Journal analysis helpers (pure — also used by scoring + the probes)
# =====================================================================

func _category_count(p: Dictionary, category: String) -> int:
	var n := 0
	for jid in p["journal"]:
		if String(SPECIES_DB[jid]["category"]) == category:
			n += 1
	return n


func distinct_categories(p: Dictionary) -> int:
	var seen := {}
	for jid in p["journal"]:
		seen[String(SPECIES_DB[jid]["category"])] = true
	return seen.size()


func _journal_has_biome(p: Dictionary, biome: String) -> bool:
	for jid in p["journal"]:
		if String(SPECIES_DB[jid]["biome"]) == biome:
			return true
	return false


func _journal_biome_count(p: Dictionary) -> int:
	var seen := {}
	for jid in p["journal"]:
		seen[String(SPECIES_DB[jid]["biome"])] = true
	return seen.size()


func largest_category_size(p: Dictionary) -> int:
	var counts := {}
	for jid in p["journal"]:
		var c := String(SPECIES_DB[jid]["category"])
		counts[c] = int(counts.get(c, 0)) + 1
	var best := 0
	for c in counts.keys():
		best = maxi(best, int(counts[c]))
	return best


# =====================================================================
#  Scoring (pure component helpers — the final total is their SUM)
# =====================================================================

func score_species(p: Dictionary) -> int:
	var v := 0
	for jid in p["journal"]:
		v += int(SPECIES_DB[jid]["points"])
	return v


func score_categories(p: Dictionary) -> int:
	return CATEGORY_TIER[clampi(distinct_categories(p), 0, CATEGORY_TIER.size() - 1)]


func score_biomes(p: Dictionary) -> int:
	return BIOME_TIER[clampi(_journal_biome_count(p), 0, BIOME_TIER.size() - 1)]


func score_largest(p: Dictionary) -> int:
	return largest_category_size(p) * LARGEST_MULT


## End-game ongoing powers (species score_cat/score_biome) + gear biome_bonus.
func score_powers(p: Dictionary) -> int:
	var v := 0
	var biomes := _journal_biome_count(p)
	for jid in p["journal"]:
		var pw: Dictionary = SPECIES_DB[jid]["power"]
		if String(pw["kind"]) == "score_cat":
			v += int(pw["per"]) * _category_count(p, String(pw["cat"]))
		elif String(pw["kind"]) == "score_biome":
			v += int(pw["per"]) * biomes
	v += gear_perk_count(p, "biome_bonus") * biomes
	return v


func score_gear(p: Dictionary) -> int:
	var v := 0
	for gid in p["gear"]:
		v += int(GEAR_DB[gid]["points"])
	return v


func score_expeditions(p: Dictionary) -> int:
	var v := 0
	for exp in EXPEDITION_DB:
		if _expedition_met(p, exp):
			v += int(exp["bonus"])
	return v


func _expedition_met(p: Dictionary, exp: Dictionary) -> bool:
	if String(exp["kind"]) == "cat_count":
		return _category_count(p, String(exp["cat"])) >= int(exp["need"])
	if String(exp["kind"]) == "biome_count":
		return _journal_biome_count(p) >= int(exp["need"])
	return false


## A live score estimate (everything except is already-final) for the HUD.
func live_score(p_index: int) -> int:
	var p: Dictionary = players[p_index]
	return score_species(p) + score_categories(p) + score_biomes(p) + score_largest(p) \
		+ score_powers(p) + score_gear(p) + score_expeditions(p) + int(p["goal_points"])


## Compute every player's final breakdown + the winner. Each breakdown's components SUM
## to "total" (the probe checks this exactly). Winner tie-break: total, then species pts,
## then journal size, then gear count, then lowest index — always a single winner.
func final_scoring() -> void:
	final_scores = []
	for pi in players.size():
		var p: Dictionary = players[pi]
		var species := score_species(p)
		var categories := score_categories(p)
		var biomes := score_biomes(p)
		var largest := score_largest(p)
		var powers := score_powers(p)
		var gear := score_gear(p)
		var expeditions := score_expeditions(p)
		var goals := int(p["goal_points"])
		var total := species + categories + biomes + largest + powers + gear + expeditions + goals
		final_scores.append({
			"index": pi,
			"species": species,
			"categories": categories,
			"biomes": biomes,
			"largest": largest,
			"powers": powers,
			"gear": gear,
			"expeditions": expeditions,
			"goals": goals,
			"total": total,
		})
	winner = _decide_winner()
	_log("EXPEDITION COMPLETE — winner %s (%d pts)." % [seat_name(winner), int(final_scores[winner]["total"])])


func _decide_winner() -> int:
	var best := 0
	for pi in range(1, players.size()):
		if _beats(pi, best):
			best = pi
	return best


func _beats(a: int, b: int) -> bool:
	var sa: Dictionary = final_scores[a]
	var sb: Dictionary = final_scores[b]
	if int(sa["total"]) != int(sb["total"]):
		return int(sa["total"]) > int(sb["total"])
	if int(sa["species"]) != int(sb["species"]):
		return int(sa["species"]) > int(sb["species"])
	var ja := (players[a]["journal"] as Array).size()
	var jb := (players[b]["journal"] as Array).size()
	if ja != jb:
		return ja > jb
	var ga := (players[a]["gear"] as Array).size()
	var gb := (players[b]["gear"] as Array).size()
	if ga != gb:
		return ga > gb
	return a < b


# =====================================================================
#  Small helpers + logging
# =====================================================================

func active_goal() -> Dictionary:
	return GOAL_DB[season % GOAL_DB.size()]


func _fmt(d: Dictionary) -> String:
	var parts: Array[String] = []
	for r in RESOURCES:
		if d.has(r) and int(d[r]) != 0:
			parts.append("%d %s" % [int(d[r]), r])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 240:
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
		"rng_state": str(_rng.state),
		"controllers": controllers.duplicate(),
		"seat_names": seat_names.duplicate(),
		"players": players.duplicate(true),
		"trail": trail.duplicate(true),
		"offer": offer.duplicate(),
		"gear_shop": gear_shop.duplicate(),
		"deck": deck.duplicate(),
		"gear_deck": gear_deck.duplicate(),
		"season": season,
		"season_round": season_round,
		"current": current,
		"game_over": game_over,
		"winner": winner,
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
	controllers = []
	seat_names = []
	var saved_ctrl: Array = data.get("controllers", [])
	var saved_names: Array = data.get("seat_names", [])
	for i in num_players:
		if i < saved_ctrl.size():
			controllers.append(int(saved_ctrl[i]))
		else:
			controllers.append(ControllerKind.HUMAN_LOCAL if i == 0 else ControllerKind.AI_HEURISTIC)
		if i < saved_names.size():
			seat_names.append(String(saved_names[i]))
		else:
			seat_names.append(_default_seat_name(i, int(controllers[i])))
	_sync_is_ai()
	trail = _coerce_trail(data.get("trail", []))
	offer = _coerce_str_array(data.get("offer", []))
	gear_shop = _coerce_str_array(data.get("gear_shop", []))
	deck = _coerce_str_array(data.get("deck", []))
	gear_deck = _coerce_str_array(data.get("gear_deck", []))
	season = int(data.get("season", 0))
	season_round = int(data.get("season_round", 0))
	current = int(data.get("current", 0))
	game_over = bool(data.get("game_over", false))
	winner = int(data.get("winner", -1))
	illegal_attempts = int(data.get("illegal_attempts", 0))
	turn_count = int(data.get("turn_count", 0))
	final_scores = []
	for s_variant in data.get("final_scores", []):
		var s: Dictionary = s_variant
		final_scores.append({
			"index": int(s["index"]),
			"species": int(s["species"]),
			"categories": int(s["categories"]),
			"biomes": int(s["biomes"]),
			"largest": int(s["largest"]),
			"powers": int(s["powers"]),
			"gear": int(s["gear"]),
			"expeditions": int(s["expeditions"]),
			"goals": int(s["goals"]),
			"total": int(s["total"]),
		})


func _coerce_str_array(src: Array) -> Array:
	var out: Array = []
	for v in src:
		out.append(String(v))
	return out


func _coerce_trail(src: Array) -> Array:
	var out: Array = []
	for site_v in src:
		var site: Dictionary = site_v
		var yld := {}
		for r in (site.get("yield", {}) as Dictionary).keys():
			yld[String(r)] = int(site["yield"][r])
		out.append({
			"name": String(site["name"]),
			"biome": String(site["biome"]),
			"yield": yld,
			"bonus": String(site["bonus"]),
			"capacity": int(site["capacity"]),
		})
	return out


func _coerce_player(src: Dictionary) -> Dictionary:
	var res := {}
	var produced := {}
	var spent := {}
	for r in RESOURCES:
		res[r] = int((src.get("resources", {}) as Dictionary).get(r, 0))
		produced[r] = int((src.get("produced", {}) as Dictionary).get(r, 0))
		spent[r] = int((src.get("spent", {}) as Dictionary).get(r, 0))
	var pawns: Array = []
	for pos in src.get("pawns", []):
		pawns.append(int(pos))
	var journal: Array = []
	for c in src.get("journal", []):
		journal.append(String(c))
	var hand: Array = []
	for c in src.get("hand", []):
		hand.append(String(c))
	var gear: Array = []
	for c in src.get("gear", []):
		gear.append(String(c))
	var stats := _new_season_stats()
	var src_stats: Dictionary = src.get("season_stats", {})
	stats["species"] = int(src_stats.get("species", 0))
	var biomes := {}
	for b in (src_stats.get("biomes", {}) as Dictionary).keys():
		biomes[String(b)] = true
	stats["biomes"] = biomes
	for c in CATEGORIES:
		stats[c] = int(src_stats.get(c, 0))
	return {
		"index": int(src["index"]),
		"is_ai": bool(src.get("is_ai", int(src["index"]) != 0)),
		"resources": res,
		"produced": produced,
		"spent": spent,
		"pawns": pawns,
		"journal": journal,
		"hand": hand,
		"gear": gear,
		"finished": bool(src.get("finished", false)),
		"goal_points": int(src.get("goal_points", 0)),
		"season_stats": stats,
	}
