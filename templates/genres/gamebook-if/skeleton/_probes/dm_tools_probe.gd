extends Node
## res://_probes/dm_tools_probe.gd
## Headless self-test for DmTools — the validated tool-schema adapter (AI-DM
## slice 1). Mirrors the gamebook-if boot-probe convention: drive the REAL API
## over the SAME session-setup pattern the boot probe uses (load the ff-2d6
## ruleset via PlaySession, begin the sample Thornwood one-off scenario with a
## FIXED seed), print ONE deterministic DEBUG line, quit non-zero on any failure.
## NO LLM, NO networking — slice 1 is fully deterministic.
##
## It proves the "LLM proposes, engine disposes" contract:
##   (a) ILLEGAL REJECTED   — apply("choose", bad id) -> ok=false illegal_choice,
##                            and the snapshot (passage id + sheet) is UNCHANGED.
##   (b) LEGAL == DIRECT     — a legal choice via DmTools lands on the SAME passage
##                            id + sheet as session.choose() called directly on a
##                            twin session with the same seed (faithful pass-through).
##   (c) PLAYS TO AN ENDING  — an always-first-legal-choice policy driven ENTIRELY
##                            through DmTools reaches is_ended()==true, bounded.
##   (d) READ-ONLY IS PURE   — snapshot / read_sheet / list_choices / inspect_passage
##                            / status leave the passage id unchanged.
##   (e) DETERMINISM         — two DmTools-driven runs (same seed + same policy)
##                            reach the identical ending id + outcome.
##
## Run:
##   Godot --headless --path <project> res://_probes/dm_tools_probe.tscn

const SCENARIO := "res://addons/nox_if_engine/data/scenarios/thornwood-crypt.json"
const SEED := 7
const MAX_STEPS := 32

