extends Node
## res://_probes/flow_probe.gd
## Phase-2 headless boot + flow probe, driven through the `Adventure` autoload with a
## fixed seed. Proves, with NO rendering:
##   * both shipped scenarios VALIDATE clean (the Grey Tithe slice + the wardens
##     scaffold): no dangling gotos, unreachable, dead-ends, or unwinnable states;
##   * the authoring VALIDATOR still catches every defect class in the broken sample;
##   * a LIVE golden path through the Grey Tithe reaches the true QUITTANCE victory
##     (winnability proven end-to-end via the engine) and a death terminal fires;
##   * every Phase-2 screen SCRIPT parses and its scene boots (reading view + combat
##     view instantiated headlessly without error).
## Run: godot --headless --path <skeleton> res://_probes/flow_probe.tscn

const GREY := "res://data/adventures/grey-tithe/adventure.json"
const SCAFFOLD := "res://data/adventures/wardens-hollow.scaffold.json"
const BROKEN := "res://data/adventures/_broken-sample.json"
const READING_VIEW := preload("res://scenes/reading_view.tscn")
const COMBAT_VIEW := preload("res://scripts/screens/combat_view.tscn")
const ADVENTURE_SHEET := preload("res://scripts/screens/adventure_sheet.gd")

# The pure-choice golden path to QUITTANCE (no dice events) — mirrors CONTENT_SAMPLE
# + the condensed finale; every step is a legal, condition-met choice.
const GOLDEN := [
	"shrine", "to_bridge", "pay_gold", "cross", "call_grissel",
	"to_ferrant", "buy_provisions", "leave",
	"to_grissel", "offer_provision", "back", "confess", "back",
	"to_odo", "ask_gently", "back",
	"descend", "go_on", "free_her", "release",
]


