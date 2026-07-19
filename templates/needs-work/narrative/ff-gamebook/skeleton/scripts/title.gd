extends Control
## res://scripts/title.gd
## Title screen: Begin Adventure rolls a fresh adventure sheet, resets the
## session and opens the book. Also emits the boot probe proving the core
## loop exists: the asset manifest loaded (N slots), a passage rendered with
## its bound illustration slot, a choice advanced the passage through
## SessionState, the 2d6 skill check resolved both pass and fail branches
## through the real dialogue, and the session-state interface (the future
## ENet sync point) was exercised end to end. The probe is fully seeded, so
## its line is byte-identical across boots; play is re-randomized afterwards.

const BOOK_SCENE := "res://scenes/book.tscn"
const BOOK_DIALOGUE := "res://dialogue/book.dialogue"

@onready var _begin_button: Button = $Center/Rows/BeginButton
@onready var _quit_button: Button = $Center/Rows/QuitButton


func _ready() -> void:
	_begin_button.pressed.connect(_on_begin_pressed)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_begin_button.grab_focus()
	_emit_boot_probe.call_deferred()


func _on_begin_pressed() -> void:
	Sheet.roll_new_character()
	SessionState.reset_session()
	get_tree().change_scene_to_file(BOOK_SCENE)


func _emit_boot_probe() -> void:
	# Deterministic probe: seeded sheet, fixed roll-under target, seeded dice.
	Sheet.set_seed(7)
	Sheet.roll_new_character()
	Sheet.skill = 7  # fixed 2d6 target so both branches are reachable
	SessionState.reset_session()
	Dice.show_popup = false

	# 1) Manifest: loaded, slot count, kind split.
	var kinds := AssetBinder.counts_by_kind()

	# 2) Page render: run the real book scene — its opening passage mutation
	#    routes through SessionState and the plate binds its manifest slot.
	var book: Control = (load(BOOK_SCENE) as PackedScene).instantiate()
	add_child(book)
	if SessionState.current_passage != "passage_1":
		await SessionState.passage_changed
	await get_tree().process_frame
	await get_tree().process_frame
	var plate = book.find_child("Plate", true, false)
	var dialogue_label = book.find_child("DialogueLabel", true, false)
	var page_render: bool = SessionState.current_passage == "passage_1" \
			and plate != null and plate.bound_slot_id == "illustration/passage_1" \
			and dialogue_label != null and dialogue_label.dialogue_line != null
	var plate_desc := "?"
	if plate != null:
		plate_desc = "%s(%s)" % [
			plate.bound_slot_id, "placeholder" if plate.is_placeholder else "art",
		]
	book.queue_free()

	# 3) Choice advances the passage — the same SessionState.choose() route
	#    the page's response buttons take.
	var resource: DialogueResource = load(BOOK_DIALOGUE)
	var line: DialogueLine = await resource.get_next_dialogue_line("passage_1")
	var guard := 0
	while line != null and line.responses.is_empty() and guard < 8:
		line = await resource.get_next_dialogue_line(line.next_id)
		guard += 1
	var from_passage := SessionState.current_passage
	line = await resource.get_next_dialogue_line(
			SessionState.choose(line.responses[0].next_id, line.responses[0].text))
	var choice_ok: bool = from_passage == "passage_1" \
			and SessionState.current_passage == "passage_2"

	# 4) 2d6 skill check, both branches, through the real passage_5 dialogue.
	#    Scan seeds for one pass and one fail (deterministic given the seed).
	var seed_pass := -1
	var seed_fail := -1
	for s in range(1, 400):
		Dice.set_seed(s)
		var r := Dice.roll_test("skill")
		if r.success and seed_pass < 0:
			seed_pass = s
		elif not r.success and seed_fail < 0:
			seed_fail = s
		if seed_pass > 0 and seed_fail > 0:
			break

	Dice.set_seed(seed_pass)
	line = await resource.get_next_dialogue_line("passage_5")
	line = await resource.get_next_dialogue_line(line.next_id)  # roll + branch
	var pass_roll: Dictionary = Dice.last_result.duplicate(true)
	line = await resource.get_next_dialogue_line(line.next_id)  # => passage_7
	var pass_ok: bool = pass_roll.success and SessionState.current_passage == "passage_7"

	var stamina_before := Sheet.stamina
	Dice.set_seed(seed_fail)
	line = await resource.get_next_dialogue_line("passage_5")
	line = await resource.get_next_dialogue_line(line.next_id)  # roll + branch
	var fail_roll: Dictionary = Dice.last_result.duplicate(true)
	line = await resource.get_next_dialogue_line(line.next_id)  # damage line
	line = await resource.get_next_dialogue_line(line.next_id)  # => passage_3
	var fail_ok: bool = (not fail_roll.success) \
			and Sheet.stamina == stamina_before - 2 \
			and SessionState.current_passage == "passage_3"

	# 5) Session interface: trail + roll log recorded; DM-seat hooks are the
	#    documented no-ops (return false until the ENet layer lands).
	var dm_noop: bool = SessionState.dm_push_passage("passage_1") == false \
			and SessionState.dm_override_roll({}) == false

	print("DEBUG: ff-gamebook core loop ready — manifest=%d slots (illustration=%d ui=%d audio=%d) page_render=%s plate=%s choice=%s->%s skill_pass=(2d6=%d vs %d -> %s => %s) skill_fail=(2d6=%d vs %d -> %s, STAMINA %d->%d => %s) session=[passages=%d rolls=%d dm_noop=%s]" % [
		AssetBinder.slot_count(),
		int(kinds.get("illustration", 0)), int(kinds.get("ui", 0)), int(kinds.get("audio", 0)),
		page_render, plate_desc,
		from_passage, "passage_2" if choice_ok else SessionState.current_passage,
		pass_roll.total, pass_roll.target, pass_roll.success,
		"passage_7" if pass_ok else "?",
		fail_roll.total, fail_roll.target, fail_roll.success,
		stamina_before, Sheet.stamina, "passage_3" if fail_ok else "?",
		SessionState.passage_history.size(), SessionState.roll_log.size(), dm_noop,
	])

	# Hand the book back to the player: popups on, randomness restored.
	Dice.show_popup = true
	Dice.set_seed(randi())
	Sheet.set_seed(randi())
	Sheet.roll_new_character()
	SessionState.reset_session()
