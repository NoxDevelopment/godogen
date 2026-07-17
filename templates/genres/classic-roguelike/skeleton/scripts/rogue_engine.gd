class_name RogueEngine
extends RefCounted
## Pure, seedable CLASSIC-ROGUELIKE engine — procedural dungeon (rooms + corridors),
## turn-based bump-combat, monster AI, items, descent, and permadeath. Node-free and
## Time-free: a single private RNG drives everything, so the SAME seed reproduces a
## BYTE-IDENTICAL run (FNV-1a checksum) across processes. The scene (dungeon.gd) and
## GameManager wrap this; all rules + state live here (the NoxDev pure-engine ABI).

const W := 40
const H := 22
const MAX_DEPTH := 8
const TURN_CAP := 4000          ## safety bound for auto_play_to_end

const WALL := 0
const FLOOR := 1
const STAIRS := 2

var rng := RandomNumberGenerator.new()
var depth := 1
var turn := 0
var game_over := false
var won := false
var grid: PackedByteArray = PackedByteArray()
var seen: PackedByteArray = PackedByteArray()      ## explored tiles (fog of war)
var player: Dictionary = {}
var monsters: Array = []                           ## [{x,y,hp,atk,name}]
var items: Array = []                              ## [{x,y,kind}]  kind: "gold"|"potion"
var log_lines: Array = []

const MONSTER_TABLE := [
	{"name": "rat", "hp": 4, "atk": 2},
	{"name": "kobold", "hp": 7, "atk": 3},
	{"name": "orc", "hp": 12, "atk": 5},
	{"name": "wraith", "hp": 18, "atk": 7},
]

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	depth = 1
	turn = 0
	game_over = false
	won = false
	player = {"x": 0, "y": 0, "hp": 24, "max_hp": 24, "atk": 5, "def": 1,
		"gold": 0, "potions": 1, "xp": 0, "level": 1}
	log_lines = []
	_gen_level()

func _idx(x: int, y: int) -> int:
	return y * W + x

func tile(x: int, y: int) -> int:
	if x < 0 or x >= W or y < 0 or y >= H:
		return WALL
	return grid[_idx(x, y)]

func is_walkable(x: int, y: int) -> bool:
	return tile(x, y) != WALL

# --------------------------------------------------------------------------- #
# Procedural level generation (rooms + corridors) — seeded
# --------------------------------------------------------------------------- #

func _gen_level() -> void:
	grid = PackedByteArray()
	grid.resize(W * H)
	seen = PackedByteArray()
	seen.resize(W * H)
	for i in range(W * H):
		grid[i] = WALL
		seen[i] = 0
	monsters = []
	items = []

	var rooms: Array = []
	var attempts := 30 + depth * 4
	for _a in range(attempts):
		if rooms.size() >= 9:
			break
		var rw := rng.randi_range(4, 8)
		var rh := rng.randi_range(3, 6)
		var rx := rng.randi_range(1, W - rw - 2)
		var ry := rng.randi_range(1, H - rh - 2)
		var overlaps := false
		for r in rooms:
			if rx - 1 <= r.x + r.w and rx + rw + 1 >= r.x and ry - 1 <= r.y + r.h and ry + rh + 1 >= r.y:
				overlaps = true
				break
		if overlaps:
			continue
		for yy in range(ry, ry + rh):
			for xx in range(rx, rx + rw):
				grid[_idx(xx, yy)] = FLOOR
		rooms.append({"x": rx, "y": ry, "w": rw, "h": rh, "cx": rx + rw / 2, "cy": ry + rh / 2})

	# connect each room to the previous one with an L-corridor
	for i in range(1, rooms.size()):
		_carve_corridor(rooms[i - 1].cx, rooms[i - 1].cy, rooms[i].cx, rooms[i].cy)

	if rooms.is_empty():
		# degenerate seed — carve a single fallback room
		for yy in range(H / 2 - 2, H / 2 + 2):
			for xx in range(2, W - 2):
				grid[_idx(xx, yy)] = FLOOR
		rooms.append({"x": 2, "y": H / 2, "w": 4, "h": 4, "cx": 4, "cy": H / 2})

	# player in first room, stairs in last
	player.x = rooms[0].cx
	player.y = rooms[0].cy
	var last: Dictionary = rooms[rooms.size() - 1]
	grid[_idx(last.cx, last.cy)] = STAIRS

	# populate: monsters + items in rooms after the first
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		var n_mon := 1 + rng.randi_range(0, 1 + depth / 2)
		for _m in range(n_mon):
			var mx := rng.randi_range(r.x, r.x + r.w - 1)
			var my := rng.randi_range(r.y, r.y + r.h - 1)
			if _occupied(mx, my) or (mx == player.x and my == player.y):
				continue
			var tier := clampi(rng.randi_range(0, depth - 1), 0, MONSTER_TABLE.size() - 1)
			var base: Dictionary = MONSTER_TABLE[tier]
			monsters.append({"x": mx, "y": my, "hp": base.hp + depth, "atk": base.atk, "name": base.name})
		if rng.randf() < 0.6:
			var ix := rng.randi_range(r.x, r.x + r.w - 1)
			var iy := rng.randi_range(r.y, r.y + r.h - 1)
			if not _occupied(ix, iy):
				items.append({"x": ix, "y": iy, "kind": "potion" if rng.randf() < 0.4 else "gold"})

	_reveal_fov()

