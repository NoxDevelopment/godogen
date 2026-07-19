extends RefCounted
class_name RagdollEngine
## res://scripts/ragdoll_engine.gd
## The PURE, seedable, headless-testable engine for a QWOP-lineage RAGDOLL
## LOCOMOTION game: actuate an athlete's individual muscles (four muscle groups
## mapped to Q / W / O / P) to stagger an articulated body forward as far as
## possible before it topples. There is NO Godot-node dependency and NO
## RigidBody2D in here: the whole articulated-body physics is our OWN fixed-
## timestep 2D sim, so a run replays BYTE-IDENTICALLY from a seed + an input
## sequence and drives headlessly with no UI at all.
##
## WHY CUSTOM PHYSICS (the key design decision — same lineage as the
## spinning-top-battler + peg-roguelike templates):
##   Godot's RigidBody2D / PhysicsServer2D solver is NOT guaranteed identical
##   across runs / builds / platforms, which would break byte-identical replays
##   and the determinism probe. So the athlete is a set of POINT MASSES (the
##   joints + limb endpoints) advanced at a FIXED dt with semi-implicit Euler
##   under gravity, wired together by rigid BONE distance-constraints and driven
##   by MUSCLE angular-constraints toward player-set target angles. Every
##   sub-step is a deterministic float computation with a FIXED iteration count
##   (an XPBD-style relaxation): integrate velocities, integrate positions,
##   relax bones + muscles + ground contact, then re-derive velocities from the
##   projected motion (so a constraint can never inject energy -> no explosion,
##   no NaN). Given (seed, config, per-frame muscle inputs) the trajectory is
##   100% reproducible. The physics itself has ZERO randomness; the ONLY RNG is
##   ONE seeded generator used for an optional tiny start jitter (config
##   "jitter", default 0.0) and it is part of save/load. A MAX_STEPS cap bounds
##   every run -> a timeout, never an infinite stagger.
##
## THE ATHLETE (>= 7 rigid segments): 11 nodes / 10 bones —
##   head, torso, thighL, shinL, footL, thighR, shinR, footR, upperArm, lowerArm.
##   9 joints carry a rest angle; four of them (the hips + knees) are the
##   PLAYER-DRIVEN muscles, the rest are stiff POSTURE springs that hold the head
##   up + the arm out for balance.
##
## MUSCLE MODEL (QWOP): four muscle groups, each an ANTAGONISTIC joint pair —
##   Q -> drive the RIGHT thigh forward + the LEFT thigh back (hip pair),
##   W -> the mirror (left thigh forward, right thigh back),
##   O -> extend the RIGHT knee + flex the LEFT knee (calf pair),
##   P -> the mirror.
##   set_muscle(i, on) shifts that pair's joint TARGET ANGLES; the joint springs
##   chase the target each step, so alternating Q/W/O/P produces a gait. A
##   planted foot gives ground TRACTION (Coulomb friction), so a hip that
##   extends against a gripped foot drives the torso FORWARD (real walking, not
##   sliding).
##
## GAME: horizontal distance travelled = score. WIN = reach the goal distance
##   before falling / timing out; LOSE = FALL (the head or torso hits the ground,
##   or the torso tips past a threshold) or TIMEOUT short of the goal. Both are
##   reachable by a deterministic scripted input policy (policy_walk advances a
##   positive distance + reaches an easy goal; policy_fall topples the athlete).

# =====================================================================
#  Fixed-timestep sim tuning (auditable constants — swap for your own game)
# =====================================================================

const DT: float = 1.0 / 120.0          ## fixed physics timestep (seconds).
const GRAVITY: float = 900.0           ## downward accel (px/s^2, +y is down).
const AIR_DRAG: float = 0.55           ## velocity decay per second (air resistance).
const SOLVER_ITERATIONS: int = 10      ## constraint relaxation passes per step (fixed).
## Hard cap on how far any node may move in ONE step (px). This is a physical
## speed limit (~7 m/s per joint) that keeps the sim honest: a constraint stack-up
## or a startup transient can never teleport a node, so there are no unphysical
## "launches" (the athlete must actually WALK, not slide) and never an explosion.
const MAX_NODE_STEP: float = 700.0 * DT

const PIXELS_PER_METER: float = 100.0  ## world -> metres (distance = hip.x / this).
const GROUND_Y: float = 400.0          ## floor plane; a node with y > this is below ground.
const GROUND_RESTITUTION: float = 0.0  ## vertical bounce off the floor (0 = feet stick).

## Horizontal slip RETAINED when a node is on the ground: 0 = frictionless slide,
## 1 = fully pinned. Feet grip hard (traction); the rest of the body skids.
const FOOT_GRIP: float = 0.94          ## toes + ankles: planted-foot traction.
const BODY_GRIP: float = 0.30          ## torso / head / arms scraping the ground.

## Muscle + posture joint stiffness (fraction of the angle error corrected per
## relaxation iteration). Muscles are springy (a smooth torque toward target);
## posture joints are stiffer so the head stays up + the stance holds.
const MUSCLE_STIFFNESS: float = 0.22
const POSTURE_STIFFNESS: float = 0.40
const BONE_STIFFNESS: float = 1.0      ## bones are rigid (full projection).

