extends SceneTree
# scene-populate GDScript helper — data-driven set-dressing builder.
#
# Emitted (with tokens filled) by emit_scene.py as scenes/build_<name>_dress.gd,
# then run headless:  godot --headless --script scenes/build_<name>_dress.gd
#
# It reads placements.json (produced by scatter.py), PATCHES the target scene by
# adding/replacing a single "SetDressing" subtree — gameplay nodes are never
# touched — and saves the .tscn. Re-running is idempotent: the old SetDressing
# is removed and rebuilt, so re-dressing only moves what the layout changed.
#
# Rules carried verbatim from godot-task/scene-generation.md:
#   * load() not preload();  = not := for instantiate()
#   * set_owner_on_new_nodes(root, root) ONCE at the end, with a GLB-recursion
#     guard (never recurse into instanced GLB internals -> 100 MB .tscn)
#   * GLB AABB-scaling to a target footprint + base-on-ground vertical align
#   * primitive collision shapes only (never trimesh on foliage)
#   * dense species -> ONE MultiMeshInstance3D per group (thousands = 1 draw call)
#   * MANDATORY quit()
#
# When a placement's asset is "primitive:<shape>" (greybox — kit not yet
# installed) it emits a labelled coloured primitive so a scene blocks out with
# zero assets. Real runs resolve most tags to GLBs via kit_index.py.

const PLACEMENTS_PATH := "__PLACEMENTS_PATH__"   # res:// path to placements.json
const TARGET_SCENE := "__TARGET_SCENE__"         # res:// path or "NEW"
const OUTPUT_SCENE := "__OUTPUT_SCENE__"         # res:// path to save
const DIMENSION := "__DIMENSION__"               # "3d" | "2d"
const NEW_GROUND := "__NEW_GROUND__"             # JSON [xmin,zmin,xmax,zmax] or "null"

var _glb_cache := {}   # path -> PackedScene


func _initialize() -> void:
	print("[scene-populate] dressing ", TARGET_SCENE, " -> ", OUTPUT_SCENE, " (", DIMENSION, ")")

	var data := _read_json(PLACEMENTS_PATH)
	if data.is_empty():
		push_error("[scene-populate] could not read placements: " + PLACEMENTS_PATH)
		quit(1)
		return

	var root := _load_or_make_root()
	if root == null:
		push_error("[scene-populate] could not obtain a scene root")
		quit(1)
		return

	# Remove any prior dressing so this run is a clean idempotent re-dress.
	var existing := root.get_node_or_null("SetDressing")
	if existing:
		root.remove_child(existing)
		existing.free()

	var dressing: Node = Node3D.new() if DIMENSION == "3d" else Node2D.new()
	dressing.name = "SetDressing"
	if DIMENSION == "2d":
		dressing.set("y_sort_enabled", true)
	root.add_child(dressing)

	if DIMENSION == "3d":
		_maybe_add_environment(dressing, data)

	# Category container nodes keep the tree readable (Trees / Foliage / ...).
	var categories := {}
	var instances: Array = data.get("instances", [])
	var mm_groups: Array = data.get("multimesh", [])
	var ground_y: float = float(data.get("ground_y", 0.0))

	var placed := 0
	for inst in instances:
		var cat := _category_node(dressing, categories, String(inst.get("category", "props")))
		var node := _make_instance(inst, ground_y)
		if node:
			cat.add_child(node)
			placed += 1

	var mm_total := 0
	for grp in mm_groups:
		var cat := _category_node(dressing, categories, String(grp.get("category", "foliage")))
		var mmi := _make_multimesh(grp, ground_y)
		if mmi:
			cat.add_child(mmi)
			mm_total += mmi.multimesh.instance_count

	# Ownership chain — set on all NEW nodes, but never recurse into GLB internals.
	_set_owner_recursive(root, root)

	var err := _save_scene(root)
	if err != OK:
		push_error("[scene-populate] save failed: " + str(err))
		quit(1)
		return

	print("[scene-populate] placed %d instances + %d multimesh instances across %d categories"
		% [placed, mm_total, categories.size()])
	print("[scene-populate] saved ", OUTPUT_SCENE)
	quit(0)


