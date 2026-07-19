class_name IFSaveGame
extends RefCounted
## res://addons/nox_if_engine/if_savegame.gd
## The SAVE CONTRACT (spec P1) — one object, two clearly-labelled halves:
##
##   * longTerm  — the durable campaign record: progress, world/campaign vars &
##                 flags, and the carried roster (IFCampaignStore.save_data()).
##                 Present for a campaign save; null for a one-off.
##   * shortTerm — the live PLAY SESSION: the current module id, its seed, the
##                 dice position and the full IFState (current passage, session
##                 vars/items/flags, sheet, roll log). This is the P0
##                 runner.snapshot() payload. Present only when a session is in
##                 progress (a mid-module save); null BETWEEN modules.
##
## The split is the deliverable: a resume restores long-term always and short-term
## only if a session was live, and scene-scoped short-term state is physically in
## a different section from the durable long-term record — it cannot bleed across.
##
## This class is also the canonicalisation point: to_canonical_json() emits a
## sort-keyed, full-precision string, and content_hash() a SHA-256 over it, so a
## save is provably byte-identical across runs.
##
## Shape (`campaign_save.json`):
##   {
##     saveVersion: 1,
##     saveKind: "campaign" | "oneoff",
##     savedAt: "<iso8601 or ''>",
##     longTerm:  { <IFCampaignStore.save_data()> } | null,
##     shortTerm: {
##       moduleId, seed, dice_state, state:{ <IFState.save_data()> }
##     } | null
##   }

const SAVE_VERSION := 1

var save_kind: String = "campaign"
var saved_at: String = ""
var long_term: Variant = null       # Dictionary or null
var short_term: Variant = null      # Dictionary or null


func _init(kind: String = "campaign") -> void:
	save_kind = kind


static func from_dict(data: Dictionary) -> IFSaveGame:
	var s := IFSaveGame.new(str(data.get("saveKind", "campaign")))
	s.saved_at = str(data.get("savedAt", ""))
	s.long_term = data.get("longTerm", null)
	s.short_term = data.get("shortTerm", null)
	return s


static func from_file(path: String) -> IFSaveGame:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("IFSaveGame: could not read '%s'" % path)
		return IFSaveGame.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("IFSaveGame: '%s' is not a JSON object" % path)
		return IFSaveGame.new()
	return IFSaveGame.from_dict(parsed)


func set_long_term(store: IFCampaignStore) -> void:
	long_term = store.save_data() if store != null else null


func set_short_term(session_snapshot: Variant, module_id: String) -> void:
	# `session_snapshot` is an IFRunner.snapshot() (or null between modules).
	if typeof(session_snapshot) != TYPE_DICTIONARY:
		short_term = null
		return
	var snap: Dictionary = session_snapshot
	short_term = {
		"moduleId": module_id,
		"seed": int(snap.get("seed", 0)),
		"dice_state": int(snap.get("dice_state", 0)),
		"state": (snap.get("state", {}) as Dictionary).duplicate(true),
	}


func has_short_term() -> bool:
	return typeof(short_term) == TYPE_DICTIONARY


func has_long_term() -> bool:
	return typeof(long_term) == TYPE_DICTIONARY


## The runner-shaped snapshot for IFRunner.restore(), rebuilt from short_term.
func session_snapshot() -> Dictionary:
	if not has_short_term():
		return {}
	var st: Dictionary = short_term
	return {
		"seed": int(st.get("seed", 0)),
		"dice_state": int(st.get("dice_state", 0)),
		"state": (st.get("state", {}) as Dictionary).duplicate(true),
	}


func to_dict() -> Dictionary:
	return {
		"saveVersion": SAVE_VERSION,
		"saveKind": save_kind,
		"savedAt": saved_at,
		"longTerm": long_term,
		"shortTerm": short_term,
	}


## Deterministic serialisation: keys sorted, full float precision — so identical
## state produces an identical string (and hash) on every machine and every run.
func to_canonical_json() -> String:
	return JSON.stringify(to_dict(), "", true, true)


func to_pretty_json() -> String:
	return JSON.stringify(to_dict(), "  ", true, true)


## SHA-256 of the canonical serialisation — the byte-identical proof handle.
func content_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(to_canonical_json().to_utf8_buffer())
	return ctx.finish().hex_encode()
