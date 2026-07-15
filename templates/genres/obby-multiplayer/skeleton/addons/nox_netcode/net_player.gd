extends CharacterBody2D
## res://addons/nox_netcode/net_player.gd
## Realtime profile — an authority-at-spawn avatar (spec "Obby integration
## points"). Each connected peer owns exactly one instance: the OWNING peer is
## its multiplayer authority and drives movement from local input; every other
## peer receives its transform/state through a MultiplayerSynchronizer built in
## code (no .tres to ship) and ignores local input for it.
##
## This is the reusable, kit-agnostic avatar the future obby template drops onto
## a CharacterBody2D level. A 3D obby swaps the base to CharacterBody3D and the
## Vector2 fields to Vector3 — the authority/sync wiring is identical.
##
## The #1 Godot MP bug is forgetting set_multiplayer_authority() at spawn; the
## spawner names each instance after its peer id and this script reads that name
## in _ready(), so authority is never left unset.

## Movement (tuned for a casual platformer; the obby overrides via export).
@export var speed: float = 260.0
@export var jump_velocity: float = -430.0
@export var gravity: float = 1100.0
@export var acceleration: float = 2400.0
@export var friction: float = 2600.0

## Input actions. Default to the built-in ui_* set so a scratch platformer runs
## with zero project input config; the obby maps its own action set.
@export var left_action: StringName = &"ui_left"
@export var right_action: StringName = &"ui_right"
@export var jump_action: StringName = &"ui_accept"

## The peer id that owns this avatar (set by the spawner via the node name).
var peer_id: int = 1
## Replicated animation/facing hint (owner writes, others read + render).
var facing: int = 1
var moving: bool = false

var _sync: MultiplayerSynchronizer


func _ready() -> void:
	# The spawner names the node after the owning peer id.
	if str(name).is_valid_int():
		peer_id = int(str(name))
	set_multiplayer_authority(peer_id)
	_build_synchronizer()
	# Non-owners never sample input; they only render synced state.
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Remote avatar: the synchronizer is writing position/velocity for us.
		return

	var dir := 0.0
	if Input.is_action_pressed(right_action):
		dir += 1.0
	if Input.is_action_pressed(left_action):
		dir -= 1.0

	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * speed, acceleration * delta)
		facing = int(sign(dir))
		moving = true
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		moving = false

	if not is_on_floor():
		velocity.y += gravity * delta
	elif Input.is_action_just_pressed(jump_action):
		velocity.y = jump_velocity

	move_and_slide()


## Build the MultiplayerSynchronizer + its SceneReplicationConfig in code so the
## avatar needs no bundled resource. Position spawns + syncs continuously
## (unreliable-ordered, off the reliable command channel); facing/moving sync on
## change for cheap animation state.
func _build_synchronizer() -> void:
	var cfg := SceneReplicationConfig.new()

	var pos := NodePath(".:position")
	cfg.add_property(pos)
	cfg.property_set_spawn(pos, true)
	cfg.property_set_replication_mode(pos, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	var vel := NodePath(".:velocity")
	cfg.add_property(vel)
	cfg.property_set_replication_mode(vel, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	for prop in [NodePath(".:facing"), NodePath(".:moving")]:
		cfg.add_property(prop)
		cfg.property_set_replication_mode(prop, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	_sync = MultiplayerSynchronizer.new()
	_sync.name = "Sync"
	_sync.root_path = NodePath("..")  # the CharacterBody2D this script is on
	_sync.replication_config = cfg
	# High-rate transforms travel on the realtime channel, unreliable-ordered.
	_sync.replication_interval = 0.0  # every physics frame
	_sync.set_multiplayer_authority(peer_id)
	add_child(_sync)