# ---------------------------------------------------------------------------
# Root acquisition
# ---------------------------------------------------------------------------

func _load_or_make_root() -> Node:
	if TARGET_SCENE != "NEW" and ResourceLoader.exists(TARGET_SCENE):
		var packed: PackedScene = load(TARGET_SCENE)
		if packed:
			return packed.instantiate()
	# NEW scene: build a root + ground sized to the requested bounds.
	if DIMENSION == "3d":
		var root := Node3D.new()
		root.name = "Level"
		_add_ground_3d(root)
		return root
	else:
		var root := Node2D.new()
		root.name = "Level"
		return root


func _add_ground_3d(root: Node3D) -> void:
	var bounds := [-20.0, -20.0, 20.0, 20.0]
	var parsed = JSON.parse_string(NEW_GROUND)
	if parsed is Array and parsed.size() == 4:
		bounds = parsed
	var w: float = abs(bounds[2] - bounds[0])
	var d: float = abs(bounds[3] - bounds[1])
	var ground := CSGBox3D.new()
	ground.name = "Ground"
	ground.size = Vector3(max(w, 1.0), 0.5, max(d, 1.0))
	ground.position = Vector3((bounds[0] + bounds[2]) * 0.5, -0.25, (bounds[1] + bounds[3]) * 0.5)
	ground.use_collision = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.32, 0.24)
	ground.material = mat
	root.add_child(ground)


func _maybe_add_environment(dressing: Node, data: Dictionary) -> void:
	var backdrop = data.get("backdrop")
	if backdrop == null:
		return
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = env
	dressing.add_child(world_env)


# ---------------------------------------------------------------------------
# Instance construction
# ---------------------------------------------------------------------------

func _category_node(dressing: Node, categories: Dictionary, cat_id: String) -> Node:
	if categories.has(cat_id):
		return categories[cat_id]
	var node: Node = Node3D.new() if DIMENSION == "3d" else Node2D.new()
	node.name = _title(cat_id)
	dressing.add_child(node)
	categories[cat_id] = node
	return node


func _make_instance(inst: Dictionary, ground_y: float) -> Node:
	var asset := String(inst.get("asset", ""))
	var tag := String(inst.get("kit_tag", "prop"))
	var pos: Array = inst.get("pos", [0, 0, 0])
	var yaw: float = float(inst.get("yaw_deg", 0.0))
	var scl: float = float(inst.get("scale", 1.0))
	var foot: Array = inst.get("footprint", [1.0, 1.0])

	if DIMENSION == "3d":
		if asset.begins_with("primitive:"):
			return _primitive_3d(tag, asset, foot, scl, Vector3(pos[0], ground_y, pos[2]), yaw)
		return _glb_3d(asset, tag, foot, scl, Vector3(pos[0], ground_y, pos[2]), yaw)
	else:
		return _prop_2d(tag, asset, foot, scl, Vector2(pos[0], pos[1]), yaw)


func _primitive_3d(tag: String, asset: String, foot: Array, scl: float, origin: Vector3, yaw: float) -> MeshInstance3D:
	var shape := asset.substr("primitive:".length())
	var fw: float = float(foot[0]) * scl
	var fd: float = float(foot[1]) * scl
	var h: float = _height_for(tag) * scl
	var mi := MeshInstance3D.new()
	mi.name = tag
	var y_off := 0.0
	match shape:
		"box":
			var m := BoxMesh.new()
			m.size = Vector3(fw, h, fd)
			mi.mesh = m
			y_off = h * 0.5
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = fw * 0.5
			m.bottom_radius = fw * 0.5
			m.height = h
			mi.mesh = m
			y_off = h * 0.5
		"cone":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = fw * 0.5
			m.height = h
			mi.mesh = m
			y_off = h * 0.5
		"sphere":
			var m := SphereMesh.new()
			m.radius = fw * 0.5
			m.height = fw
			mi.mesh = m
			y_off = fw * 0.5
		_:
			var m := BoxMesh.new()
			m.size = Vector3(fw, h, fd)
			mi.mesh = m
			y_off = h * 0.5
	mi.material_override = _greybox_material(tag)
	mi.position = origin + Vector3(0, y_off, 0)
	mi.rotation.y = deg_to_rad(yaw)
	return mi


