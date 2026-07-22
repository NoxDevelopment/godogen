class_name Dice3DTray
extends SubViewportContainer
## res://scripts/screens/dice3d_tray.gd
## The 3D physics dice tray (GDD §6.6 "the sacred dice", STYLE_GUIDE §2.2 — the one
## sound/moment nothing competes with). Beveled bone-ivory d6 dice (Jolt physics)
## tumble into a felt-and-wood tray inside an isolated SubViewport World3D, lit by a
## warm lantern rig + a WorldEnvironment (ambient IBL, SSAO contact shadows, AgX
## tonemap, subtle glow), and composited over the 2D book by the Dice-Roll Overlay.
##
## LOOK/FEEL (DICE_3D_SPEC): real rounded-box geometry (edges catch a highlight),
## a procedural bone PBR material (albedo mottling + roughness variation + micro-grain
## normal + faint warm backlight), and INSET pips baked into a per-face texture atlas
## (albedo + normal) so each pip reads as a drilled, light-catching recess — legible
## at tray scale from any settled angle. The die sits on a textured felt floor inside a
## wood-grain tray with a soft vignette; nothing floats (SSAO + shadow-cast contact
## shadows ground every die).
##
## HONEST + DETERMINISTIC + MP-SYNCABLE (PRESERVED CONTRACT): the physics roll is
## *performance only*. The seeded rules core (Adventure.test_luck / test_attribute,
## FFCombat.attack_round) has ALREADY decided each die's face; this tray throws the
## dice for drama, waits for them to settle, then snap-rotates each die so the shown
## top face equals the predetermined value. Physics NEVER changes the game result —
## every peer sees the same authoritative faces regardless of the (non-deterministic)
## tumble. On resolve we emit `roll_broadcast` so an MP layer can mirror the roll on a
## shared dice-table via nox_netcode (see §MP hook).
##
##   await tray.roll([3, 4], [FFUI.PARCHMENT, FFUI.PARCHMENT])       # faces + per-die tint
##   await tray.roll([6], [Dice3DTray.BONE], "obsidian")            # + a Studio dice theme

# STYLE_GUIDE §1.3 palette applied to real materials
const BONE := Color("efe7d2")          # Tallow bone die body
const PIP := Color("14110d")           # Bog Ink pips
const TRAY_WOOD := Color("3a2c1c")     # dark umber tray timber
const TRAY_FELT := Color("241f19")     # tray floor
const ENEMY_BONE := Color("b9b3a0")    # a greyer bone for the foe's dice (combat)

const SETTLE_MAX := 2.2                 # s — hard cap on the physics performance
const SETTLE_VEL := 0.35                # below this (lin+ang) the die is "at rest"
const SNAP_TIME := 0.18                 # s — tween from settled pose to the true face
const READ_HOLD := 0.42                 # s — settle-and-read beat (winning-face glow pulse)

const EDGE := 1.12                      # die edge length (visual + collider)
const BEVEL := 0.11                     # rounded-edge radius as a fraction of half-edge
const ATLAS_TILE := 256                 # px per face in the baked pip atlas
const FACE_SUBDIV := 9                  # grid resolution per face (rounded-box smoothness)

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

# --- Studio-swappable dice themes (DICE_3D_SPEC §7) --------------------------------
# Mirrors the Dice So Nice! control set (dice/pip/edge colour + material + texture +
# pip-vs-numeral face). Each theme is resolved to real assets via AssetBinder STABLE
# IDs first (mesh/d6, texture/dice_body, normal/dice_body, texture/dice_felt,
# normal/dice_felt, texture/dice_tray_wood); when a slot is unfilled the tray bakes
# the look procedurally so the piece is complete out of the box AND hot-swappable from
# the Studio with zero code edits (Nox centralization pattern).
const THEMES := {
	"bone": {
		"body": Color("efe7d2"), "pip": Color("14110d"), "edge": Color("cbbf9e"),
		"rough": 0.52, "felt": Color("33402f"), "felt_rim": Color("161a12"),
		"wood": Color("3a2c1c"), "warm": 0.30, "numerals": false,
	},
	"obsidian": {
		"body": Color("20232a"), "pip": Color("d9dbe0"), "edge": Color("3a3f49"),
		"rough": 0.34, "felt": Color("241d24"), "felt_rim": Color("0e0a0e"),
		"wood": Color("2a2016"), "warm": 0.10, "numerals": false,
	},
	"ivory_numeral": {
		"body": Color("f2ecdc"), "pip": Color("2a2114"), "edge": Color("d6cbac"),
		"rough": 0.5, "felt": Color("2a2118"), "felt_rim": Color("120d09"),
		"wood": Color("3a2c1c"), "warm": 0.32, "numerals": true,
	},
}

