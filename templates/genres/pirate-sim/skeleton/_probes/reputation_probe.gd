extends Node
## _probes/reputation_probe.gd
## REPUTATION probe: attacking a nation's ship lowers its standing and lifts its
## sworn enemy's; a Letter of Marque sanctions privateering against the enemy (patron
## gains, no piracy penalty), and raiding your own patron voids the marque; the marque
## offer/accept is gated by standing.

func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# --- 1) unsanctioned raid: flag down, sworn enemy up, others ~unchanged ---
	var e: PirateEngine = PirateEngine.new()
	e.setup(20260715)
	var crown0: float = float(e.reputation["Crown"])
	var empire0: float = float(e.reputation["Empire"])
	var repub0: float = float(e.reputation["Republic"])
	e._apply_attack_reputation("Crown", 12.0)
	if float(e.reputation["Crown"]) >= crown0:
		fails += 1
		notes.append("crown-not-lowered")
	if float(e.reputation["Empire"]) <= empire0:   ## Empire is Crown's enemy -> pleased.
		fails += 1
		notes.append("empire-not-raised")
	if not is_equal_approx(float(e.reputation["Republic"]), repub0):
		fails += 1
		notes.append("republic-moved")

	# --- 2) marque sanctions attacks on the patron's enemy ---
	var e2: PirateEngine = PirateEngine.new()
	e2.setup(20260715)
	e2.marque = "Crown"
	var crown_b: float = float(e2.reputation["Crown"])
	var empire_b: float = float(e2.reputation["Empire"])
	e2._apply_attack_reputation("Empire", 12.0)   ## Empire is Crown's sworn enemy.
	if float(e2.reputation["Crown"]) <= crown_b:
		fails += 1
		notes.append("marque-patron-not-rewarded")
	if float(e2.reputation["Empire"]) >= empire_b:
		fails += 1
		notes.append("marque-target-not-lowered")
	if e2.marque != "Crown":
		fails += 1
		notes.append("marque-lost-wrongly")

	# --- 3) raiding your own patron voids the marque ---
	var e3: PirateEngine = PirateEngine.new()
	e3.setup(20260715)
	e3.marque = "Crown"
	e3._apply_attack_reputation("Crown", 12.0)
	if e3.marque != "":
		fails += 1
		notes.append("patron-raid-kept-marque")

	# --- 4) marque offer/accept gated by standing ---
	var e4: PirateEngine = PirateEngine.new()
	e4.setup(20260715)
	e4.reputation["Republic"] = 5.0
	if e4.accept_marque("Republic"):               ## too low -> must be rejected.
		fails += 1
		notes.append("low-rep-marque-accepted")
	e4.reputation["Republic"] = e4.MARQUE_REP + 5.0
	if not e4.accept_marque("Republic"):
		fails += 1
		notes.append("high-rep-marque-rejected")

	# --- 5) very low standing makes a nation's ports hostile ---
	var e5: PirateEngine = PirateEngine.new()
	e5.setup(20260715)
	var target_nation: String = String(e5.ports[0]["nation"])
	e5.reputation[target_nation] = e5.HOSTILE_REP - 10.0
	if not e5.port_hostile(0):
		fails += 1
		notes.append("hostile-gate-broken")

	print("DEBUG: reputation_probe crown=%.1f empire=%.1f notes=%s fails=%d => %s" % [
		float(e.reputation["Crown"]), float(e.reputation["Empire"]), str(notes), fails,
		("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
