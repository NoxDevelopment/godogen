extends Node2D
## res://scripts/warren.gd
## THE WARREN SCREEN (built entirely in code). Renders GameManager.band — the pure
## WarrenEngine — as a playable survival + migration RPG: a top-down JOURNEY VIEW
## drawn via _draw (the chain of stops from the old warren to the promised down, the
## band's position, danger shaded, the goal marked), a HUD of season / food / morale /
## population / phase, a DECISION BAR (Forage / Scout / Rest / Move On / Shelter /
## Assign Role), and a MEMBERS PANEL listing every named animal with its role + needs.
## All rules live in WarrenEngine; this only paints inputs in and reads state out, so
## the game is fully playable AND headless-testable.

const ORIGIN := Vector2(40, 250)       ## journey strip top-left
const STOP_GAP := 150.0                ## pixels between stops on the strip
const STOP_R := 16.0                   ## stop node radius

## Role marker colours (index == role id).
const ROLE_COLOR: PackedColorArray = [
	Color(0.95, 0.82, 0.40),  # Chief       — gold
	Color(0.45, 0.80, 1.00),  # Scout       — sky
	Color(0.70, 0.60, 1.00),  # Seer        — violet
	Color(0.55, 0.90, 0.55),  # Forager     — green
	Color(1.00, 0.55, 0.45),  # Fighter     — red
	Color(1.00, 0.75, 0.90),  # Storyteller — pink
	Color(0.80, 0.80, 0.85),  # Kit         — pale grey
]

var _title_label: Label
var _hud_label: Label
var _phase_label: Label
var _members_label: Label
var _log_label: Label
var _hint_label: Label
var _status_label: Label
var _action_buttons: Array[Button] = []
var _assign_member := 0                ## which member the Assign button targets (cycles)
var _assign_role := WarrenEngine.FORAGER ## which role the Assign button confers (cycles)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	GameManager.run_reset.connect(_on_reset)
	GameManager.changed.connect(_on_changed)
	_refresh()
	queue_redraw()


func _on_reset() -> void:
	_assign_member = 0
	_refresh()
	queue_redraw()


func _on_changed() -> void:
	_refresh()
	queue_redraw()


# =====================================================================
#  Journey view (drawn)
# =====================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.09, 0.10, 0.08), true)
	var b: WarrenEngine = GameManager.band
	if b == null:
		return
	# The path line.
	var y: float = ORIGIN.y
	var n: int = b.stop_count()
	draw_line(ORIGIN, ORIGIN + Vector2(STOP_GAP * float(n - 1), 0.0), Color(0.35, 0.32, 0.28), 3.0)
	for i in n:
		var s: Dictionary = b.stop_info(i)
		var p: Vector2 = ORIGIN + Vector2(STOP_GAP * float(i), 0.0)
		# Danger shading: safer stops are green, deadlier ones red.
		var danger: float = float(s["danger"])
		var col: Color = Color(0.35, 0.75, 0.40).lerp(Color(0.90, 0.30, 0.28), clampf(danger, 0.0, 1.0))
		if bool(s["goal"]):
			col = Color(0.95, 0.85, 0.45)
		draw_circle(p, STOP_R, col)
		if bool(s["road"]):
			draw_arc(p, STOP_R + 4.0, 0.0, TAU, 20, Color(0.85, 0.5, 0.5), 2.0)  # the Man's road
		# The band's current position ring.
		if i == b.journey_index:
			draw_arc(p, STOP_R + 8.0, 0.0, TAU, 28, Color(0.95, 0.95, 0.6), 3.0)
	# The band token (a little cluster of role dots) at the current stop.
	var here: Vector2 = ORIGIN + Vector2(STOP_GAP * float(b.journey_index), -46.0)
	var mc: int = b.member_count()
	for i in mc:
		var mi: Dictionary = b.member_info(i)
		var col2: Color = ROLE_COLOR[int(mi["role"])]
		var off: Vector2 = Vector2(float(i % 6) * 12.0 - 30.0, float(i / 6) * 12.0)
		draw_circle(here + off, 4.5, col2)