# AssetBinder stable-ID slots the tray will honour when the Studio fills them.
const BIND_MESH := "mesh/d6"
const BIND_BODY_ALBEDO := "texture/dice_body"
const BIND_BODY_NORMAL := "normal/dice_body"
const BIND_FELT := "texture/dice_felt"
const BIND_FELT_NORMAL := "normal/dice_felt"
const BIND_WOOD := "texture/dice_tray_wood"

# Baked-once, shared across dice/instances (keyed by theme id). Regenerating the atlas
# is the only heavy step, so it is cached process-wide.
static var _atlas_cache: Dictionary = {}   # theme_id -> {albedo, normal, rough}
static var _mesh_cache: Dictionary = {}     # theme_id -> ArrayMesh (rounded box + UVs)

## Emitted the instant the authoritative faces are resolved+shown. An MP layer mirrors
## the roll onto a shared dice-table by re-broadcasting (seed +) these faces through
## nox_netcode (net_events); every peer runs its own physics theatre yet shows the same
## faces. Single-player simply ignores it.  (DICE_3D_SPEC §8 — hook, not full build.)
signal roll_broadcast(final_faces: Array, tints: Array)

var _viewport: SubViewport
var _world: Node3D
var _cam: Camera3D
var _tray_root: Node3D
var _dice: Array[RigidBody3D] = []
var _built := false
var _theme_id := "bone"

# Tray geometry (members so the roll/snap can spread + seat dice against the real felt
# bounds). A wider, shallower-lipped tray than before: the dice sit CENTRED on the green
# felt with only a thin sliver of wood rim in frame (DICE_3D_SPEC §3/§5).
const TRAY_HALF_X := 2.9                 # felt half-width  (wide enough for 4 combat dice)
const TRAY_HALF_Z := 1.7                 # felt half-depth
const TRAY_WALL_T := 0.26                # wood rim thickness
const TRAY_WALL_H := 0.62                # thin wood lip (was 0.95 — the lip ate the frame)
const FELT_TOP_Y := 0.0                  # world Y of the felt surface (die rest plane)


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(460, 300)


func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true                       # isolated physics + render world
	_viewport.transparent_bg = true                     # composite over the 2D page
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_viewport.handle_input_locally = false
	add_child(_viewport)

	_world = Node3D.new()
	_viewport.add_child(_world)

	_add_environment(_world)
	_add_camera(_world)
	_add_lights(_world)
	_build_tray(_world)


# --- environment: warm ambient IBL + SSAO contact shadows + AgX + glow --------------
# (DICE_3D_SPEC §4.) Transparent background is preserved so the tray still composites
# over the 2D page — the environment supplies ambient/SSAO/tonemap without drawing a sky.

func _add_environment(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)            # keep the composite transparent
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6a5f4a")          # low warm ambient (no crushed blacks)
	env.ambient_light_energy = 0.6
	env.ssao_enabled = true                             # soft contact shadows / crease AO
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.glow_enabled = true                             # gentle sheen on bone highlights
	env.glow_intensity = 0.22
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)


func _add_camera(world: Node3D) -> void:
	# 3/4 top-down — the readable angle. Framed tight so a settled die reads instantly
	# and two dice (combat / STAMINA) both fit and both read (DICE_3D_SPEC §5).
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	world.add_child(_cam)
	_frame_camera(2)


## Reframe the 3/4 camera for `n` dice. A steep look-down that clears the (now thin) near
## wood lip so the dice sit CENTRED on the green felt — only a sliver of rim shows — with
## the TOP faces dominant and the bevels still reading "3D die on a table". The multi-die
## case (combat 3-4 dice) pulls the camera up + back and widens the FOV so all dice land
## separated and fully in frame (nit #2). Camera-only: it never touches the faces.
func _frame_camera(n: int) -> void:
	if _cam == null:
		return
	var wide := n >= 3
	# Steep top-down held high, but a tight (telephoto) FOV zooms IN so the green felt
	# fills the frame with the dice as the dominant subject — only a thin sliver of the
	# near wood lip shows. The multi-die case opens the FOV a little + lifts the camera so
	# all 3-4 spread dice stay fully in frame (nit #1/#2). Camera-only; faces untouched.
	_cam.fov = 31.0 if wide else 27.0
	var cam_y := 7.4 if wide else 6.4
	var cam_z := 2.95 if wide else 2.4
	# aim at the settled dice (centre of the felt, at die-centre height) so they sit
	# vertically centred rather than pushed to the back of the tray
	_cam.look_at_from_position(Vector3(0.0, cam_y, cam_z), Vector3(0.0, 0.18, 0.0), Vector3.UP)