func _carve_corridor(x0: int, y0: int, x1: int, y1: int) -> void:
	var x := x0
	var y := y0
	while x != x1:
		grid[_idx(x, y)] = FLOOR if grid[_idx(x, y)] != STAIRS else STAIRS
		x += 1 if x1 > x else -1
	while y != y1:
		grid[_idx(x, y)] = FLOOR if grid[_idx(x, y)] != STAIRS else STAIRS
		y += 1 if y1 > y else -1

func _occupied(x: int, y: int) -> bool:
	for m in monsters:
		if m.x == x and m.y == y:
			return true
	return false

func _monster_at(x: int, y: int) -> int:
	for i in range(monsters.size()):
		if monsters[i].x == x and monsters[i].y == y:
			return i
	return -1

# --------------------------------------------------------------------------- #
# FOV — cheap radius reveal (permanent memory of seen tiles)
# --------------------------------------------------------------------------- #

func _reveal_fov(radius: int = 6) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x: int = player.x + dx
			var y: int = player.y + dy
			if x >= 0 and x < W and y >= 0 and y < H:
				seen[_idx(x, y)] = 1

# --------------------------------------------------------------------------- #
# Turn resolution — the core loop
# --------------------------------------------------------------------------- #

## action: "up"|"down"|"left"|"right"|"wait"|"quaff"|"descend"
func step(action: String) -> void:
	if game_over:
		return
	turn += 1
	match action:
		"quaff":
			_quaff()
		"descend":
			_try_descend()
		"wait":
			pass
		_:
			_player_move(action)
	if not game_over:
		_monsters_act()
	if player.hp <= 0:
		player.hp = 0
		game_over = true

func _dir(action: String) -> Vector2i:
	match action:
		"up": return Vector2i(0, -1)
		"down": return Vector2i(0, 1)
		"left": return Vector2i(-1, 0)
		"right": return Vector2i(1, 0)
	return Vector2i.ZERO

func _player_move(action: String) -> void:
	var d := _dir(action)
	if d == Vector2i.ZERO:
		return
	var nx: int = player.x + d.x
	var ny: int = player.y + d.y
	var mi := _monster_at(nx, ny)
	if mi >= 0:
		_attack_monster(mi)
		return
	if is_walkable(nx, ny):
		player.x = nx
		player.y = ny
		_pickup(nx, ny)
		if tile(nx, ny) == STAIRS:
			_try_descend()
		_reveal_fov()

