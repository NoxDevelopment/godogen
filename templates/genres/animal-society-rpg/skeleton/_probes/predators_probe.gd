extends Node
## _probes/predators_probe.gd
## PREDATORS + SURVIVAL probe — a predator raid can KILL a named member (real stakes);
## a band with a Scout/Seer warning + Fighters + speed survives MEASURABLY better than
## a band without them; and SEASONS modulate food + danger (lean, dangerous winter vs
## rich, calm summer).

## Put a band at the deadliest stop, in deep winter, weary and wounded — the honest
## conditions under which the trek turns lethal.
func _harden(e: WarrenEngine) -> void:
	var worst: int = 0
	var worst_d: float = -1.0
	for i in e.stop_count():
		var d: float = float(e.stop_info(i)["danger"])
		if d > worst_d:
			worst_d = d
			worst = i
	e.journey_index = worst
	e.day = 42  # winter
	for i in e.member_count():
		e.debug_set_hp(i, 8)


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	var weak_deaths: int = 0
	var strong_deaths: int = 0
	var named_victim: String = ""
	for s in range(1, 81):
		var seed_v: int = s * 7 + 3
		# WEAK band: strip the Seer, the Fighter, and the Scout.
		var w: WarrenEngine = WarrenEngine.new()
		w.setup(seed_v)
		_harden(w)
		w.take_action(WarrenEngine.ACT_ASSIGN, WarrenEngine.SEER, WarrenEngine.FORAGER)
		w.take_action(WarrenEngine.ACT_ASSIGN, WarrenEngine.FIGHTER, WarrenEngine.FORAGER)
		w.take_action(WarrenEngine.ACT_ASSIGN, WarrenEngine.SCOUT, WarrenEngine.FORAGER)
		var victim: String = String(w.member_info(0)["name"]) if w.member_count() > 0 else ""
		var killed: int = w.force_encounter(WarrenEngine.CAT)
		weak_deaths += killed
		if killed > 0 and named_victim == "":
			named_victim = victim
		# STRONG band: keeps its Seer + Fighter + Scout.
		var st: WarrenEngine = WarrenEngine.new()
		st.setup(seed_v)
		_harden(st)
		strong_deaths += st.force_encounter(WarrenEngine.CAT)

	# A raid CAN kill a named member.
	if not (weak_deaths > 0 and named_victim != ""):
		fails += 1
		notes.append("no-kill(%d,%s)" % [weak_deaths, named_victim])

	# The role-strong band survives measurably better (fewer losses).
	if not (strong_deaths < weak_deaths):
		fails += 1
		notes.append("no-advantage(strong%d>=weak%d)" % [strong_deaths, weak_deaths])

	# SEASONS modulate food + danger: measure the same band in summer vs winter.
	var se: WarrenEngine = WarrenEngine.new()
	se.setup(20260716)
	se.day = 18  # summer
	var forage_summer: int = se.forage_yield_preview()
	var chance_summer: float = se.encounter_chance_preview(true)
	se.day = 42  # winter
	var forage_winter: int = se.forage_yield_preview()
	var chance_winter: float = se.encounter_chance_preview(true)
	if not (forage_summer > forage_winter):
		fails += 1
		notes.append("season-food(%d<=%d)" % [forage_summer, forage_winter])
	if not (chance_winter > chance_summer):
		fails += 1
		notes.append("season-danger(%.3f<=%.3f)" % [chance_winter, chance_summer])

	print("DEBUG: predators_probe weakD=%d strongD=%d victim=%s forage(s/w)=%d/%d danger(s/w)=%.3f/%.3f notes=%s fails=%d => %s" % [
		weak_deaths, strong_deaths, named_victim, forage_summer, forage_winter,
		chance_summer, chance_winter, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
