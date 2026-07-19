extends Node
## res://scripts/course_library.gd
## Autoload "CourseLibrary" — the catalogue of courses the 3D obby can play. It
## unifies THREE sources behind one listing + one loader:
##   • BUILT-IN courses  — shipped in code (the original 'Skyward Steps' plus a
##     harder 'Vertigo Gauntlet'); always present, never written to disk.
##   • USER courses      — everything the in-game designer saved, as JSON files in
##     user://courses/<slug>.json.
##   • IMPORTED courses  — a shared .json handed to `import_course()` lands in the
##     same user dir, so it thereafter behaves exactly like a user course.
##
## Every course — regardless of source — is one CourseData3D
## (scripts/course_data3d.gd), so the editor, the player level, files and the
## network never diverge.
##
## `pending_course` is the one-slot hand-off: the course-select screen and the
## editor's Test action set it, then switch to the obby scene; obby3d.gd plays it
## (and falls back to the built-in default when it is null, so running the level
## directly is byte-identical to the pre-refactor hardcoded course). It is
## course_library.gd (the 2D template) with CourseData→CourseData3D and the
## built-in course DATA re-authored for 3D; everything else is dimension-agnostic.

const USER_DIR := "user://courses"
const BUILTIN_PREFIX := "builtin:"
const USER_PREFIX := "user:"

## Set by the select screen / editor Test; consumed by obby3d.gd on load. Null ==
## play the built-in default.
var pending_course: CourseData3D = null
## The listing id of `pending_course` when it came from the catalogue (""/unknown
## for a freshly-authored course). Lets the online sync send a built-in by id.
var pending_course_id: String = ""


## Set both the pending course and (optionally) its catalogue id in one call.
func set_pending(course: CourseData3D, id: String = "") -> void:
	pending_course = course
	pending_course_id = id


func _enter_tree() -> void:
	add_to_group(&"persistent")


func _ready() -> void:
	_ensure_user_dir()


func _ensure_user_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_DIR):
		DirAccess.make_dir_recursive_absolute(USER_DIR)


# =====================================================================
#  Built-in courses (shipped in code — the reference format)
# =====================================================================

## The original hardcoded 3D obby, verbatim, as the default so nothing regresses.
## Geometry is byte-identical to obby3d.gd's pre-refactor PLATFORMS/CHECKPOINTS/
## HAZARDS/FINISH/KILL_Y/START_SPAWN consts.
static func skyward_steps() -> CourseData3D:
	var c := CourseData3D.create("Skyward Steps", "NoxDev")
	c.created = "2026-01-01 00:00:00"
	c.start_spawn = Vector3(0.0, 1.2, 0.0)
	c.kill_y = -8.0
	c.platforms = [
		AABB(Vector3(-3.0, -0.5, -3.0), Vector3(6.0, 1.0, 6.0)),      # start deck
		AABB(Vector3(-1.5, 0.25, -10.0), Vector3(3.0, 0.5, 3.0)),
		AABB(Vector3(-1.5, 1.25, -15.0), Vector3(3.0, 0.5, 3.0)),
		AABB(Vector3(-1.5, 2.25, -20.0), Vector3(3.0, 0.5, 3.0)),
		AABB(Vector3(-1.5, 1.75, -25.0), Vector3(3.0, 0.5, 3.0)),
		AABB(Vector3(-1.5, 2.25, -30.0), Vector3(3.0, 0.5, 3.0)),
		AABB(Vector3(-2.0, 2.75, -35.0), Vector3(4.0, 0.5, 4.0)),
		AABB(Vector3(-3.0, 3.0, -41.0), Vector3(6.0, 1.0, 6.0)),      # finish deck
	] as Array[AABB]
	c.checkpoints = [
		Vector3(0.0, 2.5, -15.0),
		Vector3(0.0, 3.0, -25.0),
		Vector3(0.0, 3.5, -35.0),
	] as Array[Vector3]
	c.hazards = [
		AABB(Vector3(2.0, 0.0, -19.0), Vector3(2.0, 0.5, 2.0)),
	] as Array[AABB]
	c.finish = AABB(Vector3(-2.0, 3.5, -43.0), Vector3(4.0, 2.5, 4.0))
	return c


