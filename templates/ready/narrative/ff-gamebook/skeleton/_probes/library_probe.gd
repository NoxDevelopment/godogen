extends Node
## res://_probes/library_probe.gd
## Adventure-ecosystem drop-1 headless probe. Proves, with NO rendering, the whole
## installable-BOOK loop (ADVENTURE_FORMAT.md):
##   1. the shelf SCANS both shipped packages (grey-tithe reference + wreckers-light)
##      and ignores _broken/_scaffold files;
##   2. the NEW book validates clean (IFAdventureValidator: no dangling/unreachable/
##      dead-ends, victory reachable) and its cover + per-book slots resolve;
##   3. selecting a book SWAPS the AssetBinder overlay (book slots win, then revert);
##   4. wreckers-light PLAYS end-to-end via the engine: a golden path to the true
##      victory AND a death terminal;
##   5. saves are PER-ADVENTURE: a save taken in book B, loaded while book A is
##      active, re-selects book B (scenario + overlay) and restores the section;
##   6. INSTALL works: a package zipped into user://adventures/ is auto-extracted on
##      scan and shelved; a bare legacy .json is synthesized and playable.
## Run: godot --headless --path <skeleton> res://_probes/library_probe.tscn

const WL_GOLDEN := [
	"inn", "ask_light", "back", "buy_provisions", "to_causeway", "_onlucky",
	"read_log", "back", "lamp_room", "back", "slip_past",
	"pick", "_onsuccess", "take_all", "show_ledger", "bind", "true_light",
]


func _ready() -> void:
	await get_tree().process_frame
	var fails := 0
	var notes: Array[String] = []

	# --- 1) the shelf scans both shipped books --------------------------------
	var books := AdventureLibrary.scan(true)
	var ids: Array[String] = []
	for e in books:
		ids.append(str(e.get("id", "")))
	var shelf_ok := ids.has("grey-tithe") and ids.has("wreckers-light") \
		and not ids.has("_broken-sample") and not ids.has("wardens-hollow.scaffold")
	if not shelf_ok: fails += 1
	notes.append("shelf[%s ok=%s]" % [",".join(ids), shelf_ok])

	# --- 2) the new book validates clean + its slots resolve ------------------
	var wl := AdventureLibrary.get_entry("wreckers-light")
	var wl_scen := IFScenario.from_file(str(wl.get("entry_path", "")))
	var v := IFAdventureValidator.validate(wl_scen, Adventure.ruleset)
	var wl_valid := bool(v.ok) and (v.errors as Array).is_empty() and bool(v.victory_reachable)
	if not wl_valid: fails += 1
	notes.append("wl_validate[ok=%s errors=%d warns=%d sections=%d]" % [
		v.ok, (v.errors as Array).size(), (v.warnings as Array).size(), wl_scen.passages.size()])
	if not wl_valid:
		notes.append("  wl_errors=%s" % " | ".join(v.errors))
	var covers_ok := AdventureLibrary.cover_texture(wl) != null \
		and AdventureLibrary.cover_texture(AdventureLibrary.get_entry("grey-tithe")) != null
	if not covers_ok: fails += 1
	notes.append("covers_resolve=%s" % covers_ok)

	# --- 3) selecting swaps the AssetBinder overlay ---------------------------
	Adventure.set_book("wreckers-light")
	var over_on: bool = AssetBinder.has_slot("plate/wl_cover") and AssetBinder.get_texture("plate/wl_shore") != null
	Adventure.set_book("grey-tithe")
	var over_off: bool = not AssetBinder.has_slot("plate/wl_cover") and AssetBinder.has_slot("plate/s1")
	if not (over_on and over_off): fails += 1
	notes.append("overlay[on=%s off=%s]" % [over_on, over_off])

	# --- 4) wreckers-light plays end-to-end -----------------------------------
	Adventure.set_book("wreckers-light")
	Adventure.new_adventure(20260721)
	var at_start := Adventure.runner.state.current_passage == "w1"
	var walked := 0
	for cid in WL_GOLDEN:
		if not _has(cid):
			notes.append("  wl golden BROKE at '%s' (passage %s)" % [cid, Adventure.runner.state.current_passage])
			break
		Adventure.choose(cid)
		walked += 1
	var win_ok := Adventure.is_ended() and str(Adventure.ending().get("kind", "")) == "victory" \
		and str(Adventure.ending().get("id", "")) == "saint_light"
	if not (at_start and win_ok): fails += 1
	notes.append("wl_golden[start=%s steps=%d/%d ending=%s ok=%s]" % [
		at_start, walked, WL_GOLDEN.size(), Adventure.ending().get("id", ""), win_ok])

	Adventure.new_adventure(20260721)
	Adventure.choose("causeway")
	Adventure.choose("_onunlucky")
	Adventure.choose("_onfailure")
	var death_ok := Adventure.is_ended() and str(Adventure.ending().get("kind", "")) == "death"
	if not death_ok: fails += 1
	notes.append("wl_death[ended=%s kind=%s ok=%s]" % [
		Adventure.is_ended(), Adventure.ending().get("kind", ""), death_ok])

	# --- 5) per-adventure saves ------------------------------------------------
	SaveManager.delete_slot(7)
	Adventure.set_book("wreckers-light")
	Adventure.new_adventure(20260721)
	Adventure.choose("inn")                      # w1 -> w3
	var saved_section: String = Adventure.runner.state.current_passage
	var err: int = SaveManager.save_to_slot(7, SaveManager.capture_current())
	var tagged := str(SaveManager._read_slot(7).get("meta", {}).get("book", "")) == "wreckers-light"
	# switch to ANOTHER book, then load — the save must pull us back into ITS book
	Adventure.set_book("grey-tithe")
	Adventure.new_adventure(999)
	var entry = SaveManager.load_from_slot(7)
	var back_ok: bool = entry != null and Adventure.book_id == "wreckers-light" \
		and Adventure.runner.state.current_passage == saved_section \
		and AssetBinder.has_slot("plate/wl_cover")
	var newest_ok: bool = SaveManager.newest_slot_for_book("wreckers-light") == 7 \
		and SaveManager.newest_slot_for_book("grey-tithe") != 7
	if err != OK or not (tagged and back_ok and newest_ok): fails += 1
	notes.append("per_book_save[err=%d tagged=%s back=%s@%s newest=%s]" % [
		err, tagged, back_ok, Adventure.runner.state.current_passage, newest_ok])
	SaveManager.delete_slot(7)

	# --- 6) install: zip drop + legacy bare json ------------------------------
	var inst := await _test_install(notes)
	if not inst: fails += 1

	print("DEBUG: ff-gamebook library (drop 1) — %s  fails=%d" % [" ".join(notes), fails])
	get_tree().quit(0 if fails == 0 else 1)


