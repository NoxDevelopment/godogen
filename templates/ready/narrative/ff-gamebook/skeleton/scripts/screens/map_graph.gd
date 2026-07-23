class_name FFMapGraph
extends Control
## res://scripts/screens/map_graph.gd
## The JOURNEY MAP canvas (LOOKFEEL_PASS_2026-07 §map — the Sorcery! travel-map
## idiom, STYLE_GUIDE §1.8 `sorcery-inkle` lane). Pure presentation over data the
## map_view computes; nothing here mutates game state.
##
## TWO SURFACES, one renderer:
##   * BOOK-MAP mode — the adventure ships a hand-drawn map plate (slot
##     "plate/map") + normalized node coordinates in book.json. The plate is the
##     ground; the traveled route is inked across it as a dashed line, visited
##     locations are ink rings with their section titles hand-lettered on small
##     parchment tags, unvisited mapped places are faint sketch marks, and the
##     party is a red WAX SEAL marker at the current location (Sorcery!'s
##     miniature-on-the-map read).
##   * AUTO-CHART mode — books without a plate get "the hero's own drawn chart":
##     the visited passage graph laid out on the paper, curved dashed ink edges,
##     the same ring/wax/cross vocabulary.
##
## Node kinds: current / visited / branch (seen-but-unvisited) / death.

var nodes: Array[Dictionary] = []     # {id, pos:Vector2 (px), kind, label}
var edges: Array = []                 # [ [from_id, to_id], ... ] (drawn as travel ink)
var route: Array = []                 # ordered ids of the traveled path (dashed route)
var plate: Texture2D = null           # book map plate (null = auto-chart)
var _index: Dictionary = {}


## Build in AUTO-CHART pixel space (map_view computed positions).
func build(node_list: Array, edge_list: Array, route_list: Array = []) -> void:
	plate = null
	nodes.assign(node_list)
	edges = edge_list
	route = route_list
	_reindex()
	var maxx := 240.0
	var maxy := 240.0
	for n in nodes:
		maxx = maxf(maxx, (n.pos as Vector2).x + 120.0)
		maxy = maxf(maxy, (n.pos as Vector2).y + 80.0)
	custom_minimum_size = Vector2(maxx, maxy)
	queue_redraw()


## Build in BOOK-MAP normalized space: node pos are 0..1 over the plate.
func build_on_plate(p_plate: Texture2D, node_list: Array, route_list: Array) -> void:
	plate = p_plate
	nodes.assign(node_list)
	edges = []
	route = route_list
	_reindex()
	queue_redraw()


func _reindex() -> void:
	_index.clear()
	for n in nodes:
		_index[str(n.id)] = n


## The rect the plate occupies (aspect-fit inside the control).
func _plate_rect() -> Rect2:
	if plate == null:
		return Rect2(Vector2.ZERO, size)
	var ts := plate.get_size()
	var s := minf(size.x / ts.x, size.y / ts.y)
	var draw_size := ts * s
	return Rect2((size - draw_size) * 0.5, draw_size)


func _node_px(n: Dictionary) -> Vector2:
	var p: Vector2 = n.pos
	if plate == null:
		return p
	var r := _plate_rect()
	return r.position + Vector2(p.x * r.size.x, p.y * r.size.y)


func _draw() -> void:
	if plate != null:
		var r := _plate_rect()
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.25), true)
		draw_texture_rect(plate, r, false)
		# a thin printed rule around the plate
		draw_rect(r, Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.8), false, 1.6)

	# --- the traveled ROUTE: a dashed ink line stitched node-to-node, laid on a
	# pale halo so it stays legible over busy watercolor terrain ---------------
	var ink := Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.85)
	var halo := Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.55)
	for i in range(1, route.size()):
		var a: Dictionary = _index.get(str(route[i - 1]), {})
		var b: Dictionary = _index.get(str(route[i]), {})
		if a.is_empty() or b.is_empty():
			continue
		_dashed_curve(_node_px(a), _node_px(b), halo, 7.0, 6.0, 5.5)
		_dashed_curve(_node_px(a), _node_px(b), ink, 7.0, 6.0, 2.4)

	# auto-chart: also sketch the seen-but-untraveled branches faintly
	if plate == null:
		for e in edges:
			var a2: Dictionary = _index.get(str(e[0]), {})
			var b2: Dictionary = _index.get(str(e[1]), {})
			if a2.is_empty() or b2.is_empty():
				continue
			_dashed_curve(_node_px(a2), _node_px(b2),
				Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.30), 4.0, 7.0, 1.2)

	# --- nodes ---------------------------------------------------------------
	for n in nodes:
		_draw_node(n)


