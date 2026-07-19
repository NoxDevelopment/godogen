extends Node
## DETERMINISM + PLAYABILITY probe for the horde auto-battler engine. Same seed → byte-identical
## run (checksum) mid-run + at the end; different seeds build different enemy waves; and the greedy
## commander plays a REAL run — recruiting a growing horde and auto-battling scaling enemy waves —
## to a genuine terminal (clearing all waves, or a wipe). Prints DEBUG full_chk=<n> for cross-process
## checks.
const SEED_A := 20260717
const SEED_B := 99
func _run(sv: int) -> Dictionary:
	var e := HordeEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk": e.checksum(), "wave": e.wave, "army": e.army_size(), "power": e.army_power(),
		"won": e.won, "over": e.game_over}
func _partial(sv: int, n: int) -> int:
	var e := HordeEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.game_over: break
		e.ai_round()
	return e.checksum()
func _ready() -> void:
	var ok := true
	var a1 := _run(SEED_A); var a2 := _run(SEED_A)
	if int(a1.chk) != int(a2.chk): ok = false; push_error("seed A not deterministic (%d != %d)" % [int(a1.chk), int(a2.chk)])
	var b1 := _run(SEED_B)
	if int(a1.chk) == int(b1.chk): ok = false; push_error("different seeds produced the same run")
	var p1 := _partial(SEED_A, 6); var p2 := _partial(SEED_A, 6)
	if p1 != p2: ok = false; push_error("partial run not deterministic")
	if not bool(a1.over): ok = false; push_error("run did not end")
	if not bool(a1.won): ok = false; push_error("commander did not clear the waves (reached wave %d)" % int(a1.wave))
	# the "how many dudes" snowball should produce a large surviving horde
	if int(a1.army) < 30: ok = false; push_error("horde too small (%d) — the snowball may be broken" % int(a1.army))
	print("DEBUG full_chk=%d wave=%d army=%d power=%d won=%s" % [
		int(a1.chk), int(a1.wave), int(a1.army), int(a1.power), str(a1.won)])
	print("PROBE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
