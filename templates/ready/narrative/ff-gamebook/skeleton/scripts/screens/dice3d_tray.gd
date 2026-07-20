class_name Dice3DTray
extends SubViewportContainer
## res://scripts/screens/dice3d_tray.gd
## The 3D physics dice tray (GDD §6.6 "the sacred dice", STYLE_GUIDE §2.2 — the one
## sound/moment nothing competes with). A RigidBody3D d6 (Jolt physics) tumbles into a
## small wooden tower-tray inside an isolated SubViewport World3D, composited over the
## 2D book by the Dice-Roll Overlay. Bone-dice body + Bog-Ink pips + warm lantern light
## per the style guide.
##
## HONEST + DETERMINISTIC + MP-SYNCABLE: the physics roll is *performance only*. The
## seeded rules core (Adventure.test_luck / test_attribute, FFCombat.attack_round) has
## ALREADY decided each die's face; this tray throws the dice for drama, waits for them
## to settle, then snap-rotates each die so the shown top face equals the predetermined
## value. Physics NEVER changes the game result — every peer sees the same authoritative
## faces regardless of the (non-deterministic) tumble.
##
##   await tray.roll([3, 4], [FFUI.PARCHMENT, FFUI.PARCHMENT])   # faces + per-die tint

# STYLE_GUIDE §1.3 palette applied to real materials
const BONE := Color("efe7d2")          # Tallow bone die body
const PIP := Color("14110d")           # Bog Ink pips
const TRAY_WOOD := Color("3a2c1c")     # dark umber tray timber
const TRAY_FELT := Color("241f19")     # tray floor
const ENEMY_BONE := Color("b9b3a0")    # a greyer bone for the foe's dice (combat)

const SETTLE_MAX := 2.2                 # s — hard cap on the physics performance
const SETTLE_VEL := 0.35                # below this (lin+ang) the die is "at rest"
const SNAP_TIME := 0.18                 # s — tween from settled pose to the true face

# Local face-normal -> pip value for a standard western d6 (opposite faces sum to 7).
# +Y=1  -Y=6   +X=2  -X=5   +Z=3  -Z=4
const FACE_DIRS := {
	1: Vector3.UP, 6: Vector3.DOWN,
	2: Vector3.RIGHT, 5: Vector3.LEFT,
	3: Vector3.BACK, 4: Vector3.FORWARD,
}

# Honest pip layout (same normalized positions as the 2D FFDie in die_face.gd) so the
# 3D dice read identically to the flat fallback. Positions are 0..1 within a face.
const PIP_LAYOUT := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.28, 0.28), Vector2(0.72, 0.72)],
	3: [Vector2(0.28, 0.28), Vector2(0.5, 0.5), Vector2(0.72, 0.72)],
	4: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
	5: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.5, 0.5), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
	6: [Vector2(0.26, 0.26), Vector2(0.74, 0.26), Vector2(0.26, 0.5), Vector2(0.74, 0.5), Vector2(0.26, 0.74), Vector2(0.74, 0.74)],
}

var _viewport: SubViewport
var _dice: Array[RigidBody3D] = []
var _built := false


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(420, 210)


func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true                       # isolated physics + render world
	_viewport.transparent_bg = true                     # composite over the 2D page
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	add_child(_viewport)

	var world := Node3D.new()
	_viewport.add_child(world)

	# --- camera: a 3/4 view above the tray (world +Y stays "up" toward the lens) ---
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 42.0
	world.add_child(cam)
	# orient AFTER entering the tree (look_at needs a global transform)
	cam.look_at_from_position(Vector3(0, 5.0, 4.2), Vector3(0, 0.2, 0), Vector3.UP)

	# --- warm lantern lighting (STYLE_GUIDE: warmth is rare, meaningful) ----------
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffd9a0")                   # Tallow Flame key
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-58, -32, 0)
	key.shadow_enabled = true
	world.add_child(key)

	var fill := OmniLight3D.new()                       # soft cool fill from the lens side
	fill.light_color = Color("aeb8b4")                  # Fen Grey fill
	fill.light_energy = 1.1
	fill.omni_range = 22.0
	fill.position = Vector3(-3.5, 5.0, 6.0)
	world.add_child(fill)

	# minimal ambient so the shaded faces don't crush to black (no WorldEnvironment
	# needed — keeps the transparent composite clean)
	var amb := OmniLight3D.new()
	amb.light_energy = 0.5
	amb.light_color = Color("6f6a5c")
	amb.omni_range = 40.0
	amb.position = Vector3(2.0, 8.0, -2.0)
	world.add_child(amb)

	_build_tray(world)


