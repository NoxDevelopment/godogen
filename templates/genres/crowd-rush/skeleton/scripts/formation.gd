class_name Formation
extends RefCounted
## res://scripts/formation.gd
## Shared crowd-formation helpers: phyllotaxis (sunflower) disc slots and the
## capsule-unit MultiMesh both crowds render through. One MultiMesh draws
## every unit of a crowd in a single call — no per-unit nodes, no physics —
## which is what keeps 200+ units cheap. Slot 0 is the leader position; slot
## i sits at radius spacing*sqrt(i), so the disc packs evenly at any count.

const GOLDEN_ANGLE := 2.39996322972865332

const UNIT_RADIUS := 0.22
const UNIT_HEIGHT := 0.9


## Local (x, z) offset of formation slot i.
static func slot_offset(i: int, spacing: float) -> Vector2:
	if i <= 0:
		return Vector2.ZERO
	var r := spacing * sqrt(float(i))
	var a := float(i) * GOLDEN_ANGLE
	return Vector2(cos(a), sin(a)) * r


## Outer radius of an n-unit disc (engage/clash reach tests).
static func disc_radius(n: int, spacing: float) -> float:
	return spacing * sqrt(float(maxi(n, 1))) + UNIT_RADIUS + 0.1


## A MultiMeshInstance3D with `capacity` capsule-unit slots allocated and
## none visible. Callers set visible_instance_count + per-slot transforms.
static func make_unit_multimesh(capacity: int, color: Color) -> MultiMeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = UNIT_RADIUS
	mesh.height = UNIT_HEIGHT
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi
