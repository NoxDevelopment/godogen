class_name AdventureLibrary
extends RefCounted
## res://scripts/adventure_library.gd
## The adventure-book SHELF (ADVENTURE_FORMAT.md; GDD §6.1 #2 "Library / Bookshelf").
## Discovers installable adventure packages from the two shelves:
##
##   * BUNDLED   res://data/adventures/<book-id>/   (shipped with the game)
##   * INSTALLED user://adventures/<book-id>/       ("Install" = drop a folder/zip in)
##
## A package = book.json (manifest) + adventure.json (nox_if_engine scenario) +
## assets/ (per-book plates/audio). A .zip dropped into user://adventures/ is
## auto-extracted once on scan, then treated as a folder. Bare legacy
## res://data/adventures/<id>.json scenarios still load (a manifest is synthesized)
## so pre-format content keeps working. On a duplicate id the INSTALLED book wins.
##
## Selecting a book pushes its `slots` map as a per-book overlay onto the
## AssetBinder (book slots win over the global manifest — swap once, everywhere)
## and tells the Adventure controller which scenario to run. Pure static class —
## no autoload registration needed; state lives in static vars for the process.

const FORMAT_VERSION := 1
const BUNDLED_DIR := "res://data/adventures"
const USER_DIR := "user://adventures"
const DEFAULT_BOOK := "grey-tithe"

static var _entries: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _scanned := false
static var active_id := ""


## (Re)scan both shelves. Returns the ordered entry list (bundled first, then
## installed; installed replaces bundled on an id collision).
static func scan(force: bool = false) -> Array[Dictionary]:
	if _scanned and not force:
		return _entries
	_entries = []
	_by_id = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	_extract_dropped_zips()
	for e in _scan_shelf(BUNDLED_DIR, "bundled"):
		_add_entry(e)
	for e in _scan_shelf(USER_DIR, "installed"):
		_add_entry(e)   # installed wins on duplicate id
	_scanned = true
	return _entries


static func entries() -> Array[Dictionary]:
	return scan()


static func get_entry(book_id: String) -> Dictionary:
	scan()
	return _by_id.get(book_id, {})


static func has_book(book_id: String) -> bool:
	return not get_entry(book_id).is_empty()


## The book the game opens when nothing was chosen yet: the flagship if shelved,
## else the first openable book.
static func default_id() -> String:
	scan()
	if _by_id.has(DEFAULT_BOOK) and bool(_by_id[DEFAULT_BOOK].get("format_ok", false)):
		return DEFAULT_BOOK
	for e in _entries:
		if bool(e.get("format_ok", false)):
			return str(e.get("id", ""))
	return ""


## Make `book_id` the ACTIVE book: push its per-book asset slots onto the
## AssetBinder overlay. The Adventure controller reads active() for its scenario.
static func select(book_id: String) -> bool:
	var e := get_entry(book_id)
	if e.is_empty() or not bool(e.get("format_ok", false)):
		push_error("AdventureLibrary: cannot select book '%s' (missing or incompatible)" % book_id)
		return false
	active_id = book_id
	var binder := _binder()
	if binder != null:
		binder.push_book_slots(e.get("slots", {}))
	return true


static func active() -> Dictionary:
	return get_entry(active_id) if active_id != "" else {}


## The cover Texture2D for a shelf card. Resolves the entry's `cover` slot id
## through its own slots first, then the global AssetBinder — WITHOUT needing the
## book to be active (the shelf shows every cover at once).
static func cover_texture(entry: Dictionary) -> Texture2D:
	var slot := str(entry.get("cover", ""))
	if slot == "":
		return null
	var path := str((entry.get("slots", {}) as Dictionary).get(slot, ""))
	if path != "":
		var tex := _load_texture(path)
		if tex != null:
			return tex
	var binder := _binder()
	return binder.get_texture(slot) if binder != null else null


## Open the user shelf in the OS file manager (the Library's "Open adventures
## folder" button — install by dropping a folder/zip here).
static func open_user_folder() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	OS.shell_open(ProjectSettings.globalize_path(USER_DIR))


# --- scanning ---------------------------------------------------------------


static func _add_entry(e: Dictionary) -> void:
	var id := str(e.get("id", ""))
	if id == "":
		return
	if _by_id.has(id):
		# installed overrides bundled: replace in place, keep shelf order
		for i in _entries.size():
			if str(_entries[i].get("id", "")) == id:
				_entries[i] = e
				break
	else:
		_entries.append(e)
	_by_id[id] = e


static func _scan_shelf(dir_path: String, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with(".") or name.begins_with("_"):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			var e := _read_package(full, source)
			if not e.is_empty():
				out.append(e)
		elif name.to_lower().ends_with(".json") and not name.to_lower().ends_with(".scaffold.json"):
			var e := _read_legacy(full, source)
			if not e.is_empty():
				out.append(e)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0)
	return out