func _add_lights(world: Node3D) -> void:
	# Warm key with shadows (the grounding + edge-catch light); cool fill opens the
	# shadow side. Ambient now comes from the environment, not a hacky omni.
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffd9a0")                   # Tallow Flame key
	key.light_energy = 2.1
	key.rotation_degrees = Vector3(-56, -34, 0)
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.shadow_bias = 0.03
	key.shadow_normal_bias = 1.2
	world.add_child(key)

	var fill := OmniLight3D.new()                       # soft cool fill from the lens side
	fill.light_color = Color("b3bdb8")                  # Fen Grey fill
	fill.light_energy = 0.9
	fill.omni_range = 20.0
	fill.omni_attenuation = 1.4
	fill.position = Vector3(-3.2, 4.4, 5.2)
	world.add_child(fill)

	var rim := OmniLight3D.new()                        # low warm rim behind for bone glow
	rim.light_color = Color("c88a3e")
	rim.light_energy = 0.5
	rim.omni_range = 16.0
	rim.position = Vector3(2.2, 2.6, -3.0)
	world.add_child(rim)


# --- the tray: felt floor + wood-grain lip + vignette (DICE_3D_SPEC §3) --------------

func _build_tray(world: Node3D) -> void:
	var theme: Dictionary = _theme()
	_tray_root = Node3D.new()
	world.add_child(_tray_root)

	var half_x := TRAY_HALF_X
	var half_z := TRAY_HALF_Z
	var wall_h := TRAY_WALL_H
	var t := TRAY_WALL_T

	# --- felt floor (collider + textured plane) ---
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.06, 0)
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(half_x * 2.0, 0.12, half_z * 2.0)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half_x * 2.0, half_z * 2.0)
	floor_mesh.mesh = pm
	floor_mesh.position = Vector3(0, 0.06, 0)
	floor_mesh.material_override = _felt_material(theme)
	floor_body.add_child(floor_mesh)
	_tray_root.add_child(floor_body)

	# --- soft vignette quad just above the felt, focusing the eye on the dice ---
	var vig := MeshInstance3D.new()
	var vpm := PlaneMesh.new()
	vpm.size = Vector2(half_x * 2.0, half_z * 2.0)
	vig.mesh = vpm
	vig.position = Vector3(0, 0.10, 0)
	vig.material_override = _vignette_material(theme)
	_tray_root.add_child(vig)

	# --- four wood-grain walls (the containing tray lip) ---
	var wood := _wood_material(theme)
	_tray_root.add_child(_wall(Vector3(half_x, wall_h * 0.5, 0), Vector3(t, wall_h, half_z + t), wood))
	_tray_root.add_child(_wall(Vector3(-half_x, wall_h * 0.5, 0), Vector3(t, wall_h, half_z + t), wood))
	_tray_root.add_child(_wall(Vector3(0, wall_h * 0.5, half_z), Vector3(half_x, wall_h, t), wood))
	_tray_root.add_child(_wall(Vector3(0, wall_h * 0.5, -half_z), Vector3(half_x, wall_h, t), wood))


func _wall(pos: Vector3, half: Vector3, mat: Material) -> StaticBody3D:
	# The VISIBLE wood lip is short (thin sliver in frame), but the retaining COLLIDER
	# extends invisibly higher so a tumbling die can never hop the low rim and escape /
	# clip the frame — the lip you see is cosmetic, containment stays honest.
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = half * 2.0
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var col_h := 1.9                                     # tall invisible retaining wall
	shape.size = Vector3(half.x * 2.0, col_h, half.z * 2.0)
	# recentre the collider so its base still sits on the felt floor
	col.position = Vector3(0, col_h * 0.5 - half.y, 0)
	col.shape = shape
	body.add_child(col)
	return body


# --- one d6: rounded-box mesh + bone PBR + baked inset-pip atlas ---------------------