func _attack_monster(mi: int) -> void:
	var m: Dictionary = monsters[mi]
	var dmg: int = maxi(1, player.atk - 0 + rng.randi_range(0, 2))
	m.hp -= dmg
	_log("You hit the %s for %d." % [m.name, dmg])
	if m.hp <= 0:
		_log("The %s dies." % m.name)
		player.xp += 3 + depth
		monsters.remove_at(mi)
		_maybe_level_up()

func _maybe_level_up() -> void:
	var need: int = player.level * 12
	if player.xp >= need:
		player.xp -= need
		player.level += 1
		player.max_hp += 4
		player.hp = player.max_hp
		player.atk += 1
		_log("You reach level %d!" % player.level)

func _pickup(x: int, y: int) -> void:
	for i in range(items.size()):
		if items[i].x == x and items[i].y == y:
			if items[i].kind == "gold":
				var g := rng.randi_range(3, 8) + depth
				player.gold += g
				_log("You find %d gold." % g)
			else:
				player.potions += 1
				_log("You find a potion.")
			items.remove_at(i)
			return

func _quaff() -> void:
	if player.potions <= 0:
		_log("No potions.")
		return
	player.potions -= 1
	var heal: int = 10 + int(player.level) * 2
	player.hp = mini(player.max_hp, player.hp + heal)
	_log("You quaff a potion (+%d HP)." % heal)

func _try_descend() -> void:
	if tile(player.x, player.y) != STAIRS:
		return
	if depth >= MAX_DEPTH:
		won = true
		game_over = true
		_log("You escape the dungeon with %d gold. You win!" % player.gold)
		return
	depth += 1
	_log("You descend to depth %d." % depth)
	_gen_level()

func _monsters_act() -> void:
	for m in monsters:
		var dx: int = signi(player.x - m.x)
		var dy: int = signi(player.y - m.y)
		if abs(player.x - m.x) + abs(player.y - m.y) == 1:
			# adjacent → attack
			var dmg: int = maxi(1, m.atk - player.def + rng.randi_range(0, 1))
			player.hp -= dmg
			_log("The %s hits you for %d." % [m.name, dmg])
		else:
			# step toward the player (prefer the larger axis), avoid stacking
			var order := [Vector2i(dx, 0), Vector2i(0, dy)] if abs(player.x - m.x) >= abs(player.y - m.y) else [Vector2i(0, dy), Vector2i(dx, 0)]
			for step_v in order:
				if step_v == Vector2i.ZERO:
					continue
				var nx: int = m.x + step_v.x
				var ny: int = m.y + step_v.y
				if is_walkable(nx, ny) and not _occupied(nx, ny) and not (nx == player.x and ny == player.y):
					m.x = nx
					m.y = ny
					break

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 40:
		log_lines.remove_at(0)

# --------------------------------------------------------------------------- #
# Deterministic auto-play (for the probe / an AI seat)
# --------------------------------------------------------------------------- #

## A greedy policy with real navigation: quaff when low, clear the nearest REACHABLE
## monster (bump-attack), else route to the stairs and descend. Pathing is BFS over
## walkable tiles (routing around walls and other monsters), so the seat makes real
## progress and the run reaches a genuine win/death instead of stalling. Fully
## deterministic (no RNG, fixed neighbour order) — the same seed replays identically.
func auto_step(_policy: String = "greedy") -> void:
	if game_over:
		return
	if player.hp <= player.max_hp / 4 and player.potions > 0:
		step("quaff")
		return
	var act := ""
	var target := _nearest_monster()
	if target.x >= 0:
		act = _nav_step(target)            # ends by bumping (attacking) the monster
	if act == "":
		act = _nav_step(_find_stairs())    # nothing to fight → head down
	if act == "":
		step("wait")                       # fully boxed in — burn a turn
		return
	step(act)

func auto_play_to_end(policy: String = "greedy") -> void:
	var guard := 0
	while not game_over and guard < TURN_CAP:
		auto_step(policy)
		guard += 1
	if not game_over:
		game_over = true    ## bounded — treat as a stall

