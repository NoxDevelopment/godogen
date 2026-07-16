extends Node
## res://_probes/ai_narration_probe.gd
## Headless self-test for the AI-DM ASYNC NARRATION seam (AI-DM slice 2). Mirrors
## the gamebook-if boot-probe / dm_tools-probe convention: drive the REAL API over
## the SAME session setup (load ff-2d6 via PlaySession, begin the sample Thornwood
## one-off with a FIXED seed), print ONE deterministic DEBUG line, quit non-zero on
## any failure. It proves the slice-2 contract: narration is DISPLAY-ONLY and
## ASYNC, the computed engine is NEVER touched, and any failure is inert.
##
##   (default) DISABLED BY DEFAULT — AiDm.enabled == false as shipped.
##   (a) COMPUTED IDENTICAL      — a full first-legal play with narration OFF has a
##                                 stable checksum (passage ids + sheet + choices +
##                                 ending), and it equals the checksum with narration
##                                 ON: the `enabled` flag NEVER changes the mechanics.
##   (b) UNREACHABLE -> INERT     — with enabled=true but Ollama pointed at a DEAD
##                                 port, request_narration -> narration_ready("")
##                                 fires within the hard timeout (NO crash, NO hang),
##                                 and the mechanics (passage id, sheet, choices,
##                                 ended) are UNCHANGED by the narration call:
##                                 narration is display-only.
##   (c) DETERMINISM             — the computed play is bit-identical across runs and
##                                 independent of `enabled`.
##
## The probe PASSES WITHOUT a live LLM: (b) uses a dead port so the fail-then-inert
## path is exercised deterministically. No running Ollama is required.
##
## Run:
##   Godot --headless --path <project> res://_probes/ai_narration_probe.tscn

const SCENARIO := "res://addons/nox_if_engine/data/scenarios/thornwood-crypt.json"
const SEED := 7
const MAX_STEPS := 32
## A port that refuses immediately -> transport failure well inside the timeout.
const DEAD_HOST := "http://127.0.0.1:1"
const PROBE_TIMEOUT := 2.0
## Watchdog > timeout: if the signal has not fired by here the seam HUNG (a bug).
const WATCHDOG := 8.0

var _checks: Array[String] = []
var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- (default) DISABLED BY DEFAULT ------------------------------------------
	_expect("disabled_by_default", AiDm.enabled == false, "enabled=%s" % AiDm.enabled)

	# --- (a) COMPUTED IDENTICAL + (c) DETERMINISM -------------------------------
	# Baseline: the computed play with narration OFF (the shipped default).
	AiDm.enabled = false
	var off_a := _play_checksum(SEED)
	var off_b := _play_checksum(SEED)
	_expect("computed_deterministic_off", off_a == off_b, "%s vs %s" % [off_a, off_b])

	# Turn narration ON: the checksum of the SAME computed play must be UNCHANGED —
	# `enabled` only adds display prose, never a mechanic. (No network here: the
	# checksum path never calls request_narration.)
	AiDm.enabled = true
	var on_a := _play_checksum(SEED)
	var on_b := _play_checksum(SEED)
	_expect("computed_deterministic_on", on_a == on_b, "%s vs %s" % [on_a, on_b])
	_expect("mechanics_identical_on_vs_off", on_a == off_a,
		"on=%s off=%s" % [on_a, off_a])
	AiDm.enabled = false

	# --- (b) UNREACHABLE -> INERT, DISPLAY-ONLY ---------------------------------
	var un := await _prove_unreachable_inert()
	_expect("narration_fires_within_timeout",
		bool(un.get("fired")) and float(un.get("waited")) < WATCHDOG,
		"fired=%s waited=%.2f" % [un.get("fired"), float(un.get("waited"))])
	_expect("narration_empty_on_failure",
		str(un.get("text")) == "" and str(un.get("pid")) == "crypt_gate",
		"text=%s pid=%s" % [un.get("text"), un.get("pid")])
	_expect("mechanics_unchanged_by_narration",
		bool(un.get("unchanged")),
		"before=%s after=%s" % [un.get("before"), un.get("after")])

	# --- One DEBUG line ---------------------------------------------------------
	var all_ok: bool = _fails == 0
	print("DEBUG: ai_narration_probe — seam=AiDm(slice2) scenario=thornwood-crypt ruleset=ff-2d6 seed=%d disabled_by_default=%s computed_checksum=(off=%s on=%s identical=%s) determinism=(off=%s on=%s) unreachable=(host=%s fired=%s within=%.2fs text_empty=%s mechanics_unchanged=%s) fails=%d %s => %s" % [
		SEED,
		AiDm.enabled == false,
		off_a.substr(0, 12), on_a.substr(0, 12), on_a == off_a,
		off_a == off_b, on_a == on_b,
		DEAD_HOST, un.get("fired"), float(un.get("waited")),
		str(un.get("text")) == "", un.get("unchanged"),
		_fails, " ".join(_checks),
		"OK" if all_ok else "FAIL",
	])
	get_tree().quit(0 if all_ok else 1)


