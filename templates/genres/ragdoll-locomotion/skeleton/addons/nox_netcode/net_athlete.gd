extends Node2D
## res://addons/nox_netcode/net_athlete.gd
## Realtime profile — the RAGDOLL athlete's authority-at-spawn avatar (the
## articulated-body twin of net_player.gd / net_player_3d.gd, added additively to
## the vendored addon exactly as obby-3d-multiplayer adds net_player_3d.gd). Each
## connected peer owns exactly one instance: the OWNING peer is its multiplayer
## authority and runs its OWN RagdollEngine from local muscle input; every other
## peer receives its body POSE (the flat node-position snapshot) + progress
## through a MultiplayerSynchronizer built in code (no .tres to ship) and just
## renders it — it never sims a remote athlete.
##
## This is the exact obby net_player SEAM (authority set from the node name at
## spawn, a code-built synchronizer, owner-drives / others-render), only the
## replicated payload is an articulated pose instead of a single transform — NO
## new protocol. A ragdoll race: every peer walks its own athlete down the same
## track and sees the others' bodies stagger alongside in real time.
##
## The #1 Godot MP bug is forgetting set_multiplayer_authority() at spawn; the
## spawner names each instance after its peer id and this script reads that name
## in _ready(), so authority is never left unset.

## Fixed engine sub-steps per physics frame. Godot physics ticks at 60 Hz and the
## sim runs at 120 Hz, so 2 sub-steps keep the owner's local sim at its native
## fixed timestep (deterministic for a given input stream).
const SUBSTEPS: int = 2

## Difficulty preset the race uses (the host could broadcast this; the realtime
## default is a shared "normal" track).
@export var preset: String = "normal"

## Input actions (the four QWOP muscles). Default to the template's project map.
@export var muscle_actions: Array[StringName] = [&"muscle_q", &"muscle_w", &"muscle_o", &"muscle_p"]

## The peer id that owns this avatar (set by the spawner via the node name).
var peer_id: int = 1

## Replicated body state. The OWNER writes these from its engine each frame; every
## other peer reads them to render this athlete. `pose` is the flat
## [x0,y0,x1,y1,...] node snapshot; `dist` + `fallen` drive the remote HUD.
var pose: PackedFloat32Array = PackedFloat32Array()
var dist: float = 0.0
var fallen: bool = false
var won: bool = false

var engine: RagdollEngine
var _sync: MultiplayerSynchronizer
var _seed: int = 0


func _ready() -> void:
	# The spawner names the node after the owning peer id.
	if str(name).is_valid_int():
		peer_id = int(str(name))
	set_multiplayer_authority(peer_id)
	# A per-peer seed so each athlete's optional jitter differs but is reproducible;
	# the shared session seed (if any) folds the peer id in.
	var session_seed: int = 0
	var net := get_node_or_null("/root/Net")
	if net != null and "session_seed" in net:
		session_seed = int(net.session_seed)
	_seed = (session_seed * 2654435761 + peer_id * 40503) & 0x7FFFFFFFFFFFFFFF
	if _seed == 0:
		_seed = 20260716 + peer_id
	engine = RagdollEngine.new()
	engine.setup(_seed, {"preset": preset})
	pose = engine.pose_snapshot()
	_build_synchronizer()
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		# Remote athlete: the synchronizer is writing `pose`/`dist`/`fallen` for us;
		# push the synced pose into a local engine mirror only for the renderer.
		engine.apply_pose_snapshot(pose)
		queue_redraw()
		return

	# Owner: read local muscle input, advance the fixed-step sim, publish the pose.
	if not engine.finished:
		for i in RagdollEngine.MUSCLE_COUNT:
			engine.set_muscle(i, Input.is_action_pressed(muscle_actions[i]))
		for _s in SUBSTEPS:
			if engine.finished:
				break
			engine.step()
	pose = engine.pose_snapshot()
	dist = engine.best_distance
	fallen = engine.is_lost()
	won = engine.is_won()
	# Notify the shared NetEvents when this athlete reaches the goal (finish order).
	if won:
		var evt := get_parent().get_parent().get_node_or_null("NetEvents")
		if evt != null and evt.has_method("report_finish"):
			if not has_meta("_reported_finish"):
				set_meta("_reported_finish", true)
				evt.report_finish()
	queue_redraw()


## Build the MultiplayerSynchronizer + its SceneReplicationConfig in code so the
## avatar needs no bundled resource. The pose spawns + syncs every frame (the
## realtime channel, unreliable-ordered); progress flags sync on change.
func _build_synchronizer() -> void:
	var cfg := SceneReplicationConfig.new()

	var pose_path := NodePath(".:pose")
	cfg.add_property(pose_path)
	cfg.property_set_spawn(pose_path, true)
	cfg.property_set_replication_mode(pose_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	var dist_path := NodePath(".:dist")
	cfg.add_property(dist_path)
	cfg.property_set_replication_mode(dist_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	for prop in [NodePath(".:fallen"), NodePath(".:won")]:
		cfg.add_property(prop)
		cfg.property_set_replication_mode(prop, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	_sync = MultiplayerSynchronizer.new()
	_sync.name = "Sync"
	_sync.root_path = NodePath("..")  # the Node2D this script is on
	_sync.replication_config = cfg
	_sync.replication_interval = 0.0  # every physics frame (realtime channel)
	_sync.set_multiplayer_authority(peer_id)
	add_child(_sync)


## Draw this athlete's body from the current pose (owner: live engine; remote:
## the synced snapshot applied into the mirror engine). A distinct hue per peer.
func _draw() -> void:
	if engine == null:
		return
	var hue: float = fmod(0.11 + 0.17 * float(peer_id), 1.0)
	var limb: Color = Color.from_hsv(hue, 0.55, 0.95)
	var joint: Color = Color.from_hsv(hue, 0.35, 1.0)
	for seg in engine.bone_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var w: float = 7.0 if String(seg[2]) == "torso" else 5.0
		draw_line(a, b, limb, w)
	for i in RagdollEngine.NODE_COUNT:
		draw_circle(engine.node_position(i), 4.0, joint)
	# a head marker.
	draw_circle(engine.node_position(RagdollEngine.N_HEAD), 9.0, limb)
