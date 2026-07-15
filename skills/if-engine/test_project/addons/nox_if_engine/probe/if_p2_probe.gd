extends Node
## res://addons/nox_if_engine/probe/if_p2_probe.gd
## Headless self-test for the P2 layer (rulesets + ruleset validation/import +
## the ruleset-PORTABILITY that proves the generic engine's promise) built ON the
## P0/P1 computed engine. Mirrors the probe convention: drive the API, print ONE
## deterministic DEBUG line, quit non-zero on any failure. NO LLM, NO networking.
##
## It proves, in one seeded process:
##   (a) BUILTINS — all three genericised builtins (ff-2d6, srd-d20, pbta) load
##       AND pass the §2.5 ruleset validator (a runnable IFRuleset, no errors).
##   (b) PORTABILITY — the SAME portable scenario (`portable-trial`, which names
##       one canonical skill-test and carries no ruleset) is played under ff-2d6,
##       srd-d20 AND pbta. Each resolves with its OWN math (roll-under vs
##       meet-or-beat vs threshold-bands, 2d6 vs 1d20) yet routes to a sensible
##       authored ending. A deterministically-found seed yields THREE DISTINCT
##       canonical bands across the three systems from the one scenario+seed —
##       the crux proof that swapping the ruleset reskins all resolution.
##   (c) CUSTOM — a hand-authored user ruleset (`nox-2d10`, a 2d10 homebrew)
##       validates AND runs the same portable scenario to an ending.
##   (d) REJECTION — an intentionally-malformed ruleset is REJECTED by the
##       validator with clear, specific errors (and yields no runnable ruleset).
##
## Determinism: fixed seeds + a fixed seed-scan => the reported seed, the per-
## system bands and the signature are byte-identical across runs.
##
## Run:
##   Godot --headless --path <project> res://addons/nox_if_engine/probe/if_p2_probe.tscn

const RS_FF := "res://addons/nox_if_engine/data/rulesets/ff-2d6.json"
const RS_D20 := "res://addons/nox_if_engine/data/rulesets/srd-d20.json"
const RS_PBTA := "res://addons/nox_if_engine/data/rulesets/pbta.json"
const RS_NOX := "res://addons/nox_if_engine/data/rulesets/nox-2d10.json"
const SCENARIO := "res://addons/nox_if_engine/data/scenarios/portable-trial.json"

## Deterministic scan bound for finding a maximally-divergent seed.
const SEED_SCAN_MAX := 4096

## A portable check names a canonical attribute + difficulty; the scenario routes
## on canonical bands. The three sample sheets fix the mapped attribute so only the
## dice varies with the seed.
const CANON_ATTR := "prowess"
const DIFFICULTY := "hard"

## canonical band -> the ending id the portable scenario routes it to.
const BAND_TO_ENDING := {"success": "triumph", "partial": "scraped", "failure": "repelled"}

