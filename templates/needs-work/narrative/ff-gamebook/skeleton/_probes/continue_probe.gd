extends Node
## res://_probes/continue_probe.gd
## Phase-7 headless probe for the Continue-button fix (issue #25). Proves — with NO
## rendering — that "Continue" now RESUMES the saved section instead of starting a new
## game, through the full shipping chain (SaveManager ↔ ContinueService ↔ NoxShell):
##
##   1) with no save present, nothing is resumable;
##   2) after saving mid-run, all three resolvers report resumable;
##   3) after a fresh "New Game" wipes in-memory state to the start section, loading the
##      newest save restores the EXACT saved section + stats (not the start);
##   4) the resume target is the reading view, NOT the new-game (roll-up) scene — i.e.
##      the old `NoxShell.new_game()` wiring is gone.
## Run: godot --headless --path <skeleton> res://_probes/continue_probe.tscn

const RESUME_SCENE := "res://scenes/reading_view.tscn"


func _ready() -> void:
	await get_tree().process_frame
	var fails := 0
	var notes: Array[String] = []

	# clean slate — remove any pre-existing slots
	for i in [0, 1, 2, 3, 4, 5, 6, 7, 8, 20]:
		SaveManager.delete_slot(i)

	# --- 1) nothing to resume before any save ---------------------------------
	var pre := SaveManager.has_resumable() or ContinueService.has_resumable() or NoxShell.has_resumable()
	if pre:
		fails += 1
	notes.append("pre_resumable=%s(expect false)" % pre)

	# --- 2) run, advance to a known section, capture, save --------------------
	Adventure.new_adventure(20260719)
	Adventure.choose("causeway")               # s1 -> s2
	var saved_section: String = Adventure.runner.state.current_passage
	var saved_skill: int = Adventure.sheet.cur("skill")
	var saved_turn: int = Adventure.turn
	var err: int = SaveManager.save_to_slot(1, SaveManager.capture_current())
	if err != OK:
		fails += 1
	notes.append("saved[section=%s skill=%d turn=%d err=%d]" % [saved_section, saved_skill, saved_turn, err])

	# --- 3) resumable now true through the whole chain ------------------------
	var sm_res := SaveManager.has_resumable()
	var cs_res := ContinueService.has_resumable()
	var shell_res := NoxShell.has_resumable()
	if not (sm_res and cs_res and shell_res):
		fails += 1
	notes.append("resumable[save=%s continue=%s shell=%s]" % [sm_res, cs_res, shell_res])

	# --- 4) simulate Quit + a FRESH New Game (state back at the start) --------
	Adventure.new_adventure(999999)
	var fresh_section: String = Adventure.runner.state.current_passage
	if fresh_section == saved_section:
		fails += 1                              # sanity: a fresh game is NOT the saved section
	notes.append("fresh_start[section=%s]" % fresh_section)

	# --- 5) THE FIX: resume loads the SAVED section, not a new game -----------
	var slot: int = SaveManager.newest_slot()
	var entry = SaveManager.load_from_slot(slot)
	var resumed_section: String = Adventure.runner.state.current_passage
	var resumed_skill: int = Adventure.sheet.cur("skill")
	var continue_ok := entry != null \
		and resumed_section == saved_section \
		and resumed_section != fresh_section \
		and resumed_skill == saved_skill
	if not continue_ok:
		fails += 1
	notes.append("RESUME[slot=%d section=%s(want %s) skill=%d(want %d) ok=%s]" % [
		slot, resumed_section, saved_section, resumed_skill, saved_skill, continue_ok])

	# --- 6) resume target is the reading view, not the new-game/roll-up scene -
	var target: String = entry.scene_path if entry != null else ""
	var new_game_scene: String = NoxShell.config.new_game_scene
	var scene_ok := target == RESUME_SCENE and target != new_game_scene
	if not scene_ok:
		fails += 1
	notes.append("resume_target=%s new_game_scene=%s ok=%s" % [target, new_game_scene, scene_ok])

	# leave no test slots behind
	SaveManager.delete_slot(1)

	print("DEBUG: ff-gamebook phase-7 continue-fix — %s  fails=%d" % [" ".join(notes), fails])
	get_tree().quit(0 if fails == 0 else 1)
