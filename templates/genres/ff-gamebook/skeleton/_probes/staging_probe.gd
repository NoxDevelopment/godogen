extends Node
## _probes/staging_probe.gd
## HARVEST SLICE 4 — MULTIPLAYER "STAGING" INPUT probe.
##
## Proves, headless and deterministically, that the additive staging layer on
## SessionState (scripts/session_state.gd) satisfies its four contracts:
##
##   (a) SP UNCHANGED  — a scripted play that uses ONLY the direct turn methods
##       (advance_passage / choose / roll / roll_luck) produces a state whose
##       checksum equals a fixed baseline AND survives a save_data/load_data
##       round-trip byte-identically. The staged buffer stays empty throughout.
##   (b) STAGING WORKS — submit_staged buffers an intent WITHOUT mutating
##       current_passage; two intents from different peers sit in the buffer in
##       submit order with their peer tags; reorder + discard curate it; a stale
##       id → apply_staged returns false; and applying the same action sequence
##       through submit_staged/apply_staged reproduces the direct-play checksum
##       EXACTLY (apply routes through the real choose/roll/advance path).
##   (c) DM OVERRIDES — dm_push_passage advances the passage (a DM push);
##       dm_override_roll replaces the last roll in roll_log.
##   (d) DETERMINISM + PERSISTENCE — same seed + same applied order → identical
##       checksum across two staged replays; and a populated staged buffer
##       round-trips through save_data/load_data unchanged.
##
## Drives the SessionState / Dice / Sheet autoloads exactly as the game does
## (Dice.show_popup=false resolves tests without the tray, per the template's
## headless/replay contract). Prints one DEBUG line ending in `fails=N`.

## Baseline checksum of the scripted direct play (below). Locked so any drift in
## the single-player turn path — not just a staging regression — trips the probe.
const CHK_BASELINE := 3253719362
## Fixed dice seed: makes the 2d6 tests in the scripted play reproducible.
const DICE_SEED := 20260716


func _fnv1a(s: String) -> int:
	# 32-bit FNV-1a over the UTF-8 bytes — masked every step so it never leaves
	# the 32-bit range (portable, overflow-free in GDScript's 64-bit ints).
	var hash: int = 2166136261
	for b in s.to_utf8_buffer():
		hash = (hash ^ b) & 0xFFFFFFFF
		hash = (hash * 16777619) & 0xFFFFFFFF
	return hash


## Canonical checksum of the session's observable state: the passage trail plus
## the load-bearing fields of every logged roll. Stable key order via JSON.
func _state_checksum() -> int:
	var rolls: Array = []
	for r in SessionState.roll_log:
		rolls.append({
			"stat": r.get("stat", ""),
			"target": r.get("target", 0),
			"die_a": r.get("die_a", 0),
			"die_b": r.get("die_b", 0),
			"total": r.get("total", 0),
			"success": r.get("success", false),
		})
	var payload := {
		"passages": SessionState.passage_history.duplicate(),
		"rolls": rolls,
		"current": SessionState.current_passage,
	}
	return _fnv1a(JSON.stringify(payload))


## Put Sheet + Dice + SessionState into a fixed, replay-safe starting state.
func _reset_deterministic() -> void:
	Dice.show_popup = false
	Sheet.skill = 9
	Sheet.stamina = 19
	Sheet.luck = 9
	Sheet.max_skill = 9
	Sheet.max_stamina = 19
	Sheet.max_luck = 9
	Sheet.provisions = 4
	Sheet.inventory.clear()
	Dice.set_seed(DICE_SEED)
	SessionState.reset_session()


## The scripted adventure, played with the DIRECT turn methods only.
func _play_direct() -> void:
	_reset_deterministic()
	SessionState.advance_passage("passage_1")
	SessionState.choose("passage_2", "cross the bridge")
	SessionState.advance_passage("passage_2")
	await SessionState.roll("skill")
	SessionState.choose("passage_5", "test your luck")
	SessionState.advance_passage("passage_5")
	await SessionState.roll_luck()
	SessionState.advance_passage("passage_7")