## A hand-wavering dashed line: a slight quadratic bow + dash pattern, so the
## route reads inked by hand, not plotted by a computer.
func _dashed_curve(a: Vector2, b: Vector2, col: Color, dash: float = 7.0, gap: float = 6.0, width: float = 2.2) -> void:
	var mid := (a + b) * 0.5
	var dir := (b - a)
	var n := Vector2(-dir.y, dir.x).normalized()
	# deterministic bow from the endpoints (stable across frames)
	var bow := float((int(a.x * 13.0 + b.y * 7.0) % 17) - 8) * 1.2
	var c := mid + n * bow
	var steps := maxi(int(dir.length() / 6.0), 6)
	var pts: Array[Vector2] = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))   # quadratic bezier
	var carry := 0.0
	var pen_down := true
	for i in range(1, pts.size()):
		var seg_a := pts[i - 1]
		var seg_b := pts[i]
		var seg_len := seg_a.distance_to(seg_b)
		var pos := 0.0
		while pos < seg_len:
			var span := (dash if pen_down else gap) - carry
			var step := minf(span, seg_len - pos)
			if pen_down:
				var p0 := seg_a.lerp(seg_b, pos / seg_len)
				var p1 := seg_a.lerp(seg_b, minf((pos + step) / seg_len, 1.0))
				draw_line(p0, p1, col, width, true)
			pos += step
			carry += step
			if carry >= (dash if pen_down else gap) - 0.01:
				carry = 0.0
				pen_down = not pen_down


func _draw_node(n: Dictionary) -> void:
	var pos := _node_px(n)
	var kind := str(n.kind)
	var font := FFUI.font_display_tracked(1)
	match kind:
		"current":
			_wax_marker(pos)
		"visited":
			draw_circle(pos, 7.0, Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.85))
			draw_arc(pos, 7.0, 0, TAU, 24, Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.9), 2.2, true)
			draw_circle(pos, 2.2, Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.9))
		"branch":
			# a faint sketched mark — somewhere heard of, not yet walked
			draw_arc(pos, 6.0, 0.4, TAU - 0.5, 18, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.45), 1.4, true)
		"death":
			var red := Color(FFUI.ARREARS.r, FFUI.ARREARS.g, FFUI.ARREARS.b, 0.9)
			draw_line(pos + Vector2(-6, -6), pos + Vector2(6, 6), red, 2.6)
			draw_line(pos + Vector2(6, -6), pos + Vector2(-6, 6), red, 2.6)
	# the place name on a small parchment tag (visited + current only — the map
	# keeps its secrets for places not yet walked)
	if kind == "current" or kind == "visited":
		var lbl := str(n.label)
		if lbl == "":
			return
		var fs := 12
		var sz := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var tag_pos := pos + Vector2(-sz.x * 0.5, 13.0)
		# keep tags on the sheet
		tag_pos.x = clampf(tag_pos.x, 4.0, size.x - sz.x - 4.0)
		var pad := Vector2(5, 3)
		var tag := Rect2(tag_pos - Vector2(pad.x, fs + pad.y - 2), sz + pad * 2)
		draw_rect(tag, Color(FFUI.PARCHMENT.r, FFUI.PARCHMENT.g, FFUI.PARCHMENT.b, 0.82), true)
		draw_rect(tag, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.5), false, 1.0)
		font.draw_string(get_canvas_item(), tag_pos + Vector2(0, -1), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.95))


## The party: a red wax seal pressed onto the map (Sorcery!'s figure, our idiom).
func _wax_marker(pos: Vector2) -> void:
	draw_circle(pos + Vector2(1.5, 2.0), 11.0, Color(0, 0, 0, 0.30))
	var wax := FFUI.ARREARS
	draw_circle(pos, 10.5, wax)
	# irregular wax lip
	for i in 7:
		var ang := TAU * float(i) / 7.0 + 0.4
		draw_circle(pos + Vector2(cos(ang), sin(ang)) * 9.0, 3.0, wax)
	draw_circle(pos, 6.5, wax.darkened(0.18))
	draw_arc(pos, 6.5, 0, TAU, 20, wax.lightened(0.15), 1.2, true)
	draw_circle(pos + Vector2(-3.0, -3.5), 1.8, Color(1, 1, 1, 0.28))
