extends RefCounted
class_name CourseData
## res://scripts/course_data.gd
## The DATA-DRIVEN course model for the obby. One CourseData fully describes an
## obstacle course — its platforms, ordered checkpoint gates, hazards, a finish,
## the fall line, and where avatars spawn — plus authoring metadata (name, author,
## created). The SAME class is what:
##   • obby.gd builds a playable level from (`_build_course`),
##   • the in-game designer produces (`course_editor.gd.build_course_data`),
##   • the library saves/loads (`course_library.gd`),
##   • share/export writes to a portable `.json`, and
##   • the online course-sync broadcasts so every peer builds the identical course.
##
## There is exactly ONE course format — editor, player, library, file and network
## all round-trip through `to_dict()` / `from_dict()` (in-memory) and
## `to_json()` / `from_json()` (files + the wire). Vector2 serialises as `[x, y]`
## and Rect2 as `[x, y, w, h]` so a course is plain, human-diffable JSON.

## Serialised schema version — bump + migrate in `from_dict()` on a field change.
const SCHEMA_VERSION := 1

var name: String = "Untitled Course"
var author: String = "Anonymous"
var created: String = ""              ## ISO-ish timestamp (Time.get_datetime_string_from_system)
var start_spawn: Vector2 = Vector2(80, 400)
var platforms: Array[Rect2] = []      ## static floor pieces Rect2(x, y, w, h)
var checkpoints: Array[Vector2] = []  ## ORDERED gate positions — cleared 0,1,2,…
var hazards: Array[Rect2] = []        ## kill zones (touch → respawn)
var finish: Rect2 = Rect2(0, 0, 0, 0)
var kill_y: float = 700.0             ## fall below this → respawn at last checkpoint


# --- construction helpers ----------------------------------------------------

## Fresh course stamped with now() and the given identity.
static func create(course_name: String, course_author: String = "Anonymous") -> CourseData:
	var c := CourseData.new()
	c.name = course_name
	c.author = course_author
	c.created = Time.get_datetime_string_from_system()
	return c


func duplicate_course() -> CourseData:
	return CourseData.from_dict(to_dict())


# --- validation --------------------------------------------------------------

## A course is playable when it has at least one platform, at least one ordered
## checkpoint, a finish with real area, and a finite kill line below the start.
func is_valid() -> bool:
	return validation_errors().is_empty()


## Human-readable reasons the course is unplayable (empty == valid).
func validation_errors() -> Array[String]:
	var errs: Array[String] = []
	if name.strip_edges().is_empty():
		errs.append("course needs a name")
	if platforms.size() < 1:
		errs.append("course needs at least one platform")
	if checkpoints.size() < 1:
		errs.append("course needs at least one checkpoint")
	if finish.size.x <= 0.0 or finish.size.y <= 0.0:
		errs.append("course needs a finish with non-zero size")
	if not is_finite(kill_y):
		errs.append("kill_y must be a finite number")
	# Checkpoints are stored in placement order; guard against NaN corruption.
	for i in checkpoints.size():
		if not is_finite(checkpoints[i].x) or not is_finite(checkpoints[i].y):
			errs.append("checkpoint %d has a non-finite position" % i)
	return errs


## The checkpoints as an ordered list of {index, position} — the placement order
## IS the required clearing order (0,1,2,…). Used by validators/tools.
func ordered_checkpoints() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in checkpoints.size():
		out.append({"index": i, "position": checkpoints[i]})
	return out


# --- deep equality (float-tolerant) ------------------------------------------

func equals(other: CourseData) -> bool:
	if other == null:
		return false
	if name != other.name or author != other.author or created != other.created:
		return false
	if not _v2_eq(start_spawn, other.start_spawn):
		return false
	if not is_equal_approx(kill_y, other.kill_y):
		return false
	if not _rect_eq(finish, other.finish):
		return false
	if platforms.size() != other.platforms.size():
		return false
	for i in platforms.size():
		if not _rect_eq(platforms[i], other.platforms[i]):
			return false
	if hazards.size() != other.hazards.size():
		return false
	for i in hazards.size():
		if not _rect_eq(hazards[i], other.hazards[i]):
			return false
	if checkpoints.size() != other.checkpoints.size():
		return false
	for i in checkpoints.size():
		if not _v2_eq(checkpoints[i], other.checkpoints[i]):
			return false
	return true


static func _v2_eq(a: Vector2, b: Vector2) -> bool:
	return is_equal_approx(a.x, b.x) and is_equal_approx(a.y, b.y)


static func _rect_eq(a: Rect2, b: Rect2) -> bool:
	return _v2_eq(a.position, b.position) and _v2_eq(a.size, b.size)


# --- (de)serialisation: Dictionary <-> CourseData ----------------------------

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"name": name,
		"author": author,
		"created": created,
		"start_spawn": _v2_arr(start_spawn),
		"platforms": _rects_arr(platforms),
		"checkpoints": _v2s_arr(checkpoints),
		"hazards": _rects_arr(hazards),
		"finish": _rect_arr(finish),
		"kill_y": kill_y,
	}


static func from_dict(d: Dictionary) -> CourseData:
	var c := CourseData.new()
	c.name = str(d.get("name", "Untitled Course"))
	c.author = str(d.get("author", "Anonymous"))
	c.created = str(d.get("created", ""))
	c.start_spawn = _arr_v2(d.get("start_spawn", [80, 400]))
	c.kill_y = float(d.get("kill_y", 700.0))
	c.finish = _arr_rect(d.get("finish", [0, 0, 0, 0]))
	var plats: Array[Rect2] = []
	for r in _as_array(d.get("platforms", [])):
		plats.append(_arr_rect(r))
	c.platforms = plats
	var hz: Array[Rect2] = []
	for r in _as_array(d.get("hazards", [])):
		hz.append(_arr_rect(r))
	c.hazards = hz
	var cps: Array[Vector2] = []
	for v in _as_array(d.get("checkpoints", [])):
		cps.append(_arr_v2(v))
	c.checkpoints = cps
	return c


# --- (de)serialisation: JSON <-> CourseData (files + the wire) ---------------

func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


## Parse a course from a JSON string. Returns null (with push_error) on malformed
## JSON or a non-object root, so callers can fail gracefully on bad shared files.
static func from_json(text: String) -> CourseData:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("[CourseData] cannot parse course JSON (not a JSON object)")
		return null
	return from_dict(parsed as Dictionary)


# --- primitive array codecs (Vector2 -> [x,y], Rect2 -> [x,y,w,h]) -----------

static func _v2_arr(v: Vector2) -> Array:
	return [v.x, v.y]


static func _rect_arr(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


static func _v2s_arr(list: Array[Vector2]) -> Array:
	var out: Array = []
	for v in list:
		out.append(_v2_arr(v))
	return out


static func _rects_arr(list: Array[Rect2]) -> Array:
	var out: Array = []
	for r in list:
		out.append(_rect_arr(r))
	return out


static func _as_array(v: Variant) -> Array:
	return v if v is Array else []


static func _arr_v2(v: Variant) -> Vector2:
	var a := _as_array(v)
	if a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


static func _arr_rect(v: Variant) -> Rect2:
	var a := _as_array(v)
	if a.size() >= 4:
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Rect2(0, 0, 0, 0)