# --- the tray (tower + walls) --------------------------------------------------

func _build_tray(world: Node3D) -> void:
	var half_x := 2.9
	var half_z := 1.9
	var wall_h := 1.25

	# floor
	world.add_child(_static_box(Vector3(0, -0.25, 0), Vector3(half_x, 0.25, half_z), TRAY_FELT, 0.9))
	# four low walls (the containing tower/tray lip)
	var t := 0.28
	world.add_child(_static_box(Vector3(half_x, wall_h * 0.5, 0), Vector3(t, wall_h, half_z), TRAY_WOOD))
	world.add_child(_static_box(Vector3(-half_x, wall_h * 0.5, 0), Vector3(t, wall_h, half_z), TRAY_WOOD))
	world.add_child(_static_box(Vector3(0, wall_h * 0.5, half_z), Vector3(half_x, wall_h, t), TRAY_WOOD))
	world.add_child(_static_box(Vector3(0, wall_h * 0.5, -half_z), Vector3(half_x, wall_h, t), TRAY_WOOD))


func _static_box(pos: Vector3, half: Vector3, color: Color, rough: float = 0.8) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = half * 2.0
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	mesh.material_override = mat
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = half * 2.0
	col.shape = shape
	body.add_child(col)
	return body


# --- one d6 (box collider + a bone core + carved geometry pips) ----------------

func _make_die(tint: Color) -> RigidBody3D:
	var body := RigidBody3D.new()
	var edge := 1.25
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(edge, edge, edge)
	col.shape = box
	body.add_child(col)

	var phys := PhysicsMaterial.new()
	phys.friction = 0.7
	phys.bounce = 0.18
	body.physics_material_override = phys
	body.mass = 0.6
	body.continuous_cd = true          # a small fast die shouldn't tunnel the tray lip

	# the solid bone die body
	var core := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(edge, edge, edge)
	core.mesh = cm
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = tint
	core_mat.roughness = 0.6
	core_mat.metallic = 0.0
	core.material_override = core_mat
	body.add_child(core)

	# Bog-Ink pips as real geometry pressed into each face. A face's OUTWARD normal maps
	# to a value via FACE_DIRS, so snapping value V's normal to +Y shows V pips on top —
	# the honest pips are the same layout as the 2D FFDie (PIP_LAYOUT ↔ die_face.gd).
	var pip_mat := StandardMaterial3D.new()
	pip_mat.albedo_color = PIP
	pip_mat.roughness = 0.85
	pip_mat.metallic = 0.0
	var pip_r := edge * 0.075
	var face := edge * 0.9              # usable pip area on the face
	var surf := edge * 0.5 - pip_r * 0.35   # sink the pip slightly into the surface
	for value in FACE_DIRS.keys():
		var n: Vector3 = FACE_DIRS[value]
		# two in-plane axes for this face
		var u := n.cross(Vector3.UP)
		if u.length() < 0.01:
			u = n.cross(Vector3.RIGHT)
		u = u.normalized()
		var v := n.cross(u).normalized()
		for p: Vector2 in PIP_LAYOUT[value]:
			var pip := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = pip_r
			sm.height = pip_r * 2.0
			sm.radial_segments = 10
			sm.rings = 6
			pip.mesh = sm
			pip.material_override = pip_mat
			pip.position = n * surf + u * ((p.x - 0.5) * face) + v * ((p.y - 0.5) * face)
			pip.scale = Vector3(1, 1, 1) * 1.0
			# flatten the sphere along the face normal so it reads as a drilled pit dot
			pip.scale = Vector3.ONE - n.abs() * 0.55
			body.add_child(pip)
	return body