## Build a tiny valid package, ZIP it into user://adventures/, prove the scan
## extracts + shelves + plays it; also shelve a bare legacy scenario. Cleans up.
func _test_install(notes: Array[String]) -> bool:
	var user_dir := "user://adventures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir))
	var scen := {
		"id": "probe-tale", "name": "Probe Tale", "ruleset": "ff-2d6", "start": "p1",
		"meta": {"author": "probe"},
		"init": {"vars": {"gold": 1}, "items": {}, "flags": {}},
		"passages": [
			{"id": "p1", "title": "One", "text": "A door.", "choices": [
				{"id": "open", "text": "Open it.", "goto": "p2"}]},
			{"id": "p2", "title": "Two", "text": "Daylight.",
				"ending": {"id": "out", "kind": "victory", "label": "OUT"}},
		],
	}
	var man := {
		"formatVersion": 1, "id": "probe-tale", "title": "Probe Tale",
		"author": "probe", "blurb": "installer test", "difficulty": 1,
		"cover": "plate/cover", "entry": "adventure.json",
	}
	# zip a package (top-folder wrapped, the common hand-zipped shape)
	var zip_path := user_dir.path_join("probe-tale.zip")
	var zp := ZIPPacker.new()
	var zerr := zp.open(ProjectSettings.globalize_path(zip_path))
	if zerr != OK:
		notes.append("install[zip_open_err=%d]" % zerr)
		return false
	zp.start_file("probe-tale/book.json")
	zp.write_file(JSON.stringify(man, "  ").to_utf8_buffer())
	zp.close_file()
	zp.start_file("probe-tale/adventure.json")
	zp.write_file(JSON.stringify(scen, "  ").to_utf8_buffer())
	zp.close_file()
	zp.close()
	# a bare legacy scenario next to it
	var legacy_scen: Dictionary = scen.duplicate(true)
	legacy_scen["id"] = "legacy-tale"
	legacy_scen["name"] = "Legacy Tale"
	var legacy_path := user_dir.path_join("legacy-tale.json")
	var lf := FileAccess.open(legacy_path, FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy_scen, "  "))
	lf.close()

	AdventureLibrary.scan(true)
	var zip_e := AdventureLibrary.get_entry("probe-tale")
	var leg_e := AdventureLibrary.get_entry("legacy-tale")
	var shelved: bool = not zip_e.is_empty() and str(zip_e.get("source", "")) == "installed" \
		and not leg_e.is_empty() and bool(leg_e.get("legacy", false))
	# the installed book must be playable through the normal controller path
	var plays := false
	if shelved and Adventure.set_book("probe-tale"):
		Adventure.new_adventure(7)
		Adventure.choose("open")
		plays = Adventure.is_ended() and str(Adventure.ending().get("kind", "")) == "victory"
	notes.append("install[zip_shelved=%s legacy=%s plays=%s]" % [
		not zip_e.is_empty(), not leg_e.is_empty(), plays])

	# cleanup (files + extracted folder), then back to the flagship
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip_path + ".installed"))
	_rm_dir(user_dir.path_join("probe-tale"))
	AdventureLibrary.scan(true)
	Adventure.set_book("grey-tithe")
	return shelved and plays


func _rm_dir(path: String) -> void:
	var g := ProjectSettings.globalize_path(path)
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			_rm_dir(path.path_join(n))
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(n)))
		n = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(g)


func _has(cid: String) -> bool:
	for ch in Adventure.available_choices():
		if str(ch.get("id", "")) == cid:
			return true
	return false