func _glb_3d(asset: String, tag: String, foot: Array, scl: float, origin: Vector3, yaw: float) -> Node3D:
	if asset.begins_with("unresolved:") or not ResourceLoader.exists(asset):
		# Asset not actually present — fall back to a greybox so the build never
		# dies on a missing file (kit_index recommends what to install).
		return _primitive_3d(tag, "primitive:box", foot, scl, origin, yaw)
	var packed: PackedScene = _glb_cache.get(asset, null)
	if packed == null:
		packed = load(asset)
		_glb_cache[asset] = packed
	var model = packed.instantiate()
	model.name = tag
	var mesh_inst := _find_mesh_instance(model)
	var aabb := mesh_inst.get_aabb() if mesh_inst else AABB(Vector3.ZERO, Vector3.ONE)
	var target: float = max(float(foot[0]), float(foot[1]))
	var span: float = max(aabb.size.x, aabb.size.z)
	var fit: float = (target / span) if span > 0.0001 else 1.0
	var final_scale := fit * scl
	model.scale = Vector3.ONE * final_scale
	model.position = origin + Vector3(0, -aabb.position.y * final_scale, 0)
	model.rotation.y = deg_to_rad(yaw)
	return model


func _prop_2d(tag: String, asset: String, foot: Array, scl: float, pos: Vector2, yaw: float) -> Node2D:
	# 2D set-dressing: textured Sprite2D when the asset exists, else a greybox
	# Polygon2D. (2D depth is lighter than 3D here — see SKILL.md limitations.)
	if not asset.begins_with("primitive:") and not asset.begins_with("unresolved:") and ResourceLoader.exists(asset):
		var spr := Sprite2D.new()
		spr.name = tag
		spr.texture = load(asset)
		spr.position = pos
		spr.rotation = deg_to_rad(yaw)
		spr.scale = Vector2.ONE * scl
		return spr
	var poly := Polygon2D.new()
	poly.name = tag
	var s: float = float(foot[0]) * 16.0 * scl  # px per metre approx for greybox
	poly.polygon = PackedVector2Array([
		Vector2(-s * 0.5, -s), Vector2(s * 0.5, -s), Vector2(s * 0.5, 0), Vector2(-s * 0.5, 0)])
	poly.color = _greybox_color(tag)
	poly.position = pos
	poly.rotation = deg_to_rad(yaw)
	return poly


func _make_multimesh(grp: Dictionary, ground_y: float) -> MultiMeshInstance3D:
	if DIMENSION != "3d":
		return null
	var tag := String(grp.get("group", "foliage"))
	var asset := String(grp.get("asset", ""))
	var foot: Array = grp.get("footprint", [0.4, 0.4])
	var transforms: Array = grp.get("transforms", [])
	if transforms.is_empty():
		return null

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + tag
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D

	var y_base := 0.0
	if asset.begins_with("primitive:") or asset.begins_with("unresolved:") or not ResourceLoader.exists(asset):
		var h: float = _height_for(tag)
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = float(foot[0]) * 0.5
		m.height = h
		m.material = _greybox_material(tag)
		mm.mesh = m
		y_base = h * 0.5
	else:
		var packed: PackedScene = load(asset)
		var tmp = packed.instantiate()
		var mi := _find_mesh_instance(tmp)
		if mi and mi.mesh:
			mm.mesh = mi.mesh
			var ab := mi.get_aabb()
			y_base = -ab.position.y
		tmp.free()
		if mm.mesh == null:
			var m := BoxMesh.new()
			m.size = Vector3(float(foot[0]), 0.5, float(foot[1]))
			m.material = _greybox_material(tag)
			mm.mesh = m
			y_base = 0.25

	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		var t: Array = transforms[i]
		# [x, y, z, yaw_deg, scale]
		var origin := Vector3(float(t[0]), ground_y + y_base * float(t[4]), float(t[2]))
		var basis := Basis(Vector3.UP, deg_to_rad(float(t[3]))).scaled(Vector3.ONE * float(t[4]))
		mm.set_instance_transform(i, Transform3D(basis, origin))
	mmi.multimesh = mm
	return mmi