var _checks: Array[String] = []
var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# ---------------------------------------------------------------------
	# (a) BUILTINS load + pass the §2.5 validator.
	# ---------------------------------------------------------------------
	var v_ff := IFRulesetValidator.validate_file(RS_FF)
	var v_d20 := IFRulesetValidator.validate_file(RS_D20)
	var v_pbta := IFRulesetValidator.validate_file(RS_PBTA)
	_expect("ff_valid", v_ff.ok and v_ff.ruleset != null and str(v_ff.ruleset.id) == "ff-2d6",
		" ".join(v_ff.errors))
	_expect("d20_valid", v_d20.ok and v_d20.ruleset != null and str(v_d20.ruleset.id) == "srd-d20",
		" ".join(v_d20.errors))
	_expect("pbta_valid", v_pbta.ok and v_pbta.ruleset != null and str(v_pbta.ruleset.id) == "pbta",
		" ".join(v_pbta.errors))

	var ff: IFRuleset = v_ff.ruleset
	var d20: IFRuleset = v_d20.ruleset
	var pbta: IFRuleset = v_pbta.ruleset

	# Each builtin maps the skill-test semantic (portability wired).
	_expect("builtins_map_semantic",
		ff.has_semantic("skill-test") and d20.has_semantic("skill-test") and pbta.has_semantic("skill-test"))

	# The portable scenario loads + validates against EACH system (its one check is
	# expressible under all three).
	var scenario := IFScenario.from_file(SCENARIO)
	_expect("scenario_loaded", scenario.id == "portable-trial")
	_expect("scenario_valid_ff", scenario.validate(ff).is_empty(), " ".join(scenario.validate(ff)))
	_expect("scenario_valid_d20", scenario.validate(d20).is_empty(), " ".join(scenario.validate(d20)))
	_expect("scenario_valid_pbta", scenario.validate(pbta).is_empty(), " ".join(scenario.validate(pbta)))

	# Sample sheets — fix the mapped attribute so the dice roll is the only variable.
	var sheet_ff := {"attributes": {"SKILL": 9, "STAMINA": 20, "LUCK": 9}, "resources": {"STAMINA": 20, "provisions": 4}, "resource_max": {"STAMINA": 20}}
	var sheet_d20 := {"attributes": {"STR": 18, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10}, "resources": {"HP": 14, "AC": 13}}
	var sheet_pbta := {"attributes": {"cool": 0, "hard": 1, "hot": 0, "sharp": 0, "weird": 0}, "resources": {"harm": 0, "hold": 0, "xp": 0}}

	# ---------------------------------------------------------------------
	# (b) PORTABILITY — same scenario, three systems, three kinds of math.
	# ---------------------------------------------------------------------
	# Resolution genuinely DIFFERS per system (compile + resolve, seed 1).
	var r_ff := _resolve_once(ff, 1, sheet_ff)
	var r_d20 := _resolve_once(d20, 1, sheet_d20)
	var r_pbta := _resolve_once(pbta, 1, sheet_pbta)
	var compares := {}
	compares[str(r_ff.result.compare)] = true
	compares[str(r_d20.result.compare)] = true
	compares[str(r_pbta.result.compare)] = true
	_expect("resolution_differs", compares.size() == 3,
		"compares=%s dice=[%s,%s,%s]" % [str(compares.keys()), r_ff.result.dice, r_d20.result.dice, r_pbta.result.dice])
	# The compiled native call differs per system: ff rolls-under an attribute
	# target; d20 has a DC target from the difficulty ladder; pbta has no target.
	_expect("compiled_ff_targetdelta", r_ff.compiled.args.has("_targetDelta") and str(r_ff.compiled.args.get("attr", "")) == "SKILL",
		str(r_ff.compiled.args))
	_expect("compiled_d20_dc", int(r_d20.compiled.args.get("dc", 0)) == 20 and str(r_d20.compiled.args.get("ability", "")) == "STR",
		str(r_d20.compiled.args))
	_expect("compiled_pbta_rollmod", r_pbta.compiled.args.has("_rollModifier") and str(r_pbta.compiled.args.get("stat", "")) == "hard",
		str(r_pbta.compiled.args))

	# The crux: deterministically find a seed where the SAME scenario yields THREE
	# DISTINCT canonical bands across ff / srd / pbta (a binary system can't emit a
	# partial, so this triple is {success, failure, partial} in some assignment).
	var div := _find_divergent_seed(ff, d20, pbta, sheet_ff, sheet_d20, sheet_pbta)
	_expect("divergent_seed_found", div.seed >= 0,
		"scanned=%d" % SEED_SCAN_MAX)
	_expect("three_distinct_bands", div.bands.size() == 3,
		"ff=%s d20=%s pbta=%s" % [div.ff, div.d20, div.pbta])

	# End-to-end: at that seed, each system PLAYS the portable scenario and routes
	# to the ending its own resolution demands (band -> ending id cross-check).
	var end_ff := _play_ending(ff, scenario, div.seed, sheet_ff)
	var end_d20 := _play_ending(d20, scenario, div.seed, sheet_d20)
	var end_pbta := _play_ending(pbta, scenario, div.seed, sheet_pbta)
	_expect("route_ff", end_ff == BAND_TO_ENDING[div.ff], "band=%s ending=%s" % [div.ff, end_ff])
	_expect("route_d20", end_d20 == BAND_TO_ENDING[div.d20], "band=%s ending=%s" % [div.d20, end_d20])
	_expect("route_pbta", end_pbta == BAND_TO_ENDING[div.pbta], "band=%s ending=%s" % [div.pbta, end_pbta])
	# And the three endings are not all identical — one scenario, one seed, diverged.
	var endings := {}
	endings[end_ff] = true
	endings[end_d20] = true
	endings[end_pbta] = true
	_expect("endings_diverge", endings.size() == 3, str(endings.keys()))

	# ---------------------------------------------------------------------
	# (c) CUSTOM user ruleset validates + runs the SAME portable scenario.
	# ---------------------------------------------------------------------
	var v_nox := IFRulesetValidator.validate_file(RS_NOX)
	_expect("custom_valid", v_nox.ok and v_nox.ruleset != null and str(v_nox.ruleset.id) == "nox-2d10",
		" ".join(v_nox.errors))
	var nox: IFRuleset = v_nox.ruleset
	_expect("custom_scenario_valid", scenario.validate(nox).is_empty(), " ".join(scenario.validate(nox)))
	var sheet_nox := {"attributes": {"grit": 3, "guile": 2, "glory": 2, "guts": 2}, "resources": {"vigor": 10, "momentum": 0}, "resource_max": {"vigor": 10}}
	var end_nox := _play_ending(nox, scenario, div.seed, sheet_nox)
	_expect("custom_runs", end_nox in BAND_TO_ENDING.values(), "ending=%s" % end_nox)

	# ---------------------------------------------------------------------
	# (d) REJECTION — a malformed ruleset is rejected with clear errors.
	# ---------------------------------------------------------------------
	var bad := _malformed_ruleset()
	var v_bad := IFRulesetValidator.validate(bad)
	_expect("malformed_rejected", not v_bad.ok and v_bad.ruleset == null and v_bad.errors.size() >= 6,
		"errors=%d" % v_bad.errors.size())
	_expect("malformed_error_id", _any_contains(v_bad.errors, "id"))
	_expect("malformed_error_dice", _any_contains(v_bad.errors, "dice.default"))
	_expect("malformed_error_compare", _any_contains(v_bad.errors, "compare"))
	_expect("malformed_error_dup", _any_contains(v_bad.errors, "duplicated"))
	_expect("malformed_error_bounds", _any_contains(v_bad.errors, "min"))
	_expect("malformed_error_ref", _any_contains(v_bad.errors, "not a declared attribute"))
	# A well-formed ruleset yields NO errors — the validator is not vacuously strict.
	_expect("validator_not_vacuous", IFRulesetValidator.validate(ff.raw()).ok)

	# ---------------------------------------------------------------------
	# Determinism signature — stable across runs.
	# ---------------------------------------------------------------------
	var sig := _signature(div, end_ff, end_d20, end_pbta, end_nox)

	var all_ok := _fails == 0
	print("DEBUG: if-engine-p2 — builtins=3 custom=nox-2d10 scenario=portable-trial div_seed=%d bands=[ff:%s,d20:%s,pbta:%s] endings=[ff:%s,d20:%s,pbta:%s,nox:%s] malformed_errors=%d sig=%s fails=%d %s => %s" % [
		div.seed, div.ff, div.d20, div.pbta,
		end_ff, end_d20, end_pbta, end_nox,
		v_bad.errors.size(), sig.substr(0, 16),
		_fails, " ".join(_checks),
		"OK" if all_ok else "FAIL",
	])
	get_tree().quit(0 if all_ok else 1)


