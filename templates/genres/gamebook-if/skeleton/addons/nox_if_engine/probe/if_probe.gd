extends Node
## res://addons/nox_if_engine/probe/if_probe.gd
## Headless self-test for the nox_if_engine computed core (mirrors the ff-gamebook
## and nox_netcode probe convention: drive the API, print ONE deterministic
## DEBUG line, quit non-zero on any failure).
##
## It plays the sample scenario end-to-end under the `ff-2d6` ruleset — fully
## seeded, no LLM, no networking — and proves, in one process:
##   * passage traversal (the history trail is exactly the authored path)
##   * a resolved check (dice vs attribute -> outcome band) that BRANCHES the
##     story both ways (a victory seed and a defeat seed, deterministically found)
##   * effects applied (a variable add, an item grant, an attribute change,
##     the FF LUCK-attrition rule postEffect)
##   * an item gate (a choice offered only because item.iron_key >= 1, and proven
##     closed on a keyless state)
##   * an ending reached (kind == victory / retreat)
##   * the generic resolver expressing the OTHER two families as data
##     (srd-d20 meet-or-beat + ability modifier; pbta threshold bands)
##
## Run:
##   Godot --headless --path <project> res://addons/nox_if_engine/probe/if_probe.tscn

const RULESET_FF := "res://addons/nox_if_engine/data/rulesets/ff-2d6.json"
const RULESET_D20 := "res://addons/nox_if_engine/data/rulesets/srd-d20.json"
const RULESET_PBTA := "res://addons/nox_if_engine/data/rulesets/pbta.json"
const SCENARIO := "res://addons/nox_if_engine/data/scenarios/thornwood-crypt.json"

## Deterministic scan bound — the skill test fails ~1 in 6, so both a victory and
## a defeat seed are found within the first handful; 512 is a generous ceiling.
const SEED_SCAN_MAX := 512

const GOLDEN_CHOICES := ["descend", "search_sarcophagus", "pry_open", "unlock"]
const EXPECTED_TRAIL := [
	"crypt_gate", "antechamber", "sarcophagus", "dart_trap",
	"iron_door", "guardian", "treasure",
]

var _checks: Array[String] = []
var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ruleset := IFRuleset.from_file(RULESET_FF)
	var scenario := IFScenario.from_file(SCENARIO)

	# 0) Data loads + validates cleanly.
	_expect("loaded", ruleset.id == "ff-2d6" and scenario.id == "thornwood-crypt")
	var problems := scenario.validate(ruleset)
	_expect("valid", problems.is_empty(), " ".join(problems))

	# 1) Deterministic seed search: first seed that wins, first that loses. Same
	#    scan every run => the reported seeds are stable + reproducible.
	var win_seed := _find_seed("victory")
	var lose_seed := _find_seed("retreat")
	_expect("seeds_found", win_seed >= 0 and lose_seed >= 0,
		"win=%d lose=%d" % [win_seed, lose_seed])

	# 2) Victory play — the golden path, step by step, with the mid-play gate check.
	var vic := _play_with_gate_check(ruleset, scenario, win_seed)
	var r: IFRunner = vic.runner

	_expect("traversal", r.state.passage_history == EXPECTED_TRAIL,
		str(r.state.passage_history))

	# The item gate: at iron_door WITH the key, unlock is offered; the keyless
	# scratch state proves the same condition is what gates it.
	_expect("gate_open", vic.unlock_offered)
	_expect("gate_closed_without_key", not _gate_would_open(ruleset, scenario))

	# A resolved check that branched to the ending (guardian SKILL test succeeded).
	var guardian := _find_trace(r, "guardian", "check")
	_expect("check_resolved", not guardian.is_empty()
		and str(guardian.get("band")) == "success"
		and guardian.get("success") == true,
		"band=%s faces=%s total=%s target=%s" % [
			guardian.get("band"), guardian.get("faces"),
			guardian.get("total"), guardian.get("target")])

	# Effects applied: gold 0 -> +5 (antechamber) -> +10 (guardian win) == 15;
	# torch granted; iron key consumed by the unlock choice.
	_expect("effect_var", r.state.get_var("gold") == 15.0,
		"gold=%s" % r.state.get_var("gold"))
	_expect("effect_item_grant", r.state.has_item("torch"))
	_expect("effect_item_consume", r.state.get_item("iron_key") == 0)

	# The LUCK-attrition rule postEffect fired once (dart_trap test-luck): 11 -> 10.
	_expect("rule_posteffect", r.state.get_attr("LUCK") == 10.0,
		"luck=%s" % r.state.get_attr("LUCK"))

	# Ending reached.
	_expect("ending_victory", r.is_ended() and str(r.ending().get("kind")) == "victory",
		str(r.ending()))

	# 3) Defeat play — SAME choices, a seed where the SKILL test fails -> retreat.
	var lose := _play(ruleset, scenario, lose_seed)
	var lose_guardian := _find_trace(lose, "guardian", "check")
	_expect("branch_failure", lose.is_ended()
		and str(lose.ending().get("kind")) == "retreat"
		and str(lose_guardian.get("band")) == "failure",
		"ending=%s band=%s" % [lose.ending().get("kind"), lose_guardian.get("band")])

	# 4) Generic resolver expresses the OTHER two families as pure data.
	_expect("family_d20", _prove_d20())
	_expect("family_pbta", _prove_pbta())

	# --- One DEBUG line, netcode-style ---------------------------------------
	var all_ok := _fails == 0
	print("DEBUG: if-engine probe — ruleset=%s scenario=%s win_seed=%d lose_seed=%d rolls=%d fails=%d %s => %s" % [
		ruleset.id, scenario.id, win_seed, lose_seed,
		r.state.roll_log.size(), _fails,
		" ".join(_checks),
		"OK" if all_ok else "FAIL",
	])
	get_tree().quit(0 if all_ok else 1)


