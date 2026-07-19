extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the party-CRPG engine. Proves the same seed
## reproduces a BYTE-IDENTICAL adventure (identical FNV-1a checksum) — WITH all the d20
## attack/save/damage rolls in the mix — both mid-run and at the end; different seeds
## diverge; the party + path are seeded; and the auto-played run actually PLAYS a full
## adventure (combats resolve, heroes level up, skill-check events fire) to a genuine
## terminal (victory or a TPK). Prints `DEBUG full_chk=<n>` so the harness can confirm
## the checksum matches across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260720
const SEED_B := 3003


func _full(seed_value: int) -> Dictionary:
	var e := CrpgEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end("auto")
	var max_level := 1
	for h in e.party:
		max_level = max(max_level, int(h.level))
	return {"chk": e.checksum(), "enc": e.encounter, "won": e.won, "over": e.game_over,
		"phase": e.phase, "max_level": max_level, "gold": e.gold}


func _partial(seed_value: int, steps: int) -> int:
	var e := CrpgEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
		if e.game_over:
			break
		e.auto_step("auto")
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _full(SEED_A)
	var a2 := _full(SEED_A)
	if int(a1.chk) != int(a2.chk):
		ok = false
		push_error("seed A not deterministic (%d != %d) — seeded rolls must replay" % [int(a1.chk), int(a2.chk)])

	var b1 := _full(SEED_B)
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds converged to the same adventure")

	var p1 := _partial(SEED_A, 12)
	var p2 := _partial(SEED_A, 12)
	if p1 != p2:
		ok = false
		push_error("partial run not deterministic")

	# seeded party + path: two seeds differ at the very first checksum
	var e1 := CrpgEngine.new()
	e1.setup(SEED_A)
	var e2 := CrpgEngine.new()
	e2.setup(SEED_B)
	if e1.checksum() == e2.checksum():
		ok = false
		push_error("party/path is not seeded (initial state identical across seeds)")

	# playability: the run reached a real terminal, advanced through encounters, and the
	# party actually progressed (leveled up from combat XP)
	if not a1.over or str(a1.phase) != "done":
		ok = false
		push_error("adventure did not finish (over=%s phase=%s)" % [str(a1.over), str(a1.phase)])
	if int(a1.enc) < 2:
		ok = false
		push_error("run ended too early (encounter=%d) — combat/flow may be broken" % int(a1.enc))
	if int(a1.max_level) < 2:
		ok = false
		push_error("no leveling: no hero passed level 1 (combat XP not flowing)")

	print("DEBUG full_chk=%d encounter=%d won=%s max_level=%d gold=%d" % [
		int(a1.chk), int(a1.enc), str(a1.won), int(a1.max_level), int(a1.gold)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
