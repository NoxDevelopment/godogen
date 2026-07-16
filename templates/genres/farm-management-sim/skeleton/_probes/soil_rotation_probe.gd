extends Node
## _probes/soil_rotation_probe.gd
## SOIL + CROP ROTATION + IRRIGATION probe:
##  A) MONOCULTURE DEPLETION vs ROTATION/FERTILIZER. Three SEPARATE farms (same seed, same
##     forced-CLEAR weather) each work FIELD 0 — so soil quality, planting days and weather
##     are IDENTICAL and the ONLY difference is how nitrogen is managed. Farm A grows corn
##     every cycle (monoculture); farm B rotates a nitrogen-FIXING legume (soybeans) into
##     the middle cycle; farm C FERTILIZES before each later corn. After three cycles the
##     monoculture's final corn yield has FALLEN below its own first-cycle yield AND below
##     both the rotated and the fertilized farms' final corn yields — proving the nitrogen
##     balance measurably drives yield.
##  B) IRRIGATION MITIGATES DROUGHT. Under a forced DROUGHT the same corn crop on the same
##     field yields MORE with irrigation than without — irrigation buys back lost water.

const CFG_CLEAR: Dictionary = {
	"weather_override": FarmEngine.W_NORMAL,
	"growth_goal": 50000000, "max_years": 12, "start_cash": 5000000,
}
const CORN_DAYS: int = 90   ## == FarmEngine.CROP_DURATION[CR_CORN]; all cycles run this long.

## Grow every planted field to maturity by ticking (no livestock → no RNG divergence).
func _grow(e: FarmEngine, days: int) -> void:
	for _i in days:
		e.tick_day()

## Run three corn/rotation cycles on FIELD 0 and return the corn yield of each corn cycle.
## `crops` is the crop planted per cycle; `fert` marks cycles fertilized before planting.
## Returns [cycle0_yield, cycle1_yield, cycle2_yield].
func _run(crops: Array, fert: Array) -> Array:
	var e: FarmEngine = FarmEngine.new()
	e.setup(20260716, CFG_CLEAR)
	var out: Array = []
	for cyc in 3:
		if bool(fert[cyc]):
			e.fertilize(0)
		e.plant(0, int(crops[cyc]), true)
		_grow(e, CORN_DAYS)
		out.append(e.projected_yield(0))
		e.harvest(0)
	return out

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# ---------------------------------------------------------------
	# A) monoculture vs rotation vs fertilizer — all on field 0, matched weather.
	# ---------------------------------------------------------------
	var mono: Array = _run(
		[FarmEngine.CR_CORN, FarmEngine.CR_CORN, FarmEngine.CR_CORN], [false, false, false])
	var rota: Array = _run(
		[FarmEngine.CR_CORN, FarmEngine.CR_SOY, FarmEngine.CR_CORN], [false, false, false])
	var fertz: Array = _run(
		[FarmEngine.CR_CORN, FarmEngine.CR_CORN, FarmEngine.CR_CORN], [false, true, true])

	var yA1: int = int(mono[0])
	var yA3: int = int(mono[2])
	var yB3: int = int(rota[2])   # cycle 2 is corn again in the rotation plan.
	var yC3: int = int(fertz[2])

	# cycle-0 corn yields matched across all three farms (same field / seed / day / weather).
	if not (int(mono[0]) == int(rota[0]) and int(rota[0]) == int(fertz[0])):
		fails += 1
		notes.append("cycle0-not-matched(%d/%d/%d)" % [int(mono[0]), int(rota[0]), int(fertz[0])])
	# monoculture yield DECLINED vs its own first cycle.
	if not (yA3 < yA1):
		fails += 1
		notes.append("monoculture-not-declining(%d>=%d)" % [yA3, yA1])
	# rotation (legume) beat monoculture under matched weather.
	if not (yB3 > yA3):
		fails += 1
		notes.append("rotation-not-better(%d<=%d)" % [yB3, yA3])
	# fertilizer beat monoculture under matched weather.
	if not (yC3 > yA3):
		fails += 1
		notes.append("fertilizer-not-better(%d<=%d)" % [yC3, yA3])
	# the recovered fields materially recovered (well above the depleted monoculture).
	if not (yB3 > yA3 + yA3 / 2):
		fails += 1
		notes.append("rotation-recovery-weak(%d vs %d)" % [yB3, yA3])

	# ---------------------------------------------------------------
	# B) irrigation mitigates a drought (same field 0, forced drought).
	# ---------------------------------------------------------------
	var dry: FarmEngine = FarmEngine.new()
	dry.setup(20260716, {"weather_override": FarmEngine.W_DROUGHT,
		"growth_goal": 50000000, "max_years": 4, "start_cash": 5000000})
	dry.plant(0, FarmEngine.CR_CORN, true)
	_grow(dry, CORN_DAYS)
	var yield_dry: int = dry.projected_yield(0)

	var wet: FarmEngine = FarmEngine.new()
	wet.setup(20260716, {"weather_override": FarmEngine.W_DROUGHT,
		"growth_goal": 50000000, "max_years": 4, "start_cash": 5000000})
	wet.plant(0, FarmEngine.CR_CORN, true)
	wet.set_irrigation(0, true)
	_grow(wet, CORN_DAYS)
	var yield_wet: int = wet.projected_yield(0)

	if not (yield_wet > yield_dry):
		fails += 1
		notes.append("irrigation-no-drought-relief(wet=%d dry=%d)" % [yield_wet, yield_dry])
	# irrigation actually cost money over the run (it is not free relief).
	if not (wet.category_total("irrigation") < 0):
		fails += 1
		notes.append("irrigation-was-free(%d)" % wet.category_total("irrigation"))

	print("DEBUG: soil_rotation_probe mono=%d->%d rota_c2=%d fert_c2=%d cyc0=%d/%d/%d drought wet=%d dry=%d notes=%s fails=%d => %s" % [
		yA1, yA3, yB3, yC3, int(mono[0]), int(rota[0]), int(fertz[0]), yield_wet, yield_dry,
		str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