# --- the roll ------------------------------------------------------------------

## Throw `final_faces.size()` dice, let them tumble+settle, then snap each so its top
## face equals the authoritative value. `tints` optionally colours each die (combat:
## you vs foe). Returns when the dice are shown on their true faces.
func roll(final_faces: Array, tints: Array = []) -> void:
	_ensure_built()
	visible = true
	var n := final_faces.size()
	_spawn_dice(n, tints)

	# --- throw (drama only; the outcome is already fixed) ----------------------
	var spread := 1.2
	for i in n:
		var d := _dice[i]
		d.freeze = false
		d.sleeping = false
		var start_x := lerpf(-spread, spread, 0.0 if n <= 1 else float(i) / float(n - 1)) * (1.0 if n > 1 else 0.0)
		d.global_position = Vector3(start_x, 2.7 + randf() * 0.5, -1.1 + randf() * 0.3)
		d.global_transform.basis = _random_basis()
		d.linear_velocity = Vector3(randf_range(-1.5, 1.5), -1.0, randf_range(2.0, 3.4))
		d.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))

	# --- wait for the physics to come to rest (bounded) ------------------------
	await _await_settle()

	# --- snap to the authoritative faces (this is what keeps it honest) --------
	for i in n:
		_snap_die(_dice[i], int(final_faces[i]))
	await get_tree().create_timer(SNAP_TIME + 0.02).timeout


func _spawn_dice(n: int, tints: Array) -> void:
	# rebuild the die set to match count (cheap; happens once per roll)
	for d in _dice:
		d.queue_free()
	_dice.clear()
	var world := _viewport.get_child(0)
	for i in n:
		var tint: Color = tints[i] if i < tints.size() else BONE
		var d := _make_die(tint)
		world.add_child(d)
		_dice.append(d)


func _await_settle() -> void:
	var elapsed := 0.0
	while elapsed < SETTLE_MAX:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if elapsed < 0.4:
			continue                       # give the throw time to actually happen
		var all_rest := true
		for d in _dice:
			if d.linear_velocity.length() + d.angular_velocity.length() > SETTLE_VEL:
				all_rest = false
				break
		if all_rest:
			return


func _snap_die(d: RigidBody3D, value: int) -> void:
	# Freeze the die and tween its orientation so FACE_DIRS[value] points at world +Y,
	# with a random yaw for variety. The position is kept where physics left it.
	d.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC   # transform-driven while frozen
	d.freeze = true
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	var target := _basis_face_up(value) * Basis(Vector3.UP, randf_range(-PI, PI))
	target = target.orthonormalized()
	var from := d.global_transform.basis.orthonormalized()
	var from_q := from.get_rotation_quaternion()
	var to_q := target.get_rotation_quaternion()
	var pos := d.global_position
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var q := from_q.slerp(to_q, t)
		d.global_transform = Transform3D(Basis(q), pos),
		0.0, 1.0, SNAP_TIME)


## A basis such that (basis * FACE_DIRS[value]) == Vector3.UP — i.e. value on top.
func _basis_face_up(value: int) -> Basis:
	var n: Vector3 = FACE_DIRS[value]
	if n.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	if n.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI)
	# rotate n onto +Y
	var axis := n.cross(Vector3.UP).normalized()
	return Basis(axis, n.angle_to(Vector3.UP))


func _random_basis() -> Basis:
	return Basis.from_euler(Vector3(randf_range(0, TAU), randf_range(0, TAU), randf_range(0, TAU)))
