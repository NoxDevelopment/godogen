extends Node
## res://scripts/save_manager.gd
## SaveManager (autoload "SaveManager") — the FF-gamebook save/load layer, built on the
## `save-system` skill's cardinal rules (atomic write via <tmp>+rename, versioned, one
## folder under user://, a slot list with a summary + timestamp) but storing the game's
## own canonical serializable unit — the GDD §5 FFGameState (via Adventure.save_data()/
## load_data()) — rather than a generic SaveData preset. It is deliberately
## INTERFACE-COMPATIBLE with the `loading-continue` skill's slot picker (load_screen)
## and ContinueService (list_slots / load_from_slot / save_to_slot / delete_slot), so
## the shell's Continue button and the Save/Load screen "just work" over FF saves.
##
## Save MODES (GDD §4). Default = Bookmarks (unlimited revisit points); Ironman for
## purists (single rolling autosave, wiped on death — restart-on-death, no reload).
## Rewind / Checkpoints are wired here with documented seams (see the stubs) and are
## surfaced in Options as preview modes.

signal save_completed(slot: int, success: bool)
signal load_completed(slot: int, success: bool, data: Object)

const SAVE_DIR := "user://saves/"
const RESUME_SCENE := "res://scenes/reading_view.tscn"
const VERSION := 1

## Slot layout. Slot 0 is the rolling quick/autosave (used by the HUD Quick-Save, the
## Ironman autosave and the Continue button); slots 1..BOOKMARK_SLOTS are the unlimited
## Bookmarks the player names by section; CHECKPOINT_SLOT is the mode-gated checkpoint.
const QUICK_SLOT := 0
const BOOKMARK_SLOTS := 8
const CHECKPOINT_SLOT := 20


## One save entry. Exposes `scene_path` (read by ContinueService/load_screen) plus the
## FFGameState `payload` and display `meta`. RefCounted so it is cheap to pass around.
class SaveEntry:
	extends RefCounted
	## Literal (inner classes don't inherit the outer scope's consts); mirrors
	## SaveManager.RESUME_SCENE.
	var scene_path: String = "res://scenes/reading_view.tscn"
	var payload: Dictionary = {}
	var meta: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# Wire the shell's Continue button to us directly too (belt-and-suspenders with the
	# ContinueService autoload): NoxShell.has_resumable()/resume_last() will prefer this
	# provider, so Continue always resumes the newest save rather than starting fresh.
	var shell := get_node_or_null("/root/NoxShell")
	if shell != null and shell.has_method("set_resume_provider"):
		shell.set_resume_provider(self)


# --- paths -----------------------------------------------------------------------

func _slot_path(slot: int) -> String:
	return "%sslot_%d.json" % [SAVE_DIR, slot]


# --- mode helpers ----------------------------------------------------------------

func _is_ironman() -> bool:
	var s := get_node_or_null("/root/FFSettings")
	return s != null and s.has_method("is_ironman") and s.is_ironman()

## The slot the quick-save / autosave / Continue uses. Ironman funnels everything to
## the single QUICK_SLOT (a rolling autosave); other modes use it as the quick slot.
func autosave_slot() -> int:
	return QUICK_SLOT

## Whether the player may pick manual bookmark slots in the current mode. Ironman
## forbids manual saves (the run is the single rolling autosave).
func manual_saves_allowed() -> bool:
	return not _is_ironman()


# --- capture / apply -------------------------------------------------------------

## Snapshot the live run into a SaveEntry (the GDD §5 FFGameState + display meta).
func capture_current() -> SaveEntry:
	var e := SaveEntry.new()
	var adv := get_node_or_null("/root/Adventure")
	if adv == null or not adv.has_run():
		return e
	e.payload = adv.save_data()
	e.meta = {
		"section": str(adv.runner.state.current_passage),
		"skill": adv.sheet.cur("skill"),
		"stamina": adv.sheet.cur("stamina"),
		"stamina_max": adv.sheet.init_of("stamina"),
		"luck": adv.sheet.cur("luck"),
		"luck_max": adv.sheet.init_of("luck"),
		"gold": adv.sheet.gold,
		"turn": adv.turn,
		"saved_at": int(Time.get_unix_time_from_system()),
	}
	return e


func _summary(meta: Dictionary) -> String:
	if meta.is_empty():
		return ""
	return "§%s   ·   SK %d  ST %d/%d  LK %d/%d   ·   turn %d" % [
		str(meta.get("section", "?")),
		int(meta.get("skill", 0)),
		int(meta.get("stamina", 0)), int(meta.get("stamina_max", 0)),
		int(meta.get("luck", 0)), int(meta.get("luck_max", 0)),
		int(meta.get("turn", 0)),
	]


# --- write -----------------------------------------------------------------------

