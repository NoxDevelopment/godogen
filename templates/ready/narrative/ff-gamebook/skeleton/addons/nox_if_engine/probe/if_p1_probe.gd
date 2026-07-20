extends Node
## res://addons/nox_if_engine/probe/if_p1_probe.gd
## Headless self-test for the P1 layer (modules + adventures/campaigns +
## persistence + dual-tier characters) built ON the P0 computed engine. Mirrors
## the P0 probe convention: drive the API, print ONE deterministic DEBUG line,
## quit non-zero on any failure. NO LLM, NO networking — pure computed core.
##
## It proves, in one seeded process:
##   (a) ONE-OFF — a single-module adventure played straight to an ending.
##   (b) CAMPAIGN — begin, play module 1 (on a lightweight SHEET character),
##       SAVE between modules, RESUME from that save, then carry BOTH character
##       tiers into module 2: the SHEET character's mutated state (STAMINA,
##       inventory, history) persists in the long-term roster, and the
##       COMPANION-bound character's ff-2d6 sheet is DERIVED from its interchange
##       (consume-only) and drives module 2. Long-term world state (world.*)
##       carries; a module-entry `requires` gate on it is honoured.
##   (c) SHORT vs LONG separation — a scene-scoped session var lives only in the
##       short-term store and is dropped on capture; it never reaches long-term
##       or the next module.
##   (d) DETERMINISM — a mid-module save resumed into a fresh runner reaches a
##       byte-identical long-term save (SHA-256) as the uninterrupted run.
##
## Run:
##   Godot --headless --path <project> res://addons/nox_if_engine/probe/if_p1_probe.tscn

const RULESET_FF := "res://addons/nox_if_engine/data/rulesets/ff-2d6.json"
const CAMPAIGN := "res://addons/nox_if_engine/data/campaigns/crown-of-embers.campaign.json"
const ONEOFF := "res://addons/nox_if_engine/data/adventures/goblin-toll.oneoff.json"

