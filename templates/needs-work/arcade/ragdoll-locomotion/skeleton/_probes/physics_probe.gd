extends Node
## _probes/physics_probe.gd
## PHYSICS probe: the articulated body behaves — segments fall under gravity, a
## planted foot grips the ground (traction, not a free slide), the joint/bone
## constraints stay rigid under vigorous actuation, and nothing ever NaNs or
## explodes. Prints one DEBUG line, quits.

const Q := 1
const W := 2
const O := 4
const P := 8


func _finite_body(e: RagdollEngine) -> bool:
	for i in RagdollEngine.NODE_COUNT:
		if is_nan(e.px[i]) or is_nan(e.py[i]) or is_nan(e.vx[i]) or is_nan(e.vy[i]):
			return false
		if absf(e.px[i]) > 1.0e5 or absf(e.py[i]) > 1.0e5:
			return false
	return true


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- 1) GRAVITY: a body lifted off the floor falls (all nodes descend) ---
	var g: RagdollEngine = RagdollEngine.new()
	g.setup(20260716, {"preset": "normal", "balance_gain": 0.0})
	# lift the whole athlete well above the ground so it is unsupported.
	for i in RagdollEngine.NODE_COUNT:
		g.py[i] -= 260.0
	var head_y0: float = g.py[RagdollEngine.N_HEAD]
	var hip_y0: float = g.py[RagdollEngine.N_HIP]
	for _s in 12:
		g.set_muscle_mask(0)
		g.step()
	if g.py[RagdollEngine.N_HEAD] <= head_y0 + 1.0:
		fails += 1
		notes.append("head-did-not-fall(%.2f->%.2f)" % [head_y0, g.py[RagdollEngine.N_HEAD]])
	if g.py[RagdollEngine.N_HIP] <= hip_y0 + 1.0:
		fails += 1
		notes.append("hip-did-not-fall")
	if not _finite_body(g):
		fails += 1
		notes.append("gravity-nonfinite")

	# --- 2) TRACTION: a planted foot resists horizontal slip far more than an
	#        airborne node. Push the whole body sideways for one step and compare
	#        how far the grounded toe moved vs the airborne head. ---
	var t: RagdollEngine = RagdollEngine.new()
	t.setup(20260716, {"preset": "normal"})
	var toe0: float = t.px[RagdollEngine.N_TOE_L]
	var head0: float = t.px[RagdollEngine.N_HEAD]
	for i in RagdollEngine.NODE_COUNT:
		t.vx[i] = 220.0
	t.set_muscle_mask(0)
	t.step()
	var toe_dx: float = absf(t.px[RagdollEngine.N_TOE_L] - toe0)
	var head_dx: float = absf(t.px[RagdollEngine.N_HEAD] - head0)
	# the grounded toe (grip 0.94) should slide markedly less than the free head.
	if not (toe_dx < head_dx * 0.75):
		fails += 1
		notes.append("no-traction(toe=%.3f head=%.3f)" % [toe_dx, head_dx])

	# a foot planted flat should sit ON the floor, never below it.
	for i in [RagdollEngine.N_TOE_L, RagdollEngine.N_ANKLE_L, RagdollEngine.N_TOE_R, RagdollEngine.N_ANKLE_R]:
		if t.py[i] > t.ground_y() + 0.001:
			fails += 1
			notes.append("foot-below-floor(%d)" % i)
			break

	# --- 3) CONSTRAINT INTEGRITY: hammer every muscle for 2000 steps; bones stay
	#        near their rest length (rigid) and nothing NaNs / explodes. ---
	var c: RagdollEngine = RagdollEngine.new()
	c.setup(20260716, {"preset": "normal"})
	var max_stretch: float = 0.0
	var steps_done: int = 0
	for s in 2000:
		# a thrashing input that exercises hips + knees hard.
		var mask: int = 0
		if s % 2 == 0:
			mask = Q | O
		else:
			mask = W | P
		c.set_muscle_mask(mask)
		c.step()
		steps_done += 1
		if not _finite_body(c):
			fails += 1
			notes.append("explode@%d" % s)
			break
		# check bone rigidity against the derived rest lengths.
		for b in RagdollEngine.BONES.size():
			var a: int = int(RagdollEngine.BONES[b][0])
			var bb: int = int(RagdollEngine.BONES[b][1])
			var dx: float = c.px[bb] - c.px[a]
			var dy: float = c.py[bb] - c.py[a]
			var d: float = sqrt(dx * dx + dy * dy)
			var rest: float = c._bone_rest[b]
			if rest > 0.001:
				var stretch: float = absf(d - rest) / rest
				if stretch > max_stretch:
					max_stretch = stretch
		if c.finished:
			# vigorous thrash may topple — restart to keep stressing the solver.
			c.setup(20260716 + s, {"preset": "normal"})
	if max_stretch > 0.30:
		fails += 1
		notes.append("bones-stretched(%.1f%%)" % (max_stretch * 100.0))

	print("DEBUG: physics_probe head_fall=%.1f traction(toe=%.2f<head=%.2f) max_stretch=%.1f%% steps=%d notes=%s fails=%d => %s" % [
		g.py[RagdollEngine.N_HEAD] - head_y0, toe_dx, head_dx, max_stretch * 100.0,
		steps_done, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