## How far (radians) a muscle shifts its joint pair when engaged.
const HIP_SWING: float = 0.72          ## hip flex/extend throw.
const KNEE_THROW: float = 0.85         ## knee extend/flex throw.

## Fall thresholds — when the run ENDS as a topple.
const HEAD_FALL_MARGIN: float = 26.0   ## head within this of the floor -> fall.
const NECK_FALL_MARGIN: float = 14.0   ## shoulder within this of the floor -> fall.
const TORSO_TILT_LIMIT: float = 1.15   ## torso lean from vertical (rad) -> fall (~66 deg).

const MAX_STEPS_DEFAULT: int = 5400     ## hard cap (45 s @120Hz) -> timeout, never infinite.
const GOAL_DISTANCE_DEFAULT: float = 100.0  ## metres to WIN.

## FNV-1a folding constants (63-bit masked) for deterministic checksums.
const FNV_OFFSET: int = 1469598103934665603
const FNV_PRIME: int = 1099511628211
const MASK63: int = 0x7FFFFFFFFFFFFFFF

# =====================================================================
#  Muscle groups (the four QWOP inputs)
# =====================================================================

const MUSCLE_Q: int = 0   ## right thigh forward / left thigh back.
const MUSCLE_W: int = 1   ## left thigh forward / right thigh back.
const MUSCLE_O: int = 2   ## right knee extend / left knee flex.
const MUSCLE_P: int = 3   ## right knee flex / left knee extend.
const MUSCLE_COUNT: int = 4

const MUSCLE_NAMES: Array = ["Q", "W", "O", "P"]
const MUSCLE_LABELS: Array = [
	"Q — right thigh forward / left thigh back",
	"W — left thigh forward / right thigh back",
	"O — right knee straighten / left knee bend",
	"P — right knee bend / left knee straighten",
]

# =====================================================================
#  Node (point-mass) + segment layout
# =====================================================================
#  Node indices — the joints + limb endpoints of the athlete.

const N_HEAD: int = 0
const N_NECK: int = 1     ## top of the torso (also the shoulder).
const N_HIP: int = 2      ## pelvis (the distance origin).
const N_KNEE_L: int = 3
const N_ANKLE_L: int = 4
const N_TOE_L: int = 5
const N_KNEE_R: int = 6
const N_ANKLE_R: int = 7
const N_TOE_R: int = 8
const N_ELBOW: int = 9
const N_HAND: int = 10
const NODE_COUNT: int = 11

## The rest / standing pose (px). +x is forward (right), +y is down. The athlete
## stands with the pelvis at x=0, feet flat on GROUND_Y.
const POSE: Array = [
	Vector2(0.0, 226.0),    # head
	Vector2(0.0, 250.0),    # neck / shoulder
	Vector2(0.0, 300.0),    # hip
	Vector2(-9.0, 350.0),   # knee L
	Vector2(-9.0, 398.0),   # ankle L
	Vector2(17.0, 400.0),   # toe L
	Vector2(9.0, 350.0),    # knee R
	Vector2(9.0, 398.0),    # ankle R
	Vector2(35.0, 400.0),   # toe R
	Vector2(20.0, 282.0),   # elbow
	Vector2(34.0, 320.0),   # hand
]

## Per-node mass (kg-ish; torso heavy, extremities light). Inverse masses drive
## the constraint weighting so a light foot moves around a heavy torso.
const MASS: Array = [
	1.1,   # head
	1.6,   # neck
	3.2,   # hip
	1.0,   # knee L
	0.7,   # ankle L
	0.45,  # toe L
	1.0,   # knee R
	0.7,   # ankle R
	0.45,  # toe R
	0.55,  # elbow
	0.4,   # hand
]

## Horizontal ground grip per node (feet grip, everything else skids).
const NODE_GRIP: Array = [
	BODY_GRIP, BODY_GRIP, BODY_GRIP,
	BODY_GRIP, FOOT_GRIP, FOOT_GRIP,
	BODY_GRIP, FOOT_GRIP, FOOT_GRIP,
	BODY_GRIP, BODY_GRIP,
]

## Bones (rigid distance constraints): [node_a, node_b]. Rest length is derived
## from POSE in setup(). These are the >= 7 rigid segments.
const BONES: Array = [
	[N_HEAD, N_NECK],       # head
	[N_NECK, N_HIP],        # torso
	[N_HIP, N_KNEE_L],      # thigh L
	[N_KNEE_L, N_ANKLE_L],  # shin L
	[N_ANKLE_L, N_TOE_L],   # foot L
	[N_HIP, N_KNEE_R],      # thigh R
	[N_KNEE_R, N_ANKLE_R],  # shin R
	[N_ANKLE_R, N_TOE_R],   # foot R
	[N_NECK, N_ELBOW],      # upper arm
	[N_ELBOW, N_HAND],      # lower arm
]

const BONE_NAMES: Array = [
	"head", "torso", "thighL", "shinL", "footL",
	"thighR", "shinR", "footR", "upperArm", "lowerArm",
]