# ---------------------------------------------------------------------------
# Greybox styling (deterministic per-tag, category-aware)
# ---------------------------------------------------------------------------

func _height_for(tag: String) -> float:
	if _has(tag, ["conifer", "broadleaf", "tree"]):
		return 3.2
	if _has(tag, ["dead"]):
		return 3.0
	if _has(tag, ["fern", "grass", "mushroom"]):
		return 0.5
	if _has(tag, ["bush"]):
		return 0.7
	if _has(tag, ["log"]):
		return 0.5
	if _has(tag, ["pillar"]):
		return 4.0
	if _has(tag, ["building"]):
		return 5.0
	if _has(tag, ["wall"]):
		return 3.0
	if _has(tag, ["cactus", "statue", "sign"]):
		return 2.2
	if _has(tag, ["shrine"]):
		return 1.8
	if _has(tag, ["lantern"]):
		return 1.6
	if _has(tag, ["well"]):
		return 1.2
	if _has(tag, ["crate", "barrel", "rock", "boulder"]):
		return 1.0
	return 1.0


func _greybox_color(tag: String) -> Color:
	var base := Color(0.6, 0.6, 0.62)
	if _has(tag, ["conifer", "tree", "fern", "grass", "bush", "cactus"]):
		base = Color(0.22, 0.55, 0.27)
	elif _has(tag, ["broadleaf"]):
		base = Color(0.28, 0.62, 0.30)
	elif _has(tag, ["dead", "log"]):
		base = Color(0.42, 0.30, 0.20)
	elif _has(tag, ["rock", "boulder", "wall", "pillar", "statue"]):
		base = Color(0.55, 0.55, 0.57)
	elif _has(tag, ["shrine", "well", "sign"]):
		base = Color(0.66, 0.60, 0.48)
	elif _has(tag, ["mushroom"]):
		base = Color(0.80, 0.30, 0.28)
	elif _has(tag, ["lantern"]):
		base = Color(0.92, 0.82, 0.35)
	elif _has(tag, ["building"]):
		base = Color(0.46, 0.48, 0.52)
	# Deterministic per-tag hue nudge so sibling tags read apart.
	var h := 0
	for i in range(tag.length()):
		h = (h * 131 + tag.unicode_at(i)) & 0xffffff
	var jitter := (float(h % 1000) / 1000.0 - 0.5) * 0.12
	return Color(clampf(base.r + jitter, 0.05, 0.95),
		clampf(base.g - jitter * 0.4, 0.05, 0.95),
		clampf(base.b + jitter * 0.4, 0.05, 0.95))


func _greybox_material(tag: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _greybox_color(tag)
	mat.roughness = 0.9
	return mat


func _has(tag: String, keys: Array) -> bool:
	for k in keys:
		if tag.find(k) != -1:
			return true
	return false


func _title(s: String) -> String:
	return s.capitalize().replace(" ", "")


# ---------------------------------------------------------------------------
# Helpers carried from scene-generation.md
# ---------------------------------------------------------------------------

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_mesh_instance(child)  # recursive — use = not :=
		if found:
			return found
	return null


func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		# Instanced scene (GLB/TSCN) — do NOT recurse (avoids 100 MB inline .tscn).
		if child.scene_file_path.is_empty():
			_set_owner_recursive(child, scene_owner)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


func _save_scene(root: Node) -> int:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return err
	return ResourceSaver.save(packed, OUTPUT_SCENE)