## A full ADVENTURE_FORMAT.md package: <dir>/book.json + entry scenario.
static func _read_package(root: String, source: String) -> Dictionary:
	var manifest_path := root.path_join("book.json")
	if not FileAccess.file_exists(manifest_path):
		return {}
	var m: Variant = _read_json(manifest_path)
	if not (m is Dictionary):
		push_warning("AdventureLibrary: %s is not a JSON object" % manifest_path)
		return {}
	var man: Dictionary = m
	var problems: Array[String] = []
	for req in ["id", "title", "author", "blurb", "cover"]:
		if str(man.get(req, "")) == "":
			problems.append("book.json missing '%s'" % req)
	var fmt := int(man.get("formatVersion", 0))
	if fmt <= 0:
		problems.append("book.json missing 'formatVersion'")
	elif fmt > FORMAT_VERSION:
		problems.append("formatVersion %d newer than supported %d" % [fmt, FORMAT_VERSION])
	var entry_file := str(man.get("entry", "adventure.json"))
	var entry_path := root.path_join(entry_file)
	if not FileAccess.file_exists(entry_path):
		problems.append("entry scenario '%s' not found" % entry_file)
	# resolve the per-book slot map to absolute paths (relative -> package root)
	var slots := {}
	var raw_slots: Dictionary = man.get("slots", {}) if man.get("slots", {}) is Dictionary else {}
	for slot_id in raw_slots.keys():
		slots[str(slot_id)] = _resolve_asset_path(str(raw_slots[slot_id]), root)
	return {
		"id": str(man.get("id", root.get_file())),
		"title": str(man.get("title", "?")),
		"author": str(man.get("author", "?")),
		"blurb": str(man.get("blurb", "")),
		"difficulty": clampi(int(man.get("difficulty", 3)), 1, 5),
		"cover": str(man.get("cover", "")),
		"entry_path": entry_path,
		"root": root,
		"source": source,
		"slots": slots,
		"legacy": false,
		"format_version": fmt,
		"format_ok": problems.is_empty(),
		"problems": problems,
		"version": str(man.get("version", "")),
		"ruleset": str(man.get("ruleset", "ff-2d6")),
		# Optional Sorcery-style journey map (LOOKFEEL_PASS_2026-07): a per-book
		# hand-drawn map plate (slot "plate/map") + normalized node coordinates
		# {"nodes": {section_id: [x, y], ...}} laid onto it. Books without one get
		# the parchment auto-chart.
		"map": man.get("map", {}) if man.get("map", {}) is Dictionary else {},
	}


## A bare legacy scenario json (pre-format). Synthesizes the manifest from the
## scenario's own id/name/meta — backward-compatible load (ADVENTURE_FORMAT.md §5).
static func _read_legacy(path: String, source: String) -> Dictionary:
	var s: Variant = _read_json(path)
	if not (s is Dictionary):
		return {}
	var scen: Dictionary = s
	var id := str(scen.get("id", path.get_file().get_basename()))
	var meta: Dictionary = scen.get("meta", {}) if scen.get("meta", {}) is Dictionary else {}
	return {
		"id": id,
		"title": str(scen.get("name", id)),
		"author": str(meta.get("author", "unknown")),
		"blurb": str(meta.get("blurb", meta.get("status", ""))),
		"difficulty": clampi(int(meta.get("difficulty", 3)), 1, 5),
		"cover": str(meta.get("cover", "plate/cover")),
		"entry_path": path,
		"root": "",
		"source": source,
		"slots": {},
		"legacy": true,
		"format_version": FORMAT_VERSION,
		"format_ok": str(scen.get("start", "")) != "",
		"problems": [] as Array[String],
		"version": "",
		"ruleset": str(scen.get("ruleset", "ff-2d6")),
		"map": {},
	}


# --- install (.zip drop) ----------------------------------------------------


## "Install" support: any .zip sitting directly in user://adventures/ is extracted
## into a folder of the same name (once — skipped if the folder already exists),
## then the zip is renamed *.zip.installed so a rescan doesn't re-extract.
static func _extract_dropped_zips() -> void:
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.to_lower().ends_with(".zip"):
			_extract_zip(USER_DIR.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()


static func _extract_zip(zip_path: String) -> void:
	var target := USER_DIR.path_join(zip_path.get_file().get_basename())
	var zr := ZIPReader.new()
	if zr.open(ProjectSettings.globalize_path(zip_path)) != OK:
		push_warning("AdventureLibrary: cannot open zip %s" % zip_path)
		return
	var files := zr.get_files()
	# tolerate zips whose entries are wrapped in a single top folder ("<id>/book.json")
	var strip := ""
	if not files.has("book.json"):
		for f in files:
			if f.ends_with("/book.json") and f.count("/") == 1:
				strip = f.get_base_dir() + "/"
				break
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
		for f in files:
			if f.ends_with("/"):
				continue
			var rel := f.trim_prefix(strip) if strip != "" and f.begins_with(strip) else f
			if rel == "" or rel.begins_with("/") or rel.contains(".."):
				continue   # zip-slip guard
			var out_path := target.path_join(rel)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
			var fa := FileAccess.open(out_path, FileAccess.WRITE)
			if fa != null:
				fa.store_buffer(zr.read_file(f))
				fa.close()
	zr.close()
	# mark consumed so future scans don't re-extract
	DirAccess.rename_absolute(ProjectSettings.globalize_path(zip_path),
		ProjectSettings.globalize_path(zip_path + ".installed"))


# --- helpers ----------------------------------------------------------------


static func _resolve_asset_path(value: String, root: String) -> String:
	if value.begins_with("res://") or value.begins_with("user://"):
		return value
	return root.path_join(value)


static func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return null
	return JSON.parse_string(text)


static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		return res if res is Texture2D else null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) == OK:
		return ImageTexture.create_from_image(image)
	return null


static func _binder() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("AssetBinder")
	return null
