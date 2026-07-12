extends Node3D
## res://scripts/wave_director.gd
## Wave director: spawns escalating enemy waves (wave n = n+1 rushers +
## n shooters) at fixed ring points around the arena, tracks alive/kill
## counts, and arms the next wave when the arena is cleared. spawn_enemy()
## and start_next_wave() are public — the boot probe spawns its test enemies
## through the exact routine waves use, so a probe kill is a real
## director-tracked kill. first_wave_delay is kept longer than the 2s
## headless boot so probe spawns are the only enemies during validation.

signal wave_started(number: int, enemies: int)
signal enemy_killed(enemy: CharacterBody3D, kills: int)
signal wave_cleared(number: int)

const RUSHER := preload("res://scripts/rusher.gd")
const SHOOTER := preload("res://scripts/shooter.gd")

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(14.0, 0.05, 0.0), Vector3(-14.0, 0.05, 0.0),
	Vector3(0.0, 0.05, 14.0), Vector3(10.0, 0.05, -12.0),
	Vector3(-10.0, 0.05, -12.0), Vector3(14.0, 0.05, 10.0),
]

## Breather before wave 1 (> the 2s headless boot on purpose).
@export var first_wave_delay := 3.0
@export var wave_delay := 2.5

var wave := 0
var kills := 0
var alive := 0

var _countdown := 0.0
var _spawn_index := 0


func _ready() -> void:
	_countdown = first_wave_delay


func _physics_process(delta: float) -> void:
	if _countdown <= 0.0:
		return
	_countdown -= delta
	if _countdown <= 0.0:
		start_next_wave()


## Spawn the next wave immediately (also the between-waves countdown target).
func start_next_wave() -> void:
	wave += 1
	_countdown = 0.0
	var rushers := wave + 1
	var shooters := wave
	for i in rushers:
		spawn_enemy("rusher", _next_spawn_point())
	for i in shooters:
		spawn_enemy("shooter", _next_spawn_point())
	wave_started.emit(wave, rushers + shooters)


## Spawn one enemy ("rusher" or "shooter") and track it. Everything that
## enters the arena comes through here — waves, probes, scripted encounters.
func spawn_enemy(kind: String, pos: Vector3) -> CharacterBody3D:
	var enemy: CharacterBody3D = null
	match kind:
		"rusher":
			enemy = RUSHER.new()
		"shooter":
			enemy = SHOOTER.new()
	if enemy == null:
		return null
	enemy.position = pos
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	alive += 1
	return enemy


func _next_spawn_point() -> Vector3:
	var point := SPAWN_POINTS[_spawn_index % SPAWN_POINTS.size()]
	_spawn_index += 1
	return point


func _on_enemy_died(enemy: CharacterBody3D) -> void:
	alive = maxi(alive - 1, 0)
	kills += 1
	enemy_killed.emit(enemy, kills)
	if alive == 0 and wave > 0 and _countdown <= 0.0:
		wave_cleared.emit(wave)
		_countdown = wave_delay
