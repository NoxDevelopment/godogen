extends Node
## _probes/migration_probe.gd
## MIGRATION + REACHABILITY probe — under a deterministic auto-play policy the band
## REACHES the new-warren site and GROWS it to the target (WIN) on the base seed; a
## harsh (reckless) policy loses the band (LOSS). A seed-sweep shows BOTH outcomes
## occur, and EVERY run terminates under MAX_DAYS.

const BASE_SEED := 20260716


func _run(seed_value: int, policy: String) -> WarrenEngine:
	var e: WarrenEngine = WarrenEngine.new()
	e.setup(seed_value)
	e.auto_play_to_end(policy)
	return e


func _ready() -> void:
	var fails: int = 0
	var notes: Array = []

	# Base seed, balanced policy -> WIN (arrived + grown to target).
	var win_run: WarrenEngine = _run(BASE_SEED, "balanced")
	if not (win_run.is_win() and win_run.arrived and win_run.alive_count() >= win_run.target_pop()):
		fails += 1
		notes.append("no-win(out=%s arr=%s pop=%d)" % [win_run.outcome, str(win_run.arrived), win_run.alive_count()])

	# Base seed, reckless policy -> LOSS (band lost on the road).
	var loss_run: WarrenEngine = _run(BASE_SEED, "reckless")
	if not loss_run.is_loss():
		fails += 1
		notes.append("no-loss(out=%s)" % loss_run.outcome)

	# Seed sweep: both outcomes genuinely occur, and every run terminates.
	var bal_wins: int = 0
	var bal_losses: int = 0
	var rck_losses: int = 0
	var non_terminating: int = 0
	var max_day_seen: int = 0
	for s in range(1, 61):
		var seed_v: int = s * 101 + 7
		var bg: WarrenEngine = _run(seed_v, "balanced")
		if not bg.game_over:
			non_terminating += 1
		if bg.day > WarrenEngine.MAX_DAYS:
			non_terminating += 1
		max_day_seen = maxi(max_day_seen, bg.day)
		if bg.is_win():
			bal_wins += 1
		else:
			bal_losses += 1
		var rg: WarrenEngine = _run(seed_v, "reckless")
		if not rg.game_over:
			non_terminating += 1
		if rg.is_loss():
			rck_losses += 1

	if bal_wins <= 0:
		fails += 1
		notes.append("sweep-no-win")
	if bal_losses <= 0 and rck_losses <= 0:
		fails += 1
		notes.append("sweep-no-loss")
	if rck_losses <= 0:
		fails += 1
		notes.append("reckless-never-loses")
	if non_terminating > 0:
		fails += 1
		notes.append("non-terminating(%d)" % non_terminating)
	if max_day_seen > WarrenEngine.MAX_DAYS:
		fails += 1
		notes.append("over-max-days(%d)" % max_day_seen)

	print("DEBUG: migration_probe win_day=%d win_pop=%d loss=%s bal(w/l)=%d/%d rckL=%d maxday=%d notes=%s fails=%d => %s" % [
		win_run.day, win_run.alive_count(), str(loss_run.is_loss()),
		bal_wins, bal_losses, rck_losses, max_day_seen, str(notes), fails, ("OK" if fails == 0 else "FAIL")])
	get_tree().quit()