# --- portability helpers ----------------------------------------------------


## Compile + resolve the portable skill-test once under `rs` at `seed` with a
## fixed sheet. Returns { compiled, result, canon } where `canon` is the canonical
## band. Because the portable scenario's FIRST dice roll IS this check (the gate
## passage rolls nothing and the sheet is injected, not generated), this predicts
## exactly what the full runner does at the same seed.
func _resolve_once(rs: IFRuleset, seed: int, sheet: Dictionary) -> Dictionary:
	var dice := IFDice.new()
	dice.set_seed(seed)
	var resolver := IFResolver.new(rs, dice)
	var state := IFState.new(rs)
	state.init_sheet(sheet)
	var check := {"semantic": "skill-test", "attribute": CANON_ATTR, "difficulty": DIFFICULTY}
	var compiled := IFPortableCheck.compile(check, rs)
	var result := resolver.resolve(rs.rule(str(compiled.rule)), state, compiled.args)
	var canon := IFPortableCheck.canonical_band(str(result.band), rs)
	return {"compiled": compiled, "result": result, "canon": canon}


## Play the portable scenario under `rs` at `seed` with `sheet`; return the reached
## ending id.
func _play_ending(rs: IFRuleset, scenario: IFScenario, seed: int, sheet: Dictionary) -> String:
	var r := IFRunner.new()
	r.load(rs, scenario, seed, sheet)
	r.start()
	if r.is_choice_available("attempt"):
		r.choose("attempt")
	return str(r.ending().get("id", ""))