## Joints (angular constraints): [node_a, node_j, node_b] — the angle at J
## between the bone J->A and the bone J->B. `kind`: "muscle_hip_l",
## "muscle_hip_r", "muscle_knee_l", "muscle_knee_r", or "posture". Rest angle is
## derived from POSE in setup(); a muscle joint's live target is rest + the sum of
## the engaged muscle groups' offsets.
const JOINTS: Array = [
	[N_NECK, N_HIP, N_KNEE_L, "muscle_hip_l"],
	[N_NECK, N_HIP, N_KNEE_R, "muscle_hip_r"],
	[N_HIP, N_KNEE_L, N_ANKLE_L, "muscle_knee_l"],
	[N_HIP, N_KNEE_R, N_ANKLE_R, "muscle_knee_r"],
	[N_KNEE_L, N_ANKLE_L, N_TOE_L, "posture"],
	[N_KNEE_R, N_ANKLE_R, N_TOE_R, "posture"],
	[N_HIP, N_NECK, N_HEAD, "posture"],
	[N_HIP, N_NECK, N_ELBOW, "posture"],
	[N_NECK, N_ELBOW, N_HAND, "posture"],
]

# =====================================================================
#  Live run state
# =====================================================================

## Node kinematics — parallel arrays for deterministic, allocation-free stepping.
var px: PackedFloat64Array = PackedFloat64Array()
var py: PackedFloat64Array = PackedFloat64Array()
var vx: PackedFloat64Array = PackedFloat64Array()
var vy: PackedFloat64Array = PackedFloat64Array()
var inv_mass: PackedFloat64Array = PackedFloat64Array()

## Derived-at-setup constants for this athlete build.
var _bone_rest: PackedFloat64Array = PackedFloat64Array()
var _joint_rest: PackedFloat64Array = PackedFloat64Array()

## Per-frame muscle input (one bool per group). The view / a policy writes these
## via set_muscle(); step() reads them.
var muscles: Array = [false, false, false, false]

var step_count: int = 0
var distance: float = 0.0          ## current horizontal distance (m) from start.
var best_distance: float = 0.0     ## furthest reached this run (m) = the score.
var start_hip_x: float = 0.0
var finished: bool = false
var outcome: String = "running"    ## running | won | fell | timeout.
var fall_reason: String = ""       ## head | neck | tilt (when outcome == fell).
var feet_lifted: bool = false      ## a real step happened (a foot left the floor).
var illegal_attempts: int = 0

## Config (set in setup()).
var goal_distance: float = GOAL_DISTANCE_DEFAULT
var max_steps: int = MAX_STEPS_DEFAULT
var muscle_gain: float = 1.0       ## global muscle strength multiplier (difficulty).
var lean_bias: float = 0.0         ## a forward posture lean baked into hip rest (easy aid).
var balance_gain: float = 0.16     ## torso self-righting reflex per iteration (0 = pure ragdoll).

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = 0
var _preset: String = "normal"

# =====================================================================
#  Setup
# =====================================================================

## Start a fresh run. seed_value == 0 -> random (still saved so it replays); any
## other value replays byte-identically. `config` overrides difficulty:
##   preset:String ("easy" | "normal" | "hard"),
##   goal_distance:float, max_steps:int, muscle_gain:float, lean_bias:float,
##   jitter:float (tiny seeded start perturbation; default 0 -> perfectly clean).
func setup(seed_value: int = 0, config: Dictionary = {}) -> void:
	_seed = seed_value
	if seed_value == 0:
		_rng.randomize()
		_seed = int(_rng.seed)
	else:
		_rng.seed = seed_value
	_preset = String(config.get("preset", "normal"))
	_apply_preset(_preset)
	# explicit overrides win over the preset.
	goal_distance = float(config.get("goal_distance", goal_distance))
	max_steps = int(config.get("max_steps", max_steps))
	muscle_gain = float(config.get("muscle_gain", muscle_gain))
	lean_bias = float(config.get("lean_bias", lean_bias))
	balance_gain = float(config.get("balance_gain", balance_gain))
	var jitter: float = float(config.get("jitter", 0.0))

	_init_nodes(jitter)
	_derive_rest_lengths()

	muscles = [false, false, false, false]
	step_count = 0
	start_hip_x = px[N_HIP]
	distance = 0.0
	best_distance = 0.0
	finished = false
	outcome = "running"
	fall_reason = ""
	feet_lifted = false
	illegal_attempts = 0


## Difficulty presets. Easy: strong muscles, a forward lean, a modest goal, so a
## simple scripted gait clears it. Hard: weak muscles, no aid, the full 100 m.
func _apply_preset(preset: String) -> void:
	match preset:
		"easy":
			muscle_gain = 1.30
			lean_bias = 0.0
			balance_gain = 0.28
			goal_distance = 6.0
			max_steps = 5400
		"hard":
			muscle_gain = 0.85
			lean_bias = 0.0
			balance_gain = 0.08
			goal_distance = 100.0
			max_steps = 7200
		_:  # normal
			muscle_gain = 1.0
			lean_bias = 0.0
			balance_gain = 0.16
			goal_distance = 100.0
			max_steps = 5400


