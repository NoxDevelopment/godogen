extends Node
## _probes/society_probe.gd
## SOCIETY probe — the roles confer REAL, measurable abilities, and the survival
## economy (needs / starvation / reproduction) behaves:
##   * a FORAGER gathers strictly MORE food than the same band without one,
##   * a SCOUT strictly LOWERS the ambush chance,
##   * a STORYTELLER strictly RAISES the morale a rest restores,
##   * a food deficit HARMS the band (starvation kills),
##   * a fed band with a breeding pair GROWS up to the population cap.

func _make() -> WarrenEngine:
	var e: WarrenEngine = WarrenEngine.new()
	e.setup(20260716)
	return e


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- FORAGER gathers measurably more -------------------------------------
	var fe: WarrenEngine = _make()
	var yield_with: int = fe.forage_yield_preview()
	fe.take_action(WarrenEngine.ACT_ASSIGN, WarrenEngine.FORAGER, WarrenEngine.FIGHTER)  # drop the forager
	var yield_without: int = fe.forage_yield_preview()
	if not (yield_with > yield_without):
		fails += 1
		notes.append("forager(%d<=%d)" % [yield_with, yield_without])

	# --- SCOUT lowers the ambush rate ----------------------------------------
	var se: WarrenEngine = _make()
	var chance_with: float = se.encounter_chance_preview(true)
	se.take_action(WarrenEngine.ACT_ASSIGN, WarrenEngine.SCOUT, WarrenEngine.FORAGER)  # drop the scout
	var chance_without: float = se.encounter_chance_preview(true)
	if not (chance_with < chance_without):
		fails += 1
		notes.append("scout(%.3f>=%.3f)" % [chance_with, chance_without])

	# --- STORYTELLER raises morale on rest -----------------------------------
	var te: WarrenEngine = _make()
	var gain_with: float = te.rest_morale_gain()
	te.take_action(WarrenEngine.ACT_ASSIGN, WarrenEngine.STORYTELLER, WarrenEngine.FORAGER)
	var gain_without: float = te.rest_morale_gain()
	if not (gain_with > gain_without):
		fails += 1
		notes.append("storyteller(%.1f<=%.1f)" % [gain_with, gain_without])

	# --- a food deficit HARMS the band (starvation kills) --------------------
	var he: WarrenEngine = _make()
	he.debug_add_food(-100000)  # empty the larder
	var guard: int = 0
	while not he.game_over and guard < 40:
		guard += 1
		he.take_action(WarrenEngine.ACT_SCOUT)  # pass days without healing
	if not (he.deaths_starvation > 0):
		fails += 1
		notes.append("starvation(%d)" % he.deaths_starvation)

	# --- a fed band with a breeding pair grows up to the cap -----------------
	var ge: WarrenEngine = WarrenEngine.new()
	ge.setup(20260716, {"target": WarrenEngine.POP_CAP})
	var pair_ok: bool = ge.has_breeding_pair()
	var start_pop: int = ge.alive_count()
	ge.debug_force_arrived()
	ge.debug_add_food(9000)
	ge.auto_play_to_end("balanced")
	if not pair_ok:
		fails += 1
		notes.append("no-breeding-pair")
	if not (ge.births > 0 and ge.alive_count() > start_pop and ge.alive_count() >= WarrenEngine.POP_CAP):
		fails += 1
		notes.append("growth(pop%d<-%d births%d)" % [ge.alive_count(), start_pop, ge.births])

	print("DEBUG: society_probe forager=%d/%d scout=%.3f/%.3f story=%.0f/%.0f starveD=%d grow=%d notes=%s fails=%d => %s" % [
		yield_with, yield_without, chance_with, chance_without, gain_with, gain_without,
		he.deaths_starvation, ge.alive_count(), str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
