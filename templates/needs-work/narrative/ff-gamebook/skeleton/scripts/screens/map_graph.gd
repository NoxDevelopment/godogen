class_name FFMapGraph
extends Control
## res://scripts/screens/map_graph.gd
## The passage-graph auto-map canvas (WIREFRAMES 5.8). Pure presentation: it draws
## the visited sections as nodes and their branch edges — current (filled
## verdigris), visited (parchment), unvisited branch (outline), death-seen (arrears
## cross). Layout is computed by the caller (map_view) from GameState.passage_history
## + Section.choices[].target; this node just renders it with the reused book font.

var nodes: Array[Dictionary] = []     # {id, pos:Vector2, kind, label}
var edges: Array = []                 # [ [from_id, to_id], ... ]
var _index: Dictionary = {}


func build(node_list: Array, edge_list: Array) -> void:
	nodes.assign(node_list)
	edges = edge_list
	_index.clear()
	var maxx := 200.0
	var maxy := 200.0
	for n in nodes:
		_index[str(n.id)] = n
		maxx = maxf(maxx, (n.pos as Vector2).x + 90.0)
		maxy = maxf(maxy, (n.pos as Vector2).y + 70.0)
	custom_minimum_size = Vector2(maxx, maxy)
	queue_redraw()


func _draw() -> void:
	# edges first (behind nodes)
	for e in edges:
		var a: Dictionary = _index.get(str(e[0]), {})
		var b: Dictionary = _index.get(str(e[1]), {})
		if a.is_empty() or b.is_empty():
			continue
		var pa: Vector2 = a.pos
		var pb: Vector2 = b.pos
		draw_line(pa, pb, Color(FFUI.UMBER.r, FFUI.UMBER.g, FFUI.UMBER.b, 0.7), 2.0, true)
	# nodes
	var font := FFUI.font_body()
	for n in nodes:
		var pos: Vector2 = n.pos
		var kind := str(n.kind)
		var r := 22.0
		var fill := FFUI.PARCHMENT_2
		var ring := FFUI.UMBER
		match kind:
			"current":
				fill = FFUI.VERDIGRIS; ring = FFUI.INK; r = 26.0
			"visited":
				fill = FFUI.PARCHMENT_2; ring = FFUI.UMBER
			"branch":
				fill = Color(FFUI.PARCHMENT_2.r, FFUI.PARCHMENT_2.g, FFUI.PARCHMENT_2.b, 0.35); ring = FFUI.FEN
			"death":
				fill = Color(FFUI.ARREARS.r, FFUI.ARREARS.g, FFUI.ARREARS.b, 0.85); ring = FFUI.INK
		draw_circle(pos, r + 2.0, Color(FFUI.INK.r, FFUI.INK.g, FFUI.INK.b, 0.18))
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0, TAU, 32, ring, 2.5, true)
		if kind == "death" and font != null:
			draw_string(font, pos + Vector2(-6, 6), "✝", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, FFUI.PARCHMENT)
		if font != null:
			var lbl := str(n.label)
			var tcol: Color = FFUI.PARCHMENT if kind == "current" else FFUI.INK
			draw_string(font, pos + Vector2(-r + 4, 5), lbl, HORIZONTAL_ALIGNMENT_LEFT, r * 2 - 8, 15, tcol)