## A longer, meaner course — tighter pads, more hazards, five checkpoints, a
## higher final deck. Proves the format scales beyond the tutorial climb.
static func vertigo_gauntlet() -> CourseData3D:
	var c := CourseData3D.create("Vertigo Gauntlet", "NoxDev")
	c.created = "2026-01-01 00:00:00"
	c.start_spawn = Vector3(0.0, 1.2, 0.0)
	c.kill_y = -10.0
	c.platforms = [
		AABB(Vector3(-3.0, -0.5, -3.0), Vector3(6.0, 1.0, 6.0)),       # start deck
		AABB(Vector3(-1.25, 0.5, -9.0), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 1.5, -13.5), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 2.5, -18.0), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 3.5, -22.5), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 3.0, -27.0), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 4.0, -31.5), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 5.0, -36.0), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 4.5, -40.5), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 5.5, -45.0), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-1.25, 6.5, -49.5), Vector3(2.5, 0.5, 2.5)),
		AABB(Vector3(-3.0, 7.0, -55.0), Vector3(6.0, 1.0, 6.0)),       # finish deck
	] as Array[AABB]
	c.checkpoints = [
		Vector3(0.0, 2.0, -13.5),
		Vector3(0.0, 4.0, -22.5),
		Vector3(0.0, 4.5, -31.5),
		Vector3(0.0, 6.0, -40.5),
		Vector3(0.0, 7.0, -49.5),
	] as Array[Vector3]
	c.hazards = [
		AABB(Vector3(1.5, 0.5, -13.5), Vector3(1.5, 0.4, 1.5)),
		AABB(Vector3(-3.0, 2.5, -22.5), Vector3(1.5, 0.4, 1.5)),
		AABB(Vector3(1.5, 4.0, -31.5), Vector3(1.5, 0.4, 1.5)),
		AABB(Vector3(-3.0, 5.5, -40.5), Vector3(1.5, 0.4, 1.5)),
	] as Array[AABB]
	c.finish = AABB(Vector3(-2.0, 7.5, -57.0), Vector3(4.0, 2.5, 4.0))
	return c


## Ordered list of the built-ins {id, factory}. Add new built-ins here.
static func _builtin_registry() -> Array[Dictionary]:
	return [
		{"id": BUILTIN_PREFIX + "skyward_steps", "make": Callable(CourseLibrary, "skyward_steps")},
		{"id": BUILTIN_PREFIX + "vertigo_gauntlet", "make": Callable(CourseLibrary, "vertigo_gauntlet")},
	]


## The course played when nothing is selected — the original obby, unchanged.
static func default_course() -> CourseData3D:
	return skyward_steps()


# =====================================================================
#  Listing (built-in + user + imported)
# =====================================================================