func _make_die(tint: Color) -> RigidBody3D:
	var body := RigidBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(EDGE, EDGE, EDGE)               # collider stays a cheap cube
	col.shape = box
	body.add_child(col)

	var phys := PhysicsMaterial.new()
	phys.friction = 0.75
	phys.bounce = 0.16
	body.physics_material_override = phys
	body.mass = 0.6
	body.continuous_cd = true          # a small fast die shouldn't tunnel the tray lip

	var core := MeshInstance3D.new()
	core.mesh = _die_mesh()                            # rounded box, per-face atlas UVs
	core.material_override = _body_material(tint)      # per-die material (tint + glow anim)
	body.add_child(core)
	return body


## The bone PBR material: baked albedo (mottled bone + inset pips) + micro-grain normal
## + roughness variation + a faint warm backlight so the bone glows like ivory. Prefers
## a Studio-bound texture set, falls back to the procedural bake. `tint` shifts bone vs
## enemy-grey (combat) on top of the baked look.
func _body_material(tint: Color) -> StandardMaterial3D:
	var theme: Dictionary = _theme()
	var atlas: Dictionary = _atlas()
	var m := StandardMaterial3D.new()
	m.albedo_texture = _bound_tex(BIND_BODY_ALBEDO, atlas.albedo)
	m.albedo_color = tint
	m.metallic = 0.0
	m.roughness = 1.0
	m.roughness_texture = atlas.rough
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.normal_enabled = true
	m.normal_texture = _bound_tex(BIND_BODY_NORMAL, atlas.normal)
	m.normal_scale = 1.0
	# the rounded-box faces are built per-face (shared edge verts); render both sides so a
	# face is never culled to a hole regardless of grid winding — negligible on a convex die.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# faint warm subsurface/backlight — real bone/ivory glows a little (STYLE_GUIDE:
	# warmth is rare, meaningful — the sacred dice earn it).
	var warm: float = float(theme.warm)
	if warm > 0.0:
		m.backlight_enabled = true
		m.backlight = Color("6e4a24") * warm
		m.rim_enabled = true
		m.rim = 0.35 * warm
		m.rim_tint = 0.6
	return m


func _die_mesh() -> ArrayMesh:
	if _mesh_cache.has(_theme_id):
		return _mesh_cache[_theme_id]
	# Prefer a Studio-bound d6 model if present (still honest — snap uses FACE_DIRS).
	var bound := AssetBinder.get_slot(BIND_MESH) if AssetBinder != null else {}
	var mesh: ArrayMesh
	if bound is Dictionary and bound.has("file") and bound.get("file") != null \
			and ResourceLoader.exists(str(bound.get("file"))):
		var res: Resource = load(str(bound.get("file")))
		if res is ArrayMesh:
			mesh = res
	if mesh == null:
		mesh = _build_rounded_die_mesh()
	_mesh_cache[_theme_id] = mesh
	return mesh


## A chamfered/rounded d6 built as an ArrayMesh: six subdivided face grids projected
## onto a rounded-box surface (edges + corners rounded by BEVEL), with smooth analytic
## normals so the bevels catch a highlight, and per-face UVs into the pip atlas so the
## face whose outward normal is FACE_DIRS[v] shows the value-v tile (honest mapping).
func _build_rounded_die_mesh() -> ArrayMesh:
	var h := EDGE * 0.5
	var r := h * BEVEL                                  # corner/edge radius
	var inner := h - r
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := FACE_SUBDIV

	for value in FACE_DIRS.keys():
		var fn: Vector3 = FACE_DIRS[value]
		# in-plane axes with u x v == fn (outward winding)
		var u_axis := fn.cross(Vector3.UP)
		if u_axis.length() < 0.01:
			u_axis = fn.cross(Vector3.RIGHT)
		u_axis = u_axis.normalized()
		var v_axis := fn.cross(u_axis).normalized()
		# atlas tile for this value
		var v_int := int(value)
		var col: int = (v_int - 1) % 3
		var row: int = (v_int - 1) / 3
		var base_i := verts.size()
		for j in n + 1:
			for i in n + 1:
				var s := lerpf(-1.0, 1.0, float(i) / float(n))
				var tv := lerpf(-1.0, 1.0, float(j) / float(n))
				# point on the un-rounded cube face
				var p: Vector3 = fn * h + u_axis * (s * h) + v_axis * (tv * h)
				# project onto the rounded-box surface
				var q := Vector3(
					clampf(p.x, -inner, inner),
					clampf(p.y, -inner, inner),
					clampf(p.z, -inner, inner))
				var d := p - q
				var nrm := d.normalized()
				var surf := q + nrm * r
				verts.push_back(surf)
				norms.push_back(nrm)
				# UV into the face's atlas tile (pips drawn within the flat centre)
				var fu := (s * 0.5 + 0.5)
				var fv := (tv * 0.5 + 0.5)
				uvs.push_back(Vector2((col + fu) / 3.0, (row + fv) / 2.0))
		# triangles (CCW from outside — u x v == fn)
		for j in n:
			for i in n:
				var a := base_i + j * (n + 1) + i
				var b := a + 1
				var c := a + (n + 1)
				var e := c + 1
				idx.push_back(a); idx.push_back(b); idx.push_back(e)
				idx.push_back(a); idx.push_back(e); idx.push_back(c)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# --- procedural texture bakes -------------------------------------------------------

