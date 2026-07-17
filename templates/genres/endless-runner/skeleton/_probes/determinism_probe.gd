extends Node
## DETERMINISM + PLAYABILITY probe for the endless-runner engine. Same seed → byte-identical run
## (checksum) mid-run + at the end; different seeds lay out a different track; and the dodge AI
## runs a REAL long distance, dodging seeded obstacles + grabbing coins, to a genuine terminal
## (a crash or surviving the distance cap). Prints DEBUG full_chk=<n> for cross-process checks.
const SEED_A := 20260717
const SEED_B := 6789
func _run(sv:int)->Dictionary:
	var e:=RunnerEngine.new(); e.setup(sv); e.auto_play_to_end()
	return {"chk":e.checksum(),"dist":e.distance,"coins":e.coins,"score":e.score(),"survived":e.survived,"crash":e.crashed_on,"over":e.game_over}
func _partial(sv:int,n:int)->int:
	var e:=RunnerEngine.new(); e.setup(sv)
	for _i in range(n):
		if e.game_over: break
		e.auto_step()
	return e.checksum()
func _ready()->void:
	var ok:=true
	var a1:=_run(SEED_A); var a2:=_run(SEED_A)
	if int(a1.chk)!=int(a2.chk): ok=false; push_error("seed A not deterministic (%d != %d)"%[int(a1.chk),int(a2.chk)])
	var b1:=_run(SEED_B)
	if int(a1.chk)==int(b1.chk): ok=false; push_error("different seeds produced the same track")
	var p1:=_partial(SEED_A,300); var p2:=_partial(SEED_A,300)
	if p1!=p2: ok=false; push_error("partial run not deterministic")
	if not a1.over: ok=false; push_error("run did not end")
	if float(a1.dist)<800.0: ok=false; push_error("run too short (%.0fm) — dodge/spawn may be broken"%float(a1.dist))
	if int(a1.coins)<=0: ok=false; push_error("no coins collected")
	print("DEBUG full_chk=%d dist=%.0f coins=%d score=%d survived=%s crash=%s"%[int(a1.chk),float(a1.dist),int(a1.coins),int(a1.score),str(a1.survived),str(a1.crash)])
	print("PROBE %s"%("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