func _ready() -> void:
	await get_tree().process_frame
	var fails := 0
	var notes: Array[String] = []

	# --- 1) both scenarios validate clean --------------------------------------
	var grey := IFAdventureValidator.validate(IFScenario.from_file(GREY), Adventure.ruleset)
	var grey_ok := bool(grey.ok) and (grey.errors as Array).is_empty()
	if not grey_ok: fails += 1
	notes.append("validate_grey[ok=%s errors=%d warns=%d victory=%s]" % [
		grey.ok, (grey.errors as Array).size(), (grey.warnings as Array).size(), grey.victory_reachable])
	if not grey_ok:
		notes.append("  grey_errors=%s" % " | ".join(grey.errors))

	var scaf := IFAdventureValidator.validate(IFScenario.from_file(SCAFFOLD), Adventure.ruleset)
	var scaf_ok := bool(scaf.ok) and (scaf.errors as Array).is_empty()
	if not scaf_ok: fails += 1
	notes.append("validate_scaffold[ok=%s errors=%d]" % [scaf.ok, (scaf.errors as Array).size()])

	# --- 2) broken sample: every defect class flagged --------------------------
	var bad := IFAdventureValidator.validate(IFScenario.from_file(BROKEN), Adventure.ruleset)
	var errs := " ".join(bad.errors)
	var warns := " ".join(bad.warnings)
	var broken_ok := not bool(bad.ok) \
		and errs.contains("missing 'ghost_town'") and errs.contains("unreachable section 'orphan'") \
		and errs.contains("dead-end section 'deadend'") and errs.contains("unwinnable") \
		and warns.contains("silver_key")
	if not broken_ok: fails += 1
	notes.append("validate_broken[caught_all=%s]" % broken_ok)

	# --- 3) live golden path to the QUITTANCE victory --------------------------
	Adventure.new_adventure(20260719)
	var at_start := Adventure.runner.state.current_passage == "s1"
	if not at_start: fails += 1
	var walked := 0
	for cid in GOLDEN:
		if not _has(cid):
			notes.append("  golden BROKE at step '%s' (passage %s)" % [cid, Adventure.runner.state.current_passage])
			break
		Adventure.choose(cid)
		walked += 1
	var win_ok := Adventure.is_ended() and str(Adventure.ending().get("kind", "")) == "victory" \
		and str(Adventure.ending().get("id", "")) == "quittance"
	if not win_ok: fails += 1
	notes.append("golden[start=%s steps=%d/%d ended=%s ending=%s ok=%s]" % [
		at_start, walked, GOLDEN.size(), Adventure.is_ended(), Adventure.ending().get("id", ""), win_ok])

	# --- 4) a death terminal fires --------------------------------------------
	Adventure.new_adventure(20260719)
	Adventure.choose("reeds")               # s1 -> s12 (instant-death terminal)
	var death_ok := Adventure.is_ended() and str(Adventure.ending().get("kind", "")) == "death"
	if not death_ok: fails += 1
	notes.append("death[ended=%s kind=%s ok=%s]" % [Adventure.is_ended(), Adventure.ending().get("kind", ""), death_ok])

	# --- 5) Phase-2 screens boot (parse + _ready run) --------------------------
	Adventure.new_adventure(20260719)
	Adventure.choose("causeway")            # sit on s2 for the reading view
	var rv := READING_VIEW.instantiate()
	add_child(rv)
	await get_tree().process_frame
	var rv_ok := is_instance_valid(rv) and rv.get_child_count() > 0
	if not rv_ok: fails += 1
	notes.append("reading_view_boot[ok=%s]" % rv_ok)
	rv.queue_free()

	Adventure.jump_to("s7")
	var cv := COMBAT_VIEW.instantiate()
	cv.setup(FFEncounter.from_passage(Adventure.current_section().raw()), {"win": "_onwin", "death": "_ondeath", "escape": "_onescape"}, "7")
	add_child(cv)
	await get_tree().process_frame
	var cv_ok := is_instance_valid(cv) and cv.get_child_count() > 0
	if not cv_ok: fails += 1
	notes.append("combat_view_boot[ok=%s]" % cv_ok)
	cv.queue_free()

	# --- 6) Adventure Sheet boots + survives a full LAYOUT pass ----------------
	# Reproduces the roll-up -> pick Potion -> Begin -> open-sheet path that crashed
	# in the ruled-surface min-size computation. We instantiate the real sheet over a
	# live run (potion picked, a codeword + note recorded so the ruled panels carry
	# BOTH content and blank lines) and FORCE `get_combined_minimum_size()` on every
	# Control descendant — the exact code path that previously threw. Headless (no
	# rendering) still exercises layout/min-size, which is where the fault lived.
	Adventure.new_adventure(20260719)
	Adventure.runner.state.set_flag("potion", {"type": "skill", "doses": 2})   # a picked potion
	Adventure.runner.state.set_codeword("RESTITUTION")
	Adventure.runner.state.notes.append("the ledger cannot record a debt forgiven")
	Adventure.sheet.apply_delta({"stamina": -5})
	var sheet := ADVENTURE_SHEET.new()
	add_child(sheet)
	await get_tree().process_frame
	await get_tree().process_frame
	var laid := _force_layout(sheet)
	# spent-potion variant (the other _render branch) must lay out too
	Adventure.runner.state.set_flag("potion", {"type": "skill", "doses": 0})
	sheet.call("_render")
	await get_tree().process_frame
	laid += _force_layout(sheet)
	var sheet_ok := is_instance_valid(sheet) and laid > 0
	if not sheet_ok: fails += 1
	notes.append("adventure_sheet_boot[ok=%s controls_laid=%d]" % [sheet_ok, laid])
	sheet.queue_free()

	print("DEBUG: ff-gamebook phase-2 flow — %s  fails=%d" % [" ".join(notes), fails])
	get_tree().quit(0 if fails == 0 else 1)


## Recursively force min-size (layout) computation on every Control — this is the
## path that a native-container `super._get_minimum_size()` misuse crashes on.
func _force_layout(n: Node) -> int:
	var count := 0
	if n is Control:
		(n as Control).get_combined_minimum_size()
		count += 1
	for c in n.get_children():
		count += _force_layout(c)
	return count


func _has(cid: String) -> bool:
	for ch in Adventure.available_choices():
		if str(ch.get("id", "")) == cid:
			return true
	return false
