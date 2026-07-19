extends CanvasLayer
## res://scripts/screens/map_view.gd
## Map / Progress (WIREFRAMES 5.8, GDD §6.1 #10) — the faithful passage-graph
## auto-map. Nodes are the sections the hero has visited (from
## GameState.passage_history); edges are the branches out of them
## (Section.choices[].target). Current is highlighted; unvisited branch targets show
## as outlines; a death-terminal seen shows a cross. View-only in faithful mode (a
## Graph|Travel toggle is present; travel-as-movement is a COULD, GDD §13). A text
## list alternative is provided for screen-reader/keyboard users. Esc / ✕ closes.

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
	dim.color = Color(0.02, 0.03, 0.03, 0.55)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := FFUI.framed_panel(FFUI.UMBER)
	panel.custom_minimum_size = Vector2(760, 560)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 8)
	panel.add_child(outer)

	var head := HBoxContainer.new()
	var t := FFUI.title("MAP  ·  THE VERGE OF HARROW", 22, FFUI.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var graph_btn := FFUI.chip("Graph")
	var travel_btn := FFUI.chip("Travel")
	travel_btn.pressed.connect(func() -> void: _toast("Travel-map mode is a COULD (GDD §13) — not enabled for this book."))
	head.add_child(graph_btn)
	head.add_child(travel_btn)
	var x := FFUI.chip("✕"); x.pressed.connect(_close); head.add_child(x)
	outer.add_child(head)
	outer.add_child(FFUI.divider_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	_graph = FFMapGraph.new()
	scroll.add_child(_graph)
	outer.add_child(scroll)

	outer.add_child(FFUI.label("Legend:   ● you    ○ visited    ◌ branch    ✝ death", 14, FFUI.UMBER))
	_list = FFUI.rich(14, FFUI.UMBER)
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

	# node set: visited + their direct branch targets
	var node_ids := {}
	for p in visited_order:
		node_ids[p] = true
	var edges: Array = []
	for p in visited_order:
		var passage: Dictionary = scen.passages.get(p, {})
		for ch in passage.get("choices", []):
			var g := str(ch.get("goto", ""))
			if g == "" or str(ch.get("id", "")).begins_with("_"):
				# skip engine-consumed outcome choices from the player-facing map,
				# but still surface their destinations as branch nodes
				if g != "":
					node_ids[g] = true
					edges.append([p, g])
				continue
			node_ids[g] = true
			edges.append([p, g])

	# layer nodes by BFS depth over the full graph from start
	var depth := _bfs_depth(scen, scen.start, node_ids)
	var by_depth := {}
	for id in node_ids.keys():
		var d := int(depth.get(id, 0))
		if not by_depth.has(d):
			by_depth[d] = []
		by_depth[d].append(id)

	var nodes: Array[Dictionary] = []
	var col_w := 150.0
	var row_h := 74.0
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
			if passage.get("ending", {}).get("kind", "") == "death":
				kind = "death"
			nodes.append({
				"id": id,
				"pos": Vector2(60 + d * col_w, 48 + i * row_h),
				"kind": kind,
				"label": id,
			})
	_graph.build(nodes, edges)

	# text-list alternative
	var line := "[b]Visited:[/b] "
	for p in visited_order:
		line += ("[u]%s (current)[/u]  " % p) if p == current else ("%s  " % p)
	_list.text = line


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


func _toast(msg: String) -> void:
	var t := FFUI.label(msg, 14, FFUI.FLAME)
	t.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	add_child(t)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(t):
		t.queue_free()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