## Lay the athlete out in the rest pose (optionally with a tiny seeded jitter so
## a "random" run still diverges frame-to-frame; default jitter 0 = clean).
func _init_nodes(jitter: float) -> void:
	px = PackedFloat64Array()
	py = PackedFloat64Array()
	vx = PackedFloat64Array()
	vy = PackedFloat64Array()
	inv_mass = PackedFloat64Array()
	px.resize(NODE_COUNT)
	py.resize(NODE_COUNT)
	vx.resize(NODE_COUNT)
	vy.resize(NODE_COUNT)
	inv_mass.resize(NODE_COUNT)
	for i in NODE_COUNT:
		var p: Vector2 = POSE[i]
		var jx: float = 0.0
		var jy: float = 0.0
		if jitter > 0.0:
			jx = _rng.randf_range(-jitter, jitter)
			jy = _rng.randf_range(-jitter, jitter)
		px[i] = p.x + jx
		py[i] = p.y + jy
		vx[i] = 0.0
		vy[i] = 0.0
		inv_mass[i] = 1.0 / float(MASS[i])


## Derive bone rest lengths + joint rest angles from the standing pose.
func _derive_rest_lengths() -> void:
	_bone_rest = PackedFloat64Array()
	_bone_rest.resize(BONES.size())
	for b in BONES.size():
		var a: int = int(BONES[b][0])
		var c: int = int(BONES[b][1])
		_bone_rest[b] = _dist(a, c)
	_joint_rest = PackedFloat64Array()
	_joint_rest.resize(JOINTS.size())
	for j in JOINTS.size():
		_joint_rest[j] = _joint_angle(int(JOINTS[j][0]), int(JOINTS[j][1]), int(JOINTS[j][2]))

# =====================================================================
#  Input model — set_muscle drives the joint targets
# =====================================================================

## Engage / release a muscle group (0..3 = Q/W/O/P). Out-of-range indices are
## rejected + counted (the rules probe checks this). Returns true if applied.
func set_muscle(index: int, on: bool) -> bool:
	if index < 0 or index >= MUSCLE_COUNT:
		illegal_attempts += 1
		return false
	if finished:
		# inputs after the run ends are ignored (but not "illegal" — the human may
		# still be mashing keys); no-op.
		return false
	muscles[index] = on
	return true


## Set all four muscles at once from a bitmask (bit i = group i). Used by the
## scripted policies + the determinism probe for compact canned sequences.
func set_muscle_mask(mask: int) -> void:
	for i in MUSCLE_COUNT:
		muscles[i] = (mask & (1 << i)) != 0


func muscle_mask() -> int:
	var m: int = 0
	for i in MUSCLE_COUNT:
		if bool(muscles[i]):
			m |= (1 << i)
	return m


## The LIVE target angle for joint `j` given the current muscle inputs. Posture
## joints hold their rest angle (plus a forward lean on the hips); muscle joints
## add the engaged groups' offsets, scaled by the difficulty muscle_gain.
func _joint_target(j: int) -> float:
	var kind: String = String(JOINTS[j][3])
	var target: float = _joint_rest[j]
	var g: float = muscle_gain
	match kind:
		"muscle_hip_r":
			target += lean_bias  # a forward lean helps the athlete walk into it.
			if bool(muscles[MUSCLE_Q]):
				target += HIP_SWING * g
			if bool(muscles[MUSCLE_W]):
				target -= HIP_SWING * g
		"muscle_hip_l":
			target += lean_bias
			if bool(muscles[MUSCLE_W]):
				target += HIP_SWING * g
			if bool(muscles[MUSCLE_Q]):
				target -= HIP_SWING * g
		"muscle_knee_r":
			if bool(muscles[MUSCLE_P]):
				target += KNEE_THROW * g
			if bool(muscles[MUSCLE_O]):
				target -= KNEE_THROW * g
		"muscle_knee_l":
			if bool(muscles[MUSCLE_O]):
				target += KNEE_THROW * g
			if bool(muscles[MUSCLE_P]):
				target -= KNEE_THROW * g
		_:  # posture
			pass
	return target

# =====================================================================
#  The fixed-timestep step — semi-implicit Euler + XPBD relaxation
# =====================================================================

