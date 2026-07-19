extends Node3D
## res://scripts/main.gd
## Dungeon shell: spawns one enemy per 'E' map cell, routes dungeon/party
## messages into the HUD log, tracks kills + the secret-found flag, and opens
## the run summary when the whole party falls. Also hosts the boot probe
## proving the loop headless: a real step + turn changed cell/facing, the
## locked door refused a bump then opened on a key fetched from the key room,
## the lever opened the secret wall (walked through to prove it), an enemy
## approached across cells on its own timers and melee'd the front row, a
## member attack button killed it, and a picked-up potion healed the wounded
## member — every beat through the same public routines gameplay uses.

const EnemyScript := preload("res://scripts/enemy.gd")

var kills := 0
var secret_found := false

var _run_over := false

@onready var _dungeon: Node3D = $Dungeon
@onready var _party: Node3D = $Party
@onready var _enemies: Node3D = $Enemies
@onready var _hud: CanvasLayer = $HUD
@onready var _summary: CanvasLayer = $RunSummary


func _ready() -> void:
	_dungeon.message.connect(_hud.add_message)
	_dungeon.secret_opened.connect(_on_secret_opened)
	_party.party_defeated.connect(_on_party_defeated)
	for cell in _dungeon.enemy_cells():
		spawn_enemy(cell)

	_emit_boot_probe.call_deferred()


## The single entry point for enemies — probe spawns and level design both
## come through here, so every death is a tracked kill.
func spawn_enemy(cell: Vector2i) -> Node3D:
	var enemy: Node3D = EnemyScript.new()
	enemy.setup(_dungeon, cell)
	enemy.died.connect(_on_enemy_died)
	_enemies.add_child(enemy)
	return enemy


func _on_enemy_died(enemy: Node3D) -> void:
	kills += 1
	_hud.add_message("The %s is destroyed!" % enemy.enemy_name)
	_hud.set_kills(kills)


func _on_secret_opened(_cell: Vector2i) -> void:
	secret_found = true
	GameManager.set_flag("secret_found")


func _on_party_defeated() -> void:
	if _run_over:
		return
	_run_over = true
	var best_kills := maxi(int(GameManager.get_flag("best_kills", 0)), kills)
	GameManager.set_flag("last_run", {"kills": kills, "secret_found": secret_found})
	GameManager.set_flag("best_kills", best_kills)
	get_tree().paused = true
	_summary.show_result(kills, best_kills, secret_found)


