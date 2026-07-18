class_name RPGJobs
extends RefCounted
## res://addons/nox_rpg/rpg_jobs.gd
## Time-gated jobs that pay gold/items + reputation on completion (Immersion-Engine
## RPG systems, spec P3). Deterministic — a tick counter drives progress, no RNG.
## One job active at a time; `tick()` advances it, `complete()` pays out when ready.
## Pure RefCounted.
##
## Job shape:
##   { "duration": 5, "pay": { "gold": 20, "items": {"leather": 1} },
##     "rep": { "smiths_guild": 5 } }

var _jobs: Dictionary = {}
var _active := ""
var _ticks := 0


func _init(jobs: Dictionary = {}) -> void:
	_jobs = jobs.duplicate(true)


func job(job_id: String) -> Dictionary:
	return _jobs.get(job_id, {})


func has_job(job_id: String) -> bool:
	return _jobs.has(job_id)


func active() -> String:
	return _active


func is_active() -> bool:
	return _active != ""


## Begin a job (replaces any in progress). { ok, reason }.
func start(job_id: String) -> Dictionary:
	if not _jobs.has(job_id):
		return { "ok": false, "reason": "unknown job '%s'" % job_id }
	_active = job_id
	_ticks = 0
	return { "ok": true, "reason": "" }


func tick(n: int = 1) -> void:
	if _active != "" and n > 0:
		_ticks += n


func progress() -> float:
	if _active == "":
		return 0.0
	var dur: int = max(1, int(job(_active).get("duration", 1)))
	return clampf(float(_ticks) / float(dur), 0.0, 1.0)


func ready() -> bool:
	return _active != "" and _ticks >= int(job(_active).get("duration", 1))


## Pay out the active job if ready: gold/items into `inv`, rep via `factions`.
## { ok, paid, job, reason }.
func complete(inv: RPGInventory, factions = null) -> Dictionary:
	if not ready():
		return { "ok": false, "paid": {}, "job": "", "reason": "not finished" }
	var j := job(_active)
	var pay: Dictionary = j.get("pay", {})
	var gold: int = int(pay.get("gold", 0))
	if gold > 0:
		inv.add("gold", gold)
	var pay_items: Dictionary = pay.get("items", {})
	for id in pay_items.keys():
		inv.add(id, int(pay_items[id]))
	if factions != null:
		var rep: Dictionary = j.get("rep", {})
		for fid in rep.keys():
			factions.adjust(fid, int(rep[fid]))
	var done := _active
	_active = ""
	_ticks = 0
	return { "ok": true, "paid": pay, "job": done, "reason": "" }