## Advance the sim by ONE fixed DT with the current muscle inputs. Bounded, pure,
## deterministic. Ends the run on a fall, the goal, or the step cap. Returns true
## while the run is still live (mirrors a "keep going" flag for the caller).
func step() -> bool:
	if finished:
		return false

	# Save the pre-integration positions; velocities are re-derived from the
	# projected motion at the end (XPBD) so no constraint can inject energy.
	var prev_x: PackedFloat64Array = px.duplicate()
	var prev_y: PackedFloat64Array = py.duplicate()

	# 1) integrate velocities (gravity + air drag), then positions (semi-implicit).
	var drag: float = clampf(1.0 - AIR_DRAG * DT, 0.0, 1.0)
	for i in NODE_COUNT:
		vy[i] += GRAVITY * DT
		vx[i] *= drag
		vy[i] *= drag
		px[i] += vx[i] * DT
		py[i] += vy[i] * DT

	# 2) constraint relaxation — a FIXED number of passes (deterministic). Each
	#    pass: rigidify bones, drive muscles/posture toward their targets, then
	#    resolve ground contact + friction (last so nothing ends below the floor).
	for _iter in SOLVER_ITERATIONS:
		_solve_bones()
		_solve_joints()
		_solve_balance()
		_solve_ground(prev_x)

	# 3) clamp per-node displacement to the physical speed limit (no teleporting /
	#    no launch). Clamping a single node can momentarily violate its bone, so
	#    reconcile with a few more bone + ground passes to restore rigidity around
	#    the clamped anchors, THEN re-derive velocities from the net motion.
	for i in NODE_COUNT:
		var mdx: float = px[i] - prev_x[i]
		var mdy: float = py[i] - prev_y[i]
		var mlen: float = sqrt(mdx * mdx + mdy * mdy)
		if mlen > MAX_NODE_STEP and mlen > 0.000001:
			var scale: float = MAX_NODE_STEP / mlen
			px[i] = prev_x[i] + mdx * scale
			py[i] = prev_y[i] + mdy * scale
	for _r in 4:
		_solve_bones()
		_solve_ground(prev_x)
	# a final clamp so the reconciliation can't re-introduce a launch, then derive v.
	var inv_dt: float = 1.0 / DT
	for i in NODE_COUNT:
		var dx2: float = px[i] - prev_x[i]
		var dy2: float = py[i] - prev_y[i]
		var l2: float = sqrt(dx2 * dx2 + dy2 * dy2)
		if l2 > MAX_NODE_STEP and l2 > 0.000001:
			var sc2: float = MAX_NODE_STEP / l2
			dx2 *= sc2
			dy2 *= sc2
			px[i] = prev_x[i] + dx2
			py[i] = prev_y[i] + dy2
		vx[i] = dx2 * inv_dt
		vy[i] = dy2 * inv_dt

	step_count += 1
	_update_metrics()
	_check_end_conditions()
	return not finished


## Rigid bone distance constraints — project each pair back to its rest length,
## split by inverse mass so a light node moves more than a heavy one.
func _solve_bones() -> void:
	for b in BONES.size():
		var a: int = int(BONES[b][0])
		var c: int = int(BONES[b][1])
		var dx: float = px[c] - px[a]
		var dy: float = py[c] - py[a]
		var d: float = sqrt(dx * dx + dy * dy)
		if d < 0.000001:
			continue
		var rest: float = _bone_rest[b]
		var diff: float = (d - rest) / d
		var wa: float = inv_mass[a]
		var wc: float = inv_mass[c]
		var wsum: float = wa + wc
		if wsum <= 0.0:
			continue
		var corr: float = BONE_STIFFNESS * diff
		var fa: float = (wa / wsum) * corr
		var fc: float = (wc / wsum) * corr
		px[a] += dx * fa
		py[a] += dy * fa
		px[c] -= dx * fc
		py[c] -= dy * fc


## Muscle + posture angular constraints — rotate the two outer nodes about the
## joint node toward the joint's live target angle. Muscles are springy; posture
## joints are stiff. Inverse-mass weighted so the torque reacts through the body.
func _solve_joints() -> void:
	for j in JOINTS.size():
		var na: int = int(JOINTS[j][0])
		var nj: int = int(JOINTS[j][1])
		var nb: int = int(JOINTS[j][2])
		var kind: String = String(JOINTS[j][3])
		var stiff: float = POSTURE_STIFFNESS if kind == "posture" else MUSCLE_STIFFNESS

		var ax: float = px[na] - px[nj]
		var ay: float = py[na] - py[nj]
		var bx: float = px[nb] - px[nj]
		var by: float = py[nb] - py[nj]
		var la: float = sqrt(ax * ax + ay * ay)
		var lb: float = sqrt(bx * bx + by * by)
		if la < 0.000001 or lb < 0.000001:
			continue
		var ang_a: float = atan2(ay, ax)
		var ang_b: float = atan2(by, bx)
		var current: float = _wrap_pi(ang_b - ang_a)
		var target: float = _joint_target(j)
		var err: float = _wrap_pi(target - current)
		# split the corrective rotation between the two sides by inverse mass so
		# the heavier limb rotates less (Newton's third law, discretised).
		var wa: float = inv_mass[na]
		var wb: float = inv_mass[nb]
		var wsum: float = wa + wb
		if wsum <= 0.0:
			continue
		var rot: float = err * stiff
		var rot_b: float = rot * (wb / wsum)
		var rot_a: float = -rot * (wa / wsum)
		_rotate_about(nb, nj, bx, by, rot_b)
		_rotate_about(na, nj, ax, ay, rot_a)


