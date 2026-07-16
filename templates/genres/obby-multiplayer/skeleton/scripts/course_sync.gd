extends Node
## res://scripts/course_sync.gd
## The obby's course-sync layer — the ONE piece of game code that makes an online
## race play the HOST's chosen course on every peer. It sits on the level root as
## the fixed-name child "CourseSync" (so its RPC path is identical on all peers),
## right alongside nox_netcode's NetSpawner/NetEvents, and never touches the
## addon: it is host-authoritative in exactly the same spirit (clients REQUEST,
## the host BROADCASTS the single source of truth).
##
## Wire format is the same CourseData JSON used for files — for a built-in the
## host sends just its id (compact + guaranteed present on every client), for a
## custom/imported course it sends the full CourseData JSON so clients without the
## file still build the identical geometry. There is no separate network schema.
##
## Offline (Net.active == false) this node is completely inert: obby.gd only ever
## calls into it inside its `_net_active()` branch, so the single-player path is
## byte-identical to before.

## The host published a course (call_local → fires on the host too) OR a client
## received the host's reply. Carries the resolved CourseData to build.
signal course_ready(course: CourseData)

## The last course this node resolved (host: what it published; client: what it
## received). Null until the first publish/receive.
var active_course: CourseData = null


func _net() -> Node:
	return get_node_or_null("/root/Net")


func _active() -> bool:
	var n := _net()
	return n != null and bool(n.active)


func _is_host() -> bool:
	var n := _net()
	return n != null and n.has_method("is_host") and bool(n.is_host())


# --- host: publish the chosen course to everyone -----------------------------

## Host-only: broadcast `course` to all peers (and locally). Built-ins go by id
## for compactness; custom courses go as full JSON. No-op off a live session or
## on a client.
func publish(course: CourseData, builtin_id: String = "") -> void:
	if not _active() or not _is_host() or course == null:
		return
	if not builtin_id.is_empty():
		_sync_course.rpc("id", builtin_id)
	else:
		_sync_course.rpc("json", course.to_json())


# --- client: ask the host what course to build -------------------------------

## Client-only: request the host's active course (e.g. on a late join, before the
## host's start-of-race broadcast has been seen). Host replies point-to-point.
func request_from_host() -> void:
	if not _active() or _is_host():
		return
	_req_course.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_course() -> void:
	if not _is_host() or active_course == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	_deliver_course.rpc_id(sender, "json", active_course.to_json())


# --- the shared broadcast ----------------------------------------------------

## host -> all (call_local): resolve + adopt the course. `kind` is "id" (payload
## is a built-in listing id) or "json" (payload is CourseData JSON).
@rpc("authority", "call_local", "reliable")
func _sync_course(kind: String, payload: String) -> void:
	_adopt(kind, payload)


## host -> one client (point-to-point reply to a request). Same resolution.
@rpc("authority", "call_remote", "reliable")
func _deliver_course(kind: String, payload: String) -> void:
	_adopt(kind, payload)


func _adopt(kind: String, payload: String) -> void:
	var course := _resolve(kind, payload)
	if course == null:
		push_error("[CourseSync] could not resolve synced course (kind=%s)" % kind)
		return
	active_course = course
	course_ready.emit(course)


func _resolve(kind: String, payload: String) -> CourseData:
	if kind == "id":
		var lib := get_node_or_null("/root/CourseLibrary")
		if lib != null:
			var c: CourseData = lib.load_course(payload)
			if c != null:
				return c
		# Fall back to the built-in factory directly if the autoload is absent.
		if payload == CourseLibrary.BUILTIN_PREFIX + "sky_gauntlet":
			return CourseLibrary.sky_gauntlet()
		return CourseLibrary.starter_climb()
	return CourseData.from_json(payload)
