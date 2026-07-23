extends CanvasLayer
## res://scripts/screens/map_view.gd
## THE JOURNEY (LOOKFEEL_PASS_2026-07 §map — Sorcery!'s living travel map;
## WIREFRAMES 5.8; STYLE_GUIDE §1.8 `sorcery-inkle` lane). A full-page map sheet:
## when the active BOOK ships a hand-drawn map plate (slot "plate/map" + node
## coordinates in book.json) the party's journey is inked across that map — the
## traveled route dashed section-to-section, visited places ring-marked with
## their titles, the party a red wax seal at the current section. Books without
## a plate fall back to "the hero's own chart": the visited passage graph drawn
## on parchment in the same ink vocabulary. View-only in faithful mode; a text
## list alternative is kept for screen-reader/keyboard users. Esc / ✕ closes.

signal closed

var _graph: FFMapGraph
var _list: RichTextLabel


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_populate()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.66)
	add_child(dim)
	var panel := FFUI.framed_panel(FFUI.UMBER)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 34
	panel.offset_right = -34
	panel.offset_top = 22
	panel.offset_bottom = -22
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 6)
	panel.add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	var t := FFUI.title("THE JOURNEY  ·  %s" % Adventure.book_title().to_upper(), 22, FFUI.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := FFUI.chip("✕")
	x.pressed.connect(_close)
	head.add_child(x)
	outer.add_child(head)
	outer.add_child(FFUI.diamond_rule(FFUI.VERDIGRIS))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph = FFMapGraph.new()
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_graph)
	outer.add_child(scroll)

	var legend := FFUI.label("●  the party      ○  walked      ◌  heard of      ✕  a death seen", 13, FFUI.UMBER)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(legend)
	_list = FFUI.rich(13, FFUI.UMBER)
	outer.add_child(_list)


func _populate() -> void:
	var st := Adventure.runner.state if Adventure.runner != null else null
	var scen := Adventure.scenario
	if st == null or scen == null:
		return
	var history: Array = st.passage_history
	var current := st.current_passage

	# unique visited, in first-visit order
	var visited_order: Array[String] = []
	var visited := {}
	for pid in history:
		var p := str(pid)
		if not visited.has(p):
			visited[p] = true
			visited_order.append(p)

	var book_map: Dictionary = Adventure.book().get("map", {})
	var coords: Dictionary = book_map.get("nodes", {}) if book_map.get("nodes", {}) is Dictionary else {}
	var plate_tex: Texture2D = null
	if not coords.is_empty():
		plate_tex = AssetBinder.get_texture(str(book_map.get("plate", "plate/map")))

	if plate_tex != null:
		_populate_book_map(scen, coords, plate_tex, visited_order, visited, current, history)
	else:
		_populate_auto_chart(scen, visited_order, visited, current)

	# text-list alternative (both modes)
	var line := "[b]Walked:[/b] "
	for p in visited_order:
		var title := _title_of(scen, p)
		line += ("[u]%s (here)[/u]  ·  " % title) if p == current else ("%s  ·  " % title)
	_list.text = line.trim_suffix("  ·  ")


## BOOK-MAP mode: project the walk onto the book's hand-drawn plate. Sections
## without a coordinate (interstitial beats) snap to their nearest mapped
## ancestor in the walk, so the route and the wax seal always sit on the map.
func _populate_book_map(scen: IFScenario, coords: Dictionary, plate_tex: Texture2D,
		visited_order: Array[String], visited: Dictionary, current: String, history: Array) -> void:
	# the traveled route, collapsed to mapped nodes (deduped consecutive repeats)
	var route: Array = []
	for pid in history:
		var m := _mapped_id(str(pid), coords, history)
		if m != "" and (route.is_empty() or route.back() != m):
			route.append(m)
	var cur_mapped := _mapped_id(current, coords, history)

	var nodes: Array[Dictionary] = []
	for id in coords.keys():
		var sid := str(id)
		var c: Array = coords[sid]
		if c.size() < 2:
			continue
		var kind := "branch"
		if sid == cur_mapped:
			kind = "current"
		elif visited.has(sid):
			kind = "visited"
		var passage: Dictionary = scen.passages.get(sid, {})
		if passage.get("ending", {}).get("kind", "") == "death" and visited.has(sid):
			kind = "death"
		nodes.append({
			"id": sid,
			"pos": Vector2(float(c[0]), float(c[1])),
			"kind": kind,
			"label": _title_of(scen, sid) if (visited.has(sid) or sid == cur_mapped) else "",
		})
	_graph.build_on_plate(plate_tex, nodes, route)


## The last mapped section at-or-before `pid` in the walk ("" if none yet).
func _mapped_id(pid: String, coords: Dictionary, history: Array) -> String:
	if coords.has(pid):
		return pid
	var at := history.rfind(pid)
	if at < 0:
		at = history.size() - 1
	for i in range(at, -1, -1):
		if coords.has(str(history[i])):
			return str(history[i])
	return ""


## AUTO-CHART mode (books without a plate): the visited graph, laid out by BFS
## depth with a deterministic hand-drawn stagger, titles on the walked nodes.
func _populate_auto_chart(scen: IFScenario, visited_order: Array[String], visited: Dictionary, current: String) -> void:
	var node_ids := {}
	for p in visited_order:
		node_ids[p] = true
	var edges: Array = []
	for p in visited_order:
		var passage: Dictionary = scen.passages.get(p, {})
		for ch in passage.get("choices", []):
			var g := str(ch.get("goto", ""))
			if g == "":
				continue
			node_ids[g] = true
			edges.append([p, g])

	var depth := _bfs_depth(scen, scen.start, node_ids)
	var by_depth := {}
	for id in node_ids.keys():
		var d := int(depth.get(id, 0))
		if not by_depth.has(d):
			by_depth[d] = []
		by_depth[d].append(id)

	var nodes: Array[Dictionary] = []
	var col_w := 190.0
	var row_h := 92.0
	var depths := by_depth.keys()
	depths.sort()
	for d in depths:
		var col: Array = by_depth[d]
		col.sort()
		for i in col.size():
			var id := str(col[i])
			var kind := "branch"
			if id == current:
				kind = "current"
			elif visited.has(id):
				kind = "visited"
			var passage: Dictionary = scen.passages.get(id, {})
			if passage.get("ending", {}).get("kind", "") == "death" and visited.has(id):
				kind = "death"
			# deterministic hand-drawn stagger so the chart doesn't grid up
			var jx := float((hash(id) % 23) - 11) * 1.6
			var jy := float((hash(id + "y") % 19) - 9) * 1.8
			nodes.append({
				"id": id,
				"pos": Vector2(90 + d * col_w + jx, 64 + i * row_h + jy),
				"kind": kind,
				"label": _title_of(scen, id) if (visited.has(id) or id == current) else "",
			})
	# the walked route in visit order
	var route: Array = []
	for p in visited_order:
		route.append(p)
	_graph.build(nodes, edges, route)


func _title_of(scen: IFScenario, id: String) -> String:
	var passage: Dictionary = scen.passages.get(id, {})
	var t := str(passage.get("title", ""))
	return t if t != "" else id


func _bfs_depth(scen: IFScenario, start: String, allowed: Dictionary) -> Dictionary:
	var depth := {}
	if start == "" or not scen.has_passage(start):
		return depth
	var queue: Array = [start]
	depth[start] = 0
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var passage: Dictionary = scen.passages.get(cur, {})
		for ch in passage.get("choices", []):
			var g := str(ch.get("goto", ""))
			if g != "" and not depth.has(g):
				depth[g] = int(depth[cur]) + 1
				queue.append(g)
	return depth


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