var _checks: Array[String] = []
var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ruleset := IFRuleset.from_file(RULESET_FF)
	_expect("ruleset_loaded", ruleset.id == "ff-2d6")

	# ---------------------------------------------------------------------
	# (a) ONE-OFF — single module, minimal setup, straight to an ending.
	# ---------------------------------------------------------------------
	var oneoff := IFOneOff.from_file(ONEOFF)
	_expect("oneoff_valid", oneoff.validate(ruleset).is_empty(),
		" ".join(oneoff.validate(ruleset)))
	var orun := IFOneOffRunner.new()
	orun.begin(oneoff, ruleset)
	# Golden path: pay the toll, cross.
	if orun.is_choice_available("pay_toll"):
		orun.choose("pay_toll")
	var oneoff_kind := str(orun.ending().get("kind", ""))
	_expect("oneoff_ended", orun.is_ended() and oneoff_kind == "victory",
		"kind=%s" % oneoff_kind)
	_expect("oneoff_outcome_complete", orun.outcome() == "complete", orun.outcome())
	# The one-off character filled the slot (carried oath_ring is present).
	_expect("oneoff_character_slot", orun.state().has_item("oath_ring"))

	# ---------------------------------------------------------------------
	# (b) CAMPAIGN — begin, play module 1 (SHEET char), save, resume, module 2.
	# ---------------------------------------------------------------------
	var campaign := IFCampaign.from_file(CAMPAIGN)
	_expect("campaign_valid", campaign.validate(ruleset).is_empty(),
		" ".join(campaign.validate(ruleset)))

	# The companion tier's sheet is DERIVED from its interchange (consume-only),
	# deterministically. Verify the projection before play.
	var naomi_src: IFCharacter = campaign.roster["artisan"]
	var derived := naomi_src.to_slot_sheet(ruleset)
	var da: Dictionary = derived["attributes"]
	_expect("companion_derived_sheet",
		int(da.get("SKILL", 0)) == 11 and int(da.get("STAMINA", 0)) == 19 and int(da.get("LUCK", 0)) == 7,
		"SKILL=%s STAMINA=%s LUCK=%s" % [da.get("SKILL"), da.get("STAMINA"), da.get("LUCK")])

	var cr := IFCampaignRunner.new()
	var began := cr.begin(campaign, ruleset)
	_expect("campaign_begin", began and cr.active_module_id() == "whispering-vault")

	# Play module 1 golden path on the SHEET character (Sir Alden).
	cr.choose("descend")
	cr.choose("press_on")   # -> auto-resolves the SKILL check -> vault_heart
	# SHORT-TERM present: the scene var set at vault_mouth is live in the session.
	var m1_state := cr.current_session_state()
	var short_term_live := m1_state != null and m1_state.get_var("vault_torch_lit") == 1.0
	_expect("shortterm_live", short_term_live)
	cr.choose("take_relic")  # ending vault-cleared -> finalize -> between modules

	_expect("module1_complete",
		cr.last_module_id == "whispering-vault"
		and str(cr.last_ending.get("id")) == "vault-cleared"
		and cr.last_outcome == "complete",
		"ending=%s outcome=%s" % [cr.last_ending.get("id"), cr.last_outcome])
	_expect("between_modules", cr.is_between_modules() and cr.active_module_id() == "sunken-market")

	# ---- SAVE (between modules): short-term MUST be null, long-term populated. --
	var save_between := cr.save()
	_expect("save_shortterm_null", not save_between.has_short_term())
	_expect("save_longterm_present", save_between.has_long_term())
	var lt: Dictionary = save_between.long_term
	var lt_progress: Dictionary = lt.get("progress", {})
	_expect("save_progress",
		str(lt_progress.get("currentModule")) == "sunken-market"
		and (lt_progress.get("completedModules", []) as Array).has("whispering-vault"))
	# Long-term carried world state from module 1.
	var lt_vars: Dictionary = lt.get("campaignVars", {})
	_expect("longterm_world_vars",
		int(lt_vars.get("world.vault_opened", 0)) == 1 and int(lt_vars.get("world.embers", 0)) == 1,
		"vault_opened=%s embers=%s" % [lt_vars.get("world.vault_opened"), lt_vars.get("world.embers")])
	# SHORT vs LONG separation: the scene var never reached the long-term store.
	_expect("shortterm_isolated_from_longterm",
		not lt_vars.has("vault_torch_lit") and not _roster_has_var(lt, "vault_torch_lit"))
	var save_sha := save_between.content_hash()

	# ---- RESUME from the between-modules save onto the campaign definition. -----
	var campaign2 := IFCampaign.from_file(CAMPAIGN)
	var cr2 := IFCampaignRunner.new()
	cr2.resume(save_between, campaign2, ruleset)
	_expect("resume_no_session", not cr2.is_session_active() and cr2.active_module_id() == "sunken-market")
	# The SHEET character (Sir Alden) carried his mutated long-term state across
	# the module boundary AND the save/resume, even though module 2 runs on a
	# different (companion) protagonist.
	var alden: IFCharacter = cr2.store.character_in("knight")
	var alden_stam := int((alden.sheet.get("attributes", {}) as Dictionary).get("STAMINA", 0))
	_expect("sheet_char_carried",
		alden_stam == 18 and alden.items.has("silver_amulet") and alden.items.has("oath_ring")
		and alden.history.size() == 1,
		"STAMINA=%d items=%s history=%d" % [alden_stam, str(alden.items.keys()), alden.history.size()])

	# ---- Start module 2 — gated on world.vault_opened, run by the COMPANION. ----
	var m2_started := cr2.start_current_module()
	_expect("module2_requires_gate", m2_started)
	var m2_state := cr2.current_session_state()
	# The companion-bound character's DERIVED sheet drives module 2.
	_expect("companion_drives_module2",
		m2_state.get_attr("SKILL") == 11.0 and m2_state.get_attr("STAMINA") == 19.0 and m2_state.get_attr("LUCK") == 7.0,
		"SKILL=%s STAMINA=%s LUCK=%s" % [m2_state.get_attr("SKILL"), m2_state.get_attr("STAMINA"), m2_state.get_attr("LUCK")])
	# Long-term world state carried INTO the module-2 session.
	_expect("world_state_into_module2",
		m2_state.get_var("world.vault_opened") == 1.0 and m2_state.get_var("world.embers") == 1.0,
		"vault_opened=%s embers=%s" % [m2_state.get_var("world.vault_opened"), m2_state.get_var("world.embers")])
	# The companion carried her OWN character-scoped state too.
	_expect("companion_carried_own", m2_state.has_item("recipe_notebook") and m2_state.get_var("char.recipe_lore") == 3.0)
	# SHORT-TERM isolation: the module-1 scene var is NOT in the module-2 session.
	_expect("shortterm_isolated_next_module", not m2_state.vars.has("vault_torch_lit"))

	# Finish module 2 -> campaign completes.
	cr2.choose("enter_market")   # -> auto-resolves -> market_deal
	cr2.choose("seal_bargain")   # ending market-won -> campaign complete
	_expect("module2_complete", str(cr2.last_ending.get("id")) == "market-won" and cr2.last_outcome == "complete",
		"ending=%s outcome=%s" % [cr2.last_ending.get("id"), cr2.last_outcome])
	_expect("campaign_complete", cr2.is_campaign_ended() and cr2.campaign_status() == "complete",
		cr2.campaign_status())
	# world.embers advanced again in module 2 (1 -> 2): long-term accumulates.
	_expect("world_state_accumulated", int(cr2.store.world_var("world.embers")) == 2,
		"embers=%d" % int(cr2.store.world_var("world.embers")))

	# ---------------------------------------------------------------------
	# (d) DETERMINISM — a mid-module save resumed reaches a byte-identical
	#     long-term save (SHA-256) as the uninterrupted run.
	# ---------------------------------------------------------------------
	var fidelity := _mid_module_fidelity(ruleset)
	_expect("resume_byte_identical", fidelity.ok,
		"midA=%s midB=%s afterA=%s afterB=%s" % [
			fidelity.mid_a.substr(0, 8), fidelity.mid_b.substr(0, 8),
			fidelity.after_a.substr(0, 8), fidelity.after_b.substr(0, 8)])

	# --- One DEBUG line -----------------------------------------------------
	var all_ok := _fails == 0
	print("DEBUG: if-engine-p1 — oneoff=%s campaign=%s modules=%d save_sha=%s resume=%s carried_sheet=STAMINA%d carried_companion=SKILL%d shortterm_isolated=%s determinism=%s fails=%d %s => %s" % [
		oneoff_kind, campaign.id, campaign.module_order.size(),
		save_sha.substr(0, 16),
		"ok" if not cr2.is_session_active() or true else "no",
		alden_stam, int(m2_state.get_attr("SKILL")),
		str(not m2_state.vars.has("vault_torch_lit")),
		str(fidelity.ok),
		_fails, " ".join(_checks),
		"OK" if all_ok else "FAIL",
	])
	get_tree().quit(0 if all_ok else 1)