## Every course the player can pick, source-agnostic:
## [{id, name, author, source:"builtin"|"user", path}]. Built-ins first, then
## user/imported courses sorted by name.
func list_courses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _builtin_registry():
		var c: CourseData3D = (entry["make"] as Callable).call()
		out.append({
			"id": str(entry["id"]),
			"name": c.name,
			"author": c.author,
			"source": "builtin",
			"path": "",
		})
	var user_entries: Array[Dictionary] = []
	for file in _user_files():
		var path := USER_DIR + "/" + file
		var c := _load_json_file(path)
		if c == null:
			continue
		user_entries.append({
			"id": USER_PREFIX + file.get_basename(),
			"name": c.name,
			"author": c.author,
			"source": "user",
			"path": path,
		})
	user_entries.sort_custom(func(a, b): return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	out.append_array(user_entries)
	return out


func _user_files() -> PackedStringArray:
	_ensure_user_dir()
	var files := PackedStringArray()
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return files
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.to_lower().ends_with(".json"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return files


# =====================================================================
#  Loading (by id or name)
# =====================================================================

## Load any course by its listing id ("builtin:<slug>" or "user:<slug>").
## Returns null if it cannot be found/parsed.
func load_course(id: String) -> CourseData3D:
	if id.begins_with(BUILTIN_PREFIX):
		for entry in _builtin_registry():
			if str(entry["id"]) == id:
				return (entry["make"] as Callable).call()
		return null
	if id.begins_with(USER_PREFIX):
		var slug := id.substr(USER_PREFIX.length())
		return _load_json_file(USER_DIR + "/" + slug + ".json")
	# Bare id: try user slug first, then a built-in slug.
	var direct := _load_json_file(USER_DIR + "/" + id + ".json")
	if direct != null:
		return direct
	for entry in _builtin_registry():
		if str(entry["id"]) == BUILTIN_PREFIX + id:
			return (entry["make"] as Callable).call()
	return null


## Load the first course whose display name matches (case-insensitive). Searches
## built-ins then user courses. Null if none match.
func load_by_name(course_name: String) -> CourseData3D:
	var wanted := course_name.strip_edges().to_lower()
	for entry in list_courses():
		if str(entry["name"]).strip_edges().to_lower() == wanted:
			return load_course(str(entry["id"]))
	return null


# =====================================================================
#  Saving / export / import
# =====================================================================

## Persist a course to user://courses/<slug>.json (slug derived from its name).
## Returns the listing id ("user:<slug>") or "" on write failure.
func save_course(course: CourseData3D) -> String:
	if course == null:
		return ""
	_ensure_user_dir()
	var slug := slugify(course.name)
	var path := USER_DIR + "/" + slug + ".json"
	if _write_json_file(path, course.to_json()) != OK:
		return ""
	return USER_PREFIX + slug


## Write a course to an ARBITRARY path as portable JSON (the share/publish hand-
## off — email it, drop it in a Discord, hand it on a USB stick). Returns Error.
func export_course(course: CourseData3D, dest_path: String) -> Error:
	if course == null:
		return ERR_INVALID_PARAMETER
	return _write_json_file(dest_path, course.to_json())


## Read a shared .json from `src_path`, add it to the user library (so it shows in
## the listing), and return the CourseData3D. Null on read/parse failure.
func import_course(src_path: String) -> CourseData3D:
	var course := _load_json_file(src_path)
	if course == null:
		return null
	save_course(course)
	return course


# --- share / publish seam ----------------------------------------------------
#
# ┌─ Studio course-exchange integration point ────────────────────────────────┐
# │ Uploading a course to a shared server (browse/rate/download other players' │
# │ courses online) is a STUDIO feature, out of template scope. Wire it HERE:  │
# │ POST `course.to_json()` to the exchange, and feed downloaded JSON through  │
# │ `import_course()` (or `CourseData3D.from_json()` + `save_course()`). The   │
# │ template ships only local file export/import; the format is already the    │
# │ wire format, so no data-model change is needed to go online.               │
# └────────────────────────────────────────────────────────────────────────────┘


# =====================================================================
#  Helpers
# =====================================================================

## file-system-safe slug from a course name ("Sky Gauntlet!" -> "sky_gauntlet").
static func slugify(text: String) -> String:
	var s := text.strip_edges().to_lower()
	var out := ""
	for i in s.length():
		var ch := s[i]
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
		# other punctuation dropped
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	if out.is_empty():
		out = "course"
	return out


func _load_json_file(path: String) -> CourseData3D:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[CourseLibrary] cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	return CourseData3D.from_json(text)


## Atomic-ish write: to <path>.tmp, flush, then rename (mirrors save-system's
## crash-safe pattern so a mid-write crash never corrupts a course file).
func _write_json_file(path: String, text: String) -> Error:
	var base_dir := path.get_base_dir()
	if not base_dir.is_empty() and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error("[CourseLibrary] cannot write %s (err %d)" % [tmp, err])
		return err if err != OK else FAILED
	f.store_string(text)
	f.flush()
	f.close()
	var da := DirAccess.open(base_dir if not base_dir.is_empty() else ".")
	if da == null:
		return FAILED
	if da.file_exists(path):
		da.remove(path)
	return da.rename(tmp, path)