## The SAME adventure, but every turn is STAGED then APPLIED in submit order —
## same seed, same order → the applied path must match _play_direct exactly.
func _play_via_staging() -> void:
	_reset_deterministic()
	await SessionState.apply_staged(SessionState.submit_staged("advance", {"passage_id": "passage_1"}))
	await SessionState.apply_staged(SessionState.submit_staged("choose", {"next_id": "passage_2", "choice_text": "cross the bridge"}))
	await SessionState.apply_staged(SessionState.submit_staged("advance", {"passage_id": "passage_2"}))
	await SessionState.apply_staged(SessionState.submit_staged("roll", {"stat": "skill"}))
	await SessionState.apply_staged(SessionState.submit_staged("choose", {"next_id": "passage_5", "choice_text": "test your luck"}))
	await SessionState.apply_staged(SessionState.submit_staged("advance", {"passage_id": "passage_5"}))
	await SessionState.apply_staged(SessionState.submit_staged("roll_luck", {}))
	await SessionState.apply_staged(SessionState.submit_staged("advance", {"passage_id": "passage_7"}))


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- (a) SP UNCHANGED: direct play matches the locked baseline ------------
	await _play_direct()
	var chk_direct: int = _state_checksum()
	if chk_direct != CHK_BASELINE:
		fails += 1
		notes.append("baseline(%d!=%d)" % [chk_direct, CHK_BASELINE])
	# staged buffer stayed empty through a pure SP play
	if not SessionState.staged_actions.is_empty():
		fails += 1
		notes.append("sp-buffer-nonempty(%d)" % SessionState.staged_actions.size())
	# save/load round-trip is byte-identical for the direct play
	var saved_direct: Dictionary = SessionState.save_data()
	SessionState.load_data(saved_direct)
	if _state_checksum() != chk_direct:
		fails += 1
		notes.append("direct-roundtrip-drift")

	# --- (b) STAGING WORKS ----------------------------------------------------
	# submit buffers WITHOUT applying: current_passage must not move.
	_reset_deterministic()
	SessionState.advance_passage("passage_1")
	var before_submit: String = SessionState.current_passage
	var id_p1: String = SessionState.submit_staged("choose", {"next_id": "passage_2", "choice_text": "north"}, 11)
	var id_p2: String = SessionState.submit_staged("roll", {"stat": "skill"}, 22)
	if SessionState.current_passage != before_submit:
		fails += 1
		notes.append("submit-mutated-passage")
	# two intents, different peers, in submit order
	if SessionState.staged_actions.size() != 2:
		fails += 1
		notes.append("buffer-size(%d)" % SessionState.staged_actions.size())
	elif SessionState.staged_actions[0]["id"] != id_p1 \
			or SessionState.staged_actions[1]["id"] != id_p2 \
			or int(SessionState.staged_actions[0]["peer"]) != 11 \
			or int(SessionState.staged_actions[1]["peer"]) != 22 \
			or int(SessionState.staged_actions[0]["at"]) >= int(SessionState.staged_actions[1]["at"]):
		fails += 1
		notes.append("buffer-order/peer/at")
	# malformed submit rejected (blank arg) → "" and nothing buffered
	if SessionState.submit_staged("choose", {"next_id": ""}) != "" \
			or SessionState.submit_staged("bogus", {}) != "" \
			or SessionState.staged_actions.size() != 2:
		fails += 1
		notes.append("bad-submit-not-rejected")
	# reorder: move the roll (id_p2) to the front
	if not SessionState.reorder_staged(id_p2, 0) \
			or SessionState.staged_actions[0]["id"] != id_p2 \
			or SessionState.staged_actions[1]["id"] != id_p1:
		fails += 1
		notes.append("reorder")
	# discard the roll, leaving only the choose
	if not SessionState.discard_staged(id_p2) \
			or SessionState.staged_actions.size() != 1 \
			or SessionState.staged_actions[0]["id"] != id_p1:
		fails += 1
		notes.append("discard")
	# apply the survivor: routes through the real choose() → passage advances
	if not await SessionState.apply_staged(id_p1):
		fails += 1
		notes.append("apply-returned-false")
	SessionState.advance_passage("passage_2")  # the choose's target, as a page would
	if SessionState.current_passage != "passage_2" or not SessionState.staged_actions.is_empty():
		fails += 1
		notes.append("apply-side-effect")
	# stale/illegal id → apply/discard/reorder all report false
	if await SessionState.apply_staged(id_p1) \
			or SessionState.discard_staged("nope") \
			or SessionState.reorder_staged("nope", 0):
		fails += 1
		notes.append("stale-id-not-false")
	# apply routes IDENTICALLY to direct: staged full-play checksum == direct
	await _play_via_staging()
	var chk_staged: int = _state_checksum()
	if chk_staged != chk_direct:
		fails += 1
		notes.append("staged!=direct(%d!=%d)" % [chk_staged, chk_direct])

	# --- (c) DM OVERRIDES -----------------------------------------------------
	_reset_deterministic()
	SessionState.advance_passage("passage_1")
	await SessionState.roll("skill")
	var pre_hist: int = SessionState.passage_history.size()
	if not SessionState.dm_push_passage("passage_9") \
			or SessionState.current_passage != "passage_9" \
			or SessionState.passage_history.size() != pre_hist + 1:
		fails += 1
		notes.append("dm_push_passage")
	var last_before: Dictionary = SessionState.roll_log[SessionState.roll_log.size() - 1]
	var forced := {"stat": "skill", "target": 99, "die_a": 1, "die_b": 1,
		"total": 2, "success": true, "forced": true}
	var log_len_before: int = SessionState.roll_log.size()
	if not SessionState.dm_override_roll(forced) \
			or SessionState.roll_log.size() != log_len_before \
			or SessionState.roll_log[SessionState.roll_log.size() - 1] == last_before \
			or not bool(SessionState.roll_log[SessionState.roll_log.size() - 1].get("forced", false)):
		fails += 1
		notes.append("dm_override_roll")

	# --- (d) DETERMINISM + STAGED BUFFER PERSISTENCE --------------------------
	await _play_via_staging()
	var chk_s1: int = _state_checksum()
	await _play_via_staging()
	var chk_s2: int = _state_checksum()
	if chk_s1 != chk_s2:
		fails += 1
		notes.append("staged-nondeterministic(%d!=%d)" % [chk_s1, chk_s2])
	# a populated staged buffer round-trips through save/load unchanged
	_reset_deterministic()
	SessionState.advance_passage("passage_1")
	SessionState.submit_staged("choose", {"next_id": "passage_4", "choice_text": "left"}, 7)
	SessionState.submit_staged("roll_luck", {}, 8)
	var buf_before: String = JSON.stringify(SessionState.staged_actions)
	var counter_before: int = SessionState._stage_counter
	var saved: Dictionary = SessionState.save_data()
	# mutate live, then restore from the save → the buffer must come back intact
	SessionState.clear_staged()
	SessionState.load_data(saved)
	if JSON.stringify(SessionState.staged_actions) != buf_before \
			or SessionState._stage_counter != counter_before:
		fails += 1
		notes.append("staged-buffer-roundtrip")
	# back-compat: a pre-staging save (no staged_actions key) loads to an empty
	# buffer without error
	SessionState.load_data({"current_passage": "passage_1",
		"passage_history": ["passage_1"], "roll_log": []})
	if not SessionState.staged_actions.is_empty():
		fails += 1
		notes.append("legacy-load-not-empty")

	print("DEBUG: staging_probe chk_direct=%d chk_staged=%d chk_replay=%d notes=%s fails=%d => %s" % [
		chk_direct, chk_staged, chk_s2, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
