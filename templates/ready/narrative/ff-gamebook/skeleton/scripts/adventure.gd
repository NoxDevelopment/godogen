extends Node
## res://scripts/adventure.gd
## Autoload "Adventure" — the FF game controller. After the Phase-1 UNIFICATION it
## binds the two layers around ONE shared runtime store:
##
##   * nox_if_engine (the BACKBONE): IFRuleset (ff-2d6) + IFScenario (the book's
##     narrative graph) + IFRunner drive passage flow, choices, conditions, gold,
##     items, flags/codewords and routing. The runner owns the single authoritative
##     `IFState`. The graph IS the world (GDD §2/§3).
##   * the FF rules core (the FF-FLAVOURED VIEW + bespoke combat): FFAdventureSheet
##     is a VIEW over the runner's SAME `IFState` (so a section's `gold +25` or item
##     pickup reaches the sheet + HUD with no glue), and FF checks (test / test-luck
##     / test-skill / test-stamina) are MIGRATED onto the ruleset's resolutionRules
##     via IFResolver. Combat (2d6+SKILL opposed rounds) stays the one bespoke layer.
##
## Two deterministic dice streams (both seeded from the run seed) keep replay/MP
## sync honest: the runner's own narrative-graph stream, and this controller's
## combat/luck stream (`dice`) that the migrated FF checks + combat resolve on. The
## serializable unit of save + net sync is FFGameState (GDD §5).

signal adventure_started
signal passage_changed(passage_id: String)
signal sheet_changed
signal hero_died

const RULESET_PATH := "res://addons/nox_if_engine/data/rulesets/ff-2d6.json"
## Phase 2: the shipped vertical slice is *The Grey Tithe* (CONTENT_SAMPLE §§1-12 +
## a condensed Act III finale so the full roll-up -> play -> death/victory loop is
## winnable). The Phase-0 wardens-hollow scaffold remains in data/adventures/ for
## the rules probes.
const SCENARIO_PATH := "res://data/adventures/grey-tithe.json"

const _STAT_ATTR := {"skill": "SKILL", "stamina": "STAMINA", "luck": "LUCK"}

var ruleset: IFRuleset
var scenario: IFScenario
var runner: IFRunner
var sheet: FFAdventureSheet
## The combat/luck dice + the resolver the MIGRATED FF checks run on. Seeded per run
## (a stream distinct from the runner's graph dice) so a fixed `seed` replays
## byte-for-byte.
var dice: IFDice
var resolver: IFResolver
var seed: int = 0
## Monotonic turn counter (GDD §5 GameState.turn) — one per choice taken.
var turn: int = 0


func _enter_tree() -> void:
	add_to_group(&"player")
	add_to_group(&"persistent")


func _ready() -> void:
	ruleset = IFRuleset.from_file(RULESET_PATH)
	scenario = IFScenario.from_file(SCENARIO_PATH)


func _ensure_content() -> void:
	if ruleset == null or ruleset.id == "":
		ruleset = IFRuleset.from_file(RULESET_PATH)
	if scenario == null or scenario.start == "":
		scenario = IFScenario.from_file(SCENARIO_PATH)


## Start a fresh run. `run_seed` of 0 picks a random seed (still recorded, so the
## run is reproducible after the fact); a non-zero seed replays deterministically.
func new_adventure(run_seed: int = 0) -> void:
	_ensure_content()
	seed = run_seed if run_seed != 0 else int(Time.get_unix_time_from_system()) ^ (randi() | 1)
	turn = 0

	# The narrative-graph backbone rolls up the ONE authoritative IFState (SKILL
	# 1d6+6, etc.) from the ruleset's gen expressions inside load().
	runner = IFRunner.new()
	runner.load(ruleset, scenario, seed)

	# The FF sheet is a VIEW over that SAME state — it sets the never-exceed-Initial
	# caps to the rolled values and grants the GDD §3 starting kit INTO the state.
	sheet = FFAdventureSheet.new()
	sheet.bind(runner.state, ruleset)

	# The combat/luck stream + the resolver the migrated FF checks run on. A derived
	# seed so this stream doesn't mirror the graph/roll-up stream.
	dice = IFDice.new()
	dice.set_seed(seed ^ 0x9E3779B9)
	resolver = IFResolver.new(ruleset, dice)

	runner.start()   # onEnter effects now mutate the SAME state the sheet views

	adventure_started.emit()
	sheet_changed.emit()
	passage_changed.emit(runner.state.current_passage)


func has_run() -> bool:
	return runner != null and sheet != null


func current_passage() -> Dictionary:
	if runner == null:
		return {}
	return runner.current_passage()


## The current section as a typed §5 view (title/text/illustration/events/…).
func current_section() -> IFSection:
	return IFSection.of(current_passage())


func available_choices() -> Array:
	if runner == null:
		return []
	return runner.available_choices()


func is_ended() -> bool:
	return runner != null and runner.is_ended()


func ending() -> Dictionary:
	return runner.ending() if runner != null else {}


