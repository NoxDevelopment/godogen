class_name IFCampaignRunner
extends RefCounted
## res://addons/nox_if_engine/if_campaign_runner.gd
## The CAMPAIGN entry point (spec P1) — orchestrates a multi-module campaign over
## the P0 engine, owning the SHORT-TERM session (the active IFRunner) and the
## LONG-TERM store (IFCampaignStore) and the flow between them:
##
##   begin -> [ start module -> play to ending -> capture into long-term ->
##             advance to next module ] * -> campaign complete
##
## The two persistence layers are visibly separate here. During a module the
## world/campaign vars (namespaced `world.*`) and the protagonist's carried
## vars/inventory (`char.*` / `item.*`) are LAYERED onto the live session so the
## narrative graph can read and write them with the ordinary condition/effect
## vocabulary. At module end, `_capture` promotes ONLY those namespaced keys back
## into the long-term store (world.* -> campaign, char.*/item.* + the sheet ->
## the character); every other session var was scene-scoped and is dropped. That
## capture is exactly what makes a character — a lightweight sheet OR a
## companion-bound one — carry into the next module with its state intact, while
## the scene it just left does not.
##
## save()/resume() serialise both layers via IFSaveGame: long-term always,
## short-term only when a session is live (a mid-module save). Content (modules,
## scenarios, rulesets) is NOT in the save — resume() is handed the campaign
## definition again and rehydrates the mutable state onto it.

const WORLD_PREFIX := "world."
const CHAR_PREFIX := "char."

var campaign: IFCampaign
var ruleset: IFRuleset
var store: IFCampaignStore

## The active short-term session (null between modules / after the campaign ends).
var runner: IFRunner
var _session_active: bool = false

## The last module that ended and how (for the caller/probe).
var last_module_id: String = ""
var last_ending: Dictionary = {}
var last_outcome: String = ""


# --- lifecycle --------------------------------------------------------------


## Begin a NEW campaign: build the long-term store from the campaign's authored
## defaults + roster, then start the first module's session. `seed_override` < 0
## uses the campaign's own master seed.
func begin(campaign_in: IFCampaign, ruleset_in: IFRuleset, seed_override: int = -1) -> bool:
	campaign = campaign_in
	ruleset = ruleset_in
	store = IFCampaignStore.new()
	store.init_from_campaign(campaign, seed_override)
	return start_current_module()


## Start (or resume-into) the session for store.current_module. Returns false if
## the module is gated by an unmet `requires` or the campaign is already ended.
func start_current_module() -> bool:
	if store.status != "active":
		return false
	var module_id := store.current_module
	if not campaign.has_module(module_id):
		push_error("IFCampaignRunner: current module '%s' not in campaign" % module_id)
		store.status = "failed"
		return false
	var module := campaign.module_of(module_id)
	var slot := campaign.protagonist_for(module_id)
	var character := store.character_in(slot)
	if character == null:
		push_error("IFCampaignRunner: no roster character in slot '%s'" % slot)
		store.status = "failed"
		return false

	# Entry gate: `requires` conditions checked against the LONG-TERM state.
	if not _requires_met(module.entry_requires, character):
		push_error("IFCampaignRunner: module '%s' entry requirements not met" % module_id)
		return false

	# Fresh session, seeded deterministically from the campaign master seed.
	var scenario := module.scenario
	scenario.start = module.start_passage()
	var ordinal := store.module_history.size() + 1
	var seed := store.module_seed(ordinal)

	runner = IFRunner.new()
	runner.load(ruleset, scenario, seed, character.to_slot_sheet(ruleset))

	# Layer the LONG-TERM state onto the SHORT-TERM session.
	_layer_long_term(character)
	# Module entry effects, then begin play.
	runner.state.apply_effects(module.entry_on_entry)
	runner.start()
	_session_active = true

	# A module could end on entry (auto-resolution to an ending); handle it.
	_maybe_finalize()
	return true


## Layer campaign (world.*) + the protagonist's carried (char.*/item.*) state onto
## the live session. Called after load() so it overrides the module's init defaults.
func _layer_long_term(character: IFCharacter) -> void:
	for k in store.campaign_vars.keys():
		runner.state.set_var(str(k), float(store.campaign_vars[k]))
	for k in store.campaign_flags.keys():
		runner.state.set_flag(str(k), store.campaign_flags[k])
	var cv := character.carried_vars()
	for k in cv.keys():
		runner.state.set_var(str(k), float(cv[k]))
	var ci := character.carried_items()
	for k in ci.keys():
		runner.state.grant_item(str(k), int(ci[k]))
	var cf := character.carried_flags()
	for k in cf.keys():
		runner.state.set_flag(str(k), cf[k])


