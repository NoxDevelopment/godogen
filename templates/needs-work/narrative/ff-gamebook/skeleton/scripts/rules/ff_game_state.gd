class_name FFGameState
extends RefCounted
## res://scripts/rules/ff_game_state.gd
## The GDD §5 `GameState` — the serializable, TINY unit that is at once the save
## payload, the net-sync packet and the replay seed:
##
##   GameState = { sectionId,
##                 sheets: { playerId -> AdventureSheet },   # SP: just "p1"
##                 codewords,                                # the shared "true path"
##                 rngSeed,                                  # per-run seed
##                 turn }                                    # monotonic turn counter
##
## Because the whole unified sheet lives in ONE IFState (Phase 1), each `sheets`
## entry is simply that player's `IFState.save_data()`. For byte-for-byte replay
## and MP host authority we also carry the live RNG positions of BOTH deterministic
## dice streams (the narrative-graph stream and the combat/luck stream), so a
## resumed or re-hosted session keeps rolling the identical sequence a
## non-interrupted run would have (GDD §5 "seeded per run … enables MP sync +
## replay/verify"). This object is pure data — the `Adventure` autoload builds it
## and applies it.

const VERSION := 1

var section_id: String = ""
var sheets: Dictionary = {}          # playerId -> IFState.save_data() dict
var codewords: Dictionary = {}       # mirror of the party's shared codewords (§5)
var rng_seed: int = 0
var turn: int = 0

## Replay/sync seams — the mid-stream RNG positions (not part of the §5 headline
## fields but required for deterministic resume).
var graph_dice_state: int = 0        # IFRunner's narrative-graph dice
var combat_dice_state: int = 0       # the combat/luck (FF rules-core) dice


## Build a GameState from its parts. `player_sheets` maps playerId -> the player's
## IFState.save_data() dict (SP passes { "p1": <state> }).
static func capture(
		p_section_id: String,
		player_sheets: Dictionary,
		p_codewords: Dictionary,
		p_rng_seed: int,
		p_graph_dice_state: int,
		p_combat_dice_state: int,
		p_turn: int) -> FFGameState:
	var gs := FFGameState.new()
	gs.section_id = p_section_id
	gs.sheets = player_sheets.duplicate(true)
	gs.codewords = p_codewords.duplicate(true)
	gs.rng_seed = p_rng_seed
	gs.graph_dice_state = p_graph_dice_state
	gs.combat_dice_state = p_combat_dice_state
	gs.turn = p_turn
	return gs


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"sectionId": section_id,
		"sheets": sheets.duplicate(true),
		"codewords": codewords.duplicate(true),
		"rngSeed": rng_seed,
		"graphDiceState": graph_dice_state,
		"combatDiceState": combat_dice_state,
		"turn": turn,
	}


static func from_dict(data: Dictionary) -> FFGameState:
	var gs := FFGameState.new()
	gs.section_id = str(data.get("sectionId", ""))
	gs.sheets = (data.get("sheets", {}) as Dictionary).duplicate(true)
	gs.codewords = (data.get("codewords", {}) as Dictionary).duplicate(true)
	gs.rng_seed = int(data.get("rngSeed", 0))
	gs.graph_dice_state = int(data.get("graphDiceState", 0))
	gs.combat_dice_state = int(data.get("combatDiceState", 0))
	gs.turn = int(data.get("turn", 0))
	return gs


func is_empty() -> bool:
	return sheets.is_empty() and section_id == ""


## The primary (single-player / leader) sheet payload, or {} for an empty state.
func primary_sheet(player_id: String = "p1") -> Dictionary:
	if sheets.has(player_id):
		return sheets[player_id]
	for k in sheets.keys():
		return sheets[k]
	return {}