## Take a graph choice (applies its effects + routes through the if-engine). Effects
## like `gold +25` / item grants land in the shared IFState → the sheet + HUD.
func choose(choice_id: String) -> void:
	if runner == null:
		return
	runner.choose(choice_id)
	turn += 1
	passage_changed.emit(runner.state.current_passage)
	_emit_sheet_and_death()


# --- MIGRATED FF checks (ruleset resolutionRules via IFResolver) -------------


## Test your Luck (GDD §3): resolves the ff-2d6 `test-luck` rule — roll-under vs
## current LUCK, double-1 always Lucky / double-6 always Unlucky — whose postEffect
## spends one LUCK on EVERY test (pass or fail). Returns a UI/log-friendly dict with
## the same shape the reading view + combat expect.
func test_luck() -> Dictionary:
	var rule := ruleset.rule("test-luck")
	var before := sheet.cur("luck")
	var res := resolver.resolve(rule, runner.state)
	var after := sheet.cur("luck")
	var r := {
		"kind": "test-luck",
		"faces": res.faces, "total": int(res.total),
		"target": before,
		"lucky": str(res.band) == "success",
		"crit_lucky": str(res.crit) == "success",
		"crit_unlucky": str(res.crit) == "fail",
		"luck_before": before, "luck_after": after,
	}
	_emit_sheet_and_death()
	return r


## Test a non-consuming attribute — Skill / Stamina (GDD §3) — via the generic
## ff-2d6 `test` rule (2d6 <= current; the stat is NOT spent). `stat` is "skill" /
## "stamina" / "luck" or a native attribute key.
func test_attribute(stat: String) -> Dictionary:
	var attr: String = _STAT_ATTR.get(stat, stat)
	var rule := ruleset.rule("test")
	var target := sheet.cur(stat)
	var res := resolver.resolve(rule, runner.state, {"attr": attr})
	var r := {
		"kind": "test-" + stat,
		"faces": res.faces, "total": int(res.total),
		"target": target,
		"success": str(res.band) == "success",
		"crit_success": str(res.crit) == "success",
		"crit_fail": str(res.crit) == "fail",
	}
	_emit_sheet_and_death()
	return r


## Notify listeners the sheet mutated (combat/provisions call this after routing
## through apply_delta). Fires hero_died once when STAMINA hits 0.
func notify_sheet_changed(report: Dictionary = {}) -> void:
	sheet_changed.emit()
	if bool(report.get("died", false)) or (sheet != null and sheet.is_dead()):
		hero_died.emit()


func _emit_sheet_and_death() -> void:
	sheet_changed.emit()
	if sheet != null and sheet.is_dead():
		hero_died.emit()


# --- authoring / debug seams (GDD §10) --------------------------------------


## Jump-to-any-section debug play mode. Teleports into `section_id` (applying its
## onEnter/check/ending), preserving the sheet. Returns false for an unknown id.
func jump_to(section_id: String) -> bool:
	if runner == null:
		return false
	var ok := runner.jump_to(section_id)
	if ok:
		passage_changed.emit(runner.state.current_passage)
		_emit_sheet_and_death()
	return ok


## Hot-reload preview: re-read the scenario JSON from disk and swap it in, keeping
## live state. Re-renders in place if the current section survived; otherwise jumps
## to the new start. Returns true on a successful reload.
func reload_scenario() -> bool:
	if runner == null:
		return false
	var fresh := IFScenario.from_file(SCENARIO_PATH)
	if fresh.start == "":
		return false
	scenario = fresh
	var kept := runner.reload_scenario(fresh)
	if not kept:
		runner.jump_to(fresh.start)
	passage_changed.emit(runner.state.current_passage)
	_emit_sheet_and_death()
	return true


## Validate the loaded (or a given) adventure with the authoring validator.
func validate_adventure(scenario_in: IFScenario = null) -> Dictionary:
	_ensure_content()
	var target := scenario_in if scenario_in != null else scenario
	return IFAdventureValidator.validate(target, ruleset)


# --- "persistent" save ABI (via the §5 GameState) ---------------------------


func save_data() -> Dictionary:
	if not has_run():
		return {}
	var gs := FFGameState.capture(
		runner.state.current_passage,
		{"p1": sheet.save_data()},
		runner.state.codewords,
		seed,
		runner.dice.get_state(),
		dice.get_state(),
		turn)
	return gs.to_dict()


func load_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	_ensure_content()
	var gs := FFGameState.from_dict(data)
	seed = gs.rng_seed
	turn = gs.turn

	# Rebuild the runner around the restored IFState (the unified sheet payload).
	runner = IFRunner.new()
	runner.restore(ruleset, scenario, {
		"seed": seed,
		"dice_state": gs.graph_dice_state,
		"state": gs.primary_sheet("p1"),
	})

	# The FF sheet re-views the restored state (caps + kit already in the payload).
	sheet = FFAdventureSheet.new()
	sheet.bind(runner.state, ruleset)

	dice = IFDice.new()
	dice.set_seed(seed ^ 0x9E3779B9)
	dice.set_state(gs.combat_dice_state)
	resolver = IFResolver.new(ruleset, dice)

	adventure_started.emit()
	sheet_changed.emit()
	passage_changed.emit(runner.state.current_passage)