## Deterministically find the first seed at which ff / srd / pbta produce three
## DISTINCT canonical bands from the one portable check. Same scan every run.
func _find_divergent_seed(ff: IFRuleset, d20: IFRuleset, pbta: IFRuleset, s_ff: Dictionary, s_d20: Dictionary, s_pbta: Dictionary) -> Dictionary:
	for seed in range(1, SEED_SCAN_MAX + 1):
		var b_ff := str(_resolve_once(ff, seed, s_ff).canon)
		var b_d20 := str(_resolve_once(d20, seed, s_d20).canon)
		var b_pbta := str(_resolve_once(pbta, seed, s_pbta).canon)
		var set := {}
		set[b_ff] = true
		set[b_d20] = true
		set[b_pbta] = true
		if set.size() == 3:
			return {"seed": seed, "ff": b_ff, "d20": b_d20, "pbta": b_pbta, "bands": set}
	return {"seed": -1, "ff": "", "d20": "", "pbta": "", "bands": {}}


# --- malformed fixture ------------------------------------------------------


## A ruleset with (at least) seven distinct schema violations, built inline so the
## proof is self-contained: no id, no dice.default, an attribute min>max, a
## duplicate attribute key, a bad gen expression, a resource `from` a non-attribute,
## an unknown compare mode, an operand missing its ref, and a bad band `when`.
func _malformed_ruleset() -> Dictionary:
	return {
		"id": "",
		"attributes": [
			{"key": "AAA", "min": 10, "max": 2},
			{"key": "AAA"},
			{"key": "BBB", "gen": "2dz"},
		],
		"resources": [
			{"key": "pool", "from": "NOPE"},
		],
		"resolutionRules": [
			{
				"id": "r1",
				"compare": "nonsense-mode",
				"operands": [{"type": "attributeArg", "role": "modifier"}],
				"bands": [{"id": "x", "when": "weird-band"}],
			},
		],
	}


# --- plumbing ---------------------------------------------------------------


func _signature(div: Dictionary, e_ff: String, e_d20: String, e_pbta: String, e_nox: String) -> String:
	var canonical := "seed=%d|ff=%s->%s|d20=%s->%s|pbta=%s->%s|nox->%s" % [
		div.seed, div.ff, e_ff, div.d20, e_d20, div.pbta, e_pbta, e_nox]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _any_contains(errors: Array, needle: String) -> bool:
	for e in errors:
		if str(e).contains(needle):
			return true
	return false


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		_checks.append("%s=FAIL(%s)" % [label, detail])
	else:
		_checks.append("%s=ok" % label)