# =====================================================================
#  HUD (built in code)
# =====================================================================

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Backdrop painted in _draw() (root layer 0), behind the world. A full-rect
	# ColorRect in this front CanvasLayer would occlude the whole map.

	_title_label = _mk_label(layer, Vector2(24, 14), 22, Color(0.92, 0.85, 0.55))
	_title_label.text = "WATERSHIP ROAD — lead the band to a new warren, and make it thrive"

	_hud_label = _mk_label(layer, Vector2(24, 48), 16, Color(0.82, 0.92, 0.85))
	_phase_label = _mk_label(layer, Vector2(24, 72), 15, Color(0.85, 0.88, 0.95))
	_status_label = _mk_label(layer, Vector2(24, 96), 16, Color(1.0, 0.9, 0.55))

	# Decision bar.
	var bar := HBoxContainer.new()
	bar.position = Vector2(24, 128)
	bar.add_theme_constant_override("separation", 8)
	bar.add_to_group(&"decision_bar")
	layer.add_child(bar)
	_action_buttons.clear()
	for a in WarrenEngine.ACTION_COUNT:
		var btn := Button.new()
		btn.text = WarrenEngine.ACTION_NAME[a]
		btn.add_to_group(&"scalable_text")
		btn.pressed.connect(_on_action.bind(a))
		bar.add_child(btn)
		_action_buttons.append(btn)

	_hint_label = _mk_label(layer, Vector2(24, 168), 12, Color(0.68, 0.72, 0.66))
	_hint_label.text = "Forage food · Scout the road · Rest for morale · Move on toward the down · Shelter · Assign a role · Esc pause · R restart"

	# Members panel (right column).
	_members_label = _mk_label(layer, Vector2(700, 48), 13, Color(0.86, 0.88, 0.82))
	_members_label.text = ""

	_log_label = _mk_label(layer, Vector2(40, 470), 13, Color(0.74, 0.80, 0.72))
	_log_label.text = "The band sets out…"


func _on_action(action: int) -> void:
	var b: WarrenEngine = GameManager.band
	if b == null:
		return
	if action == WarrenEngine.ACT_ASSIGN:
		# Cycle the target member (skipping kits) and confer the next adult role.
		_cycle_assign_target()
		GameManager.decide(WarrenEngine.ACT_ASSIGN, _assign_member, _assign_role)
	else:
		GameManager.decide(action)
	_refresh()
	queue_redraw()


func _cycle_assign_target() -> void:
	var b: WarrenEngine = GameManager.band
	if b == null or b.member_count() == 0:
		return
	# Find the next adult member to reassign.
	var count: int = b.member_count()
	for step in count:
		_assign_member = (_assign_member + 1) % count
		var mi: Dictionary = b.member_info(_assign_member)
		if not bool(mi["adult"]):
			continue
		# Confer a role different from the member's current one.
		var cur: int = int(mi["role"])
		_assign_role = WarrenEngine.FORAGER if cur != WarrenEngine.FORAGER else WarrenEngine.FIGHTER
		return


## Public helper the UI probe calls: apply a decision immediately and repaint, so a
## headless test can assert the state changed and the view updated.
func debug_decide(action: int, arg0: int = -1, arg1: int = -1) -> bool:
	var ok: bool = GameManager.decide(action, arg0, arg1)
	_refresh()
	queue_redraw()
	return ok


func _refresh() -> void:
	var b: WarrenEngine = GameManager.band
	if b == null:
		return
	_hud_label.text = "%s, Year %d, Day %d   ·   Food %d   ·   Morale %d   ·   Pop %d (adults %d, kits %d)" % [
		b.season_name(), b.year() + 1, b.day, b.food_stock,
		int(round(b.morale)), b.member_count(), b.adult_count(), b.kit_count()]
	_phase_label.text = "Phase: %s   ·   At: %s   ·   Toward: %s   ·   Cohesion %d%%" % [
		b.phase_name(), b.current_stop_name(),
		String(b.stop_info(b.next_stop_index())["name"]),
		int(round(b.cohesion() * 100.0))]
	var status: String = ""
	if b.is_win():
		status = "A THRIVING WARREN — YOU WIN"
	elif b.is_loss():
		status = "THE ROAD ENDS — %s" % b.loss_reason
	elif b.arrived:
		status = "Founded — grow to %d to win" % b.target_pop()
	else:
		status = "On the road — reach the down before day %d" % WarrenEngine.DEADLINE_DAYS
	_status_label.text = status
	_refresh_members(b)
	_log_label.text = "\n".join(b.recent_log(6))
	for a in _action_buttons.size():
		_action_buttons[a].disabled = b.game_over


func _refresh_members(b: WarrenEngine) -> void:
	var lines: Array[String] = ["THE BAND"]
	for i in b.member_count():
		var mi: Dictionary = b.member_info(i)
		var sex: String = "F" if int(mi["sex"]) == WarrenEngine.FEMALE else "M"
		lines.append("%s (%s, %s)  hp %d  hunger %d  fatigue %d" % [
			String(mi["name"]), String(mi["role_name"]), sex,
			int(mi["hp"]), int(mi["hunger"]), int(mi["fatigue"])])
	_members_label.text = "\n".join(lines)


func _log(text: String) -> void:
	if _log_label:
		_log_label.text = text


func _mk_label(parent: Node, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_to_group(&"scalable_text")
	parent.add_child(l)
	return l


# =====================================================================
#  Input
# =====================================================================

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"restart"):
		GameManager.new_run(0)
		return
	if e.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
		return