var _checks: Array[String] = []
var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- schema shape: exactly one mutating tool, named `choose` ----------------
	PlaySession.begin_oneoff_scenario(SCENARIO, SEED)
	var dm: DmTools = DmTools.for_session(PlaySession)
	var schema: Array = dm.tool_schema()
	var mutating: Array = []
	var read_only: Array = []
	for entry in schema:
		if bool(entry.get("mutates", false)):
			mutating.append(str(entry.get("name")))
		else:
			read_only.append(str(entry.get("name")))
	_expect("schema_one_mutator",
		mutating == ["choose"]
		and read_only.has("inspect_passage") and read_only.has("list_choices")
		and read_only.has("read_sheet") and read_only.has("status"),
		"mutating=%s read_only=%s" % [mutating, read_only])

	# --- (a) ILLEGAL REJECTED — no mutation on an illegal proposal ---------------
	var before_pid: String = str(dm.snapshot().get("passage", {}).get("id", ""))
	var before_sheet: String = JSON.stringify(dm.snapshot().get("sheet", {}))
	var bad: Dictionary = dm.apply("choose", {"choice_id": "__does_not_exist__"})
	var after_pid: String = str(dm.snapshot().get("passage", {}).get("id", ""))
	var after_sheet: String = JSON.stringify(dm.snapshot().get("sheet", {}))
	_expect("illegal_rejected",
		bad.get("ok") == false and str(bad.get("error")) == "illegal_choice"
		and str(bad.get("choice_id")) == "__does_not_exist__"
		and (bad.get("legal") as Array).has("descend")
		and before_pid == after_pid and before_pid == "crypt_gate"
		and before_sheet == after_sheet,
		"err=%s pid %s->%s sheet_changed=%s" % [bad.get("error"), before_pid, after_pid, before_sheet != after_sheet])

	# --- unknown tool is rejected ----------------------------------------------
	var unknown: Dictionary = dm.apply("no_such_tool", {})
	_expect("unknown_tool_rejected",
		unknown.get("ok") == false and str(unknown.get("error")) == "unknown_tool",
		"err=%s" % unknown.get("error"))

	# --- (d) READ-ONLY IS PURE — reads never move the passage -------------------
	var read_pid_before: String = str(PlaySession.current_passage().get("id", ""))
	var _s: Dictionary = dm.snapshot()
	var r_sheet: Dictionary = dm.apply("read_sheet", {})
	var r_choices: Dictionary = dm.apply("list_choices", {})
	var r_passage: Dictionary = dm.apply("inspect_passage", {})
	var r_status: Dictionary = dm.apply("status", {})
	var read_pid_after: String = str(PlaySession.current_passage().get("id", ""))
	_expect("read_only_pure",
		r_sheet.get("ok") == true and r_choices.get("ok") == true
		and r_passage.get("ok") == true and r_status.get("ok") == true
		and str((r_passage.get("data", {}) as Dictionary).get("id", "")) == "crypt_gate"
		and read_pid_before == read_pid_after and read_pid_after == "crypt_gate",
		"pid %s->%s" % [read_pid_before, read_pid_after])

	# --- (b) LEGAL == DIRECT — adapter is a faithful pass-through ----------------
	# Twin A: direct session.choose on a fresh seeded session.
	PlaySession.begin_oneoff_scenario(SCENARIO, SEED)
	var direct_report: Dictionary = PlaySession.choose("descend")
	var direct_pid: String = str(PlaySession.current_passage().get("id", ""))
	var direct_sheet: String = JSON.stringify(PlaySession.sheet_view())
	# Twin B: identical fresh session, same seed, choose via DmTools.
	PlaySession.begin_oneoff_scenario(SCENARIO, SEED)
	var dm_b: DmTools = DmTools.for_session(PlaySession)
	var via_tool: Dictionary = dm_b.apply("choose", {"choice_id": "descend"})
	var tool_pid: String = str((via_tool.get("snapshot", {}) as Dictionary).get("passage", {}).get("id", ""))
	var tool_sheet: String = JSON.stringify((via_tool.get("snapshot", {}) as Dictionary).get("sheet", {}))
	_expect("legal_matches_direct",
		via_tool.get("ok") == true and not direct_report.is_empty()
		and direct_pid == "antechamber" and tool_pid == direct_pid
		and tool_sheet == direct_sheet,
		"direct=%s tool=%s sheet_equal=%s" % [direct_pid, tool_pid, tool_sheet == direct_sheet])

	# --- (c) PLAYS TO AN ENDING — always-first-legal policy through DmTools ------
	var run1: Dictionary = _play_first_legal(SEED)
	_expect("plays_to_ending",
		bool(run1.get("ended")) and int(run1.get("steps")) <= MAX_STEPS
		and str(run1.get("ending_id")) != "",
		"ended=%s steps=%d ending=%s" % [run1.get("ended"), int(run1.get("steps")), run1.get("ending_id")])

	# --- (e) DETERMINISM — same seed + same policy -> same terminal --------------
	var run2: Dictionary = _play_first_legal(SEED)
	_expect("deterministic",
		str(run1.get("ending_id")) == str(run2.get("ending_id"))
		and str(run1.get("outcome")) == str(run2.get("outcome"))
		and int(run1.get("steps")) == int(run2.get("steps")),
		"a=(%s,%s) b=(%s,%s)" % [run1.get("ending_id"), run1.get("outcome"), run2.get("ending_id"), run2.get("outcome")])

	# --- One DEBUG line ---------------------------------------------------------
	var all_ok: bool = _fails == 0
	print("DEBUG: dm_tools_probe — adapter=DmTools scenario=thornwood-crypt ruleset=ff-2d6 seed=%d tools=(mutating=%s read_only=%d) illegal_rejected=%s(no_mutation) legal_matches_direct=%s@%s plays_to_ending=%s(%s in %d steps) read_only_pure=%s deterministic=%s fails=%d %s => %s" % [
		SEED,
		mutating, read_only.size(),
		bad.get("ok") == false,
		via_tool.get("ok") == true, tool_pid,
		run1.get("ended"), str(run1.get("ending_id")), int(run1.get("steps")),
		read_pid_before == read_pid_after,
		str(run1.get("ending_id")) == str(run2.get("ending_id")),
		_fails, " ".join(_checks),
		"OK" if all_ok else "FAIL",
	])
	get_tree().quit(0 if all_ok else 1)


# --- helpers ----------------------------------------------------------------


## Drive a fresh seeded session to a terminal state ENTIRELY through DmTools,
## always applying the first legal choice. Returns the terminal facts + step count.
func _play_first_legal(seed: int) -> Dictionary:
	PlaySession.begin_oneoff_scenario(SCENARIO, seed)
	var dm: DmTools = DmTools.for_session(PlaySession)
	var steps: int = 0
	while not bool(dm.snapshot().get("ended", false)) and steps < MAX_STEPS:
		var choices: Array = dm.snapshot().get("choices", [])
		if choices.is_empty():
			break
		var first_id: String = str((choices[0] as Dictionary).get("id", ""))
		var res: Dictionary = dm.apply("choose", {"choice_id": first_id})
		if res.get("ok") != true:
			break
		steps += 1
	var snap: Dictionary = dm.snapshot()
	return {
		"ended": bool(snap.get("ended", false)),
		"ending_id": str((snap.get("ending", {}) as Dictionary).get("id", "")),
		"outcome": str(snap.get("outcome", "")),
		"steps": steps,
	}


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		_checks.append("%s=FAIL(%s)" % [label, detail])
	else:
		_checks.append("%s=ok" % label)