## The athlete's BALANCE REFLEX — a self-righting torque that rotates the torso
## (neck about hip) back toward vertical, inverse-mass split so the pelvis takes
## the reaction. balance_gain scales it by difficulty: strong on easy (a forgiving
## walk), weak on hard (a true ragdoll teeter). This is what makes a simple
## scripted gait able to walk without a human constantly catching the fall; a
## hard-enough muscle lunge still overpowers it and topples (LOSS stays reachable).
func _solve_balance() -> void:
	if balance_gain <= 0.0:
		return
	var dx: float = px[N_NECK] - px[N_HIP]
	var dy: float = py[N_NECK] - py[N_HIP]
	var tilt: float = _wrap_pi(atan2(dx, -dy))  # 0 = neck straight above hip.
	if absf(tilt) < 0.0001:
		return
	# Rotate the UPPER body toward vertical about the pelvis, WITHOUT moving the
	# pelvis. Keeping the hip pivot fixed means balance never launches the body
	# horizontally (the earlier reaction-on-hip term made it rocket forward); the
	# only thing that moves the athlete along the ground is the leg gait pushing
	# through gripped feet. The head + arms follow the neck through their bones on
	# the next relaxation pass.
	var rot: float = -tilt * balance_gain
	_rotate_about(N_NECK, N_HIP, dx, dy, rot)


## Rotate node `n` (offset ox,oy from pivot pj) by `ang` radians about the pivot.
func _rotate_about(n: int, pj: int, ox: float, oy: float, ang: float) -> void:
	var c: float = cos(ang)
	var s: float = sin(ang)
	var nx: float = ox * c - oy * s
	var ny: float = ox * s + oy * c
	px[n] = px[pj] + nx
	py[n] = py[pj] + ny


## Ground contact + Coulomb-style friction. A node pushed below the floor is
## lifted to it, its downward motion is killed (with a small restitution), and
## its HORIZONTAL slip is resisted by its grip — feet grip hard, so a planted
## foot converts a hip drive into forward travel (traction, not sliding).
func _solve_ground(prev_x: PackedFloat64Array) -> void:
	for i in NODE_COUNT:
		if py[i] <= GROUND_Y:
			continue
		py[i] = GROUND_Y
		# vertical: cancel the descent (bounce is 0 for feet -> they plant).
		if vy[i] > 0.0:
			vy[i] = -vy[i] * GROUND_RESTITUTION
		# horizontal: retain only (1 - grip) of the slip since the last frame.
		var grip: float = float(NODE_GRIP[i])
		var slip: float = px[i] - prev_x[i]
		px[i] = prev_x[i] + slip * (1.0 - grip)

# =====================================================================
#  Metrics + end conditions
# =====================================================================

func _update_metrics() -> void:
	distance = (px[N_HIP] - start_hip_x) / PIXELS_PER_METER
	if distance > best_distance:
		best_distance = distance
	# a "real step" is any moment a foot clears the floor by a margin — proof the
	# gait lifts + plants rather than skating both feet along the ground.
	if not feet_lifted:
		var lift: float = 8.0
		if py[N_TOE_L] < GROUND_Y - lift or py[N_TOE_R] < GROUND_Y - lift \
				or py[N_ANKLE_L] < GROUND_Y - lift or py[N_ANKLE_R] < GROUND_Y - lift:
			# only counts once the athlete has actually moved off the spot a touch,
			# so merely standing (feet always at/above the line) is not a "step".
			if absf(distance) > 0.02:
				feet_lifted = true


func _check_end_conditions() -> void:
	# WIN: reached the goal (measured on furthest progress, so a stumble past the
	# line still counts) before any fall / timeout.
	if best_distance >= goal_distance:
		finished = true
		outcome = "won"
		return
	# FALL: the head or the shoulder hits the floor, or the torso tips too far.
	if py[N_HEAD] >= GROUND_Y - HEAD_FALL_MARGIN:
		_end_fall("head")
		return
	if py[N_NECK] >= GROUND_Y - NECK_FALL_MARGIN:
		_end_fall("neck")
		return
	var tilt: float = _torso_tilt()
	if absf(tilt) > TORSO_TILT_LIMIT:
		_end_fall("tilt")
		return
	# TIMEOUT: the step cap bounds every run (never an infinite stagger).
	if step_count >= max_steps:
		finished = true
		outcome = "timeout"


func _end_fall(reason: String) -> void:
	finished = true
	outcome = "fell"
	fall_reason = reason


## The torso's lean from vertical (rad). 0 = perfectly upright; +/- = tipped
## forward/back. Used for the fall check + the HUD.
func _torso_tilt() -> float:
	var dx: float = px[N_NECK] - px[N_HIP]
	var dy: float = py[N_NECK] - py[N_HIP]
	# upright means neck is straight above hip -> (0, -len). Measure the deviation.
	return _wrap_pi(atan2(dx, -dy))


func is_won() -> bool:
	return finished and outcome == "won"


func is_lost() -> bool:
	return finished and (outcome == "fell" or outcome == "timeout")

# =====================================================================
#  Scripted input policies (deterministic — drive a whole run headlessly)
# =====================================================================

## The canonical WALK policy: a periodic QWOP gait that plants + pushes to carry
## the athlete FORWARD a positive distance (and clears the easy goal). Pure
## function of the step index -> a muscle bitmask, so a scripted run is
## byte-identical. The cadence: lead with one leg's hip-drive + the opposite
## knee, swap on the half-cycle (the classic QWOP alternation).
## The gait period + the "duty" tail where the knee drive releases near the end of
## each stance (tuned by the headless gait search — a non-zero duty is what keeps
## the walk a steady stride instead of a runaway lurch).
const WALK_PERIOD: int = 48
const WALK_KNEE_DUTY: int = 6