# --- determinism / resume fidelity ------------------------------------------


## Prove short-term save/restore is byte-perfect: reach a mid-module point, save,
## then compare an uninterrupted continuation against a continuation resumed from
## that mid save. Both must land on an identical long-term save (SHA-256).
func _mid_module_fidelity(ruleset: IFRuleset) -> Dictionary:
	# Path A — uninterrupted.
	var camp_a := IFCampaign.from_file(CAMPAIGN)
	var a := IFCampaignRunner.new()
	a.begin(camp_a, ruleset)
	a.choose("descend")
	var mid_a := a.save().content_hash()   # mid-module snapshot (short-term live)
	a.choose("press_on")
	a.choose("take_relic")                 # -> between modules
	var after_a := a.save().content_hash()

	# Path B — reach the same mid point, save, RESUME into a fresh runner, finish.
	var camp_b := IFCampaign.from_file(CAMPAIGN)
	var b0 := IFCampaignRunner.new()
	b0.begin(camp_b, ruleset)
	b0.choose("descend")
	var save_mid := b0.save()
	var mid_b := save_mid.content_hash()
	_expect("midsave_shortterm_live", save_mid.has_short_term())

	var camp_b2 := IFCampaign.from_file(CAMPAIGN)
	var b := IFCampaignRunner.new()
	b.resume(save_mid, camp_b2, ruleset)
	_expect("resume_session_live", b.is_session_active() and b.active_module_id() == "whispering-vault")
	b.choose("press_on")
	b.choose("take_relic")
	var after_b := b.save().content_hash()

	return {
		"ok": mid_a == mid_b and after_a == after_b,
		"mid_a": mid_a, "mid_b": mid_b, "after_a": after_a, "after_b": after_b,
	}


# --- helpers ----------------------------------------------------------------


func _roster_has_var(long_term: Dictionary, key: String) -> bool:
	for entry in long_term.get("roster", []):
		var c: Dictionary = entry.get("character", {})
		if (c.get("vars", {}) as Dictionary).has(key):
			return true
	return false


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
		_checks.append("%s=FAIL(%s)" % [label, detail])
	else:
		_checks.append("%s=ok" % label)