# --- play helpers -----------------------------------------------------------


## Play the golden choice sequence under a seed. Auto-resolution passages
## (dart_trap, guardian) resolve themselves on entry; we only issue the
## interactive choices.
func _play(ruleset: IFRuleset, scenario: IFScenario, seed: int) -> IFRunner:
	var r := IFRunner.new()
	r.load(ruleset, scenario, seed)
	r.start()
	for choice_id in GOLDEN_CHOICES:
		if r.is_ended():
			break
		if r.is_choice_available(choice_id):
			r.choose(choice_id)
	return r


## Same as _play but pauses at iron_door to record whether `unlock` is offered.
func _play_with_gate_check(ruleset: IFRuleset, scenario: IFScenario, seed: int) -> Dictionary:
	var r := IFRunner.new()
	r.load(ruleset, scenario, seed)
	r.start()
	var unlock_offered := false
	for choice_id in GOLDEN_CHOICES:
		if r.is_ended():
			break
		if r.state.current_passage == "iron_door":
			unlock_offered = r.is_choice_available("unlock")
		if r.is_choice_available(choice_id):
			r.choose(choice_id)
	return {"runner": r, "unlock_offered": unlock_offered}


## Deterministically find the first seed (1..MAX) whose golden play ends in the
## given ending kind.
func _find_seed(kind: String) -> int:
	var ruleset := IFRuleset.from_file(RULESET_FF)
	var scenario := IFScenario.from_file(SCENARIO)
	for seed in range(1, SEED_SCAN_MAX + 1):
		var r := _play(ruleset, scenario, seed)
		if r.is_ended() and str(r.ending().get("kind")) == kind:
			return seed
	return -1


## Would iron_door's `unlock` choice be offered to a fresh, keyless character?
## Evaluates the authored condition directly — the gate's ground truth.
func _gate_would_open(ruleset: IFRuleset, scenario: IFScenario) -> bool:
	var state := IFState.new(ruleset)
	state.init_sheet({"attributes": {}, "resources": {}})
	var iron_door := scenario.passage("iron_door")
	for ch in iron_door.get("choices", []):
		if str(ch.get("id")) == "unlock":
			return state.conditions_met(ch.get("conditions", null))
	return false


func _find_trace(r: IFRunner, passage: String, type: String) -> Dictionary:
	for entry in r.trace:
		if str(entry.get("type")) == type and str(entry.get("passage")) == passage:
			return entry
	return {}


# --- generic-resolver family proofs -----------------------------------------


## srd-d20: 1d20 + abilityMod(STR 16 -> +3) vs DC 14 (meet-or-beat, natural crits).
## Proves the resolver handles a modifier operand + a param target + meet-or-beat.
func _prove_d20() -> bool:
	var rs := IFRuleset.from_file(RULESET_D20)
	var dice := IFDice.new()
	dice.set_seed(7)
	var resolver := IFResolver.new(rs, dice)
	var state := IFState.new(rs)
	state.init_sheet({"attributes": {"STR": 16, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10}, "resources": {"HP": 10}})
	var res := resolver.resolve(rs.rule("ability-check"), state, {"ability": "STR", "dc": 14})
	# +3 modifier from STR 16; band consistent with meet-or-beat vs DC 14
	# (unless a natural crit overrode it).
	var mod_ok: bool = res.modifier == 3.0
	var faces_total: int = int(res.faces[0]) + 3
	var band_ok: bool
	if res.crit == "success":
		band_ok = str(res.band) == "critSuccess"
	elif res.crit == "fail":
		band_ok = str(res.band) == "critFailure"
	elif faces_total >= 14:
		band_ok = str(res.band) == "success"
	else:
		band_ok = str(res.band) == "failure"
	_checks.append("d20(total=%d,band=%s)" % [int(res.total), res.band])
	return mod_ok and band_ok and res.compare == "meet-or-beat"


## pbta: 2d6 + stat(cool +1) -> miss/partial/full threshold bands. Proves the
## resolver handles a band table with no per-check target.
func _prove_pbta() -> bool:
	var rs := IFRuleset.from_file(RULESET_PBTA)
	var dice := IFDice.new()
	dice.set_seed(3)
	var resolver := IFResolver.new(rs, dice)
	var state := IFState.new(rs)
	state.init_sheet({"attributes": {"cool": 1, "hard": 0, "hot": 0, "sharp": 0, "weird": 0}, "resources": {"harm": 0}})
	var res := resolver.resolve(rs.rule("move"), state, {"stat": "cool"})
	var t := int(res.total)
	var expected: String
	if t <= 6:
		expected = "miss"
	elif t <= 9:
		expected = "partial"
	else:
		expected = "full"
	_checks.append("pbta(total=%d,band=%s)" % [t, res.band])
	return str(res.band) == expected and res.compare == "threshold-bands" and res.success == null


# --- assertion plumbing -----------------------------------------------------


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		_checks.append("%s=FAIL(%s)" % [label, detail])
	else:
		_checks.append("%s=ok" % label)
