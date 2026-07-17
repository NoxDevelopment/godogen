extends Node2D
## res://scripts/crpg_view.gd
## The playable party-CRPG screen — renders GameManager's CrpgEngine (party + enemy stat
## blocks with HP, the initiative-active actor, the combat log, and encounter progress)
## and turns input into commands. All rules live in CrpgEngine; this is presentation +
## input only. On a hero's combat turn: click an enemy to attack it (wizard auto-picks
## fireball vs a crowd / magic missile on one; martials strike) · H cleric heals the most
## wounded · F wizard fireball · D defend. Space resolves an event or advances. A auto-plays
## the whole run · R restarts. Enemy turns resolve automatically.

var eng: CrpgEngine
var _auto_accum := 0.0
var party_box: Array = []      ## screen rects per party index
var enemy_box: Array = []      ## {id, rect}

func _ready() -> void:
	eng = GameManager.engine
	GameManager.resolve_ai_turns()
	set_process(true)

func _process(delta: float) -> void:
	if eng == null:
		return
	if GameManager.party_auto and not eng.game_over:
		_auto_accum += delta
		if _auto_accum >= 0.12:
			_auto_accum = 0.0
			GameManager.auto_step()
			queue_redraw()
		return
	# resolve any pending enemy turns so we always rest on a player decision
	if eng.in_combat:
		var a := eng.actor_at_ptr()
		if not a.is_empty() and int(a.side) == 1:
			GameManager.resolve_ai_turns()
			queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if eng == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(event.position)
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER:
				if eng.phase == "event":
					GameManager.continue_explore()
			KEY_A:
				GameManager.party_auto = not GameManager.party_auto
			KEY_R:
				GameManager.new_game()
				eng = GameManager.engine
				GameManager.resolve_ai_turns()
			KEY_H: _hero_spell("cure_wounds")
			KEY_F: _hero_spell("fireball")
			KEY_B: _hero_spell("bless")
			KEY_D:
				if _is_player_turn():
					eng.act_defend()
					GameManager.resolve_ai_turns()
		queue_redraw()

func _is_player_turn() -> bool:
	if not eng.in_combat or eng.game_over or GameManager.party_auto:
		return false
	var a := eng.actor_at_ptr()
	return not a.is_empty() and int(a.side) == 0

func _on_click(pos: Vector2) -> void:
	if not _is_player_turn():
		return
	for eb in enemy_box:
		if (eb.rect as Rect2).has_point(pos):
			var actor := eng.actor_at_ptr()
			if str(actor.cls) == "wizard" and int(actor.slots) > 0:
				if eng.alive_enemies().size() >= 3:
					eng.act_spell("fireball", 0)
				else:
					eng.act_spell("magic_missile", int(eb.id))
			else:
				eng.act_attack(int(eb.id))
			GameManager.resolve_ai_turns()
			return

func _hero_spell(spell: String) -> void:
	if not _is_player_turn():
		return
	var actor := eng.actor_at_ptr()
	var ok := false
	if spell == "cure_wounds" and str(actor.cls) == "cleric":
		ok = eng.act_spell("cure_wounds", -1)
	elif spell == "bless" and str(actor.cls) == "cleric":
		ok = eng.act_spell("bless", 0)
	elif spell == "fireball" and str(actor.cls) == "wizard":
		ok = eng.act_spell("fireball", 0)
	if ok:
		GameManager.resolve_ai_turns()

# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if eng == null:
		return
	var font := ThemeDB.fallback_font
	var active := eng.actor_at_ptr() if eng.in_combat else {}
	var active_id: int = int(active.id) if not active.is_empty() else -1
	# header
	draw_string(font, Vector2(24, 30), "Encounter %d/%d   phase: %s   gold %d   %s" % [
		min(eng.encounter + 1, eng.path.size()), eng.path.size(), eng.phase, eng.gold,
		("AUTO" if GameManager.party_auto else "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	# party (left)
	party_box = []
	for i in range(eng.party.size()):
		var h: Dictionary = eng.party[i]
		var r := Rect2(24, 60 + i * 74, 360, 66)
		party_box.append(r)
		_draw_actor(font, r, "%s  L%d" % [str(h.cls).capitalize(), int(h.level)],
			int(h.hp), int(h.max_hp), Color(0.40, 0.66, 1.0), bool(h.alive), int(h.id) == active_id,
			"slots %d/%d%s" % [int(h.slots), int(h.max_slots), ("  BLESS" if int(h.blessed) > 0 else "")])
	# enemies (right)
	enemy_box = []
	for i in range(eng.enemies.size()):
		var e: Dictionary = eng.enemies[i]
		var r := Rect2(896, 60 + i * 60, 360, 52)
		enemy_box.append({"id": int(e.id), "rect": r})
		var col: Color = Color(1.0, 0.55, 0.30) if bool(e.boss) else Color(1.0, 0.46, 0.42)
		_draw_actor(font, r, str(e.name).capitalize() + ("  (BOSS)" if bool(e.boss) else ""),
			int(e.hp), int(e.max_hp), col, bool(e.alive), int(e.id) == active_id, "AC %d" % int(e.ac))
	# event / prompt
	if eng.phase == "event" and eng.encounter < eng.path.size():
		var ev: Dictionary = eng.path[eng.encounter].event
		draw_string(font, Vector2(430, 300), str(ev.desc), HORIZONTAL_ALIGNMENT_CENTER, 420, 17, Color(1, 0.9, 0.6))
		draw_string(font, Vector2(430, 330), "(%s check, DC %d) — SPACE to resolve" % [str(ev.ability).to_upper(), int(ev.dc)],
			HORIZONTAL_ALIGNMENT_CENTER, 420, 13, Color(0.75, 0.78, 0.8))
	# active-turn hint
	if _is_player_turn():
		var a := eng.actor_at_ptr()
		draw_string(font, Vector2(430, 250), "%s's turn — click an enemy to attack%s · D defend" % [
			str(a.cls).capitalize(),
			("  ·  H heal  B bless" if str(a.cls) == "cleric" else ("  ·  F fireball" if str(a.cls) == "wizard" else ""))],
			HORIZONTAL_ALIGNMENT_CENTER, 420, 14, Color(1, 1, 0.5))
	# log
	var ln := 0
	for i in range(max(0, eng.log_lines.size() - 6), eng.log_lines.size()):
		draw_string(font, Vector2(24, 512 + ln * 18), str(eng.log_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.72, 0.74, 0.78))
		ln += 1
	draw_string(font, Vector2(24, 636),
		"Click enemy=attack · H heal · F fireball · B bless · D defend · SPACE resolve/continue · A auto · R restart",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.62, 0.66))
	if eng.game_over:
		draw_string(font, Vector2(430, 360), "%s — press R" % ("VICTORY!" if eng.won else "THE PARTY HAS FALLEN"),
			HORIZONTAL_ALIGNMENT_CENTER, 420, 24, Color(1, 0.85, 0.4))

func _draw_actor(font: Font, r: Rect2, title: String, hp: int, mx: int, col: Color, alive: bool, active: bool, sub: String) -> void:
	var bg := Color(0.12, 0.13, 0.16) if alive else Color(0.10, 0.05, 0.05)
	draw_rect(r, bg)
	if active:
		draw_rect(r, Color(1, 1, 0.35), false, 2.5)
	draw_string(font, r.position + Vector2(8, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col if alive else Color(0.5, 0.4, 0.4))
	# hp bar
	var f: float = clampf(float(hp) / float(max(1, mx)), 0.0, 1.0)
	var bar := Rect2(r.position + Vector2(8, 30), Vector2(r.size.x - 16, 8))
	draw_rect(bar, Color(0.2, 0.05, 0.05))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(0.3, 0.85, 0.35) if alive else Color(0.4, 0.2, 0.2))
	draw_string(font, r.position + Vector2(8, r.size.y - 6), "HP %d/%d   %s" % [hp, mx, sub], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.82, 0.85))