## Atomic slot write (save-system cardinal rule: <tmp> + flush + rename). `data` may be
## a SaveEntry from capture_current(); a null/foreign value snapshots the live run.
func save_to_slot(slot: int, data: Object = null) -> int:
	var entry: SaveEntry = data if data is SaveEntry else capture_current()
	if entry.payload.is_empty():
		push_warning("SaveManager: nothing to save (no active run)")
		save_completed.emit(slot, false)
		return ERR_UNAVAILABLE
	var blob := {
		"version": VERSION,
		"meta": entry.meta,
		"payload": entry.payload,
	}
	var path := _slot_path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open %s for write" % tmp)
		save_completed.emit(slot, false)
		return ERR_CANT_OPEN
	f.store_string(JSON.stringify(blob, "  "))
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		# rename may fail across some backends if the target exists — remove + retry
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	var ok := err == OK
	save_completed.emit(slot, ok)
	return err


## Quick-save / autosave to the rolling slot (HUD Save button, Ironman autosave).
func quick_save() -> int:
	return save_to_slot(autosave_slot())


# --- read ------------------------------------------------------------------------

func _read_slot(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Load a slot: applies its FFGameState to the live Adventure (so the reading view
## restores on _ready) and returns a SaveEntry carrying `scene_path` for the caller
## (ContinueService / load_screen change into scene_path). Returns null on failure.
func load_from_slot(slot: int) -> SaveEntry:
	var blob := _read_slot(slot)
	if blob.is_empty():
		push_error("SaveManager: slot %d is empty/unreadable" % slot)
		load_completed.emit(slot, false, null)
		return null
	var entry := SaveEntry.new()
	entry.payload = blob.get("payload", {})
	entry.meta = blob.get("meta", {})
	var adv := get_node_or_null("/root/Adventure")
	if adv != null and not entry.payload.is_empty():
		adv.load_data(entry.payload)
	load_completed.emit(slot, true, entry)
	return entry


func quick_load() -> SaveEntry:
	return load_from_slot(autosave_slot())


# --- delete / list ---------------------------------------------------------------

func delete_slot(slot: int) -> int:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return OK


## The slots the picker shows, as {slot, exists, modified_time, thumbnail_path,
## summary}. In Ironman only the rolling autosave is exposed; otherwise the quick slot
## plus the unlimited Bookmarks.
func list_slots() -> Array:
	var out: Array = []
	var slots: Array[int] = [QUICK_SLOT]
	if not _is_ironman():
		for i in range(1, BOOKMARK_SLOTS + 1):
			slots.append(i)
	for slot in slots:
		out.append(_slot_info(slot))
	return out


func _slot_info(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	var exists := FileAccess.file_exists(path)
	var mtime := 0
	var summary := ""
	if exists:
		mtime = int(FileAccess.get_modified_time(path))
		var blob := _read_slot(slot)
		summary = _summary(blob.get("meta", {}))
	var label := "Quick / Autosave" if slot == QUICK_SLOT else ("Bookmark %d" % slot)
	return {
		"slot": slot,
		"exists": exists,
		"modified_time": mtime,
		"thumbnail_path": "",
		"summary": summary,
		"label": label,
	}


func has_any_save() -> bool:
	for s in list_slots():
		if s.get("exists", false):
			return true
	return false


# --- Continue (resume-last) — the NoxShell resume-provider contract ---------------

func has_resumable() -> bool:
	return has_any_save()


## Resume the newest save: load it (applying state to Adventure) and change into the
## reading view. Routes through SceneLoader when present for a real loading transition.
func resume_last() -> void:
	var slot := newest_slot()
	if slot < 0:
		push_warning("SaveManager.resume_last(): nothing to resume")
		return
	var entry := load_from_slot(slot)
	if entry == null:
		return
	var loader := get_node_or_null("/root/SceneLoader")
	if loader != null and loader.has_method("change_scene"):
		loader.change_scene(entry.scene_path)
	else:
		get_tree().change_scene_to_file(entry.scene_path)


func newest_slot() -> int:
	var best := -1
	var best_time := -1
	for s in list_slots():
		if not s.get("exists", false):
			continue
		var t := int(s.get("modified_time", 0))
		if t > best_time:
			best_time = t
			best = int(s.get("slot", -1))
	return best


# --- mode hooks ------------------------------------------------------------------

## Called when the hero dies. Ironman is restart-on-death with NO reload, so the run's
## save is wiped — the player cannot load back into a dead run.
func on_death() -> void:
	if _is_ironman():
		delete_slot(autosave_slot())


## CHECKPOINTS (preview): a section flagged as a checkpoint calls this to drop a
## mode-gated autosave. Wired seam; content-side checkpoint flags are a v1.1 follow-up.
func mark_checkpoint() -> void:
	var s := get_node_or_null("/root/FFSettings")
	if s != null and s.save_mode == 3:   # FFSettings.SaveMode.CHECKPOINTS
		save_to_slot(CHECKPOINT_SLOT)


## REWIND (preview): inkle-style "the story remembers — revise a past choice". The
## engine already keeps IFState.passage_history; a full rewind rebuilds state at an
## earlier index. Exposed as a documented seam surfaced in Options; the interactive
## timeline UI is a v1.1 follow-up.
func can_rewind() -> bool:
	var adv := get_node_or_null("/root/Adventure")
	return adv != null and adv.runner != null and adv.runner.state.passage_history.size() > 1
