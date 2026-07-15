class_name IFOneOffRunner
extends RefCounted
## res://addons/nox_if_engine/if_oneoff_runner.gd
## The ONE-OFF entry point (spec P1) — plays a single-module adventure straight to
## an ending. Deliberately thin: it is the P0 IFRunner with a module's entry/exit
## wrapper and an optional character filling the protagonist slot. No long-term
## store, no progression — the counterpart to IFCampaignRunner, kept SEPARATE so
## the quick front door and the campaign surface never share code paths beyond the
## shared engine itself.
##
## Usage:
##   var oneoff := IFOneOff.from_file(".../goblin-toll.oneoff.json")
##   var run := IFOneOffRunner.new()
##   run.begin(oneoff, ruleset)
##   while not run.is_ended():
##       run.choose(run.available_choices()[0].id)
##   var ending := run.ending()

var oneoff: IFOneOff
var ruleset: IFRuleset
var runner: IFRunner


func begin(oneoff_in: IFOneOff, ruleset_in: IFRuleset) -> void:
	oneoff = oneoff_in
	ruleset = ruleset_in
	var module := oneoff.module
	var scenario := module.scenario
	# Entry override: start at the module's declared start passage.
	scenario.start = module.start_passage()

	runner = IFRunner.new()
	# A supplied character fills the slot; otherwise the scenario sheet is used.
	if oneoff.has_character:
		var sheet := oneoff.character.to_slot_sheet(ruleset)
		runner.load(ruleset, scenario, oneoff.seed, sheet)
		# Seed the character's carried vars/items onto the fresh session.
		_seed_carried(oneoff.character)
	else:
		runner.load(ruleset, scenario, oneoff.seed)

	# Module onEntry effects, then begin.
	runner.state.apply_effects(module.entry_on_entry)
	runner.start()


func _seed_carried(character: IFCharacter) -> void:
	for k in character.carried_vars().keys():
		runner.state.set_var(str(k), float(character.carried_vars()[k]))
	for k in character.carried_items().keys():
		runner.state.grant_item(str(k), int(character.carried_items()[k]))
	for k in character.carried_flags().keys():
		runner.state.set_flag(str(k), character.carried_flags()[k])


func available_choices() -> Array:
	return runner.available_choices()


func is_choice_available(choice_id: String) -> bool:
	return runner.is_choice_available(choice_id)


func choose(choice_id: String) -> void:
	runner.choose(choice_id)


func is_ended() -> bool:
	return runner.is_ended()


func ending() -> Dictionary:
	return runner.ending()


func state() -> IFState:
	return runner.state


## The exit outcome the reached ending maps to ("complete"/"fail"), via the
## module's exit contract — even a one-off gets the same win/lose classification.
func outcome() -> String:
	if not is_ended():
		return ""
	return str(oneoff.module.exit_rule_for(ending()).get("outcome", "fail"))