func _nearest_monster() -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for m in monsters:
		var d: int = abs(m.x - player.x) + abs(m.y - player.y)
		if d < bd:
			bd = d
			best = Vector2i(m.x, m.y)
	return best

func _find_stairs() -> Vector2i:
	for y in range(H):
		for x in range(W):
			if grid[_idx(x, y)] == STAIRS:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## BFS shortest-path first step from the player to `goal` over walkable tiles. Other
## monsters are impassable (routed around); the goal tile itself is always allowed so
## a path can END on a monster (the returned step bump-attacks it) or on the stairs
## (returns "descend" when already standing on them). "" means the goal is unreachable.
func _nav_step(goal: Vector2i) -> String:
	if goal.x < 0:
		return ""
	var px: int = player.x
	var py: int = player.y
	if px == goal.x and py == goal.y:
		return "descend" if tile(px, py) == STAIRS else "wait"
	var goal_k: int = goal.y * W + goal.x
	var blocked := {}
	for m in monsters:
		if m.x != goal.x or m.y != goal.y:
			blocked[m.y * W + m.x] = true
	var start_k: int = py * W + px
	var came := {}
	var queue: Array = [start_k]
	var visited := {start_k: true}
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var found := false
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		if cur == goal_k:
			found = true
			break
		var cx: int = cur % W
		var cy: int = cur / W
		for d in dirs:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or nx >= W or ny < 0 or ny >= H:
				continue
			var nk: int = ny * W + nx
			if visited.has(nk):
				continue
			if tile(nx, ny) == WALL:
				continue
			if blocked.has(nk):
				continue
			visited[nk] = true
			came[nk] = cur
			queue.append(nk)
	if not found:
		return ""
	# walk the predecessor chain back to the tile adjacent to the player
	var first: int = goal_k
	while came.has(first) and came[first] != start_k:
		first = came[first]
	if not came.has(first):
		return ""
	var fx: int = first % W
	var fy: int = first / W
	if fx > px:
		return "right"
	if fx < px:
		return "left"
	if fy > py:
		return "down"
	return "up"

# --------------------------------------------------------------------------- #
# Determinism checksum (FNV-1a over the full state) + save/load ABI
# --------------------------------------------------------------------------- #

func checksum() -> int:
	var h := 1469598103934665603
	var mask := (1 << 63) - 1
	# fold the state into a string, then FNV-1a the bytes
	var s := "%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [depth, turn, int(game_over), int(won),
		player.x, player.y, player.hp, player.gold, player.level, player.potions]
	for m in monsters:
		s += "|m%d,%d,%d" % [m.x, m.y, m.hp]
	for it in items:
		s += "|i%d,%d" % [it.x, it.y]
	for b in grid:
		h = (h ^ int(b)) & mask
		h = (h * 1099511628211) & mask
	for c in s.to_utf8_buffer():
		h = (h ^ int(c)) & mask
		h = (h * 1099511628211) & mask
	return h

func save_data() -> Dictionary:
	return {
		"seed": rng.seed, "depth": depth, "turn": turn,
		"game_over": game_over, "won": won,
		"player": player.duplicate(true),
		"monsters": monsters.duplicate(true),
		"items": items.duplicate(true),
		"grid": grid, "seen": seen,
	}

func load_data(d: Dictionary) -> void:
	rng.seed = int(d.get("seed", 0))
	depth = int(d.get("depth", 1))
	turn = int(d.get("turn", 0))
	game_over = bool(d.get("game_over", false))
	won = bool(d.get("won", false))
	player = (d.get("player", {}) as Dictionary).duplicate(true)
	monsters = (d.get("monsters", []) as Array).duplicate(true)
	items = (d.get("items", []) as Array).duplicate(true)
	grid = d.get("grid", PackedByteArray())
	seen = d.get("seen", PackedByteArray())
