extends Node3D
## res://scripts/main.gd
## Run shell: crowd-count/distance HUD, finish + wipe handling into the run
## summary with best-survivors/best-distance flags on GameManager, and the
## boot probe proving the loop headless: gate math (+10 then x2) applied by
## real crossings, the spike strip killed individual units, an enemy-crowd
## clash resolved 1:1 with correct arithmetic, and the finish tower was
## evaluated.

var _run_over := false

@onready var _crowd: Node3D = $Crowd
@onready var _spikes: Node3D = $Spikes
@onready var _enemy: Node3D = $EnemyCrowd
@onready var _finish: Node3D = $FinishLine
@onready var _summary: CanvasLayer = $RunSummary
@onready var _count_label: Label = $HUD/Margin/Rows/CountLabel
@onready var _distance_label: Label = $HUD/Margin/Rows/DistanceLabel
@onready var _hint_label: Label = $HUD/Margin/Rows/HintLabel


func _ready() -> void:
	_crowd.count_changed.connect(_on_count_changed)
	_crowd.died.connect(_on_crowd_wiped)
	_finish.finished.connect(_on_finished)
	_hint_label.text = "A/D or mouse: steer — the crowd runs itself"
	_on_count_changed(_crowd.count)

	_emit_boot_probe.call_deferred()


func _process(_delta: float) -> void:
	if _run_over:
		return
	_distance_label.text = "Distance: %d m" % int(_crowd.distance)


func _on_count_changed(count: int) -> void:
	_count_label.text = "Crowd: %d" % count


func _on_finished(survivors: int, boss_count: int, win: bool) -> void:
	_end_run(win, survivors, boss_count)


func _on_crowd_wiped() -> void:
	_end_run(false, 0, _finish.boss_count)


func _end_run(win: bool, survivors: int, boss_count: int) -> void:
	if _run_over:
		return
	_run_over = true
	var best := maxi(int(GameManager.get_flag("best_survivors", 0)), survivors)
	GameManager.set_flag("last_run", {
		"survivors": survivors, "boss": boss_count,
		"distance": _crowd.distance, "win": win,
	})
	GameManager.set_flag("best_survivors", best)
	if _crowd.distance > float(GameManager.get_flag("best_distance", 0.0)):
		GameManager.set_flag("best_distance", _crowd.distance)
	get_tree().paused = true
	_summary.show_result(win, survivors, boss_count, _crowd.distance, best)


func _emit_boot_probe() -> void:
	for i in 2:
		await get_tree().physics_frame
	# Compress travel/reform/clash time — the mechanics are rate-independent
	# and this keeps the whole probe inside a 120-frame boot.
	_crowd.run_speed = 20.0
	_crowd.reform_speed = 60.0
	_enemy.clash_rate = 60.0
	var c0: int = _crowd.count

	# Gates: line up in the lane of the gate we want and let the real forward
	# motion + try_cross() consume it (the paired gate must stay untouched).
	var gate_add: Node3D = $Gates/GateAdd10
	_crowd.teleport_to(gate_add.global_position.x, gate_add.global_position.z + 1.5)
	var c1 := await _await_count_change(c0, 40)
	var gate_mul: Node3D = $Gates/GateTimes2
	_crowd.teleport_to(gate_mul.global_position.x, gate_mul.global_position.z + 1.5)
	var c2 := await _await_count_change(c1, 40)
	var gate_math: bool = c1 == c0 + 10 and c2 == c1 * 2

	# Spike strip: run past it down the track center — the units whose slots
	# sweep through the hazard box die individually, the rest flow on.
	_crowd.teleport_to(0.0, _spikes.global_position.z + 1.2)
	for i in 40:
		if _crowd.global_position.z < _spikes.global_position.z - 1.5:
			break
		await get_tree().physics_frame
	var obstacle_kills: int = _spikes.kills
	var c3: int = _crowd.count

	# Enemy clash: approach until the discs touch, then 1:1 annihilation —
	# the survivor count must be exactly the difference.
	var enemy_start: int = _enemy.count
	_crowd.teleport_to(0.0, _enemy.global_position.z + 8.0)
	for i in 60:
		if _enemy.count <= 0 or _crowd.count <= 0:
			break
		await get_tree().physics_frame
	var c4: int = _crowd.count
	var clash_ok: bool = _enemy.count == 0 and c4 == c3 - enemy_start

	# Finish: cross the line; the tower comparison ends the run.
	_crowd.teleport_to(0.0, _finish.global_position.z + 2.0)
	for i in 40:
		if _finish.evaluated:
			break
		await get_tree().physics_frame
	var last_run: Dictionary = GameManager.get_flag("last_run", {})
	var win: bool = bool(last_run.get("win", false))
	print("DEBUG: crowd-rush core loop ready — gates=[+10,x2] count=%d->%d->%d gate_math=%s obstacle_kills=%d clash=%d-%d->%d clash_ok=%s finish=%s survivors=%d boss=%d" % [
		c0, c1, c2, gate_math, obstacle_kills, c3, enemy_start, c4, clash_ok,
		"win" if win else "lose", c4, _finish.boss_count,
	])


func _await_count_change(from: int, max_frames: int) -> int:
	for i in max_frames:
		if _crowd.count != from:
			break
		await get_tree().physics_frame
	return _crowd.count