func _emit_boot_probe() -> void:
	for i in 4:
		await get_tree().physics_frame

	# Freeze every spawned enemy and compress the rate-independent timings
	# (tween lengths, cooldowns, the bump-message guard) so the whole loop
	# fits in the 120-frame boot window. No RNG anywhere — runs are fully
	# deterministic.
	for enemy in _enemies.get_children():
		enemy.active = false
	var normal_step: float = _party.step_time
	var normal_turn: float = _party.turn_time
	_party.step_time = 0.03
	_party.turn_time = 0.03
	_party.cooldown_scale = 0.05

	# 1. Grid step + turn: from the '@' start (2,2) facing N, turn right to
	# E and take one real tweened step — cell and facing must both change.
	var start_cell: Vector2i = _party.cell
	var start_facing: String = _party.facing_name()
	_party.turn(1)
	await _party_idle()
	_party.try_step(0)
	await _party_idle()
	var step_turn := "(%d,%d)%s->(%d,%d)%s" % [
		start_cell.x, start_cell.y, start_facing,
		_party.cell.x, _party.cell.y, _party.facing_name(),
	]

	# 2. Locked-door bump without the key: walking into 'D' at (5,2) must
	# refuse (door stays closed, party stays put).
	_party.warp_to(Vector2i(4, 2), 1)
	_party.try_step(0)
	await get_tree().physics_frame
	var locked_bump: bool = not _dungeon.is_open(Vector2i(5, 2)) \
			and _party.cell == Vector2i(4, 2)

	# 3. Fetch the key: step onto the key cell in the key room — the arrival
	# collect is the same path every pickup uses.
	_party.warp_to(Vector2i(3, 8), 3)
	_party.try_step(0)
	await _party_idle()
	var key_picked: bool = _party.keys == 1 and _party.cell == Vector2i(2, 8)

	# 4. Back to the locked door with the key: the bump consumes it and the
	# door opens — then walk through the doorway to prove passage.
	_party.warp_to(Vector2i(4, 2), 1)
	_party.try_step(0)
	for i in 6:
		await get_tree().physics_frame
	_party.try_step(0)
	await _party_idle()
	var locked_door: bool = _dungeon.is_open(Vector2i(5, 2)) \
			and _party.keys == 0 and _party.cell == Vector2i(5, 2)

	# 5. The lever opens the secret wall: interact() pulls the lever in the
	# cell ahead, then walk through where the wall stood.
	_party.warp_to(Vector2i(10, 2), 1)
	var lever_ok: bool = _party.interact()
	var lever_secret: bool = lever_ok and _dungeon.is_open(Vector2i(7, 4))
	_party.warp_to(Vector2i(7, 5), 0)
	_party.try_step(0)
	await _party_idle()
	var secret_walk: bool = _party.cell == Vector2i(7, 4)

	# 6. Enemy pressure: wake the secret-room skeleton at (8,8) on compressed
	# timers — it must walk cells toward the party on its own and melee the
	# front row (Aiden soaks it: front/back row semantics).
	_party.warp_to(Vector2i(8, 6), 2)
	var brute: Node3D = _dungeon.occupant(Vector2i(8, 8))
	brute.move_interval = 0.05
	brute.attack_interval = 0.05
	brute.active = true
	var hp_before: int = _party.members[0]["hp"]
	var melee_front := ""
	for i in 60:
		if _party.members[0]["hp"] < hp_before:
			melee_front = "%s:%d->%d" % [
				_party.members[0]["name"], hp_before, _party.members[0]["hp"],
			]
			break
		await get_tree().physics_frame
	brute.active = false

	# 7. Kill it with the front member's attack button (the exact routine
	# the portrait button and hotkey 1 call) — 3 swings at 12 damage.
	var attack_kill := false
	for i in 80:
		if not is_instance_valid(brute):
			attack_kill = true
			break
		_party.attack(0)
		await get_tree().physics_frame

	# 8. Potion: step onto the secret room's potion, then drink — it must
	# heal the member with the lowest HP (Aiden, who took the melee).
	_party.warp_to(Vector2i(8, 6), 3)
	_party.try_step(0)
	await _party_idle()
	var hp_hurt: int = _party.members[0]["hp"]
	_party.use_potion()
	var potion_heal := "%s:%d->%d" % [
		_party.members[0]["name"], hp_hurt, _party.members[0]["hp"],
	]

	# Hand the dungeon back: surviving enemies wake, timings restore, and the
	# party returns to the start (world state — open doors, used key, pulled
	# lever — stays, exactly as it would for a player).
	_party.step_time = normal_step
	_party.turn_time = normal_turn
	_party.cooldown_scale = 1.0
	for enemy in _enemies.get_children():
		if is_instance_valid(enemy):
			enemy.active = true
	_party.warp_to(_dungeon.start_cell, 0)

	print("DEBUG: dungeon-crawler-classic core loop ready — step_turn=%s locked_bump=%s key_picked=%s locked_door=%s lever_secret=%s secret_walk=%s melee_front=%s attack_kill=%s potion_heal=%s kills=%d" % [
		step_turn, locked_bump, key_picked, locked_door, lever_secret,
		secret_walk, melee_front, attack_kill, potion_heal, kills,
	])


func _party_idle() -> void:
	for i in 30:
		if not _party.is_busy():
			return
		await get_tree().physics_frame
