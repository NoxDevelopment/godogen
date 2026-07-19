extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager") AND the noir CASE engine.
## A noir detective game is deduction, not twitch: investigate locations to turn
## up CLUES, combine the right clues into DEDUCTIONS, and once the chain is
## complete, name the culprit. This holds that case — a data-driven catalogue of
## suspects / locations / clues / deductions + the player's progress — as pure,
## seedable-free, headless-testable logic. The investigation scene only reads
## this and forwards clicks (same separation as the other NoxDev engines).
##
## Lives in the "game_manager" + "persistent" groups and implements the
## save_data()/load_data() ABI contract, so godotsmith's save_system persists an
## in-progress case (clues found, deductions made) with no extra wiring.

signal case_changed  ## a clue found / deduction made / accusation (UI listens)

# =====================================================================
#  The CASE — "The Neon Alibi" (all data; swap it to author a new case)
# =====================================================================

const CULPRIT := "sol"

const SUSPECTS := {
	"vera": {"name": "Vera Cross", "role": "the torch singer"},
	"sol": {"name": "Sol Kessler", "role": "the fixer"},
	"mona": {"name": "Mona Reyes", "role": "the widow"},
}

## Locations you can investigate. Each examine reveals every clue staged there.
const LOCATIONS := {
	"office": {"name": "The victim's office"},
	"club": {"name": "The Neon Room (club)"},
	"alley": {"name": "The back alley"},
	"docks": {"name": "The waterfront docks"},
}

## Clues: id -> {name, location, desc}. A location's clues surface when examined.
const CLUES := {
	"ledger": {"name": "Doctored ledger", "location": "office", "desc": "Shipment takings, skimmed for months."},
	"cufflink": {"name": "Monogrammed cufflink", "location": "office", "desc": "Initials 'S.K.' under the desk."},
	"matchbook": {"name": "Club matchbook", "location": "club", "desc": "The Neon Room — a regular's book of matches."},
	"note": {"name": "Threat note", "location": "club", "desc": "'Pay up or sink' — the fixer's hand."},
	"shell": {"name": ".38 shell casing", "location": "alley", "desc": "Spent brass by the dumpster."},
	"tiretrack": {"name": "Tire tracks", "location": "alley", "desc": "A coupe's tread — Sol drives a coupe."},
	"manifest": {"name": "Shipping manifest", "location": "docks", "desc": "Where the skimmed crates were bound."},
}

## Deductions: id -> {name, requires:[clue ids], desc}. Unlock when all their
## clues are found; forming all of them lets you accuse.
const DEDUCTIONS := {
	"motive": {
		"name": "Motive: the skim",
		"requires": ["ledger", "manifest"],
		"desc": "Sol was bleeding the shipment money — a motive to silence the books.",
	},
	"means": {
		"name": "Means: the .38 + the note",
		"requires": ["shell", "note"],
		"desc": "The threat note and the spent .38 give both intent and weapon.",
	},
	"opportunity": {
		"name": "Opportunity: at the scene",
		"requires": ["matchbook", "tiretrack", "cufflink"],
		"desc": "Placed at the club and the alley, and in the office itself.",
	},
}

# =====================================================================
#  Progress state
# =====================================================================
var discovered: Array[String] = []      ## clue ids found.
var examined: Array[String] = []        ## location ids investigated.
var deductions_made: Array[String] = [] ## deduction ids formed.
var accused := ""                        ## suspect id accused ("" = none).
var closed := false                      ## the case is closed after an accusation.
var solved := false

var flags: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


# =====================================================================
#  Case lifecycle
# =====================================================================

func begin_case() -> void:
	discovered = []
	examined = []
	deductions_made = []
	accused = ""
	closed = false
	solved = false
	case_changed.emit()


## Investigate a location. Reveals every not-yet-found clue staged there and
## returns the ids newly discovered (so the UI can highlight what turned up).
func examine(location_id: String) -> Array[String]:
	var found: Array[String] = []
	if not LOCATIONS.has(location_id) or closed:
		return found
	if not examined.has(location_id):
		examined.append(location_id)
	for clue_id in CLUES.keys():
		if String(CLUES[clue_id]["location"]) == location_id and not discovered.has(clue_id):
			discovered.append(clue_id)
			found.append(clue_id)
	if not found.is_empty():
		case_changed.emit()
	return found


func clues_at(location_id: String) -> Array[String]:
	var out: Array[String] = []
	for clue_id in CLUES.keys():
		if String(CLUES[clue_id]["location"]) == location_id:
			out.append(clue_id)
	return out


func has_clue(clue_id: String) -> bool:
	return discovered.has(clue_id)


# =====================================================================
#  Deductions
# =====================================================================

## Can this deduction be formed now? (all its clues found, not already made.)
func can_form(deduction_id: String) -> bool:
	if not DEDUCTIONS.has(deduction_id) or deductions_made.has(deduction_id):
		return false
	for clue_id in DEDUCTIONS[deduction_id]["requires"]:
		if not discovered.has(String(clue_id)):
			return false
	return true


func form_deduction(deduction_id: String) -> bool:
	if not can_form(deduction_id):
		return false
	deductions_made.append(deduction_id)
	case_changed.emit()
	return true


## Deduction ids that are unlocked and not yet made.
func available_deductions() -> Array[String]:
	var out: Array[String] = []
	for id in DEDUCTIONS.keys():
		if can_form(String(id)):
			out.append(String(id))
	return out


# =====================================================================
#  Accusation
# =====================================================================

## You may accuse only once the full deduction chain is complete — noir plays
## fair: no naming a name on a hunch.
func can_accuse() -> bool:
	return not closed and deductions_made.size() == DEDUCTIONS.size()


## Name the culprit. Closes the case; solved iff the chain is complete AND the
## suspect is the real culprit. Returns whether it was solved.
func accuse(suspect_id: String) -> bool:
	if closed or not SUSPECTS.has(suspect_id) or not can_accuse():
		return false
	accused = suspect_id
	closed = true
	solved = suspect_id == CULPRIT
	if solved:
		set_flag("cases_solved", int(get_flag("cases_solved", 0)) + 1)
	case_changed.emit()
	return solved


func is_closed() -> bool:
	return closed


# =====================================================================
#  Flags
# =====================================================================

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func clear_flag(flag: String) -> void:
	flags.erase(flag)


# =====================================================================
#  Persistence
# =====================================================================

func save_data() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"discovered": discovered.duplicate(),
		"examined": examined.duplicate(),
		"deductions_made": deductions_made.duplicate(),
		"accused": accused,
		"closed": closed,
		"solved": solved,
	}


func load_data(data: Dictionary) -> void:
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	discovered = _to_strings(data.get("discovered", []))
	examined = _to_strings(data.get("examined", []))
	deductions_made = _to_strings(data.get("deductions_made", []))
	accused = String(data.get("accused", ""))
	closed = bool(data.get("closed", false))
	solved = bool(data.get("solved", false))
	case_changed.emit()


func _to_strings(a: Variant) -> Array[String]:
	var out: Array[String] = []
	for v in (a as Array):
		out.append(String(v))
	return out