func _atlas() -> Dictionary:
	if _atlas_cache.has(_theme_id):
		return _atlas_cache[_theme_id]
	var out := _bake_atlas(_theme())
	_atlas_cache[_theme_id] = out
	return out


## Bake the 3x2 face atlas: bone albedo (mottled) with inset pips (dark, AO-ringed,
## rim-highlit), a matching normal map where each pip is a concave spherical dent, and a
## roughness map (bone base + rougher inked pits). Pip layout matches PIP_LAYOUT / the
## 2D FFDie so 3D and 2D read identically. Numeral themes stamp engraved digits instead.
func _bake_atlas(theme: Dictionary) -> Dictionary:
	var ts := ATLAS_TILE
	var w := ts * 3
	var h := ts * 2
	var albedo := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var normal := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rough := Image.create(w, h, false, Image.FORMAT_RGBA8)

	var mottle := FastNoiseLite.new()
	mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mottle.frequency = 0.02
	mottle.seed = 1337
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.14
	grain.seed = 91
	var flat_n := Color(0.5, 0.5, 1.0, 1.0)

	var body: Color = theme.body
	var pip_col: Color = theme.pip
	var base_rough: float = theme.rough
	var numerals: bool = theme.numerals
	var pip_r := ts * 0.088

	for value in range(1, 7):
		var col: int = (value - 1) % 3
		var row: int = (value - 1) / 3
		var ox := col * ts
		var oy := row * ts
		var glyph := _numeral_bitmap(value) if numerals else PackedInt32Array()
		for py in ts:
			for px in ts:
				var gx := ox + px
				var gy := oy + py
				var fx := float(px) / float(ts)
				var fy := float(py) / float(ts)
				# --- bone body defaults ---
				var mv := mottle.get_noise_2d(gx, gy) * 0.5 + 0.5   # 0..1
				var gv := grain.get_noise_2d(gx * 2.0, gy * 2.0)     # -1..1
				var a := body * (0.9 + mv * 0.2)
				a.a = 1.0
				var rgh := clampf(base_rough + gv * 0.14, 0.05, 1.0)
				# micro-grain normal (cheap: tilt by local grain value)
				var nx := clampf(0.5 + gv * 0.05, 0.0, 1.0)
				var ny := clampf(0.5 + grain.get_noise_2d(gy * 2.0, gx * 2.0) * 0.05, 0.0, 1.0)
				var nrm := Color(nx, ny, 1.0, 1.0)

				# --- pip / numeral carving (inset, light-catching) ---
				var carve := 0.0                                   # 0..1 pit depth at this px
				var pit_dir := Vector2.ZERO
				if numerals:
					if _in_numeral(glyph, fx, fy):
						carve = 1.0
				else:
					for p: Vector2 in PIP_LAYOUT[value]:
						var cpx := p.x * ts
						var cpy := p.y * ts
						var dd := Vector2(px - cpx, py - cpy)
						var dist := dd.length()
						if dist < pip_r:
							var tnorm := dist / pip_r               # 0 centre .. 1 rim
							carve = maxf(carve, 1.0)
							pit_dir = dd.normalized() if dist > 0.5 else Vector2.ZERO
							# concave dent normal: walls tilt toward the pit centre
							var slope := tnorm * 1.6
							var pnx := -pit_dir.x * slope
							var pny := -pit_dir.y * slope
							var pnz := 1.0
							var pl := sqrt(pnx * pnx + pny * pny + pnz * pnz)
							nrm = Color(pnx / pl * 0.5 + 0.5, pny / pl * 0.5 + 0.5, pnz / pl * 0.5 + 0.5, 1.0)
							# darker toward the rim (baked AO), inked centre
							var rim_ao := lerpf(0.72, 1.0, tnorm)
							a = pip_col * rim_ao
							a.a = 1.0
							rgh = clampf(base_rough + 0.22, 0.05, 1.0)
							break
				if numerals and carve > 0.0:
					a = pip_col
					a.a = 1.0
					rgh = clampf(base_rough + 0.2, 0.05, 1.0)
					nrm = Color(0.5, 0.5, 1.0, 1.0)

				albedo.set_pixel(gx, gy, a)
				normal.set_pixel(gx, gy, nrm)
				rough.set_pixel(gx, gy, Color(rgh, rgh, rgh, 1.0))

	albedo.generate_mipmaps()
	rough.generate_mipmaps()
	normal.generate_mipmaps()
	return {
		"albedo": ImageTexture.create_from_image(albedo),
		"normal": ImageTexture.create_from_image(normal),
		"rough": ImageTexture.create_from_image(rough),
	}