func policy_walk(step_index: int) -> int:
	var half: int = WALK_PERIOD / 2
	var phase: int = step_index % WALK_PERIOD
	var mask: int = 0
	if phase < half:
		# stance on the LEFT foot: extend the left hip (W drives left thigh back +
		# right thigh forward) while the right knee straightens (O) — the planted
		# left foot grips and the body levers FORWARD over it.
		mask = (1 << MUSCLE_W) | (1 << MUSCLE_O)
		if phase >= half - WALK_KNEE_DUTY:
			mask &= ~((1 << MUSCLE_O) | (1 << MUSCLE_P))  # release the knee to plant.
	else:
		# stance on the RIGHT foot: the mirror (Q + P).
		mask = (1 << MUSCLE_Q) | (1 << MUSCLE_P)
		if phase >= WALK_PERIOD - WALK_KNEE_DUTY:
			mask &= ~((1 << MUSCLE_O) | (1 << MUSCLE_P))
	return mask


## A policy that deliberately TOPPLES the athlete: a fast flip-lunge that drives
## the right hip forward while thrashing the knees out of phase, so the athlete
## pitches over and the head / shoulder hits the floor (or the torso exceeds the
## tilt limit) -> a FALL. Reliable whenever the balance reflex is weak (the "hard"
## preset, or any run with a lowered balance_gain), which the fall probe uses.
func policy_fall(step_index: int) -> int:
	if (step_index / 8) % 2 == 0:
		return (1 << MUSCLE_Q) | (1 << MUSCLE_O)
	return (1 << MUSCLE_Q) | (1 << MUSCLE_P)


## Run a full scripted policy to its end (fall / goal / timeout), bounded by the
## step cap. `which`: "walk" | "fall". Returns the outcome dictionary. Pure —
## does not touch the RNG, so it replays byte-identically.
func run_policy(which: String) -> Dictionary:
	while not finished:
		var mask: int = 0
		match which:
			"walk":
				mask = policy_walk(step_count)
			"fall":
				mask = policy_fall(step_count)
			_:
				mask = 0
		set_muscle_mask(mask)
		step()
	return result()


## Advance a fixed number of steps under a policy (for mid-run probes). Stops
## early if the run ends.
func run_policy_steps(which: String, n: int) -> void:
	for _i in n:
		if finished:
			break
		var mask: int = 0
		if which == "walk":
			mask = policy_walk(step_count)
		elif which == "fall":
			mask = policy_fall(step_count)
		set_muscle_mask(mask)
		step()

# =====================================================================
#  Queries for the view / probes
# =====================================================================

## The current outcome snapshot.
func result() -> Dictionary:
	return {
		"outcome": outcome,
		"finished": finished,
		"distance": distance,
		"best_distance": best_distance,
		"goal_distance": goal_distance,
		"steps": step_count,
		"fall_reason": fall_reason,
		"feet_lifted": feet_lifted,
		"tilt": _torso_tilt(),
	}


## Node world position (for rendering + the net avatar's synced state).
func node_position(i: int) -> Vector2:
	return Vector2(px[i], py[i])


## The whole athlete as a flat PackedFloat32Array [x0,y0,x1,y1,...] — the compact
## payload the networked avatar syncs for the remote view.
func pose_snapshot() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(NODE_COUNT * 2)
	for i in NODE_COUNT:
		out[i * 2] = float(px[i])
		out[i * 2 + 1] = float(py[i])
	return out


## Overwrite the node positions from a synced snapshot (remote avatar render).
## Velocities are zeroed — a remote view renders the synced pose, it does not sim.
func apply_pose_snapshot(snap: PackedFloat32Array) -> void:
	if snap.size() < NODE_COUNT * 2:
		return
	for i in NODE_COUNT:
		px[i] = float(snap[i * 2])
		py[i] = float(snap[i * 2 + 1])
		vx[i] = 0.0
		vy[i] = 0.0
	_update_metrics()


## Bone endpoints for the renderer: [[a:Vector2, b:Vector2, name:String], ...].
func bone_segments() -> Array:
	var out: Array = []
	for b in BONES.size():
		out.append([node_position(int(BONES[b][0])), node_position(int(BONES[b][1])), String(BONE_NAMES[b])])
	return out


func ground_y() -> float:
	return GROUND_Y


func seed_value() -> int:
	return _seed


func preset() -> String:
	return _preset

# =====================================================================
#  Determinism checksums
# =====================================================================

func _fold(h: int, v: int) -> int:
	h = (h ^ v) * FNV_PRIME
	return h & MASK63


## FNV-1a over the QUANTISED body state (positions + velocities to 1e-3 px). Two
## engines with the same seed + config + input history match iff this matches —
## the determinism probe folds this each step.
func body_checksum() -> int:
	var h: int = FNV_OFFSET
	for i in NODE_COUNT:
		h = _fold(h, int(round(px[i] * 1000.0)))
		h = _fold(h, int(round(py[i] * 1000.0)))
		h = _fold(h, int(round(vx[i] * 1000.0)))
		h = _fold(h, int(round(vy[i] * 1000.0)))
	return h


