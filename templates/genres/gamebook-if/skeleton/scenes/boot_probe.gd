extends Node
## res://scenes/boot_probe.gd
## Headless boot probe for the gamebook-if template (mirrors the ff-gamebook /
## nox_if_engine / nox_netcode probe convention: drive the real API, print ONE
## deterministic DEBUG line, quit non-zero on any failure). It proves the whole
## PLAYABLE loop over the computed nox_if_engine — NO LLM, NO networking — in one
## seeded process:
##
##   * PASSAGE RENDER  — the sample one-off opens at its start passage with text,
##     and the real play scene boots clean and renders it with choice buttons.
##   * GATED CHOICE    — at the iron door the `unlock` choice is offered only
##     because item.iron_key >= 1 (proven closed on a keyless state).
##   * RESOLVED DICE   — the guardian SKILL test resolves through the engine's
##     generic resolver and surfaces as a tray roll on the turn it happens.
##   * EFFECT          — gold 0 -> 15 (a var add + a guardian-win var add), a
##     torch granted, the iron key consumed by the unlock choice.
##   * ENDING          — the victory ending is reached deterministically.
##   * SAVE/LOAD       — a mid-adventure IFSaveGame round-trips: the resumed run
##     reaches the identical ending + gold as the uninterrupted run.
##   * CAMPAIGN        — the Crown of Embers campaign plays module 1 -> between
##     modules -> module 2 -> campaign complete via IFCampaignRunner.
##   * AI OPTIONAL     — AiDm is disabled + inert; play reaches the ending with it
##     doing nothing.
##
## Run:
##   Godot --headless --path <project> res://scenes/boot_probe.tscn

const SCENARIO := "res://addons/nox_if_engine/data/scenarios/thornwood-crypt.json"
const CAMPAIGN := "res://addons/nox_if_engine/data/campaigns/crown-of-embers.campaign.json"
const GOLDEN := ["descend", "search_sarcophagus", "pry_open", "unlock"]
const SEED_SCAN_MAX := 512

var _checks: Array[String] = []
var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# 0) Deterministic seed: first whose golden play reaches the victory ending.
	var win_seed := _find_victory_seed()
	_expect("victory_seed", win_seed >= 0, str(win_seed))

	# 1) Begin the sample one-off through PlaySession (the real UI bridge).
	PlaySession.begin_oneoff_scenario(SCENARIO, win_seed)
	var start := PlaySession.current_passage()
	_expect("passage_render",
		str(start.get("id")) == "crypt_gate" and not str(start.get("text", "")).is_empty(),
		"start=%s" % start.get("id"))

	# Sheet HUD is built from the ruleset sheetTemplate (attributes + resources).
	var sheet := PlaySession.sheet_view()
	_expect("sheet_from_template",
		(sheet.get("attributes", []) as Array).size() == 3
		and (sheet.get("resources", []) as Array).size() == 2,
		"attrs=%d res=%d" % [(sheet.get("attributes", []) as Array).size(), (sheet.get("resources", []) as Array).size()])

	# 2) Walk the golden path, capturing effects + the gate + the dice check.
	var gold_start := PlaySession.active_state().get_var("gold")
	PlaySession.choose("descend")                  # -> antechamber: gold +5, torch granted
	var gold_antechamber := PlaySession.active_state().get_var("gold")
	var torch_ok := PlaySession.active_state().has_item("torch")
	PlaySession.choose("search_sarcophagus")       # -> sarcophagus: iron_key granted
	var key_ok := PlaySession.active_state().has_item("iron_key")
	PlaySession.choose("pry_open")                 # -> dart_trap (auto luck test) -> iron_door
	var trap_rolls := PlaySession.active_state().roll_log.size()

	var at_iron_door := str(PlaySession.current_passage().get("id")) == "iron_door"
	var gate_open := PlaySession.is_choice_available("unlock")
	var gate_closed_keyless := not _gate_would_open_keyless()
	_expect("gated_choice", at_iron_door and gate_open and gate_closed_keyless,
		"door=%s open=%s closed_keyless=%s" % [at_iron_door, gate_open, gate_closed_keyless])

	var report := PlaySession.choose("unlock")     # consume key -> guardian (auto SKILL test) -> ending
	var key_consumed := PlaySession.active_state().get_item("iron_key") == 0
	var guardian_roll: Dictionary = {}
	for roll in report.get("rolls", []):
		if str(roll.get("rule")) == "test":
			guardian_roll = roll
	_expect("dice_check_resolved",
		not guardian_roll.is_empty() and trap_rolls >= 1,
		"guardian_band=%s total=%s target=%s trap_rolls=%d" % [
			guardian_roll.get("band"), guardian_roll.get("total"), guardian_roll.get("target"), trap_rolls])

	var final_gold := PlaySession.active_state().get_var("gold")
	_expect("effect_applied",
		gold_antechamber == gold_start + 5.0 and torch_ok and key_ok and key_consumed and final_gold == 15.0,
		"gold=%s torch=%s key_consumed=%s" % [final_gold, torch_ok, key_consumed])

	var ending := PlaySession.ending()
	_expect("ending_reached",
		PlaySession.is_ended() and str(ending.get("kind")) == "victory",
		"ending=%s" % ending)
	var main_rolls := PlaySession.active_state().roll_log.size()

	# 3) Save/load round-trips through IFSaveGame (mid-adventure short-term save).
	var save_load_ok := _prove_save_load(win_seed)
	_expect("save_load", save_load_ok)

	# 4) Campaign flow (IFCampaignRunner): module 1 -> boundary -> module 2 -> done.
	var campaign_ok := _prove_campaign()
	_expect("campaign", campaign_ok)

	# 5) The AI-DM seam is disabled + inert — play reached the ending without it.
	_expect("ai_disabled", AiDm.enabled == false)
	_expect("ai_inert",
		AiDm.narrate_passage({}, null) == ""
		and AiDm.review_choices([1, 2], null) == [1, 2]
		and AiDm.dm_intervene("x", {}) == false)

	# 6) The real play scene boots clean and renders the passage + choice buttons.
	var scene_ok := await _prove_play_scene(win_seed)
	_expect("play_scene_boots", scene_ok)

	# --- One DEBUG line ---------------------------------------------------------
	var all_ok := _fails == 0
	print("DEBUG: gamebook-if playable core — flow=oneoff+campaign scenario=thornwood-crypt ruleset=ff-2d6 win_seed=%d passage_render=%s gated_choice=unlock@iron_door(open_with_key,closed_keyless) dice_check=(%s 2d6=%s vs SKILL %s -> %s band=%s) effect=(gold %d->%d, torch granted, iron_key consumed) ending=%s(%s) save_load=%s campaign=%s(%s) ai=disabled+inert play_scene=boots rolls=%d fails=%d %s => %s" % [
		win_seed,
		str(start.get("id")) == "crypt_gate",
		guardian_roll.get("rule", "?"), str(guardian_roll.get("total", "?")),
		str(guardian_roll.get("target", "?")), str(guardian_roll.get("success", "?")),
		guardian_roll.get("band", "?"),
		int(gold_start), int(final_gold),
		str(ending.get("id")), str(ending.get("kind")),
		save_load_ok,
		"crown-of-embers", _campaign_status,
		main_rolls,
		_fails, " ".join(_checks),
		"OK" if all_ok else "FAIL",
	])
	get_tree().quit(0 if all_ok else 1)