func _felt_material(theme: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var felt: Color = theme.felt
	var rim: Color = theme.felt_rim
	var bound_albedo := _bound_tex(BIND_FELT, null)
	if bound_albedo != null:
		m.albedo_texture = bound_albedo
	else:
		m.albedo_texture = _bake_felt_albedo(felt, rim)
	m.albedo_color = Color.WHITE
	m.metallic = 0.0
	m.roughness = 0.96
	m.normal_enabled = true
	m.normal_texture = _bound_tex(BIND_FELT_NORMAL, _bake_felt_normal())
	m.normal_scale = 0.7
	m.uv1_scale = Vector3(3.0, 3.0, 3.0)               # tile the weave across the floor
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _bake_felt_albedo(felt: Color, _rim: Color) -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var fib := FastNoiseLite.new()
	fib.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fib.frequency = 0.5
	fib.seed = 7
	for y in s:
		for x in s:
			# fine woven fibre: two crossing high-freq bands + noise fleck
			var weave := 0.5 + 0.5 * sin(float(x) * 0.9) * 0.12 + 0.5 * sin(float(y) * 0.9) * 0.12
			var fl := fib.get_noise_2d(x, y) * 0.10
			var c := felt * (0.85 + weave * 0.12 + fl)
			c.a = 1.0
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _bake_felt_normal() -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			# crossing fibre ridges → a cloth micro-normal
			var dx := cos(float(x) * 0.9) * 0.16 + cos(float(y) * 0.45) * 0.05
			var dy := cos(float(y) * 0.9) * 0.16 + cos(float(x) * 0.45) * 0.05
			var nz := 1.0
			var l := sqrt(dx * dx + dy * dy + nz * nz)
			img.set_pixel(x, y, Color(dx / l * 0.5 + 0.5, dy / l * 0.5 + 0.5, nz / l * 0.5 + 0.5, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _vignette_material(theme: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _bake_vignette(theme.felt_rim)
	m.albedo_color = Color.WHITE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return m


func _bake_vignette(rim: Color) -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var cx := s * 0.5
	var cy := s * 0.5
	var maxd := cx * 1.15
	for y in s:
		for x in s:
			var d := Vector2(x - cx, y - cy).length() / maxd
			var alpha := clampf((d - 0.45) / 0.55, 0.0, 1.0)
			alpha = alpha * alpha * 0.55                # darken toward the rim only
			img.set_pixel(x, y, Color(rim.r, rim.g, rim.b, alpha))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _wood_material(theme: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var bound := _bound_tex(BIND_WOOD, null)
	if bound != null:
		m.albedo_texture = bound
	else:
		m.albedo_texture = _bake_wood(theme.wood)
	m.albedo_color = Color.WHITE
	m.metallic = 0.0
	m.roughness = 0.62
	m.uv1_scale = Vector3(2.0, 1.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _bake_wood(wood: Color) -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var wn := FastNoiseLite.new()
	wn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	wn.frequency = 0.03
	wn.seed = 42
	for y in s:
		for x in s:
			# stretched grain: rings along X warped by noise
			var warp := wn.get_noise_2d(x, y) * 8.0
			var ring := 0.5 + 0.5 * sin((float(x) + warp) * 0.4)
			var streak := wn.get_noise_2d(x * 0.5, y * 4.0) * 0.08
			var c := wood * (0.78 + ring * 0.22 + streak)
			c.a = 1.0
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- theme / binding helpers --------------------------------------------------------

func _theme() -> Dictionary:
	return THEMES.get(_theme_id, THEMES["bone"])


## AssetBinder texture by stable ID, or the procedural fallback when the slot is unfilled.
func _bound_tex(slot_id: String, fallback: Texture2D) -> Texture2D:
	if AssetBinder != null and AssetBinder.has_slot(slot_id):
		var t := AssetBinder.get_texture(slot_id)
		if t != null:
			return t
	return fallback


func _apply_theme(theme_id: String) -> void:
	if theme_id == "" or theme_id == _theme_id:
		return
	if not THEMES.has(theme_id):
		push_warning("Dice3DTray: unknown dice theme '%s' — keeping '%s'" % [theme_id, _theme_id])
		return
	_theme_id = theme_id
	if _built and _tray_root != null:
		_tray_root.queue_free()
		_build_tray(_world)


# --- the roll (honest contract PRESERVED) -------------------------------------------

## Throw `final_faces.size()` dice, let them tumble+settle, then snap each so its top
## face equals the authoritative value. `tints` optionally colours each die (combat:
## you vs foe). `theme_id` optionally swaps the whole dice look (Studio themes). Returns
## when the dice are shown on their true faces. THE SEEDED CORE DECIDES THE FACES — this
## only performs and reveals them; physics never changes the result.
func roll(final_faces: Array, tints: Array = [], theme_id: String = "") -> void:
	_apply_theme(theme_id)
	_ensure_built()
	_frame_camera(final_faces.size())                  # widen framing for the 3-4 die case
	visible = true
	var n := final_faces.size()
	_spawn_dice(n, tints)

	# --- throw (drama only; the outcome is already fixed) ----------------------
	# Lay the dice out on a centred, well-separated grid and toss them gently downward
	# with a little scatter so they tumble but settle spread across the framed felt —
	# never overlapping, never into a wall, never out of frame (DICE_3D_SPEC §5/§10).
	# 1-3 dice → one centred row; 4 dice (combat) → a 2x2 block so all four read.
	var cols: int = n if n <= 3 else int(ceil(n / 2.0))
	var rows: int = int(ceil(float(n) / float(cols)))
	var sx := 1.72                                      # column pitch (> die edge 1.12)
	var sz := 1.52                                      # row pitch
	for i in n:
		var d := _dice[i]
		d.freeze = false
		d.sleeping = false
		var cx := i % cols
		var cz := i / cols
		var gx := (float(cx) - float(cols - 1) * 0.5) * sx
		var gz := (float(cz) - float(rows - 1) * 0.5) * sz
		# tiny per-die jitter so it isn't a rigid stamp, but far too small to overlap
		d.global_position = Vector3(gx + randf_range(-0.08, 0.08), 1.4 + randf() * 0.12,
			gz + randf_range(-0.08, 0.08))
		d.global_transform.basis = _random_basis()
		# gentle toss: mostly a drop with a little tumble, so each die settles near its
		# spawn cell (spread + readable) instead of rolling into a central pile / a wall.
		d.linear_velocity = Vector3(randf_range(-0.25, 0.25), -1.4, randf_range(-0.25, 0.25))
		d.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))

	# --- wait for the physics to come to rest (bounded) ------------------------
	await _await_settle()

	# --- snap to the authoritative faces (this is what keeps it honest) --------
	for i in n:
		_snap_die(_dice[i], int(final_faces[i]))
	await get_tree().create_timer(SNAP_TIME + 0.02).timeout

	# --- settle-and-read beat: a brief warm glow pulse on the landed dice ------
	roll_broadcast.emit(final_faces, tints)            # MP hook (see header §MP)
	await _read_pulse()


func _spawn_dice(n: int, tints: Array) -> void:
	# rebuild the die set to match count (cheap; happens once per roll)
	for d in _dice:
		d.queue_free()
	_dice.clear()
	for i in n:
		var tint: Color = tints[i] if i < tints.size() else _theme().body
		var d := _make_die(tint)
		_world.add_child(d)
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
	# yaw MUST be applied in world space (about world +Y) AFTER the face-up alignment,
	# else it rotates the target face off the top for side-values (2/3/4/5) — breaking
	# the honest "shown top face == seeded value" contract. (world_yaw * face_up)
	var target := Basis(Vector3.UP, randf_range(-PI, PI)) * _basis_face_up(value)
	target = target.orthonormalized()
	var from := d.global_transform.basis.orthonormalized()
	var from_q := from.get_rotation_quaternion()
	var to_q := target.get_rotation_quaternion()
	# Seat the die FLUSH on the felt: pin its centre to the exact rest height (a flat face
	# down at y=FELT_TOP_Y) and clamp X/Z inside the felt so a die that settled leaning on
	# / climbing a wall is pulled down flat and fully onto the felt — never left tilted or
	# hovering (nit #3). Only the resting POSE is corrected; the shown face is untouched.
	var pos := d.global_position
	var lim_x := TRAY_HALF_X - TRAY_WALL_T - EDGE * 0.5 - 0.03
	var lim_z := TRAY_HALF_Z - TRAY_WALL_T - EDGE * 0.5 - 0.03
	pos.x = clampf(pos.x, -lim_x, lim_x)
	pos.z = clampf(pos.z, -lim_z, lim_z)
	pos.y = FELT_TOP_Y + EDGE * 0.5                     # flat face flush on the felt
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var q := from_q.slerp(to_q, t)
		d.global_transform = Transform3D(Basis(q), pos),
		0.0, 1.0, SNAP_TIME)


## The read moment (DICE_3D_SPEC §6): a short warm emission pulse on the settled dice so
## the eye lands on the result, then hold. Look/feel only — the faces are already fixed.
func _read_pulse() -> void:
	var mats: Array[StandardMaterial3D] = []
	for d in _dice:
		var mi := d.get_child(1) as MeshInstance3D    # child 0 = collider, child 1 = mesh
		if mi != null and mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = mi.material_override
			m.emission_enabled = true
			m.emission = Color("ffcf8a")
			m.emission_energy_multiplier = 0.0
			mats.append(m)
	var tw := create_tween()
	tw.tween_method(func(e: float) -> void:
		for m in mats:
			m.emission_energy_multiplier = e,
		0.0, 0.55, READ_HOLD * 0.5)
	tw.tween_method(func(e: float) -> void:
		for m in mats:
			m.emission_energy_multiplier = e,
		0.55, 0.10, READ_HOLD * 0.5)
	await tw.finished


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


# --- numeral face support (themed dice; DICE_3D_SPEC §2 "numerals option") -----------
# Compact 5x7 glyphs for 1..6, packed row-major as 35 ints (1 = inked). Rendered as an
# engraved digit instead of pips when a theme sets numerals=true.
const _NUMERAL_GLYPHS := {
	1: [0,0,1,0,0, 0,1,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,1,1,1,0],
	2: [0,1,1,1,0, 1,0,0,0,1, 0,0,0,0,1, 0,0,1,1,0, 0,1,0,0,0, 1,0,0,0,0, 1,1,1,1,1],
	3: [1,1,1,1,1, 0,0,0,0,1, 0,0,0,1,0, 0,0,1,1,0, 0,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0],
	4: [0,0,0,1,0, 0,0,1,1,0, 0,1,0,1,0, 1,0,0,1,0, 1,1,1,1,1, 0,0,0,1,0, 0,0,0,1,0],
	5: [1,1,1,1,1, 1,0,0,0,0, 1,1,1,1,0, 0,0,0,0,1, 0,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0],
	6: [0,0,1,1,0, 0,1,0,0,0, 1,0,0,0,0, 1,1,1,1,0, 1,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0],
}


func _numeral_bitmap(value: int) -> PackedInt32Array:
	var g: Array = _NUMERAL_GLYPHS.get(value, _NUMERAL_GLYPHS[1])
	var out := PackedInt32Array()
	for v: int in g:
		out.push_back(v)
	return out


## Is normalized face coord (fx,fy) inside the inked part of the 5x7 glyph, centred and
## scaled to ~52% of the face?
func _in_numeral(glyph: PackedInt32Array, fx: float, fy: float) -> bool:
	if glyph.is_empty():
		return false
	var span := 0.52
	var gx := (fx - 0.5) / span + 0.5
	var gy := (fy - 0.5) / span + 0.5
	if gx < 0.0 or gx >= 1.0 or gy < 0.0 or gy >= 1.0:
		return false
	var cx := int(gx * 5.0)
	var cy := int(gy * 7.0)
	return glyph[clampi(cy, 0, 6) * 5 + clampi(cx, 0, 4)] == 1
