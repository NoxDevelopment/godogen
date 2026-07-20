class_name FFDie
extends Control
## res://scripts/screens/die_face.gd
## A single honest d6 face drawn with real pips (STYLE_GUIDE / WIREFRAMES 5.3
## "honest pips" — never a fudged number). Reused by the Dice-Roll Overlay and the
## Character-creation roll-up. Set `value` (1-6) and it redraws; `pip_color` tints
## the pips for crit/lucky/unlucky feedback. Pure presentation — it holds no RNG;
## the value it shows is whatever the seeded rules core already rolled.

@export var value: int = 6: set = set_value
@export var pip_color: Color = FFUI.INK: set = set_pip_color
@export var body_color: Color = Color("efe7d2")   # bone / tallow die body
@export var edge_color: Color = FFUI.UMBER

const _PIPS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.28, 0.28), Vector2(0.72, 0.72)],
	3: [Vector2(0.28, 0.28), Vector2(0.5, 0.5), Vector2(0.72, 0.72)],
	4: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
	5: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.5, 0.5), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
	6: [Vector2(0.28, 0.26), Vector2(0.72, 0.26), Vector2(0.28, 0.5), Vector2(0.72, 0.5), Vector2(0.28, 0.74), Vector2(0.72, 0.74)],
}


func _init() -> void:
	custom_minimum_size = Vector2(64, 64)


func set_value(v: int) -> void:
	value = clampi(v, 1, 6)
	queue_redraw()


func set_pip_color(c: Color) -> void:
	pip_color = c
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	var r := Rect2(Vector2.ZERO, s)
	var radius := s.x * 0.16
	# body + edge (soft shadow feel via a slightly offset darker rect)
	draw_rect(Rect2(Vector2(2, 3), s), Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.18), true)
	_rounded(r, radius, body_color, true)
	_rounded(r, radius, edge_color, false, maxf(s.x * 0.03, 2.0))
	var pip_r := s.x * 0.085
	for p: Vector2 in _PIPS.get(value, []):
		draw_circle(Vector2(p.x * s.x, p.y * s.y), pip_r, pip_color)


func _rounded(rect: Rect2, radius: float, color: Color, filled: bool, width: float = 1.0) -> void:
	# A rounded rectangle via a StyleBoxFlat draw (crisp corners, no manual arcs).
	var sb := StyleBoxFlat.new()
	if filled:
		sb.bg_color = color
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(int(width))
		sb.border_color = color
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)