# --- helpers ----------------------------------------------------------------


var _campaign_status := "?"


func _find_victory_seed() -> int:
	for s in range(1, SEED_SCAN_MAX + 1):
		if _play_golden_kind(s) == "victory":
			return s
	return -1


func _play_golden_kind(seed: int) -> String:
	PlaySession.begin_oneoff_scenario(SCENARIO, seed)
	for cid in GOLDEN:
		if PlaySession.is_ended():
			break
		if PlaySession.is_choice_available(cid):
			PlaySession.choose(cid)
	return str(PlaySession.ending().get("kind", ""))


## The iron-door `unlock` gate evaluated on a fresh, keyless state — the gate's
## ground truth (its authored condition, with no key present).
func _gate_would_open_keyless() -> bool:
	var scen := IFScenario.from_file(SCENARIO)
	var rs := PlaySession.load_ruleset(scen.ruleset_id)
	var state := IFState.new(rs)
	state.init_sheet({"attributes": {}, "resources": {}})
	var iron_door := scen.passage("iron_door")
	for ch in iron_door.get("choices", []):
		if str(ch.get("id")) == "unlock":
			return state.conditions_met(ch.get("conditions", null))
	return false


## A mid-adventure save must resume to the identical continuation (same ending +
## gold) as an uninterrupted run — proving IFSaveGame short-term round-trips.
func _prove_save_load(seed: int) -> bool:
	# Path A — uninterrupted.
	PlaySession.begin_oneoff_scenario(SCENARIO, seed)
	PlaySession.choose("descend")
	PlaySession.choose("search_sarcophagus")   # at sarcophagus (iron_key in hand)
	if not PlaySession.save_game():
		return false
	PlaySession.choose("pry_open")
	PlaySession.choose("unlock")
	var end_a := str(PlaySession.ending().get("id", ""))
	var gold_a := PlaySession.active_state().get_var("gold")

	# Path B — load the mid save, continue identically.
	if not PlaySession.load_game():
		return false
	var resumed_at := str(PlaySession.current_passage().get("id", ""))
	PlaySession.choose("pry_open")
	PlaySession.choose("unlock")
	var end_b := str(PlaySession.ending().get("id", ""))
	var gold_b := PlaySession.active_state().get_var("gold")
	PlaySession.clear_save()
	return resumed_at == "sarcophagus" and end_a == end_b and gold_a == gold_b and end_a != ""


func _prove_campaign() -> bool:
	if not PlaySession.begin_campaign_file(CAMPAIGN):
		return false
	PlaySession.choose("descend")
	PlaySession.choose("press_on")   # auto-resolves the module-1 SKILL check
	PlaySession.choose("take_relic") # module 1 ends -> between modules
	if not PlaySession.is_between_modules():
		return false
	if not PlaySession.advance_campaign_module():
		return false
	PlaySession.choose("enter_market")
	PlaySession.choose("seal_bargain")  # module 2 ends -> campaign complete
	_campaign_status = PlaySession.outcome()
	return PlaySession.is_ended() and PlaySession.outcome() == "complete"


func _prove_play_scene(seed: int) -> bool:
	PlaySession.begin_oneoff_scenario(SCENARIO, seed)
	var packed := load("res://scenes/play.tscn") as PackedScene
	if packed == null:
		return false
	var scene := packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var title_label := scene.find_child("TitleLabel", true, false)
	var choices := scene.find_child("Choices", true, false)
	var ok: bool = title_label != null and not str(title_label.text).is_empty() \
		and choices != null and choices.get_child_count() >= 1
	scene.queue_free()
	return ok


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		_checks.append("%s=FAIL(%s)" % [label, detail])
	else:
		_checks.append("%s=ok" % label)