## Order-stable checksum of the WHOLE run (body + progress + outcome + RNG). Used
## by the save/load round-trip probe.
func run_checksum() -> int:
	var h: int = body_checksum()
	h = _fold(h, _seed)
	h = _fold(h, int(_rng.state & MASK63))
	h = _fold(h, step_count)
	h = _fold(h, int(round(distance * 1000.0)))
	h = _fold(h, int(round(best_distance * 1000.0)))
	h = _fold(h, int(round(goal_distance * 1000.0)))
	h = _fold(h, max_steps)
	h = _fold(h, int(round(muscle_gain * 1000.0)))
	h = _fold(h, int(round(lean_bias * 1000.0)))
	h = _fold(h, int(round(balance_gain * 1000.0)))
	h = _fold(h, 1 if finished else 0)
	h = _fold(h, hash(outcome))
	h = _fold(h, hash(fall_reason))
	h = _fold(h, 1 if feet_lifted else 0)
	h = _fold(h, muscle_mask())
	h = _fold(h, illegal_attempts)
	return h

# =====================================================================
#  Save / load — the WHOLE run round-trips (JSON-safe)
# =====================================================================

func to_dict() -> Dictionary:
	return {
		"seed": _seed,
		"rng_state": str(_rng.state),
		"preset": _preset,
		"goal_distance": goal_distance,
		"max_steps": max_steps,
		"muscle_gain": muscle_gain,
		"lean_bias": lean_bias,
		"balance_gain": balance_gain,
		"px": _f64_to_array(px),
		"py": _f64_to_array(py),
		"vx": _f64_to_array(vx),
		"vy": _f64_to_array(vy),
		"muscles": muscles.duplicate(),
		"step_count": step_count,
		"start_hip_x": start_hip_x,
		"distance": distance,
		"best_distance": best_distance,
		"finished": finished,
		"outcome": outcome,
		"fall_reason": fall_reason,
		"feet_lifted": feet_lifted,
		"illegal_attempts": illegal_attempts,
	}


func from_dict(data: Dictionary) -> void:
	_seed = int(data.get("seed", 0))
	_rng.seed = _seed
	_rng.state = String(data.get("rng_state", str(_rng.state))).to_int()
	_preset = String(data.get("preset", "normal"))
	goal_distance = float(data.get("goal_distance", GOAL_DISTANCE_DEFAULT))
	max_steps = int(data.get("max_steps", MAX_STEPS_DEFAULT))
	muscle_gain = float(data.get("muscle_gain", 1.0))
	lean_bias = float(data.get("lean_bias", 0.0))
	balance_gain = float(data.get("balance_gain", 0.16))
	px = _array_to_f64(data.get("px", []))
	py = _array_to_f64(data.get("py", []))
	vx = _array_to_f64(data.get("vx", []))
	vy = _array_to_f64(data.get("vy", []))
	inv_mass = PackedFloat64Array()
	inv_mass.resize(NODE_COUNT)
	for i in NODE_COUNT:
		inv_mass[i] = 1.0 / float(MASS[i])
	_derive_rest_lengths()
	var m: Array = data.get("muscles", [false, false, false, false])
	muscles = [false, false, false, false]
	for i in mini(MUSCLE_COUNT, m.size()):
		muscles[i] = bool(m[i])
	step_count = int(data.get("step_count", 0))
	start_hip_x = float(data.get("start_hip_x", 0.0))
	distance = float(data.get("distance", 0.0))
	best_distance = float(data.get("best_distance", 0.0))
	finished = bool(data.get("finished", false))
	outcome = String(data.get("outcome", "running"))
	fall_reason = String(data.get("fall_reason", ""))
	feet_lifted = bool(data.get("feet_lifted", false))
	illegal_attempts = int(data.get("illegal_attempts", 0))

# =====================================================================
#  Small math + array helpers
# =====================================================================

func _dist(a: int, b: int) -> float:
	var dx: float = float(POSE[b].x) - float(POSE[a].x)
	var dy: float = float(POSE[b].y) - float(POSE[a].y)
	return sqrt(dx * dx + dy * dy)


func _joint_angle(a: int, j: int, b: int) -> float:
	var ax: float = float(POSE[a].x) - float(POSE[j].x)
	var ay: float = float(POSE[a].y) - float(POSE[j].y)
	var bx: float = float(POSE[b].x) - float(POSE[j].x)
	var by: float = float(POSE[b].y) - float(POSE[j].y)
	return _wrap_pi(atan2(by, bx) - atan2(ay, ax))


func _wrap_pi(a: float) -> float:
	var r: float = fmod(a + PI, TAU)
	if r < 0.0:
		r += TAU
	return r - PI


func _f64_to_array(a: PackedFloat64Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(v)
	return out


func _array_to_f64(a: Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(NODE_COUNT)
	for i in NODE_COUNT:
		out[i] = float(a[i]) if i < a.size() else 0.0
	return out
