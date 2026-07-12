extends Node3D
## res://scripts/enemy.gd
## Grid enemy (group "enemies"): occupies exactly one dungeon cell, steps
## toward the party on a move timer (greedy axis-priority step with a
## fallback to the other axis — pure grid queries, no physics, no nav bake),
## and melees the front row on its own attack timer once it stands in a
## cardinally-adjacent cell. Movement respects doors and secret walls
## (closed = blocked), other enemies' occupancy and the party's cell, so
## enemies pour through doors only after the party opens them. take_hit()
## is the damage contract every party attack calls; `active` gates the AI
## (probe freezes, cutscenes) while damage keeps working. The body is a
## code-built capsule — swap _build_body() when real art lands.

signal died(enemy: Node3D)
signal damaged(amount: int, cause: String)

@export var enemy_name := "Skeleton"
@export var max_health := 30
@export var damage := 8
## Seconds between grid steps toward the party.
@export var move_interval := 1.1
## Seconds between melee swings while adjacent to the party.
@export var attack_interval := 1.6
@export var body_color := Color(0.78, 0.74, 0.62)
## AI gate — inactive enemies stand still but still take damage.
@export var active := true

var health := 0
var cell := Vector2i.ZERO

var _dungeon: Node3D
var _move_clock := 0.0
var _attack_clock := 0.0
var _tween: Tween


## Called by main.gd before add_child: which dungeon, which cell.
func setup(dungeon: Node3D, start: Vector2i) -> void:
	_dungeon = dungeon
	cell = start


func _ready() -> void:
	add_to_group(&"enemies")
	health = max_health
	position = _dungeon.world_pos(cell)
	_dungeon.occupy(cell, self)
	_build_body()


func _physics_process(delta: float) -> void:
	if not active or _dungeon == null:
		return
	var party := _find_party()
	if party == null or party.is_defeated():
		return
	_move_clock += delta
	_attack_clock += delta
	var target: Vector2i = _dungeon.party_cell
	var dist := absi(target.x - cell.x) + absi(target.y - cell.y)
	if dist == 1:
		if _attack_clock >= attack_interval:
			_attack_clock = 0.0
			party.take_enemy_hit(damage, enemy_name)
	elif _move_clock >= move_interval:
		_move_clock = 0.0
		_step_toward(target)


## The damage contract: every party attack (melee and spark) lands here.
func take_hit(amount: int, cause: String) -> void:
	if health <= 0:
		return
	health -= amount
	damaged.emit(amount, cause)
	if health <= 0:
		_dungeon.vacate(cell)
		died.emit(self)
		queue_free()


## Greedy grid chase: try the axis with the larger distance first, fall back
## to the other. Blocked by walls, closed doors/secrets, other enemies and
## the party's own cell (adjacency is for attacking, not stacking).
func _step_toward(target: Vector2i) -> void:
	var delta := target - cell
	var options: Array[Vector2i] = []
	var step_x := Vector2i(signi(delta.x), 0)
	var step_y := Vector2i(0, signi(delta.y))
	if absi(delta.x) >= absi(delta.y):
		if delta.x != 0:
			options.append(step_x)
		if delta.y != 0:
			options.append(step_y)
	else:
		if delta.y != 0:
			options.append(step_y)
		if delta.x != 0:
			options.append(step_x)
	for option in options:
		var next: Vector2i = cell + option
		if not _dungeon.is_open(next):
			continue
		if _dungeon.occupant(next) != null:
			continue
		if next == _dungeon.party_cell:
			continue
		_dungeon.vacate(cell)
		cell = next
		_dungeon.occupy(cell, self)
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "position", _dungeon.world_pos(cell),
				minf(move_interval * 0.5, 0.3))
		return


func _find_party() -> Node3D:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return null
	return players[0] as Node3D


func _build_body() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.7
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	material.roughness = 0.8
	capsule.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = capsule
	mesh.position = Vector3(0.0, 0.85, 0.0)
	add_child(mesh)
