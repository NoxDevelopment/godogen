extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager") AND the obby RUN state.
## An obby is a race through an obstacle course: hit each checkpoint in order,
## fall/hit a hazard to respawn at your last checkpoint, reach the finish for a
## time. This holds that run — checkpoint progress, deaths, finish time, and a
## persisted best time — as pure, headless-testable logic. The level scene and
## (when networked) nox_netcode's NetEvents only read + drive this.
##
## Lives in the "game_manager" + "persistent" groups and implements the
## save_data()/load_data() contract from the NoxDev template ABI, so godotsmith's
## save_system drop-in persists your best time + progress.

signal course_changed  ## checkpoint reached / death / finish (HUD listens)

# --- run state -------------------------------------------------------------
var checkpoint_count := 0        ## gates on the course (set by the level).
var current_checkpoint := -1     ## last checkpoint cleared; -1 = at the start.
var deaths := 0
var started := false
var finished := false
var elapsed := 0.0               ## live run time (local clock).
var finish_time := 0.0
var best_time := -1.0            ## < 0 = no finish yet.

# --- legacy flag store (world flags / meta-progression) --------------------
var flags: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


# =====================================================================
#  Course lifecycle
# =====================================================================

## Start (or restart) a run over a course with `count` ordered checkpoints.
## best_time is deliberately kept across restarts.
func begin_course(count: int) -> void:
	checkpoint_count = maxi(count, 0)
	current_checkpoint = -1
	deaths = 0
	started = true
	finished = false
	elapsed = 0.0
	finish_time = 0.0
	course_changed.emit()


## Advance the live clock. The level calls this each physics frame while a run
## is in progress; offline this is the authoritative timer, online NetEvents
## owns the shared clock and this just mirrors local feel.
func tick(delta: float) -> void:
	if started and not finished:
		elapsed += delta


## Clear a checkpoint. Monotonic — only the very next gate in sequence counts
## (mirrors NetEvents' host-side anti-cheat), so back-tracking or teleport-skips
## are ignored. Returns true if this was real progress.
func reach_checkpoint(checkpoint_id: int) -> bool:
	if checkpoint_id != current_checkpoint + 1:
		return false
	current_checkpoint = checkpoint_id
	course_changed.emit()
	return true


## Where a respawn drops you: the index of your last checkpoint, or -1 for the
## course start. The level maps this to a world position.
func respawn_index() -> int:
	return current_checkpoint


## You fell / hit a hazard. Counts a death; the level teleports you to
## respawn_index(). Returns the index to respawn at.
func die() -> int:
	if not finished:
		deaths += 1
		course_changed.emit()
	return current_checkpoint


## Cross the finish. Records the time and updates the best. First finish wins;
## repeated crossings are ignored until begin_course() resets the run.
func finish(time: float) -> void:
	if finished:
		return
	finished = true
	started = false
	finish_time = time
	if best_time < 0.0 or time < best_time:
		best_time = time
	set_flag("courses_finished", int(get_flag("courses_finished", 0)) + 1)
	course_changed.emit()


func is_course_complete() -> bool:
	return finished


# =====================================================================
#  Flags
# =====================================================================

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func clear_flag(flag: String) -> void:
	flags.erase(flag)


# =====================================================================
#  Persistence
# =====================================================================

func save_data() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"checkpoint_count": checkpoint_count,
		"current_checkpoint": current_checkpoint,
		"deaths": deaths,
		"started": started,
		"finished": finished,
		"elapsed": elapsed,
		"finish_time": finish_time,
		"best_time": best_time,
	}


func load_data(data: Dictionary) -> void:
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	checkpoint_count = int(data.get("checkpoint_count", 0))
	current_checkpoint = int(data.get("current_checkpoint", -1))
	deaths = int(data.get("deaths", 0))
	started = bool(data.get("started", false))
	finished = bool(data.get("finished", false))
	elapsed = float(data.get("elapsed", 0.0))
	finish_time = float(data.get("finish_time", 0.0))
	best_time = float(data.get("best_time", -1.0))
	course_changed.emit()