func _requires_met(requires: Array, character: IFCharacter) -> bool:
	if requires == null or requires.is_empty():
		return true
	# Evaluate against a scratch state carrying the long-term values.
	var scratch := IFState.new(ruleset)
	scratch.init_sheet(character.to_slot_sheet(ruleset))
	for k in store.campaign_vars.keys():
		scratch.set_var(str(k), float(store.campaign_vars[k]))
	for k in store.campaign_flags.keys():
		scratch.set_flag(str(k), store.campaign_flags[k])
	for k in character.carried_vars().keys():
		scratch.set_var(str(k), float(character.carried_vars()[k]))
	for k in character.carried_items().keys():
		scratch.grant_item(str(k), int(character.carried_items()[k]))
	return scratch.conditions_met(requires)


# --- play (delegates to the active session) ---------------------------------


func available_choices() -> Array:
	if not _session_active or runner == null:
		return []
	return runner.available_choices()


func is_choice_available(choice_id: String) -> bool:
	return _session_active and runner != null and runner.is_choice_available(choice_id)


## Take a choice; if it ends the module, capture + advance automatically.
func choose(choice_id: String) -> void:
	if not _session_active or runner == null:
		push_warning("IFCampaignRunner: choose('%s') with no active session" % choice_id)
		return
	runner.choose(choice_id)
	_maybe_finalize()


func current_session_state() -> IFState:
	return runner.state if runner != null else null


func active_module_id() -> String:
	return store.current_module


# --- module boundary --------------------------------------------------------


func _maybe_finalize() -> void:
	if _session_active and runner != null and runner.is_ended():
		_finalize_module()


## The module has reached an ending: apply the exit rule, capture the session into
## the long-term store, and advance the current-module pointer (or end the
## campaign). After this the session is inactive — a save here is "between
## modules" (short-term null); the next module is started by start_current_module().
func _finalize_module() -> void:
	var module_id := store.current_module
	var module := campaign.module_of(module_id)
	var slot := campaign.protagonist_for(module_id)
	var character := store.character_in(slot)

	var ending := runner.ending()
	var exit_rule := module.exit_rule_for(ending)
	var outcome := str(exit_rule.get("outcome", "fail"))

	# Exit effects mutate the SESSION first (so world.* lands in session vars),
	# then _capture promotes them into the long-term store.
	runner.state.apply_effects(exit_rule.get("effects", []))
	_capture(character)

	character.note_module(module_id, ending)
	store.mark_completed(module_id, ending)

	last_module_id = module_id
	last_ending = ending
	last_outcome = outcome

	_session_active = false

	if outcome != "complete":
		store.status = "failed"
		return

	# Advance: explicit goto, else the campaign's linear next.
	var next_id := str(exit_rule.get("goto", ""))
	if next_id == "":
		next_id = campaign.next_module_after(module_id)
	if next_id == "":
		store.status = "complete"
		store.current_module = ""
	else:
		store.current_module = next_id


## Promote the played session into the long-term store: the protagonist's sheet +
## char.*/item.* into the character; world.* into the campaign store. Everything
## else in the session is scene-scoped short-term state and is intentionally left
## behind — this is the concrete short-term/long-term separation.
func _capture(character: IFCharacter) -> void:
	# Character: full sheet + inventory + char.* vars/flags.
	character.capture_from(runner.state, CHAR_PREFIX)
	# Campaign: world.* vars/flags.
	for k in runner.state.vars.keys():
		var key := str(k)
		if key.begins_with(WORLD_PREFIX):
			store.campaign_vars[key] = runner.state.vars[k]
	for k in runner.state.flags.keys():
		var key := str(k)
		if key.begins_with(WORLD_PREFIX):
			store.campaign_flags[key] = runner.state.flags[k]


# --- status -----------------------------------------------------------------


func is_session_active() -> bool:
	return _session_active


func is_between_modules() -> bool:
	return not _session_active and store.status == "active" and store.current_module != ""


func is_campaign_ended() -> bool:
	return store.status == "complete" or store.status == "failed"


func campaign_status() -> String:
	return store.status


# --- persistence ------------------------------------------------------------


## Build the save: long-term always; short-term only if a session is live.
func save() -> IFSaveGame:
	var sg := IFSaveGame.new("campaign")
	sg.set_long_term(store)
	if _session_active and runner != null:
		sg.set_short_term(runner.snapshot(), store.current_module)
	else:
		sg.short_term = null
	return sg


## Resume from a save onto the campaign definition (content). Restores the long-
## term store always; if the save held a live session, restores that session
## byte-for-byte via IFRunner.restore(). If it was between modules, the caller
## continues with start_current_module().
func resume(save_game: IFSaveGame, campaign_in: IFCampaign, ruleset_in: IFRuleset) -> void:
	campaign = campaign_in
	ruleset = ruleset_in
	store = IFCampaignStore.new()
	store.load_data(save_game.long_term)

	if save_game.has_short_term():
		var module_id := str((save_game.short_term as Dictionary).get("moduleId", store.current_module))
		store.current_module = module_id
		var module := campaign.module_of(module_id)
		var scenario := module.scenario
		scenario.start = module.start_passage()
		runner = IFRunner.new()
		runner.restore(ruleset, scenario, save_game.session_snapshot())
		_session_active = true
	else:
		runner = null
		_session_active = false
