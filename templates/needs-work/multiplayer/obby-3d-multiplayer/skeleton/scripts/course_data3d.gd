extends RefCounted
class_name CourseData3D
## res://scripts/course_data3d.gd
## The DATA-DRIVEN course model for the 3D obby. One CourseData3D fully describes
## an obstacle course — its box platforms, ordered checkpoint gates, hazards, a
## finish volume, the fall line, and where avatars spawn — plus authoring
## metadata (name, author, created). The SAME class is what:
##   • obby3d.gd builds a playable level from (`_build_course`),
##   • the in-game 3D designer produces (`course_editor3d.gd.build_course_data`),
##   • the library saves/loads (`course_library.gd`),
##   • share/export writes to a portable `.json`, and
##   • the online course-sync broadcasts so every peer builds the identical course.
##
## There is exactly ONE course format — editor, player, library, file and network
## all round-trip through `to_dict()` / `from_dict()` (in-memory) and
## `to_json()` / `from_json()` (files + the wire). Vector3 serialises as
## `[x, y, z]` and AABB as `[x, y, z, sx, sy, sz]` (min corner + size) so a course
## is plain, human-diffable JSON. It is course_data.gd (the 2D template) with
## Vector2→Vector3 and Rect2→AABB; the round-trip contract is identical in spirit.

## Serialised schema version — bump + migrate in `from_dict()` on a field change.
const SCHEMA_VERSION := 1

var name: String = "Untitled Course"
var author: String = "Anonymous"
var created: String = ""              ## ISO-ish timestamp (Time.get_datetime_string_from_system)
var start_spawn: Vector3 = Vector3(0.0, 1.2, 0.0)
var platforms: Array[AABB] = []       ## static floor boxes AABB(min_corner, size)
var checkpoints: Array[Vector3] = []  ## ORDERED gate positions — cleared 0,1,2,…
var hazards: Array[AABB] = []         ## kill volumes (touch → respawn)
var finish: AABB = AABB(Vector3.ZERO, Vector3.ZERO)
var kill_y: float = -8.0              ## fall below this (Y up) → respawn at last checkpoint


# --- construction helpers ----------------------------------------------------

## Fresh course stamped with now() and the given identity.
static func create(course_name: String, course_author: String = "Anonymous") -> CourseData3D:
	var c := CourseData3D.new()
	c.name = course_name
	c.author = course_author
	c.created = Time.get_datetime_string_from_system()
	return c


func duplicate_course() -> CourseData3D:
	return CourseData3D.from_dict(to_dict())


# --- validation --------------------------------------------------------------

## A course is playable when it has at least one platform, at least one ordered
## checkpoint, a finish with real volume, and a finite kill line.
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
	if finish.size.x <= 0.0 or finish.size.y <= 0.0 or finish.size.z <= 0.0:
		errs.append("course needs a finish with non-zero volume")
	if not is_finite(kill_y):
		errs.append("kill_y must be a finite number")
	# Checkpoints are stored in placement order; guard against NaN corruption.
	for i in checkpoints.size():
		var cp := checkpoints[i]
		if not is_finite(cp.x) or not is_finite(cp.y) or not is_finite(cp.z):
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

func equals(other: CourseData3D) -> bool:
	if other == null:
		return false
	if name != other.name or author != other.author or created != other.created:
		return false
	if not _v3_eq(start_spawn, other.start_spawn):
		return false
	if not is_equal_approx(kill_y, other.kill_y):
		return false
	if not _aabb_eq(finish, other.finish):
		return false
	if platforms.size() != other.platforms.size():
		return false
	for i in platforms.size():
		if not _aabb_eq(platforms[i], other.platforms[i]):
			return false
	if hazards.size() != other.hazards.size():
		return false
	for i in hazards.size():
		if not _aabb_eq(hazards[i], other.hazards[i]):
			return false
	if checkpoints.size() != other.checkpoints.size():
		return false
	for i in checkpoints.size():
		if not _v3_eq(checkpoints[i], other.checkpoints[i]):
			return false
	return true


static func _v3_eq(a: Vector3, b: Vector3) -> bool:
	return is_equal_approx(a.x, b.x) and is_equal_approx(a.y, b.y) and is_equal_approx(a.z, b.z)


static func _aabb_eq(a: AABB, b: AABB) -> bool:
	return _v3_eq(a.position, b.position) and _v3_eq(a.size, b.size)


# --- (de)serialisation: Dictionary <-> CourseData3D --------------------------

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"name": name,
		"author": author,
		"created": created,
		"start_spawn": _v3_arr(start_spawn),
		"platforms": _aabbs_arr(platforms),
		"checkpoints": _v3s_arr(checkpoints),
		"hazards": _aabbs_arr(hazards),
		"finish": _aabb_arr(finish),
		"kill_y": kill_y,
	}


static func from_dict(d: Dictionary) -> CourseData3D:
	var c := CourseData3D.new()
	c.name = str(d.get("name", "Untitled Course"))
	c.author = str(d.get("author", "Anonymous"))
	c.created = str(d.get("created", ""))
	c.start_spawn = _arr_v3(d.get("start_spawn", [0.0, 1.2, 0.0]))
	c.kill_y = float(d.get("kill_y", -8.0))
	c.finish = _arr_aabb(d.get("finish", [0, 0, 0, 0, 0, 0]))
	var plats: Array[AABB] = []
	for a in _as_array(d.get("platforms", [])):
		plats.append(_arr_aabb(a))
	c.platforms = plats
	var hz: Array[AABB] = []
	for a in _as_array(d.get("hazards", [])):
		hz.append(_arr_aabb(a))
	c.hazards = hz
	var cps: Array[Vector3] = []
	for v in _as_array(d.get("checkpoints", [])):
		cps.append(_arr_v3(v))
	c.checkpoints = cps
	return c


# --- (de)serialisation: JSON <-> CourseData3D (files + the wire) -------------

func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


## Parse a course from a JSON string. Returns null (with push_error) on malformed
## JSON or a non-object root, so callers can fail gracefully on bad shared files.
static func from_json(text: String) -> CourseData3D:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("[CourseData3D] cannot parse course JSON (not a JSON object)")
		return null
	return from_dict(parsed as Dictionary)


# --- primitive array codecs (Vector3 -> [x,y,z], AABB -> [x,y,z,sx,sy,sz]) ----

static func _v3_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _aabb_arr(a: AABB) -> Array:
	return [a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z]


static func _v3s_arr(list: Array[Vector3]) -> Array:
	var out: Array = []
	for v in list:
		out.append(_v3_arr(v))
	return out


static func _aabbs_arr(list: Array[AABB]) -> Array:
	var out: Array = []
	for a in list:
		out.append(_aabb_arr(a))
	return out


static func _as_array(v: Variant) -> Array:
	return v if v is Array else []


static func _arr_v3(v: Variant) -> Vector3:
	var a := _as_array(v)
	if a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _arr_aabb(v: Variant) -> AABB:
	var a := _as_array(v)
	if a.size() >= 6:
		return AABB(
			Vector3(float(a[0]), float(a[1]), float(a[2])),
			Vector3(float(a[3]), float(a[4]), float(a[5])),
		)
	return AABB(Vector3.ZERO, Vector3.ZERO)