# --- helpers ----------------------------------------------------------------


## Drive a fresh seeded session to a terminal state, always taking the FIRST legal
## choice, and hash the whole computed play: at each step the passage id, the
## ruleset sheet view, and the offered (engine-gated) choice ids, plus the terminal
## ending id + outcome. This is the "computed behaviour" fingerprint; it must not
## depend on AiDm.enabled (narration is display-only) — proven by comparing on/off.
func _play_checksum(seed: int) -> String:
	PlaySession.begin_oneoff_scenario(SCENARIO, seed)
	var parts: Array[String] = []
	var steps := 0
	while not PlaySession.is_ended() and steps < MAX_STEPS:
		var p := PlaySession.current_passage()
		parts.append("P:" + str(p.get("id", "")))
		parts.append("S:" + JSON.stringify(PlaySession.sheet_view()))
		var ids: Array[String] = []
		for ch in PlaySession.available_choices():
			ids.append(str(ch.get("id", "")))
		parts.append("C:" + ",".join(ids))
		if ids.is_empty():
			break
		PlaySession.choose(ids[0])
		steps += 1
	parts.append("END:%s:%s" % [str(PlaySession.ending().get("id", "")), PlaySession.outcome()])
	return "\n".join(parts).sha256_text()


## A compact fingerprint of the CURRENT mechanical state (passage id + sheet +
## offered choices + ended). Used to prove request_narration changes nothing.
func _mechanics_sig() -> String:
	var ids: Array[String] = []
	for ch in PlaySession.available_choices():
		ids.append(str(ch.get("id", "")))
	return "%s|%s|%s|%s" % [
		str(PlaySession.current_passage().get("id", "")),
		JSON.stringify(PlaySession.sheet_view()),
		",".join(ids),
		str(PlaySession.is_ended()),
	]


## Enable narration, point the provider at a DEAD port, fire one request, and prove
## it resolves to narration_ready("") within the timeout without hanging, leaving
## the mechanics untouched. Returns the observed facts for assertion.
func _prove_unreachable_inert() -> Dictionary:
	AiDm.enabled = true
	ProjectSettings.set_setting("ai_dm/host", DEAD_HOST)
	ProjectSettings.set_setting("ai_dm/timeout_seconds", PROBE_TIMEOUT)

	PlaySession.begin_oneoff_scenario(SCENARIO, SEED)
	var passage := PlaySession.current_passage()
	var state := PlaySession.active_state()
	var before := _mechanics_sig()

	var got := {"fired": false, "pid": "", "text": "<unset>"}
	AiDm.narration_ready.connect(
		func(pid: String, txt: String) -> void:
			got["fired"] = true
			got["pid"] = pid
			got["text"] = txt,
		CONNECT_ONE_SHOT)

	AiDm.request_narration(passage, state)

	var waited := 0.0
	while not bool(got["fired"]) and waited < WATCHDOG:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1

	var after := _mechanics_sig()
	got["waited"] = waited
	got["before"] = before
	got["after"] = after
	got["unchanged"] = before == after

	# Restore the shipped defaults so we leave no global state behind.
	AiDm.enabled = false
	ProjectSettings.set_setting("ai_dm/host", AiDm.DEF_HOST)
	ProjectSettings.set_setting("ai_dm/timeout_seconds", AiDm.DEF_TIMEOUT)
	return got


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		_checks.append("%s=FAIL(%s)" % [label, detail])
	else:
		_checks.append("%s=ok" % label)
