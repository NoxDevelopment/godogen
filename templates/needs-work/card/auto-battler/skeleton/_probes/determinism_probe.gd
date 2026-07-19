extends Node
## _probes/determinism_probe.gd
## DETERMINISM + PLAYABILITY probe for the auto-battler engine. Proves the same seed reproduces a
## BYTE-IDENTICAL run (identical FNV-1a checksum) mid-run and at the end; different seeds roll a
## different shop + waves; and the shop AI drafts teams and AUTO-BATTLES a real run — winning
## trophies against escalating waves — to a genuine terminal (a win at the trophy target or a loss
## when out of lives). Prints `DEBUG full_chk=<n>` so the harness can confirm the checksum matches
## across two SEPARATE PROCESSES.
## Run: godot --headless --path <skeleton> res://_probes/determinism_probe.tscn

const SEED_A := 20260717
const SEED_B := 1357


func _run(seed_value: int) -> Dictionary:
	var e := AutoBattlerEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end()
	return {"chk": e.checksum(), "won": e.won, "round": e.round_no, "trophies": e.trophies,
		"lives": e.lives, "team": e.team.size(), "over": e.game_over}


func _partial(seed_value: int, steps: int) -> int:
	var e := AutoBattlerEngine.new()
	e.setup(seed_value)
	for _i in range(steps):
		if e.game_over:
			break
		e.auto_step()
	return e.checksum()


func _ready() -> void:
	var ok := true

	var a1 := _run(SEED_A)
	var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk):
		ok = false
		push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])

	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk):
		ok = false
		push_error("different seeds produced the same run")

	var p1 := _partial(SEED_A, 4)
	var p2 := _partial(SEED_A, 4)
	if p1 != p2:
		ok = false
		push_error("partial run not deterministic")

	# playability: the AI reached a terminal and won at least a few rounds (drafting + combat work)
	if not a1.over:
		ok = false
		push_error("run did not reach a terminal")
	if int(a1.trophies) < 2:
		ok = false
		push_error("too few trophies won (%d) — drafting/combat may be broken" % int(a1.trophies))

	print("DEBUG full_chk=%d won=%s round=%d trophies=%d lives=%d team=%d" % [
		int(a1.chk), str(a1.won), int(a1.round), int(a1.trophies), int(a1.lives), int(a1.team)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
